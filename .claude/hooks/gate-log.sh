#!/usr/bin/env bash
# PostToolUse hook (Skill, Agent): records gates against commits in <git dir>/claude-gates.log
# as "<commit> <gate>". Never blocks: a logging failure must not stop work.
#  - Skill: "<HEAD> skill:<name>" (an audit trail of what was loaded; not proof it passed).
#  - Agent: "<commit> independent-review", only for a finished (foreground) agent whose report
#    contains the line "REVIEWED <commit>". A background agent returns before it has reviewed.
# The "verified" gate is written only by scripts/verify.sh when build, tests and analyze pass.
set -uo pipefail

input=$(cat)
log="$(git rev-parse --git-common-dir 2>/dev/null)/claude-gates.log" || exit 0

case "$(jq -r '.tool_name // empty' <<<"$input")" in
  Skill)
    skill=$(jq -r '.tool_input.skill // empty' <<<"$input")
    head=$(git rev-parse HEAD 2>/dev/null) || exit 0
    [[ -n "$skill" ]] && echo "$head skill:$skill" >>"$log" ;;
  Agent)
    [[ "$(jq -r '.tool_input.run_in_background // false' <<<"$input")" == "true" ]] && exit 0
    reviewed=$(jq -r '.tool_response | tostring' <<<"$input" \
      | grep -oE 'REVIEWED [0-9a-f]{7,40}' | tail -1 | cut -d' ' -f2)
    [[ -z "$reviewed" ]] && exit 0
    commit=$(git rev-parse --verify --quiet "${reviewed}^{commit}") || exit 0
    echo "$commit independent-review" >>"$log" ;;
esac
exit 0
