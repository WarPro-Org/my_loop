---
name: state-lifecycle-consistency
description: Use when adding or changing app state that is kept across launches (saved to disk) or pinned for a walk AND read by more than one place (rules, saved profile, offline queues). Fills a lifecycle matrix (every reader × every app moment), writes one test per cell through the real trigger, and proves each test goes red when the behaviour it guards is removed — so gaps are found by the author, not the user.
origin: extracted-from-session-2026-09-26 (FR1 rules)
---

# State lifecycle consistency

## Why this exists
In FR1 the user had to ask "are rules applied when offline, back online, signed out, killed,
mid-walk?". The code had been reviewed several times, but reviewers read the diff line by line
and never asked "what does each reader see at each moment of the app's life?". Answering that
question later found:
- a **real bug**: a walk started right after launch pinned the built-in rules, because the saved
  copy was still loading (async load, sync reader, no "ready" wait);
- a **test that could not fail**: the "crash mid-save" test wrote the half-file itself instead of
  making the real save stop, so removing write-then-rename kept it green;
- a **test that could pass for the wrong reason**: "the fix is ignored" was checked by "the path
  didn't grow", which is also true when the walk never started;
- **half the pinned values untested**: only the GPS filter was checked, not the loop estimate.

## When to Activate
State that is **kept across launches** (saved to disk) **or pinned for a walk**, and is **read by
more than one place**. A provider that just fetches and shows data does not qualify. For disk
queues and caches, run this alongside `flutter-disk-concurrency-test`.

- **Design time (Gate 2):** build the matrix in the design doc. That is its one home (on the bug
  track: the Bug Report's affected rows).
- **Each commit:** update the matrix for the readers this commit adds or changes; their cells'
  tests are due in the same commit. Readers a later PR adds get their tests in that PR (fits the
  split server → wiring → app PRs and the 0.x "tests land with the story" rule).
- **PR:** copy the current matrix into the PR description.

## Step 1 — List the readers
Every place that reads the state (grep the provider/field). For a pinned value, list **each use**
of the pinned copy separately (e.g. GPS filter AND loop estimate).

## Step 2 — Fill the matrix (design doc; copied into the PR)
Rows = readers. Columns = moments. Each cell: expected value + the test that proves it, or a
one-line "accepted: <reason>" when the cell is harmless or out of scope (agreed with the user).

| Moment | What to check |
|---|---|
| Cold start, before the saved copy has loaded | Does any reader act on the built-in/default copy? It must wait (e.g. a `ready` future) or be harmless. |
| First launch, offline, nothing saved | Built-in copy works. |
| Offline / server error / 401 on refresh | Current value kept, nothing half-applied. |
| Back online (reconnect) and back to the app (resume) | Refresh really fires from that trigger. |
| Sign in / sign out / switch account | User-bound state cleared; shared state kept. |
| Killed mid-save | Old copy intact; next save works. |
| Two updates at once (start + login refresh) | One wins cleanly; nothing lost. |
| During a walk | Pinned copy used by every reader; next walk uses the new value. |
| Killed mid-walk, then relaunched | A resumed or drained walk uses the rules pinned at its start (or the server judges it) — never the built-in or a newer copy by accident. |
| Corrupt / unreadable saved copy | Falls back, still refreshes. |

## Step 3 — Test rules for every cell
- **Use the real trigger**, not a shortcut: fire the lifecycle event, the reconnect handler, the
  sign-out teardown — never call `refresh()` by hand in a test that claims "resume refreshes".
- **Make the real code fail; never fake its result.** A crash test injects a failure into the
  real save (a seam such as an injectable rename step) — it never writes the "after crash" file
  itself.
- **A "nothing happened" assertion needs a positive control first.** Before asserting "the fix was
  ignored", assert the flow is live (status tracking, no error, a good fix IS counted).
- **Prove each test can fail.** Break the behaviour the test guards (one change at a time — for
  new features too, not only bug fixes), run, see red, restore. Record it in the matrix:
  "test X — red when Y is removed".

## Step 4 — Review
The independent review gets the matrix and the "red when Y is removed" list. It must (a) look for a
missing reader or moment, (b) re-run at least one "red when" per new test. Breaking code is done
only in a scratch copy (`git worktree add` or `git stash`) and reverted before reporting; the
author's tree is left clean. A review that only reads the diff is not done.
