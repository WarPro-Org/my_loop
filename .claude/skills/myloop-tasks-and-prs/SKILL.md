---
name: myloop-tasks-and-prs
description: MyLoop's rules for GitHub tasks, branches, PRs and merges: task format and sections, keeping tasks and linked items in sync, branch names, PR size, stacked PR merges, going through the gate rows one by one, and what the "PR rules" check enforces. Use before writing a commit message (Task line), creating or updating a task, opening, describing or merging a PR, or filling a PR's gate section.
origin: MyLoop (moved from CLAUDE.md to keep it small)
---

# Tasks, branches and PRs

Moved word for word from CLAUDE.md. CLAUDE.md keeps the core rules and the checklist; this skill holds the procedure.

**User stories (GitHub tasks)**
- One task per requirement (FR). Task title: `0.1 > FR1 > <short title>`. PR title: `0.1 > FR1 (k/N) > <short title>`,
  with "Part k of N" in the description.
- Body is short — readable in under a minute. At creation it has the sections below; while the work runs it grows
  the later sections in the order set under "Task sections" (Keep tasks up to date):
  - **Story:** As a …, I want …, so that …
  - **What:** what we will build (2–4 bullets).
  - **Why:** the reason, with requirement IDs (e.g. `#20`).
  - **How:** the approach in 2–4 bullets — no code.
  - **Acceptance criteria:** a checklist that can be tested. If the story adds state covered by
    `state-lifecycle-consistency`, the criteria cover every app moment in that skill's matrix. The user must never be the one to find a missing case.
- Show the draft to the user and create the task **only after they approve it**.

**Branch and merge per requirement**
- Every FR gets its own branch named with version and title: `v0.1/fr1-configurable-game-settings`.
- Work is pushed there and opened as its own PR.
- A PR merges into `master` only after (1) an independent agent review and (2) the user's own review.
- **Every check-in gets an independent agent review.** Order for every change:
  Pre-Check-in skills → commit and push → update the task → independent agent review against the task and the
  requirement (short, human-style — see below) → fix what it finds (and review the fix) → Pre-PR skills → the user's final review → merge.
  Never ask the user to review work the agent hasn't reviewed.
- Keep each PR small enough to review: about **15 files / 400 changed lines**. Split a bigger FR into
  several PRs (e.g. server module → server wiring → app), each on its own `v0.1/frN-<part>` branch.
