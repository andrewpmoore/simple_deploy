simple_deploy is a quick and easy way to deploy apps to the store's test systems

NOTE: This is very much a work-in-progress package at the moment, until it reaches version 1.0

## Features

Deploy to iOS Test Flight
Deploy to Android Play Store tracks of your choice
Supports flavors

## Getting started

Install the dependency into your `pubspec.yaml` with the following:

```
dev_dependencies:
  simple_deploy: latest_version # e.g. ^0.23.0
```

Create a `deploy.yaml` file at the root of your project and configure it

Here is minimal example version of `deploy.yaml`

```
android:
  credentialsFile: "c:/credentials/project-credentials.json"
  packageName: "com.example.coolapp"
  whatsNew: "Simple bug fixes"

ios:
  teamKeyId: "ABCD1A4A12"
  developerId: "76a6aa66-e80a-67e9-e987-6a1c711a4b2"
  bundleId: "com.example.coolapp"  # Required for App Store submission
  whatsNew: "New features and improvements"  # Optional, used for App Store submission
  flavor: "flavor"            # specify a flavor if required, or omit if not using flavors
  generatedFileName: "fancyproject.ipa"         # supply a custom file name for the ipa, or omit if using the default
  # App Store Connect API configuration (required for storeIncrement version strategy)
  issuerId: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # App Store Connect API Issuer ID
  keyId: "XXXXXXXXXX"  # App Store Connect API Key ID
  privateKeyPath: "path/to/AuthKey_XXXXXXXXXX.p8"  # Path to your private key file
```

And here's a version with all options set:

```
common:
  versionStrategy: "none"  # or "pubspecIncrement" or "storeIncrement"

android:
  credentialsFile: "c:/credentials/project-credentials.json"
  packageName: "com.example.coolapp"
  trackName: "internal"
  whatsNew: "Simple bug fixes"
  flavor: "flavor"            # specify a flavor if required, or omit if not using flavors
  generatedFileName: "fancyproject.aab"       # supply a custom file name for the aab, or omit if using the default

ios:
  teamKeyId: "ABCD1A4A12"
  developerId: "76a6aa66-e80a-67e9-e987-6a1c711a4b2"
  bundleId: "com.example.coolapp"  # Required for App Store submission
  whatsNew: "New features and improvements"  # Optional, used for App Store submission
  flavor: "flavor"            # specify a flavor if required, or omit if not using flavors
  generatedFileName: "fancyproject.ipa"         # supply a custom file name for the ipa, or omit if using the default
  # App Store Connect API configuration (required for storeIncrement version strategy)
  issuerId: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # App Store Connect API Issuer ID
  keyId: "XXXXXXXXXX"  # App Store Connect API Key ID
  privateKeyPath: "path/to/AuthKey_XXXXXXXXXX.p8"  # Path to your private key file
```

#### Parameter details

| `flavor`     | Description                                                                                                                                    |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | --- |
| `flavorName` | Optional parameter, which can be set for both `android` and `iOS`, don't supply if not using flavors, or provide the flavor name if using them |     |

| `versionStrategy`  | Description                                                                                                                            |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| `none`             | Default. Uses the current value in the `pubspec`.                                                                                      |
| `pubspecIncrement` | Retrieves the current build number from the `pubspec`, increments it by one, and uses the updated number.                              |
| `storeIncrement`   | Gets the latest version code from the store (Play Store for Android), increments it by one, and updates the pubspec. For Android only. |

| `trackName`  | Description                             |
| ------------ | --------------------------------------- |
| `internal`   | Default. Deploys to the internal track. |
| `alpha`      | Deploys to the alpha track.             |
| `beta`       | Deploys to the beta track.              |
| `production` | Deploys to the production track.        |

Here's the step-by-step instructions for configuring for each platform

[Android configuration](https://github.com/andrewpmoore/simple_deploy/blob/main/android.md)

[iOS configuration](https://github.com/andrewpmoore/simple_deploy/blob/main/ios.md)

## Usage

Just run `dart run simple_deploy` and select the deployment platform

You can also supply the platform with

- `dart run simple_deploy android`
- `dart run simple_deploy ios`
- `dart run simple_deploy ios --submit-review` # This will also submit to App Store review after TestFlight processing

If you are using flavors you can add them here, they will override what is set in the pubspec.yaml, for example

- `dart run simple_deploy android --flavor flavorName`

You can use the `--pubspecIncrement` flag to increment the build number for a specific deployment, regardless of the `versionStrategy` setting in your `deploy.yaml`:

- `dart run simple_deploy --pubspecIncrement`

This flag will override the `versionStrategy` setting just for that deployment, allowing you to increment the build number only when needed.

## Additional information

You'll need to get some developer details from App Store connect for the `deploy.yaml` file
You will also need to set up a google cloud project to create the `.json` file required for android.
See steps below of these:

### Android configuration

[Android configuration](https://github.com/andrewpmoore/simple_deploy/blob/main/android.md)

### iOS configuration

[iOS configuration](https://github.com/andrewpmoore/simple_deploy/blob/main/ios.md)

### Contributions

Thanks to the following people for their great contributions to this project
[KarlJan Reginaldo](https://github.com/karlreginaldo)
