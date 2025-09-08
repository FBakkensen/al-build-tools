
# Unified Makefile for AL (Business Central) Project
# Cross-platform build system using platform-specific scripts

# =============================================================================
# App Directory Configuration
# =============================================================================
APP_DIR := app

# =============================================================================
# Build Options (tweak as needed)
# =============================================================================
# Treat AL compiler warnings as errors (1 to enable, 0 to disable)
WARN_AS_ERROR ?= 1
# Export so scripts inherit this setting on all platforms
export WARN_AS_ERROR

# =============================================================================
# Platform Detection
# =============================================================================
ifeq ($(OS),Windows_NT)
	PLATFORM := windows
	SCRIPT_EXT := .ps1
	SCRIPT_CMD := powershell -NoProfile -ExecutionPolicy Bypass -File
else
	PLATFORM := linux
	SCRIPT_EXT := .sh
	SCRIPT_CMD := bash
endif

# =============================================================================
# Targets
# =============================================================================
.PHONY: all build clean help show-config show-analyzers

# Default target
all: build

# Help target
help:
	@echo "AL Project Build System"
	@echo "======================="
	@echo ""
	@echo "Available targets:"
	@echo "  build         - Compile the AL project with analysis"
	@echo "  clean         - Remove build artifacts"
	@echo "  show-config   - Display current configuration"
	@echo "  show-analyzers - Show discovered analyzers"
	@echo "  help          - Show this help message"
	@echo ""
	@echo "Platform: $(PLATFORM)"
	@echo ""
	@echo "Options (set in Makefile):"
	@echo "  WARN_AS_ERROR=$(WARN_AS_ERROR)   Treat warnings as errors (/warnaserror+)"

# Build target - main compilation
build:
	$(SCRIPT_CMD) scripts/make/$(PLATFORM)/build$(SCRIPT_EXT) $(APP_DIR)

# Clean build artifacts
clean:
	$(SCRIPT_CMD) scripts/make/$(PLATFORM)/clean$(SCRIPT_EXT) $(APP_DIR)

# Show current configuration
show-config:
	$(SCRIPT_CMD) scripts/make/$(PLATFORM)/show-config$(SCRIPT_EXT) $(APP_DIR)

# Show discovered analyzers
show-analyzers:
	$(SCRIPT_CMD) scripts/make/$(PLATFORM)/show-analyzers$(SCRIPT_EXT) $(APP_DIR)
