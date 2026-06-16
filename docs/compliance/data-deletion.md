# Data Deletion Guarantee (Guideline 5.1.1(v))

Apple requires apps that support account creation to also support in-app account deletion that
removes the account and its data.

## Current behavior

- **Endpoint:** `DELETE /api/users/{id}` (`UsersController.DeleteAccount`).
- **Authorization:** controller is `[Authorize]`; `DenySelf(id)` ensures a user can only
  delete **their own** account (no IDOR).
- **What it deletes** (`UserService.DeleteUserData`): the user's `TerritoryCells`, `Claims`,
  and the `User` row.

## Gap to close before launch

🟠 **The Firebase Auth user record is not deleted** — only Postgres rows are removed. The
Firebase identity (UID, email) persists, so deletion is incomplete and a re-signup is not
clean.

**Fix:** in `DeleteAccount`, also call the **Firebase Admin SDK** `DeleteUserAsync(firebaseUid)`
server-side, so the identity and its PII are fully removed. Order the operation so app data and
identity are both gone (or neither), and handle the already-deleted case idempotently.

## Also confirm cascade completeness

When new user-owned tables are added (e.g. `DeviceToken`, `UserAchievement`, `DailyMission`,
`ExploredCell`, `CellTransfer`, `LeaderboardEntry`), ensure `DeleteUserData` removes or
anonymizes them too. **`CellTransfer` is append-only history** — decide explicitly whether to
delete a deleted user's transfer rows or anonymize the actor; document the choice here when made.

## In-app entry point

The deletion action must be reachable inside the app (Profile → Settings), not only via the
web Privacy Policy. Confirm `profile_screen.dart` exposes it with a confirmation step.
