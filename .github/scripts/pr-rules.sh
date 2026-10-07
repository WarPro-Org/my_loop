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
readonly SCENARIOS=docs/scenarios.md
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

# The part of a line before its first " - " or " — ": the skill list. What follows is a reason or a
# note, and a skill named there doesn't count.
before_dash() {
  local line=$1 em hyphen
  em=${line%%" — "*}
  hyphen=${line%%" - "*}
  if (( ${#hyphen} < ${#em} )); then printf '%s\n' "$hyphen"; else printf '%s\n' "$em"; fi
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
  line=$(grep -m1 '^\*\*Skills run:\*\*' <<<"$body")
  run=$(before_dash "${line#\*\*Skills run:\*\*}" | grep -oE '`[a-z0-9-]+`' | tr -d '`')
  na=""
  # "- Not applicable: `a`, `b` — reason": skills before the first dash, the reason after it.
  local rest names reason
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    rest=${line#*Not applicable:}
    names=$(before_dash "$rest")
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

# Scenario catalogue (CLAUDE.md "Scenario catalogue"): every FR design doc answers every ID, IDs are
# never removed, and a code PR names the IDs it touches. The catalogue and design docs are read from
# the PR's merge commit, so a PR that adds an ID must answer it everywhere in the same PR.
catalogue_ids() { git show "$1:$SCENARIOS" 2>/dev/null | grep -oE '^\| [A-Z]+-[0-9]+ \|' | grep -oE '[A-Z]+-[0-9]+'; }

# The test names a file declares, one per line: Dart test('…') / testWidgets("…") (the name may start on
# the next line, may be split into adjacent literals, and \' is read as '), or C# [Fact]/[Theory] methods
# (comments may sit between their attributes).
test_names() {
  case "$1" in
    *.dart) perl -0ne '
      my $lit = qr/\x27(?:[^\x27\\]|\\.)*\x27|"(?:[^"\\]|\\.)*"/;
      while (/\b(?:test|testWidgets)\(\s*((?:$lit)(?:\s*(?:$lit))*)/g) {
        my $all = $1; my $n = "";
        while ($all =~ /\x27((?:[^\x27\\]|\\.)*)\x27|"((?:[^"\\]|\\.)*)"/g) { $n .= defined $1 ? $1 : $2 }
        $n =~ s/\\(.)/$1/g; print "$n\n";
      }' ;;
    *.cs) perl -0ne 'print "$1\n" while /\[(?:Fact|Theory)\b(?:[^\[\]]|\[[^\]]*\])*\](?:\s*(?:\[(?:[^\[\]]|\[[^\]]*\])*\]|\/\/[^\n]*))*\s*public\s+(?:async\s+)?(?:void|Task)\s+(\w+)\s*\(/g' ;;
  esac
}

