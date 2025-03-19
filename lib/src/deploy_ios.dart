import 'dart:io';
import 'dart:async';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'common.dart';
import 'app_store_api.dart';

// Function to handle errors
void handleError(String message) {
  print("Error: $message");
  exit(1);
}

Future<bool> waitForBuildProcessing(
    String apiKey, String apiIssuer, String bundleId) async {
  print('Waiting for build to process in TestFlight...');
  int attempts = 0;
  const maxAttempts = 30; // 15 minutes maximum wait time

  while (attempts < maxAttempts) {
    var result = await Process.run(
      'xcrun',
      [
        'altool',
        '--list-builds',
        '--type',
        'ios',
        '--bundle-id',
        bundleId,
        '--apiKey',
        apiKey,
        '--apiIssuer',
        apiIssuer
      ],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      print('Error checking build status: ${result.stderr}');
      return false;
    }

    // Check if the build is processed (you'll need to parse the output)
    if (result.stdout.toString().contains('Processing Complete')) {
      print('Build processing complete!');
      return true;
    }

    print('Build still processing... (${attempts + 1}/$maxAttempts)');
    await Future.delayed(
        Duration(seconds: 30)); // Wait 30 seconds between checks
    attempts++;
  }

  print('Timed out waiting for build to process');
  return false;
}

Future<bool> submitForReview(
    String apiKey, String apiIssuer, String bundleId, String whatsNew) async {
  print('Submitting build for App Store review...');

  var result = await Process.run(
    'xcrun',
    [
      'altool',
      '--submit-for-review',
      '--type',
      'ios',
      '--bundle-id',
      bundleId,
      '--apiKey',
      apiKey,
      '--apiIssuer',
      apiIssuer,
      '--whats-new',
      whatsNew
    ],
    runInShell: true,
  );

  if (result.exitCode != 0) {
    print('Failed to submit for review: ${result.stderr}');
    return false;
  }

  print('Successfully submitted for App Store review!');
  return true;
}

Future<void> deploy(
    {String? flavor,
    bool skipClean = false,
    bool submitToReview = false,
    bool useStoreIncrement = false}) async {
  final workingDirectory = Directory.current.path;

  // Load config based on the flavor (if provided)
  final configFileName = flavor != null ? 'ios_$flavor' : 'ios';
  final config = await loadConfig(workingDirectory, configFileName);

  final apiKey = config?['teamKeyId'];
  if (apiKey == null) {
    print('No teamKeyId supplied');
    exit(1);
  }
  final apiIssuer = config?['developerId'];
  if (apiIssuer == null) {
    print('No developerId supplied');
    exit(1);
  }

  final bundleId = config?['bundleId'];
  if (bundleId == null) {
    print('No bundleId supplied');
    exit(1);
  }

  // If using store increment, validate and get App Store Connect API config
  if (useStoreIncrement) {
    final issuerId = config?['issuerId'];
    if (issuerId == null) {
      print('No issuerId supplied (required for storeIncrement)');
      exit(1);
    }
    final keyId = config?['keyId'];
    if (keyId == null) {
      print('No keyId supplied (required for storeIncrement)');
      exit(1);
    }
    final privateKeyPath = config?['privateKeyPath'];
    if (privateKeyPath == null) {
      print('No privateKeyPath supplied (required for storeIncrement)');
      exit(1);
    }

    // Get the latest build number from TestFlight and increment it
    final appStoreApi = AppStoreApiClient(
      issuerId: issuerId,
      keyId: keyId,
      privateKeyPath: privateKeyPath,
      bundleId: bundleId,
    );

    final latestBuildNumber = await appStoreApi.getLatestBuildNumber();
    final nextBuildNumber = latestBuildNumber + 1;

    // Update the pubspec.yaml with the new build number
    final pubspecFile = File('pubspec.yaml');
    final pubspecContent = await pubspecFile.readAsString();
    final doc = loadYaml(pubspecContent);
    final editor = YamlEditor(pubspecContent);
    final currentVersion = doc['version'] as String;
    final versionParts = currentVersion.split('+');
    final versionNumber = versionParts[0];
    final newVersion = '$versionNumber+$nextBuildNumber';
    editor.update(['version'], newVersion);
    await pubspecFile.writeAsString(editor.toString());
    print(
        'Updated build number to $nextBuildNumber in pubspec.yaml based on TestFlight version');
  }

  final whatsNew = config?['whatsNew'] ?? 'Bug fixes and improvements';

  final generatedFileName = (config?['generatedFileName'] ?? 'app.ipa')
      .toString()
      .replaceFirst('.ipa', '');

  DateTime startTime = DateTime.now();

  // Run flutter clean if not skipped
  if (!skipClean) {
    bool success = await flutterClean(workingDirectory);
    if (!success) {
      return;
    }
  }

  // Build the iOS .ipa with optional flavor
  print('Building the iOS .ipa ${flavor != null ? "for $flavor flavor" : ""}');
  var buildArgs = ['build', 'ipa'];
  if (flavor != null) {
    buildArgs.add('--flavor');
    buildArgs.add(flavor);
    print('iOS flavor $flavor');
  }

  var result = await Process.run('flutter', buildArgs,
      workingDirectory: workingDirectory, runInShell: true);
  if (result.exitCode != 0) {
    handleError('flutter build ipa failed: ${result.stderr}');
  }
  print('Built .ipa file');

  // Upload the IPA to TestFlight
  print('Uploading the IPA to TestFlight');
  result = await Process.run(
    'xcrun',
    [
      'altool',
      '--upload-app',
      '--type',
      'ios',
      '--file',
      '$workingDirectory/build/ios/ipa/$generatedFileName${flavor != null ? '-$flavor' : ''}.ipa',
      '--apiKey',
      apiKey,
      '--apiIssuer',
      apiIssuer
    ],
    workingDirectory: workingDirectory,
    runInShell: true,
  );
  if (result.exitCode != 0) {
    handleError('Upload to TestFlight failed: ${result.stderr}');
  }

  print('iOS app uploaded to TestFlight successfully!');

  if (submitToReview) {
    // Wait for the build to be processed
    bool processed = await waitForBuildProcessing(apiKey, apiIssuer, bundleId);
    if (!processed) {
      print('Failed to verify build processing status');
      return;
    }

    // Submit for review
    bool submitted =
        await submitForReview(apiKey, apiIssuer, bundleId, whatsNew);
    if (!submitted) {
      print('Failed to submit for App Store review');
      return;
    }
  }

  print('Time taken: ${DateTime.now().difference(startTime)}');
}
