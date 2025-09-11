# AL Build Tools (overlay bootstrap)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Contributions welcome](https://img.shields.io/badge/Contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

A minimal, cross-platform build toolkit for Microsoft AL projects with a dead-simple bootstrap. It is designed to be dropped into an existing git repo and updated by running the same single command again.

Install and update are the same: the bootstrap copies everything from this repo’s `overlay/` folder into your project. Because you’re in git, you review and commit changes as you like.

## Quick Start (Install Latest)

- Linux/macOS (bash)
  ```
  curl -fsSL https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.sh | bash -s -- --dest .
  ```

- Windows (PowerShell 7+)
  ```
  iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .
  ```

Re-run the same command any time to update — it re-copies `overlay/*` over your working tree.

---

## What This Repo Provides

- `overlay/` — the files that are copied into your project:
  - `Makefile` — thin dispatcher to platform scripts.
  - `scripts/make/linux/*` — build, clean, show-config, show-analyzers and helpers.
  - `scripts/make/windows/*` — PowerShell equivalents (PowerShell 7+).
  - `.gitattributes` — recommended line-ending normalization.
  - `AGENTS.md` — contributor/agent guidance (optional to keep).
- `bootstrap/` — the self-contained installers used by the one-liners above:
  - `install.sh` (bash)
  - `install.ps1` (PowerShell 7+)

## Why “overlay”?

Only the contents of `overlay/` are ever copied to your project. That keeps the bootstrap stable even if other files are added to this repository in the future.

## Requirements

- Linux/macOS: `bash`, `curl`, `tar`, and either `unzip` or `python3`
- Windows: PowerShell 7+ (`Invoke-WebRequest`, `Expand-Archive` built-in)
- Destination should be a git repo (no backups are created; git handles history and diffs)

## After Installing

- Linux
  - Build: `bash scripts/make/linux/build.sh`
  - Clean: `bash scripts/make/linux/clean.sh`
  - Show config: `bash scripts/make/linux/show-config.sh`
  - Show analyzers: `bash scripts/make/linux/show-analyzers.sh`
- Windows (PowerShell 7+)
  - Build: `pwsh -File scripts/make/windows/build.ps1`
  - Clean: `pwsh -File scripts/make/windows/clean.ps1`
  - Show config: `pwsh -File scripts/make/windows/show-config.ps1`
  - Show analyzers: `pwsh -File scripts/make/windows/show-analyzers.ps1`
- Make (optional)
  - If `make` is available: `make build`, `make clean`, etc., will dispatch to the platform scripts.

<!-- Simplified intentionally: one use case — install the latest. Advanced flags exist but are omitted here for clarity. -->

## How It Works

1. Downloads a ZIP of this repo at the specified ref (default `main`).
2. Copies `overlay/*` into your destination directory, overwriting existing files.
3. No state files and no backups — use git to review and commit changes.

## Troubleshooting

- “Running scripts is disabled” on Windows: start PowerShell as Administrator and run:
  `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` or use `-ExecutionPolicy Bypass` for one-off runs.
- Linux/macOS: ensure `curl`, `tar`, and either `unzip` or `python3` are installed and in `PATH`.

## WSL Development Setup (Ubuntu 22.04/24.04)

Set up the tools needed to run local analysis and tests when developing inside WSL.

- Check distro info
  - `. /etc/os-release && echo "$ID $VERSION_ID $VERSION_CODENAME"`

- Install base packages
  - `sudo apt-get update && sudo apt-get install -y curl gpg jq python3 shellcheck`

- Add Microsoft package repo (required for PowerShell 7)
  - `sudo mkdir -p /etc/apt/keyrings`
  - `curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg`
  - `. /etc/os-release`
  - `echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/${VERSION_ID}/prod ${VERSION_CODENAME} main" | sudo tee /etc/apt/sources.list.d/microsoft-prod.list >/dev/null`
  - `sudo apt-get update && sudo apt-get install -y powershell`

- Install PSScriptAnalyzer in PowerShell
  - `pwsh -NoLogo -NoProfile -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"`

- Verify tools
  - `shellcheck -V`
  - `pwsh --version`
  - `pwsh -NoLogo -NoProfile -Command "Get-Module PSScriptAnalyzer -ListAvailable | Select Name,Version"`

- Run repository tests
  - `for t in tests/contract/*.sh tests/integration/*.sh; do echo "--- $t"; bash "$t" || break; done`

Troubleshooting WSL apt sources
- Remove stale/unsigned repos (example: Warp):
  - `sudo rm -f /etc/apt/sources.list.d/warp*.list /etc/apt/trusted.gpg.d/warp*.gpg /etc/apt/keyrings/warp*.gpg 2>/dev/null || true`
  - `sudo apt-get update`
- If Microsoft repo 404s for your `${VERSION_ID}`, temporarily pin to jammy (22.04):
  - `echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/22.04/prod jammy main" | sudo tee /etc/apt/sources.list.d/microsoft-prod.list >/dev/null && sudo apt-get update`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow, cross‑platform parity rules, and analyzer tips. In short: keep Linux and Windows behavior in parity, update both `overlay/scripts/make/linux` and `overlay/scripts/make/windows`, and keep the Makefile thin.

## License

Licensed under the [MIT License](LICENSE). You are free to use, modify, and distribute this project with attribution and without warranty.
