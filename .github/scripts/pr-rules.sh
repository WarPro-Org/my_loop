#!/usr/bin/env bash
# Checks a pull request against the CLAUDE.md rules a machine can check. Prints every broken rule
# and exits 1 if any. Run from a checkout of the PR merge commit (HEAD^1 = base, HEAD^2 = PR head).
# Inputs (env): PR_TITLE, PR_BODY, PR_BRANCH, PR_FILES, PR_ADDED, PR_DELETED, PR_AUTHOR_TYPE.
set -uo pipefail

readonly MAX_FILES=15
readonly MAX_LINES=400
readonly FR_BRANCH='^v[0-9]+\.[0-9]+/fr([0-9]+)'
readonly CLAUDE_MARK='claude.ai/code'

if [[ "${PR_AUTHOR_TYPE:-}" == "Bot" ]]; then
  echo "Bot PR: CLAUDE.md PR rules don't apply."
  exit 0
fi

# Template hints (HTML comments, even multi-line) left in place don't count as filled in.
body=$(perl -0pe 's/<!--.*?-->//gs' <<<"${PR_BODY:-}")
lines=$(( ${PR_ADDED:-0} + ${PR_DELETED:-0} ))
changed=$(git diff --name-only HEAD^1 HEAD 2>/dev/null)
problems=()

fr=""
[[ "${PR_BRANCH:-}" =~ $FR_BRANCH ]] && fr="${BASH_REMATCH[1]}"
by_claude=false
grep -q "$CLAUDE_MARK" <<<"$body" && by_claude=true

if [[ -n "$fr" || "$by_claude" == true ]]; then
  grep -q '^## Pre-PR Skill Gate' <<<"$body" \
    || problems+=("Add the '## Pre-PR Skill Gate' section listing every gate row that applies.")
  skills=$(grep -m1 '^\*\*Skills run:\*\*' <<<"$body" | sed 's/^\*\*Skills run:\*\*//')
  [[ "$skills" =~ [a-z] ]] \
    || problems+=("Fill in '**Skills run:**' with the skills that actually ran on the head commit (or 'none').")
fi

if [[ -n "$fr" ]]; then
  grep -qE '^(Task: |Closes |Part of |Part [0-9]+ of [0-9]+ for )[^#]*#[0-9]+' <<<"$body" \
    || problems+=("FR PRs start with a task link line, e.g. 'Task: #201'.")
  doc_pattern="docs/versions/[^ )\`]+/design/fr${fr}-[^ )\`]*\\.md"
  doc=$(grep -oE "$doc_pattern" <<<"$body" | head -1)
  code_changed=$(grep -vE '^docs/' <<<"$changed" || true)
  if [[ -z "$doc" ]]; then
    problems+=("Link FR${fr}'s design doc (docs/versions/<release>/<version>/design/fr${fr}-<name>.md).")
  elif git cat-file -e "HEAD^1:$doc" 2>/dev/null; then
    :  # approved doc already on the base branch
  elif grep -qx "$doc" <<<"$changed" && [[ -z "$code_changed" ]]; then
    :  # this PR is the design doc itself (docs only)
  else
    problems+=("$doc must be merged (approved) before FR${fr} code: it isn't on the base branch.")
  fi
fi

if (( ${PR_FILES:-0} > MAX_FILES || lines > MAX_LINES )) && ! grep -q '^Size exception:' <<<"$body"; then
  problems+=("PR is ${PR_FILES:-0} files / ${lines} lines (limit ~${MAX_FILES} / ~${MAX_LINES}). Split it, or add a 'Size exception: <reason, agreed with the owner>' line.")
fi

if ((${#problems[@]})); then
  printf 'PR rules not met (CLAUDE.md):\n'
  printf -- '- %s\n' "${problems[@]}"
  exit 1
fi
echo "PR rules met."
