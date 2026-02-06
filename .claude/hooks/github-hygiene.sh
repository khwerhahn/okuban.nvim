#!/bin/bash
# SessionStart hook: comprehensive GitHub hygiene checks.
# Warns about stale issues, unmerged PRs, missing branches, label mismatches,
# and other workflow issues that should be addressed.
#
# Dependencies: jq (for JSON parsing), gh (for GitHub API).
# If either is missing, the hook exits gracefully.

# Check for required tools
if ! command -v jq &>/dev/null || ! command -v gh &>/dev/null; then
  exit 0  # Skip silently; tools not installed yet
fi

# Verify we're in a git repo with GitHub remote
if ! git rev-parse --git-dir &>/dev/null 2>&1; then
  exit 0
fi

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
if [ -z "$REPO" ]; then
  exit 0
fi

WARNINGS=""
ACTIONS=""

# ---------------------------------------------------------------------------
# 1. Check for in-progress issues without open PRs
# ---------------------------------------------------------------------------
IN_PROGRESS=$(gh issue list --repo "$REPO" --label "okuban:in-progress" --state open --json number,title --jq '.[] | "\(.number)|\(.title)"' 2>/dev/null)

if [ -n "$IN_PROGRESS" ]; then
  while IFS='|' read -r ISSUE_NUM ISSUE_TITLE; do
    # Check if any open PR references this issue
    HAS_PR=$(gh pr list --repo "$REPO" --state open --json number,title,body --jq "[.[] | select(.body | test(\"(Fixes|Closes|Resolves|Refs)\\s*#${ISSUE_NUM}\\b\"; \"i\")) | .number] | length" 2>/dev/null)
    if [ "$HAS_PR" = "0" ] || [ -z "$HAS_PR" ]; then
      # Also check by branch naming convention
      HAS_BRANCH_PR=$(gh pr list --repo "$REPO" --state open --json headRefName --jq "[.[] | select(.headRefName | test(\"issue-${ISSUE_NUM}(-|$)\"))] | length" 2>/dev/null)
      if [ "$HAS_BRANCH_PR" = "0" ] || [ -z "$HAS_BRANCH_PR" ]; then
        WARNINGS="${WARNINGS}\n  - Issue #${ISSUE_NUM} (${ISSUE_TITLE}) is okuban:in-progress but has NO open PR"
        ACTIONS="${ACTIONS}\n  - Create a feature branch and PR for #${ISSUE_NUM}, or move it back to okuban:todo"
      fi
    fi
  done <<< "$IN_PROGRESS"
fi

# ---------------------------------------------------------------------------
# 2. Check for open PRs with all CI checks passing (ready to merge)
# ---------------------------------------------------------------------------
OPEN_PRS=$(gh pr list --repo "$REPO" --state open --json number,title,statusCheckRollup --jq '.[] | {number, title, checks: [.statusCheckRollup[]? | .conclusion] | unique}' 2>/dev/null)

if [ -n "$OPEN_PRS" ]; then
  while IFS= read -r PR_JSON; do
    PR_NUM=$(echo "$PR_JSON" | jq -r '.number')
    PR_TITLE=$(echo "$PR_JSON" | jq -r '.title')
    CHECKS=$(echo "$PR_JSON" | jq -r '.checks')
    # All checks passed if the only conclusion is "SUCCESS" (or empty for no checks)
    ALL_PASS=$(echo "$CHECKS" | jq 'if length == 0 then false elif . == ["SUCCESS"] then true else false end')
    if [ "$ALL_PASS" = "true" ]; then
      WARNINGS="${WARNINGS}\n  - PR #${PR_NUM} (${PR_TITLE}) has all CI checks passing — ready to merge"
      ACTIONS="${ACTIONS}\n  - Review and merge PR #${PR_NUM}, or request changes if not ready"
    fi
  done < <(echo "$OPEN_PRS" | jq -c '.')
fi

# ---------------------------------------------------------------------------
# 3. Check for stale review issues (labeled okuban:review but no recent activity)
# ---------------------------------------------------------------------------
IN_REVIEW=$(gh issue list --repo "$REPO" --label "okuban:review" --state open --json number,title --jq '.[] | "\(.number)|\(.title)"' 2>/dev/null)

