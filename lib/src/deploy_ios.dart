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
  final autoIncrementMarketingVersion = config?['autoIncrementMarketingVersion'] as bool? ?? true;

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

  String appVersion = currentVersionString.split('+').first;
  int buildNumber = int.parse(currentVersionString.split('+').last);

  if (useStoreIncrement) {
    print('Checking TestFlight for latest build details...');

    if (autoIncrementMarketingVersion) {
      final latestMarketingVersion = await appStoreApi.getLatestMarketingVersion();

      if (latestMarketingVersion != null && isVersionHigher(latestMarketingVersion, appVersion)) {
        // Marketing version is lower than the last one in the store, so we need to update it.
        appVersion = latestMarketingVersion;
        print('Updated app version to match store: $appVersion');
      }
    }

    // Get the latest build number for this marketing version
    final latestBuildNumber = await appStoreApi.getLatestBuildNumber(appVersion);
    buildNumber = latestBuildNumber + 1;
    print('Updated pubspec.yaml build number to $buildNumber.');

    // Update pubspec.yaml with the new version string
    final newVersionString = '$appVersion+$buildNumber';
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
    '--build-name=$appVersion',
    '--build-number=$buildNumber',
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
    appVersion: appVersion,
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