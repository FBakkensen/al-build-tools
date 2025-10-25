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
# Phase Timing Functions (T026)
# ============================================================================

declare -A PHASE_START_TIMES

# Mark the start of an execution phase
phase_start() {
    local phase_name="$1"
    PHASE_START_TIMES["${phase_name}"]=$(date +%s)
    write_phase "${phase_name}" "start"
}

# Mark the end of an execution phase
phase_end() {
    local phase_name="$1"
    local start_time="${PHASE_START_TIMES[${phase_name}]}"
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    write_phase "${phase_name}" "end" "${duration}s"
}

# ============================================================================
# GitHub Release Resolution (T020)
# ============================================================================

# Query GitHub API and resolve release tag
resolve_github_release() {
    local api_url="$1"
    local ref="$2"

    phase_start "release-resolution"
    write_step "1" "Resolving release information"

    if [[ "${ref}" == "latest" ]]; then
        echo "Querying GitHub API for latest release..."
        local release_url="${api_url}/latest"
    else
        echo "Querying GitHub API for release tag: ${ref}..."
        local release_url="${api_url}/tags/${ref}"
    fi

    write_diagnostic "info" "Querying ${release_url}"

    # Query GitHub API with timeout
    local response
    if ! response=$(curl -fsSL --max-time 30 "${release_url}" 2>&1); then
        write_diagnostic "error" "Failed to query GitHub API: ${response}"
        phase_end "release-resolution"
        return 1
    fi

    # Parse release tag from JSON response
    local release_tag
    release_tag=$(echo "${response}" | grep -oP '"tag_name":\s*"\K[^"]+' | head -n1)

    if [[ -z "${release_tag}" ]]; then
        write_diagnostic "error" "Failed to parse release tag from API response"
        phase_end "release-resolution"
        return 1
    fi

    # Parse download URL for overlay.zip asset (with fallback to al-build-tools-*.zip)
    local download_url
    download_url=$(echo "${response}" | grep -oP '"browser_download_url":\s*"\K[^"]+overlay\.zip' | head -n1)

    # Fallback to al-build-tools-*.zip if overlay.zip not found
    if [[ -z "${download_url}" ]]; then
        download_url=$(echo "${response}" | grep -oP '"browser_download_url":\s*"\K[^"]+al-build-tools-[^"]+\.zip' | head -n1)
        if [[ -n "${download_url}" ]]; then
            write_diagnostic "info" "Using fallback asset: $(basename "${download_url}")"
        fi
    fi

    if [[ -z "${download_url}" ]]; then
        write_diagnostic "error" "Failed to find overlay.zip or al-build-tools-*.zip asset in release ${release_tag}"
        phase_end "release-resolution"
        return 1
    fi

    echo "Resolved release: ${release_tag}"
    write_diagnostic "info" "Release tag: ${release_tag}"
    write_diagnostic "info" "Download URL: ${download_url}"

    # Export for use by other functions
    RESOLVED_RELEASE_TAG="${release_tag}"
    RESOLVED_DOWNLOAD_URL="${download_url}"

    phase_end "release-resolution"
    return 0
}

# ============================================================================
# Overlay Download (T021)
# ============================================================================

# Download overlay archive from GitHub
download_overlay() {
    local download_url="$1"
    local temp_dir="$2"

    phase_start "overlay-download"
    write_step "2" "Downloading overlay archive"

    local archive_path="${temp_dir}/overlay.zip"

    echo "Downloading overlay archive..."
    write_diagnostic "info" "Downloading from ${download_url}"

    # Download with curl with timeout and progress
    if ! curl -fsSL --max-time 300 -o "${archive_path}" "${download_url}" 2>&1; then
        write_diagnostic "error" "Failed to download overlay archive"
        phase_end "overlay-download"
        return 1
    fi

    # Verify file was downloaded
    if [[ ! -f "${archive_path}" ]]; then
        write_diagnostic "error" "Archive file not found after download"
        phase_end "overlay-download"
        return 1
    fi

    local file_size
    file_size=$(stat -c%s "${archive_path}" 2>/dev/null || stat -f%z "${archive_path}" 2>/dev/null)

    echo "Download complete (${file_size} bytes)"
    write_diagnostic "info" "Archive downloaded: ${file_size} bytes"

    # Export for use by other functions
    OVERLAY_ARCHIVE_PATH="${archive_path}"

    phase_end "overlay-download"
    return 0
}

