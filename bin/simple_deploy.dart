import 'dart:io';

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

  String? flavor = _getFlavorFromArgs(arguments);
  bool shouldIncrementVersion = arguments.contains('--pubspecIncrement');
  bool shouldSubmitReview = arguments.contains('--submit-review');

  if (arguments.isEmpty ||
      (arguments.length == 1 &&
          (flavor != null || shouldIncrementVersion || shouldSubmitReview))) {
    await promptAndDeploy(flavor, shouldIncrementVersion, shouldSubmitReview);
  } else {
    String target = arguments[0].toLowerCase();
    if (target == 'ios') {
      if (Platform.isMacOS) {
        await deployIos(flavor, shouldIncrementVersion, shouldSubmitReview);
      } else {
        print('Error: You can only deploy to iOS from MacOS.');
        return;
      }
    } else if (target == 'android') {
      await deployAndroid(flavor, shouldIncrementVersion);
    } else {
      print('Invalid argument. Please pass "ios" or "android".');
    }
  }
}

Future<void> promptAndDeploy(String? flavor, bool shouldIncrementVersion,
    bool shouldSubmitReview) async {
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
    await deployAndroid(flavor, shouldIncrementVersion);
  } else if (choice == '2') {
    await deployIos(flavor, shouldIncrementVersion, shouldSubmitReview);
  } else if (choice == 'a') {
    await deployAll(flavor, shouldIncrementVersion, shouldSubmitReview);
  } else if (choice == 'q') {
    print('Quitting deployment.');
  } else {
    print(Platform.isMacOS
        ? 'Invalid choice. Please enter 1, 2, a, or q.'
        : 'Invalid choice. Please enter 1.');
  }
}

Future<void> deployIos(String? flavor,
    [bool shouldIncrementVersion = false,
    bool shouldSubmitReview = false]) async {
  final versionStrategy = await handleVersionStrategy(shouldIncrementVersion);
  print('Deploying to iOS...');
  await ios.deploy(
      flavor: flavor,
      submitToReview: shouldSubmitReview,
      useStoreIncrement: versionStrategy == 'storeIncrement');
}

Future<void> deployAndroid(String? flavor,
    [bool shouldIncrementVersion = false]) async {
  final versionStrategy = await handleVersionStrategy(shouldIncrementVersion);
  print('Deploying to Android...');
  await android.deploy(
      flavor: flavor, useStoreIncrement: versionStrategy == 'storeIncrement');
}

Future<void> deployAll(String? flavor,
    [bool shouldIncrementVersion = false,
    bool shouldSubmitReview = false]) async {
  await handleVersionStrategy(shouldIncrementVersion);
  print('Deploying to all platforms...');

  // Clean once before deploying to all platforms
  final workingDirectory = Directory.current.path;
  bool success = await flutterClean(workingDirectory);
  if (!success) {
    print('Failed to clean project');
    return;
  }

  await android.deploy(flavor: flavor, skipClean: true);
  if (Platform.isMacOS) {
    await ios.deploy(
        flavor: flavor, skipClean: true, submitToReview: shouldSubmitReview);
  } else {
    print('iOS deployment is only available on MacOS.');
  }
}

Future<String> handleVersionStrategy(
    [bool shouldIncrementVersion = false]) async {
  final workingDirectory = Directory.current.path;
  String versionStrategy = 'none';
  try {
    final config = await loadConfig(workingDirectory, 'common');
    versionStrategy = config?['versionStrategy'] ?? 'none';
  } catch (e) {
    //
  }

  // Override version strategy if --pubspecIncrement flag is provided
  if (shouldIncrementVersion) {
    versionStrategy = 'pubspecIncrement';
  }

  print('versionStrategy: $versionStrategy');

  if (versionStrategy == 'pubspecIncrement') {
    await incrementBuildNumber();
  } else if (versionStrategy == 'storeIncrement') {
    // This will be handled by the deploy function
    print(
        'Using store increment strategy - will get latest version from store');
  } else if (versionStrategy == 'none') {
    // Do nothing
  } else {
    print(
        'Invalid versionStrategy. Valid values are `none`, `pubspecIncrement`, and `storeIncrement`.');
    exit(1);
  }

  return versionStrategy;
}

Future<void> incrementBuildNumber() async {
  final pubspecFile = File('pubspec.yaml');
  final pubspecContent = await pubspecFile.readAsString();

  final doc = loadYaml(pubspecContent);
  final editor = YamlEditor(pubspecContent);

  final currentVersion = doc['version'] as String;
  final versionParts = currentVersion.split('+');
  final versionNumber = versionParts[0];
  final currentBuildNumber =
      int.parse(versionParts.length > 1 ? versionParts[1] : '0');

  final newBuildNumber = currentBuildNumber + 1;
  final newVersion = '$versionNumber+$newBuildNumber';

  editor.update(['version'], newVersion);
  await pubspecFile.writeAsString(editor.toString());
  print('Updated build number to $newBuildNumber in pubspec.yaml');
}

// Helper function to parse the --flavor argument
String? _getFlavorFromArgs(List<String> args) {
  for (var arg in args) {
    if (arg.startsWith('--flavor=')) {
      return arg.split('=').last;
    }
  }
  return null;
}
