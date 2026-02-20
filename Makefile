.PHONY: lint test check format

lint: ## Run StyLua check and Luacheck
	@echo "Checking formatting with StyLua..."
	@stylua --check . || (echo "Run 'make format' to fix formatting"; exit 1)
	@echo "Running Luacheck..."
	@luacheck lua/ tests/

test: ## Run plenary.nvim tests
	@echo "Running tests..."
	@nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"

check: lint test ## Run lint + test (same as CI)

format: ## Auto-format with StyLua
	@stylua .
	@echo "Formatted."
