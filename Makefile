.PHONY: claude-code ensure-docker

# Ensure Docker is running (cross-platform: macOS and Windows)
ensure-docker:
	@echo "🐳 Checking Docker status..."
	@if command -v docker >/dev/null 2>&1; then \
		if docker info >/dev/null 2>&1; then \
			echo "✅ Docker is running"; \
		else \
			echo "⚠️ Docker is not running. Starting Docker..."; \
			if [ "$$(uname)" = "Darwin" ]; then \
				open -a Docker; \
				echo "⏳ Waiting for Docker to start..."; \
				timeout=60; \
				while ! docker info >/dev/null 2>&1 && [ $$timeout -gt 0 ]; do \
					sleep 2; \
					timeout=$$((timeout - 2)); \
					printf "."; \
				done; \
				echo ""; \
				if docker info >/dev/null 2>&1; then \
					echo "✅ Docker started successfully"; \
				else \
					echo "❌ Docker failed to start within 60 seconds"; \
					exit 1; \
				fi; \
			elif [ "$$(uname -o 2>/dev/null)" = "Msys" ] || [ "$$(uname -o 2>/dev/null)" = "Cygwin" ] || [ -n "$$WINDIR" ]; then \
				echo "Starting Docker Desktop on Windows..."; \
				cmd.exe /c "start \"\" \"C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe\"" 2>/dev/null || \
				powershell.exe -Command "Start-Process 'C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe'" 2>/dev/null || \
				echo "⚠️ Could not auto-start Docker. Please start Docker Desktop manually."; \
				echo "⏳ Waiting for Docker to start..."; \
				timeout=60; \
				while ! docker info >/dev/null 2>&1 && [ $$timeout -gt 0 ]; do \
					sleep 2; \
					timeout=$$((timeout - 2)); \
					printf "."; \
				done; \
				echo ""; \
				if docker info >/dev/null 2>&1; then \
					echo "✅ Docker started successfully"; \
				else \
					echo "❌ Docker failed to start within 60 seconds"; \
					echo "Please start Docker Desktop manually and try again."; \
					exit 1; \
				fi; \
			else \
				echo "⚠️ Unsupported OS for auto-starting Docker. Please start Docker manually."; \
				exit 1; \
			fi; \
		fi; \
	else \
		echo "❌ Docker is not installed. Please install Docker Desktop."; \
		exit 1; \
	fi

claude-code: ensure-docker ## Start Claude Code with comprehensive tool permissions including compound commands
	@echo "🔄 Checking for Claude Code updates..."
	@brew upgrade claude-code 2>/dev/null || echo "⚠️ Update check failed, continuing with current version"
	@echo "🚀 Starting Claude Code..."
	claude --continue --dangerously-skip-permissions
