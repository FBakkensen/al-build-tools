#!/bin/bash
set -e

# Business Central Symbol Restoration Script
#
# This script restores Business Central symbols using the NuGet CLI by installing symbol packages from Microsoft and AppSource feeds.
# Key behaviors:
# - Uses the NuGet CLI to install symbol packages at the highest available version
# - Installs Microsoft system symbols and AppSource dependencies via configured NuGet sources
# - Organizes downloaded .app files into the .alpackages folder, handling duplicates and cleaning up empty directories
# - Processes dependencies declared in app.json, constructing package names from publisher, name, and id
# - Checks for required tools: nuget CLI (mandatory), jq (optional for JSON parsing), curl and unzip for version info
#
# Key insight: nuget install extracts .app files from .nupkg packages into subdirectories; the script moves them to .alpackages and cleans up.
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

if ! command -v mono &> /dev/null; then
    echo "Error: mono not found. This script requires mono to run nuget.exe."
    exit 1
fi

if [ ! -f "/usr/local/bin/nuget.exe" ]; then
    echo "Error: /usr/local/bin/nuget.exe not found. This script requires the NuGet CLI."
    exit 1
fi

echo "Using curl $(curl --version | head -1)"
echo "Using unzip $(unzip -v | head -1)"
echo "Using nuget $(mono /usr/local/bin/nuget.exe | head -1)"

# Check if jq is available for JSON parsing (optional but recommended)
# Check if jq is available for JSON parsing (optional but recommended)
if command -v jq &> /dev/null; then
    echo "Using jq $(jq --version) for JSON parsing"
else
    echo "Warning: jq not available, using basic text parsing (jq recommended for better reliability)"
fi

# Function to organize downloaded .app files and clean up empty directories
ORGANIZE_APP_FILES() {
    echo "Organizing downloaded symbol files..."
    find "$SYMBOLS_PATH" -name "*.app" -type f | while read -r app_file; do
        app_filename=$(basename "$app_file")
        target_file="$SYMBOLS_PATH/$app_filename"
        if [ "$(dirname "$app_file")" != "$SYMBOLS_PATH" ]; then
            if [ -f "$target_file" ]; then
                echo "  Found duplicate for $app_filename, skipping move."
            else
                echo "  Moving $app_filename to $SYMBOLS_PATH"
                mv "$app_file" "$SYMBOLS_PATH/"
            fi
        fi
    done
    echo "Cleaning up empty package directories..."
    find "$SYMBOLS_PATH" -mindepth 1 -type d -empty -delete
}

# Setup NuGet sources
echo "Setting up NuGet sources..."

# Add the MSSymbols feed
echo "Adding NuGet source for Microsoft Symbols..."
mono /usr/local/bin/nuget.exe sources Add -Name "MSSymbols" -Source "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json" -NonInteractive
echo "Adding NuGet source for AppSource Symbols..."
mono /usr/local/bin/nuget.exe sources Add -Name "AppSource" -Source "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json" -NonInteractive

# Download latest Microsoft.Application.symbols with dependencies
echo "Downloading Microsoft.Application.symbols and its dependencies..."
mono /usr/local/bin/nuget.exe install Microsoft.Application.symbols -Source MSSymbols -OutputDirectory "$SYMBOLS_PATH" -Prerelease -DependencyVersion Highest -NonInteractive

# Download dependencies from app.json
echo "Downloading dependencies from app.json..."
jq -c '.dependencies[]' "$APP_JSON_PATH" | while read -r dep; do
    PUBLISHER=$(echo "$dep" | jq -r '.publisher')
    NAME=$(echo "$dep" | jq -r '.name')
    DEP_ID=$(echo "$dep" | jq -r '.id')

    # Remove all spaces from the name (truncate spaces)
    NAME_TRUNCATED=$(echo "$NAME" | tr -d ' ')
    PACKAGE_NAME="$PUBLISHER.$NAME_TRUNCATED.symbols.$DEP_ID"

    echo "➡️  Processing dependency: $NAME by $PUBLISHER"
    echo "  Attempting to install package: $PACKAGE_NAME"

    if mono /usr/local/bin/nuget.exe install "$PACKAGE_NAME" -Source "AppSource" -OutputDirectory "$SYMBOLS_PATH" -Prerelease -DependencyVersion Highest -NonInteractive; then
        echo "  ✅ Successfully downloaded $PACKAGE_NAME"
    else
        echo "  ⚠️  Failed to download dependency '$NAME'. Package $PACKAGE_NAME not found in AppSource feed or requires a specific version."
    fi
done

# Organize all .app files after all downloads
echo "Organizing symbol files..."
ORGANIZE_APP_FILES

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