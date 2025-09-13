# Repository Guidelines

This repository provides a minimal, cross‑platform AL build toolkit. Projects consume only the `overlay/` payload; the bootstrap scripts re‑copy it for installs and updates. Keep entry points stable for consumers.

## Project Structure & Module Organization
- `overlay/` (copied into target repos)
  - `Makefile` → dispatches to platform scripts
  - `scripts/make/linux/` → `build.sh`, `clean.sh`, `show-config.sh`, `show-analyzers.sh`, `lib/*.sh`
  - `scripts/make/windows/` → `build.ps1`, `clean.ps1`, `show-config.ps1`, `show-analyzers.ps1`, `lib/*.ps1`
  - `scripts/next-object-number.sh` → find first available AL object number (Linux)
  - `.github/` → optional workflows/scripts projects may inherit
- `bootstrap/` → `install.sh`, `install.ps1` (one‑liner installers)
- `scripts/` → repo maintenance and CI helpers (not copied)
- `specs/` → feature specs; `tests/` → contract/integration shell tests; `templates/` → doc templates

## Build, Test, and Development Commands
- Install latest into a project
- Linux: `curl -fsSL https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.sh | bash -s -- --dest .`
  - Windows: `iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .`
- After copy (inside a project)
  - Linux: `bash scripts/make/linux/build.sh [app]` · Windows: `pwsh -File scripts/make/windows/build.ps1 [app]`
  - Optional: `make build`, `make clean`
- Local quality gate (this repo): `bash scripts/ci/run-static-analysis.sh`
- Run tests: `find tests -type f -name 'test_*.sh' -exec bash {} \;`

## Coding Style & Naming Conventions
- Bash: `#!/usr/bin/env bash`, `set -euo pipefail`; portable tools; clear errors; kebab‑case filenames; lower_snake_case functions.
- PowerShell (7+): `#requires -Version 7.0`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference='Stop'`; use `param(...)`; mirror Linux behavior; PascalCase functions.
- Parity: every task added under Linux must have a Windows peer with the same name and semantics; support `--verbose`/`VERBOSE` consistently.

## Testing Guidelines
- Tests are POSIX shell scripts under `tests/contract/` and `tests/integration/`; each exits non‑zero on failure and prints a reason.
- Cover success and failure paths (missing analyzers, syntax errors, JSON policy violations, timeout).
- Prefer small, isolated fixtures; avoid network calls in tests.

## Commit & Pull Request Guidelines
- Use Conventional Commits: `type(scope): summary` (e.g., `feat(build): ruleset support`, `fix(windows): PSSA param parsing`).
- Keep PRs focused; maintain Linux/Windows parity.
- Include: motivation, key changes, local verification steps for both OSes, and linked issues. Avoid introducing new network dependencies in `overlay/` scripts.

## Security & Configuration Tips
- Never hardcode secrets; read from environment variables.
- On Windows, use `-ExecutionPolicy Bypass` only for one‑off local runs.

## Agent Behavior (Codex CLI)
- Never run repository‑changing Git operations without explicit user instruction. This includes staging, committing, pushing, tagging, rebasing, or resetting.
- Never create a pull request without explicit user instruction.
- Do not suggest Git commands or propose opening a pull request unless the user explicitly asks for it.
- When the user explicitly instructs to perform any of these actions, carry them out precisely as requested and confirm results.
