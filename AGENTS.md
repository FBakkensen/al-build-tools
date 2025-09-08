# AGENTS.md

Repository-wide agent guidelines for this template build project.

## Scope

These instructions apply to the entire repository. They exist to help human contributors and AI agents (e.g., GitHub Copilot Agents, Codex CLI) work consistently when adding or changing build logic across Linux and Windows.

## Purpose

This repo is a template for setting up local build workflows on Linux and Windows. It provides mirrored platform scripts and a thin `Makefile` shim so teams can adopt the same structure in their projects.

Deployment model: install = update. A bootstrap script copies only the contents of `overlay/` into a target git repository. Re-running the same one‑liner updates by re-copying from `overlay/`.

## Bootstrap (copy/paste)

- Linux/macOS

```
curl -fsSL https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.sh | bash -s -- --dest .
```

- Windows (PowerShell 7+)

```
iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .
```

Notes:
- The commands copy `overlay/*` into the destination (default `.`) and overwrite existing files. No backups are made; use git to review/commit.
- You can override branch/tag with `--ref`/`-Ref` and the repo with `--url`/`-Url`.

## Quick Start

After bootstrapping into a project, these are the standard entry points that become available in that project’s root:

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
  - If `make` is available, `make` targets should dispatch to the OS scripts. Prefer calling the platform scripts directly on Windows where `make` may not be installed.

## Repo Layout (entry points)

- `overlay/` — the payload that gets copied into projects
  - `overlay/Makefile` — convenience wrapper that delegates to platform-specific scripts.
  - `overlay/scripts/make/linux/` — Linux build tasks
    - `build.sh`, `clean.sh`, `show-config.sh`, `show-analyzers.sh`, `next-object-number.sh`
    - `lib/common.sh`, `lib/json-parser.sh`
  - `overlay/scripts/make/windows/` — Windows build tasks (PowerShell 7+)
    - `build.ps1`, `clean.ps1`, `show-config.ps1`, `show-analyzers.ps1`
    - `lib/common.ps1`, `lib/json-parser.ps1`
- `bootstrap/` — one-liner installers that copy `overlay/` into a target repo
  - `bootstrap/install.sh` (Linux/macOS)
  - `bootstrap/install.ps1` (Windows, PowerShell 7+)

Use the `lib/*` helpers instead of re-implementing common functionality (logging, JSON parsing, argument handling, etc.). Keep behavior in parity across platforms.

## Design Rules

1. Cross-platform parity
   - When introducing a new task, add both a Linux `.sh` and Windows `.ps1` implementation with the same file name and semantics.
   - If a task is inherently OS-specific, document why and guard its usage (e.g., in the `Makefile` or caller script).

2. Do not break entry points
   - Do not rename or move existing scripts within `overlay/` without explicit approval. Update `overlay/Makefile` only to dispatch to these scripts.

3. Shell standards (Linux)
   - Shebang: `#!/usr/bin/env bash`
   - Set strict mode at top of file: `set -euo pipefail` and `IFS=$'\n\t'` when appropriate.
   - Prefer portable Bash over GNU-only utilities when feasible; if you depend on a specific tool, check for it and emit a helpful error.
   - Use functions; keep side effects scoped; write to a single output directory passed via env/flags when possible.

4. PowerShell standards (Windows)
   - Require PowerShell 7+: add `#requires -Version 7.0` at the top.
   - `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` near the top.
   - Use `param(...)` for inputs; prefer `Write-Output`/`Write-Host` for logs, `throw` for errors, and return non-zero exit codes when appropriate.

5. Logging & verbosity
   - Support a `VERBOSE` or `--verbose` flag that increases log detail. Mirror the behavior across `.sh` and `.ps1` scripts.

6. Idempotence
   - Re-running `build` or `clean` should not corrupt state. Prefer creating/cleaning well-defined directories and files.

7. JSON & config
   - Reuse `lib/json-parser.sh` / `lib/json-parser.ps1` for reading configuration. Keep the schema and defaulting logic platform-agnostic.

## Adding or Modifying Tasks

1. Implement both sides
   - Add `overlay/scripts/make/linux/<task>.sh` and `overlay/scripts/make/windows/<task>.ps1` with equivalent behavior.

2. Wire the `Makefile`
   - Dispatch to the platform script based on OS detection (or provide targets that directly call the platform scripts). Keep logic minimal in `overlay/Makefile` and rich in the scripts.

3. Reuse helpers
   - Prefer common helpers in `lib/` over duplicating logic. If a helper is missing, introduce it in both `overlay/scripts/make/linux/lib` and `overlay/scripts/make/windows/lib` with consistent naming and behavior.

4. Document the task
   - Add a short usage header at the top of each script. If the task is commonly used, mention it in this file during the next edit.

## Expectations for AI Agents (Copilot, Codex CLI)

- Read and honor this AGENTS.md before making changes.
- Keep diffs minimal and focused. Do not refactor unrelated code.
- Update or create both Linux and Windows scripts for new tasks.
- Prefer `apply_patch` with small, reviewable changes. Include rationale in commit messages (if committing).
- Do not introduce network calls or external dependencies without explicit direction.
- Avoid destructive changes. If cleanup is required, make it explicit and confirm first.
- When OS-specific behaviors are required, clearly guard and document them.

### Codex/Copilot Agent Workflow Hints

- Propose a brief plan, then implement in small steps.
- Explain what you are about to do before writing files.
- If scripts require secrets or tokens, read from environment variables and never hardcode them.

## Environment & Tooling Notes

- PowerShell 7 installation may be required on Windows machines that only ship with Windows PowerShell 5.1.
- Windows execution policy: if blocked, run with `-ExecutionPolicy Bypass` or set the policy per-process.
- Bash: assume a reasonably recent Bash (v4+). If features require newer versions, check and warn.

## Line Endings and Encoding

Use UTF-8 across the repo. Normalize endings via `.gitattributes` to avoid cross-platform noise.

Example `.gitattributes` recommendations:

```
# Shell scripts use LF
*.sh text eol=lf

# PowerShell scripts use CRLF for Windows editors
*.ps1 text eol=crlf

# Makefiles and JSON
Makefile text eol=lf
*.json text eol=lf
```

## Commit & PR Guidelines

- Describe motivation, key changes, and any OS-specific considerations.
- Include basic manual verification steps for both Linux and Windows.
- Keep each change scoped; prefer multiple small PRs to one large PR.

## Troubleshooting

- Windows: “running scripts is disabled on this system” — start PowerShell as Administrator and run: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` or use `-ExecutionPolicy Bypass` for one-off runs.
- Linux: missing tools — ensure required CLI tools are installed (document any hard dependencies at the top of the script and exit with a helpful message if absent).
- Parity drift — if behavior diverges between platforms, open an issue and restore parity as soon as possible.

---

If anything in this guide becomes outdated as the build evolves, update this file in the same PR as your changes.
