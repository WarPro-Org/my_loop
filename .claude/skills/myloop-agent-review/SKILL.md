---
name: myloop-agent-review
description: How MyLoop's independent agent reviews a commit or PR: short human-style findings (what is wrong, how it affects the user, what to change), Task-line check, scenario IDs, gate rows, lifecycle matrix, working through every gate skill's checklist, and re-running a red check in a scratch worktree. Use when reviewing, and paste its name into every reviewer agent's prompt.
origin: MyLoop (moved from CLAUDE.md to keep it small)
---

# Code reviews by an agent

Moved word for word from CLAUDE.md. Every review report ends with `REVIEWED <commit>`.

**Code reviews by an agent**
- Whenever the user asks for a new agent to review code, the agent reviews like a human teammate would:
  short, on point, plain language — no long technical essays.
- For each problem: **what is wrong**, **how it affects the app for the user**, and **what to change** — a few lines each.
- Only real problems; no praise, no padding. If nothing is wrong, say so in one line.
- Reading the diff is not enough. The reviewer also:
  - checks every commit in the PR ends with a `Task: #N` line, and reports any that doesn't;
  - checks the PR against every `docs/scenarios.md` ID its area touches; any finding that no ID covers is reported
    as "new scenario" and gets an ID in the fix;
  - checks the PR's gate section against the changed files and every row of both gate tables, and reports a row
    that applies but wasn't run, or a "Not applicable" whose reason is wrong, as a finding;
  - for state covered by `state-lifecycle-consistency`, checks each changed reader against every moment in that
    skill's matrix and reports any moment nobody handled;
  - works through the checklist of every gate skill the PR lists as run — always including `solid-architecture`
    for production C# or Dart — and reports each box that fails, so no skill is checked only by the author;
  - re-runs at least one of the author's "red when Y is removed" checks per new test, breaking code only in a
    scratch worktree (`git worktree add <tmp> HEAD`, removed afterwards) — a test that stays green guards nothing.
