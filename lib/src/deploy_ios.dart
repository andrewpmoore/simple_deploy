import 'dart:io';
import 'common.dart';

// Function to handle errors
void handleError(String message) {
  print("Error: $message");
  exit(1);
}

Future<void> deploy({String? flavor}) async {
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

  DateTime startTime = DateTime.now();

  // Run flutter clean
  bool success = await flutterClean(workingDirectory);
  if (!success) {
    return;
  }

  // Build the iOS .ipa with optional flavor
  print('Building the iOS .ipa ${flavor != null ? "for $flavor flavor" : ""}');
  var buildArgs = ['build', 'ipa'];
  if (flavor != null) {
    buildArgs.add('--flavor');
    buildArgs.add(flavor);
    print('iOS flavor $flavor');
  }

  var result = await Process.run('flutter', buildArgs, workingDirectory: workingDirectory, runInShell: true);
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
      '--type', 'ios',
      '--file', '$workingDirectory/build/ios/ipa/app${flavor != null ? '-$flavor' : ''}.ipa',
      '--apiKey', apiKey,
      '--apiIssuer', apiIssuer
    ],
    workingDirectory: workingDirectory,
    runInShell: true,
  );
  if (result.exitCode != 0) {
    handleError('Upload to TestFlight failed: ${result.stderr}');
  }

  print('iOS app uploaded to TestFlight successfully!');
  print('Time taken: ${DateTime.now().difference(startTime)}');
}
