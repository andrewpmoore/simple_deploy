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
  final minLength = newParts.length < oldParts.length ? newParts.length : oldParts.length;
  for (var i = 0; i < minLength; i++) {
    if (newParts[i] > oldParts[i]) return true;
    if (newParts[i] < oldParts[i]) return false;
  }
  return newParts.length > oldParts.length;
}

Future<void> deploy({
  String? flavor,
  bool skipClean = false,
  bool submitToReview = false,
  bool useStoreIncrement = false,
  // New parameters for App Store release control
  bool releaseAfterReview = false,
  String? releaseType,
  String? scheduledReleaseDate,
}) async {
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
  final autoIncrementMarketingVersion = config?['autoIncrementMarketingVersion'] as bool? ?? false;

  if (issuerId == null || keyId == null || privateKeyPath == null || bundleId == null) {
    handleError('ios config in deploy.yaml must include issuerId, keyId, privateKeyPath, and bundleId.');
  }

  final appStoreApi = AppStoreApiClient(
    issuerId: issuerId!,
    keyId: keyId!,
    privateKeyPath: privateKeyPath!,
    bundleId: bundleId!,
  );

  // 2. Handle versioning
  final pubspecFile = File('pubspec.yaml');
  final pubspecContent = await pubspecFile.readAsString();
  final editor = YamlEditor(pubspecContent);
  final currentVersionString = (loadYaml(pubspecContent) as YamlMap)['version'] as String;

  final parts = currentVersionString.split('+');
  String marketingVersion = parts[0];
  int buildNumber = int.parse(parts[1]);

  if (useStoreIncrement) {
    print('Checking App Store Connect for latest build details...');
    final latestBuildDetails = await appStoreApi.getLatestBuildDetails();

    int latestStoreBuildNumber = 0;
    if (latestBuildDetails != null) {
      final storeMarketingVersion = latestBuildDetails['marketingVersion'] as String;
      latestStoreBuildNumber = latestBuildDetails['buildNumber'] as int;

      print('Found store version: $storeMarketingVersion+$latestStoreBuildNumber');

      if (isVersionHigher(storeMarketingVersion, marketingVersion)) {
        marketingVersion = storeMarketingVersion;
        print('Adopted marketing version from App Store: $marketingVersion');
      }
    } else {
      print('No existing builds found in App Store Connect.');
    }

    buildNumber = latestStoreBuildNumber + 1;
    print('New build number will be $buildNumber.');

    if (autoIncrementMarketingVersion) {
      final marketingParts = marketingVersion.split('.').map(int.parse).toList();
      if (marketingParts.isNotEmpty) {
        marketingParts[marketingParts.length - 1]++;
        marketingVersion = marketingParts.join('.');
        print('Auto-incremented marketing version to: $marketingVersion');
      }
    }

    final newVersionString = '$marketingVersion+$buildNumber';
    print('Updating pubspec.yaml to version: $newVersionString');
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
    '--build-name=$marketingVersion',
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
    appVersion: marketingVersion,
    buildNumber: buildNumber.toString(),
    whatsNew: whatsNew,
    submitForReview: submitToReview, // Determines if App Store or Beta review
    releaseAfterReview: releaseAfterReview, // For App Store: Release after review
    releaseType: releaseType, // For App Store: MANUAL, AFTER_APPROVAL, SCHEDULED
    scheduledReleaseDate: DateTime.parse(scheduledReleaseDate??DateTime.now().toIso8601String()), // For App Store: If releaseType is SCHEDULED
  );

  if (success) {
    print('✅ iOS deployment completed successfully!');
  } else {
    print('❌ iOS deployment failed.');
  }

  print('Time taken: ${DateTime.now().difference(startTime)}');
}