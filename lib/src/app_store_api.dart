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

  /// [MODIFIED] Retrieves the latest build details (marketing version and build number) from TestFlight.
  Future<Map<String, dynamic>?> getLatestBuildDetails() async {
    final appId = await _getAppId();
    if (appId == null) {
      return null;
    }
    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token'};
    // Sort by uploadedDate to reliably get the latest build.
    // Include preReleaseVersion to get the marketing version string.
    final url = Uri.parse('$_apiBaseUrl/builds?filter[app]=$appId&sort=-uploadedDate&limit=1&include=preReleaseVersion');
    final response = await http.get(url, headers: headers);

    if (response.statusCode != 200) {
      print('Failed to get latest build from App Store API: ${response.body}');
      return null;
    }
    final data = json.decode(response.body);
    if (data['data'] == null || data['data'].isEmpty) {
      return null; // No builds found.
    }

    final latestBuild = data['data'][0];
    final buildNumberString = latestBuild['attributes']['version'];

    String? marketingVersion;
    if (data['included'] != null && (data['included'] as List).isNotEmpty) {
      final preReleaseInfo = (data['included'] as List).firstWhere(
            (item) => item['type'] == 'preReleaseVersions',
        orElse: () => null,
      );
      if (preReleaseInfo != null) {
        marketingVersion = preReleaseInfo['attributes']['version'];
      }
    }

    if (buildNumberString == null || marketingVersion == null) {
      print('Could not determine full version info from API response.');
      return null;
    }

    return {
      'marketingVersion': marketingVersion,
      'buildNumber': int.parse(buildNumberString),
    };
  }


  /// [MODIFIED] Finds a build by its marketing version AND build number.
  Future<String?> _getBuildIdByVersion(String marketingVersion, String buildNumber) async {
    final appId = await _getAppId();
    if (appId == null) return null;

    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token'};
    // Filter by both the marketing version (preReleaseVersion.version) and the build number (version).
    final url = Uri.parse('$_apiBaseUrl/builds?filter[app]=$appId&filter[preReleaseVersion.version]=$marketingVersion&filter[version]=$buildNumber&limit=1');
    final response = await http.get(url, headers: headers);

    if (response.statusCode != 200) {
      print('Failed to find build for version $marketingVersion ($buildNumber): ${response.body}');
      return null;
    }
    final data = json.decode(response.body);
    if (data['data'] == null || data['data'].isEmpty) {
      return null;
    }
    return data['data'][0]['id'];
  }


  /// [MODIFIED] Main method to upload IPA and then manage with the API.
  Future<bool> uploadAndSubmit({
    required String ipaPath,
    required String appVersion,
    required String buildNumber, // Added buildNumber parameter
    String? whatsNew,
    required bool submitForReview,
  }) async {
    try {
      // Step 1: Use `altool` (via xcrun) to upload the IPA file.
      print('Uploading IPA using altool...');
      final altoolResult = await Process.run('xcrun', [
        'altool',
        '--upload-app',
        '-f',
        ipaPath,
        '-t',
        'ios',
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
      print('Waiting for App Store Connect to register the new build ($appVersion+$buildNumber)...');
      String? buildId;
      const maxAttempts = 60; // Poll for up to 5 minutes
      for (int i = 0; i < maxAttempts; i++) {
        // Use the updated method with both version components
        buildId = await _getBuildIdByVersion(appVersion, buildNumber);
        if (buildId != null) {
          print('Found build with ID: $buildId');
          break;
        }
        await Future.delayed(Duration(seconds: 5));
      }

      if (buildId == null) {
        print('Failed to find the new build in App Store Connect after upload.');
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