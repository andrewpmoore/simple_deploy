### `ios.md`

```markdown
## Steps for configuring iOS deployment

To deploy to Test Flight and optionally submit for App Store review, follow the steps below.

<ol>
<li>Please go to <a href="https://appstoreconnect.apple.com/">App Store connect</a> and log in.</li>
<li>At the top right hand corner, click on your name and then <code>Edit profile</code>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/apple0001.png" width="100%"/>

<li>Find the **Issuer ID** and make a note of it, this needs to be set in the `deploy.yaml` as the `issuerId` property</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/apple0002.png" width="100%"/>

<li>Go to **Users and access**, **Integrations**, **Team Keys** then click on the **+** to add a key.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/apple0003.png" width="100%"/>

<li>Give the Key a `name` and set the access to `App Manager` and press **Generate**.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/apple0004.png" width="100%"/>

<li>Copy the **Key ID** and place it into the `keyId` in the `deploy.yaml` and press **Download** to download the private key</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/apple0005.png" width="100%"/>

</ol>

Place the downloaded file onto your build machine and set the path to this file as `privateKeyPath` in your `deploy.yaml`. For example, `privateKeyPath: "path/to/your/AuthKey_XXXXXXXXXX.p8"`.

### Configuration for App Store Submission

To enable submitting your app for App Store review (not just TestFlight beta review), you'll use the `--submit-review` flag. You can also control how the app is released after approval.

**`deploy.yaml` Configuration:**

Add or update the following keys in the `ios` section of your `deploy.yaml` file:

```yaml
ios:
  # ... existing App Store Connect API configuration (issuerId, keyId, privateKeyPath) ...
  bundleId: "com.example.coolapp"          # Required: Your app's bundle ID.
  whatsNew: "New features and improvements" # Optional: Default "What's New" text for the submission.
                                          # This is currently applied to the 'en-US' localization.
  # New keys for App Store Release Management:
  releaseAfterReview: false               # Optional (boolean, defaults to false): 
                                          #   Set to true to automatically release the app after approval.
  releaseType: "MANUAL"                   # Optional (String, defaults to MANUAL if releaseAfterReview is true, otherwise not set): 
                                          #   How the app should be released.
                                          #   Valid values:
                                          #     "MANUAL" - Requires manual release from App Store Connect.
                                          #     "AFTER_APPROVAL" - Releases automatically once Apple approves it.
                                          #     "SCHEDULED" - Releases on a specific date/time after approval.
  scheduledReleaseDate: null              # Optional (String: ISO 8601 format, e.g., "YYYY-MM-DDTHH:MM:SS.sssZ"):
                                          #   The date for a scheduled release. Only used if releaseType is "SCHEDULED".
  # ... other existing iOS configurations (flavor, generatedFileName, autoIncrementMarketingVersion) ...
```

**Command-Line Usage:**

To build, upload, and submit your iOS app for App Store review:

```bash
dart run simple_deploy ios --submit-review
```

**Overriding Release Options via Command Line:**

You can override the `deploy.yaml` settings for release management using these command-line flags:

*   `--ios-release-after-review`:
    *   If this flag is present, it sets `releaseAfterReview` to `true`.
    *   If omitted, the value from `deploy.yaml` (or the default `false`) is used.
    *   Example: `dart run simple_deploy ios --submit-review --ios-release-after-review`

*   `--ios-release-type="<TYPE>"`:
    *   Sets the release type. Replace `<TYPE>` with `MANUAL`, `AFTER_APPROVAL`, or `SCHEDULED`.
    *   Example: `dart run simple_deploy ios --submit-review --ios-release-type="AFTER_APPROVAL"`

*   `--ios-scheduled-release-date="<ISO_DATE_STRING>"`:
    *   Sets the scheduled release date if `--ios-release-type` is `SCHEDULED`.
    *   The date must be in ISO 8601 format (e.g., `2023-12-25T10:00:00.000Z`).
    *   Example: `dart run simple_deploy ios --submit-review --ios-release-type="SCHEDULED" --ios-scheduled-release-date="2024-01-15T09:00:00Z"`

**Process:**

When using `--submit-review` for iOS with App Store submission enabled (which is the new default behavior for `--submit-review`):

1.  Builds your IPA.
2.  Uploads the IPA to App Store Connect.
3.  Waits for the build to finish processing.
4.  Submits the build for App Store review, using the "What's New" text and release settings from your `deploy.yaml` or command-line overrides.
    *   **"What's New" Localization:** Currently, the "What's New" text is applied to the `en-US` localization. Future enhancements will support more languages.

<b>If you are having problems</b>
Ensure that `flutter build ios` is working correctly as a command at the root of your project and resolve any errors associated with that. Also, ensure your App Store Connect API key has "App Manager" permissions.

```