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

### 2. Assign yourself

```bash
gh issue edit $ARGUMENTS --add-assignee @me
```

### 3. Apply the kanban label

```bash
gh issue edit $ARGUMENTS --add-label "okuban:in-progress"
```

If the issue already has another `okuban:` label, remove it first:

```bash
gh issue edit $ARGUMENTS --remove-label "okuban:todo" --add-label "okuban:in-progress"
```

### 4. Create a feature branch

Derive a short slug from the issue title (lowercase, hyphens, no special chars, max 40 chars). Then:

```bash
git checkout -b feat/issue-$ARGUMENTS-<slug>
```

Use `fix/` prefix instead of `feat/` if the issue has a `type: bug` label.

### 5. Comment on the issue

```bash
gh issue comment $ARGUMENTS --body "Started working on this issue."
```

### 6. Confirm

Print a summary:
- Issue: #NUMBER — TITLE
- Branch: `feat/issue-NUMBER-slug`
- Kanban: moved to **In Progress**
- Remind: all commits must include `Refs #$ARGUMENTS` or `Fixes #$ARGUMENTS`
