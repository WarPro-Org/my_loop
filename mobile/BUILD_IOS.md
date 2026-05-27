# MyLoop — iOS Build Guide

## Prerequisites (on your MacBook)

1. **Install Xcode** from the App Store (requires macOS 14+)
2. **Install Flutter**:
   ```bash
   git clone https://github.com/flutter/flutter.git -b stable ~/flutter
   echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   flutter doctor
   ```
3. **Accept Xcode license**:
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app
   sudo xcodebuild -license accept
   ```
4. **Install CocoaPods** (needed for Firebase + plugins):
   ```bash
   sudo gem install cocoapods
   ```

## Transfer Project to Mac

Copy the `C:\Workspace\MyLoop\mobile` folder to your Mac using:
- USB drive
- AirDrop
- Git (recommended): push to a repo and clone on Mac

## Firebase Setup (Required for Auth)

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a new project called "MyLoop"
3. **Add iOS app**:
   - Bundle ID: `com.myloop.myloop`
   - App nickname: MyLoop iOS
4. Download `GoogleService-Info.plist`
5. Place it in `mobile/ios/Runner/GoogleService-Info.plist`
6. In Firebase Console → **Authentication → Sign-in method**:
   - Enable **Google** (add your iOS client ID from GoogleService-Info.plist)
   - Enable **Apple** (requires Apple Developer account)

### Apple Sign-In Setup
1. Go to [Apple Developer](https://developer.apple.com)
2. Under Certificates → Identifiers → your app ID → enable "Sign In with Apple"
3. Under Keys → create a key with "Sign In with Apple" enabled
4. Add the key to Firebase Console → Authentication → Apple provider

## Build & Run

```bash
cd ~/path-to/mobile

# Get dependencies
flutter pub get

# Install iOS native dependencies
cd ios && pod install && cd ..

# List available devices
flutter devices

# Run on connected iPhone (USB)
flutter run

# Or run on simulator
open -a Simulator
flutter run
```

## Install on Physical iPhone

### Option A: Development build (free, lasts 7 days)
1. Connect iPhone via USB cable
2. In Xcode: open `ios/Runner.xcworkspace`
3. Sign in with your Apple ID (Xcode → Settings → Accounts)
4. Select your team under Runner → Signing & Capabilities
5. Select your iPhone as the target device
6. Press ▶️ Run (or use `flutter run`)
7. On iPhone: Settings → General → VPN & Device Management → Trust your developer profile

### Option B: TestFlight (requires $99/year Apple Developer account)
```bash
flutter build ipa
```
Then upload the `.ipa` file via Xcode → Distribute App → TestFlight.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "No signing certificate" | Xcode → Settings → Accounts → add Apple ID |
| Pod install fails | `cd ios && pod deintegrate && pod install` |
| "Untrusted Developer" on iPhone | Settings → General → VPN & Device Management → Trust |
| Firebase crash on launch | Ensure `GoogleService-Info.plist` is in `ios/Runner/` |
| Google Sign-In redirect fails | Add reversed client ID to URL schemes in Info.plist |

## URL Schemes (after Firebase setup)

After downloading `GoogleService-Info.plist`, add the reversed client ID to your URL schemes:

1. Open `ios/Runner/Info.plist`
2. Add under `<dict>`:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>YOUR_REVERSED_CLIENT_ID_FROM_GOOGLE_SERVICE_INFO</string>
    </array>
  </dict>
</array>
```
