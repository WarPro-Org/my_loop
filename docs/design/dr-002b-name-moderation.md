# Design — DR-002b: Display-name moderation

**Status:** Gate 2 approved 2026-09-22 · **Requirements:** Gate 1 approved 2026-09-22 · **Depends on:** #189 (Latin names + `NormalizeDisplayName`)

App Store Guideline 1.2 (verified against Apple's published text) requires, for user-generated
content: **(1)** filtering, **(2)** a report mechanism with timely responses, **(3)** blocking
abusive users, **(4)** published contact information. Display names are UGC — they appear on the
leaderboard, map hex popups, the in-app inbox and push notifications.

---

## 1. Gate 1 decisions (reference)

| # | Decision |
|---|---|
| 1 | 3 distinct reporters → auto-hide, then human confirm/restore |
| 2 | Injectable alert channels; email (MailKit SMTP) now, Slack later. One alert per state change, post-commit, best-effort |
| 3 | Moderators = Firebase UID allowlist in `ModerationOptions` |
| 4 | Fold → severe tier substring, reserved tier whole-word; list in code; generic error |
| 5 | Hide overwrites `DisplayName` with `Player#XXXX`; free rename; 2 confirmed strikes lock rename |
| 6 | Block = identity-only, server-stored, never affects gameplay |
| 7 | Report/Block from `/user-profile` ⋮ only; reasons Offensive/Impersonation/Other; online-only |
| 8 | Moderator `rescan` endpoint: auto-hide existing matches + one digest email; not a strike |
| 9 | SignalR `PlayerNameChanged` broadcast on hide/restore/rename |
| 10 | Inbox items carry the actor's user id (tap-through + block masking) |

### Corrections found during design (from reading the code)

- **No FCM data payload is needed.** In-app inbox items are created on the client from the
  SignalR `HexOwnershipChanged` event (`journey_screen.dart:384`), which already carries
  `newOwnerId`. The OS push text is built server-side, so the server masks it there.
  `IFcmSender` stays title/body only.
- **Contact information (1.2 bullet 4) is missing.** The only link is Privacy Policy
  (`login_screen.dart:158`). Added: a "Contact support" row (see §7).
- **Schema is not migration-based.** `DbInitializer` uses `EnsureCreated()` + idempotent DDL
  patches (ADR-0003 tracks the move to migrations). This design follows that convention.

---

## 2. Blocklist & folding (PR 1)

New pure static class `Services/Moderation/NameModeration.cs` (no I/O, no DI):

```csharp
public static class NameModeration
{
    public static string Fold(string normalizedName);          // see pipeline below
    public static bool IsBlocked(string normalizedName);        // severe OR reserved, minus exceptions
    public static string PlaceholderFor(Guid userId);           // "Player#" + first 4 hex of Id, upper
}
```

Fold pipeline (input is already `ValidationService.NormalizeDisplayName` output):
1. `ToLowerInvariant`
2. NFD → drop `UnicodeCategory.NonSpacingMark` (`àdmin` → `admin`, `ł` handled by explicit map `ł→l, ø→o, đ→d, ß→ss, æ→ae, œ→oe, ı→i`)
3. Leet map `0→o 1→i 3→e 4→a 5→s 7→t @→a $→s` (`@`/`$` cannot pass validation today; mapped anyway so the fold is safe to reuse)
4. Tokens = split on `[ \-_']`; **joined** = tokens concatenated

Matching:
- **Severe** (`FrozenSet<string>` in `Constants/NameBlocklist.cs`): blocked if `joined.Contains(term)` for any term
- **Reserved** (`admin, administrator, mod, moderator, official, support, staff, myloop, system`): blocked if **any token equals** a term, or `joined` equals a term (`my_loop`, `My Loop`)
- **Exceptions** (`FrozenSet`, initially empty): a folded `joined` value in this set is never blocked — for real surnames that trip the severe tier

`ValidationService.ValidateDisplayName` adds, after the regex check:
`if (NameModeration.IsBlocked(normalized)) return "This name isn't allowed";`
(single generic message — never reveals the matched term or tier).

Source list: LDNOOBW (**CC-BY-4.0**, verified; attribution in the generated file header) for
en/fr/de/es/it/pt/nl/pl/sv/da/no/fi/cs/hu/tr. `scripts/moderation/build_name_blocklist.py`
generates `Constants/NameBlocklist.g.cs` from pinned commits; terms are stored pre-folded.

**Implementation refinement (PR 1).** Measured against a 27k first/last-name corpus, raw
LDNOOBW substring matching blocked 119 real names (Frances, Connell, Fischer, Regina…), and
against an English word list it hit words like *therapist* (rapist) and *trimming* (rimming).
Tiers are therefore derived, not hand-sorted:
- **Severe substrings** = a hand-curated `CORE` (fuck, cunt, shit, hitler, … — each with 0
  corpus hits) + LDNOOBW terms of ≥ 7 chars that occur inside no name and no English word.
  Shorter foreign terms hid inside names/words (Finnish *pipari*, Polish *jajko*).
- **Whole words** = every other LDNOOBW term, minus ordinary words (English list + a reviewed
  `DROP_WHOLE_WORD` list for other languages), plus `KEEP_WHOLE_WORD` insults that are also
  English words (ass, cock, nazi…). Reserved staff words live in `NameModeration`.
- **Dropped** = terms that *are* common names (dick, regina, anita) and identity terms (gay,
  lesbian, bisexual, trans, …) — self-description is never blocked; slurs are.
- Result: 898 severe, 383 whole-word, 7 exceptions.

**Review fixes (#193 agent review).** The first corpus was Anglo-heavy, and `shit`/`fuk` blocked
Harshit, Rakshit, Kshitij, Ashita, Fukuda, Fukuoka…, which matters for the beta's
Bangalore/Mumbai/Tokyo players:
- `shit` and `fuk` are whole-word only. Compounds such as *bullshit* and *shithead* stay
  substring matches.
- The generator adds a curated South and East Asian name list and **fails** if any severe term
  hits a corpus name not covered by an exception.
- Exceptions apply **per word** (removed before matching), so "Scunthorpe United" passes.
- Reserved words also match with trailing digits ("Admin2", "Moderator1"), and the brand
  `myloop` is reserved anywhere in a name ("MyLoopSupport").
- `ſ ƒ ħ ŧ ƀ ƶ ǥ` fold to their Latin reading.
- `scripts/moderation/fold_vectors.json` is asserted by both the generator and the xUnit suite,
  so the two folds cannot drift apart. (The old fold-stability test could not detect that drift.)

**Review fixes, round 2 (#193) — deviations from the Matching rules above.**
- **Severe terms match inside one word, not on `joined`.** Scanning the concatenation of all
  words let a first name and surname form a term across the boundary: Thomas Lutz (s+lut →
  *slut*), Margaret Ardern (*retard*), Philip Ornstein (*porn*), Louisa Lopez (*salope*), Mari
  Conti (*maricon*). Crossing the generator's first-name and surname corpora found 2,291 such
  pairs. Each word is now scanned on its own. The only joining left is for **spelled-out
  letters**: each maximal run of tokens of at most `GameConstants.MaxSpelledOutTokenLength`
  (= 1) characters is joined and checked against both tiers, so "s-h-i-t", "f u c k" and
  "A-s-s" are still refused. The same rule replaces the whole-word check on `joined`, so
  "Ana L" (an+al) is no longer refused. "my_loop" / "My Loop" are still refused by the brand
  rule (`myloop` anywhere in the concatenation, reserved tier only).
- **The limit is 1, not 2.** At 2, real two-letter name parts join into listed terms (Si Ki →
  *siki*, Su Ka → *suka*, As Lu Ty → *slut*). Accepted cost: spellings that split a word into
  two-letter chunks ("fu ck") are not caught; the report path is the backstop.
- **Generator check.** Because the matcher never joins two real name parts, checking each
  corpus name on its own is sufficient; a first × surname pair check is not needed. The
  generator instead fails if any corpus name is short enough to be joined as a spelled-out
  letter, and an xUnit test asserts its `MAX_SPELLED_OUT_TOKEN_LENGTH` equals the C# constant.
  The generated list did not change and is still byte-reproducible.
- **Reserved words** also match with digits trimmed from both ends, before and after leetspeak
  ("2Admin", "4dmin2", "M0derator1"), and inside an x wrapper at both ends ("xXAdminXx").
  One-sided x (Max, Rex, Xander) is not a wrapper.
- **`root` is no longer reserved** — Root is an ordinary surname (Joe Root). `system` and
  `admin` cover system impersonation.

**Accepted false positives (whole-word tier).** These whole-word terms are also real names, and
are kept on purpose because the slur or sexual reading is the common one in an English-language
leaderboard:

| Term | Real names refused | Why kept |
|---|---|---|
| `coon` | Carrie Coon (surname) | Racial slur |
| `semen` | Semen Petrenko (Ukrainian transliteration of Semyon), Semen Padang | Sexual term |
| `fuk` | Lau Fuk Wing, Fuk-sang (Cantonese given name) | Common spelling of *fuck*; already narrowed from substring to whole word, so Fukuda/Fukuoka pass |

Remedy for an affected player: the report/restore path's human review. The player contacts
support (§7) and a moderator reviews the name, as for a reported name (§4.3). Adding the folded
word to `EXCEPTIONS` in the generator would un-block it for every player, so that is a product
decision per term, not the default remedy.

---

## 3. DB schema changes

Convention: entity config in `AppDbContext.OnModelCreating` (fresh DBs via `EnsureCreated`) **and**
an idempotent `ApplyModerationSchema(db)` block in `DbInitializer.ApplySchemaPatches` (existing DBs).

### 3.1 `Users` — new columns (PR 2)

| Column | Type | Null | Default | Purpose |
|---|---|---|---|---|
| `NameHiddenAt` | `timestamptz` | yes | `NULL` | Set when the current `DisplayName` is a moderation placeholder |
| `ConfirmedNameStrikes` | `integer` | no | `0` | Incremented only by moderator confirm |
| `NameLockedAt` | `timestamptz` | yes | `NULL` | Set when strikes reach 2; cleared by moderator unlock |

All three have DB defaults, so an **old binary's `INSERT` into `Users` still succeeds** after the
patch runs (rolling deploy / rollback safety). EF only selects mapped columns, so old code ignores them.

### 3.2 `NameReports` (PR 2)

| Column | Type | Notes |
|---|---|---|
| `Id` | `uuid` PK | |
| `ReporterId` | `uuid` FK → `Users(Id)` `ON DELETE CASCADE` | |
| `ReportedUserId` | `uuid` FK → `Users(Id)` `ON DELETE CASCADE` | |
| `NameSnapshot` | `varchar(32)` | Name as it was when reported |
| `Reason` | `smallint` | `0 Offensive, 1 Impersonation, 2 Other` |
| `CreatedAt` | `timestamptz` | |

Indexes: **unique** `(ReporterId, ReportedUserId, NameSnapshot)` (one report per reporter per name);
`(ReportedUserId, NameSnapshot)` (threshold count); `(ReporterId, CreatedAt)` (daily limit).

### 3.3 `NameModerationCases` (PR 2)

| Column | Type | Notes |
|---|---|---|
| `Id` | `uuid` PK | |
| `UserId` | `uuid` FK → `Users(Id)` `ON DELETE CASCADE` | |
| `NameSnapshot` | `varchar(32)` | The name under review; restore writes this back |
| `Source` | `smallint` | `0 Reports, 1 Rescan` |
| `Status` | `smallint` | `0 Open, 1 AutoHidden, 2 Confirmed, 3 Restored` |
| `OpenedAt` / `HiddenAt` / `ResolvedAt` | `timestamptz` | `HiddenAt`, `ResolvedAt` nullable |
| `ResolvedByUid` | `varchar(128)` null | Moderator Firebase UID — audit trail |

Index: **unique** `(UserId, NameSnapshot)` — one case per name. It is the "first report" claim
used for once-only alerting (`INSERT … ON CONFLICT DO NOTHING`; only the inserting request alerts).
A name that was restored and later re-reported reopens the same row (`Status` back to `Open`).

### 3.4 `UserBlocks` (PR 3)

| Column | Type | Notes |
|---|---|---|
| `BlockerId` | `uuid` FK → `Users(Id)` `ON DELETE CASCADE` | |
| `BlockedId` | `uuid` FK → `Users(Id)` `ON DELETE CASCADE` | |
| `CreatedAt` | `timestamptz` | |

PK `(BlockerId, BlockedId)` — also serves the push-masking lookup `(victim, thief)`.

### 3.5 Rollback

All changes are **additive** (new nullable/defaulted columns, new tables). Rollback = redeploy
the previous binary; it ignores the new columns/tables. No data rewrite is needed. If a full
removal is ever wanted, a manual script drops the three tables and three columns — not run
automatically. Account deletion (`DELETE /api/users/{id}`) is covered by `ON DELETE CASCADE`;
`AccountDeletionTransactionTests` gets a case asserting reports/cases/blocks are removed.

**Risk accepted:** `ApplySchemaPatches` logs-and-continues on failure (existing behaviour). A failed
moderation patch would surface as 500s on report/block endpoints, not at startup. Mitigation:
`ApplyModerationSchema` runs its DDL in one explicit transaction (Postgres DDL is transactional)
so it is all-or-nothing, and logs at `Error` on failure.

---

## 4. API changes

New Options (first in the codebase; bound + validated on start):

```csharp
public sealed class ModerationOptions      // section "Moderation"
{
    public string[] ModeratorUids { get; init; } = [];
}
public sealed class ModerationEmailOptions // section "Moderation:Email"
{
    public string? Host { get; init; }     // empty ⇒ email channel disabled, alerts logged only
    public int Port { get; init; } = 587;
    public bool UseStartTls { get; init; } = true;
    public string? Username { get; init; }
    public string? Password { get; init; } // env var / appsettings.Development.json only
    public string From { get; init; } = "";
    public string[] To { get; init; } = [];
}
```

Constants (`GameConstants`): `NameReportHideThreshold = 3`, `MaxNameReportsPerReporterPerDay = 10`,
`NameStrikesToLock = 2`, `MaxBlocksPerUser = 200`, `RescanPageSize = 500`.

### 4.1 Player endpoints (`[Authorize]`)

New `NameReportsController` and `BlocksController` (keeps `UsersController` thin).

| Verb + path | Body | Success | Errors |
|---|---|---|---|
| `POST /api/users/{id}/name-report` | `NameReportRequest { reason: "offensive" \| "impersonation" \| "other" }` | `204` (also for a duplicate — idempotent, reveals nothing) | `400` self / moderator target / bad reason · `404` unknown user · `429` daily limit |
| `GET /api/users/me/blocks` | — | `200 BlockListResponse { blockedUserIds: Guid[] }` | — |
| `PUT /api/users/{id}/block` | — | `204` (idempotent) | `400` self · `404` unknown · `409` over `MaxBlocksPerUser` |
| `DELETE /api/users/{id}/block` | — | `204` (idempotent) | — |

`{id}` is always the **target**; the actor is always `ICurrentUser` (never from the body — #99).
`reason` is a string on the wire (`JsonStringEnumConverter` on the DTO property, camelCase names).

### 4.2 Changed player endpoint

`PATCH /api/users/{id}` with `displayName` while `NameLockedAt != null` → **`409`**
`{ "code": "name_locked", "message": "Your name can't be changed right now." }`.
A successful rename clears `NameHiddenAt` and broadcasts `PlayerNameChanged`.

### 4.3 Moderator endpoints (`[Authorize(Policy = "Moderator")]`, `ModerationController`)

| Verb + path | Body | Success |
|---|---|---|
| `GET /api/moderation/cases?status=open\|autoHidden` | — | `200 ModerationCaseResponse[]` |
| `POST /api/moderation/cases/{caseId}/confirm` | — | `204` — `Status=Confirmed`, `ConfirmedNameStrikes++`, lock at 2. If the case is still `Open` (not yet hidden) confirm also hides |
| `POST /api/moderation/cases/{caseId}/restore` | — | `204` — writes `NameSnapshot` back **only if** `DisplayName` is still the placeholder (a player who has since renamed keeps their new name) |
| `POST /api/moderation/users/{userId}/unlock-name` | — | `204` — clears `NameLockedAt` (strikes kept) |
| `POST /api/moderation/rescan` | — | `200 RescanResponse { scanned: int, hidden: int }` |

`ModerationCaseResponse { id: Guid, userId: Guid, nameSnapshot: string, currentDisplayName: string,
source: "reports"|"rescan", status: "open"|"autoHidden"|"confirmed"|"restored", reportCount: int,
reasons: string[], confirmedStrikes: int, openedAt: DateTime, hiddenAt: DateTime? }`

The `Moderator` policy: `FirebaseUid` claim ∈ `ModerationOptions.ModeratorUids` (ordinal compare).
Non-moderators get `403`; no endpoint reveals who the moderators are.

### 4.4 Report transaction (race-safe)

`NameReportService.ReportAsync(reporterId, reportedUserId, reason)`:

```
strategy.ExecuteAsync(async () => {
  ChangeTracker.Clear();
  await using tx = BeginTransaction();
  SELECT … FROM "Users" WHERE "Id" = @reported FOR UPDATE      -- serialises reports per target
  if reporter has ≥ 10 reports since UTC midnight → return Limited
  INSERT NameReport … ON CONFLICT (ReporterId, ReportedUserId, NameSnapshot) DO NOTHING
     → 0 rows ⇒ return Duplicate
  INSERT case (UserId, NameSnapshot, Open) ON CONFLICT DO NOTHING → openedNow
     (if the row exists with Status=Restored → UPDATE to Open, openedNow = true)
  count = COUNT(DISTINCT ReporterId) for (reported, snapshot)
  if count ≥ 3:
     UPDATE "Users" SET DisplayName = placeholder, NameHiddenAt = now()
       WHERE Id = @reported AND DisplayName = @snapshot     → hiddenNow = (rows == 1)
     UPDATE case SET Status = AutoHidden, HiddenAt = now() WHERE hiddenNow
  commit
  return (openedNow, hiddenNow)
})
-- post-commit, outside the retried block (database-retry-resilience):
if openedNow → alerts.Send(FirstReport)
if hiddenNow → alerts.Send(AutoHidden); notifier.PlayerNameChanged(reported, placeholder)
```

- The `FOR UPDATE` row lock means two concurrent third reports cannot both count 2 (missed hide)
  or both hide (double alert).
- Retry after an ambiguous commit: the report insert hits `ON CONFLICT` → `Duplicate` → no
  duplicate alert. **Accepted:** in that rare case the alert for that transition is lost; the
  case row still exists and appears in `GET /api/moderation/cases`.

Rescan: keyset pages of 500 by `Id`; per blocked user, a small transaction with the same
conditional `UPDATE` (source `Rescan`, no per-user alert); after the loop one `RescanDigest`
alert + one `PlayerNameChanged` per hidden user. Idempotent — a re-run skips already-hidden names
(placeholder `Player#…` never matches the blocklist).

### 4.5 Alerts

```csharp
public interface IModerationAlertChannel { Task SendAsync(ModerationAlert alert, CancellationToken ct); }
public sealed class ModerationAlerter(IEnumerable<IModerationAlertChannel> channels, ILogger<…> log)
{   // fan-out; each channel isolated in try/catch; never throws to the caller
    public Task SendAsync(ModerationAlert alert, CancellationToken ct);
}
public sealed record ModerationAlert(ModerationAlertKind Kind, Guid? CaseId, Guid? UserId,
    string? NameSnapshot, int ReportCount, IReadOnlyList<string> Lines); // Lines used by digest
```

`SmtpModerationAlertChannel` (MailKit) is registered only when `Moderation:Email:Host` is set;
otherwise no channel is registered and `ModerationAlerter` logs the alert at `Information`
(same pattern as the `Push:Enabled` flag). A Slack channel later = one new class + one
registration line. Every alert is also a structured log event (`ModerationAlertRaised`).
Email bodies contain the name snapshot and case id, **never** the reporter's identity.

### 4.6 Push masking (PR 3)

`IPushNotificationService.NotifyHexStolen(Guid victimUserId, Guid thiefUserId, string thiefDisplayName, int stolenCount)`
— new `thiefUserId` parameter. If `UserBlocks` has `(victim, thief)`, the body uses
`"A player captured …"`. Single call site: `TerritoryService.cs:1309`.

---

## 5. SignalR changes (PR 4)

| Hub method (server → client) | Target | Payload |
|---|---|---|
| `PlayerNameChanged` | `Clients.All` | `{ userId: Guid, displayName: string }` |

Sent from `ITerritoryNotifier.NotifyPlayerNameChanged(Guid userId, string displayName)` on:
auto-hide, rescan hide, moderator confirm-from-open, restore, and **every successful rename**.
Fire-and-forget with a try/catch like `NotifyHexOwnershipChanged` (a failed broadcast never
fails the request). Names are already public, so broadcasting to unauthenticated connections
discloses nothing new. No client → server methods are added.

---

## 6. Riverpod state impact (Flutter)

| Provider | Change |
|---|---|
| **`blockedUsersProvider`** (new) `AsyncNotifierProvider<BlockedUsersNotifier, Set<String>>` | Loads `GET /api/users/me/blocks` after sign-in; user-bound file cache via the `offline-first-user-bound-cache` pattern (save-on-success, restore-offline, cross-user guard, clear-on-signout) so masking survives an offline cold start. `block(id)` / `unblock(id)` are optimistic with rollback + snackbar on failure; require online (existing offline modal otherwise). |
| **`displayNameFor(ref, userId, rawName)`** (new helper) | Returns `"Blocked player"` when `userId ∈ blockedUsersProvider`, else `rawName`. Every other-player name render goes through it. |
| `cityLeaderboardProvider` / `countryLeaderboardProvider` / `worldLeaderboardProvider` | Unchanged shape. `ref.invalidate`d on `PlayerNameChanged`; rows render through `displayNameFor`; blocked rows use a neutral avatar. |
| `HexTerritoryManager` (map cells) + `TerritoryCache` | On `PlayerNameChanged`, patch `ownerName` for every cell with `ownerId == userId` and re-save cache. Hex popup renders through `displayNameFor`. |
| `userProfileProvider` | On `PlayerNameChanged` for **my** `userId` → `setDisplayName` (my name was hidden or restored) + `ProfileCache`. `PATCH` `409 name_locked` → show message, revert optimistic rename. |
| `notificationProvider` | `AppNotification` gains `actorUserId: String?` (nullable — legacy persisted items have none). `addTheftAlert` takes `thiefId`; `journey_screen.dart:380` groups by `newOwnerId` instead of display name (fixes two same-named thieves merging). Inbox renders the body with the actor name through `displayNameFor`; items with `actorUserId` are tappable → `/user-profile`. |
| `TerritoryRealtimeService` | Registers `connection.on('PlayerNameChanged', …)`; exposes a `Stream<PlayerNameChangedEvent>`. |

`/user-profile` screen: ⋮ menu with **Report name** (reason sheet → `POST name-report` → "Thanks,
we'll review it") and **Block / Unblock player**. Hidden for my own profile.

---

## 7. Contact information (Guideline 1.2 bullet 4)

`ProfileScreen` gains a **Contact support** row → `mailto:` via the existing `url_launcher`
dependency. Address held in `AppConstants.supportEmail` (**address needed from product**).
The same address must be the App Store Connect Support URL/contact.

---

## 8. Cross-stack contract table

| Boundary | .NET (name : type) | Flutter (name : type) |
|---|---|---|
| Report request | `NameReportRequest.Reason : NameReportReason` (string enum) | `reason : String` ∈ `offensive/impersonation/other` |
| Report target | route `{id} : Guid` | `userId : String` (Guid string) |
| Block list | `BlockListResponse.BlockedUserIds : Guid[]` | `blockedUserIds : List<String>` → `Set<String>` |
| Block target | route `{id} : Guid` | `userId : String` |
| Rename locked | `409 { code: "name_locked", message: string }` | `code == 'name_locked'` |
| Realtime | `PlayerNameChanged { UserId : Guid, DisplayName : string }` (camelCase over SignalR JSON) | `PlayerNameChangedEvent { userId : String, displayName : String }` |
| Existing, now relied on | `HexChangeEvent.NewOwnerId : Guid` | `HexChangeEvent.newOwnerId : String` |
| Existing, now relied on | `LeaderboardEntryResponse.UserId : Guid` | `LeaderboardEntry.userId : String` |
| Existing, now relied on | `TerritoryCell OwnerId : Guid` | `TerritoryCell.ownerId : String` |
| Placeholder format | `"Player#" + Id.ToString("N")[..4].ToUpperInvariant()` | treated as an opaque string |
| Constants | `NameReportHideThreshold = 3` etc. | not mirrored — server-only |
| Inbox (client-only) | — | `AppNotification.actorUserId : String?` (JSON `actorUserId`) |

Guid strings: .NET serialises lowercase `d` format; Flutter compares ids as received — no
case-folding needed as long as every id originates from the API.

---

## 9. Known-risk checklist

| Risk | Status |
|---|---|
| Two concurrent third reports → double hide / double email, or both count 2 → missed hide | **Mitigated** — `FOR UPDATE` on the target row + conditional `UPDATE … WHERE DisplayName = @snapshot` |
| Execution-strategy retry duplicates side effects | **Mitigated** — alerts/broadcast post-commit outside the retried block; inserts are `ON CONFLICT DO NOTHING` |
| Lost alert after ambiguous commit | **Accepted** — case still visible in `GET /cases` |
| Brigading (3 friends wipe a rival's name) | **Accepted by design** — victim renames immediately; no strike without a moderator |
| Report spam by one account | **Mitigated** — unique per (reporter, target, name) + 10/day + existing global rate limiter |
| Restore clobbers a newer name the player chose | **Mitigated** — restore is conditional on the placeholder still being current |
| Blocklist false positive on a real surname | **Mitigated** — exceptions set; generic error; report-review path unaffected |
| Blocklist evasion via Cyrillic/Greek homoglyphs | **Mitigated by #189** (Latin-only) + accent fold |
| Blocklist evasion via creative spelling | **Accepted** — the report path is the backstop |
| Moderator impersonation via `Admin` names | **Mitigated** — reserved tier |
| Moderator endpoints reachable by players | **Mitigated** — policy; tests assert `403` |
| SMTP credentials leak | **Mitigated** — Options from env / gitignored config only; never logged |
| SMTP outage fails a report | **Mitigated** — alerter swallows + logs per channel |
| Hidden name lingers on devices offline during the broadcast | **Accepted until #177 merges** (reconnect re-fetch); screens also refresh on normal reloads |
| Legacy inbox items (no `actorUserId`) not masked / not tappable | **Accepted** (Gate 1) |
| Offline cold start shows blocked names unmasked | **Mitigated** — user-bound block-list cache |
| Moderation DDL patch fails silently at startup | **Mitigated** — one transactional block, `Error` log |
| Rescan request too long at scale | **Accepted for beta** (keyset paging); revisit if user count > ~50k |
| Report stores reporter identity (PII) | **Mitigated** — cascade on account deletion; never included in alert emails. App Store privacy label: check whether "Other User Content" must be declared (UNVERIFIED) |
| Anti-cheat: block used to protect territory | **N/A by design** — block never affects gameplay |

---

## 10. PR plan & skill gates

| PR | Scope | Pre-PR skills (CLAUDE.md) |
|---|---|---|
| 1 | `NameModeration` + generated blocklist in `ValidationService`; rename waits for the API and shows its refusal (the client cannot pre-check the blocklist, so a fire-and-forget rename would show a name the server refused) | coding-standards, dotnet-patterns, csharp-testing, security-review, dart-flutter-patterns, flutter-dart-code-review |
| 2 | `Moderator` policy + `ModerationOptions` (moved from PR 1 to ship with their first consumer), Users columns, `NameReports`, `NameModerationCases`, report endpoint, moderator endpoints incl. rescan, alerter + SMTP channel, rename lock | + webapi-standards, database-migrations, database-retry-resilience, api-design, error-handling |
| 3 | `UserBlocks`, block endpoints, push masking, Flutter block list + `displayNameFor` + ⋮ menu + contact support | + api-design (cross-stack), dart-flutter-patterns, flutter-dart-code-review, app-store-compliance, offline-first-user-bound-cache |
| 4 | `PlayerNameChanged` hub event + Flutter handlers; `actorUserId` inbox + tap-through | + latency-critical-systems, api-design (cross-stack), flutter-disk-concurrency-test (inbox/territory caches) |

Every PR: `dotnet test`, `flutter test`, `flutter analyze`, `verification-loop`.
