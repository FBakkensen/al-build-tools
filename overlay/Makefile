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
	@echo ""
	@echo "================================================================================"
	@printf "\033[33m🔧 MAKEFILE | AL Project Build System | PowerShell Only\033[0m\n"
	@echo "================================================================================"
	@echo ""
	@printf "\033[36m📋 AVAILABLE TARGETS:\033[0m\n"
	@printf "  \033[32m•\033[0m \033[37mdownload-compiler\033[0m - Install/update the AL compiler dotnet tool\n"
	@printf "  \033[32m•\033[0m \033[37mdownload-symbols\033[0m  - Download required Business Central symbol packages\n"
	@printf "  \033[32m•\033[0m \033[37mbuild\033[0m             - Compile the AL project with analysis\n"
	@printf "  \033[32m•\033[0m \033[37mclean\033[0m             - Remove build artifacts\n"
	@printf "  \033[32m•\033[0m \033[37mshow-config\033[0m       - Display current configuration\n"
	@printf "  \033[32m•\033[0m \033[37mshow-analyzers\033[0m    - Show discovered analyzers\n"
	@printf "  \033[32m•\033[0m \033[37mhelp\033[0m              - Show this help message\n"
	@echo ""
	@printf "\033[36m⚙️  CONFIGURATION OPTIONS:\033[0m\n"
	@printf "  \033[37mWARN_AS_ERROR\033[0m=\033[33m$(WARN_AS_ERROR)\033[0m         Treat warnings as errors (/warnaserror+)\n"
	@printf "  \033[37mRULESET_PATH\033[0m=\033[33m$(RULESET_PATH)\033[0m   Optional ruleset file passed to ALC if present\n"
	@printf "  \033[37mAL_TOOL_VERSION\033[0m=\033[33m$(AL_TOOL_VERSION)\033[0m         Override compiler tool version when provisioning\n"
	@printf "  \033[37mALBT_SYMBOL_CACHE_ROOT\033[0m=\033[33m$(ALBT_SYMBOL_CACHE_ROOT)\033[0m  Override symbol cache root path\n"
	@printf "  \033[37mALBT_SYMBOL_FEEDS\033[0m=\033[33m$(ALBT_SYMBOL_FEEDS)\033[0m      Comma-separated feeds for symbol provisioning\n"
	@printf "  \033[37mLINTERCOP_FORCE\033[0m=\033[33m$(LINTERCOP_FORCE)\033[0m         Force re-download of BusinessCentral.LinterCop analyzer (1=yes)\n"
	@echo ""
	@printf "\033[36m🚀 GETTING STARTED:\033[0m\n"
	@printf "  \033[32m✓\033[0m Run provisioning targets before '\033[37mmake build\033[0m' when setting up a new environment\n"
	@printf "  \033[32m✓\033[0m Typical workflow: \033[37mmake download-compiler && make download-symbols && make build\033[0m\n"
	@echo ""

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
