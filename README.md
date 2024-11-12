simple_deploy is a quick and easy way to deploy apps to the store's test systems

NOTE: This is very much a work-in-progress package at the moment, until it reaches version 1.0

## Features

Deploy to iOS Test Flight
Deploy to Android Play Store Test Track

## Getting started
Install the dependency into your `pubspec.yaml` with the follow

```
dev_dependencies:
  simple_deploy: latest_version # e.g. ^0.20.0
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
  developerId: "76a6aa66-e80a-67e9-e987-6a1c711a4b2            
```

And here's a version will all options set

Here is minimal example version of `deploy.yaml`
```
common:
  versionStrategy: "none" 

android:
  credentialsFile: "c:/credentials/project-credentials.json"   
  packageName: "com.example.coolapp"                           
  trackName: "internal"                                        
  whatsNew: "Simple bug fixes"                                 
  flavor: "flavor"             # optional, don't supply if you are not using flavors   
  generatedFileName: "fancyproject.ipa"                        

ios:
  teamKeyId: "ABCD1A4A12"                                      
  developerId: "76a6aa66-e80a-67e9-e987-6a1c711a4b2            
  flavor: "flavor"             # optional, don't supply if you are not using flavors  
  generatedFileName: "fancyproject.aab"                                                             
```


####Parameter details
| `flavor` | Description                                                                                               |
|------------------------|-----------------------------------------------------------------------------------------------------------|
| `flavorName`                 | Optional parameter, which can be set for both `android` and `iOS`, don't supply if not using flavors, or provide the flavor name if using them |                                                                  |




| `versionStrategy` | Description                                                                                               |
|------------------------|-----------------------------------------------------------------------------------------------------------|
| `none`                 | Default. Uses the current value in the `pubspec`.                                                         |
| `pubspecIncrement`     | Retrieves the current build number from the `pubspec`, increments it by one, and uses the updated number. |



| `trackName` | Description                             |
|------------------|-----------------------------------------|
| `internal`       | Default. Deploys to the internal track. |
| `alpha`          | Deploys to the alpha track.             |
| `beta`           | Deploys to the beta track.              |
| `production`     | Deploys to the production track.        |

Here's the step-by-step instructions for configuring for each platform

[Android configuration](https://github.com/andrewpmoore/simple_deploy/blob/main/android.md)

[iOS configuration](https://github.com/andrewpmoore/simple_deploy/blob/main/ios.md)

## Usage

Just run `dart run simple_deploy` and select the deployment platform

You can also supply the platform with 
 - `dart run simple_deploy android`
 - `dart run simple_deploy ios`

If you are using flavors you can add them here, they will override what is set in the pubspec.yaml, for example
 - `dart run simple_deploy android --flavor flavorName`

## Additional information
You'll need to get some developer details from App Store connect for the deploy.yaml file
You will also need to set up a google cloud project to create the `.json` file required for android.
See steps below of these:

### Android configuration
[Android configuration](https://github.com/andrewpmoore/simple_deploy/blob/main/android.md)

### iOS configuration
[iOS configuration](https://github.com/andrewpmoore/simple_deploy/blob/main/ios.md)


### Contributions
Thanks to the following people for their great contributions to this project
[KarlJan Reginaldo](https://github.com/karlreginaldo)    