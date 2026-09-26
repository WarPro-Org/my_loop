#!/usr/bin/env bash
# PreToolUse hook (create / merge pull request): refuses unless the PR's head commit has the
# final gate (verification-loop) and an independent review logged by gate-log.sh. This makes
# "ticked but never ran" impossible for those two gates.
set -uo pipefail

readonly REQUIRED_GATES=(verification-loop independent-review)

deny() {
  jq -n --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")
case "$tool" in
  *create_pull_request)
    branch=$(jq -r '.tool_input.head // empty' <<<"$input")
    ref="refs/heads/${branch}" ;;
  *merge_pull_request)
    number=$(jq -r '.tool_input.pullNumber // empty' <<<"$input")
    ref="refs/pull/${number}/head" ;;
  *) exit 0 ;;
esac

commit=$(git ls-remote origin "$ref" 2>/dev/null | awk 'NR==1 {print $1}')
[[ -z "$commit" ]] && deny "Gate check: could not find the pushed commit for $ref. Push first, then retry."

log="$(git rev-parse --git-common-dir)/claude-gates.log"
missing=()
for gate in "${REQUIRED_GATES[@]}"; do
  grep -qx "$commit $gate" "$log" 2>/dev/null || missing+=("$gate")
done

if ((${#missing[@]})); then
  deny "Gate check: commit ${commit:0:7} has no record of: ${missing[*]}. Run them on this exact commit (Skill verification-loop; an Agent call described as a review), then retry. See CLAUDE.md → Gates are mandatory."
fi
exit 0
