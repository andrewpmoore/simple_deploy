// deploy_ios.dart

import 'dart:io';
import 'dart:async';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'common.dart';
import 'app_store_api.dart';

void handleError(String message) {
  print("Error: $message");
  exit(1);
}

// Helper function to compare version strings (e.g., '1.0.5' vs '1.0.16')
bool isVersionHigher(String newVersion, String oldVersion) {
  final newParts = newVersion.split('.').map(int.parse).toList();
  final oldParts = oldVersion.split('.').map(int.parse).toList();
  for (var i = 0; i < newParts.length; i++) {
    if (newParts[i] > oldParts[i]) return true;
    if (newParts[i] < oldParts[i]) return false;
  }
  return false;
}

Future<void> deploy(
    {String? flavor,
      bool skipClean = false,
      bool submitToReview = false,
      bool useStoreIncrement = false}) async {
  final workingDirectory = Directory.current.path;

  // 1. Load configuration
  final config = await loadConfig(workingDirectory, 'ios');
  if (config == null) {
    handleError('Could not load "ios" configuration from deploy.yaml');
  }

  final issuerId = config?['issuerId']?.toString();
  final keyId = config?['keyId']?.toString();
  final privateKeyPath = config?['privateKeyPath']?.toString();
  final bundleId = config?['bundleId']?.toString();

  if (issuerId == null || keyId == null || privateKeyPath == null || bundleId == null) {
    handleError('ios config in deploy.yaml must include issuerId, keyId, privateKeyPath, and bundleId.');
  }

  final appStoreApi = AppStoreApiClient(
    issuerId: issuerId!,
    keyId: keyId!,
    privateKeyPath: privateKeyPath!,
    bundleId: bundleId!,
  );

  // 2. Handle version increment if requested and get the final app version
  final pubspecFile = File('pubspec.yaml');
  final pubspecContent = await pubspecFile.readAsString();
  final editor = YamlEditor(pubspecContent);
  final currentVersionString = (loadYaml(pubspecContent) as YamlMap)['version'] as String;

  // The version format is now handled correctly (e.g., '1.0.15.37')
  final parts = currentVersionString.split('.');
  String marketingVersion = parts.sublist(0, parts.length - 1).join('.');
  int buildNumber = int.parse(parts.last);

  if (useStoreIncrement) {
    print('Checking TestFlight for latest build details...');
    final latestAppVersion = await appStoreApi.getLatestAppVersion();

    if (latestAppVersion != null) {
      final latestParts = latestAppVersion.split('.');
      final latestMarketingVersion = latestParts.sublist(0, latestParts.length - 1).join('.');
      final latestBuildNumber = int.parse(latestParts.last);

      if (isVersionHigher(latestMarketingVersion, marketingVersion)) {
        // If the store's marketing version is higher, we must use it.
        marketingVersion = latestMarketingVersion;
        buildNumber = latestBuildNumber + 1;
        print('Updated marketing version to match store: $marketingVersion');
      } else {
        // Otherwise, we simply increment the local build number.
        buildNumber = latestBuildNumber + 1;
      }
    }

    print('Updated build number to $buildNumber.');

    // Update pubspec.yaml with the new version string
    final newVersionString = '$marketingVersion.$buildNumber';
    editor.update(['version'], newVersionString);
    await pubspecFile.writeAsString(editor.toString());
  }

  DateTime startTime = DateTime.now();

  // 3. Clean and Build
  if (!skipClean) {
    if (!await flutterClean(workingDirectory)) return;
  }

  print('Building the iOS .ipa ${flavor != null ? "for $flavor flavor" : ""}');
  var buildResult = await Process.run('flutter', [
    'build', 'ipa',
    if (flavor != null) ...['--flavor', flavor],
    // Use the build-name and build-number flags to ensure Info.plist is correctly updated.
    '--build-name=$marketingVersion',
    '--build-number=$buildNumber.0', // Build number for iOS should be an integer, but Flutter's flag takes a string
  ],
      workingDirectory: workingDirectory, runInShell: true);

  if (buildResult.exitCode != 0) {
    handleError('flutter build ipa failed: ${buildResult.stderr}');
  }
  print('Built .ipa file successfully.');

  // 4. Deploy using the API client
  final ipaName = config?['generatedFileName']?.toString() ?? 'app.ipa';
  final ipaPath = '$workingDirectory/build/ios/ipa/$ipaName';
  final whatsNew = config?['whatsNew']?.toString();

  bool success = await appStoreApi.uploadAndSubmit(
    ipaPath: ipaPath,
    appVersion: marketingVersion, // Pass the marketing version here
    whatsNew: whatsNew,
    submitForReview: submitToReview,
  );

  if (success) {
    print('✅ iOS deployment completed successfully!');
  } else {
    print('❌ iOS deployment failed.');
  }

  print('Time taken: ${DateTime.now().difference(startTime)}');
}