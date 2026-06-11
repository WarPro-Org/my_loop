# Apple App Store Review Checklist (Phase 1)

Status legend: ✅ done · 🟠 verify · 🔴 blocker

## Blockers

- 🔴 **Privacy Manifest** (`mobile/ios/Runner/PrivacyInfo.xcprivacy`) — currently **missing**.
  Apple auto-rejects (ITMS-91053) apps whose SDKs use required-reason APIs (Firebase,
  geolocator, path_provider). See [privacy-manifest.md](privacy-manifest.md).
- 🔴 **Location permission scope** — `Info.plist` declares
  `NSLocationAlwaysAndWhenInUseUsageDescription` + `UIBackgroundModes: location`. The loop is
  user-initiated (START → walk → STOP), which is the textbook **When In Use** case. Downgrade
  to When-In-Use for MVP unless background tracking is genuinely required and justified in
  review notes. (Guideline 5.1.1.)

## Verify

- 🟠 **Account deletion is complete** — must remove the **Firebase Auth user record** (Admin
  SDK), not just Postgres rows. See [data-deletion.md](data-deletion.md). (Guideline 5.1.1(v).)
- 🟠 **Hide the `local`/email signup** path in store builds; keep Sign in with Apple + Google.
- 🟠 In-app deletion entry point reachable from Profile/Settings (not web-only).
- 🟠 Graceful **location-denied** state — testers frequently deny permission.
- 🟠 Permission **pre-prompt** explaining *why* before the system location dialog.

## Done

- ✅ **Sign in with Apple** offered alongside Google (Guideline 4.8 satisfied).
- ✅ **Privacy Policy + Terms** served at `/privacy` and `/terms` (Guideline 5.1.1).
- ✅ Account-deletion endpoint exists, `[Authorize]` + self-only guard (no IDOR).
- ✅ ATS on (default), all traffic HTTPS/`wss`.

## Reviewer notes (submit with the build)

The core action requires physically walking a closed outdoor loop, which an App Review tester
cannot do. **Provide:**
1. A test account (Sign in with Apple or a seeded Google account).
2. A short "how to play" + why location is needed.
3. A reviewer-accessible way to exercise a claim without walking (e.g., a debug/simulated
   route or a server-seeded territory in the test account's city) so the loop can be observed.
