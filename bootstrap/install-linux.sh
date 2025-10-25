#!/usr/bin/env bash
#requires bash 4.0+
# AL Build Tools Bootstrap Installer for Linux
# Purpose: Download and install AL Build Tools overlay on Ubuntu Linux systems
# License: MIT

set -euo pipefail

# ============================================================================
# Exit Code Constants (T005)
# ============================================================================

readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL=1
readonly EXIT_GUARD=2
readonly EXIT_MISSING_TOOL=6

# ============================================================================
# Diagnostic Marker Functions (T004)
# ============================================================================

# Write diagnostic marker in standard format: [install] <type> key="value"
write_marker() {
    local marker_type="$1"
    shift
    local output="[install] ${marker_type}"

    # Append key="value" pairs
    while [[ $# -gt 0 ]]; do
        output="${output} $1"
        shift
    done

    echo "${output}"
}

# Write step marker with index and name
write_step() {
    local index="$1"
    local name="$2"
    write_marker "step" "index=\"${index}\"" "name=\"${name}\""
}

# Write prerequisite marker with tool, status, and optional version
write_prerequisite() {
    local tool="$1"
    local status="$2"
    local version="${3:-}"

    if [[ -n "${version}" ]]; then
        write_marker "prerequisite" "tool=\"${tool}\"" "status=\"${status}\"" "version=\"${version}\""
    else
        write_marker "prerequisite" "tool=\"${tool}\"" "status=\"${status}\""
    fi
}

# Write phase marker with name and optional duration
write_phase() {
    local phase_name="$1"
    local phase_event="$2"  # "start" or "end"
    local duration="${3:-}"

    if [[ "${phase_event}" == "start" ]]; then
        write_marker "phase" "name=\"${phase_name}\"" "event=\"start\""
    elif [[ "${phase_event}" == "end" && -n "${duration}" ]]; then
        write_marker "phase" "name=\"${phase_name}\"" "event=\"end\"" "duration=\"${duration}\""
    else
        write_marker "phase" "name=\"${phase_name}\"" "event=\"${phase_event}\""
    fi
}

# Write guard violation marker
write_guard() {
    local category="$1"
    local message="$2"
    write_marker "guard" "category=\"${category}\"" "message=\"${message}\""
}

# Write general diagnostic marker
write_diagnostic() {
    local level="$1"
    local message="$2"
    write_marker "diagnostic" "level=\"${level}\"" "message=\"${message}\""
}

# ============================================================================
# Bash Version Validation (T009)
# ============================================================================

# Check if bash version is 4.0 or higher
check_bash_version() {
    local major_version="${BASH_VERSINFO[0]}"

    if [[ "${major_version}" -lt 4 ]]; then
        echo "ERROR: Bash 4.0 or higher is required. Current version: ${BASH_VERSION}" >&2
        write_diagnostic "error" "Bash version check failed: ${BASH_VERSION} (requires 4.0+)"
        exit "${EXIT_MISSING_TOOL}"
    fi

    write_diagnostic "info" "Bash version check passed: ${BASH_VERSION}"
}

# ============================================================================
# Parameter Parsing (T006)
# ============================================================================

# Default parameter values
URL="${ALBT_URL:-https://api.github.com/repos/FBakkensen/al-build-tools/releases}"
REF="${ALBT_RELEASE:-latest}"
DESTINATION_PATH="${ALBT_DESTINATION_PATH:-.}"
SOURCE="${ALBT_SOURCE:-github}"

# Display usage information
usage() {
    cat <<EOF
AL Build Tools Bootstrap Installer for Linux

Usage: $(basename "$0") [OPTIONS]

Options:
  -Url <url>              GitHub API URL for releases (default: official repo)
  -Ref <tag>              Release tag to install (default: latest)
  -DestinationPath <path> Installation directory (default: current directory)
  -Source <source>        Installation source (default: github)
  -h, --help              Show this help message

Environment Variables:
  ALBT_URL                Override default GitHub API URL
  ALBT_RELEASE            Override default release (latest)
  ALBT_DESTINATION_PATH   Override default destination path
  ALBT_SOURCE             Override default source
  ALBT_AUTO_INSTALL       Set to 1 to auto-install prerequisites without prompts
  VERBOSE                 Set to 1 for detailed logging

Examples:
  # Install latest release to current directory
  bash install-linux.sh

  # Install specific release to custom path
  bash install-linux.sh -Ref v1.2.3 -DestinationPath /opt/al-build-tools

  # Auto-install mode (CI-friendly)
  ALBT_AUTO_INSTALL=1 bash install-linux.sh

EOF
}

# Parse command-line arguments (T006, T008)
parse_arguments() {
    local unknown_params=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -Url)
                URL="$2"
                shift 2
                ;;
            -Ref)
                REF="$2"
                shift 2
                ;;
            -DestinationPath)
                DESTINATION_PATH="$2"
                shift 2
                ;;
            -Source)
                SOURCE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit "${EXIT_SUCCESS}"
                ;;
            *)
                unknown_params+=("$1")
                shift
                ;;
        esac
    done

    # Check for unknown parameters (T008)
    if [[ ${#unknown_params[@]} -gt 0 ]]; then
        echo "ERROR: Unknown parameter(s): ${unknown_params[*]}" >&2
        echo "" >&2
        write_guard "unknown-parameter" "Unknown parameter(s): ${unknown_params[*]}"
        usage
        exit "${EXIT_GUARD}"
    fi
}

# ============================================================================
# Git Repository Guard Checks (T007)
# ============================================================================

# Check if current directory is a git repository
is_git_repo() {
    if git rev-parse --git-dir >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Check if git working tree is clean (no uncommitted changes)
is_working_tree_clean() {
    if ! is_git_repo; then
        return 1
    fi

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        return 1
    fi

    # Check for untracked files that would be affected
    local untracked_count
    untracked_count=$(git ls-files --others --exclude-standard overlay/ 2>/dev/null | wc -l)

    if [[ "${untracked_count}" -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Validate git repository state (guard check)
validate_git_state() {
    if ! is_git_repo; then
        echo "ERROR: Current directory is not a git repository" >&2
        echo "AL Build Tools must be installed in a git repository" >&2
        write_guard "not-git-repo" "Installation requires git repository"
        exit "${EXIT_GUARD}"
    fi

    if ! is_working_tree_clean; then
        echo "ERROR: Git working tree has uncommitted changes" >&2
        echo "Please commit or stash your changes before installing" >&2
        write_guard "dirty-working-tree" "Git working tree must be clean"
        exit "${EXIT_GUARD}"
    fi

    write_diagnostic "info" "Git repository state validated"
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    # Validate bash version first (T009)
    check_bash_version

    # Parse command-line arguments (T006, T008)
    parse_arguments "$@"

    # Validate git repository state (T007)
    validate_git_state

    echo "AL Build Tools Installation for Linux"
    echo "======================================"
    echo ""
    echo "Configuration:"
    echo "  Release: ${REF}"
    echo "  Destination: ${DESTINATION_PATH}"
    echo "  Source: ${SOURCE}"
    echo ""

    # TODO: T010-T026 - Implement main installer orchestration
    write_diagnostic "info" "Phase 2 foundation complete - main installer logic pending"

    exit "${EXIT_SUCCESS}"
}

# Execute main function with all arguments
main "$@"
