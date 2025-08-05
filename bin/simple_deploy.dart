import 'dart:io';

import 'package:args/args.dart';
import 'package:simple_deploy/src/common.dart';
import 'package:simple_deploy/src/deploy_android.dart' as android;
import 'package:simple_deploy/src/deploy_ios.dart' as ios;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

bool checkDeployFile() {
  final workingDirectory = Directory.current.path;
  final configFile = File('$workingDirectory/deploy.yaml');
  return configFile.existsSync();
}

void main(List<String> arguments) async {
  if (!checkDeployFile()) {
    print('Error: deploy.yaml file not found in the root of the project.');
    return;
  }

  final parser = ArgParser()
    ..addOption('flavor', abbr: 'f', help: 'The product flavor to build.')
    ..addFlag('pubspecIncrement', help: 'Increment the build number in pubspec.yaml before building.')
    ..addFlag('submit-review', help: 'Submit the build for review (App Store for iOS, specific track for Android).')
    ..addFlag('ios-release-after-review', help: 'iOS: Release the app automatically after App Store review approval.', defaultsTo: null)
    ..addOption('ios-release-type', help: 'iOS: Release type (MANUAL, AFTER_APPROVAL, SCHEDULED).')
    ..addOption('ios-scheduled-release-date', help: 'iOS: Scheduled release date (ISO 8601 format, e.g., YYYY-MM-DDTHH:MM:SS.sssZ).');

  final argResults = parser.parse(arguments);

  String? flavorCmd = argResults['flavor'] as String?;
  bool shouldIncrementVersionCmd = argResults['pubspecIncrement'] as bool;
  bool shouldSubmitReviewCmd = argResults['submit-review'] as bool;

  bool? iosReleaseAfterReviewCmd = argResults['ios-release-after-review'] as bool?;
  String? iosReleaseTypeCmd = argResults['ios-release-type'] as String?;
  String? iosScheduledReleaseDateCmd = argResults['ios-scheduled-release-date'] as String?;

  if (argResults.rest.isEmpty) {
    await promptAndDeploy(
      flavor: flavorCmd,
      shouldIncrementVersion: shouldIncrementVersionCmd,
      shouldSubmitReview: shouldSubmitReviewCmd,
      iosReleaseAfterReviewArg: iosReleaseAfterReviewCmd,
      iosReleaseTypeArg: iosReleaseTypeCmd,
      iosScheduledReleaseDateArg: iosScheduledReleaseDateCmd
    );
  } else {
    String target = argResults.rest[0].toLowerCase();
    if (target == 'ios') {
      if (Platform.isMacOS) {
        await deployIos(
          flavor: flavorCmd,
          shouldIncrementVersion: shouldIncrementVersionCmd,
          shouldSubmitReview: shouldSubmitReviewCmd,
          releaseAfterReviewArg: iosReleaseAfterReviewCmd,
          releaseTypeArg: iosReleaseTypeCmd,
          scheduledReleaseDateArg: iosScheduledReleaseDateCmd
          // skipClean defaults to false here, which is appropriate
        );
      } else {
        print('Error: You can only deploy to iOS from MacOS.');
      }
    } else if (target == 'android') {
      await deployAndroid(
        flavor: flavorCmd,
        shouldIncrementVersion: shouldIncrementVersionCmd
        // Android review submission is simpler for now, shouldSubmitReviewCmd could be passed if needed
      );
    } else {
      print('Invalid argument. Please pass "ios" or "android".');
      print(parser.usage);
    }
  }
}

Future<void> promptAndDeploy({
  String? flavor,
  required bool shouldIncrementVersion,
  required bool shouldSubmitReview,
  required bool? iosReleaseAfterReviewArg,
  required String? iosReleaseTypeArg,
  required String? iosScheduledReleaseDateArg
}) async {
  if (Platform.isMacOS) {
    print('Choose deployment target:');
    print('1. Android');
    print('2. iOS');
    print('a. All platforms');
    print('q. Quit');
  } else {
    print('Automatically selecting Android build and deploy');
  }

  String? choice = Platform.isMacOS ? stdin.readLineSync() : '1';

  if (choice == '1') {
    await deployAndroid(flavor: flavor, shouldIncrementVersion: shouldIncrementVersion);
  } else if (choice == '2') {
    await deployIos(
      flavor: flavor,
      shouldIncrementVersion: shouldIncrementVersion,
      shouldSubmitReview: shouldSubmitReview,
      releaseAfterReviewArg: iosReleaseAfterReviewArg,
      releaseTypeArg: iosReleaseTypeArg,
      scheduledReleaseDateArg: iosScheduledReleaseDateArg
    );
  } else if (choice == 'a') {
    await deployAll(
      flavor: flavor,
      shouldIncrementVersion: shouldIncrementVersion,
      shouldSubmitReview: shouldSubmitReview,
      iosReleaseAfterReviewArg: iosReleaseAfterReviewArg,
      iosReleaseTypeArg: iosReleaseTypeArg,
      iosScheduledReleaseDateArg: iosScheduledReleaseDateArg
    );
  } else if (choice == 'q') {
    print('Quitting deployment.');
  } else {
    print(Platform.isMacOS
        ? 'Invalid choice. Please enter 1, 2, a, or q.'
        : 'Invalid choice. Please enter 1.');
  }
}

