# PowerShell-only Makefile for AL (Business Central) Project
# Uses Windows PowerShell 7+ (pwsh) scripts under scripts/make/

# =============================================================================
# App Directory Configuration
# =============================================================================
APP_DIR := .

# =============================================================================
# Build Options (tweak as needed)
# =============================================================================
# Treat AL compiler warnings as errors (1 to enable, 0 to disable)
WARN_AS_ERROR ?= 1
# Export so scripts inherit this setting
export WARN_AS_ERROR

# Optional ruleset file for analyzers (leave empty to disable)
# Example: RULESET_PATH := ruleset.json
RULESET_PATH ?= al.ruleset.json
export RULESET_PATH

# =============================================================================
# PowerShell Invocation (Windows-only)
# =============================================================================
SCRIPT_CMD := pwsh -NoLogo -NoProfile -File

# =============================================================================
# Targets
# =============================================================================
.PHONY: all build clean help show-config show-analyzers

# Default target
all: build

# Help target
help:
	@echo "AL Project Build System (PowerShell only)"
	@echo "========================================="
	@echo ""
	@echo "Available targets:"
	@echo "  build          - Compile the AL project with analysis"
	@echo "  clean          - Remove build artifacts"
	@echo "  show-config    - Display current configuration"
	@echo "  show-analyzers - Show discovered analyzers"
	@echo "  help           - Show this help message"
	@echo ""
	@echo "Options (set in Makefile):"
	@echo "  WARN_AS_ERROR=$(WARN_AS_ERROR)   Treat warnings as errors (/warnaserror+)"
	@echo "  RULESET_PATH=$(RULESET_PATH)   Optional ruleset file passed to ALC if present"

# Build target - main compilation
build:
	$(SCRIPT_CMD) scripts/make/build.ps1 $(APP_DIR)

# Clean build artifacts
clean:
	$(SCRIPT_CMD) scripts/make/clean.ps1 $(APP_DIR)

# Show current configuration
show-config:
	$(SCRIPT_CMD) scripts/make/show-config.ps1 $(APP_DIR)

# Show discovered analyzers
show-analyzers:
	$(SCRIPT_CMD) scripts/make/show-analyzers.ps1 $(APP_DIR)
