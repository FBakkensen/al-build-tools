# Quickstart: Linux Installation Support

**Audience**: Developers implementing or testing Linux installer
**Time**: 15 minutes
**Prerequisites**: Ubuntu 22.04 system (or Docker), git, sudo access

---

## For End Users: Installing AL Build Tools on Linux

### 1. Prepare System

```bash
# Cache sudo session (required for prerequisite installation)
sudo -v

# Initialize git repository if needed
git init
git config user.name "Your Name"
git config user.email "you@example.com"
```

### 2. Run Installer (One-Liner)

```bash
# Download and run installer (not yet implemented)
curl -sSL https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install-linux.sh | bash
```

### 3. Or Clone and Install Locally

```bash
# Clone repository
git clone https://github.com/FBakkensen/al-build-tools.git
cd al-build-tools

# Run installer (bash script)
bash bootstrap/install-linux.sh
```

### Expected Output

```
================================================================================
  AL Build Tools Installation
================================================================================

[>] Checking prerequisites
[install] prerequisite tool="git" status="check"
[install] prerequisite tool="git" status="found" version="2.34.1"
[install] prerequisite tool="powershell" status="check"
[install] prerequisite tool="powershell" status="missing"

[>] Installing PowerShell 7
[install] prerequisite tool="powershell" status="installing"
... (apt output)
[+] PowerShell 7.4.0 installed

[>] Downloading overlay
[install] phase name="overlay-download" duration="5s"

[>] Copying files
[install] step index=4 name=Copy_Files

[>] Creating git commit
[install] phase name="git-commit" duration="1s"

[+] Installation completed successfully
```

---

## For Developers: Implementation Workflow

### Phase 0: Setup Development Environment

```bash
# Clone repository and switch to feature branch
git clone https://github.com/FBakkensen/al-build-tools.git
cd al-build-tools
git checkout 009-linux-install-support

# Review planning artifacts
cat specs/009-linux-install-support/plan.md
cat specs/009-linux-install-support/research.md
cat specs/009-linux-install-support/data-model.md
ls specs/009-linux-install-support/contracts/
```

### Phase 1: Create Linux Installer Scripts

```bash
# Create bootstrap/install-linux.sh (bash script - main entry point)
# Key responsibilities:
# - Parameter parsing (Url, Ref, DestinationPath, Source)
# - Git repository validation (guard checks)
# - Call install-prerequisites-linux.sh for apt operations
# - Download overlay.zip using curl
# - Extract archive using tar/unzip
# - Copy files to destination
# - Create git commit using git CLI
# - Emit diagnostic markers matching Windows format

# Create bootstrap/install-prerequisites-linux.sh (bash script)
# Implement:
# - Sudo session check: sudo -n true
# - apt cache update with retry logic
# - Microsoft repository setup (download .deb package)
# - PowerShell 7 installation: apt-get install powershell
# - .NET SDK installation: apt-get install dotnet-sdk-8.0
# - After PowerShell installed, delegate to pwsh for:
#   - Install-Module InvokeBuild -Scope CurrentUser -Force
```

### Phase 2: Create Test Harness

```bash
# Create scripts/ci/test-bootstrap-install-linux.ps1 (PowerShell - runs on host)
# Adapt from test-bootstrap-install.ps1:
# - Use ubuntu:22.04 base image instead of Windows Server Core
# - Mount volumes for artifact extraction
# - Execute bash script inside container: bash /tmp/install-linux.sh
# - Parse transcript for diagnostic markers
# - Generate summary.json matching schema
# - Validate JSON against contracts/test-summary-schema.json
```

### Phase 3: Run Local Tests

```bash
# Test prerequisite installation (requires sudo)
sudo -v
bash bootstrap/install-prerequisites-linux.sh -Verbose

# Test full installer in Docker container
pwsh -File scripts/ci/test-bootstrap-install-linux.ps1 -Verbose

# Verify artifacts
ls out/test-install/
cat out/test-install/summary.json | jq .
```

### Phase 4: Validate Against Contracts

```bash
# Install JSON schema validator
npm install -g ajv-cli

# Validate summary.json
ajv validate \
  -s specs/009-linux-install-support/contracts/test-summary-schema.json \
  -d out/test-install/summary.json

# Check exit codes
pwsh -Command '$LASTEXITCODE; if ($LASTEXITCODE -ne 0) { exit 1 }'
```

---

## Testing Scenarios

### Scenario 1: Fresh Ubuntu Install

```bash
docker run --rm -it ubuntu:22.04 bash

# Inside container:
apt-get update && apt-get install -y curl
curl -sSL https://raw.githubusercontent.com/.../install-linux.sh | bash

# Expected: All prerequisites installed, overlay copied, exit 0
```

### Scenario 2: Partial Prerequisites

