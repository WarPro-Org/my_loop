#!/usr/bin/env bash
# Prints "code=true" when the change touches anything besides docs (docs/, *.md) or agent
# skills/config (.claude/), else "code=false". Anything it can't work out counts as code.
# --no-renames: a file moved from code into docs/ must still count as a code change.
# Inputs (env): EVENT, PR_BASE (pull_request base sha), PUSH_BEFORE (push "before" sha), GITHUB_SHA.
set -uo pipefail

readonly NO_COMMIT=0000000000000000000000000000000000000000
readonly DOCS_ONLY='^(docs/|\.claude/)|\.md$'

case "${EVENT:-}" in
  pull_request) base="${PR_BASE:-}" ;;
  push) base="${PUSH_BEFORE:-}" ;;
  *) base="" ;;
esac

if [[ -z "$base" || "$base" == "$NO_COMMIT" ]]; then
  echo "code=true"
  exit 0
fi

if ! changed=$(git diff --no-renames --name-only "$base" "${GITHUB_SHA:-HEAD}"); then
  echo "code=true"
  exit 0
fi

if [[ -z "$changed" ]] || grep -qvE "$DOCS_ONLY" <<<"$changed"; then
  echo "code=true"
else
  echo "code=false"
fi
