#!/usr/bin/env bash
# Checks a pull request against the CLAUDE.md rules a machine can check. Prints every broken rule
# and exits 1 if any. Runs from master's copy of this script (pull_request_target), so a PR can't
# loosen its own check; the PR is only read as git data. Inputs (env): PR_TITLE, PR_BODY, PR_BRANCH,
# PR_HEAD_SHA, PR_MERGE (a ref to the PR's merge commit, default HEAD), PR_FILES, PR_ADDED,
# PR_DELETED, PR_AUTHOR_TYPE.
set -uo pipefail

readonly MAX_FILES=15
readonly MAX_LINES=400
readonly FR_BRANCH='^v[0-9]+\.[0-9]+/fr([0-9]+)'
readonly CLAUDE_MARK='claude.ai/code'
readonly MASTER=origin/master
# Gate rows: read from master's checkout (the working directory), never from the PR.
readonly GATE_TABLES=CLAUDE.md
readonly GATE_ROWS=.github/gate-rows.tsv
readonly SKILLS_DIR=.claude/skills
readonly FINAL_GATE=verification-loop
readonly REMOVAL_GATE=coordinate-overlapping-pr-removals
readonly NOT_CODE='^(docs/|\.claude/)|\.md$'   # same rule as code-changed.sh

if [[ "${PR_AUTHOR_TYPE:-}" == "Bot" ]]; then
  echo "Bot PR: CLAUDE.md PR rules don't apply."
  exit 0
fi

# Template hints (HTML comments, even multi-line) left in place don't count as filled in.
body=$(perl -0pe 's/<!--.*?-->//gs' <<<"${PR_BODY:-}")
lines=$(( ${PR_ADDED:-0} + ${PR_DELETED:-0} ))
merge="${PR_MERGE:-HEAD}"
changed=$(git diff --name-only "$merge^1" "$merge" 2>/dev/null)
problems=()
# Changed code files as "<status><TAB><path>" lines. Read NUL-separated (-z): git then prints names
# as they are, never quoted, so an unusual file name can't slip past the patterns. If the diff can't be read, the check fails (never skips).
code_status=""
status_file=$(mktemp)
if git diff --no-renames --name-status -z "$merge^1" "$merge" >"$status_file" 2>/dev/null; then
  while IFS= read -r -d '' status && IFS= read -r -d '' path; do
    if [[ "$path" == *$'\t'* || "$path" == *$'\n'* ]]; then
      problems+=("File name with a tab or line break isn't allowed: rename it.")
    elif ! [[ "$path" =~ $NOT_CODE ]]; then
      code_status+="$status"$'\t'"$path"$'\n'
    fi
  done <"$status_file"
else
  problems+=("Couldn't read the PR's changed files (merge commit $merge).")
fi
rm -f "$status_file"

# Skills named in CLAUDE.md's two gate tables (backticked names that are real skill folders).
gate_skills() {
  awk '/^## /{on = ($0 ~ /^## (Pre-Check-in|Pre-PR) Skill Gate/)} on && /^\|/' "$GATE_TABLES" 2>/dev/null \
    | grep -oE '`[a-z0-9-]+`' | tr -d '`' | sort -u \
    | while read -r skill; do [[ -d "$SKILLS_DIR/$skill" ]] && echo "$skill"; done
}

