simple_deploy is a quick and easy way to deploy apps to the store's test systems and for App Store review.


## Features

Deploy to iOS Test Flight and submit for App Store review
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
  # App Store Connect API configuration (All fields are required)
  issuerId: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  keyId: "XXXXXXXXXX"
  privateKeyPath: "path/to/your/AuthKey_XXXXXXXXXX.p8"
  bundleId: "com.example.coolapp"
  
  # Optional fields for TestFlight and App Store Submission
  whatsNew: "New features and improvements" # "What's New" text
  flavor: "production"                   # Omit if not using flavors
  generatedFileName: "custom_name.ipa"   # Omit to use the default ipa name
  # Optional fields for App Store Release Management (used when submitting for review)
  releaseAfterReview: false               # true to automatically release after approval
  releaseType: "MANUAL"                   # MANUAL, AFTER_APPROVAL, or SCHEDULED
  scheduledReleaseDate: null              # ISO 8601 date string for SCHEDULED release
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
  # App Store Connect API configuration
  issuerId: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # App Store Connect API Issuer ID
  keyId: "XXXXXXXXXX"  # App Store Connect API Key ID
  privateKeyPath: "path/to/AuthKey_XXXXXXXXXX.p8"  # Path to your private key file
  bundleId: "com.example.coolapp"  # Required for App Store submission
  
  # Optional fields for TestFlight and App Store Submission
  whatsNew: "New features and improvements"
  flavor: "flavor"            # specify a flavor if required, or omit if not using flavors
  generatedFileName: "fancyproject.ipa"         # supply a custom file name for the ipa, or omit if using the default
  autoIncrementMarketingVersion: false # defaults to false, updates the first part of the 'version' in the pubspec.yaml, e.g. 1.0.15+39 (it would increment to 1.0.16)

  # Optional fields for App Store Release Management (used with --submit-review)
  releaseAfterReview: false               # Set to true to automatically release the app after approval.
  releaseType: "MANUAL"                   # How the app should be released: MANUAL, AFTER_APPROVAL, SCHEDULED.
  scheduledReleaseDate: null              # The date for a scheduled release (ISO 8601 format, e.g., "YYYY-MM-DDTHH:MM:SS.sssZ"). Used if releaseType is "SCHEDULED".
```

#### Parameter details

| `flavor`     | Description                                                                                                                                    |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | --- |
| `flavorName` | Optional parameter, which can be set for both `android` and `iOS`, don't supply if not using flavors, or provide the flavor name if using them |     |

| `versionStrategy`  | Description                                                                                                                            |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| `none`             | Default. Uses the current value in the `pubspec`.                                                                                      |
| `pubspecIncrement` | Retrieves the current build number from the `pubspec`, increments it by one, and uses the updated number.                              |
| `storeIncrement`   | Gets the latest version code from the store (Play Store for Android or App Store Connect for iOS build number), increments it by one, and updates the pubspec. |

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
- `dart run simple_deploy ios --submit-review` # Builds, uploads to TestFlight, then submits the build for App Store review.

**iOS App Store Release Options (used with `--submit-review`):**

- `dart run simple_deploy ios --submit-review --ios-release-after-review` # Release automatically after Apple's approval.
- `dart run simple_deploy ios --submit-review --ios-release-type="AFTER_APPROVAL"` # Same as above.
- `dart run simple_deploy ios --submit-review --ios-release-type="MANUAL"` # Default, requires manual release from App Store Connect.
- `dart run simple_deploy ios --submit-review --ios-release-type="SCHEDULED" --ios-scheduled-release-date="YYYY-MM-DDTHH:MM:SSZ"` # Schedule release for a specific date (UTC).

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
