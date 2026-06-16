---
name: app-store-compliance
description: Apple App Store Review Guideline + iOS privacy compliance gate for MyLoop. Use before any PR that touches auth, location, push, permissions, data collection, account management, purchases, third-party SDKs, or Info.plist / Runner.xcodeproj / PrivacyInfo.xcprivacy — to catch the things that get a GPS+social-login app rejected.
origin: MyLoop (staff-engineering standard)
---

# App Store Compliance — iOS Rejection Prevention

MyLoop is a high-risk profile for App Review: **background GPS + social login + push +
location data**. Each of those maps to a specific guideline that has rejected apps. This
skill is a verification pass, not a coding pattern — run it before opening/merging any PR
that touches the trigger areas, and fix violations before pushing.

## When to Activate

PR touches any of: Firebase Auth / Sign-in flow, `location_service.dart` / background
location, FCM / push, permission prompts, any new data field collected from users,
account deletion, in-app purchases, a new third-party SDK, or
`Info.plist` / `Runner.xcodeproj` / `PrivacyInfo.xcprivacy` / `AndroidManifest.xml`.

## 1. Sign in with Apple — Guideline 4.8 (HARD BLOCKER for MyLoop)

MyLoop offers **Google** social login. Apple requires that any app using a third-party
or social login service **also offer Sign in with Apple** (an equivalent privacy-respecting
option). Shipping Google sign-in without SiwA on iOS = rejection.

- [ ] Sign in with Apple is present on the iOS sign-in screen alongside Google
- [ ] SiwA option does not collect more than name + email, and offers "Hide My Email" compatibility
- [ ] Apple capability enabled in `Runner.xcodeproj` entitlements

## 2. Location — Guidelines 5.1.1, 5.1.5, 2.5.4

- [ ] Every requested key has a **specific, user-facing purpose string** (no generic "for app
      functionality"). Current strings in `Info.plist`:
      `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`.
- [ ] App requests **When-In-Use first**, escalates to Always only with clear in-context
      justification — never Always cold.
- [ ] `UIBackgroundModes` includes `location` **only because** continuous walk-tracking
      genuinely needs it; the value to the user (live territory capture) is visible while
      backgrounded. Apple rejects background location that isn't core to the feature.
- [ ] App still functions (degraded) if the user grants only When-In-Use or denies — no
      dead-end, no nag loop.
- [ ] Location data is not sold or shared with third parties without explicit consent (5.1.2).

## 3. App Tracking Transparency (ATT) — Guideline 5.1.2 / framework

- [ ] If any SDK (analytics, ads, attribution) tracks the user **across other companies'
      apps/sites**, the `AppTrackingTransparency` prompt is shown **before** tracking, with
      `NSUserTrackingUsageDescription` set. If MyLoop does **not** cross-app track, confirm no
      SDK silently does, and do not collect IDFA.

## 4. Privacy Manifest & Required Reason APIs

- [ ] `PrivacyInfo.xcprivacy` exists and is current: declares collected data types
      (location, identifiers, user ID) and reasons.
- [ ] Any "Required Reason API" used (file timestamp, UserDefaults, disk space, system
      boot time) has an approved reason code listed. Third-party SDKs must ship their own
      privacy manifests + signatures (Firebase does — keep versions current).
- [ ] App Store Connect **privacy "nutrition label" matches what the code actually
      collects** — mismatch is a common rejection/removal cause.

## 5. Account Deletion — Guideline 5.1.1(v) (HARD BLOCKER)

Any app that supports account creation **must** let the user **initiate account + data
deletion from within the app** (not just deactivate, not "email support").

- [ ] In-app "Delete account" path exists and reaches an API endpoint that deletes/anonymizes
      server-side data (territory, loops, profile, FCM tokens).
- [ ] Deletion is discoverable (Settings/Profile), not buried.

## 6. Push Notifications — Guideline 5.6 / 4.5.4

- [ ] Push is **not required** to use the app, and not used for marketing/promotions without
      separate opt-in consent.
- [ ] FCM token handling deletes tokens on logout/account deletion.

## 7. Minimum Functionality & Beta — Guidelines 4.2, 2.1, TestFlight

- [ ] Build is not a thin web wrapper / placeholder; provides native value (4.2).
- [ ] No crashes on a clean install with permissions denied.
- [ ] Closed beta distribution goes through **TestFlight**, not ad-hoc App Store submission,
      and external testers require Beta App Review.

## 8. Purchases — Guideline 3.1.1 (only if selling)

- [ ] If MyLoop ever sells digital goods/boosts, it uses **StoreKit / IAP** — no external
      payment links for digital content. (Physical goods/services use other means.) If no
      purchases exist yet, confirm the PR isn't introducing an external-payment path.

## Cross-stack note

Account deletion, ATT, and data-collection claims span Flutter UI ↔ .NET API ↔ App Store
Connect config. A client-only change (e.g. adding a "Delete account" button) is incomplete
without the server endpoint that actually deletes the data — verify both sides, consistent
with the project's #1 bug class (.NET ↔ Flutter contract drift).

## Pre-PR Checklist (summary)

- [ ] Sign in with Apple present wherever Google sign-in is (4.8)
- [ ] Location purpose strings specific; When-In-Use first; background-mode justified; graceful on denial
- [ ] No undisclosed cross-app tracking; ATT prompt if tracking; IDFA only with consent
- [ ] `PrivacyInfo.xcprivacy` + Required Reason codes current; nutrition label matches code
- [ ] In-app account+data deletion exists and hits a real server-side delete
- [ ] Push optional, consent-gated for marketing, tokens cleared on logout/delete
- [ ] No placeholder functionality; no crash with permissions denied; beta via TestFlight
- [ ] No external payment path for digital goods (IAP only) if purchases are touched
