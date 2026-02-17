---
name: start-issue
description: Start work on a GitHub issue. Fetches details, assigns you, creates a branch, applies the kanban label, and comments on the issue.
argument-hint: "<issue-number>"
allowed-tools: Bash, Read, Grep
---

# Start Work on a GitHub Issue

Begin work on issue #$ARGUMENTS.

## Steps

### 1. Fetch issue details

```bash
gh issue view $ARGUMENTS --json number,title,body,state,labels,assignees
```

- Confirm the issue exists and is **open**
- If the issue is closed, warn the user and ask whether to reopen it
- Summarize the issue title, description, and acceptance criteria

### 2. Verify clean starting state

Ensure we're on the default branch with a clean working tree:

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
CURRENT=$(git branch --show-current)
```

- If not on the default branch: switch to it and pull latest
  ```bash
  git checkout $DEFAULT_BRANCH
  git pull
  ```
- If the working tree is dirty (`git status --porcelain` has output): warn the user and ask before proceeding (uncommitted changes could be lost)

### 3. Check for existing work on this issue

Look for open PRs already linked to this issue:

```bash
gh pr list --search "Fixes #$ARGUMENTS OR Closes #$ARGUMENTS" --state open --json number,title,headRefName
```

Also check by branch name convention:

```bash
gh pr list --head "issue-$ARGUMENTS" --state open --json number,title,headRefName
```

And check for existing local branches:

```bash
git branch --list "*issue-$ARGUMENTS*"
```

- If an open PR exists: warn "PR #X already exists for this issue on branch `branch-name`. Continue anyway?" and ask the user
- If a local branch exists but no PR: offer to switch to it instead of creating a new one

### 4. Assign yourself

```bash
gh issue edit $ARGUMENTS --add-assignee @me
```

### 5. Apply the kanban label

```bash
gh issue edit $ARGUMENTS --add-label "okuban:in-progress"
```

If the issue already has another `okuban:` label, remove it first:

```bash
gh issue edit $ARGUMENTS --remove-label "okuban:todo" --add-label "okuban:in-progress"
```

### 6. Create a feature branch

Derive a short slug from the issue title (lowercase, hyphens, no special chars, max 40 chars). Then:

```bash
git checkout -b feat/issue-$ARGUMENTS-<slug>
```

Use `fix/` prefix instead of `feat/` if the issue has a `type: bug` label.

### 7. Comment on the issue

```bash
gh issue comment $ARGUMENTS --body "Started working on this issue."
```

### 8. Confirm

Print a summary:
- Issue: #NUMBER — TITLE
- Branch: `feat/issue-NUMBER-slug`
- Kanban: moved to **In Progress**
- Remind: all commits must include `Refs #$ARGUMENTS` or `Fixes #$ARGUMENTS`