# ============================================================================
# Overlay Extraction (T022)
# ============================================================================

# Extract overlay archive and detect corruption
extract_overlay() {
    local archive_path="$1"
    local temp_dir="$2"

    write_step "3" "Extracting overlay archive"

    local extract_dir="${temp_dir}/overlay"
    mkdir -p "${extract_dir}"

    echo "Extracting overlay archive..."
    write_diagnostic "info" "Extracting to ${extract_dir}"

    # Extract with unzip
    if ! unzip -q -o "${archive_path}" -d "${extract_dir}" 2>&1; then
        write_diagnostic "error" "Failed to extract overlay archive (possibly corrupt)"
        return 1
    fi

    # Verify extraction succeeded (check for expected files)
    if [[ ! -d "${extract_dir}/overlay" ]]; then
        write_diagnostic "error" "Overlay directory not found after extraction (corrupt archive)"
        return 1
    fi

    echo "Extraction complete"
    write_diagnostic "info" "Overlay extracted successfully"

    # Export for use by other functions
    OVERLAY_EXTRACT_DIR="${extract_dir}/overlay"

    return 0
}

# ============================================================================
# File Copy (T023)
# ============================================================================

# Copy overlay files to destination
copy_overlay_files() {
    local source_dir="$1"
    local dest_path="$2"

    phase_start "file-copy"
    write_step "4" "Copying overlay files"

    local dest_overlay="${dest_path}/overlay"

    echo "Copying overlay files to ${dest_overlay}..."
    write_diagnostic "info" "Source: ${source_dir}"
    write_diagnostic "info" "Destination: ${dest_overlay}"

    # Create destination directory if needed
    mkdir -p "${dest_overlay}"

    # Copy files recursively
    if ! cp -r "${source_dir}"/* "${dest_overlay}/" 2>&1; then
        write_diagnostic "error" "Failed to copy overlay files"
        phase_end "file-copy"
        return 1
    fi

    # Count copied files
    local file_count
    file_count=$(find "${dest_overlay}" -type f | wc -l)

    echo "Copy complete (${file_count} files)"
    write_diagnostic "info" "Copied ${file_count} files"

    phase_end "file-copy"
    return 0
}

# ============================================================================
# Git Commit (T024)
# ============================================================================

# Create git commit with overlay files
create_git_commit() {
    local dest_path="$1"
    local release_tag="$2"

    phase_start "git-commit"
    write_step "5" "Creating git commit"

    echo "Creating git commit..."

    # Change to destination directory
    cd "${dest_path}" || return 1

    # Check if this is initial commit
    local is_initial_commit=false
    if ! git rev-parse HEAD >/dev/null 2>&1; then
        is_initial_commit=true
        write_diagnostic "info" "Initial commit detected"
    fi

    # Stage overlay files
    if ! git add overlay/ 2>&1; then
        write_diagnostic "error" "Failed to stage overlay files"
        phase_end "git-commit"
        return 1
    fi

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        echo "No changes to commit (overlay already up-to-date)"
        write_diagnostic "info" "No changes to commit"
        phase_end "git-commit"
        return 0
    fi

    # Create commit
    local commit_message
    if [[ "${is_initial_commit}" == true ]]; then
        commit_message="chore: initialize AL Build Tools (${release_tag})"
    else
        commit_message="chore: update AL Build Tools overlay (${release_tag})"
    fi

    if ! git commit -m "${commit_message}" >/dev/null 2>&1; then
        write_diagnostic "error" "Failed to create git commit"
        phase_end "git-commit"
        return 1
    fi

    local commit_hash
    commit_hash=$(git rev-parse --short HEAD)

    echo "Commit created: ${commit_hash}"
    write_diagnostic "info" "Commit hash: ${commit_hash}"

    phase_end "git-commit"
    return 0
}

# ============================================================================
# Main Installer Orchestration (T025)
# ============================================================================

orchestrate_installation() {
    local url="$1"
    local ref="$2"
    local dest_path="$3"

    # Create temporary directory for download
    local temp_dir
    temp_dir=$(mktemp -d)

    # Ensure cleanup on exit (use subshell to avoid unbound variable issues)
    trap 'if [[ -n "${temp_dir:-}" ]]; then rm -rf "${temp_dir}"; fi' EXIT

    # Step 1: Resolve GitHub release (T020)
    if ! resolve_github_release "${url}" "${ref}"; then
        echo ""
        echo "ERROR: Failed to resolve GitHub release" >&2
        return "${EXIT_GENERAL}"
    fi

    # Step 2: Install prerequisites (calls install-prerequisites-linux.sh)
    phase_start "prerequisite-installation"
    write_step "1.5" "Installing prerequisites"

    local prereq_script="${BASH_SOURCE[0]%/*}/install-prerequisites-linux.sh"
    if [[ ! -f "${prereq_script}" ]]; then
        write_diagnostic "error" "Prerequisites installer not found: ${prereq_script}"
        phase_end "prerequisite-installation"
        return "${EXIT_GENERAL}"
    fi

    echo ""
    echo "==================================="
    echo "Installing Prerequisites"
    echo "==================================="
    echo ""

    if ! bash "${prereq_script}"; then
        write_diagnostic "error" "Prerequisite installation failed"
        phase_end "prerequisite-installation"
        return "${EXIT_GENERAL}"
    fi

    phase_end "prerequisite-installation"

    echo ""
    echo "==================================="
    echo "Installing AL Build Tools"
    echo "==================================="
    echo ""

    # Step 3: Download overlay (T021)
    if ! download_overlay "${RESOLVED_DOWNLOAD_URL}" "${temp_dir}"; then
        echo ""
        echo "ERROR: Failed to download overlay archive" >&2
        return "${EXIT_GENERAL}"
    fi

    # Step 4: Extract overlay (T022)
    if ! extract_overlay "${OVERLAY_ARCHIVE_PATH}" "${temp_dir}"; then
        echo ""
        echo "ERROR: Failed to extract overlay archive" >&2
        return "${EXIT_GENERAL}"
    fi

    # Step 5: Copy files (T023)
    if ! copy_overlay_files "${OVERLAY_EXTRACT_DIR}" "${dest_path}"; then
        echo ""
        echo "ERROR: Failed to copy overlay files" >&2
        return "${EXIT_GENERAL}"
    fi

    # Step 6: Create git commit (T024)
    if ! create_git_commit "${dest_path}" "${RESOLVED_RELEASE_TAG}"; then
        echo ""
        echo "ERROR: Failed to create git commit" >&2
        return "${EXIT_GENERAL}"
    fi

    # Success!
    echo ""
    echo "==================================="
    echo "Installation Complete!"
    echo "==================================="
    echo ""
    echo "AL Build Tools ${RESOLVED_RELEASE_TAG} has been installed successfully."
    echo ""
    echo "Next steps:"
    echo "  1. Review the overlay/ directory"
    echo "  2. Run: pwsh -Command 'Invoke-Build' to build your AL project"
    echo "  3. See overlay/CLAUDE.md for available commands"
    echo ""

    write_diagnostic "info" "Installation completed successfully"

    return 0
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

    echo ""
    echo "========================================"
    echo "AL Build Tools Installation for Linux"
    echo "========================================"
    echo ""
    echo "Configuration:"
    echo "  Release: ${REF}"
    echo "  Destination: ${DESTINATION_PATH}"
    echo "  API URL: ${URL}"
    echo ""

    # Run main installer orchestration (T025, T026)
    if ! orchestrate_installation "${URL}" "${REF}" "${DESTINATION_PATH}"; then
        exit "${EXIT_GENERAL}"
    fi

    exit "${EXIT_SUCCESS}"
}

# Execute main function with all arguments
main "$@"