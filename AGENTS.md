# Repository Guidelines

This repository provides a minimal, cross-platform AL build toolkit. Projects consume only the `overlay/` payload; the bootstrap script re-copies it for installs and updates. Keep entry points stable so updates remain drop-in.

## Project Structure & Module Organization
### Overlay Payload Principles
The `overlay/` directory is a versioned, copy-only payload shipped verbatim into consumer repositories by the bootstrap/install process.

Core rules:
1. Ephemeral: A subsequent install/update will overwrite any local edits inside a consumer project's copied overlay. Never instruct consumers to modify overlay files directly.
2. Minimal Surface: Only ship stable, user-facing entry points (e.g., `Makefile`, platform build/clean/show scripts, next-object-number helpers, ruleset). Do NOT place internal helpers, test harnesses, CI-only config, or experimental scripts here.
3. Self‑Contained Scripts: Each shipped script must run without depending on repository-internal (non-overlay) modules. If logic would require shared helpers, either inline it (small) or keep it internal and exclude from overlay.
4. No Secrets / Network: Overlay scripts must not embed secrets or perform network calls (except standard AL toolchain behaviors invoked by the user).
5. Backward Compatibility: Entry point names and basic flags should remain stable; deprecations require a documented migration note.
6. Explicit Scope: Anything under `overlay/` is considered public contract surface; internal refactors must not break externally observable behavior without versioned communication.
7. Analysis & Tests Internal: Static analysis configurations, Pester tests, and CI orchestration stay outside `overlay/` (they run in this toolkit repo only).
8. Keep Noise Out: Avoid shipping editor configs, dev-only scripts, or large assets. Every additional file increases update friction.

When contributing: If you are about to add a new file under `overlay/`, ask: (a) Is this required by end users at execution time? (b) Can the responsibility stay internal? Only proceed if both answers justify public exposure.

- `overlay/` - payload copied into target repos
  - `Makefile` - dispatches to platform scripts.
  - `scripts/make/linux/` -> `build.sh`, `clean.sh`, `show-config.sh`, `show-analyzers.sh`, `lib/*.sh` (legacy; slated for consolidation into inline logic).
  - `scripts/make/windows/` -> `build.ps1`, `clean.ps1`, `show-config.ps1`, `show-analyzers.ps1`, `lib/*.ps1` (legacy; slated for consolidation / removal of lib subfolders).
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

## ⚠️ CRITICAL: Repository Safety Warning
**NEVER run `bootstrap/install.ps1` directly in this repository.** 

Running the installer in the source repository will:
- Pollute the working directory with overlay files
- Create untracked files that interfere with git operations
- Potentially overwrite local development files
- Make the repository dirty and complicate testing

**Safe alternatives:**
- Use the test harness in `tests/` directory which creates isolated workspaces
- Run installer in a separate, disposable test directory
- Use the archive server test utilities that provide controlled environments

The installer is designed to be run in **consumer repositories**, not in the development repository.

