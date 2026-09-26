#!/usr/bin/env bash
# PostToolUse hook (Skill, Agent): records which gate ran on which commit, so a PR can only
# claim gates that really ran. Log: <git dir>/claude-gates.log, lines "<commit> <gate>".
# Never blocks: a logging failure must not stop work.
set -uo pipefail

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")
case "$tool" in
  Skill) gate=$(jq -r '.tool_input.skill // empty' <<<"$input") ;;
  Agent)
    # An independent review is an Agent call whose description says "review".
    description=$(jq -r '.tool_input.description // empty' <<<"$input")
    [[ "${description,,}" == *review* ]] && gate="independent-review" || gate="" ;;
  *) gate="" ;;
esac
[[ -z "$gate" ]] && exit 0

commit=$(git rev-parse HEAD 2>/dev/null) || exit 0
log="$(git rev-parse --git-common-dir)/claude-gates.log"
echo "$commit $gate" >>"$log"
exit 0