# "<skill><TAB><file>" for every gate skill a changed code file makes required.
required_skills() {
  local status file pattern skills skill
  while IFS=$'\t' read -r status file; do
    [[ -z "$file" ]] && continue
    [[ "$status" == D ]] && printf '%s\t%s\n' "$REMOVAL_GATE" "$file"
    while IFS=$'\t' read -r pattern skills; do
      [[ -z "$pattern" || "$pattern" == \#* ]] && continue
      [[ "$file" =~ $pattern ]] || continue
      for skill in $skills; do printf '%s\t%s\n' "$skill" "$file"; done
    done <"$GATE_ROWS"
  done <<<"$code_status"
}

# Every gate row must be gone through: a skill a changed file requires must have run, and every other
# gate skill must be named, as run or as "- Not applicable: `skill` — <reason>".
check_gate_rows() {
  local all run na line skill file missing=()
  all=$(gate_skills)
  if [[ -z "$all" || ! -r "$GATE_ROWS" ]]; then
    problems+=("Couldn't read the gate rows ($GATE_TABLES tables, $GATE_ROWS) on master.")
    return
  fi
  run=$(grep -m1 '^\*\*Skills run:\*\*' <<<"$body" | grep -oE '`[a-z0-9-]+`' | tr -d '`')
  na=""
  # "- Not applicable: `a`, `b` — reason": skills before the first dash, the reason after it.
  local rest names hyphen_cut reason
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    rest=${line#*Not applicable:}
    names=${rest%%" — "*}   # cut at whichever dash comes first
    hyphen_cut=${rest%%" - "*}
    (( ${#hyphen_cut} < ${#names} )) && names=$hyphen_cut
    reason=${rest#"$names"}
    if grep -qE '[A-Za-z]{3,}' <<<"$reason"; then
      na+=$'\n'$(grep -oE '`[a-z0-9-]+`' <<<"$names" | tr -d '`')
    else
      problems+=("'${line}' has no reason: write '- Not applicable: \`skill\` — <why it doesn't apply>'.")
    fi
  done < <(grep -E '^(- )?Not applicable:' <<<"$body")

  grep -qx "$FINAL_GATE" <<<"$run" \
    || problems+=("\`$FINAL_GATE\` (scripts/verify.sh) must be in Skills run for a PR that changes code.")
  while IFS=$'\t' read -r skill file; do
    [[ -z "$skill" ]] && continue
    grep -qx "$skill" <<<"$run" \
      || problems+=("\`$skill\` is required by $file (CLAUDE.md gate row, $GATE_ROWS) but isn't in Skills run.")
  done < <(required_skills | sort -u -t$'\t' -k1,1)
  for skill in $all; do
    grep -qx "$skill" <<<"$run"$'\n'"$na" || missing+=("\`$skill\`")
  done
  ((${#missing[@]})) && problems+=("Gate rows not gone through: ${missing[*]}. Add each to Skills run, or a line '- Not applicable: \`skill\` — <reason>'.")
}

fr=""
[[ "${PR_BRANCH:-}" =~ $FR_BRANCH ]] && fr="${BASH_REMATCH[1]}"
by_claude=false
{ grep -q "$CLAUDE_MARK" <<<"$body" || [[ "${PR_BRANCH:-}" == claude/* ]]; } && by_claude=true

if [[ -n "$fr" || "$by_claude" == true ]]; then
  grep -q '^## Pre-PR Skill Gate' <<<"$body" \
    || problems+=("Add the '## Pre-PR Skill Gate' section listing every gate row that applies.")
  skills=$(grep -m1 '^\*\*Skills run:\*\*' <<<"$body" | sed 's/^\*\*Skills run:\*\*//')
  [[ "$skills" =~ [a-z] ]] \
    || problems+=("Fill in '**Skills run:**' with the skills that actually ran on the head commit (or 'none').")
  head="${PR_HEAD_SHA:-}"
  reviewed=$(grep -oE '^(- )?REVIEWED [0-9a-f]{7,40}' <<<"$body" | awk '{print $NF}')
  covered=false
  for sha in $reviewed; do [[ -n "$head" && "$head" == "$sha"* ]] && covered=true; done
  [[ "$covered" == true ]] \
    || problems+=("Add 'REVIEWED ${head:0:7} — <result>' under '## Independent review': the latest commit has no recorded independent review.")
  [[ -n "$code_status" ]] && check_gate_rows
fi

if [[ -n "$fr" ]]; then
  grep -qE '^(Task: |Closes |Part of |Part [0-9]+ of [0-9]+ for )[^#]*#[0-9]+' <<<"$body" \
    || problems+=("FR PRs start with a task link line, e.g. 'Task: #201'.")
  title_part=""; body_part=""
  [[ "${PR_TITLE:-}" =~ ^[0-9]+\.[0-9]+\ \>\ FR${fr}\ \(([0-9]+)/([0-9]+)\)\ \> ]] \
    && title_part="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  [[ "$body" =~ Part\ ([0-9]+)\ of\ ([0-9]+)([^0-9]|$) ]] && body_part="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  if [[ -z "$title_part" ]]; then
    problems+=("FR PR titles look like '0.1 > FR${fr} (k/N) > <title>'.")
  elif [[ "$title_part" != "$body_part" ]]; then
    problems+=("Title says ${title_part} but the description says '${body_part:-nothing}': write 'Part ${title_part%/*} of ${title_part#*/}' and keep them in sync.")
  fi
  doc_pattern="docs/versions/[^ )\`]+/design/fr${fr}-[^ )\`]*\\.md"
  doc=$(grep -oE "$doc_pattern" <<<"$body" | head -1)
  code_changed=$(grep -vE '^docs/' <<<"$changed" || true)
  if [[ -z "$doc" ]]; then
    problems+=("Link FR${fr}'s design doc (docs/versions/<release>/<version>/design/fr${fr}-<name>.md).")
  elif git cat-file -e "$MASTER:$doc" 2>/dev/null; then
    :  # approved (merged) doc on master
  elif grep -qx "$doc" <<<"$changed" && [[ -z "$code_changed" ]]; then
    :  # this PR is the design doc itself (docs only)
  else
    problems+=("$doc must be merged into master (approved) before FR${fr} code.")
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
