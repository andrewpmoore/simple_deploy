import 'dart:io';

import 'package:yaml/yaml.dart';

// Load configuration from a YAML file, with support for dart-define overrides
Future<Map<String, dynamic>?> loadConfig(String workingDirectory, String section) async {
  final configFile = File('$workingDirectory/deploy.yaml');
  if (!await configFile.exists()) {
    print('Info: deploy.yaml not found at ${configFile.path}. Skipping its configuration.');
    // Return an empty map if no config file, so dart-defines can still work
    return {};
  }
  final configContent = await configFile.readAsString();
  final YamlMap fullYamlMap;
  try {
    fullYamlMap = loadYaml(configContent) as YamlMap;
  } catch (e) {
    print('Error parsing deploy.yaml: $e');
    return null; // Indicate error
  }

  final dynamic sectionYaml = fullYamlMap[section];

  final Map<String, dynamic> sectionMap = {};
  if (sectionYaml is YamlMap) {
    sectionYaml.forEach((key, value) {
      sectionMap[key.toString()] = value;
    });
  } else if (sectionYaml != null) {
    // Section exists but is not a map, this might be an error depending on expected structure
    print('Warning: Section "$section" in deploy.yaml is not a map.');
  }

  // Define a map of YAML keys to their corresponding dart-define environment variable names
  Map<String, String> defineOverrides = {};
  final String sectionUpper = section.toUpperCase();

  if (section == 'common') {
    defineOverrides = {
      'versionStrategy': 'SIMPLE_DEPLOY_${sectionUpper}_VERSION_STRATEGY',
    };
  } else if (section == 'android') {
    defineOverrides = {
      'credentialsFile': 'SIMPLE_DEPLOY_${sectionUpper}_CREDENTIALS_FILE',
      'packageName': 'SIMPLE_DEPLOY_${sectionUpper}_PACKAGE_NAME',
      'trackName': 'SIMPLE_DEPLOY_${sectionUpper}_TRACK_NAME',
      'whatsNew': 'SIMPLE_DEPLOY_${sectionUpper}_WHATS_NEW',
      'flavor': 'SIMPLE_DEPLOY_${sectionUpper}_FLAVOR',
      'generatedFileName': 'SIMPLE_DEPLOY_${sectionUpper}_GENERATED_FILE_NAME',
    };
  } else if (section == 'ios') {
    defineOverrides = {
      'issuerId': 'SIMPLE_DEPLOY_${sectionUpper}_ISSUER_ID',
      'keyId': 'SIMPLE_DEPLOY_${sectionUpper}_KEY_ID',
      'privateKeyPath': 'SIMPLE_DEPLOY_${sectionUpper}_PRIVATE_KEY_PATH',
      'bundleId': 'SIMPLE_DEPLOY_${sectionUpper}_BUNDLE_ID',
      'whatsNew': 'SIMPLE_DEPLOY_${sectionUpper}_WHATS_NEW',
      'flavor': 'SIMPLE_DEPLOY_${sectionUpper}_FLAVOR',
      'generatedFileName': 'SIMPLE_DEPLOY_${sectionUpper}_GENERATED_FILE_NAME',
      'autoIncrementMarketingVersion': 'SIMPLE_DEPLOY_${sectionUpper}_AUTO_INCREMENT_MARKETING_VERSION',
      'releaseAfterReview': 'SIMPLE_DEPLOY_${sectionUpper}_RELEASE_AFTER_REVIEW',
      'releaseType': 'SIMPLE_DEPLOY_${sectionUpper}_RELEASE_TYPE',
      'scheduledReleaseDate': 'SIMPLE_DEPLOY_${sectionUpper}_SCHEDULED_RELEASE_DATE',
    };
  }

  // Apply overrides from dart-defines
  defineOverrides.forEach((yamlKey, defineKey) {
    const String defaultValue = ''; // String.fromEnvironment needs a const default.
    final defineValue = String.fromEnvironment(defineKey, defaultValue: defaultValue);

    if (defineValue != defaultValue) { // Check if the define was actually provided
      dynamic parsedValue = defineValue;
      // Handle boolean conversions for specific keys
      if (yamlKey == 'autoIncrementMarketingVersion' || yamlKey == 'releaseAfterReview') {
        if (defineValue.toLowerCase() == 'true') {
          parsedValue = true;
        } else if (defineValue.toLowerCase() == 'false') {
          parsedValue = false;
        } else {
          print('Warning: Invalid boolean value "$defineValue" for dart-define $defineKey. Using raw string value.');
        }
      }
      sectionMap[yamlKey] = parsedValue;
      print('Info: Overridden $section.$yamlKey with value from dart-define $defineKey.');
    }
  });

  return sectionMap;
}

Future<bool> flutterClean(String workingDirectory) async {
  print('Clean the project');
  var result = await Process.run('flutter', ['clean'],
      workingDirectory: workingDirectory, runInShell: true);
  if (result.exitCode != 0) {
    print('flutter clean failed: ${result.stderr}');
    return false;
  }
  return true;
}
