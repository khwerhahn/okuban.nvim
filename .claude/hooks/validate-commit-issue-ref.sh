#!/bin/bash
# PreToolUse hook: blocks git commits that don't reference a GitHub issue.
# Expects JSON on stdin with tool_name and tool_input fields.
#
# Dependencies: jq (for JSON parsing). If jq is not installed, the hook
# is skipped gracefully (commits are allowed).

INPUT=$(cat)

# Check for jq — required to parse hook input JSON
if ! command -v jq &>/dev/null; then
  exit 0  # Allow commit; can't parse without jq
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check Bash commands that are git commits
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

if ! echo "$COMMAND" | grep -qE '^git commit'; then
  exit 0
fi

# Exempt merge and revert commits
if echo "$COMMAND" | grep -qiE '(Merge|Revert)'; then
  exit 0
fi

# Check for issue reference anywhere in the commit command
if echo "$COMMAND" | grep -qiE '(Fixes|Closes|Resolves|Refs)\s+#[0-9]+'; then
  exit 0
fi

# Also check for bare #NUMBER references (common shorthand)
if echo "$COMMAND" | grep -qE '#[0-9]+'; then
  exit 0
fi

# Block the commit
echo "Commit message must reference a GitHub issue (e.g., Fixes #42, Refs #42)." >&2
exit 2
