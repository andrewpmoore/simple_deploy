## 1.0.0-dev.3
- Added `versionStrategy: "storeIncrement"` which will get the current store build number and increment it by 1
- Added support for submitting iOS apps directly to App Store review
- Added `bundleId` requirement for iOS configuration
- Added optional `whatsNew` text for App Store submissions
- Fixed documentation to correctly reference `deploy.yaml` instead of `pubspec.yaml`

## 0.25.0

- Decreased the minimum dart version

## 0.24.0

- Document improvements

## 0.23.0

- Document improvements

## 0.22.0

- Document improvements

## 0.21.0

- Added support for custom build names

## 0.20.0

- Added support for flavors

## 0.19.0

- Merged pull request to fix bug and add animated cursor, thanks KarlJan Reginaldo

## 0.18.0

- Better validation if the deploy.yaml is missing parameters

## 0.17.0

- Fix for script continuing if versionStrategy was invalid

## 0.16.0

- Bug fixes

## 0.15.0

- Added the `versionStrategy` so it can auto increment the pubspec.yaml build number on each run

## 0.14.0

- Added the ability to add the track to android builds

## 0.13.0

- Document improvements

## 0.12.0

- Added android documentation for configuration
- Changed the iOS properties to match what they are called in app store connect

## 0.11.0

- Attempt to fix deployments on iOS not working

## 0.10.0

- Shared some code across iOS and Android builds that is common
- Added to documentation
- Fix for ios paths not working

## 0.9.0

- Improved documentation

## 0.8.0

- Show that android is auto selected if not on a mac

## 0.7.0

- bug fixes on mac check

## 0.6.0

- Auto deploy to android if not on a mac (as it's the only option)
- If passing parameter of `ios` and not on a mac, show an error

## 0.5.0

- Fix file checking for deploy.yaml

## 0.4.0

- Tidy and check for whether a deploy.yaml file exists before trying to deploy
- Improve input layout if using the interactive prompt

## 0.3.0

- More fixes

## 0.2.0

- Some fixes

## 0.1.0

- Initial version experiment
