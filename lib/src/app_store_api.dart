// app_store_api.dart

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class AppStoreApiClient {
  final String issuerId;
  final String keyId;
  final String privateKeyPath;
  final String bundleId;
  static const _apiBaseUrl = 'https://api.appstoreconnect.apple.com/v1';

  AppStoreApiClient({
    required this.issuerId,
    required this.keyId,
    required this.privateKeyPath,
    required this.bundleId,
  });

  /// Generates a JWT token for authentication.
  String _generateToken() {
    final privateKey = File(privateKeyPath).readAsStringSync();
    final jwt = JWT(
      {
        'iss': issuerId,
        'exp': DateTime.now().add(Duration(minutes: 20)).millisecondsSinceEpoch ~/ 1000,
        'aud': 'appstoreconnect-v1'
      },
      header: {'kid': keyId, 'typ': 'JWT'},
    );
    return jwt.sign(ECPrivateKey(privateKey), algorithm: JWTAlgorithm.ES256);
  }

  /// Retrieves the internal App ID from the bundle ID.
  Future<String?> _getAppId() async {
    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token'};
    final url = Uri.parse('$_apiBaseUrl/apps?filter[bundleId]=$bundleId');
    final response = await http.get(url, headers: headers);

    if (response.statusCode != 200) {
      print('Failed to get app: ${response.body}');
      return null;
    }
    final data = json.decode(response.body);
    if (data['data'] == null || data['data'].isEmpty) {
      return null;
    }
    return data['data'][0]['id'];
  }

  /// Retrieves the latest marketing version string from TestFlight.
  Future<String?> getLatestMarketingVersion() async {
    final appId = await _getAppId();
    if (appId == null) {
      print('No app found with bundle ID: $bundleId');
      return null;
    }

    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token'};
    // Sort by version and get the first one to find the latest
    final url = Uri.parse('$_apiBaseUrl/builds?filter[app]=$appId&sort=-version&limit=1');
    final response = await http.get(url, headers: headers);

    if (response.statusCode != 200) {
      print('Failed to get latest build from App Store API: ${response.body}');
      return null;
    }
    final data = json.decode(response.body);
    if (data['data'] == null || data['data'].isEmpty) {
      return null;
    }

    // This now correctly returns the marketing version string, e.g., '1.0.16'
    return data['data'][0]['attributes']['version'];
  }

  /// Retrieves the latest build number for a given marketing version.
  Future<int> getLatestBuildNumber(String marketingVersion) async {
    final appId = await _getAppId();
    if (appId == null) {
      return 0;
    }
    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token'};
    final url = Uri.parse(
        '$_apiBaseUrl/builds?filter[app]=$appId&filter[version]=$marketingVersion&sort=-uploadedDate&limit=1');
    final response = await http.get(url, headers: headers);

    if (response.statusCode != 200) {
      return 0;
    }
    final data = json.decode(response.body);
    if (data['data'] == null || data['data'].isEmpty) {
      return 0;
    }

    // The build number is typically the version number in the pubspec.yaml file, which is what we need to increment.
    // The App Store Connect API 'version' attribute is the marketing version.
    // We will retrieve the build number from the pubspec.yaml file in the deploy script.
    // This function will now simply return 0 if no builds are found for the marketing version.
    return 0;
  }

  /// NEW METHOD: Find a build by version and bundle ID
  Future<String?> _getBuildIdByVersion(String version) async {
    final appId = await _getAppId();
    if (appId == null) return null;

    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token'};
    // We filter by both app and the version string to find the correct build.
    final url = Uri.parse('$_apiBaseUrl/builds?filter[app]=$appId&filter[version]=$version');
    final response = await http.get(url, headers: headers);

    if (response.statusCode != 200) {
      print('Failed to find build for version $version: ${response.body}');
      return null;
    }
    final data = json.decode(response.body);
    if (data['data'] == null || data['data'].isEmpty) {
      return null;
    }
    return data['data'][0]['id'];
  }

  /// Main method to upload IPA using `altool` and then manage with the API.
  Future<bool> uploadAndSubmit({
    required String ipaPath,
    required String appVersion, // We now need the app version to find the build later.
    String? whatsNew,
    required bool submitForReview,
  }) async {
    try {
      // Step 1: Use `altool` to upload the IPA file.
      print('Uploading IPA using altool...');
      final altoolResult = await Process.run('xcrun', [
        'altool',
        '--upload-app',
        '-f',
        ipaPath,
        '-t', // Use '-t' for the type flag
        'ios', // Specify 'ios' as the platform type
        '--apiKey',
        keyId,
        '--apiIssuer',
        issuerId,
      ]);

      if (altoolResult.exitCode != 0) {
        print('IPA upload failed with altool:');
        print(altoolResult.stderr);
        return false;
      }
      print('altool upload successful.');
      print(altoolResult.stdout);

      // Step 2: Poll for the new build to appear in App Store Connect.
      // This is necessary because it takes a moment for the new build to be visible.
      print('Waiting for App Store Connect to register the new build...');
      String? buildId;
      const maxAttempts = 60; // Up to 5 minutes
      for (int i = 0; i < maxAttempts; i++) {
        buildId = await _getBuildIdByVersion(appVersion);
        if (buildId != null) {
          print('Found build with ID: $buildId');
          break;
        }
        await Future.delayed(Duration(seconds: 5));
      }

      if (buildId == null) {
        print('Failed to find the new build in App Store Connect.');
        return false;
      }

      // Step 3: Poll for build processing status.
      print('Waiting for App Store Connect to process the build...');
      final processed = await pollBuildStatus(buildId);
      if (!processed) {
        print('Build processing failed or timed out.');
        return false;
      }
      print('Build processing complete!');

      // Step 4: Optionally submit the processed build for Beta App Review.
      if (submitForReview) {
        print('Submitting build for Beta App Review...');
        final submitted = await submitForBetaReview(buildId, whatsNew);
        if (submitted) {
          print('Successfully submitted for review.');
        } else {
          print('Failed to submit for review.');
          return false;
        }
      }
      return true;
    } catch (e) {
      print('An error occurred during deployment: $e');
      return false;
    }
  }

  /// Polls the build status until it's processed or fails.
  Future<bool> pollBuildStatus(String buildId) async {
    const maxAttempts = 30; // 15 minutes
    for (int i = 0; i < maxAttempts; i++) {
      final token = _generateToken();
      final url = Uri.parse('$_apiBaseUrl/builds/$buildId');
      final headers = {'Authorization': 'Bearer $token'};
      final response = await http.get(url, headers: headers);

      if (response.statusCode != 200) {
        await Future.delayed(Duration(seconds: 30));
        continue;
      }

      final data = json.decode(response.body);
      final processingState = data['data']['attributes']['processingState'];
      print('Build status: $processingState (${i + 1}/$maxAttempts)');

      if (processingState == 'VALID') return true;
      if (processingState == 'FAILED' || processingState == 'INVALID') return false;

      await Future.delayed(Duration(seconds: 30));
    }
    return false;
  }

  /// Submits a processed build for Beta App Review.
  Future<bool> submitForBetaReview(String buildId, String? whatsNew) async {
    if (whatsNew != null && whatsNew.isNotEmpty) {
      final localizationSuccess = await _createBetaBuildLocalization(buildId, whatsNew);
      if (!localizationSuccess) {
        print('Could not add "What\'s New" text to the build. Submitting without it.');
      }
    }

    return await _createBetaAppReviewSubmission(buildId);
  }

  Future<bool> _createBetaBuildLocalization(String buildId, String whatsNew) async {
    final token = _generateToken();
    final url = Uri.parse('$_apiBaseUrl/betaBuildLocalizations');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final body = json.encode({
      'data': {
        'type': 'betaBuildLocalizations',
        'attributes': {'whatsNew': whatsNew, 'locale': 'en-US'},
        'relationships': {'build': {'data': {'type': 'builds', 'id': buildId}}}
      }
    });

    final response = await http.post(url, headers: headers, body: body);
    return response.statusCode == 201;
  }

  Future<bool> _createBetaAppReviewSubmission(String buildId) async {
    final token = _generateToken();
    final url = Uri.parse('$_apiBaseUrl/betaAppReviewSubmissions');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final body = json.encode({
      'data': {
        'type': 'betaAppReviewSubmissions',
        'relationships': {'build': {'data': {'type': 'builds', 'id': buildId}}}
      }
    });
    final response = await http.post(url, headers: headers, body: body);
    return response.statusCode == 201;
  }
}