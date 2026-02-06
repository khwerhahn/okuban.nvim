# Label Setup Guide

okuban.nvim uses GitHub issue labels to organize your kanban board. You can create them automatically with `:OkubanSetup` or manually with the `gh` commands below.

---

## Kanban Column Labels

These 5 labels power the kanban board. Created by `:OkubanSetup`.

| Label | Color | Description |
|-------|-------|-------------|
| `okuban:backlog` | `#c5def5` (light blue) | Not yet planned |
| `okuban:todo` | `#0075ca` (blue) | Planned for work |
| `okuban:in-progress` | `#fbca04` (yellow) | Actively being worked on |
| `okuban:review` | `#d4c5f9` (lavender) | Awaiting review |
| `okuban:done` | `#0e8a16` (green) | Completed |

```bash
gh label create "okuban:backlog"     --color "c5def5" --description "Kanban: Not yet planned"
gh label create "okuban:todo"        --color "0075ca" --description "Kanban: Planned for work"
gh label create "okuban:in-progress" --color "fbca04" --description "Kanban: Actively being worked on"
gh label create "okuban:review"      --color "d4c5f9" --description "Kanban: Awaiting review"
gh label create "okuban:done"        --color "0e8a16" --description "Kanban: Completed"
```

Issues without any `okuban:` label appear in an **Unsorted** column (configurable).

---

## Type Labels

Categorize the kind of work. Created by `:OkubanSetup --full`.

| Label | Color | Description |
|-------|-------|-------------|
| `type: bug` | `#d73a4a` (red) | Something is not working |
| `type: feature` | `#0075ca` (blue) | New functionality |
| `type: docs` | `#fef2c0` (cream) | Documentation improvement |
| `type: chore` | `#e6e6e6` (gray) | Maintenance, refactoring, CI |

```bash
gh label create "type: bug"      --color "d73a4a" --description "Something is not working"
gh label create "type: feature"  --color "0075ca" --description "New functionality"
gh label create "type: docs"     --color "fef2c0" --description "Documentation improvement"
gh label create "type: chore"    --color "e6e6e6" --description "Maintenance, refactoring, CI"
```

---

## Priority Labels

Signal urgency. Created by `:OkubanSetup --full`.

| Label | Color | Description |
|-------|-------|-------------|
| `priority: critical` | `#d73a4a` (red) | Drop everything |
| `priority: high` | `#d93f0b` (orange) | Do this cycle |
| `priority: medium` | `#fbca04` (yellow) | Important but not urgent |
| `priority: low` | `#0e8a16` (green) | Backlog / nice-to-have |

```bash
gh label create "priority: critical" --color "d73a4a" --description "Drop everything"
gh label create "priority: high"     --color "d93f0b" --description "Do this cycle"
gh label create "priority: medium"   --color "fbca04" --description "Important but not urgent"
gh label create "priority: low"      --color "0e8a16" --description "Backlog / nice-to-have"
```

---

## Community Labels

Help contributors find entry points. Created by `:OkubanSetup --full`.

| Label | Color | Description |
|-------|-------|-------------|
| `good first issue` | `#7057ff` (purple) | Good for newcomers |
| `help wanted` | `#008672` (teal) | Maintainer seeks help |
| `needs: triage` | `#fbca04` (yellow) | Needs initial assessment |
| `needs: repro` | `#fbca04` (yellow) | Needs reproduction steps |

```bash
gh label create "good first issue" --color "7057ff" --description "Good for newcomers"
gh label create "help wanted"      --color "008672" --description "Maintainer seeks help"
gh label create "needs: triage"    --color "fbca04" --description "Needs initial assessment"
gh label create "needs: repro"     --color "fbca04" --description "Needs reproduction steps"
```

`good first issue` and `help wanted` are [GitHub-special labels](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/encouraging-helpful-contributions-to-your-project-with-labels) — they appear on your repo's Contribute page. Never rename them.

---

## Color Conventions

All colors use GitHub's native palette for readability on both light and dark themes:

| Color | Hex | Used for |
|-------|-----|----------|
| Red | `#d73a4a` | Bugs, critical priority |
| Orange | `#d93f0b` | High priority |
| Yellow | `#fbca04` | Medium priority, needs attention, in-progress |
| Green | `#0e8a16` | Low priority, done |
| Blue | `#0075ca` | Features, todo |
| Light blue | `#c5def5` | Backlog |
| Lavender | `#d4c5f9` | Review |
| Purple | `#7057ff` | Community (good first issue) |
| Teal | `#008672` | Community (help wanted) |
| Cream | `#fef2c0` | Docs |
| Gray | `#e6e6e6` | Chores |

---

## Moving Cards

Moving an issue between kanban columns = swapping labels:

```bash
gh issue edit 42 --remove-label "okuban:todo" --add-label "okuban:in-progress"
```

The plugin handles this automatically when you press `m` on a card.