- Stacked PRs (each based on the previous one's branch) are merged **in order**. This repo allows only squash merges,
  so after each merge: retarget the next PR to `master`, merge `master` into its branch, check build and tests, then
  push (pushing after the retarget makes CI run against `master`).
  - Keep each next branch up to date: after every check-in on a parent, merge the parent into the next branch.
    Then the next branch already holds every parent fix, and a conflict with `master` is only the parent's own
    lines coming back in squashed form.
  - Before resolving, check `git diff <parent's final commit> <next branch>` shows only the next PR's own changes;
    if not, merge the parent's final commit in first.
  - Per conflicting file: keep the next branch's version only if `git diff <parent's final commit> master -- <file>`
    is empty (the conflict is only the parent's squashed lines). Otherwise another PR changed it too: resolve by
    hand and keep both changes. Never drop a line the parent or another PR changed.

**Keep tasks up to date (no info lost)** — applies while building and merging, not only while planning.
- **FR task** ends with a `## Progress` section:
  - a table: PR | what it does (one line) | status (merge commit once merged);
  - under it, a check-in log grouped by PR: `commit — what changed and why`, one line each, clear without the chat.
    Every check-in is in the log; commits with the same purpose may share a line (`a1b2c3d, e4f5a6b — …`).
- **Every check-in is attached to its task:** each commit message ends with a `Task: #N` line, so GitHub lists it on
  the task's timeline, and the PR that carries it links the task. Every commit has a task: the FR task, or a
  process or bug task created before the first commit (the parent version task for a one-off small fix). Rules that
  come out of closing an FR may ride on its close-out PR under the FR task; the parent task gets a "—" row for
  them.
- **Task sections, in this order:** Summary (once the FR is done) · Story · What · Why · How · Decisions · Left to
  later FRs · Acceptance criteria · Process notes · Progress. Decisions hold only what shapes the app (behaviour, data,
  contracts, limits) with the reason. Process mishaps and record gaps go in Process notes, one line each.
- **Parent version task** ends with a `## Progress` table: FR | task | what it does (one line) | status — no commit log.
  Work not tied to an FR (process, bug fix) gets a row there with FR "—"; if it has its own task, that task gets
  the FR-task format.
- A PR closed without merging, or split, keeps its row: "Closed — replaced by #… because …".
- Decisions and deviations (a value kept, work moved to a later FR) go in Decisions or Left to later FRs, with the
  reason; process mishaps go in Process notes.
- When: in the same turn as every check-in, PR opened or closed, review result and merge — before reporting to
  the user. When a PR merges, tick the criteria it meets; after the last merge, close the task and mark it done in
  the parent.
- A change of plan updates the task's What / How / Acceptance criteria after the user agrees, together with the spec.
- Write for someone reading it in 10 years: short, plain words, no chat references, no unexplained jargon; link PRs.

**Keep linked items in sync** — one piece of work touches the spec, the design doc, the FR task, the parent version
task and every PR of that FR. When any of them changes, update all the others in the same turn:
- The FR record (once the FR is closed) is one of these items.
- A new PR for an FR renumbers all of its PRs to `(k/N)`, in merge order, in every title and in every
  description's "Part k of N" line and PR list, including merged PRs. For example, 3 PRs become 5 when a design
  doc and a fix PR are added.
- New findings (gaps, decisions, extra work) go into the design doc, the FR task's What / How / Decisions /
  Acceptance criteria, and the Progress table, not only into chat or a PR.
- A PR's status changes (opened, reviewed, merged, closed) update the FR task and the parent task.
- Before reporting to the owner, check each linked item says the same thing.

**Going through the gate rows** and **Enforced on GitHub** (both from CLAUDE.md "Gates are mandatory"):

**Going through the gate rows.** Never pick rows by what the PR is "about": a one-line comment edit in a Dart file
or a test still triggers the Dart and test rows. List the changed files (`git diff --name-only master...HEAD`), then
take **every** row of both gate tables in turn. Each skill ends up either in "Skills run" (invoked on the head
commit) or on its own line ``- Not applicable: `<skill>` — <reason>``. A file that matches a row's pattern in
`.github/gate-rows.tsv` means that skill applies, and "PR rules" fails without it. A row no file pattern can
decide (state kept across launches, error handling, hex counts, anti-cheat logic) is judged by what the change does.

**Enforced on GitHub** — so a forgotten step shows up as a red check the owner sees. It can't catch a false
claim; the owner's review and the review records in the PR are what keep claims honest.
- **CI** proves build, tests and analyze on every commit (`scripts/verify.sh` runs the same steps locally).
- **"PR rules"** (`.github/workflows/pr-rules.yml`, re-runs when the description is edited). The script always
  comes from master (for a stacked PR: as long as its base branch's `pr-rules.yml` is unchanged from master),
  so a PR can't loosen the check that judges it. A PR stacked on another branch gets the
  check only once that branch has the workflow, and every PR does once it is retargeted to master. **A missing
  "PR rules" check counts as not passed.**
  - Claude-made PRs (session link in the body, or a `claude/` branch) and FR PRs need the gate section, a
    filled "Skills run", and a line starting `REVIEWED <commit>` for the **latest** commit. Every push turns it red until that commit is reviewed and recorded.
  - If such a PR changes code (anything but `docs/`, `.claude/` and `*.md`): every skill a changed file requires
    (`.github/gate-rows.tsv`, plus the removals gate for a deleted file and `verification-loop` always) is in
    "Skills run", and every skill in the two gate tables is named, as run or ``- Not applicable: `<skill>` — <reason>``.
  - FR PRs (branch `vX.Y/frN-…`) need a task link line, "Part k of N" matching the title's `(k/N)`, and FR N's
    design doc already merged into master. A docs-only PR that adds the design doc is the exception. When the
    design doc merges, re-run "PR rules" on the FR's open PRs (a push or a description edit does it).
  - Every PR: `docs/scenarios.md` keeps every ID it had on master. Every FR design doc's `## Scenarios` table
    answers every ID exactly once, outside comments and code fences:
    - `covered` names an existing test file and a test name found in it;
    - `n/a` and `accepted` give a reason;
    - `open` names an owner;
    - `n/a` on a `[search]` ID starts with `searched:` and says what was searched (10+ characters).

    Claude-made and FR PRs that change code also need a `**Scenarios:**` line naming known IDs, or
    `none — <reason>`.
  - Every PR: every file with a delete, update, raw SQL, file rewrite or ownership change matching the patterns in
    the script (listed in `docs/data-removals.md`, with their blind spots) is one row there. Each row names a file
    that exists, appears once, has a verdict `keeps #N`, `keeps none — <reason>` or `breaks #N`, and an owner for
    `breaks`.
  - Every PR: a design doc new on this PR has a `## Early blind audit` section linking a saved report under
    `audits/` (it doesn't check that the report belongs to that FR).
  - Every PR: every docs folder, top-level docs file and kind of version subfolder is named in the Docs map.
  - Any PR over the size limit needs a `Size exception:` line.
  - Bot PRs are skipped.
