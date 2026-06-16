---
name: mobile-background-location
description: Foreground service vs ACCESS_BACKGROUND_LOCATION and the iOS UIBackgroundModes runtime trap. Use when writing or reviewing Flutter/geolocator code that must keep receiving GPS positions while backgrounded / screen off.
origin: extracted-from-session-2026-06-15
---

# Mobile background location: foreground service vs ACCESS_BACKGROUND_LOCATION

## When to Activate
Reviewing or writing any Flutter/geolocator code that must keep receiving GPS
positions while the app is backgrounded or the screen is off (walk tracking,
fitness, navigation).

## Rules / Checklist
- **Android — prefer a foreground service, not background-location permission.**
  Configure geolocator's `AndroidSettings.foregroundNotificationConfig` so it runs a
  location-typed foreground service (visible notification). This keeps the stream
  alive with the screen off and **does not require `ACCESS_BACKGROUND_LOCATION`** —
  omitting it keeps you out of Google Play's background-location declaration/review
  policy. Declare `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION`.
- **iOS — `allowBackgroundLocationUpdates: true` throws at runtime without
  `UIBackgroundModes: location` in `Info.plist`.** CI/unit tests will not catch this.
  When reviewing a PR that sets it, verify `Info.plist` directly (also needs
  `NSLocationWhenInUseUsageDescription`; add `NSLocationAlwaysAndWhenInUseUsageDescription`
  for "Always"). Set `pauseLocationUpdatesAutomatically: false` and
  `showBackgroundLocationIndicator: true`.
- **Make settings selection pure and testable.** A `buildSettings(platform)` returning
  the right `AndroidSettings`/`AppleSettings`/`LocationSettings` is unit-testable per
  platform; real background behavior needs on-device QA (FGS notification clears on
  stop; battery from `enableWakeLock: true`).
- **Store consoles (not code):** App Store App Privacy + Play Data safety must declare
  location collection before release — flag these; not verifiable from the repo.
