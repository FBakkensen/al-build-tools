# AL Build Tools

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Contributions welcome](https://img.shields.io/badge/Contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

A minimal, cross-platform build toolkit for Microsoft AL (Business Central) projects. Drop it into your AL repository and build with a single command.

## Quick Install

Run inside the root of your AL git repository (PowerShell 7+):

```powershell
iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .
```

Re-run the same command at any time to update to the latest release (or pin with `-Ref vX.Y.Z`).

## What Problem This Solves

AL Build Tools provides a predictable, copy-only build system that you can refresh at any time. No custom scaffolding, no hidden state—just a set of PowerShell scripts that live in your repository.

**Key benefits:**
- **Copy-only overlay** - Install just overwrites files in your repo, nothing else
- **Cross-platform** - Works on Windows and Linux with PowerShell 7.2+
- **Automated provisioning** - Compiler and symbols resolved from your `app.json`
- **Idempotent updates** - Rerun the installer to pull new versions; review changes in git

If you outgrow it, just delete the copied files—there's no hidden state.

## Prerequisites

- **PowerShell 7.2+** - [Install PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
- **.NET SDK** - Required for installing the AL compiler as a dotnet tool and downloading symbols from NuGet
- **InvokeBuild module** - Install with: `Install-Module InvokeBuild -Scope CurrentUser`
- **Git working directory** - The installer copies files into your repo
- **AL project directory** - Default expected path: `app/` with `app.json`

## Quick Start

After installing, run your first build:

```powershell
# First time: provision compiler and symbols
Invoke-Build provision

# Build your project
Invoke-Build build
```

## Daily Usage Guide

AL Build Tools follows a three-stage workflow:

### 1. Compiler Setup (One-time per machine)

The AL compiler is installed as a .NET tool and cached in your user profile. You only need to do this once per machine:

```powershell
Invoke-Build download-compiler
```

### 2. Symbol Provisioning (Per project or when dependencies change)

Business Central symbols are downloaded based on your `app.json` dependencies. Run this once per project, or whenever you add new dependencies:

```powershell
Invoke-Build download-symbols
```

Or provision both compiler and symbols at once:

```powershell
Invoke-Build provision
```

### 3. Daily Development Workflow

These are the commands you'll use every day:

**Build your main app:**
```powershell
Invoke-Build build
```

**Run full test workflow** (build → test → publish → run tests):
```powershell
Invoke-Build test
```

**Clean build artifacts:**
```powershell
Invoke-Build clean
```

**View configuration:**
```powershell
Invoke-Build show-config
```

## Available Tasks

Run `Invoke-Build ?` to see all available tasks. Here are the main ones:

### Main Tasks

| Task | Description |
|------|-------------|
| `build` | Compile the main app only |
| `test` | Run full test workflow (build → test → publish → run tests) |
| `publish` | Publish main app to BC server (builds first) |
| `provision` | Set up environment (compiler + symbols) |
| `clean` | Remove build artifacts |

### Utility Tasks

| Task | Description |
|------|-------------|
| `show-config` | Display current configuration |
| `show-analyzers` | Show discovered analyzers |
| `new-bc-container` | Create and configure BC Docker container |
| `validate-breaking-changes` | Validate app against previous release |
| `help` | Show built-in help message |

### Setup Tasks

| Task | Description |
|------|-------------|
| `download-compiler` | Install/update AL compiler (one-time per machine) |
| `download-symbols` | Download BC symbol packages (per project) |
| `download-symbols-test` | Download symbols for test app |
| `all` | Full setup: provision + test (for new environments) |

## Configuration

### Core Settings in al.build.ps1

The build system is configured through `al.build.ps1`, which defines several key settings:

**Project Structure:**
- **App Directory** (`ALBT_APP_DIR`) - Location of your main AL project (default: `app/`)
  - Must contain a valid `app.json` file
  - Used for compiler and symbol resolution
- **Test Directory** (`ALBT_TEST_DIR`) - Location of your test project (default: `test/`)
  - Optional, only needed if you have tests

**Code Analysis:**
- **Analyzer Discovery** - Automatically reads enabled analyzers from `.vscode/settings.json`
  - Supports modern format: `al.codeAnalyzers` array
  - Supports legacy format: `al.enableCodeCop`, `al.enableUICop`, etc.
  - Built-in analyzers: CodeCop, UICop, AppSourceCop, PerTenantExtensionCop
  - Custom analyzers with path token resolution (`${analyzerFolder}`, `${workspaceFolder}`, etc.)
- **Ruleset File** (`RULESET_PATH`) - Optional analyzer ruleset (default: `al.ruleset.json`)
  - Only used if the file exists in your project root
  - Configures severity levels and rules for enabled analyzers

**Build Behavior:**
- **Warnings as Errors** (`WARN_AS_ERROR`) - Treat compiler warnings as build failures (default: `1`)
  - Set to `0` to allow warnings

All settings can be overridden via parameters or environment variables (see below).

### Using Parameters

Pass configuration directly to Invoke-Build:

```powershell
# Build without treating warnings as errors
Invoke-Build build -WarnAsError "0"

# Use a different app directory
Invoke-Build build -AppDir "src/app"

# Configure BC server for testing
Invoke-Build test -ServerUrl "http://localhost:8080" -ServerInstance "BC"
```

### Using Environment Variables

Set environment variables before running Invoke-Build:

```powershell
$env:ALBT_APP_DIR = "src/app"
$env:WARN_AS_ERROR = "0"
$env:ALBT_BC_SERVER_URL = "http://localhost:8080"
Invoke-Build build
```

### Configuration Priority

Settings are resolved in this order:
1. **Parameter** (highest priority) - passed to `Invoke-Build`
2. **Environment Variable** - set before invocation
3. **Default Value** - defined in `al.build.ps1`

### Common Configuration Variables

| Variable | Parameter | Default | Description |
|----------|-----------|---------|-------------|
| `ALBT_APP_DIR` | `-AppDir` | `app` | App directory containing app.json |
| `ALBT_TEST_DIR` | `-TestDir` | `test` | Test app directory |
| `WARN_AS_ERROR` | `-WarnAsError` | `1` | Treat compiler warnings as errors |
| `RULESET_PATH` | `-RulesetPath` | `al.ruleset.json` | Analyzer ruleset file |
| `ALBT_BC_SERVER_URL` | `-ServerUrl` | `http://bctest` | Business Central server URL |
| `ALBT_BC_SERVER_INSTANCE` | `-ServerInstance` | `BC` | BC server instance name |
| `ALBT_BC_CONTAINER_NAME` | `-ContainerName` | `bctest` | BC Docker container name |
| `ALBT_BC_TENANT` | `-Tenant` | `default` | BC tenant name |

For a complete list, see the configuration section in `al.build.ps1`.

## Updating

To update to the latest release, simply re-run the install command:

```powershell
iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .
```

Or pin to a specific version:

```powershell
iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest . -Ref v1.2.3
```

Review the changes in git and commit what you want to keep.

## CI/CD Integration

Use AL Build Tools in your CI pipeline:

```yaml
# Example GitHub Actions workflow
- name: Install AL Build Tools
  shell: pwsh
  run: |
    iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex
    Install-AlBuildTools -Dest .

- name: Provision and Build
  shell: pwsh
  run: |
    Invoke-Build provision
    Invoke-Build build

- name: Run Tests
  shell: pwsh
  run: Invoke-Build test
```

## Troubleshooting

### "Invoke-Build is not recognized"

Install the InvokeBuild module:

```powershell
Install-Module InvokeBuild -Scope CurrentUser -Force
```

### "Running scripts is disabled" (Windows)

Set execution policy to allow scripts:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Or use `-ExecutionPolicy Bypass` for one-off runs.

### PowerShell version too old

AL Build Tools requires PowerShell 7.2+. Check your version:

```powershell
$PSVersionTable.PSVersion
```

Install the latest PowerShell from [microsoft.com/powershell](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell).

### Linux/macOS setup

Ensure PowerShell 7.2+ is installed:

```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y powershell

# macOS
brew install powershell/tap/powershell
```

Then install InvokeBuild:

```bash
pwsh -Command "Install-Module InvokeBuild -Scope CurrentUser -Force"
```

## What Gets Installed

The installer copies these files to your repository:

```
overlay/
├── al.build.ps1           # Main build orchestrator (Invoke-Build)
├── scripts/
│   ├── common.psm1        # Shared utilities
│   └── make/              # PowerShell build scripts
│       ├── build.ps1
│       ├── clean.ps1
│       ├── download-compiler.ps1
│       ├── download-symbols.ps1
│       ├── publish-app.ps1
│       ├── run-tests.ps1
│       ├── show-config.ps1
│       ├── show-analyzers.ps1
│       ├── new-bc-container.ps1
│       └── validate-breaking-changes.ps1
└── al.ruleset.json        # Code analyzer ruleset
```

Only files in `overlay/` are copied—nothing else. Use git to review and commit changes.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development workflow, coding standards, and testing guidelines.

## License

Licensed under the [MIT License](LICENSE). Free to use, modify, and distribute with attribution.
