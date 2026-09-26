#!/usr/bin/env bash
# PreToolUse hook:
#  - create / merge / auto-merge a pull request: refuses unless the PR's pushed head commit has
#    "verified" (scripts/verify.sh passed) and "independent-review" (a finished review that named
#    that commit) in the gate log.
#  - Bash: refuses any command that touches the gate log directly, so entries can't be hand-written.
# The log lives in the container's .git dir: a new session starts empty, so gates re-run there.
set -uo pipefail

readonly REQUIRED_GATES=(verified independent-review)
readonly LOG_NAME=claude-gates.log

deny() {
  jq -n --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")
case "$tool" in
  Bash)
    jq -r '.tool_input.command // empty' <<<"$input" | grep -q "$LOG_NAME" \
      && deny "The gate log is written only by the hooks and scripts/verify.sh, never by hand."
    exit 0 ;;
  *create_pull_request)
    ref="refs/heads/$(jq -r '.tool_input.head // empty' <<<"$input")" ;;
  *merge_pull_request | *enable_pr_auto_merge)
    ref="refs/pull/$(jq -r '.tool_input.pullNumber // empty' <<<"$input")/head" ;;
  *) exit 0 ;;
esac

commit=$(git ls-remote origin "$ref" 2>/dev/null | awk 'NR==1 {print $1}')
[[ -z "$commit" ]] && deny "Gate check: could not find the pushed commit for $ref. Push first, then retry."

log="$(git rev-parse --git-common-dir)/$LOG_NAME"
missing=()
for gate in "${REQUIRED_GATES[@]}"; do
  grep -qx "$commit $gate" "$log" 2>/dev/null || missing+=("$gate")
done
((${#missing[@]})) && deny "Gate check: commit ${commit:0:7} has no record of: ${missing[*]}. On this exact commit run scripts/verify.sh (verified) and a foreground independent review whose report ends with 'REVIEWED ${commit:0:7}', then retry."
exit 0
