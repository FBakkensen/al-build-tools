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

# Force re-download of BusinessCentral.LinterCop analyzer (0/1)
LINTERCOP_FORCE ?= 0
export ALBT_FORCE_LINTERCOP := $(LINTERCOP_FORCE)

# =============================================================================
# Provisioning Options (override via environment or make variables)
# =============================================================================
# Example usage:
#   make download-compiler AL_TOOL_VERSION=11.0.0
#   make download-symbols ALBT_SYMBOL_CACHE_ROOT=/tmp/bc-cache
ifdef SYMBOL_CACHE_ROOT
export ALBT_SYMBOL_CACHE_ROOT := $(SYMBOL_CACHE_ROOT)
endif
ifdef SYMBOL_FEEDS
export ALBT_SYMBOL_FEEDS := $(SYMBOL_FEEDS)
endif
ifdef AL_TOOL_VERSION
export AL_TOOL_VERSION
endif

# =============================================================================
# PowerShell Invocation (Windows-only)
# =============================================================================
SCRIPT_CMD := pwsh -NoLogo -NoProfile -File

# =============================================================================
# Targets
# =============================================================================
.PHONY: all build clean help show-config show-analyzers download-compiler download-symbols

# Default target
all: build

# Help target
help:
	@echo "AL Project Build System (PowerShell only)"
	@echo "========================================="
	@echo ""
	@echo "Available targets:"
	@echo "  download-compiler - Install/update the AL compiler dotnet tool"
	@echo "  download-symbols  - Download required Business Central symbol packages"
	@echo "  build          - Compile the AL project with analysis"
	@echo "  clean          - Remove build artifacts"
	@echo "  show-config    - Display current configuration"
	@echo "  show-analyzers - Show discovered analyzers"
	@echo "  help           - Show this help message"
	@echo ""
	@echo "Options (set in Makefile):"
	@echo "  WARN_AS_ERROR=$(WARN_AS_ERROR)   Treat warnings as errors (/warnaserror+)"
	@echo "  RULESET_PATH=$(RULESET_PATH)   Optional ruleset file passed to ALC if present"
	@echo "  AL_TOOL_VERSION=$(AL_TOOL_VERSION)   Override compiler tool version when provisioning"
	@echo "  ALBT_SYMBOL_CACHE_ROOT=$(ALBT_SYMBOL_CACHE_ROOT)   Override symbol cache root path"
	@echo "  ALBT_SYMBOL_FEEDS=$(ALBT_SYMBOL_FEEDS)   Comma-separated feeds for symbol provisioning"
	@echo "  LINTERCOP_FORCE=$(LINTERCOP_FORCE)   Force re-download of BusinessCentral.LinterCop analyzer (1=yes)"
	@echo ""
	@echo "Run provisioning targets before 'make build' when setting up a new environment."

# Provisioning targets
download-compiler:
	ALBT_VIA_MAKE=1 $(SCRIPT_CMD) scripts/make/download-compiler.ps1 $(APP_DIR)

download-symbols:
	ALBT_VIA_MAKE=1 $(SCRIPT_CMD) scripts/make/download-symbols.ps1 $(APP_DIR) -VerboseSymbols

# Build target - main compilation
# Assumes download-compiler and download-symbols have been run at least once per environment.
build:
	ALBT_VIA_MAKE=1 $(SCRIPT_CMD) scripts/make/build.ps1 $(APP_DIR)

# Clean build artifacts
clean:
	ALBT_VIA_MAKE=1 $(SCRIPT_CMD) scripts/make/clean.ps1 $(APP_DIR)

# Show current configuration
show-config:
	ALBT_VIA_MAKE=1 $(SCRIPT_CMD) scripts/make/show-config.ps1 $(APP_DIR)

# Show discovered analyzers
show-analyzers:
	ALBT_VIA_MAKE=1 $(SCRIPT_CMD) scripts/make/show-analyzers.ps1 $(APP_DIR)