if [ -n "$IN_REVIEW" ]; then
  while IFS='|' read -r ISSUE_NUM ISSUE_TITLE; do
    WARNINGS="${WARNINGS}\n  - Issue #${ISSUE_NUM} (${ISSUE_TITLE}) is in okuban:review — needs attention"
    ACTIONS="${ACTIONS}\n  - Review and merge the PR for #${ISSUE_NUM}, or move it to okuban:done"
  done <<< "$IN_REVIEW"
fi

# ---------------------------------------------------------------------------
# 4. Check current branch: feature branch without a PR
# ---------------------------------------------------------------------------
BRANCH=$(git branch --show-current 2>/dev/null)

if [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  # Check if this branch has an open PR
  BRANCH_PR=$(gh pr list --repo "$REPO" --head "$BRANCH" --state open --json number --jq '.[0].number' 2>/dev/null)
  if [ -z "$BRANCH_PR" ]; then
    # No PR — check for unpushed commits
    UNPUSHED=$(git log "origin/main..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [ "$UNPUSHED" -gt 0 ]; then
      WARNINGS="${WARNINGS}\n  - Branch '${BRANCH}' has ${UNPUSHED} unpushed commit(s) with no open PR"
      ACTIONS="${ACTIONS}\n  - Push the branch and create a PR: git push -u origin ${BRANCH} && gh pr create"
    fi
  else
    # PR exists — this branch's work is done, should be on main
    # Check if there are uncommitted or unpushed changes first
    DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    UNPUSHED=$(git log "origin/${BRANCH}..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [ "$DIRTY" -eq 0 ] && [ "$UNPUSHED" -eq 0 ]; then
      WARNINGS="${WARNINGS}\n  - Still on branch '${BRANCH}' which already has PR #${BRANCH_PR} — work is done here"
      ACTIONS="${ACTIONS}\n  - Switch back to main: git checkout main && git pull"
    elif [ "$DIRTY" -gt 0 ] || [ "$UNPUSHED" -gt 0 ]; then
      WARNINGS="${WARNINGS}\n  - Branch '${BRANCH}' has PR #${BRANCH_PR} but also has uncommitted/unpushed changes"
      ACTIONS="${ACTIONS}\n  - Commit and push remaining changes, or switch to main if they're unrelated"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 5. Check for closed issues still labeled okuban:in-progress
# ---------------------------------------------------------------------------
CLOSED_IN_PROGRESS=$(gh issue list --repo "$REPO" --label "okuban:in-progress" --state closed --json number,title --jq '.[] | "\(.number)|\(.title)"' 2>/dev/null)

if [ -n "$CLOSED_IN_PROGRESS" ]; then
  while IFS='|' read -r ISSUE_NUM ISSUE_TITLE; do
    WARNINGS="${WARNINGS}\n  - Issue #${ISSUE_NUM} (${ISSUE_TITLE}) is CLOSED but still labeled okuban:in-progress"
    ACTIONS="${ACTIONS}\n  - Fix label: gh issue edit ${ISSUE_NUM} --remove-label okuban:in-progress --add-label okuban:done"
  done <<< "$CLOSED_IN_PROGRESS"
fi

# ---------------------------------------------------------------------------
# 6. Check for open issues labeled okuban:done (should be closed)
# ---------------------------------------------------------------------------
OPEN_DONE=$(gh issue list --repo "$REPO" --label "okuban:done" --state open --json number,title --jq '.[] | "\(.number)|\(.title)"' 2>/dev/null)

if [ -n "$OPEN_DONE" ]; then
  while IFS='|' read -r ISSUE_NUM ISSUE_TITLE; do
    WARNINGS="${WARNINGS}\n  - Issue #${ISSUE_NUM} (${ISSUE_TITLE}) is labeled okuban:done but still OPEN"
    ACTIONS="${ACTIONS}\n  - Close the issue: gh issue close ${ISSUE_NUM}"
  done <<< "$OPEN_DONE"
fi

# ---------------------------------------------------------------------------
# Output results
# ---------------------------------------------------------------------------
if [ -n "$WARNINGS" ]; then
  echo ""
  echo "=== GITHUB HYGIENE CHECK ==="
  echo -e "Warnings:${WARNINGS}"
  echo ""
  echo -e "Suggested actions:${ACTIONS}"
  echo ""
  echo "Address these issues before starting new work."
fi
