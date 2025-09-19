# AL Build Tools (overlay bootstrap)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Contributions welcome](https://img.shields.io/badge/Contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

A minimal, cross-platform build toolkit for Microsoft AL projects with a dead-simple bootstrap. It is designed to be dropped into an existing git repo and updated by running the same single command again.

Install and update are the same: the bootstrap resolves a published GitHub release, downloads its overlay ZIP asset (it prefers `overlay.zip` and falls back to `al-build-tools-<tag>.zip` for legacy releases), and copies everything from the archive’s `overlay/` folder into your project. Because you’re in git, you review and commit changes as you like.

## Quick Start (Install Latest Release)

- PowerShell 7+ for installer (Windows, macOS, Linux)
  ```
  iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .
  ```

Re-run the same command any time to update — it re-downloads the chosen release asset and re-copies `overlay/*` over your working tree.

### Release Selection Order

The installer always targets GitHub releases (branch zipballs are no longer used):

- `-Ref <tag>` command parameter wins when provided.
- Otherwise `ALBT_RELEASE` environment variable selects the release.
- Otherwise the latest published (non-draft, non-prerelease) release is chosen.

If `ALBT_RELEASE` influences selection, the installer emits a verbose note so automation logs capture the override.

Examples:

- `pwsh -File bootstrap/install.ps1 -Dest . -Ref v1.2.3`
- `$env:ALBT_RELEASE = 'v1.2.2'; pwsh -File bootstrap/install.ps1 -Dest .`

### Rate Limits

GitHub’s unauthenticated REST API limit is 60 requests per hour per source IP. Heavy automation should provide a GitHub token (for example `GITHUB_TOKEN`) in the environment before invoking the installer to benefit from higher limits.

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

The installer contract (FR-012) documents the behaviors enforced by the automated suites so contributors know what must remain stable. Coverage lives in:
- `tests/contract/Install.*.Tests.ps1` — guard rails and download diagnostics (FR-003, FR-004, FR-008, FR-014, FR-015, FR-020, FR-023, FR-024).
- `tests/integration/Install.*.Tests.ps1` — success, idempotence, parity, and performance flows (FR-001, FR-002, FR-005, FR-006, FR-010, FR-017-FR-019, FR-022, FR-025).
- `tests/_install/Assert-Install.psm1` — shared helpers that lock diagnostic formats and hash verification (FR-009, FR-021).

Key expectations that must stay stable:
- Guard rails: rejects non-git destinations, dirty working trees, unsupported PowerShell, unknown parameters, and restricted/denied writes. Each failure emits `[install] guard <Reason>` and exits 10 (guards) or 30 (permission scope).
- Download diagnostics: acquisition failures log a single `[install] download failure ... category=<NetworkUnavailable|NotFound|CorruptArchive|Timeout|Unknown>` line, exit 20, and must leave the destination unchanged.
- Temp workspace: emits `[install] temp workspace="..."`, which must live under the system temp root and be cleaned up after every run.
- Success path: success logs `[install] success ref="..." overlay="..." duration=<seconds>` and a second run must restore overlay file hashes (idempotence).
- Step telemetry: `[install] step index=... name=...` stays stable to keep parity and performance checks meaningful across platforms.

When updating `bootstrap/install.ps1`, adjust `specs/005-add-tests-for/traceability.md` if coverage moves and run `pwsh -File scripts/run-tests.ps1 -CI`; CI replays the same contract on Windows and Ubuntu.

## Manual Release Workflow

- Trigger the `Manual Overlay Release` GitHub Actions workflow whenever you are ready to ship a tagged overlay-only archive.
- Provide `version`, `summary`, and `dry_run` inputs; the workflow enforces semantic version monotonicity, tag uniqueness, and overlay cleanliness before packaging.
- Run a dry pass (`dry_run=true`) to preview the staged overlay file list, SHA-256 manifest, metadata JSON block, and diff summary without creating a tag or release.
- Run a publish pass (`dry_run=false`) to create the `vMAJOR.MINOR.PATCH` tag, upload the overlay ZIP (`overlay.zip` going forward; legacy releases use `al-build-tools-<version>.zip`), and embed both the manifest and metadata block in the release notes.
- Consumers can verify archives by expanding the ZIP, running `sha256sum -c manifest.sha256.txt` (or the PowerShell equivalent), and matching the `root_hash` and `commit` fields reported in the release metadata.
- For step-by-step maintainer and consumer checklists, see [specs/006-manual-release-workflow/quickstart.md](specs/006-manual-release-workflow/quickstart.md).


## How It Works

1. Resolves the effective release tag using the selection order above.
2. Downloads the overlay ZIP asset (`overlay.zip` when present, otherwise `al-build-tools-<tag>.zip`) from the chosen GitHub release (using the releases API).
3. Copies `overlay/*` into your destination directory, overwriting existing files.
4. No state files and no backups — use git to review and commit changes.

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
