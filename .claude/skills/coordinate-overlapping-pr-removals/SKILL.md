---
name: coordinate-overlapping-pr-removals
description: Use when a PR deletes a method, endpoint, DTO, or file, or when two open PRs touch the same symbol. Prevents the hidden conflict where merging a removal strands another open PR — both a git conflict and a test-compile failure on master.
origin: extracted-from-session-2026-06-26
---

# Coordinate merge order when a PR removes code another open PR edits

## When to use
Before merging any PR that **deletes** a method/endpoint/DTO/file, and whenever two open PRs touch the
same symbol. This is the cross-stack/contract-drift bug class CLAUDE.md flags as MyLoop's #1.

## The trap (real case)
PR #61 removed `ProcessTrailClaim`/`ProcessStepClaim`. Open PR #57 was independently editing those same
methods and had just gone green. #61 merged first →
- #57 became `CONFLICTING` (git can't 3-way-merge edits whose surrounding code was deleted), AND
- #57's tests stopped **compiling** against master (they called the deleted methods) — a build failure,
  not a textual conflict, invisible until CI re-ran.

A removal's own diff and CI look clean; the damage lands on *other* PRs.

## Checklist before merging a removal
1. List open PRs touching the deleted symbols: `gh pr list --state open`, then grep each
   (`gh pr view N --json files` / its diff) for the methods/types/routes you delete. Don't trust memory.
2. For each overlap, decide merge order explicitly and state it in BOTH PR descriptions.
3. Check the other PR's **tests**, not just production hunks — a test referencing a deleted symbol breaks
   the build on master.
4. After merging the removal, immediately re-check overlapping PRs' `mergeable` and comment with concrete
   rebase steps: keep hunks on surviving paths, drop hunks on deleted code, rewrite affected tests.
5. Prefer landing the smaller/older PR first so the removal rebases over it rather than stranding it.

## Why it's missed
Each PR is individually green and coherent; the conflict is emergent from merge order and lives in the
intersection no single PR's review or CI covers. Flagging the overlap in the description is necessary but
not sufficient — the merge-order decision must be enforced at merge time.
