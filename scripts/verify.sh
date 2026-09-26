#!/usr/bin/env bash
# MyLoop's verification-loop for the 0.x rebuild, on the current commit: build, the 0.1 user-story
# tests, flutter analyze (no new issues) and a secrets scan of the changed files. Exits 0 only if
# every step passed; any step that couldn't run counts as failed.
set -uo pipefail

readonly ANALYZE_BASELINE=20   # issues on master before the rebuild; must not grow
readonly SECRET_PATTERN='(AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY)'

root=$(git rev-parse --show-toplevel) || exit 1
cd "$root" || exit 1
export PATH="/opt/flutter-sdk/flutter/bin:$PATH"
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT
failures=()

step() { echo "== $1"; }

# The result is recorded against the commit, so the files on disk must be exactly that commit.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Uncommitted or untracked changes: commit or stash them first, so the commit is what gets verified."
  exit 1
fi

step "Build API"
dotnet build api/MyLoop.Api/MyLoop.Api.csproj -c Release -v q -nologo >"$logs/build" 2>&1 \
  || { tail -20 "$logs/build"; failures+=("build"); }

step "Build old tests (compiled, not run)"
dotnet build tests/MyLoop.Api.Tests/MyLoop.Api.Tests.csproj -c Release -v q -nologo >"$logs/oldtests" 2>&1 \
  || { tail -20 "$logs/oldtests"; failures+=("old-tests-build"); }

step "0.1 user-story tests (.NET)"
if dotnet test tests/MyLoop.V01.Tests/MyLoop.V01.Tests.csproj -c Release -nologo >"$logs/dotnet" 2>&1; then
  grep -E "Passed!" "$logs/dotnet"
else
  tail -30 "$logs/dotnet"; failures+=("dotnet-tests")
fi

step "0.1 user-story tests (Flutter)"
if [[ -d mobile/test/v0_1 ]]; then
  if (cd mobile && flutter test test/v0_1 >"$logs/flutter" 2>&1); then
    tail -1 "$logs/flutter"
  else
    tail -30 "$logs/flutter"; failures+=("flutter-tests")
  fi
else
  echo "no 0.1 Flutter tests on this commit yet"
fi

step "flutter analyze (no new issues)"
(cd mobile && flutter analyze >"$logs/analyze" 2>&1)
if grep -q "No issues found" "$logs/analyze"; then
  issues=0
else
  issues=$(grep -oE '^[0-9]+ issues? found' "$logs/analyze" | grep -oE '^[0-9]+')
fi
if [[ -z "${issues:-}" ]]; then
  tail -20 "$logs/analyze"; failures+=("analyze-did-not-run")
else
  echo "$issues issues (baseline $ANALYZE_BASELINE)"
  (( issues <= ANALYZE_BASELINE )) || failures+=("analyze")
fi

step "Secrets scan (files changed vs origin/master)"
if ! git diff -z --name-only --diff-filter=d origin/master...HEAD >"$logs/changed"; then
  failures+=("secrets-scan-did-not-run")
else
  while IFS= read -r -d '' file; do
    [[ -f "$file" ]] || continue   # e.g. a submodule path
    grep -nE "$SECRET_PATTERN" -- "$file"
    case $? in
      0) failures+=("secrets in $file") ;;
      1) ;;
      *) failures+=("secrets-scan-error on $file") ;;
    esac
  done <"$logs/changed"
fi

commit=$(git rev-parse --short HEAD)
if ((${#failures[@]})); then
  echo "VERIFICATION FAILED on $commit: ${failures[*]}"
  exit 1
fi
echo "VERIFICATION PASSED on $commit"
