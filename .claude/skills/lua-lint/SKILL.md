---
name: lua-lint
description: Run StyLua formatting and Luacheck linting on Lua files
argument-hint: "[file-or-directory]"
allowed-tools: Bash, Read, Glob, Grep
disable-model-invocation: true
---

# Lua Lint & Format

Run StyLua and Luacheck on the codebase.

## Usage

- `/lua-lint` — Check all Lua files
- `/lua-lint lua/okuban/api.lua` — Check a specific file

## Steps

### 1. Format Check (StyLua)

```bash
# Check formatting (dry-run)
stylua --check lua/ tests/

# Auto-fix formatting
stylua lua/ tests/
```

If `$ARGUMENTS` is provided:
```bash
stylua --check $ARGUMENTS
```

### 2. Lint (Luacheck)

```bash
# Lint all
luacheck lua/ tests/

# Lint specific file
luacheck $ARGUMENTS
```

### 3. Report

After running both tools:
1. List any formatting issues found (and whether they were auto-fixed)
2. List all Luacheck warnings/errors grouped by file
3. For each issue, explain what's wrong and suggest a fix
4. If everything passes, confirm clean status

## Prerequisites

If tools are missing, suggest installation:
```bash
# StyLua
brew install stylua
# or: cargo install stylua

# Luacheck
luarocks install luacheck
# or: brew install luacheck
```
