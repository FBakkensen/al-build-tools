#!/bin/bash
set -e

# Business Central Symbol Restoration Script
#
# This script downloads Business Central symbols from Microsoft NuGet feeds using direct .nupkg download and extraction.
# Key behaviors:
# - Always uses REST API for efficient package discovery with flexible matching
#   * Directly queries Microsoft feeds using REST API (no authentication required)
#   * Always returns the most recent version available in the feed
#   * Supports exact matches, partial matches, and GUID-suffixed packages
#   * Filters out country-specific variants (e.g., Microsoft.Application.DK.symbols.{GUID})
#   * Downloads international/base versions only
#   * Downloads .nupkg files directly and extracts .app files to .alpackages folder
# - Supports both Microsoft and AppSource packages with unified discovery methods
# - No nuget.exe dependencies - uses curl for downloads and unzip for extraction
# - Always targets the most recent version for all dependencies (no version pinning)
#
# Key insight: .nupkg files are ZIP files containing .app files. We download them directly,
# extract the .app files to the .alpackages folder, and clean up the temporary files.
# No authentication is required for public Microsoft feeds.
#
# Usage: ./restore-symbols.sh <project-path>

# Check parameters
if [ $# -ne 1 ]; then
    echo "Usage: $0 <project-path>"
    exit 1
fi

PROJECT_PATH="$1"

echo "Restoring symbols for project: $PROJECT_PATH"

# Find app.json - could be in root or app subdirectory
if [ -f "$PROJECT_PATH/app.json" ]; then
    APP_JSON_PATH="$PROJECT_PATH/app.json"
    AL_PROJECT_DIR="$PROJECT_PATH"
elif [ -f "$PROJECT_PATH/app/app.json" ]; then
    APP_JSON_PATH="$PROJECT_PATH/app/app.json"
    AL_PROJECT_DIR="$PROJECT_PATH/app"
else
    echo "Error: app.json not found in $PROJECT_PATH or $PROJECT_PATH/app"
    exit 1
fi

echo "Using app.json from: $APP_JSON_PATH"
echo "AL project directory: $AL_PROJECT_DIR"

# Read BC version from app.json
BC_VERSION=$(jq -r '.application' "$APP_JSON_PATH")
BC_MAJOR_VERSION=$(echo "$BC_VERSION" | cut -d. -f1)
echo "BC Version: $BC_VERSION (Major: $BC_MAJOR_VERSION)"

# Create symbols directory
SYMBOLS_PATH="$AL_PROJECT_DIR/.alpackages"
mkdir -p "$SYMBOLS_PATH"

# Check required tools
if ! command -v curl &> /dev/null; then
    echo "Error: curl not found. This script requires curl to download .nupkg files."
    exit 1
fi

if ! command -v unzip &> /dev/null; then
    echo "Error: unzip not found. This script requires unzip to extract .app files from .nupkg files."
    exit 1
fi

echo "Using curl $(curl --version | head -1)"
echo "Using unzip $(unzip -v | head -1)"

# Check if jq is available for JSON parsing (optional but recommended)
if command -v jq &> /dev/null; then
    echo "Using jq $(jq --version) for JSON parsing"
else
    echo "Warning: jq not available, using basic text parsing (jq recommended for better reliability)"
fi

# Setup NuGet sources using dotnet CLI (more reliable than XML config)
# Direct .nupkg download and extraction approach
# No nuget.exe required - we'll download .nupkg files directly and extract .app files
echo "Setting up direct .nupkg download and extraction..."

# Function to download and extract .nupkg directly
download_and_extract_nupkg() {
    local package_name="$1"
    local version="$2"
    local source_name="$3"
    local source_url="$4"

    echo "📦 Downloading $package_name v$version from $source_name..."

    # Construct the download URL for the .nupkg file
    local download_url=""

    # Check if this is an Azure DevOps feed (contains visualstudio.com)
    if [[ "$source_url" =~ visualstudio\.com ]]; then
        # Extract organization and project from the URL
        # Example: https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v2
        # Should become: https://pkgs.dev.azure.com/dynamicssmb2/DynamicsBCPublicFeeds/_apis/packaging/feeds/MSSymbols/nuget/packages/{package}/versions/{version}/content?api-version=7.1-preview.1

        if [[ "$source_url" =~ https://([^.]+)\.pkgs\.visualstudio\.com/([^/]+)/_packaging/([^/]+)/nuget/v2 ]]; then
            local organization="${BASH_REMATCH[1]}"
            local project="${BASH_REMATCH[2]}"
            local feed_id="${BASH_REMATCH[3]}"

            # Use the Azure DevOps REST API format
            download_url="https://pkgs.dev.azure.com/${organization}/${project}/_apis/packaging/feeds/${feed_id}/nuget/packages/${package_name}/versions/${version}/content?api-version=7.1-preview.1"
        else
            # Fallback to the original format for non-matching URLs
            download_url="${source_url}/download/${package_name}/${version}/${package_name}.${version}.nupkg"
        fi
    else
        # For non-Azure DevOps feeds, use the standard NuGet format
        download_url="${source_url}/download/${package_name}/${version}/${package_name}.${version}.nupkg"
    fi

    local nupkg_file="/tmp/${package_name}.${version}.nupkg"

    # Download the .nupkg file
    echo "  🔗 Using URL: $download_url"
    if curl -s -f -L -o "$nupkg_file" "$download_url"; then
        echo "✅ Downloaded $package_name v$version"

        # Extract .app files from the .nupkg (which is just a ZIP file)
        local extract_dir="/tmp/extract_${package_name}_${version}"
        mkdir -p "$extract_dir"

        if unzip -q "$nupkg_file" -d "$extract_dir" 2>/dev/null; then
            # Find and copy .app files to the symbols directory
            find "$extract_dir" -name "*.app" -type f | while read -r app_file; do
                local app_filename=$(basename "$app_file")
                cp "$app_file" "$SYMBOLS_PATH/"
                echo "  ✅ Extracted: $app_filename"
            done

            # Clean up extraction directory
            rm -rf "$extract_dir"
            rm -f "$nupkg_file"
            return 0
        else
            echo "❌ Failed to extract $nupkg_file"
            rm -f "$nupkg_file"
            return 1
        fi
    else
        echo "❌ Failed to download $package_name v$version from $source_name"
        echo "  🔗 URL attempted: $download_url"
        return 1
    fi
}

# Function to find Microsoft packages with GUID using direct REST API
find_microsoft_package_with_guid_direct() {
    local base_name="$1"  # e.g., "Microsoft.BaseApplication.symbols"
    local major_version="$2"
    local source_name="$3"
    local api_url="$4"

    echo "🔍 Finding $base_name packages (exact match, partial match, or GUID suffix, no country codes) from $source_name..." >&2

    # Query the NuGet feed API directly
    local search_output="/tmp/rest_api_search_$(echo "$base_name" | tr '.' '_' | tr ' ' '_').txt"

    if timeout 60 curl -s "${api_url}?q=${base_name}&take=50" > "$search_output" 2>/dev/null; then
        # Extract package names using jq if available
        local matching_packages=""
        if command -v jq >/dev/null 2>&1; then
            matching_packages=$(jq -r '.data[]?.id // empty' "$search_output" 2>/dev/null | sort -u)
        else
            # Fallback: basic text parsing for package names
            matching_packages=$(grep -o '"id":"[^"]*"' "$search_output" 2>/dev/null | sed 's/"id":"\([^"]*\)"/\1/' | sort -u)
        fi

        # Filter out country-specific packages and find base versions
        local country_codes="\.US\.|\.GB\.|\.DK\.|\.DE\.|\.FR\.|\.ES\.|\.IT\.|\.NL\.|\.BE\.|\.SE\.|\.NO\.|\.FI\.|\.CH\.|\.AT\.|\.CA\.|\.AU\.|\.NZ\.|\.IN\.|\.MX\.|\.CZ\.|\.PL\.|\.RU\.|\.IS\."

        local base_package=""
        # First, try to find exact match (no GUID suffix)
        while IFS= read -r package; do
            if [[ -n "$package" && ! "$package" =~ $country_codes ]]; then
                if [[ "$package" == "$base_name" ]]; then
                    echo "    📦 Found exact match: $package" >&2
                    base_package="$package"
                    break
                fi
            fi
        done <<< "$matching_packages"

        # If no exact match found, look for partial matches or GUID-suffixed versions
        if [[ -z "$base_package" ]]; then
            # Create a normalized search pattern by removing spaces and hyphens
            local base_name_normalized=$(echo "$base_name" | sed 's/[- ]//g' | tr '[:upper:]' '[:lower:]')

            while IFS= read -r package; do
                if [[ -n "$package" && ! "$package" =~ $country_codes ]]; then
                    # Normalize the package name for comparison
                    local package_normalized=$(echo "$package" | sed 's/[- ]//g' | tr '[:upper:]' '[:lower:]')

                    # Check if the normalized package name contains the normalized base name
                    if [[ "$package_normalized" == *"$base_name_normalized"* ]]; then
                        echo "    📦 Found partial match: $package" >&2
                        base_package="$package"
                        break
                    fi

                    # Look for GUID pattern as fallback
                    if [[ "$package" =~ ^${base_name}\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
                        echo "    📦 Found GUID-suffixed package: $package" >&2
                        base_package="$package"
                        break
                    fi
                fi
            done <<< "$matching_packages"
        fi

        if [ -n "$base_package" ]; then
            # Extract version from the JSON response for this specific package
            local latest_version=""
            if command -v jq >/dev/null 2>&1; then
                latest_version=$(jq -r ".data[] | select(.id == \"$base_package\") | .version" "$search_output" 2>/dev/null | grep "^${major_version}\." | sort -V | tail -1)
            else
                # Fallback: basic parsing for version
                latest_version=$(grep -A 5 "\"id\":\"$base_package\"" "$search_output" 2>/dev/null | grep -o '"version":"[^"]*"' | sed 's/"version":"\([^"]*\)"/\1/' | grep "^${major_version}\." | sort -V | tail -1)
            fi

            if [ -n "$latest_version" ]; then
                echo "    ✅ Found: $base_package v$latest_version" >&2
                rm -f "$search_output"
                echo "$base_package:$latest_version"  # Return both package name and version
                return 0
            else
                echo "    ⚠️  No version found for major version $major_version" >&2
            fi
        fi
    fi

    rm -f "$search_output"
    echo "    ❌ No base package found for $base_name" >&2
    return 1
}

# Function to download symbols with dynamic version discovery (for both Microsoft and non-Microsoft packages)
download_symbols_dynamic() {
    local package_name="$1"
    local major_version="$2"

    echo "📦 Downloading $package_name (latest ${major_version}.x.x.x with dynamic discovery)..."

    # Define source mappings for direct download
    local sources=(
        "AppSourceSymbols|https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v2|https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/query2"
        "MSSymbols|https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v2|https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/query2"
    )

    # Try each source in order of preference
    for source in "${sources[@]}"; do
        local source_name=$(echo "$source" | cut -d'|' -f1)
        local download_url=$(echo "$source" | cut -d'|' -f2)
        local api_url=$(echo "$source" | cut -d'|' -f3)

        echo "  Trying source: $source_name"

        # Use the flexible search function that handles exact matches, partial matches, and GUID suffixes
        local package_info=$(find_microsoft_package_with_guid_direct "$package_name" "$major_version" "$source_name" "$api_url")

        if [ -n "$package_info" ]; then
            # Split package_info into package name and version
            local actual_package_name=$(echo "$package_info" | cut -d: -f1)
            local latest_version=$(echo "$package_info" | cut -d: -f2)

            echo "  Attempting to download $actual_package_name v$latest_version from $source_name..."
            if download_and_extract_nupkg "$actual_package_name" "$latest_version" "$source_name" "$download_url"; then
                echo "✅ Successfully downloaded $actual_package_name v$latest_version from $source_name"
                return 0
            else
                echo "⚠️  Download failed for $actual_package_name v$latest_version from $source_name"
            fi
        fi
    done

    echo "❌ Failed to download $package_name for major version $major_version"
    return 1
}

# Download Microsoft system symbols
echo "Downloading Microsoft system symbols..."
echo "📦 Downloading Microsoft base symbol packages (always latest version)..."
echo "⚠️  Note: Searching for Microsoft packages, base versions only (no country codes)"

# Microsoft Base Applications with dynamic discovery (always latest version)
download_symbols_dynamic "Microsoft.BaseApplication.symbols" "$BC_MAJOR_VERSION" || echo "Continuing despite failure..."
download_symbols_dynamic "Microsoft.Application.symbols" "$BC_MAJOR_VERSION" || echo "Continuing despite failure..."
download_symbols_dynamic "Microsoft.SystemApplication.symbols" "$BC_MAJOR_VERSION" || echo "Continuing despite failure..."

# Additional Microsoft platform symbols often required by AL compiler
download_symbols_dynamic "Microsoft.System.symbols" "$BC_MAJOR_VERSION" || echo "Continuing despite failure..."
download_symbols_dynamic "Microsoft.BusinessFoundation.symbols" "$BC_MAJOR_VERSION" || echo "Continuing despite failure..."

# Try alternative naming patterns for System symbols
download_symbols_dynamic "Microsoft.Platform.symbols" "$BC_MAJOR_VERSION" || echo "Continuing despite failure..."

# Download dependencies from app.json
echo "Downloading dependencies..."
jq -c '.dependencies[]' "$APP_JSON_PATH" | while read -r dep; do
    PUBLISHER=$(echo "$dep" | jq -r '.publisher')
    NAME=$(echo "$dep" | jq -r '.name')
    VERSION=$(echo "$dep" | jq -r '.version')
    DEP_MAJOR_VERSION=$(echo "$VERSION" | cut -d. -f1)

    # Create package name with original name
    PACKAGE_NAME="$PUBLISHER.$NAME.symbols"

    # Also create alternative package name with spaces converted to hyphens and no spaces
    # This handles the common case where app.json has "9A Advanced Manufacturing - License"
    # but the actual package is "9altitudes.9AAdvancedManufacturing-License.symbols"
    NAME_NORMALIZED=$(echo "$NAME" | sed 's/ /-/g')  # Convert spaces to hyphens
    NAME_NO_SPACES=$(echo "$NAME" | sed 's/ //g')    # Remove all spaces
    ALT_PACKAGE_NAME1="$PUBLISHER.$NAME_NORMALIZED.symbols"
    ALT_PACKAGE_NAME2="$PUBLISHER.$NAME_NO_SPACES.symbols"

    echo "Trying dependency: $PACKAGE_NAME"
    echo "  Alternatives: $ALT_PACKAGE_NAME1, $ALT_PACKAGE_NAME2"

    # Always use the most recent version (DEP_MAJOR_VERSION) for all dependencies
    # Try original name first, then alternatives
    if download_symbols_dynamic "$PACKAGE_NAME" "$DEP_MAJOR_VERSION"; then
        continue
    elif download_symbols_dynamic "$ALT_PACKAGE_NAME1" "$DEP_MAJOR_VERSION"; then
        continue
    elif download_symbols_dynamic "$ALT_PACKAGE_NAME2" "$DEP_MAJOR_VERSION"; then
        continue
    else
        echo "Continuing despite failure..."
    fi
done

# Verify symbol files are in place (no copying needed - files are already extracted to the correct location)
echo "Organizing symbol files..."
# Note: .app files are already extracted directly to $SYMBOLS_PATH, so no copying is needed

# Clean up temporary files
rm -f /tmp/rest_api_search_*.txt /tmp/extract_*

echo "Symbol restoration complete!"
echo "Symbols available in: $SYMBOLS_PATH"

# Count total .app files found
APP_COUNT=$(find "$SYMBOLS_PATH" -name "*.app" -type f | wc -l)
echo "Total .app files: $APP_COUNT"

if [ "$APP_COUNT" -eq 0 ]; then
    echo ""
    echo "⚠️  WARNING: No symbol files (.app) were downloaded!"
    echo "This could indicate:"
    echo "  - Network connectivity problems"
    echo "  - Incorrect version numbers in app.json"
    echo "  - Package names not available in the configured feeds"
    echo ""
    echo "Please check:"
    echo "  1. BC version ($BC_VERSION) exists in Microsoft feeds"
    echo "  2. Network can reach Microsoft NuGet feeds"
    echo ""
    exit 1
else
    echo "✅ Symbol restoration successful!"
    echo ""
    echo "Available symbol files:"
    ls -la "$SYMBOLS_PATH"/*.app 2>/dev/null || echo "  (No .app files in root, but found in subdirectories)"
fi