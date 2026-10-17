Task: #<!-- number -->
Design doc (FR work only): <!-- docs/versions/<release>/<version>/design/frN-<name>.md -->

## For the user

<!-- CLAUDE.md "Explain every change from the user's side": for each change, three plain lines as if to an end
user — What you'll notice / The problem today / The fix. No code names, file paths or jargon. -->

## What & why

<!-- Explain the "why", not just the "what". -->

## Pre-PR Skill Gate

<!-- Go through EVERY row of both gate tables in CLAUDE.md (Pre-Check-in and Pre-PR) against the
changed files: git diff --name-only master...HEAD. Don't pick rows by what the PR is "about".
One line per row that applies: the row → `skill`, run on <commit>: <result>.
"PR rules" fails if a skill a changed file requires (.github/gate-rows.tsv) isn't in Skills run,
or if any gate skill is not named below. -->

- 

**Skills run:** <!-- only skills actually invoked on the head commit, in backticks; "none" if none. Never from memory. -->

<!-- Every other gate skill, one line each (several skills may share a reason):
- Not applicable: `skill` — <why no changed file or behaviour triggers it> -->

<!-- Over ~15 files / ~400 lines? Split the PR, or add a line: "Size exception: <reason, agreed with the owner>" -->

## Independent review

<!-- One line per reviewed commit, newest last: REVIEWED <commit> — <result, and what was fixed>. The latest commit must be listed. -->

## Testing

<!-- How was this verified? -->