Future<void> deployIos({
  String? flavor,
  bool shouldIncrementVersion = false,
  bool shouldSubmitReview = false,
  bool? releaseAfterReviewArg,
  String? releaseTypeArg,
  String? scheduledReleaseDateArg,
  bool skipClean = false // Now a named parameter, defaults to false
}) async {
  final workingDirectory = Directory.current.path;
  final versionStrategy = await handleVersionStrategy(workingDirectory, shouldIncrementVersion);
  final iosConfig = await loadConfig(workingDirectory, 'ios');

  bool releaseAfterReview = releaseAfterReviewArg ?? (iosConfig?['releaseAfterReview'] as bool? ?? false);
  String? releaseType = releaseTypeArg ?? iosConfig?['releaseType'] as String?;
  String? scheduledReleaseDate = scheduledReleaseDateArg ?? iosConfig?['scheduledReleaseDate'] as String?;

  print('Deploying to iOS...');
  await ios.deploy(
    flavor: flavor,
    useStoreIncrement: versionStrategy == 'storeIncrement',
    submitToReview: shouldSubmitReview,
    skipClean: skipClean, // Correctly passed
    releaseAfterReview: releaseAfterReview,
    releaseType: releaseType,
    scheduledReleaseDate: scheduledReleaseDate
  );
}

Future<void> deployAndroid({
  String? flavor,
  bool shouldIncrementVersion = false
}) async {
  final workingDirectory = Directory.current.path;
  final versionStrategy = await handleVersionStrategy(workingDirectory, shouldIncrementVersion);
  print('Deploying to Android...');
  await android.deploy(
    flavor: flavor,
    useStoreIncrement: versionStrategy == 'storeIncrement'
  );
}

Future<void> deployAll({
  String? flavor,
  required bool shouldIncrementVersion,
  required bool shouldSubmitReview,
  required bool? iosReleaseAfterReviewArg,
  required String? iosReleaseTypeArg,
  required String? iosScheduledReleaseDateArg
}) async {
  final workingDirectory = Directory.current.path;
  // Version strategy handled once for all based on shouldIncrementVersion flag
  await handleVersionStrategy(workingDirectory, shouldIncrementVersion);
  print('Deploying to all platforms...');

  bool success = await flutterClean(workingDirectory);
  if (!success) {
    print('Failed to clean project');
    return;
  }

  // For deployAll, shouldIncrementVersion is now effectively false for these calls
  // as it was handled by the global handleVersionStrategy above.
  await deployAndroid(flavor: flavor, shouldIncrementVersion: false);

  if (Platform.isMacOS) {
    await deployIos(
      flavor: flavor,
      shouldIncrementVersion: false, // Handled globally
      shouldSubmitReview: shouldSubmitReview,
      releaseAfterReviewArg: iosReleaseAfterReviewArg,
      releaseTypeArg: iosReleaseTypeArg,
      scheduledReleaseDateArg: iosScheduledReleaseDateArg,
      skipClean: true // Already cleaned globally
    );
  } else {
    print('iOS deployment is only available on MacOS.');
  }
}

Future<String> handleVersionStrategy(String workingDirectory, [bool cmdLineIncrement = false]) async {
  String versionStrategy = 'none'; // Default
  try {
    final config = await loadConfig(workingDirectory, 'common');
    versionStrategy = config?['versionStrategy'] as String? ?? 'none';
  } catch (e) {
    print('Warning: Could not load common config for versionStrategy: $e');
  }

  if (cmdLineIncrement) {
    versionStrategy = 'pubspecIncrement';
  }

  print('Version strategy: $versionStrategy');

  if (versionStrategy == 'pubspecIncrement') {
    await incrementBuildNumber(workingDirectory);
  } else if (versionStrategy == 'storeIncrement') {
    print('Using store increment strategy - will get latest version from store (handled by platform-specific deploy).');
  } else if (versionStrategy == 'none') {
    // Do nothing
  } else {
    print('Error: Invalid versionStrategy "$versionStrategy". Valid values are `none`, `pubspecIncrement`, and `storeIncrement`.');
    exit(1);
  }
  return versionStrategy;
}

Future<void> incrementBuildNumber(String workingDirectory) async {
  final pubspecFile = File('$workingDirectory/pubspec.yaml');
  if (!await pubspecFile.exists()) {
    print('Error: pubspec.yaml not found at ${pubspecFile.path}');
    return;
  }
  final pubspecContent = await pubspecFile.readAsString();
  final YamlMap doc;
  try {
    doc = loadYaml(pubspecContent) as YamlMap;
  } catch(e) {
    print('Error parsing pubspec.yaml: $e');
    return;
  }
  
  final editor = YamlEditor(pubspecContent);
  final currentVersion = doc['version'] as String?;

  if (currentVersion == null) {
    print('Error: "version" field not found in pubspec.yaml');
    return;
  }

  final versionParts = currentVersion.split('+');
  final versionNumber = versionParts[0];
  final currentBuildNumber = int.tryParse(versionParts.length > 1 ? versionParts[1] : '0') ?? 0;
  final newBuildNumber = currentBuildNumber + 1;
  final newVersion = '$versionNumber+$newBuildNumber';

  editor.update(['version'], newVersion);
  await pubspecFile.writeAsString(editor.toString());
  print('Updated build number to $newBuildNumber in pubspec.yaml (version: $newVersion)');
}
