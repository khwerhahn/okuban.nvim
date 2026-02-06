#!/bin/bash
# SessionStart hook: detects the current issue from the branch name and injects context.
# Output is plain text that Claude sees at session start.
#
# Dependencies: jq (for JSON parsing), gh (for issue details).
# If either is missing, the hook exits gracefully.

# Check for required tools
if ! command -v jq &>/dev/null || ! command -v gh &>/dev/null; then
  exit 0  # Skip silently; tools not installed yet
fi

BRANCH=$(git -C "$CLAUDE_PROJECT_DIR" branch --show-current 2>/dev/null)

if [ -z "$BRANCH" ]; then
  exit 0
fi

# Extract issue number from branch name patterns:
# feat/issue-42-description, fix/issue-42-description, docs/issue-42-description
ISSUE_NUM=$(echo "$BRANCH" | grep -oE 'issue-([0-9]+)' | grep -oE '[0-9]+' | head -1)

if [ -z "$ISSUE_NUM" ]; then
  exit 0
fi

# Fetch issue details (fast, ~400ms)
ISSUE_DATA=$(gh issue view "$ISSUE_NUM" --json title,state,labels --repo "$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)" 2>/dev/null)

if [ -z "$ISSUE_DATA" ]; then
  exit 0
fi

TITLE=$(echo "$ISSUE_DATA" | jq -r '.title // "Unknown"')
STATE=$(echo "$ISSUE_DATA" | jq -r '.state // "Unknown"')
LABELS=$(echo "$ISSUE_DATA" | jq -r '[.labels[].name] | join(", ") // "none"')

echo "Currently on branch '$BRANCH' which is linked to Issue #${ISSUE_NUM}: ${TITLE} (${STATE}). Labels: ${LABELS}. All commits in this session must reference this issue with 'Fixes #${ISSUE_NUM}' or 'Refs #${ISSUE_NUM}'."
