---
name: close-issue
description: Close a GitHub issue after work is complete. Moves the kanban label to done, closes stale PRs, deletes feature branches, and closes the issue.
argument-hint: "<issue-number>"
allowed-tools: Bash, Read, Grep
---

# Close a GitHub Issue

Close issue #$ARGUMENTS after verifying work is complete.

## Steps

### 1. Verify the issue exists and is open

```bash
gh issue view $ARGUMENTS --json number,title,state,labels
```

- If already closed, inform the user and stop
- Show the issue title for confirmation

### 2. Check for linked PRs

```bash
gh pr list --search "Fixes #$ARGUMENTS OR Closes #$ARGUMENTS" --state all --json number,title,state,url,headRefName
```

Also check by branch name convention:

```bash
gh pr list --head "issue-$ARGUMENTS" --state all --json number,title,state,url,headRefName
```

- If merged PRs exist, note them as evidence of completion
- If open PRs exist, they will be closed in the next step

### 3. Close stale open PRs linked to this issue

For each **open** PR found in step 2:

```bash
gh pr close <PR_NUMBER> --comment "Superseded — issue #$ARGUMENTS closed directly."
```

Collect the `headRefName` from each closed PR for branch cleanup in step 5.

### 4. Move the kanban label to Done

Remove any existing `okuban:` label and add `okuban:done`:

```bash
gh issue edit $ARGUMENTS --remove-label "okuban:backlog" --remove-label "okuban:todo" --remove-label "okuban:in-progress" --remove-label "okuban:review" --add-label "okuban:done"
```

### 5. Comment and close

```bash
gh issue comment $ARGUMENTS --body "Work completed. Closing this issue."
gh issue close $ARGUMENTS --reason "completed"
```

### 6. Delete remote feature branches for this issue

For each branch name collected from PRs in step 2/3, plus any remote branches matching the issue pattern:

```bash
# Find remote branches matching the issue number
git fetch --prune
git branch -r --list "*issue-$ARGUMENTS*"
```

For each matching remote branch (skip `main`, `HEAD`, `release-please`):

```bash
git push origin --delete <branch-name>
```

### 7. Clean up local feature branches

Switch to `main` and pull latest:

```bash
git checkout main
git pull
```

Find and delete **all** local branches matching this issue:

```bash
git branch --list "*issue-$ARGUMENTS*"
```

For each matching branch (skip the current branch):

```bash
git branch -D <branch>
```

Prune stale remote tracking refs:

```bash
git fetch --prune
```

### 8. Confirm

Print a summary:
- Issue: #NUMBER — TITLE
- Status: **Closed** (completed)
- Kanban: moved to **Done**
- PRs closed: list any PRs closed in step 3 (or "none")
- Remote branches deleted: list branches deleted in step 6 (or "none")
- Local branches deleted: list branches deleted in step 7 (or "none")
