# Privacy Manifest (`PrivacyInfo.xcprivacy`)

Apple requires a privacy manifest for apps whose code or SDKs use "required-reason APIs"
(since 2024-05-01). Missing/incomplete manifests are auto-rejected (ITMS-91053). This file
documents what MyLoop must declare and why.

## Location of the file

`mobile/ios/Runner/PrivacyInfo.xcprivacy` — **currently missing, must be added.**

## What to declare

### `NSPrivacyTracking`
`false` — MyLoop runs no ads, no third-party tracking, no data brokers (consistent with the
published Privacy Policy). Declaring `false` avoids App Tracking Transparency prompts.

### `NSPrivacyCollectedDataTypes`

| Data type | Linked to user | Tracking | Purpose |
|-----------|----------------|----------|---------|
| Precise Location | Yes | No | App Functionality (record walks, claim territory) |
| Name | Yes | No | App Functionality (display name; from SiwA/Google) |
| Email Address | Yes | No | App Functionality / Account (from SiwA/Google) |
| User ID | Yes | No | App Functionality (Firebase UID) |

### `NSPrivacyAccessedAPITypes`

Declare the required-reason APIs the bundled SDKs use, with the documented reason codes:

| API category | Reason | Used by |
|--------------|--------|---------|
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Firebase, plugins |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | path_provider, Firebase |
| `NSPrivacyAccessedAPICategoryDiskSpace` | `E174.1` | Firebase |
| `NSPrivacyAccessedAPICategorySystemBootTime` | `35F9.1` | Firebase |

> Confirm the exact set against the versions in `pubspec.lock` — recent Firebase / geolocator
> / path_provider pods ship their **own** manifests, but the app-level manifest must still
> declare app-level data collection and any reason-APIs your own code calls.

## Verification before archive

- `PrivacyInfo.xcprivacy` present in the Runner target and included in the build.
- App Store Connect "App Privacy" answers match this table (location, name, email, user id;
  no tracking).
- No `NSAllowsArbitraryLoads` in `Info.plist` (would trigger ATS review questions).