check_design_doc_scenarios() {
  local doc=$1 ids=$2 table id status evidence path paths names name tests seen="" missing=()
  # Only the '## Scenarios' section counts; rows inside a code fence or an HTML comment don't.
  table=$(git show "$merge:$doc" 2>/dev/null | perl -0pe 's/<!--.*?-->//gs' \
    | awk '/^```/{fence = !fence; next} fence{next} /^## /{on = ($0 ~ /^## Scenarios[[:space:]]*$/); next} on')
  if [[ -z "$table" ]]; then
    problems+=("$doc has no '## Scenarios' table: answer every ID in $SCENARIOS.")
    return
  fi
  while IFS='|' read -r _ id status evidence _; do
    id=$(xargs <<<"$id"); status=$(xargs <<<"$status")
    [[ "$id" =~ ^[A-Z]+-[0-9]+$ ]] || continue
    grep -qx "$id" <<<"$seen" && { problems+=("$doc answers $id more than once."); continue; }
    seen+="$id"$'\n'
    grep -qx "$id" <<<"$ids" || { problems+=("$doc answers $id, which isn't in $SCENARIOS."); continue; }
    case "$status" in
      covered)
        # Each named test file must exist as a file, and each quoted test name must be in one of them.
        paths=$(grep -oE '`[^`]+`' <<<"$evidence" | tr -d '`' | grep -E '(^|/)(test|tests)/' || true)
        names=$(grep -oE '"[^"]+"' <<<"$evidence" | tr -d '"' || true)
        [[ -n "$paths" ]] || problems+=("$doc: $id is 'covered' but names no test file in backticks.")
        [[ -n "$names" ]] || problems+=("$doc: $id is 'covered' but names no test in double quotes.")
        # Each named file must exist; each quoted name must be exactly the name of a test in one of them.
        tests=""
        for path in $paths; do
          if [[ "$(git cat-file -t "$merge:$path" 2>/dev/null)" == blob ]]; then
            tests+=$(git show "$merge:$path" | test_names "$path")$'\n'
          else
            problems+=("$doc: $id names $path, which isn't a file.")
          fi
        done
        [[ -n "$paths" && -z "${tests//$'\n'/}" ]] && problems+=("$doc: $id names no file that declares a test.")
        while IFS= read -r name; do
          [[ -z "$name" || -z "${tests//$'\n'/}" ]] && continue
          grep -qxF -- "$name" <<<"$tests" || problems+=("$doc: $id names the test \"$name\", which isn't the full name of a test in its test file(s).")
        done <<<"$names" ;;
      n/a|accepted)
        grep -qE '[A-Za-z]{3,}' <<<"$evidence" || problems+=("$doc: $id is '$status' with no reason.")
        # An existing-code ID is not answered by the size of the diff: n/a must say what was searched.
        if [[ "$status" == n/a ]] && grep -qx "$id" <<<"$search_ids" && ! grep -qE '^[[:space:]]*searched:' <<<"$evidence"; then
          problems+=("$doc: $id is marked [search] in $SCENARIOS, so its 'n/a' must start with 'searched:' and say what was searched and found.")
        fi ;;
      open)
        grep -qE '#[0-9]+|FR[0-9]+' <<<"$evidence" || problems+=("$doc: $id is 'open' with no owner (FRn or #task).") ;;
      *) problems+=("$doc: $id has status '$status'; use covered, n/a, open or accepted.") ;;
    esac
  done <<<"$table"
  for id in $ids; do grep -qx "$id" <<<"$seen" || missing+=("$id"); done
  ((${#missing[@]})) && problems+=("$doc doesn't answer ${#missing[@]} scenario ID(s): ${missing[*]}. Add a row for each to its '## Scenarios' table.")
}

# IDs whose catalogue row carries the [search] marker: they are about code that already exists.
search_ids=""
check_scenarios() {
  local ids master_ids removed doc line named id
  ids=$(catalogue_ids "$merge")
  search_ids=$(git show "$merge:$SCENARIOS" 2>/dev/null | grep -E '^\| [A-Z]+-[0-9]+ \|.*\[search\]' | grep -oE '^\| [A-Z]+-[0-9]+' | grep -oE '[A-Z]+-[0-9]+' || true)
  master_ids=$(catalogue_ids "$MASTER")
  if [[ -z "$ids" ]]; then
    [[ -n "$master_ids" ]] && problems+=("$SCENARIOS is missing or empty: scenario IDs are never removed.")
    return
  fi
  removed=$(comm -23 <(sort -u <<<"$master_ids") <(sort -u <<<"$ids") | grep . | tr '\n' ' ')
  [[ -n "$removed" ]] && problems+=("Scenario IDs removed from $SCENARIOS: ${removed}. IDs are never deleted; mark one '(retired: <reason>)'.")
  while IFS= read -r doc; do
    [[ -n "$doc" ]] && check_design_doc_scenarios "$doc" "$ids"
  done < <(git ls-tree -r --name-only "$merge" -- docs/versions 2>/dev/null | grep -E '/design/fr[0-9]+-[^/]*\.md$')
  [[ "$by_claude" == true || -n "$fr" ]] && [[ -n "$code_status" ]] || return 0
  line=$(grep -m1 '^\*\*Scenarios:\*\*' <<<"$body")
  if [[ -z "$line" ]]; then
    problems+=("A code PR needs a '**Scenarios:**' line: the $SCENARIOS IDs it covers or changes, or 'none — <reason>'.")
    return
  fi
  named=$(before_dash "${line#\*\*Scenarios:\*\*}" | grep -oE '[A-Z]+-[0-9]+' || true)
  if [[ -z "$named" ]]; then
    grep -qiE 'none[^A-Za-z]+.*[A-Za-z]{3,}' <<<"${line#\*\*Scenarios:\*\*}" \
      || problems+=("'**Scenarios:**' names no ID: list them, or write 'none — <reason>'.")
  fi
  for id in $named; do
    grep -qx "$id" <<<"$ids" || problems+=("'**Scenarios:**' names $id, which isn't in $SCENARIOS: add it there first.")
  done
}

# Data-removal register (DATA-1): every file that deletes, overwrites, hands over or expires user data is a row in
# docs/data-removals.md with a verdict and, for 'breaks', an owner; every row names a file that exists.
REGISTER=docs/data-removals.md
SERVER_REMOVAL='ExecuteDelete|DELETE FROM|\.Remove\(|\.RemoveRange\(|TRUNCATE|DROP TABLE|DROP COLUMN|\.OwnerId = '
PHONE_REMOVAL='\.delete\(|deleteSync\(|removeWhere\(|\.removeAt\(|\.removeRange\(|\.clear\(\)'
trim() { local v=$1; v="${v#"${v%%[![:space:]]*}"}"; printf '%s' "${v%"${v##*[![:space:]]}"}"; }
check_data_removals() {
  local found register listed file path verdict owner
  found=$( { git grep -lE "$SERVER_REMOVAL" "$merge" -- 'api/*.cs' ':(exclude)api/*/Migrations/*' 2>/dev/null || true
             git grep -lE "$PHONE_REMOVAL" "$merge" -- 'mobile/lib/shared/services/*.dart' 'mobile/lib/shared/state/*.dart' 2>/dev/null || true; } \
           | sed 's/^[^:]*://' | sort -u)
  register=$(git show "$merge:$REGISTER" 2>/dev/null || true)
  if [[ -z "$register" ]]; then
    [[ -n "$found" ]] && problems+=("$REGISTER is missing: list every file that deletes, overwrites, hands over or expires user data.")
    return
  fi
  listed=""
  while IFS='|' read -r _ file _ verdict owner _; do
    file=$(trim "${file//\`/}"); verdict=$(trim "$verdict"); owner=$(trim "$owner")
    [[ "$file" =~ ^(api|mobile|tests)/[^[:space:]]+$ ]] || continue
    listed+="$file"$'\n'
    [[ "$(git cat-file -t "$merge:$file" 2>/dev/null)" == blob ]] || problems+=("$REGISTER lists $file, which isn't a file: remove the row.")
    if [[ "$verdict" =~ ^keeps\ (#[0-9]+|none\ —\ .{3,})$ ]]; then :
    elif [[ "$verdict" =~ ^breaks\ #[0-9]+$ ]]; then
      grep -qE '^(FR[0-9]+|#[0-9]+)$' <<<"$owner" || problems+=("$REGISTER: $file 'breaks' a requirement but has no owner (FRn or #task).")
    else
      problems+=("$REGISTER: $file has verdict '$verdict'; use 'keeps #N', 'keeps none — <reason>' or 'breaks #N'.")
    fi
  done <<<"$register"
  while IFS= read -r file; do
    [[ -n "$file" ]] && ! grep -qxF -- "$file" <<<"$listed" \
      && problems+=("$file deletes, overwrites, hands over or expires data but isn't in $REGISTER: add a row with its verdict.")
  done <<<"$found"
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

check_scenarios
check_data_removals

if (( ${PR_FILES:-0} > MAX_FILES || lines > MAX_LINES )) && ! grep -q '^Size exception:' <<<"$body"; then
  problems+=("PR is ${PR_FILES:-0} files / ${lines} lines (limit ~${MAX_FILES} / ~${MAX_LINES}). Split it, or add a 'Size exception: <reason, agreed with the owner>' line.")
fi

if ((${#problems[@]})); then
  printf 'PR rules not met (CLAUDE.md):\n'
  printf -- '- %s\n' "${problems[@]}"
  exit 1
fi
echo "PR rules met."
