---
name: gh-graphql
description: Test and explore GitHub issue/label CLI commands for the kanban board
argument-hint: "[command-description]"
allowed-tools: Bash, Read, Write, Grep
---

# GitHub CLI Query Explorer

Build and test `gh` CLI commands for issue and label management.

## Usage

- `/gh-graphql list issues with label` — Build and test a gh issue list command
- `/gh-graphql move card between columns` — Test label swap commands
- `/gh-graphql` — Interactive exploration of the gh CLI

## Steps

1. **Check auth**: Run `gh auth status` to verify GitHub access
2. **Build command**: Construct the `gh` command for `$ARGUMENTS`
3. **Test it**: Execute the command and inspect output
4. **Iterate**: Refine based on the response
5. **Save**: Write working patterns to `lua/okuban/` as reusable command templates

## Key Commands

### List issues per column
```bash
gh issue list --label "okuban:todo" --json number,title,assignees,labels,state
```

### Move a card (label swap)
```bash
gh issue edit 42 --remove-label "okuban:todo" --add-label "okuban:in-progress"
```

### Get issue details
```bash
gh issue view 42 --json title,body,labels,assignees,comments,state
```

### Setup labels
```bash
gh label create "okuban:backlog" --color "c5def5" --description "Kanban: Not yet planned"
gh label create "okuban:todo" --color "0075ca" --description "Kanban: Planned for work"
gh label create "okuban:in-progress" --color "fbca04" --description "Kanban: Actively being worked on"
gh label create "okuban:review" --color "d4c5f9" --description "Kanban: Awaiting review"
gh label create "okuban:done" --color "0e8a16" --description "Kanban: Completed"
```

### List all labels
```bash
gh label list --json name,color,description
```

## Output

Always provide:
1. The working command
2. Example response (trimmed)
3. Notes on pagination or rate limits if relevant
