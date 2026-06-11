# ADR-0002: Use Firebase Authentication for identity

- **Status:** Accepted
- **Date:** 2026-06-11
- **Deciders:** Engineering

## Context

We need cross-platform (iOS + Android) authentication with social login, secure token
handling, and minimal backend to maintain for a solo/small team with no infra budget. Apple
App Store Guideline 4.8 requires that if we offer a third-party social login (Google), we
also offer a privacy-preserving option (Sign in with Apple).

## Decision

Use **Firebase Authentication** as the identity provider, offering **Sign in with Apple** and
**Google**. The backend validates the Firebase-issued JWT on every request
(`AddJwtBearer`, authority `securetoken.google.com/<project>`); the caller's identity is
**always derived from the validated token**, never from the request body. App users are keyed
by `FirebaseUid`.

## Consequences

- **Positive:** Social login + secure token storage handled by the Firebase SDK (iOS tokens
  land in the Keychain by default). Satisfies Apple 4.8 via Sign in with Apple. No password
  storage on our side. Pairs naturally with FCM for push.
- **Negative / Trade-offs:** Vendor lock-in to Firebase identity. Email from Sign in with
  Apple is only provided on the **first** authentication — it must be persisted then. A
  `"local"`/`"dev_"` auth path exists for development and should be hidden in store builds.
- **Follow-ups:** Account deletion must also remove the **Firebase Auth user record** via the
  Admin SDK, not just our Postgres rows — see
  [compliance/data-deletion.md](../compliance/data-deletion.md). Ensure `/hubs` query-string
  tokens are never written to access logs (see [realtime.md](../architecture/realtime.md)).

## Alternatives Considered

| Option | Why rejected |
|--------|--------------|
| Self-hosted auth (ASP.NET Identity) | Password storage, reset flows, and social-login plumbing we'd own and secure ourselves. No infra budget. |
| Auth0 / Clerk | Cost; Firebase already needed for FCM, so one fewer vendor. |
