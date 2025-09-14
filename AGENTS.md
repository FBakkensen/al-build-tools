# Repository Guidelines

This repository provides a minimal, cross-platform AL build toolkit. Projects consume only the `overlay/` payload; the bootstrap script re-copies it for installs and updates. Keep entry points stable so updates remain drop-in.

## Project Structure & Module Organization
- `overlay/` - payload copied into target repos
  - `Makefile` - dispatches to platform scripts.
  - `scripts/make/linux/` -> `build.sh`, `clean.sh`, `show-config.sh`, `show-analyzers.sh`, `lib/*.sh`.
  - `scripts/make/windows/` -> `build.ps1`, `clean.ps1`, `show-config.ps1`, `show-analyzers.ps1`, `lib/*.ps1`.
  - `scripts/next-object-number.sh`, `scripts/next-object-number.ps1`.
  - `al.ruleset.json` - ruleset consumed by AL analyzers; analyzers are not bundled.
- `bootstrap/` - `install.ps1` (one-liner installer).
- `scripts/` - repo maintenance helpers (not copied).
- `specs/`, `templates/`, `memory/` - planning docs and templates.

## Build, Test, and Development Commands
- Install into a project (PowerShell 7+):
  - `iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .`
- Build from a consumer project:
  - Linux: `bash scripts/make/linux/build.sh [app]`
  - Windows: `pwsh -File scripts/make/windows/build.ps1 [app]`
- Shortcuts: `make build`, `make clean` (if `make` is available).
- Inspect config:
  - Linux: `bash scripts/make/linux/show-config.sh`
  - Windows: `pwsh -File scripts/make/windows/show-config.ps1`
- Note: The repo does not bundle analyzers; `show-analyzers.*` only reports tools installed on your machine.

## Coding Style & Naming Conventions
- Bash: `#!/usr/bin/env bash`, `set -euo pipefail`; portable tools; kebab-case filenames; lower_snake_case functions; 2-space indent.
- PowerShell (7+): `#requires -Version 7.0`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference='Stop'`; `param(...)`; PascalCase functions; mirror Linux behavior.
- Parity: every Linux task has a Windows peer with identical name/semantics; support `--verbose`/`VERBOSE` consistently.

## Testing Guidelines
- No repository-owned automated tests at present. If you add tests, prefer small POSIX shell scripts under `tests/contract/` and `tests/integration/`, avoid network calls, and ensure failures exit non-zero with a reason.

## Commit & Pull Request Guidelines
- Conventional Commits: `type(scope): summary` (e.g., `feat(build): ruleset support`, `fix(windows): PSSA param parsing`).
- Keep PRs focused; maintain Linux/Windows parity. Include motivation, key changes, local verification steps for both OSes, and linked issues. Avoid adding new network dependencies in `overlay/` scripts.

## Security & Configuration Tips
- Never hardcode secrets; read from environment variables. On Windows, use `-ExecutionPolicy Bypass` only for one-off local runs.

## Agent Behavior (Codex CLI)
- Do not run repository-changing Git operations or create PRs without explicit user instruction. Follow the paths/commands above and ask when uncertain.
