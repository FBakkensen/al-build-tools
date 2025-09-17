# AL Build Tools (overlay bootstrap)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Contributions welcome](https://img.shields.io/badge/Contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

A minimal, cross-platform build toolkit for Microsoft AL projects with a dead-simple bootstrap. It is designed to be dropped into an existing git repo and updated by running the same single command again.

Install and update are the same: the bootstrap copies everything from this repo’s `overlay/` folder into your project. Because you’re in git, you review and commit changes as you like.

## Quick Start (Install Latest)

- PowerShell 7+ for installer (Windows, macOS, Linux)
  ```
  iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .
  ```

Re-run the same command any time to update — it re-copies `overlay/*` over your working tree.

---

## What This Repo Provides

- `overlay/` — the files that are copied into your project:
  - `Makefile` — thin dispatcher that invokes PowerShell entrypoints.
  - `scripts/make/*.ps1` — PowerShell 7.2+ entrypoints: `build.ps1`, `clean.ps1`, `show-config.ps1`, `show-analyzers.ps1`.
  - `scripts/next-object-number.ps1` — helper: print next available AL object id.
  - `.gitattributes` — recommended line-ending normalization.
  - `AGENTS.md` — contributor/agent guidance (optional to keep).
- `bootstrap/` — the self-contained installer used by the one‑liner above:
  - `install.ps1` (PowerShell 7+)

## Why “overlay”?

Only the contents of `overlay/` are ever copied to your project. That keeps the bootstrap stable even if other files are added to this repository in the future.

## Requirements

- Installer: PowerShell 7.0+ (`Invoke-WebRequest`, `Expand-Archive` built-in)
- Entry scripts: PowerShell 7.2+ (`#requires -Version 7.2`)
- Destination should be a git repo (no backups are created; git handles history and diffs)

## After Installing

- Make (recommended)
  - `make build` — compile the AL project
  - `make clean` — remove build artifact
  - `make show-config` — print normalized config snapshot
  - `make show-analyzers` — list enabled analyzers and resolved DLLs

- Direct PowerShell invocation (advanced)
  - Entry scripts are guarded and expect to run via `make`. If you must call them directly, set `ALBT_VIA_MAKE=1` and pass the app directory (default `app`):
    - `ALBT_VIA_MAKE=1 pwsh -File scripts/make/build.ps1 app`
    - `ALBT_VIA_MAKE=1 pwsh -File scripts/make/clean.ps1 app`
    - `ALBT_VIA_MAKE=1 pwsh -File scripts/make/show-config.ps1 app`
    - `ALBT_VIA_MAKE=1 pwsh -File scripts/make/show-analyzers.ps1 app`
  - The helper `scripts/next-object-number.ps1` is safe to run without the guard.

## Guard Policy

To keep behavior consistent and avoid accidental misuse, the entrypoints under `scripts/make/*.ps1` refuse direct execution unless `ALBT_VIA_MAKE=1` is present in the environment (the Makefile sets this automatically). Direct calls without the guard exit with code 2 and a guidance message like “Run via make (e.g., make build)”.

Exceptions: the helper `scripts/next-object-number.ps1` is not guarded.

## Exit Codes

Entry scripts use a standardized mapping for predictable CI behavior:

- Success: 0
- GeneralError: 1
- Guard: 2
- Analysis: 3
- Contract: 4
- Integration: 5
- MissingTool: 6

## Verbosity

- Enable verbose logs with either `-Verbose` or `VERBOSE=1` in the environment. Verbose messages follow PowerShell’s `Write-Verbose` conventions.

## Static Analysis Quality Gate

PRs that modify `overlay/**` or `bootstrap/**` run a PSScriptAnalyzer quality gate in CI (Windows and Ubuntu). Blocking errors fail the job with exit code 3 using the repository `PSScriptAnalyzerSettings.psd1`.

Run locally (PowerShell):
```
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path overlay, bootstrap/install.ps1 -Recurse -Settings PSScriptAnalyzerSettings.psd1
```

## Tests

The repository includes Pester tests for contract behavior and integration flows (Makefile-driven usage). CI runs the suite on Windows and Ubuntu.

- Run all tests locally:
  - `pwsh -File scripts/run-tests.ps1 -CI`
- Or invoke directly with Pester:
  - `Invoke-Pester -CI -Path tests/contract`
  - `Invoke-Pester -CI -Path tests/integration`

### Installer Test Contract

The installer contract (FR-012) documents the behaviors enforced by the automated suites so contributors know what must remain stable:

- Guard rails: rejects non-git destinations, dirty working trees, unsupported PowerShell, unknown parameters, and restricted/denied writes. Each failure emits `[install] guard <Reason>` and exits 10 (guards) or 30 (permission scope); tests assert these diagnostics.
- Temp workspace: emits `[install] temp workspace="..."`, which must live under the system temp root and be cleaned up after every run.
- Download diagnostics: acquisition failures log `[install] download failure ... category=<NetworkUnavailable|NotFound|CorruptArchive|Timeout|Unknown>` and must leave the destination unchanged.
- Success path: success logs `[install] success ref="..." overlay="..." duration=<seconds>` and a second run must restore overlay file hashes (idempotence).
- Step telemetry: `[install] step index=... name=...` stays stable to keep parity and performance checks meaningful across platforms.

Run `pwsh -File scripts/run-tests.ps1 -CI` before modifying `bootstrap/install.ps1`; CI replays the same contract on Windows and Ubuntu.

## How It Works

1. Downloads a ZIP of this repo at the specified ref (default `main`).
2. Copies `overlay/*` into your destination directory, overwriting existing files.
3. No state files and no backups — use git to review and commit changes.

## Troubleshooting

- “Running scripts is disabled” on Windows: start PowerShell as Administrator and run:
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` or use `-ExecutionPolicy Bypass` for one-off runs.
- Linux/macOS: ensure PowerShell 7.2+ (`pwsh`) and `make` are installed and available in `PATH`.

## WSL Development Setup (Ubuntu 22.04/24.04)

Set up the tools needed to run local analysis and tests when developing inside WSL.

- Check distro info
  - `. /etc/os-release && echo "$ID $VERSION_ID $VERSION_CODENAME"`

- Install base packages
  - `sudo apt-get update && sudo apt-get install -y curl gpg jq make`

- Add Microsoft package repo (required for PowerShell 7)
  - `sudo mkdir -p /etc/apt/keyrings`
  - `curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg`
  - `. /etc/os-release`
  - `echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/${VERSION_ID}/prod ${VERSION_CODENAME} main" | sudo tee /etc/apt/sources.list.d/microsoft-prod.list >/dev/null`
  - `sudo apt-get update && sudo apt-get install -y powershell`

- Install PSScriptAnalyzer and Pester in PowerShell
  - `pwsh -NoLogo -NoProfile -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module PSScriptAnalyzer,Pester -Scope CurrentUser -Force"`

- Verify tools
  - `pwsh --version`
  - `make --version`
  - `pwsh -NoLogo -NoProfile -Command "Get-Module PSScriptAnalyzer -ListAvailable | Select Name,Version"`

- Run repository tests
  - `pwsh -File scripts/run-tests.ps1 -CI`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for workflow, coding style, and analyzer tips. In short: entrypoints are PowerShell-only under `overlay/scripts/make`, guarded for Makefile use, and should remain self‑contained and stable.

## License

Licensed under the [MIT License](LICENSE). You are free to use, modify, and distribute this project with attribution and without warranty.
