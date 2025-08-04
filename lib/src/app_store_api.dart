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
        'exp':
        DateTime.now().add(Duration(minutes: 20)).millisecondsSinceEpoch ~/
            1000,
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

  /// Gets the latest build number from TestFlight.
  Future<int> getLatestBuildNumber() async {
    final appId = await _getAppId();
    if (appId == null) {
      print('No app found with bundle ID: $bundleId');
      return 0;
    }

    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token'};
    final url = Uri.parse(
        '$_apiBaseUrl/builds?filter[app]=$appId&sort=-version&limit=1');
    final response = await http.get(url, headers: headers);

    if (response.statusCode != 200) return 0;
    final data = json.decode(response.body);
    if (data['data'] == null || data['data'].isEmpty) return 0;

    return int.tryParse(data['data'][0]['attributes']['version'] ?? '0') ?? 0;
  }

  /// Main method to upload IPA, wait for processing, and submit for review.
  Future<bool> uploadAndSubmit({
    required String ipaPath,
    String? whatsNew,
    required bool submitForReview,
  }) async {
    try {
      final appId = await _getAppId();
      if (appId == null) {
        print('Could not find app with bundle ID: $bundleId');
        return false;
      }

      print('Requesting upload details from App Store Connect...');
      final uploadDetails = await _createUploadSession(appId);
      if (uploadDetails == null) {
        print('Failed to get upload details from App Store Connect.');
        return false;
      }

      final uploadId = uploadDetails['uploadId'];
      final uploadUrl = uploadDetails['uploadUrl'];
      final uploadHeaders = uploadDetails['uploadHeaders'];
      final fileLength = uploadDetails['fileLength'];

      print('Uploading IPA file...');
      final uploadSuccess =
      await _uploadIpa(uploadUrl, uploadHeaders, ipaPath, fileLength);
      if (!uploadSuccess) {
        print('IPA upload failed.');
        return false;
      }
      print('IPA uploaded successfully. Upload ID: $uploadId');

      print('Committing upload to start processing...');
      final buildId = await _commitUpload(uploadId, fileLength);
      if (buildId == null) {
        print('Failed to commit upload.');
        return false;
      }
      print('Upload committed. New Build ID: $buildId');

      print('Waiting for App Store Connect to process the build...');
      final processed = await pollBuildStatus(buildId);
      if (!processed) {
        print('Build processing failed or timed out.');
        return false;
      }
      print('Build processing complete!');

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

  /// **CORRECT IMPLEMENTATION**
  /// Creates a new App Store Connect `builds` resource using the Upload API.
  /// This endpoint is different from the old `builds` endpoint and correctly
  /// handles the upload reservation process.
  Future<Map<String, dynamic>?> _createUploadSession(String appId) async {
    final token = _generateToken();
    final url = Uri.parse('$_apiBaseUrl/builds');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    final body = json.encode({
      'data': {
        'type': 'builds',
        'relationships': {
          'app': {
            'data': {'type': 'apps', 'id': appId}
          }
        }
      }
    });

    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode != 201) {
      print(
          'Failed to create upload session: ${response.statusCode} ${response.body}');
      return null;
    }

    final data = json.decode(response.body);
    final buildId = data['data']['id'];

    // The 'uploadOperation' contains the unique URL and headers for uploading the IPA file.
    final uploadOperation = data['data']['attributes']['uploadOperations'][0];
    final uploadUrl = uploadOperation['url'];
    final requestHeaders = uploadOperation['requestHeaders'] as List;
    final fileLength = uploadOperation['length'] as int;

    final uploadHeadersMap = {
      for (var h in requestHeaders) h['name']: h['value']
    };

    return {
      'buildId': buildId,
      'uploadUrl': uploadUrl,
      'uploadHeaders': uploadHeadersMap,
      'fileLength': fileLength,
    };
  }

  /// Uploads the IPA file to the URL provided by App Store Connect.
  Future<bool> _uploadIpa(
      String uploadUrl, Map<String, dynamic> headers, String ipaPath, int fileLength) async {
    final file = File(ipaPath);
    if (!await file.exists()) {
      print('Error: IPA file not found at $ipaPath');
      return false;
    }

    final fileBytes = await file.readAsBytes();
    final uploadUri = Uri.parse(uploadUrl);

    // Add the required headers for the upload.
    headers['Content-Type'] = 'application/octet-stream';
    headers['Content-Length'] = fileBytes.length.toString();
    headers['Accept'] = 'application/json';

    final response = await http.put(
      uploadUri,
      headers: headers.cast<String, String>(),
      body: fileBytes,
    );

    if (response.statusCode != 200) {
      print('Failed to upload IPA file: ${response.statusCode} ${response.body}');
      return false;
    }
    return true;
  }

  /// **NEW METHOD**
  /// Commits the upload to App Store Connect, signaling that the file transfer is complete.
  /// This triggers the build processing.
  Future<String?> _commitUpload(String buildId, int fileLength) async {
    final token = _generateToken();
    final url = Uri.parse('$_apiBaseUrl/builds/$buildId');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    final body = json.encode({
      'data': {
        'id': buildId,
        'type': 'builds',
        'attributes': {
          'uploaded': true,
          'archiveFileSize': fileLength,
          'usesAppStoreConnectApi': true,
        },
      }
    });

    final response = await http.patch(url, headers: headers, body: body);

    if (response.statusCode != 200) {
      print('Failed to commit build upload: ${response.statusCode} ${response.body}');
      return null;
    }

    final data = json.decode(response.body);
    return data['data']['id'];
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