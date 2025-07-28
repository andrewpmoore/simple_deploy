import 'dart:convert';
import 'dart:io';
import 'package:googleapis/androidpublisher/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:simple_deploy/src/loading.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'common.dart';

/// Gets the latest version code from the Play Store for the given package and track
Future<int> getLatestVersionCode(AndroidPublisherApi androidPublisher,
    String packageName, String editId, String trackName) async { // Added editId parameter
  try {
    // Use the valid editId instead of 'temp'
    final track =
    await androidPublisher.edits.tracks.get(packageName, editId, trackName);
    if (track.releases == null || track.releases!.isEmpty) {
      return 0; // No releases yet
    }

    // Find the highest version code across all releases
    int highestVersionCode = 0;
    for (var release in track.releases!) {
      if (release.versionCodes == null || release.versionCodes!.isEmpty) {
        continue;
      }
      for (var versionCode in release.versionCodes!) {
        final code = int.tryParse(versionCode) ?? 0;
        if (code > highestVersionCode) {
          highestVersionCode = code;
        }
      }
    }
    return highestVersionCode;
  } catch (e) {
    // Check if the error is because the track doesn't exist yet, which is not a critical failure
    if (e.toString().contains('track_not_found')) {
      print('Warning: Track "$trackName" not found. Assuming version code 0.');
      return 0;
    }
    print('Warning: Failed to get latest version code from Play Store: $e');
    return 0;
  }
}


Future<void> deploy(
    {String? flavor,
      bool skipClean = false,
      bool useStoreIncrement = false}) async {
  final workingDirectory = Directory.current.path;

  // Load config based on the flavor (if provided)
  final configFileName = flavor != null ? 'android_$flavor' : 'android';
  final config = await loadConfig(workingDirectory, configFileName);

  final credentialsFile0 = config?['credentialsFile'];
  if (credentialsFile0 == null) {
    print('No credentialsFile supplied');
    exit(1);
  }
  final packageName = config?['packageName'];
  if (packageName == null) {
    print('No packageName supplied');
    exit(1);
  }
  final whatsNew = config?['whatsNew'] ?? 'No changes supplied';
  final trackNameRaw = config?['trackName'] ?? 'internal';
  final trackName = trackNameRaw.toString();
  final generatedFileName = config?['generatedFileName'] ?? 'app-release.aab';

  DateTime startTime = DateTime.now();

  startLoading('Get service account');
  File credentialsFile = File(credentialsFile0);
  final credentials = ServiceAccountCredentials.fromJson(
      json.decode(credentialsFile.readAsStringSync()));
  final httpClient = await clientViaServiceAccount(
      credentials, [AndroidPublisherApi.androidpublisherScope]);
  final androidPublisher = AndroidPublisherApi(httpClient);

  try {
    startLoading('Get Edit ID');
    final insertEdit =
    await androidPublisher.edits.insert(AppEdit(), packageName);
    final editId = insertEdit.id!;
    print("Edit ID: $editId");

    // If using store increment, get the latest version code and increment it
    if (useStoreIncrement) {
      startLoading('Getting latest version from Play Store...');
      final latestVersionCode =
      await getLatestVersionCode(androidPublisher, packageName, editId, trackName);
      final nextVersionCode = latestVersionCode + 1;
      print('Latest store version: $latestVersionCode. New version will be: $nextVersionCode');

      // Update the pubspec.yaml with the new version code
      final pubspecFile = File('pubspec.yaml');
      final pubspecContent = await pubspecFile.readAsString();
      final doc = loadYaml(pubspecContent);
      final editor = YamlEditor(pubspecContent);
      final currentVersion = doc['version'] as String;
      final versionParts = currentVersion.split('+');
      final versionNumber = versionParts[0];
      final newVersion = '$versionNumber+$nextVersionCode';
      editor.update(['version'], newVersion);
      await pubspecFile.writeAsString(editor.toString());
      print(
          'Updated build number to $nextVersionCode in pubspec.yaml');
    }

    // Run flutter clean if not skipped
    if (!skipClean) {
      bool success = await flutterClean(workingDirectory);
      if (!success) {
        stopLoading();
        return;
      }
    }

    startLoading('Build app bundle');
    var buildArgs = ['build', 'appbundle'];
    if (flavor != null) {
      buildArgs.add('--flavor');
      buildArgs.add(flavor);
      print('Android flavor $flavor');
    }
    var result = await Process.run('flutter', buildArgs,
        workingDirectory: workingDirectory, runInShell: true);

    if (result.exitCode != 0) {
      print('flutter build appbundle failed: ${result.stderr}');
      stopLoading();
      return;
    }
    print('App bundle built successfully');


    startLoading('Upload app bundle');
    final aabFile = File(
        '$workingDirectory/build/app/outputs/bundle/${flavor ?? 'release'}/$generatedFileName');
    final media = Media(aabFile.openRead(), aabFile.lengthSync());
    final uploadResponse = await androidPublisher.edits.bundles
        .upload(packageName, editId, uploadMedia: media);
    print("Bundle version code: ${uploadResponse.versionCode}");

    print('Assign to $trackName track');
    final track = Track(
      track: trackName,
      releases: [
        TrackRelease(
          name: '${trackName.capitalize()} Release',
          status: 'completed',
          versionCodes: [uploadResponse.versionCode!.toString()],
          releaseNotes: [
            LocalizedText(
              language: 'en-US',
              text: whatsNew,
            ),
          ],
        ),
      ],
    );
    await androidPublisher.edits.tracks
        .update(track, packageName, editId, trackName);
    print("Assigned bundle to $trackName track with release notes");

    await androidPublisher.edits.commit(packageName, editId);
    print("Edit committed, upload complete.");
  } catch (e) {
    print("Failed to upload to Play Console: $e");
  } finally {
    httpClient.close();
    print('Time taken: ${DateTime.now().difference(startTime)}');
    stopLoading();
  }
}


extension StringExtension on String {
  String capitalize() {
    return this[0].toUpperCase() + substring(1);
  }
}
