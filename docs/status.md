# MyLoop — where we are

Read this first in every session; the start-of-session hook prints it. Every PR that changes what is below
(an FR step, a PR opened or merged, an owner to-do done) updates this page in the same PR, written as the state
**after** that PR merges. Keep it under a screen: details live in the linked items.

**Last updated:** 2026-10-17, with FR2's server settings PR (3/7).

## Now

- **Version:** 0.1 (single-player rebuild). Spec: `docs/versions/1/0.1/requirements.md`. Parent task: #198.
- **FR1** (game rules): done, closed 2026-10-07. Record: `docs/versions/1/0.1/records/fr1-game-rules.md`.
- **FR2** (walk session: start and stop), task #236: Gate 1 and Gate 2 done. Spec decisions (Pause dropped; walk
  diary #44, closed app ends the walk #45, sign-out #46; auto-end in a vehicle or after 10 minutes still, with
  warnings; each loop sent when it closes) and the approved design doc `design/fr2-walk-session.md` (owner decisions
  O1–O11, early blind audit `audits/2026-10-14-fr2-early-blind-audit.md`) merged with PR 1/7 (#237). PR 2/7 fixed
  the gaps a re-check of the design and its review found. PR 3/7 added the server `AutoEnd` settings (rules version
  2), the six new phone fields, and the saved-copy upgrade (O10). Deploy the server before any app release with it:
  a new app on an old server rejects every rules reply and keeps its rules.
- **Next:** FR2 PR 4/7 (value floors, walk diary store, debug viewer) on `v0.1/fr2-diary`. Load
  `myloop-tasks-and-prs` first.

## Open PRs

None.

## Waiting on the owner

- Make the cloud environment's setup script install `dotnet` and `flutter`, so every session can run
  `scripts/verify.sh`. What worked on 2026-10-17 (`builds.dotnet.microsoft.com` is still blocked):
  `apt-get install -y dotnet-sdk-10.0` (Ubuntu's archive) and Flutter 3.44.0's Linux archive from
  `storage.googleapis.com/flutter_infra_release` unpacked into `/opt/flutter-sdk`.
- Before FR2 PR 3/7 merges: the indoor walk test for the 250 m "still" cap, on a real phone (design, O3), saved in
  `audits/`; if it needs 400 m, PR 3/7 changes `AutoEnd:StillMaxWalkedMeters` and the built-in copy before merging.
- Before FR2 PR 6/7 merges, on a real iPhone: warnings while the app is suspended, the notification package next to
  Firebase messaging, and whether a stopwatch keeps counting while the phone sleeps; on a real Android 13+ phone:
  whether refusing notifications hides the tracking notification.
- Before FR2 PR 7/7 merges, on a real iPhone: turning off precise location with the app in the background ends the
  walk with that reason.
- Make "PR rules" a required status check on `master`, so a red check blocks merging (#230–#232 merged red).
- Pick squash or rebase merges and make the repo setting and the `myloop-tasks-and-prs` skill agree (#229–#234
  were rebase-merged; the skill says squash only).
- Delete the old FR1 branches (this session can't): `v0.1/fr1-configurable-game-settings`, `v0.1/fr1-design-doc`,
  `v0.1/fr1a-rules-module-api`, `v0.1/fr1b-server-uses-rules`, `v0.1/fr1c-app-uses-rules`,
  `v0.1/fr1d-fixes-contract-tests`, `v0.1/fr1f-spec-updates`, `v0.1/fr1g-audit-gaps`, `v0.1/fr1g-audit-server`,
  `v0.1/fr1h-audit-app`, `v0.1/fr1h-audit-app-2`, `v0.1/fr1i-audit-followups`.

## Known open problems owned by later FRs

Data loss in old beta code (stealing, decay, startup wipe of explored hexes) — FR6, FR7; seeded bots — FR13;
unbounded sign-in step for non-rules requests — FR3. Each is a bullet in that FR's spec section.

## Working habits

- One session per task (an FR part, a bug); end it by updating this page and the task.
- CLAUDE.md holds the core rules; load the workflow skill for the step (`myloop-*`).
