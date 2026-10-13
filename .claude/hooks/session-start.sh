#!/bin/bash
# Prints where MyLoop stands into every new session, so a fresh chat starts oriented without re-reading history.
# Read-only: never changes the repo. Must never fail a session start.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

echo "=== MyLoop session start ==="
if [[ -f docs/status.md ]]; then
  cat docs/status.md
else
  echo "docs/status.md is missing: ask the owner where things stand."
fi
echo
echo "=== Recent commits on master ==="
git fetch -q origin master 2>/dev/null || true
git log --oneline -8 origin/master 2>/dev/null || git log --oneline -8 2>/dev/null || true
echo
echo "Current branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
exit 0
