## Steps for configuring Android deployment

To deploy to the Play Store, follow the steps below.

A Google Service Account is required to upload your binary to Google Play Store. This JSON key must be added to your account to publish apps to Google Play.

<ol>
<li>Please go to <a href="https://console.cloud.google.com/apis/dashboard">Google Cloud Platform</a> and create a Google Cloud Project if you don't already have one.</li>

<li><b>Enable</b> the <code>Google Play Android Developer API</code> for your Google Cloud Project.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service00.01.png" width="100%"/>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service00.02.png" width="100%"/>

<li>Login with your account, then go to <b>Credentials</b> -> <b>Create Credentials</b>, and click <b>Service account</b>.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service01.png" width="100%"/>

<li>This screen will forward you to the <b>Create service account</b> page. Fill in the details of your service account. Based on the service name, an automatic <b>Service account ID</b> will be created. <b>Make a note of the email address created here as it will be required later on in the process.</b></b></li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service03.png" width="100%"/>

<li>Select <code>Editor</code> in the Role dropdown</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service04.png" width="100%"/>

<li>Click <b>Done</b> to save this account.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service05.png" width="100%"/>

<li>Click <b>Manage service accounts</b> to open the management page.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service05-1.png" width="100%"/>

<li>Find the account you just created. Click the three dots in the Actions column, then click <b>Manage keys</b>.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service06.png" width="100%"/>

<li>Click <b>ADD KEY</b> and then click <b>Create new key</b>.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service07.png" width="100%"/>

<li>Download your key as JSON and save it.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service08.png" width="100%"/>

<li>Go to <a href="https://play.google.com/console/developers">Google Play Console</a> and login with your account. Go to <b>User and permissions</b> and click <b>Invite new users</b>.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service09-2.png" width="100%"/>

<li>Add the email generated in step 7 in the <b>Email address</b> field.</li>

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service12.png" width="100%"/>

<li>Check your user's permissions.

<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service11-1.png" width="100%"/>

Make sure this account has access to <b>Releases</b>, <b>Store presence</b>, and <b>App access</b>.
<img src="https://raw.githubusercontent.com/andrewpmoore/simple_deploy/main/images/google-service11.png" width="100%"/>

Then click <b>Invite User</b>. Your account key is ready. 🎉

</li>

<li>Your account is now ready. Save the <code>.json</code> file created into a secure location on your build machine. Don't check it into a public version control system.</li>

<li>Configure your <code>deploy.yaml</code> file's <code>credentialsFile</code> property to point at the downloaded file's path from the step above.</li>

<li>Set your <code>packageName</code> to match the package name declared in your <code>\android\app\build.gradle</code></li>

<li>Specify what's new in this build in the <code>whatsNew</code> field of your <code>deploy.yaml</code>.</li>

</ol>

<b>If you are having problems</b>  
Ensure that `flutter build appbundle` is working correctly as a command at the root of your project and resolve any errors associated with that.
