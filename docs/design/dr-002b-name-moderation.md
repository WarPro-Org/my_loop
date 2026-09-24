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

Matching (Gate 2 text — **superseded**; the rules the code implements are in "Current matching
rules" below):
- ~~**Severe** (`FrozenSet<string>` in `Constants/NameBlocklist.cs`): blocked if `joined.Contains(term)` for any term~~
- ~~**Reserved** (`admin, administrator, mod, moderator, official, support, staff, myloop, system`): blocked if **any token equals** a term, or `joined` equals a term (`my_loop`, `My Loop`)~~
- ~~**Exceptions** (`FrozenSet`, initially empty): a folded `joined` value in this set is never blocked — for real surnames that trip the severe tier~~

### Current matching rules (`NameModeration.IsBlocked`, after review round 3)

Terms live in `Constants/NameBlocklist.g.cs` (generated). A name is blocked if any rule matches.
"Word" = a token of the leetspeak fold; "letter" = a token of at most
`GameConstants.MaxSpelledOutTokenLength` (1) characters.

| # | Rule | Example refused | Example accepted |
|---|---|---|---|
| R1 | A **severe** term occurs inside one word, also read with the digits leetspeak leaves unmapped (2, 6, 8, 9) removed (words in `Exceptions` are skipped, in either reading) | Fuckface, N1gg3r, Fu2ck, Nig9ger | Scunthorpe United, Thomas Lutz |
| R2 | A **whole-word** or **reserved** term equals one word, also with its digits removed | Ass, Big Ass, The Admin, Na2zi | Cassandra, Badminton |
| R3 | Each maximal run of letters is joined and checked by R1 and R2 | s-h-i-t, A-s-s, K-K-K | Ana L, J K Lee |
| R4 | A **whole-word** or **reserved** term equals a word from the digit-preserving fold with digits trimmed from either end (before or after leetspeak), or with an x wrapper (`x` at both ends, length ≥ 3) trimmed | Admin2, 4dmin2, Nazi1, Coon2, xXnaziXx | Max, Rex, Xander, Alex, Maddox |
| R5 | `myloop` anywhere in the concatenated digit-preserving fold | MyLoopSupport, my_loop | — |
| R6 | Two **adjacent** words, unless the pair is in `JoinExceptions`: **(a)** their concatenation equals a severe term; **(b)** exactly one is a letter and the concatenation equals a whole-word term; **(c)** exactly one is a letter and a severe term of ≥ `GameConstants.MinSpanningSevereTermLength` (5) chars is a prefix (letter first) or suffix (letter last) of the concatenation | Nig Ger, F uck, Fuc K, B itch, S hit, Shi T, Fa G, N iggerboy | Deb Allen, S Luther, P Ornstein, Chin K |

Not caught (accepted): a **whole-word**-tier term split into two multi-letter words ("Na Zi",
"Sh It"; R6b needs one side to be a single letter, or two real name parts would form terms), a letter + word whose
concatenation contains a 4-letter severe term plus more letters ("S lutty"), and a term split
across three or more non-letter words. The report path is the backstop.

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
- **Severe substrings** = a hand-curated `CORE` (fuck, cunt, hitler, … — each with 0
  corpus hits; `shit` was here until the review fixes below made it whole-word only) + LDNOOBW terms of ≥ 7 chars that occur inside no name and no English word.
  Shorter foreign terms hid inside names/words (Finnish *pipari*, Polish *jajko*).
- **Whole words** = every other LDNOOBW term, minus ordinary words (English list + a reviewed
  `DROP_WHOLE_WORD` list for other languages), plus `KEEP_WHOLE_WORD` insults that are also
  English words (ass, cock, nazi…). Reserved staff words live in `NameModeration`.
- **Dropped** = terms that *are* common names (dick, regina, anita) and identity terms (gay,
  lesbian, bisexual, trans, …) — self-description is never blocked; slurs are.
- Result: 898 severe, 383 whole-word, 7 exceptions. (After review round 3: 898 severe,
  384 whole-word — `kkk` added — 7 exceptions, 50 join exceptions. After round 4: 909 severe —
  11 compounds added to `CORE`, see below — and 51 join exceptions.)

**Review fixes (#193 agent review).** The first corpus was Anglo-heavy, and `shit`/`fuk` blocked
Harshit, Rakshit, Kshitij, Ashita, Fukuda, Fukuoka…, which matters for the beta's
Bangalore/Mumbai/Tokyo players:
- `shit` and `fuk` are whole-word only, so compounds are caught only when listed. Round 4 added
  common ones to `CORE` as severe substrings: *bullshit, horseshit, dipshit, shithead, shitface,
  shithole, shitbag, dumbass, asshat, asswipe, douchebag*. *dickhead* is left out: the generator
  flags "Dick Head" as a real first name + surname pair.
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
  letters** (*superseded in round 3: adjacent word pairs are also checked, rule R6*): each maximal run of tokens of at most `GameConstants.MaxSpelledOutTokenLength`
  (= 1) characters is joined and checked against both tiers, so "s-h-i-t", "f u c k" and
  "A-s-s" are still refused. The same rule replaces the whole-word check on `joined`, so
  "Ana L" (an+al) is no longer refused. "my_loop" / "My Loop" are still refused by the brand
  rule (`myloop` anywhere in the concatenation, reserved tier only).
- **The limit is 1, not 2.** At 2, real two-letter name parts join into listed terms (Si Ki →
  *siki*, Su Ka → *suka*, As Lu Ty → *slut*). Accepted cost (after round 3, rule R6): a
  whole-word-tier term split into two multi-letter words ("Na Zi", "Sh It") is not caught; a
  severe term split that way ("Fu Ck") is, by R6a. The report path is the backstop.
- **Generator check.** (*Superseded in round 3 — the matcher now does join adjacent pairs, so
  the generator also checks corpus pairs; see below.*) Because the matcher never joins two real
  name parts, checking each corpus name on its own is sufficient; a first × surname pair check
  is not needed. The generator instead fails if any corpus name is short enough to be joined as
  a spelled-out letter, and an xUnit test asserts its `MAX_SPELLED_OUT_TOKEN_LENGTH` equals the
  C# constant. The generated list did not change and is still byte-reproducible.
- **Reserved words** also match with digits trimmed from both ends, before and after leetspeak
  ("2Admin", "4dmin2", "M0derator1"), and inside an x wrapper at both ends ("xXAdminXx").
  One-sided x (Max, Rex, Xander) is not a wrapper.
- **`root` is no longer reserved** — Root is an ordinary surname (Joe Root). `system` and
  `admin` cover system impersonation.

**Review fixes, round 3 (#193).** Rules R4 and R6 in "Current matching rules" above.
- **One space defeated the severe tier.** Per-word matching let "N igger", "F uck", "Fuc K",
  "Nig Ger", "B itch", "S hit", "Shi T" and "Fa G" through. R6 checks each pair of adjacent
  words, but never scans a first name + surname for a term inside their concatenation (that is
  what refused Thomas Lutz): only an **exact** severe match joins two ordinary words (R6a).
  Substring and whole-word matching across the space need one side to be a single letter —
  evidence of deliberate splitting (R6b, R6c).
- **Why 5 for spanning terms (R6c).** At 4, an initial next to a real surname forms a term:
  S Luther, S Luttrell → *slut*; P Ornstead, P Orna → *porn*; J Izzy → *jizz*. At 5 the
  corpora give no initial + name pair except ones that spell a term exactly, which R6a/R6b
  already cover. Accepted cost: "S lutty"-style splits of 4-letter terms are not caught.
  `GameConstants.MinSpanningSevereTermLength` mirrors the generator's
  `MIN_SPANNING_SEVERE_TERM_LENGTH`; an xUnit test asserts they match.
- **Generator pair check.** `join_collisions()` lists every pair R6 would refuse where both
  halves are corpus names, or one is a single letter and the other a corpus name (73 pairs).
  Generation **fails** unless each is reviewed into `JOIN_EXCEPTIONS` (emitted as
  `NameBlocklist.JoinExceptions`, never joined: Deb Allen, De Conner, Ana L, Chin K, Wan K,
  K Inkster, …) or `ACCEPTED_JOIN_REFUSALS` (still refused because the pair reads as the term
  and is not a plausible name: B Itch, Va Gina, Wan Ker, White Power, As S, F Ag, T Wat, …), and
  fails on a stale entry that no longer collides. A plain "fail on any collision" would have
  forced `bitch`, `bastard`, `wanker`, `vagina` out of the severe tier, since "B"+"Itch",
  "Bast"+"Ard", "Wan"+"Ker" and "Va"+"Gina" are all corpus pairs.
- **Whole words ignored digit and x-wrapper trimming.** "Nazi1", "Fag1", "Coon2", "Anal2",
  "Semen2", "xXnaziXx", "xXcoonXx" passed, because leetspeak turns a trailing `1` into `i`
  before the whole-word check. R4 runs the reserved-word readings through the whole-word tier
  too. No corpus name is x-wrapped, so the trim adds no real-name refusals.
- **`kkk`** added to the whole-word tier via the generator's `KEEP_WHOLE_WORD` list.

**Review fixes, round 4 (#193).**
- **Unmapped digits split a term inside a word.** Leetspeak maps only 0/1/3/4/5/7, so "Fu2ck",
  "F2uck", "Nig9ger" and "Na2zi" passed. R1 and R2 now also read each word and spelled-out run
  with its remaining digits removed (skipping `Exceptions` in that reading too). No corpus name
  contains a digit, so this adds no real-name refusals.
- **Common compounds** (*bullshit*, *shithead*, …) added to `CORE`; see "Review fixes" above.
- **"K Ike"** moved from `ACCEPTED_JOIN_REFUSALS` to `JOIN_EXCEPTIONS`: Ike is a common Igbo
  surname and first name, so an initial + Ike is a plausible real name. Accepted cost: "K ike"
  is not caught by R6b; "Kike" and "K-i-k-e" still are.

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
| `POST /api/users/{id}/name-reports` | `NameReportRequest { reason: "offensive" \| "impersonation" \| "other" }` | `204` (also for a duplicate — idempotent, reveals nothing) | `400` self / bad reason (a moderator target is answered `204`, see §4.7) · `404` unknown user · `429` daily limit |
| `GET /api/users/me/blocks` | — | `200 BlockListResponse { blockedUserIds: Guid[] }` | — |
| `PUT /api/users/{id}/block` | — | `204` (idempotent) | `400` self · `404` unknown · `409` over `MaxBlocksPerUser` |
| `DELETE /api/users/{id}/block` | — | `204` (idempotent) | — |

`{id}` is always the **target**; the actor is always `ICurrentUser` (never from the body — #99).
`reason` is a string on the wire (`JsonStringEnumConverter` on the DTO property, camelCase names).

### 4.2 Changed player endpoint

`PATCH /api/users/{id}` with `displayName` while `NameLockedAt != null` → **`409`**
`{ "code": "name_locked", "message": "Your name can't be changed right now." }`.
A successful rename clears `NameHiddenAt` and broadcasts `PlayerNameChanged`.
The moderation checks and the save run in one transaction under the player's `Users` row lock
(§4.9).

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
  SELECT pg_advisory_xact_lock(NREP, key(@reporter))         -- serialises one reporter's reports (§4.9)
  SELECT … FROM "Users" WHERE "Id" = @reported FOR NO KEY UPDATE  -- serialises reports per target
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

- The row lock means two concurrent third reports cannot both count 2 (missed hide)
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
`"A player captured …"` (`GameConstants.BlockedActorLabel`, matched by the app's in-app theft alert —
see §7.1). Single call site: `TerritoryService.cs:1309`.

---

### 4.7 Implementation notes (PR 2) — deviations from the above

- **Reporting a moderator returns `204`, not `400`.** A distinct answer would reveal who the
  moderators are, contradicting §4.3. The report is recorded (so it spends the daily budget, §4.9)
  but opens no case and never hides the name.
- **Threshold window.** Only reports with `CreatedAt >= case.OpenedAt` count. Without it, a name
  a moderator restored would be re-hidden by the very reports that were already judged plus one.
- **Renaming back to a confirmed-removed name** is refused (`400 "This name isn't allowed"`),
  otherwise a player could re-adopt a name a moderator removed and the confirmed case would block
  it from ever being re-hidden.
- **Rescan skips names with a `Restored` or `Confirmed` case** — a moderator already decided.
- **Alerts are queued, not sent in the request.** `IModerationAlerts.Raise` writes to a bounded
  in-memory queue drained by a `BackgroundService`, so a report never waits on SMTP. A dropped
  alert (queue full / restart) is recoverable: every alert is logged when raised and the case row
  is the source of truth.
- **The rename checks live in `UserService.UpdateProfile`** (superseded the round-1
  `[FromServices] IModerationService` + `CheckRenameAsync` call in the controller, §4.9), so the
  `UsersController` constructor is unchanged.
- **Rescan uses offset paging ordered by `Id`**, not keyset on `Guid` (translation of `Guid`
  comparison is not guaranteed). Hides never remove rows; a mid-scan registration can shift a page,
  which is harmless because that name passed the blocklist at registration.

### 4.8 Review fixes (#194 agent review)

- **Blocker, fixed:** a player could rename straight back to an auto-hidden name, after which no
  path could hide it again. Now a rename to a name with an `AutoHidden` (or `Confirmed`) case is
  refused, Confirm always attempts the hide, and reports may re-hide under an `AutoHidden` case.
- The daily report limit is checked **before** the moderator-target test, so at the limit a
  moderator answers 429 like everyone else and the endpoint can't reveal who moderates.
- A rename always writes `NameHiddenAt = NULL`. EF used to skip the column when it was already null
  at load time, so a hide committing mid-rename left the new name flagged as hidden.
- Restore only applies while `User.NameHiddenAt == case.HiddenAt`, so restoring an older case can't
  undo a newer hide of a different name.
- Confirm, restore and rescan lock the `Users` row before the case row, the same order reports use.
  This removes a report↔confirm deadlock, and a report can no longer insert the case between
  rescan's read and its insert.
- The rescan summary email is sent from `finally`, so names already hidden are reported even if
  the scan fails part-way.

### 4.9 Review fixes, round 2 (#194 agent review)

- **The rename is one locked transaction.** `PATCH /api/users/{id}` with `displayName` makes one
  call, `UserService.UpdateProfile`, which (inside `CreateExecutionStrategy`, after
  `ChangeTracker.Clear()`) locks the player's `Users` row `FOR NO KEY UPDATE` — the same lock,
  taken first, as reports, confirm, restore and rescan — then runs the rename gate (locked /
  removed name), re-reads the user and saves, marking `DisplayName` and `NameHiddenAt` modified.
  It returns `ProfileUpdateResult { Status: Updated | NotFound | NameLocked | NameRemoved, User? }`,
  which the controller maps to `200` / `404` / `409 name_locked` / `400`. The wire contract is
  unchanged. This closes two races: a confirm committing between the old unlocked check and the
  save let a player re-adopt a `Confirmed` name; a hide committing while a profile save resent the
  current name left the placeholder showing with `NameHiddenAt = NULL`, which restore could never
  match. `IModerationService.CheckRenameAsync` is removed (it was only safe under the lock).
- **Re-hiding under any status but `Restored`** (defence in depth). A report at or above the
  threshold, or a confirm, hides a name that is showing under an `Open`, `AutoHidden` or
  `Confirmed` case. A `Confirmed` case keeps its status (so it can't then be "restored") and a
  repeat confirm never adds a second strike.
- **Rename-back check ignores letter case and normalises snapshots.** The player's few
  `AutoHidden`/`Confirmed` snapshots are loaded, each normalised with `NormalizeDisplayName`
  (the stored text is used if it is ill-formed UTF-16) and compared to the request with
  `OrdinalIgnoreCase`. "Rude Name" → "rude name" is refused, and so is a snapshot stored before
  #189 (smart apostrophe, decomposed accents).
- **A report of a moderator spends the reporter's budget.** It is inserted like any report, after
  the daily-limit check, and then short-circuits: no case, no hide, no alert, `Ignored` → `204`.
  Before, it inserted nothing, so at limit − 1 a report of a candidate followed by one of a fresh
  player answered `429` (candidate counted, not a moderator) or `204` (a moderator). Such rows are
  never counted later: a case window opened after the player leaves the allowlist starts after
  them, and the queue counts only reports inside a window. **Accepted edge:** if a case for that
  exact name was already open before the player became a moderator, reports filed while they
  moderate fall inside its window and show in the queue; a moderator still decides, and reports
  can't hide a moderator's name. A reporter who reported the name while its owner moderated can't
  report the same name again after demotion (unique per reporter, target and name).
- **`FOR NO KEY UPDATE` instead of `FOR UPDATE`** on the `Users` row (`ModerationLocks`). It still
  conflicts with itself and with `UPDATE`, so it serialises every moderation write, but not with
  the `FOR KEY SHARE` lock a `NameReports` foreign-key check takes on the reporter's row. A→B
  racing B→A no longer deadlocks.
- **One reporter's reports are serialised**, so concurrent reports against different targets
  can't each count N − 1 and overshoot the daily limit. **Deviation from the suggested fix** (lock
  the reporter's `Users` row as well, both rows in `Guid` order): leaderboard, decay,
  hex-count reconciliation and territory code update many `Users` rows in no fixed order, so a
  second row lock in reports could deadlock with them. Reports instead take a transaction-scoped
  advisory lock on the reporter first — two-key form in its own namespace (`NREP`), which never
  overlaps the one-key advisory locks `TerritoryService` and `LeaderboardService` use. Nothing that
  holds a lock ever waits for it, so it can't join a deadlock cycle. Reporters whose 32-bit keys
  collide are merely serialised with each other.
- **Unlock is audited.** `UnlockNameAsync(userId, moderatorUid)` logs the moderator's UID
  (structured), like confirm and restore.
- **Options are validated at startup.** `Moderation:Email`, when enabled, needs a port in
  1–65535 and a `From` and every `To` that parse as a mailbox with a domain. `Moderation` refuses
  a blank moderator UID (it could never match and would silently leave that moderator out).
- **Flutter shows the `name_locked` message.** `ApiService.extractApiError` also reads `message`
  (after `error`), so a `409 { code, message }` body reaches the player instead of the generic
  save error.
- **Account deletion purges moderation rows explicitly.** `UserService.DeleteUserData` deletes
  the player's `NameReports` (both directions) and `NameModerationCases` in its transaction, per
  its "no reliance on cascades" contract; the DB cascades remain as a second line.

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

`/user-profile` screen: ⋮ menu with **Report name** (reason sheet → `POST name-reports` → "Thanks,
we'll review it") and **Block / Unblock player**. Hidden for my own profile.

---

## 7. Contact information (Guideline 1.2 bullet 4)

`ProfileScreen` gains a **Contact support** row → `mailto:` via the existing `url_launcher`
dependency. Address held in `AppConstants.supportEmail` (**address needed from product**).
The same address must be the App Store Connect Support URL/contact.

---

### 7.1 Implementation notes (PR 3) — deviations from the above

- **Support address is a build flag**, `--dart-define=SUPPORT_EMAIL=…` (decision 2026-09-22), like
  `API_URL`: the address never lives in the repo. In a build without it, tapping the row shows a
  "not configured" snackbar and logs a warning — **release/TestFlight builds must pass it**, and it
  must match App Store Connect.
- **Masking changes the name only, not the avatar.** Avatars are one of 12 fixed emoji, not
  user-generated content, so there is nothing to moderate in them.
- **Inbox masking moves to PR 4**, which adds `actorUserId` to inbox items — masking needs the id.
  PR 3 masks the leaderboard, map hex popup and the player's profile screen.
- **Leaderboard "is this me?" now compares user ids, not display names.** Names are not unique
  (DR-002c), so another player with my name was highlighted as me and could not be tapped; masking
  would also break a name comparison.
- **Stale-fetch race fixed:** a slow block-list fetch at sign-in could overwrite (in state and on
  disk) a block made while it was in flight. Fixed by the edit overlay described under the review
  fixes below. Regression test fails without the fix.
- **Review fixes (#195 agent review):**
  - The stale-fetch guard discarded the whole server list whenever a block was made during a slow
    load. The notifier now keeps this session's edits and applies them on top of every cached or
    fetched list. A failed edit rolls back only its own id.
  - In-app theft alerts are masked when they are created, and grouped by thief id, not name (so
    two same-named thieves no longer merge). This part no longer waits for PR 4.
  - The leaderboard and the map masks names at render time and pass the *raw* name to the profile
    screen, which masks it itself. So after Unblock, the header shows the real name.
  - Contact Support never fails silently: with no mail app it shows the address, and a build
    without `SUPPORT_EMAIL` says so and logs a warning. The build-time guard belongs with #181's
    fail-closed release config (follow-up once both merge).
- **Review fixes, round 2 (#195 agent review):**
  - The app root keeps `blockedUsersProvider` alive from app start, so the list starts loading the
    moment an account signs in, not when the first theft event arrives. Theft alerts (written to
    the persisted inbox) and the map hex popup also wait for the list's first load
    (`BlockedUsersNotifier.blockedIdsFor`: the cached list, or the first fetch when there is no
    cache) instead of reading the still-empty initial state. Chosen over storing the actor id on
    the alert because that is PR 4's inbox change; awaiting costs one local file read.
  - A failed block/unblock restores the id's previous edit, not "no edit", so an older server list
    can't undo an earlier successful edit.
  - A first load that failed (offline with no cache, or a 5xx) is retried on app resume and hub
    reconnect (`resyncTriggersProvider`, the trigger the other hydrated slices use). Once a fetch has
    succeeded, the triggers don't re-fetch.
  - The block limit is exact: the count and insert run in an execution-strategy-wrapped transaction
    behind a per-blocker advisory lock (two-key namespace `UBLK`, beside the reporter lock). A
    target deleted between the existence check and the insert (FK violation 23503) is `404`, not
    `500`.
  - **One label per kind of surface.** A theft alert names a blocked thief **"A player"**, in push
    and in-app alike (`GameConstants.BlockedActorLabel` / `blockedActorLabel`): the same event now
    reads the same in both places, and a lock screen doesn't reveal a block. Where the name stands
    alone — leaderboard row, map popup, profile — it stays **"Blocked player"** (`blockedPlayerLabel`,
    §6), because the viewer needs to see why the name is hidden and find the player to unblock.
- **Review fixes, round 3 (#195 agent review):**
  - The block-limit race test inserted a block that was already seeded (duplicate key) and so never
    exercised the lock. It now seeds `MaxBlocksPerUser + 2` users and races two unseeded targets.
  - **Account switches can't leak a list.** In Riverpod 3 a rebuild keeps the Notifier instance and
    `ref.mounted` stays true, so the previous account's in-flight load, fetch or edit used to write
    into the next account's state, finish its first load and re-cache the old list after sign-out.
    `build()` now bumps a generation; every async step captures it and drops its result once it
    has moved on, and each load completes the completer it started with.
  - **Overlapping edits to one id:** only the newest in-flight edit to an id changes what is shown.
    An older edit that fails meanwhile doesn't roll back over it; a refusal rolls back to the last
    edit the server accepted, else to the server list.
  - **Map hex popup waits at most `blockListPopupWait` (2 s)** for the first load, so a slow network
    can't make a tap look ignored. If the list still isn't known, another player's name is shown as
    "A player" (`blockedActorLabel`), never the raw name; the viewer's own hex shows their name.
  - **Known gap, accepted until PR 4:** sign-out clears the block-list cache, so every sign-in
    starts without one. If that first fetch fails (a 5xx, or offline) while theft events arrive,
    `blockedIdsFor` returns the empty list and the in-app alert is saved to the inbox with the
    thief's raw name. The retry on resume/reconnect fixes masking from then on, but not alerts
    already written. PR 4 stores `actorUserId` on inbox items and masks at render time, which
    closes this.
- **Account deletion purges `UserBlocks` explicitly, both directions** (blocks the player made and
  blocks against them), alongside PR 2's `NameReports` / `NameModerationCases` purge in
  `UserService.DeleteUserData`; the FK cascades remain a second line.
- **Block-list cache is cleared by `UserSessionTeardown.clearUserBoundState`**, the single
  sign-out / account-deletion path on master, not by each screen.
- **Found, out of scope:** the login screen's Terms/Privacy links point at the dev ngrok tunnel
  (`login_screen.dart:154,160`) — dead links in a production build, and an App Store review risk.

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
| Two concurrent third reports → double hide / double email, or both count 2 → missed hide | **Mitigated** — `FOR NO KEY UPDATE` on the target row + conditional `UPDATE … WHERE DisplayName = @snapshot` |
| Rename racing a hide or a moderator decision (re-adopted confirmed name; placeholder with no hide flag) | **Mitigated** — rename checks and saves in one transaction under the same row lock (§4.9) |
| Two players reporting each other at once deadlock | **Mitigated** — `FOR NO KEY UPDATE` doesn't block FK key-share checks (§4.9) |
| Moderator identity probed via the report response or budget | **Mitigated** — moderator targets answer `204` and spend budget like any report (§4.9) |
| Concurrent reports by one player overshoot the daily limit | **Mitigated** — per-reporter advisory lock (§4.9) |
| Execution-strategy retry duplicates side effects | **Mitigated** — alerts/broadcast post-commit outside the retried block; inserts are `ON CONFLICT DO NOTHING` |
| Lost alert after ambiguous commit | **Accepted** — case still visible in `GET /cases` |
| Brigading (3 friends wipe a rival's name) | **Accepted by design** — victim renames immediately; no strike without a moderator |
| Report spam by one account | **Mitigated** — unique per (reporter, target, name) + 10/day (serialised per reporter) + existing global rate limiter |
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
| Report stores reporter identity (PII) | **Mitigated** — explicit purge (and cascade) on account deletion; never included in alert emails. App Store privacy label: check whether "Other User Content" must be declared (UNVERIFIED) |
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
