---
name: nvim-test
description: Run Neovim plugin tests using plenary.nvim in headless mode
argument-hint: "[test-file-or-directory]"
allowed-tools: Bash, Read, Glob, Grep
---

# Neovim Plugin Test Runner

Run tests for the okuban.nvim plugin using plenary.nvim.

## Usage

- `/nvim-test` — Run all tests in `tests/`
- `/nvim-test tests/test_api.lua` — Run a specific test file

## How to Run

### All tests:
```bash
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

### Single file:
```bash
nvim --headless -c "PlenaryBustedFile $ARGUMENTS"
```

## Test File Convention

Test files must:
- Live in `tests/` directory
- End with `_spec.lua`
- Use plenary busted-style syntax:

```lua
describe("module_name", function()
  before_each(function()
    -- setup
  end)

  it("should do something", function()
    assert.are.equal(expected, actual)
  end)
end)
```

## Minimal Init

Tests use `tests/minimal_init.lua` which loads only the plugin and plenary — no user config.

## After Running

1. Report pass/fail counts
2. Show any failing test details with file:line references
3. If tests fail, read the failing test and the source code to suggest fixes
