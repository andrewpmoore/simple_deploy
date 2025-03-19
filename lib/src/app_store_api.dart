import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class AppStoreApiClient {
  final String issuerId;
  final String keyId;
  final String privateKeyPath;
  final String bundleId;

  AppStoreApiClient({
    required this.issuerId,
    required this.keyId,
    required this.privateKeyPath,
    required this.bundleId,
  });

  /// Generates a JWT token for authentication
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

    return jwt.sign(
      ECPrivateKey(privateKey),
      algorithm: JWTAlgorithm.ES256,
    );
  }

  /// Gets the latest build number from TestFlight
  Future<int> getLatestBuildNumber() async {
    try {
      final token = _generateToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      // First get the app ID using the bundle ID
      final appsUrl = Uri.parse(
          'https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=$bundleId');
      final appsResponse = await http.get(appsUrl, headers: headers);

      if (appsResponse.statusCode != 200) {
        print('Failed to get app: ${appsResponse.body}');
        return 0;
      }

      final appsData = json.decode(appsResponse.body);
      if (appsData['data'] == null || appsData['data'].isEmpty) {
        print('No app found with bundle ID: $bundleId');
        return 0;
      }

      final appId = appsData['data'][0]['id'];

      // Get the builds for this app
      final buildsUrl = Uri.parse(
          'https://api.appstoreconnect.apple.com/v1/builds?filter[app]=$appId&sort=-version&limit=1');
      final buildsResponse = await http.get(buildsUrl, headers: headers);

      if (buildsResponse.statusCode != 200) {
        print('Failed to get builds: ${buildsResponse.body}');
        return 0;
      }

      final buildsData = json.decode(buildsResponse.body);
      if (buildsData['data'] == null || buildsData['data'].isEmpty) {
        print('No builds found for app');
        return 0;
      }

      // The version attribute contains the build number
      final latestBuild = buildsData['data'][0];
      final buildNumber =
          int.tryParse(latestBuild['attributes']['version'] ?? '0') ?? 0;

      print('Latest build number from TestFlight: $buildNumber');
      return buildNumber;
    } catch (e) {
      print('Error getting latest build number from TestFlight: $e');
      return 0;
    }
  }
}
