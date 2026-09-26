#!/usr/bin/env bash
# MyLoop's verification-loop for the 0.x rebuild: build, the 0.1 user-story tests, flutter analyze
# (no new issues), and a secrets scan, on the current commit. Exit 0 only if all pass. On success
# it records "<commit> verified" in the gate log that .claude/hooks/gate-check.sh reads.
set -uo pipefail

readonly ANALYZE_BASELINE=20   # issues on master before the rebuild; must not grow
root=$(git rev-parse --show-toplevel)
cd "$root" || exit 1
export PATH="/opt/flutter-sdk/flutter/bin:$PATH"
failures=()

step() { echo "== $1"; }

step "Build API"
dotnet build api/MyLoop.Api/MyLoop.Api.csproj -c Release -v q -nologo >/tmp/verify-build.log 2>&1 \
  || { tail -20 /tmp/verify-build.log; failures+=("build"); }

step "Build old tests (compiled, not run)"
dotnet build tests/MyLoop.Api.Tests/MyLoop.Api.Tests.csproj -c Release -v q -nologo >/tmp/verify-oldtests.log 2>&1 \
  || { tail -20 /tmp/verify-oldtests.log; failures+=("old-tests-build"); }

step "0.1 user-story tests (.NET)"
dotnet test tests/MyLoop.V01.Tests/MyLoop.V01.Tests.csproj -c Release -nologo 2>&1 | tail -3 \
  | tee /tmp/verify-dotnet.log
grep -q "Passed!" /tmp/verify-dotnet.log || failures+=("dotnet-tests")

step "0.1 user-story tests (Flutter)"
if [[ -d mobile/test/v0_1 ]]; then
  (cd mobile && flutter test test/v0_1 2>&1 | tail -2) | tee /tmp/verify-flutter.log
  grep -q "All tests passed" /tmp/verify-flutter.log || failures+=("flutter-tests")
else
  echo "no 0.1 Flutter tests on this commit yet"
fi

step "flutter analyze (no new issues)"
analyze_output=$(cd mobile && flutter analyze 2>&1)
issues=$(grep -oE '^[0-9]+ issues? found' <<<"$analyze_output" | grep -oE '^[0-9]+')
issues=${issues:-0}
echo "$issues issues (baseline $ANALYZE_BASELINE)"
(( issues <= ANALYZE_BASELINE )) || failures+=("analyze")

step "Secrets scan (changed files vs master)"
changed=$(git diff --name-only origin/master...HEAD 2>/dev/null)
if [[ -n "$changed" ]] && grep -nE '(AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY)' \
    $(ls -d $changed 2>/dev/null) 2>/dev/null; then
  failures+=("secrets")
fi

commit=$(git rev-parse HEAD)
if ((${#failures[@]})); then
  echo "VERIFICATION FAILED on ${commit:0:7}: ${failures[*]}"
  exit 1
fi
echo "$commit verified" >>"$(git rev-parse --git-common-dir)/claude-gates.log"
echo "VERIFICATION PASSED on ${commit:0:7}"
