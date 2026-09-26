#!/usr/bin/env bash
# Tests pr-rules.sh's gate-row check. Each case builds a throwaway repo holding this checkout's
# CLAUDE.md, gate-rows.tsv and skill folders, makes a PR merge commit with the given changed files,
# and runs the script on it. Exits 1 if any case gives the wrong result.
set -uo pipefail

root=$(git rev-parse --show-toplevel) || exit 1
script="$root/.github/scripts/pr-rules.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0
readonly SESSION=$'\nhttps://claude.ai/code/session_test'

g() { git -c user.email=test@example.com -c user.name=test -c init.defaultBranch=master "$@"; }

# make_pr "<added files, one per line>" "<deleted files, one per line>": a fresh repo whose HEAD is the PR's merge commit.
make_pr() {
  local IFS=$'\n'   # one file per line; a name may contain spaces or a tab
  rm -rf "$work/repo" && mkdir -p "$work/repo" && cd "$work/repo" || exit 1
  g init -q
  mkdir -p .github .claude/skills
  cp "$root/CLAUDE.md" . && cp "$root/.github/gate-rows.tsv" .github/
  for dir in "$root"/.claude/skills/*/; do mkdir -p ".claude/skills/$(basename "$dir")" && touch ".claude/skills/$(basename "$dir")/SKILL.md"; done
  for file in $2; do mkdir -p "$(dirname "$file")" && echo old >"$file"; done
  g add -A && g commit -qm base
  g checkout -qb pr
  for file in $1; do mkdir -p "$(dirname "$file")" && echo new >"$file"; done
  for file in $2; do g rm -q "$file"; done
  g add -A && g commit -qm change
  head_sha=$(git rev-parse HEAD)
  g checkout -q master && g merge -q --no-ff --no-edit pr
}

# expect <pass|fail> <name> <body> [text the output must contain]
expect() {
  local out code
  out=$(env -i PATH="$PATH" PR_MERGE="${MERGE:-HEAD}" PR_TITLE="process: test" PR_BODY="$3" PR_BRANCH=claude/test \
    PR_HEAD_SHA="$head_sha" PR_FILES=3 PR_ADDED=10 PR_DELETED=0 PR_AUTHOR_TYPE=User bash "$script" 2>&1)
  code=$?
  local wrong=false
  [[ "$1" == pass && $code -ne 0 ]] && wrong=true
  [[ "$1" == fail && $code -eq 0 ]] && wrong=true
  [[ -n "${4:-}" ]] && ! grep -qF -- "$4" <<<"$out" && wrong=true
  if [[ "$wrong" == true ]]; then
    echo "FAIL: $2 (expected $1${4:+ with '$4'})"; echo "$out" | sed 's/^/    /'; failed=1
  else
    echo "ok: $2"
  fi
}

body() { # body "<skills run>" "<not-applicable lines>"
  printf '## Pre-PR Skill Gate\n**Skills run:** %s\n%s\n## Independent review\n- REVIEWED %s — clean.%s' \
    "$1" "$2" "${head_sha:0:7}" "$SESSION"
}

# #204's real code files (a sample of the old tests), with the gate lists it had before and after the audit.
PR204_FILES="api/MyLoop.Api/Services/HexGridService.cs
api/MyLoop.Api/Services/PathValidationService.cs
api/MyLoop.Api/Constants/GameConstants.cs
tests/MyLoop.V01.Tests/FR1/ServicesUseRulesTests.cs
tests/MyLoop.Api.Tests/HexGridServiceTests.cs
mobile/lib/features/journey/hex_overlay.dart
mobile/test/mock_walk_engine_test.dart
docs/runbooks/incident-spoofing.md
.claude/skills/coding-standards/SKILL.md"
PR204_DELETED="api/MyLoop.Api/Constants/AntiCheatConstants.cs"
FIRST_204='`coding-standards`, `dotnet-patterns`, `csharp-testing`, `security-review`, `coordinate-overlapping-pr-removals`, `verification-loop`'
FINAL_204='`flutter-disk-concurrency-test`, `coding-standards`, `dotnet-patterns`, `csharp-testing`, `security-review`, `database-migrations`, `dart-flutter-patterns`, `flutter-dart-code-review`, `mock-gps-anticheat`, `coordinate-overlapping-pr-removals`, `verification-loop`'
NA_204='- Not applicable: `state-lifecycle-consistency` — server reads the rules once at startup
- Not applicable: `webapi-standards`, `api-design`, `latency-critical-systems`, `database-retry-resilience` — no startup, endpoint, cache or transaction change
- Not applicable: `mobile-background-location`, `app-store-compliance`, `error-handling` — no location service, iOS or error-handling change'

make_pr "$PR204_FILES" "$PR204_DELETED"
expect fail "#204 with its first gate list" "$(body "$FIRST_204" "$NA_204")" \
  '`flutter-disk-concurrency-test` is required by mobile/test/mock_walk_engine_test.dart'
expect fail "#204 first list also misses the Dart rows" "$(body "$FIRST_204" "$NA_204")" '`dart-flutter-patterns` is required'
expect fail "#204 first list also misses mock GPS" "$(body "$FIRST_204" "$NA_204")" '`mock-gps-anticheat` is required'
expect pass "#204 with its final gate list" "$(body "$FINAL_204" "$NA_204")"
expect fail "a required skill marked not applicable" \
  "$(body "${FINAL_204/\`mock-gps-anticheat\`, /}" "$NA_204"$'\n- Not applicable: `mock-gps-anticheat` — only comments')" \
  '`mock-gps-anticheat` is required'
expect fail "a gate row nobody named" "$(body "$FINAL_204" "${NA_204/\`error-handling\` /}")" \
  'Gate rows not gone through: `error-handling`'
expect fail "not applicable without a reason" \
  "$(body "$FINAL_204" "${NA_204/ — server reads the rules once at startup/}")" 'has no reason'
expect fail "verification-loop missing" "$(body "${FINAL_204/, \`verification-loop\`/}" "$NA_204")" \
  '`verification-loop` (scripts/verify.sh) must be in Skills run'

make_pr "api/MyLoop.Api/Services/Foo.cs" "api/MyLoop.Api/Services/Old.cs"
expect fail "a deleted code file needs the removals gate" \
  "$(body '`coding-standards`, `dotnet-patterns`, `csharp-testing`, `verification-loop`' "$NA_204")" \
  '`coordinate-overlapping-pr-removals` is required by api/MyLoop.Api/Services/Old.cs'

make_pr "mobile/lib/shared/services/api_service.dart" ""
expect fail "#205's api_service change needs api-design" \
  "$(body '`coding-standards`, `dart-flutter-patterns`, `flutter-dart-code-review`, `verification-loop`' "$NA_204")" \
  '`api-design` is required by mobile/lib/shared/services/api_service.dart'

make_pr "api/MyLoop.Api/Models/ClaimRequest.cs" ""
expect fail "a server request/response class needs api-design" \
  "$(body '`coding-standards`, `dotnet-patterns`, `csharp-testing`, `verification-loop`' "$NA_204")" \
  '`api-design` is required by api/MyLoop.Api/Models/ClaimRequest.cs'

make_pr "api/MyLoop.Api/Services/Café.cs" ""
expect fail "a non-ASCII file name still matches its rows" \
  "$(body '`verification-loop`' "$NA_204")" '`coding-standards` is required by api/MyLoop.Api/Services/Café.cs'

make_pr $'mobile/lib/a\tb.dart' ""
expect fail "a file name with a tab fails" "$(body "$FINAL_204" "$NA_204")" "File name with a tab"

make_pr "api/MyLoop.Api/Migrations/20260101_Add.cs" ""
MIGRATION_RUN='`coding-standards`, `dotnet-patterns`, `csharp-testing`, `database-migrations`, `verification-loop`, `flutter-disk-concurrency-test`, `dart-flutter-patterns`, `flutter-dart-code-review`, `mock-gps-anticheat`, `coordinate-overlapping-pr-removals`'
NA_MIGRATION=$'- Not applicable: `database-retry-resilience` — no transaction, and no change to `DbContext`\n'"${NA_204/\`database-retry-resilience\`/\`dotnet-patterns\`}"
expect pass "a migration doesn't force the retry skill; a reason may name code in backticks" \
  "$(body "$MIGRATION_RUN, \`security-review\`" "$NA_MIGRATION")"
expect fail "a skill named only inside a reason doesn't count" \
  "$(body "$MIGRATION_RUN" "$NA_MIGRATION"$'\n- Not applicable: `state-lifecycle-consistency` — reviewed like `security-review`')" \
  'Gate rows not gone through: `security-review`'

make_pr $'docs/versions/1/0.1/design/fr9-x.md\n.claude/skills/mock-gps-anticheat/SKILL.md\nREADME.md' "docs/old.md"
expect pass "docs-only PR: no gate rows required" "$(body 'none' '')"
MERGE=no-such-ref expect fail "changed files can't be read: fails, never skips" "$(body 'none' '')" \
  "Couldn't read the PR's changed files"

exit "$failed"
