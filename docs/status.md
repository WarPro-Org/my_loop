# MyLoop — where we are

Read this first in every session; the start-of-session hook prints it. Every PR that changes what is below
(an FR step, a PR opened or merged, an owner to-do done) updates this page in the same PR, written as the state
**after** that PR merges. Keep it under a screen: details live in the linked items.

**Last updated:** 2026-10-13, with the PR that added this page.

## Now

- **Version:** 0.1 (single-player rebuild). Spec: `docs/versions/1/0.1/requirements.md`. Parent task: #198.
- **FR1** (game rules): done, closed 2026-10-07. Record: `docs/versions/1/0.1/records/fr1-game-rules.md`.
- **Next:** FR2 (walk session: start, pause, stop), Gate 1 requirement grill. Load `myloop-srdp-gates` first. No
  task, design doc or branch exists yet.

## Open PRs

None besides the one that adds this page.

## Waiting on the owner

- Make "PR rules" a required status check on `master`, so a red check blocks merging (#230–#232 merged red).
- Pick squash or rebase merges and make the repo setting and CLAUDE.md agree (#229–#234 were rebase-merged;
  CLAUDE.md says squash only).
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
