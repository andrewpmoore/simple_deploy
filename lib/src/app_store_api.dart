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
      print('No app found for bundle ID: $bundleId');
      return null;
    }
    return data['data'][0]['id'];
  }

  /// Retrieves the latest build details (marketing version and build number) from TestFlight.
  Future<Map<String, dynamic>?> getLatestBuildDetails() async {
    final appId = await _getAppId();
    if (appId == null) {
      return null;
    }
    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token'};
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

  /// Finds a build by its marketing version AND build number.
  Future<String?> _getBuildIdByVersion(String marketingVersion, String buildNumber) async {
    final appId = await _getAppId();
    if (appId == null) return null;

    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token'};
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

  /// Main method to upload IPA and then manage with the API.
  Future<bool> uploadAndSubmit({
    required String ipaPath,
    required String appVersion, // Marketing version
    required String buildNumber,
    String? whatsNew,
    required bool submitForReview, // True for App Store Review, false for TestFlight Beta Review
    bool releaseAfterReview = false, // New: For App Store Review, determines if release is automatic or manual
    String? releaseType, // New: For App Store Review (MANUAL, AFTER_APPROVAL, SCHEDULED)
    DateTime? scheduledReleaseDate, // New: For App Store Review if releaseType is SCHEDULED
  }) async {
    try {
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
        print(altoolResult.stdout);
        return false;
      }
      print('altool upload successful.');
      print(altoolResult.stdout);

      print('Waiting for App Store Connect to register the new build ($appVersion+$buildNumber)...');
      String? buildId;
      const maxAttempts = 60; // Poll for up to 5 minutes (60 * 5s = 300s)
      for (int i = 0; i < maxAttempts; i++) {
        buildId = await _getBuildIdByVersion(appVersion, buildNumber);
        if (buildId != null) {
          print('Found build with ID: $buildId');
          break;
        }
        if (i < maxAttempts -1) await Future.delayed(Duration(seconds: 5));
      }

      if (buildId == null) {
        print('Failed to find the new build in App Store Connect after upload.');
        return false;
      }

      print('Waiting for App Store Connect to process the build...');
      final processed = await pollBuildStatus(buildId);
      if (!processed) {
        print('Build processing failed or timed out.');
        return false;
      }
      print('Build processing complete!');

      if (submitForReview) {
        print('Submitting build for App Store Review...');
        final appStoreSubmissionSuccessful = await _submitForAppStoreReview(
          buildId: buildId,
          appVersionString: appVersion,
          whatsNew: whatsNew,
          releaseAfterReview: releaseAfterReview,
          releaseType: releaseType,
          scheduledReleaseDate: scheduledReleaseDate,
        );
        if (appStoreSubmissionSuccessful) {
          print('Successfully submitted for App Store Review.');
        } else {
          print('Failed to submit for App Store Review.');
          return false;
        }
      } else {
        print('Submitting build for Beta App Review (TestFlight)...');
        final betaSubmitted = await _submitForBetaReview(buildId, whatsNew);
        if (betaSubmitted) {
          print('Successfully submitted for Beta App Review.');
        } else {
          print('Failed to submit for Beta App Review.');
          return false;
        }
      }
      return true;
    } catch (e, s) {
      print('An error occurred during deployment: $e\n$s');
      return false;
    }
  }

  Future<bool> pollBuildStatus(String buildId) async {
    const maxAttempts = 30; // Max 15 minutes (30 * 30s)
    for (int i = 0; i < maxAttempts; i++) {
      final token = _generateToken();
      final url = Uri.parse('$_apiBaseUrl/builds/$buildId');
      final headers = {'Authorization': 'Bearer $token'};
      final response = await http.get(url, headers: headers);

      if (response.statusCode != 200) {
        print('Polling build status: HTTP ${response.statusCode}. Retrying...');
        if (i < maxAttempts -1) await Future.delayed(Duration(seconds: 30));
        continue;
      }

      final data = json.decode(response.body);
      final processingState = data['data']['attributes']['processingState'];
      print('Build status: $processingState (${i + 1}/$maxAttempts)');

      if (processingState == 'VALID') return true;
      if (processingState == 'FAILED' || processingState == 'INVALID') return false;

      if (i < maxAttempts -1) await Future.delayed(Duration(seconds: 30));
    }
    print('Polling build status timed out.');
    return false;
  }

  // Submits a processed build for Beta App Review (TestFlight)
  Future<bool> _submitForBetaReview(String buildId, String? whatsNew) async {
    if (whatsNew != null && whatsNew.isNotEmpty) {
      final localizationSuccess = await _createBetaBuildLocalization(buildId, whatsNew);
      if (!localizationSuccess) {
        print('Could not add "What\'s New" text to the TestFlight build. Submitting without it.');
      }
    }
    return await _createBetaAppReviewSubmission(buildId);
  }

  Future<bool> _createBetaBuildLocalization(String buildId, String whatsNew) async {
    final token = _generateToken();
    final url = Uri.parse('$_apiBaseUrl/betaBuildLocalizations');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    // Defaulting to en-US for Beta What's New. Consider making this configurable if needed.
    final body = json.encode({
      'data': {
        'type': 'betaBuildLocalizations',
        'attributes': {'whatsNew': whatsNew, 'locale': 'en-US'}, // Default to en-US
        'relationships': {'build': {'data': {'type': 'builds', 'id': buildId}}}
      }
    });
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 201) {
        print('Successfully created beta build localization with What\'s New.');
        return true;
    } else {
        print('Failed to create beta build localization: ${response.statusCode} ${response.body}');
        return false;
    }
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
    if (response.statusCode == 201) {
        print('Successfully created beta app review submission.');
        return true;
    } else {
        print('Failed to create beta app review submission: ${response.statusCode} ${response.body}');
        return false;
    }
  }

  // --- Phase 1: App Store Review Submission --- 

  Future<bool> _submitForAppStoreReview({
    required String buildId,
    required String appVersionString, // e.g., "1.2.3"
    String? whatsNew,
    bool releaseAfterReview = false,
    String? releaseType, // MANUAL, AFTER_APPROVAL, SCHEDULED
    DateTime? scheduledReleaseDate,
  }) async {
    final appId = await _getAppId();
    if (appId == null) return false;

    // 1. Get or Create App Store Version
    String? appStoreVersionId = await _getOrCreateAppStoreVersion(appId, appVersionString, buildId);
    if (appStoreVersionId == null) {
      print('Could not get or create App Store Version.');
      return false;
    }

    // 2. Update "What's New" (appStoreVersionLocalization)
    if (whatsNew != null && whatsNew.isNotEmpty) {
      final localizationUpdated = await _updateAppStoreVersionLocalization(
        appStoreVersionId: appStoreVersionId,
        whatsNew: whatsNew,
        locale: 'en-US', // Phase 1: Default to en-US
      );
      if (!localizationUpdated) {
        print('Warning: Failed to update What\'s New text. Proceeding with submission...');
        // Depending on requirements, you might want to return false here.
      }
    }
    
    // 3. Set Release Type for the App Store Version
    final releaseTypeSet = await _setAppStoreVersionReleaseType(
        appStoreVersionId, 
        releaseType ?? (releaseAfterReview ? 'AFTER_APPROVAL' : 'MANUAL'), 
        scheduledReleaseDate
    );
    if (!releaseTypeSet) {
        print('Failed to set release type for the App Store Version.');
        return false;
    }

    // 4. Create App Store Version Submission
    final submissionCreated = await _createAppStoreVersionSubmission(appStoreVersionId);
    if (!submissionCreated) {
      print('Failed to create App Store Version Submission.');
      return false;
    }

    print('Successfully submitted version $appVersionString for App Store Review.');
    return true;
  }

  Future<String?> _getOrCreateAppStoreVersion(String appId, String versionString, String buildId) async {
    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

    // Check for existing "PREPARE_FOR_SUBMISSION" or "WAITING_FOR_REVIEW" version
    var url = Uri.parse('$_apiBaseUrl/apps/$appId/appStoreVersions?filter[versionString]=$versionString&filter[appStoreState]=PREPARE_FOR_SUBMISSION,WAITING_FOR_REVIEW,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED,INVALID_BINARY&limit=1');
    var response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['data'] != null && data['data'].isNotEmpty) {
        final existingVersion = data['data'][0];
        final existingVersionId = existingVersion['id'] as String;
        final existingBuildId = existingVersion['relationships']?['build']?['data']?['id'];
        print('Found existing App Store Version ($versionString) with ID: $existingVersionId and state: ${existingVersion['attributes']?['appStoreState']}');
        
        // If build is not associated or is different, associate it.
        if (existingBuildId != buildId) {
             print('Associating build $buildId with version $existingVersionId.');
            final buildAssociated = await _associateBuildWithAppStoreVersion(existingVersionId, buildId);
            if (!buildAssociated) {
                print('Failed to associate build $buildId with version $existingVersionId.');
                return null; // Critical failure
            }
        }
        return existingVersionId;
      }
    } else {
      print('Error fetching existing App Store Versions: ${response.statusCode} ${response.body}');
      // Continue to attempt creation if not a critical error
    }

    // If no suitable existing version, create a new one
    print('Creating new App Store Version for $versionString...');
    url = Uri.parse('$_apiBaseUrl/appStoreVersions');
    final body = json.encode({
      'data': {
        'type': 'appStoreVersions',
        'attributes': {
          'platform': 'IOS',
          'versionString': versionString,
        },
        'relationships': {
          'app': {'data': {'type': 'apps', 'id': appId}},
          'build': {'data': {'type': 'builds', 'id': buildId}}
        }
      }
    });

    response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      final newVersionId = data['data']['id'] as String;
      print('Successfully created new App Store Version with ID: $newVersionId and associated build $buildId.');
      return newVersionId;
    } else {
      print('Failed to create App Store Version: ${response.statusCode} ${response.body}');
      return null;
    }
  }

  Future<bool> _associateBuildWithAppStoreVersion(String appStoreVersionId, String buildId) async {
    final token = _generateToken();
    final url = Uri.parse('$_apiBaseUrl/appStoreVersions/$appStoreVersionId/relationships/build');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final body = json.encode({
        'data': {'type': 'builds', 'id': buildId}
    });

    final response = await http.patch(url, headers: headers, body: body);
    if (response.statusCode == 204) { // 204 No Content on success
        print('Successfully associated build $buildId with App Store Version $appStoreVersionId.');
        return true;
    } else {
        print('Failed to associate build: ${response.statusCode} ${response.body}');
        return false;
    }
  }

  Future<bool> _updateAppStoreVersionLocalization(
    {required String appStoreVersionId, required String whatsNew, required String locale}
  ) async {
    final token = _generateToken();
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

    // First, try to get existing localization for this locale.
    // Note: This is simplified. A robust solution would list all localizations and find the target.
    var localizationUrl = Uri.parse('$_apiBaseUrl/appStoreVersions/$appStoreVersionId/appStoreVersionLocalizations?filter[locale]=$locale&limit=1');
    var response = await http.get(localizationUrl, headers: headers);
    String? localizationId;

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['data'] != null && data['data'].isNotEmpty) {
        localizationId = data['data'][0]['id'] as String;
        print('Found existing localization for locale $locale with ID $localizationId');
      }
    } else {
        print('Could not fetch existing localization for $locale: ${response.statusCode} ${response.body}');
        // Not necessarily an error if it doesn't exist, we will create it.
    }

    final attributes = {'whatsNew': whatsNew};
    http.Response updateResponse;

    if (localizationId != null) {
      // Update existing localization
      print('Updating existing What\'s New for locale $locale (ID: $localizationId)...');
      localizationUrl = Uri.parse('$_apiBaseUrl/appStoreVersionLocalizations/$localizationId');
      final body = json.encode({'data': {'type': 'appStoreVersionLocalizations', 'id': localizationId, 'attributes': attributes}});
      updateResponse = await http.patch(localizationUrl, headers: headers, body: body);
    } else {
      // Create new localization
      print('Creating new What\'s New for locale $locale...');
      localizationUrl = Uri.parse('$_apiBaseUrl/appStoreVersionLocalizations');
      final body = json.encode({
        'data': {
          'type': 'appStoreVersionLocalizations',
          'attributes': {...attributes, 'locale': locale},
          'relationships': {
            'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': appStoreVersionId}}
          }
        }
      });
      updateResponse = await http.post(localizationUrl, headers: headers, body: body);
    }

    if (updateResponse.statusCode == 200 || updateResponse.statusCode == 201) {
      print('Successfully updated/created What\'s New for locale $locale.');
      return true;
    } else {
      print('Failed to update/create What\'s New for locale $locale: ${updateResponse.statusCode} ${updateResponse.body}');
      return false;
    }
  }
  
  Future<bool> _setAppStoreVersionReleaseType(String appStoreVersionId, String releaseType, DateTime? scheduledDate) async {
    final token = _generateToken();
    final url = Uri.parse('$_apiBaseUrl/appStoreVersions/$appStoreVersionId');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

    final Map<String, dynamic> attributes = {
        'releaseType': releaseType, // MANUAL, AFTER_APPROVAL, SCHEDULED
    };
    if (releaseType == 'SCHEDULED' && scheduledDate != null) {
        attributes['earliestReleaseDate'] = scheduledDate.toUtc().toIso8601String();
    } else if (releaseType == 'SCHEDULED' && scheduledDate == null) {
        print('Error: Release type is SCHEDULED but no scheduledDate was provided.');
        return false;
    }

    final body = json.encode({
        'data': {
            'type': 'appStoreVersions',
            'id': appStoreVersionId,
            'attributes': attributes,
        }
    });

    final response = await http.patch(url, headers: headers, body: body);
    if (response.statusCode == 200) {
        print('Successfully set release type to $releaseType for version $appStoreVersionId.');
        return true;
    } else {
        print('Failed to set release type: ${response.statusCode} ${response.body}');
        return false;
    }
  }

  Future<bool> _createAppStoreVersionSubmission(String appStoreVersionId) async {
    final token = _generateToken();
    final url = Uri.parse('$_apiBaseUrl/appStoreVersionSubmissions');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    final body = json.encode({
      'data': {
        'type': 'appStoreVersionSubmissions',
        'relationships': {
          'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': appStoreVersionId}}
        }
      }
    });

    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 201) {
      print('Successfully created App Store Version Submission.');
      return true;
    } else {
      print('Failed to create App Store Version Submission: ${response.statusCode} ${response.body}');
      return false;
    }
  }
}
