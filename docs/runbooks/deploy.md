# Runbook: Deploy

> Placeholder — fill in with the real hosting target once chosen. Captures the shape of the
> deploy so the steps live in-repo, not in someone's head.

## Backend (.NET 10 API)

1. Run tests: `dotnet test` (see `tests/MyLoop.Api.Tests`).
2. Apply DB migrations as part of release — startup runs `db.Database.Migrate()`
   ([db-migrations.md](db-migrations.md)).
3. Required configuration (never commit secrets):
   - `ConnectionStrings:DefaultConnection` — Postgres.
   - Firebase project authority/audience (currently in `Program.cs` — move to config).
   - `Cors:AllowedOrigins` — browser origins only (native mobile is unaffected by CORS).
   - FCM service-account credentials for `PushNotificationService`.
4. Verify `/privacy` and `/terms` are reachable over HTTPS (Apple requires live URLs).

## Mobile (Flutter)

1. `flutter analyze` + `flutter test`.
2. Bump build: `scripts/bump_build.ps1` (or `--build-number`).
3. iOS: see `mobile/BUILD_IOS.md`. Confirm `PrivacyInfo.xcprivacy` is present
   ([../compliance/privacy-manifest.md](../compliance/privacy-manifest.md)) before archiving.
4. Submit via App Store Connect with reviewer notes
   ([../compliance/apple-review-checklist.md](../compliance/apple-review-checklist.md)).
