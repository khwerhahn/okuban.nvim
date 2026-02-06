---
name: close-issue
description: Close a GitHub issue after work is complete. Moves the kanban label to done, comments on the issue, and closes it.
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
gh pr list --search "Fixes #$ARGUMENTS OR Closes #$ARGUMENTS" --json number,title,state,url
```

- If open PRs exist, warn: "There are open PRs linked to this issue. Close them first or merge them?"
- If merged PRs exist, note them as evidence of completion

### 3. Move the kanban label to Done

Remove any existing `okuban:` label and add `okuban:done`:

```bash
gh issue edit $ARGUMENTS --remove-label "okuban:in-progress" --add-label "okuban:done"
```

### 4. Comment and close

```bash
gh issue comment $ARGUMENTS --body "Work completed. Closing this issue."
gh issue close $ARGUMENTS --reason "completed"
```

### 5. Confirm

Print a summary:
- Issue: #NUMBER — TITLE
- Status: **Closed** (completed)
- Kanban: moved to **Done**
