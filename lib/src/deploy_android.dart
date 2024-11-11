import 'dart:convert';
import 'dart:io';
import 'package:googleapis/androidpublisher/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:simple_deploy/src/loading.dart';

import 'common.dart';

Future<void> deploy({String? flavor}) async {
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

  DateTime startTime = DateTime.now();

  // Run flutter clean
  bool success = await flutterClean(workingDirectory);
  if (!success) {
    stopLoading();
    return;
  }

  startLoading('Build app bundle');

  // Build the app bundle with optional flavor
  var buildArgs = ['build', 'appbundle'];
  if (flavor != null) {
    buildArgs.add('--flavor');
    buildArgs.add(flavor);
    print('Android flavor $flavor');
  }

  var result = await Process.run('flutter', buildArgs, workingDirectory: workingDirectory, runInShell: true);

  if (result.exitCode != 0) {
    print('flutter build appbundle failed: ${result.stderr}');
    stopLoading();
    return;
  }
  print('App bundle built successfully');

  startLoading('Get service account');
  File credentialsFile = File(credentialsFile0);
  final credentials = ServiceAccountCredentials.fromJson(json.decode(credentialsFile.readAsStringSync()));
  final httpClient = await clientViaServiceAccount(credentials, [AndroidPublisherApi.androidpublisherScope]);

  try {
    startLoading('Get Edit ID');
    final androidPublisher = AndroidPublisherApi(httpClient);
    final insertEdit = await androidPublisher.edits.insert(AppEdit(), packageName);
    final editId = insertEdit.id!;
    print("Edit ID: $editId");

    startLoading('Upload app bundle');
    final aabFile = File('$workingDirectory/build/app/outputs/bundle/${flavor ?? 'release'}/app-release.aab');
    final media = Media(aabFile.openRead(), aabFile.lengthSync());
    final uploadResponse = await androidPublisher.edits.bundles.upload(packageName, editId, uploadMedia: media);
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
    await androidPublisher.edits.tracks.update(track, packageName, editId, trackName);
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
