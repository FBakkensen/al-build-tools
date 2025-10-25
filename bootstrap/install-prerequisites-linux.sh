#!/usr/bin/env bash
#requires bash 4.0+
# AL Build Tools Prerequisites Installer for Linux
# Purpose: Install prerequisites (Git, PowerShell 7, .NET SDK 8.0, InvokeBuild) on Ubuntu Linux
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

# Write prerequisite marker with tool, status, and optional version
write_prerequisite() {
    local tool="$1"
    local status="$2"
    local version="${3:-}"
    local sudo_cached="${4:-}"

    local args=("tool=\"${tool}\"" "status=\"${status}\"")

    if [[ -n "${version}" ]]; then
        args+=("version=\"${version}\"")
    fi

    if [[ -n "${sudo_cached}" ]]; then
        args+=("sudoCached=\"${sudo_cached}\"")
    fi

    write_marker "prerequisite" "${args[@]}"
}

# Write general diagnostic marker
write_diagnostic() {
    local level="$1"
    local message="$2"
    write_marker "diagnostic" "level=\"${level}\"" "message=\"${message}\""
}

# Write step marker with index and name
write_step() {
    local index="$1"
    local name="$2"
    write_marker "step" "index=\"${index}\"" "name=\"${name}\""
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
# Environment Configuration
# ============================================================================

# Auto-install mode (set ALBT_AUTO_INSTALL=1 to skip prompts)
AUTO_INSTALL="${ALBT_AUTO_INSTALL:-0}"

# Microsoft repository configuration
readonly MICROSOFT_REPO_URL="https://packages.microsoft.com/config/ubuntu"
readonly UBUNTU_VERSION="22.04"
readonly MICROSOFT_PACKAGES_DEB="packages-microsoft-prod.deb"

# Retry configuration for apt locks
readonly APT_LOCK_MAX_RETRIES=3
readonly APT_LOCK_RETRY_DELAYS=(5 10 20)  # exponential backoff in seconds

# ============================================================================
# Prerequisite Detection Functions (T010)
# ============================================================================

# Check if git is installed and get version
check_git() {
    if command -v git >/dev/null 2>&1; then
        local version
        version=$(git --version 2>/dev/null | grep -oP 'git version \K[0-9.]+' || echo "unknown")
        echo "${version}"
        return 0
    else
        return 1
    fi
}

# Check if PowerShell 7 is installed and get version
check_powershell() {
    if command -v pwsh >/dev/null 2>&1; then
        local version
        version=$(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || echo "unknown")
        echo "${version}"
        return 0
    else
        return 1
    fi
}

# Check if .NET SDK 8.0 is installed and get version
check_dotnet() {
    if command -v dotnet >/dev/null 2>&1; then
        local version
        # Get the SDK version (not runtime version)
        version=$(dotnet --list-sdks 2>/dev/null | grep -oP '^8\.[0-9.]+' | head -n1 || echo "")
        if [[ -n "${version}" ]]; then
            echo "${version}"
            return 0
        else
            # .NET is installed but not SDK 8.0
            return 1
        fi
    else
        return 1
    fi
}

# Check if InvokeBuild PowerShell module is installed
check_invokebuild() {
    if command -v pwsh >/dev/null 2>&1; then
        local version
        version=$(pwsh -NoProfile -Command "Get-Module -ListAvailable InvokeBuild | Select-Object -First 1 -ExpandProperty Version | ForEach-Object { \$_.ToString() }" 2>/dev/null || echo "")
        if [[ -n "${version}" ]]; then
            echo "${version}"
            return 0
        else
            return 1
        fi
    else
        # PowerShell not installed, so InvokeBuild can't be checked
        return 1
    fi
}

# ============================================================================
# Sudo Session Validation (T011)
# ============================================================================

# Check if sudo session is cached (can run sudo without password prompt)
check_sudo_session() {
    if sudo -n true 2>/dev/null; then
        write_diagnostic "info" "Sudo session is cached"
        return 0
    else
        write_diagnostic "error" "Sudo session is not cached - run 'sudo -v' before installer"
        return 1
    fi
}

# ============================================================================
# Apt Lock Retry Logic (T012)
# ============================================================================

# Wait for apt lock to be released with exponential backoff
wait_for_apt_lock() {
    local attempt=1

    while [[ ${attempt} -le ${APT_LOCK_MAX_RETRIES} ]]; do
        # Check if apt lock files exist
        if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
           ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1 && \
           ! fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
            # No locks detected
            return 0
        fi

        local delay=${APT_LOCK_RETRY_DELAYS[$((attempt - 1))]}
        write_prerequisite "sudo" "retry" "" ""
        write_diagnostic "warning" "Apt is locked by another process (attempt ${attempt}/${APT_LOCK_MAX_RETRIES}), waiting ${delay}s..."
        echo "Waiting for apt lock to be released (${delay} seconds)..."
        sleep "${delay}"

        attempt=$((attempt + 1))
    done

    # All retries exhausted
    write_diagnostic "error" "Apt lock timeout after ${APT_LOCK_MAX_RETRIES} attempts"
    return 1
}

# Run apt command with lock retry logic
run_apt_with_retry() {
    local max_attempts=3
    local attempt=1

    while [[ ${attempt} -le ${max_attempts} ]]; do
        if wait_for_apt_lock; then
            # Run the apt command
            if "$@"; then
                return 0
            else
                local exit_code=$?
                write_diagnostic "error" "Apt command failed with exit code ${exit_code}"
                return ${exit_code}
            fi
        fi

        attempt=$((attempt + 1))
    done

    return 1
}

# ============================================================================
# Microsoft Repository Setup (T013)
# ============================================================================

# Install Microsoft package repository
setup_microsoft_repository() {
    write_step "1" "Setting up Microsoft package repository"
    write_prerequisite "sudo" "installing" "" ""

    local temp_dir
    temp_dir=$(mktemp -d)
    local deb_file="${temp_dir}/${MICROSOFT_PACKAGES_DEB}"

    # Download Microsoft packages configuration
    local repo_url="${MICROSOFT_REPO_URL}/${UBUNTU_VERSION}/${MICROSOFT_PACKAGES_DEB}"
    echo "Downloading Microsoft repository configuration..."
    write_diagnostic "info" "Downloading from ${repo_url}"

    if ! curl -fsSL -o "${deb_file}" "${repo_url}"; then
        rm -rf "${temp_dir}"
        write_diagnostic "error" "Failed to download Microsoft repository configuration"
        return 1
    fi

    # Install the package
    echo "Installing Microsoft repository configuration..."
    if ! sudo dpkg -i "${deb_file}" >/dev/null 2>&1; then
        rm -rf "${temp_dir}"
        write_diagnostic "error" "Failed to install Microsoft repository configuration"
        return 1
    fi

    rm -rf "${temp_dir}"
    write_prerequisite "sudo" "installed" "" "true"
    return 0
}

# ============================================================================
# Apt Cache Update (T014)
# ============================================================================

# Update apt package cache
update_apt_cache() {
    write_step "2" "Updating package cache"
    echo "Updating package cache (this may take a moment)..."

    if ! run_apt_with_retry sudo apt-get update -qq; then
        write_diagnostic "error" "Failed to update apt cache"
        return 1
    fi

    write_diagnostic "info" "Package cache updated successfully"
    return 0
}

# ============================================================================
# Tool Installation Functions (T015-T018)
# ============================================================================

# Install git via apt (T015)
install_git() {
    write_prerequisite "git" "installing" "" ""
    echo "Installing Git..."

    if ! run_apt_with_retry sudo apt-get install -y git; then
        write_prerequisite "git" "failed" "" ""
        return 1
    fi

    local version
    version=$(check_git)
    write_prerequisite "git" "installed" "${version}" ""
    return 0
}

# Install PowerShell 7 via apt (T016)
install_powershell() {
    write_prerequisite "powershell" "installing" "" ""
    echo "Installing PowerShell 7..."

    if ! run_apt_with_retry sudo apt-get install -y powershell; then
        write_prerequisite "powershell" "failed" "" ""
        return 1
    fi

    local version
    version=$(check_powershell)
    write_prerequisite "powershell" "installed" "${version}" ""
    return 0
}

# Install .NET SDK 8.0 via apt (T017)
install_dotnet() {
    write_prerequisite "dotnet" "installing" "" ""
    echo "Installing .NET SDK 8.0..."

    if ! run_apt_with_retry sudo apt-get install -y dotnet-sdk-8.0; then
        write_prerequisite "dotnet" "failed" "" ""
        return 1
    fi

    local version
    version=$(check_dotnet)
    write_prerequisite "dotnet" "installed" "${version}" ""
    return 0
}

# Install InvokeBuild module via PowerShell (T018)
install_invokebuild() {
    write_prerequisite "InvokeBuild" "installing" "" ""
    echo "Installing InvokeBuild module..."

    # Run PowerShell command and capture output
    local output
    if output=$(pwsh -NoProfile -Command "Install-Module InvokeBuild -Scope CurrentUser -Force -ErrorAction Stop" 2>&1); then
        local version
        version=$(check_invokebuild)
        write_prerequisite "InvokeBuild" "installed" "${version}" ""
        return 0
    else
        echo "Installation output: ${output}" >&2
        write_prerequisite "InvokeBuild" "failed" "" ""
        return 1
    fi
}

# ============================================================================
# Interactive Prompt Functions (T027 - Phase 4 - US2)
# ============================================================================

# Read and validate user input with retry logic (FR-019)
# Arguments:
#   $1: Prompt message
#   $2: Valid inputs (space-separated, e.g., "Y y N n")
#   $3: Example of valid input (e.g., "Y/n")
# Returns:
#   0 if valid input provided (echoes normalized response to stdout)
#   1 if invalid input after retry
read_user_input() {
    local prompt="$1"
    local valid_inputs="$2"
    local example="$3"
    local max_attempts=2
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        echo -n "${prompt}"
        local response
        read -r response
        
        # Normalize to uppercase for comparison
        local normalized
        normalized=$(echo "${response}" | tr '[:lower:]' '[:upper:]')
        
        # Check if response is valid
        if [[ " ${valid_inputs} " == *" ${normalized} "* ]]; then
            echo "${normalized}"
            return 0
        fi
        
        # Invalid input handling
        if [[ ${attempt} -lt ${max_attempts} ]]; then
            write_marker "input" "status=\"invalid\"" "example=\"${example}\""
            echo "Invalid input '${response}'. Valid options: ${example}" >&2
            echo "Retrying in 2 seconds..." >&2
            sleep 2
        else
            write_marker "input" "status=\"failed\"" "attempts=\"${max_attempts}\""
            echo "ERROR: Invalid input '${response}' after ${max_attempts} attempts. Expected: ${example}" >&2
            return 1
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Prompt user for installation approval with tool details
# Arguments:
#   $1: Tool name (e.g., "Git", "PowerShell 7")
#   $2: Tool purpose/description
# Returns:
#   0 if user approves (Y)
#   1 if user declines (N) or invalid input after retry
prompt_for_installation() {
    local tool_name="$1"
    local tool_purpose="$2"

    echo ""
    echo "==================================="
    echo "Prerequisite Installation Required"
    echo "==================================="
    echo ""
    echo "Tool: ${tool_name}"
    echo "Purpose: ${tool_purpose}"
    echo ""
    
    # Use read_user_input with validation
    local response
    if response=$(read_user_input "Install ${tool_name}? [Y/n]: " "Y YES N NO " "Y/n"); then
        # Valid response received
        if [[ "${response}" == "Y" || "${response}" == "YES" || "${response}" == "" ]]; then
            return 0
        else
            return 1
        fi
    else
        # Invalid input after retry
        return 1
    fi
}

# ============================================================================
# Prerequisite Orchestration (T019)
# ============================================================================

# Main prerequisite orchestration function
orchestrate_prerequisites() {
    local needs_microsoft_repo=false
    local needs_apt_update=false
    local missing_tools=()

    # Validate sudo session first (T011)
    write_prerequisite "sudo" "check" "" ""
    if ! check_sudo_session; then
        echo ""
        echo "ERROR: Sudo session is not cached" >&2
        echo "Please run 'sudo -v' to cache your sudo credentials before running the installer" >&2
        echo ""
        write_diagnostic "error" "Sudo session validation failed"
        exit "${EXIT_MISSING_TOOL}"
    fi
    write_prerequisite "sudo" "found" "" "true"

    echo "Checking prerequisites..."
    echo ""

    # Detect all prerequisites (T010)
    local git_version dotnet_version pwsh_version ib_version

    write_prerequisite "git" "check" "" ""
    if git_version=$(check_git); then
        write_prerequisite "git" "found" "${git_version}" ""
        echo "[✓] Git: ${git_version}"
    else
        write_prerequisite "git" "missing" "" ""
        echo "[✗] Git: Not installed"
        missing_tools+=("git")
    fi

    write_prerequisite "powershell" "check" "" ""
    if pwsh_version=$(check_powershell); then
        write_prerequisite "powershell" "found" "${pwsh_version}" ""
        echo "[✓] PowerShell 7: ${pwsh_version}"
    else
        write_prerequisite "powershell" "missing" "" ""
        echo "[✗] PowerShell 7: Not installed"
        missing_tools+=("powershell")
        needs_microsoft_repo=true
    fi

    write_prerequisite "dotnet" "check" "" ""
    if dotnet_version=$(check_dotnet); then
        write_prerequisite "dotnet" "found" "${dotnet_version}" ""
        echo "[✓] .NET SDK 8.0: ${dotnet_version}"
    else
        write_prerequisite "dotnet" "missing" "" ""
        echo "[✗] .NET SDK 8.0: Not installed"
        missing_tools+=("dotnet")
        needs_microsoft_repo=true
    fi

    write_prerequisite "InvokeBuild" "check" "" ""
    if ib_version=$(check_invokebuild); then
        write_prerequisite "InvokeBuild" "found" "${ib_version}" ""
        echo "[✓] InvokeBuild: ${ib_version}"
    else
        write_prerequisite "InvokeBuild" "missing" "" ""
        echo "[✗] InvokeBuild: Not installed"
        missing_tools+=("InvokeBuild")
    fi

    echo ""

    # If all prerequisites are met, exit early
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        write_diagnostic "info" "All prerequisites already installed"
        echo "All prerequisites are already installed!"
        return 0
    fi

    # Check if auto-install mode is enabled (T028 - Phase 4 - US2)
    if [[ "${AUTO_INSTALL}" != "1" ]]; then
        echo "Missing prerequisites detected. Interactive installation mode."
        echo ""
        
        # Interactive mode - prompt for each missing tool (T028, T030)
        local tools_to_install=()
        
        for tool in "${missing_tools[@]}"; do
            local tool_name=""
            local tool_purpose=""
            
            # Define tool descriptions (T030)
            case "${tool}" in
                git)
                    tool_name="Git"
                    tool_purpose="Version control system required for managing AL Build Tools overlay files and repository operations"
                    ;;
                powershell)
                    tool_name="PowerShell 7"
                    tool_purpose="Cross-platform shell and scripting framework required to run AL Build Tools overlay scripts and build orchestration"
                    ;;
                dotnet)
                    tool_name=".NET SDK 8.0"
                    tool_purpose="Microsoft .NET development kit required for AL compiler (microsoft.dynamics.businesscentral.development.tools) and build tools"
                    ;;
                InvokeBuild)
                    tool_name="InvokeBuild"
                    tool_purpose="PowerShell build automation module required for AL Build Tools task orchestration (Invoke-Build command)"
                    ;;
            esac
            
            # Prompt user for approval (T028)
            if prompt_for_installation "${tool_name}" "${tool_purpose}"; then
                write_diagnostic "info" "User approved installation of ${tool_name}"
                tools_to_install+=("${tool}")
            else
                # User declined installation (T029)
                echo ""
                echo "Installation declined for ${tool_name}."
                write_diagnostic "warning" "User declined installation of ${tool_name}"
                write_prerequisite "${tool}" "declined" "" ""
                
                # Exit gracefully with clear message (T029)
                echo ""
                echo "====================================="
                echo "Installation Cannot Proceed"
                echo "====================================="
                echo ""
                echo "AL Build Tools requires ${tool_name} to function."
                echo ""
                echo "To install manually, please run:"
                case "${tool}" in
                    git)
                        echo "  sudo apt-get update && sudo apt-get install -y git"
                        ;;
                    powershell)
                        echo "  # Install Microsoft repository"
                        echo "  wget -q ${MICROSOFT_REPO_URL}/${UBUNTU_VERSION}/${MICROSOFT_PACKAGES_DEB}"
                        echo "  sudo dpkg -i ${MICROSOFT_PACKAGES_DEB}"
                        echo "  sudo apt-get update"
                        echo "  sudo apt-get install -y powershell"
                        ;;
                    dotnet)
                        echo "  # Install Microsoft repository"
                        echo "  wget -q ${MICROSOFT_REPO_URL}/${UBUNTU_VERSION}/${MICROSOFT_PACKAGES_DEB}"
                        echo "  sudo dpkg -i ${MICROSOFT_PACKAGES_DEB}"
                        echo "  sudo apt-get update"
                        echo "  sudo apt-get install -y dotnet-sdk-8.0"
                        ;;
                    InvokeBuild)
                        echo "  pwsh -Command 'Install-Module InvokeBuild -Scope CurrentUser -Force'"
                        ;;
                esac
                echo ""
                echo "Then re-run the installer."
                echo ""
                
                exit "${EXIT_MISSING_TOOL}"
            fi
        done
        
        # Update missing_tools to only include approved tools
        missing_tools=("${tools_to_install[@]}")
        
        # If user declined all tools, exit
        if [[ ${#missing_tools[@]} -eq 0 ]]; then
            write_diagnostic "error" "No prerequisites approved for installation"
            exit "${EXIT_MISSING_TOOL}"
        fi
        
        echo ""
        echo "Proceeding with installation of approved tools..."
        echo ""
        
        # Recalculate if Microsoft repo is needed
        needs_microsoft_repo=false
        for tool in "${missing_tools[@]}"; do
            if [[ "${tool}" == "powershell" || "${tool}" == "dotnet" ]]; then
                needs_microsoft_repo=true
                break
            fi
        done
    else
        # Auto-install mode
        echo "Installing missing prerequisites (auto-install mode)..."
        echo ""
    fi

    # Setup Microsoft repository if needed (T013, T014)
    if [[ "${needs_microsoft_repo}" == true ]]; then
        if ! setup_microsoft_repository; then
            write_diagnostic "error" "Failed to setup Microsoft repository"
            exit "${EXIT_GENERAL}"
        fi
        needs_apt_update=true
    fi

    # Update apt cache if needed
    if [[ "${needs_apt_update}" == true ]]; then
        if ! update_apt_cache; then
            write_diagnostic "error" "Failed to update apt cache"
            exit "${EXIT_GENERAL}"
        fi
    fi

    # Install missing tools (T015-T018)
    for tool in "${missing_tools[@]}"; do
        case "${tool}" in
            git)
                if ! install_git; then
                    write_diagnostic "error" "Failed to install Git"
                    exit "${EXIT_GENERAL}"
                fi
                ;;
            powershell)
                if ! install_powershell; then
                    write_diagnostic "error" "Failed to install PowerShell 7"
                    exit "${EXIT_GENERAL}"
                fi
                ;;
            dotnet)
                if ! install_dotnet; then
                    write_diagnostic "error" "Failed to install .NET SDK 8.0"
                    exit "${EXIT_GENERAL}"
                fi
                ;;
            InvokeBuild)
                # InvokeBuild requires PowerShell, so ensure it's installed first
                if ! command -v pwsh >/dev/null 2>&1; then
                    write_diagnostic "error" "Cannot install InvokeBuild: PowerShell not available"
                    exit "${EXIT_GENERAL}"
                fi
                if ! install_invokebuild; then
                    write_diagnostic "error" "Failed to install InvokeBuild module"
                    exit "${EXIT_GENERAL}"
                fi
                ;;
        esac
    done

    echo ""
    echo "All prerequisites installed successfully!"
    write_diagnostic "info" "Prerequisite installation completed"
    return 0
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    # Validate bash version first (T009)
    check_bash_version

    echo "AL Build Tools Prerequisites Installer for Linux"
    echo "================================================="
    echo ""

    # Run prerequisite orchestration (T019)
    orchestrate_prerequisites

    exit "${EXIT_SUCCESS}"
}

# Execute main function with all arguments
main "$@"