```bash
docker run --rm -it ubuntu:22.04 bash

# Pre-install git only
apt-get update && apt-get install -y git

# Run installer
bash /path/to/install-linux.sh

# Expected: Skip git, install PS7 + .NET + InvokeBuild, exit 0
```

### Scenario 3: Missing Sudo

```bash
docker run --rm -it --user 1000:1000 ubuntu:22.04 bash

# Run installer without sudo
bash /path/to/install-linux.sh

# Expected: [install] prerequisite tool="sudo" status="missing", exit 6
```

### Scenario 4: Not a Git Repository

```bash
mkdir /tmp/not-a-repo
cd /tmp/not-a-repo
bash /path/to/install-linux.sh

# Expected: [install] guard GitRepoRequired, exit 2
```

### Scenario 5: Dirty Working Tree

```bash
git init /tmp/test-repo
cd /tmp/test-repo
echo "test" > file.txt
git add file.txt
# Don't commit

bash /path/to/install-linux.sh

# Expected: [install] guard CleanWorkingTreeRequired, exit 2
```

---

## Diagnostic Output Examples

### Success Case

```
[install] step index=1 name=Check_Prerequisites
[install] prerequisite tool="git" status="found" version="2.34.1"
[install] prerequisite tool="powershell" status="found" version="7.4.0"
[install] prerequisite tool="dotnet" status="found" version="8.0.100"
[install] prerequisite tool="InvokeBuild" status="found"
[install] step index=2 name=Resolve_Release
[install] phase name="release-resolution" duration="3s"
[install] step index=3 name=Download_Overlay
[install] phase name="overlay-download" duration="5s"
[install] step index=4 name=Copy_Files
[install] phase name="file-copy" duration="2s"
[install] step index=5 name=Git_Commit
[install] phase name="git-commit" duration="1s"
[+] Installation completed successfully
```

### Failure Case (apt locked)

```
[install] step index=1 name=Check_Prerequisites
[install] prerequisite tool="powershell" status="missing"
[install] step index=2 name=Install_Prerequisites
[install] prerequisite tool="powershell" status="installing"
[install] prerequisite status="retry" reason="apt-locked" delay="5s"
[install] prerequisite status="retry" reason="apt-locked" delay="10s"
[install] prerequisite status="retry" reason="apt-locked" delay="20s"
[X] Installation failed: apt package manager locked after 3 retries. Try: sudo fuser -vki /var/lib/dpkg/lock-frontend
```

### Guard Violation

```
[install] guard GitRepoRequired
Installation failed: Destination must be a git repository. Run 'git init' first.
```

---

## File Structure After Implementation

```
bootstrap/
├── install.ps1                      # Existing Windows installer (PowerShell - routes to Linux on non-Windows)
├── install-prerequisites.ps1        # Existing Windows prerequisites (PowerShell)
├── install-linux.sh                 # NEW: Linux installer (Bash - main entry point)
└── install-prerequisites-linux.sh   # NEW: Linux prerequisites (Bash - apt operations)

scripts/ci/
├── test-bootstrap-install.ps1       # Existing Windows test harness (PowerShell)
└── test-bootstrap-install-linux.ps1 # NEW: Linux test harness (PowerShell - runs on host)

specs/009-linux-install-support/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md                    # This file
├── contracts/
│   ├── README.md
│   ├── exit-codes.md
│   ├── installer-diagnostic-schema.json
│   └── test-summary-schema.json
└── tasks.md                         # Generated by /speckit.tasks (not yet created)
```

---

## Troubleshooting

### "Sudo session required"

**Problem**: Installer exits with code 6, message about sudo
**Solution**: Run `sudo -v` before installer to cache credentials

### "apt package manager locked"

**Problem**: Another process (unattended-upgrades) holding lock
**Solution**: Wait for background process to finish, or run:
```bash
sudo fuser -vki /var/lib/dpkg/lock-frontend
```

### "PowerShell 7 installation failed"

**Problem**: Microsoft package repository unreachable
**Solution**:
1. Check internet connectivity
2. Verify DNS resolution: `nslookup packages.microsoft.com`
3. Manual install: https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu

### "Corrupt overlay archive"

**Problem**: Download corrupted, extraction fails
**Solution**: Delete cached zip and retry:
```bash
rm -f ~/.cache/albt/overlay.zip
pwsh -File bootstrap/install-linux.ps1
```

---

## Next Steps

1. ✅ Planning complete (this file)
2. ⏳ Implement `bootstrap/install-linux.sh` (Bash)
3. ⏳ Implement `bootstrap/install-prerequisites-linux.sh` (Bash)
4. ⏳ Implement `scripts/ci/test-bootstrap-install-linux.ps1` (PowerShell)
5. ⏳ Write Pester tests for installer
6. ⏳ Update CI pipeline to run Linux tests
7. ⏳ Update README with Linux installation instructions
8. ⏳ Release and announce Linux support

---

**Status**: ✅ Quickstart complete, ready for implementation tasks
