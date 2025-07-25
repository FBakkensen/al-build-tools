
#!/bin/bash
set -e

echo "Setting up AL compiler (latest version)..."

# Create a temporary working directory for all downloads and extraction
WORKDIR=$(mktemp -d)
echo "Using temp directory: $WORKDIR"
cd "$WORKDIR"

# Download the latest AL Language VSIX
echo "Downloading latest AL Language extension..."
wget --user-agent="Mozilla/5.0" "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-dynamics-smb/vsextensions/al/latest/vspackage" -O al.vsix.gz

# Check if we got a gzipped file
if file al.vsix.gz | grep -q "gzip compressed"; then
    echo "Decompressing VSIX file..."
    gunzip al.vsix.gz
    mv al.vsix al.vsix.zip
elif file al.vsix.gz | grep -q "Zip archive"; then
    # It's already a zip, just rename
    mv al.vsix.gz al.vsix.zip
else
    echo "Error: Downloaded file is not a valid VSIX/ZIP file"
    echo "File type: $(file al.vsix.gz)"
    cd -
    rm -rf "$WORKDIR"
    exit 1
fi

# Verify it's a valid zip now
if ! unzip -t al.vsix.zip >/dev/null 2>&1; then
    echo "Error: File is not a valid ZIP archive"
    exit 1
fi

# Extract version from extension/package.json inside the VSIX
unzip -p al.vsix.zip extension/package.json > package.json
AL_VERSION=$(grep '"version"' package.json | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
EXT_DIR="$HOME/.vscode-server/extensions/ms-dynamics-smb.al-$AL_VERSION"

# Remove any existing extension dir for this version
rm -rf "$EXT_DIR"
mkdir -p "$EXT_DIR"

echo "AL compiler and analyzers extracted to $EXT_DIR (original VSIX structure)"
echo "Setup complete."
# Extract VSIX to the correct VS Code extension directory
unzip -q al.vsix.zip -d "$EXT_DIR"

# Move contents of extension/ up one level if present
if [ -d "$EXT_DIR/extension" ]; then
  echo "Moving files from $EXT_DIR/extension to $EXT_DIR ..."
  shopt -s dotglob nullglob
  mv "$EXT_DIR/extension"/* "$EXT_DIR/"
  shopt -u dotglob nullglob
  rmdir "$EXT_DIR/extension"
fi

echo "AL compiler and analyzers installed to $EXT_DIR (alc should be at $EXT_DIR/bin/linux/alc)"
echo "Setup complete."