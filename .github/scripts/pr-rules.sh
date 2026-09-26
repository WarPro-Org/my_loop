#!/usr/bin/env bash
# Checks a pull request against the CLAUDE.md rules a machine can check. Prints every broken
# rule and exits 1 if any. Inputs (env): PR_TITLE, PR_BODY, PR_BRANCH, PR_FILES, PR_ADDED, PR_DELETED.
set -uo pipefail

readonly MAX_FILES=15
readonly MAX_LINES=400
readonly FR_TITLE='^[0-9]+\.[0-9]+ > FR[0-9]+'
readonly FR_BRANCH='^v[0-9]+\.[0-9]+/fr[0-9]+'
readonly DESIGN_DOC='docs/versions/[^ )`]+/design/fr[0-9]+[^ )`]*\.md'

title="${PR_TITLE:-}"
lines=$(( ${PR_ADDED:-0} + ${PR_DELETED:-0} ))
# Template hints (HTML comments) left in place do not count as filled in.
body=$(sed -E 's/<!--.*-->//g' <<<"${PR_BODY:-}")
problems=()

grep -qE '#[0-9]+' <<<"$body" \
  || problems+=("Link the task this PR belongs to (e.g. #201).")

grep -q '^## Pre-PR Skill Gate' <<<"$body" \
  || problems+=("Add the '## Pre-PR Skill Gate' section listing every gate row that applies.")

skills_line=$(grep -m1 '^\*\*Skills run:\*\*' <<<"$body" || true)
[[ -n "${skills_line#\*\*Skills run:\*\*}" && "${skills_line#\*\*Skills run:\*\*}" =~ [a-z] ]] \
  || problems+=("Fill in '**Skills run:**' with the skills that actually ran (or 'none').")

if [[ "$title" =~ $FR_TITLE ]]; then
  [[ "${PR_BRANCH:-}" =~ $FR_BRANCH ]] \
    || problems+=("FR work goes on a branch named like v0.1/fr1-<part>.")
  doc=$(grep -oE "$DESIGN_DOC" <<<"$body" | head -1)
  if [[ -z "$doc" ]]; then
    problems+=("Link the FR's approved design doc (docs/versions/<release>/<version>/design/frN-*.md).")
  elif [[ ! -f "$doc" ]]; then
    problems+=("The linked design doc $doc does not exist in this branch.")
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
