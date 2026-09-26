---
name: state-lifecycle-consistency
description: Use when adding or changing app state that is loaded, saved, cached, synced from the server, or pinned for a walk (rules, profile, queues, caches). Fills a lifecycle matrix (every reader × every app moment), writes one test per cell through the real trigger, and proves each test fails without its fix — so gaps are found by the author, not the user.
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
Before committing any change that adds or changes state which is read from disk, fetched from the
server, cached, queued, or captured at the start of a walk/session.

## Step 1 — List the readers
Every place that reads the state (grep the provider/field). For a pinned value, list **each use**
of the pinned copy separately (e.g. GPS filter AND loop estimate).

## Step 2 — Fill the matrix (in the PR description)
Rows = readers. Columns = moments. Each cell: expected value + the test that proves it, or
"accepted: <reason>" agreed with the user.

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
| Corrupt / unreadable saved copy | Falls back, still refreshes. |

## Step 3 — Test rules for every cell
- **Use the real trigger**, not a shortcut: fire the lifecycle event, the reconnect handler, the
  sign-out teardown — never call `refresh()` by hand in a test that claims "resume refreshes".
- **Make the real code fail; never fake its result.** A crash test injects a failure into the
  real save (a seam such as an injectable rename step) — it never writes the "after crash" file
  itself.
- **A "nothing happened" assertion needs a positive control first.** Before asserting "the fix was
  ignored", assert the flow is live (status tracking, no error, a good fix IS counted).
- **Prove each test fails without its fix.** Break the fix (one at a time), run, see red, restore.
  List in the PR: "test X — fails when Y is removed".

## Step 4 — Review
The independent review gets the matrix and must (a) look for a missing row/column, (b) break at
least one fix per new test to confirm it goes red. A review that only reads the diff is not done.
