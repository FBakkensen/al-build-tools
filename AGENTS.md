# Repository Guidelines

This repository provides mirrored Linux and Windows build tooling that teams copy into their projects via the `overlay/` folder. The bootstrap scripts install (and update) by re-copying `overlay/` into a target repo.

## Project Structure & Module Organization
- `overlay/` — payload copied into projects
  - `Makefile` — thin shim that dispatches to OS scripts
  - `scripts/make/linux/` — `build.sh`, `clean.sh`, `show-config.sh`, `show-analyzers.sh`, `next-object-number.sh`, `lib/common.sh`, `lib/json-parser.sh`
  - `scripts/make/windows/` — `build.ps1`, `clean.ps1`, `show-config.ps1`, `show-analyzers.ps1`, `lib/common.ps1`, `lib/json-parser.ps1`
- `bootstrap/` — one‑liner installers: `install.sh`, `install.ps1`

Avoid renaming or moving entry points under `overlay/`.

## Build, Test, and Development Commands
After bootstrapping into a project root:
- Linux
  - Build: `bash scripts/make/linux/build.sh`
  - Clean: `bash scripts/make/linux/clean.sh`
  - Inspect: `bash scripts/make/linux/show-config.sh` | `show-analyzers.sh`
- Windows (PowerShell 7+)
  - Build: `pwsh -File scripts/make/windows/build.ps1`
  - Clean: `pwsh -File scripts/make/windows/clean.ps1`
  - Inspect: `pwsh -File scripts/make/windows/show-config.ps1` | `show-analyzers.ps1`
- Make (optional on systems with `make`): `make build`, `make clean`

Commands are idempotent; reruns should not corrupt state.

## Coding Style & Naming Conventions
- Shell (bash): `#!/usr/bin/env bash`, `set -euo pipefail`; prefer portable utilities; emit helpful errors. Use functions and keep side effects scoped. Kebab‑case filenames.
- PowerShell: `#requires -Version 7.0`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference = 'Stop'`. Use `param(...)` and throw on failure. Mirror behavior with Linux scripts.
- Parity: add new tasks in both OS folders with the same name and semantics. Support `VERBOSE`/`--verbose` consistently.

## Testing Guidelines
- Manual checks: run Build/Clean on both OS in a sample repo; repeat to confirm idempotence. Review `show-config` output.
- Static analysis (optional but recommended): Shell scripts with `shellcheck`; PowerShell with `PSScriptAnalyzer`.

## Commit & Pull Request Guidelines
- Keep changes minimal and scoped; do not refactor unrelated code.
- Describe motivation, key changes, and any OS‑specific considerations.
- Provide basic verification steps for Linux and Windows; link issues.
- Do not introduce network calls or external deps without explicit direction.

## Security & Configuration Tips
- Read secrets from environment variables; never hardcode.
- Windows execution policy: use `-ExecutionPolicy Bypass` for one‑offs if needed.
