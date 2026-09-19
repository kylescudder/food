# iOS TestFlight CI

GitHub Actions builds and tests Food for iOS when a pull request changes the
app. Every qualifying push to `main` archives the app and uploads it to
TestFlight. Both workflows can also be run manually from the Actions tab.

The workflows live at
[`ios-build.yml`](../.github/workflows/ios-build.yml) and
[`ios-testflight.yml`](../.github/workflows/ios-testflight.yml).

## One-time setup

### 1. App Store Connect API key

1. In App Store Connect, open **Users and Access → Integrations → App Store
   Connect API**, then generate an API key.
2. Give the key **App Manager** access.
3. Download its `.p8` file and record the Issuer ID and Key ID.

An existing App Store Connect key used by another app on the same Apple team
can be reused.

### 2. App ID, CloudKit, and signing

Create or confirm the explicit App ID `org.thescudders.food` under the same team as
`APPLE_TEAM_ID`. Enable the capabilities used by `Food/Food.entitlements`:

- iCloud with CloudKit container `iCloud.com.kyle.food`
- Push Notifications

Create an App Store Connect app using bundle ID `org.thescudders.food`. Create an App
Store provisioning profile for that identifier with the exact display name
`org.thescudders.food`. The profile must include the app's iCloud and push
capabilities. Export an Apple Distribution certificate as a password-protected
`.p12` file.

Before uploading the first release, initialize the CloudKit development schema
and deploy it to Production as described in the main README.

### 3. GitHub Actions secrets

Add these repository secrets under **Settings → Secrets and variables →
Actions**:

| Secret name | Value |
|---|---|
| `APP_STORE_CONNECT_API_KEY_P8` | Full contents of the `AuthKey_XXXXXXXXXX.p8` file |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | App Store Connect Issuer ID UUID |
| `APPLE_TEAM_ID` | 10-character Apple Developer Team ID |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded `.p12` Apple Distribution certificate |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` certificate |
| `IOS_FOOD_PROFILE_BASE64` | Base64-encoded provisioning profile named `org.thescudders.food` |
| `IOS_KEYCHAIN_PASSWORD` | A strong temporary CI keychain password |

The API key and distribution certificate secrets can reuse the values from the
other iOS repositories on the same team. The Food provisioning profile is
app-specific.

To encode the binary signing files on macOS:

```sh
base64 -i org.thescudders.food.mobileprovision | pbcopy
base64 -i Distribution.p12 | pbcopy
```

### 4. First run

1. Run **iOS · Build** manually to verify the project against the current Xcode
   runner.
2. Run **iOS · TestFlight** manually against `main`.
3. Confirm the build finishes processing in App Store Connect and is available
   to the intended internal testing group.

After that succeeds, qualifying pushes to `main` upload automatically.

## Maintenance

- Bump `MARKETING_VERSION` in `Food.xcodeproj/project.pbxproj` when the public
  app version changes.
- CI uses the GitHub run number as `CURRENT_PROJECT_VERSION`, giving each
  TestFlight upload a unique build number.
- Rotate the App Store Connect key by updating the three
  `APP_STORE_CONNECT_API_KEY_*` secrets.
- Rotate signing assets by replacing the certificate or provisioning-profile
  secrets. Keep the profile name `org.thescudders.food` unless the Xcode project,
  export options, and workflow are updated together.
