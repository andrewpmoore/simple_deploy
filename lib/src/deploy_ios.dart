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

  // 2. Handle version increment if requested
  if (useStoreIncrement) {
    print('Checking TestFlight for latest build number...');
    final latestBuildNumber = await appStoreApi.getLatestBuildNumber();
    final nextBuildNumber = latestBuildNumber + 1;

    final pubspecFile = File('pubspec.yaml');
    final pubspecContent = await pubspecFile.readAsString();
    final editor = YamlEditor(pubspecContent);
    final currentVersion = (loadYaml(pubspecContent) as YamlMap)['version'] as String;
    final newVersion = '${currentVersion.split('+').first}+$nextBuildNumber';
    editor.update(['version'], newVersion);
    await pubspecFile.writeAsString(editor.toString());
    print('Updated pubspec.yaml build number to $nextBuildNumber.');
  }

  DateTime startTime = DateTime.now();

  // 3. Clean and Build
  if (!skipClean) {
    if (!await flutterClean(workingDirectory)) return;
  }

  print('Building the iOS .ipa ${flavor != null ? "for $flavor flavor" : ""}');
  var buildResult = await Process.run('flutter', ['build', 'ipa', if (flavor != null) ...['--flavor', flavor]],
      workingDirectory: workingDirectory, runInShell: true);

  if (buildResult.exitCode != 0) {
    handleError('flutter build ipa failed: ${buildResult.stderr}');
  }
  print('Built .ipa file successfully.');

  // 4. Deploy using the API client
  final ipaName = config?['generatedFileName']?.toString() ?? 'app.ipa';
  final ipaPath = '$workingDirectory/build/ios/ipa/$ipaName';
  final whatsNew = config?['whatsNew']?.toString();

  // As noted, a real implementation for the IPA upload is required in the API client.
  // The line below assumes the client can handle it.
  bool success = await appStoreApi.uploadAndSubmit(
    ipaPath: ipaPath,
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