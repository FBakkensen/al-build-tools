Contributing to al-build-tools
================================

Thanks for your interest in improving this project! This repository is a template for cross‑platform build tooling. Contributions are welcome from individuals and organizations.

License and Contributor Terms
-----------------------------
- This project is licensed under the MIT License (see `LICENSE`).
- By submitting a contribution (pull request, patch, or suggestion), you agree that your contribution will be licensed under the MIT License.

How to Contribute
-----------------
- Fork the repo and create your feature branch from `main`.
- Branch naming: use a short, descriptive prefix, e.g. `feat/…`, `fix/…`, `docs/…`, `chore/…`.
- Make focused changes with small, reviewable commits. Reference issues in commit messages when applicable.
- Open a pull request against `main` with:
  - A clear description of motivation and changes.
  - Any OS‑specific considerations (Windows/Linux under PowerShell 7.2+) and manual verification notes.
  - Conventional Commits formatting for titles (e.g., `feat(build): add guard policy`).

Development Guidelines
----------------------
- PowerShell‑only entrypoints: build/clean/show-* live under `overlay/scripts/make/*.ps1` and must remain self‑contained (no `lib/` folders).
- Cross‑OS support: scripts run on Windows and Linux using PowerShell 7.2+; avoid OS‑specific assumptions.
- Stability: do not break existing entry points under `overlay/` (see `AGENTS.md`).
- PowerShell:
  - Require PowerShell 7.2+ with `#requires -Version 7.2` in overlay scripts.
  - Use `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.
- Guard policy: entrypoints are intended to run via `make` and enforce `ALBT_VIA_MAKE` (exit code 2 when missing). Keep this guard in place for consistency.
- Logging & verbosity: support verbose output via `Write-Verbose`; honor `-Verbose` and `VERBOSE=1`.
- JSON & config: keep parsing inline in entrypoints; avoid introducing shared helpers into the overlay.

Local Checks (Recommended)
--------------------------
- Show analyzers discovered for a project: `make show-analyzers` (or `ALBT_VIA_MAKE=1 pwsh -File overlay/scripts/make/show-analyzers.ps1 app`).
- Static analysis (PowerShell):
  - `Set-PSRepository -Name PSGallery -InstallationPolicy Trusted`
  - `Install-Module PSScriptAnalyzer -Scope CurrentUser -Force`
  - `Invoke-ScriptAnalyzer -Path overlay, bootstrap/install.ps1 -Recurse -Settings PSScriptAnalyzerSettings.psd1`
- Tests (Pester):
  - `pwsh -File scripts/run-tests.ps1 -CI`
  - Or `Invoke-Pester -CI -Path tests/contract` and `Invoke-Pester -CI -Path tests/integration`

Static Analysis Quality Gate
----------------------------
Pull requests that modify files under `overlay/` or `bootstrap/` run PSScriptAnalyzer in GitHub Actions (Windows and Ubuntu). Blocking errors fail the job with exit code 3 using the repo `PSScriptAnalyzerSettings.psd1`. Findings appear as GitHub annotations and a summary.

Categories and exit behavior:
- Blocking: Syntax, Security, Configuration, Policy
- Advisory (non-blocking): Style

Examples:
- Configuration (blocking): invalid JSON, duplicate JSON keys, missing PSScriptAnalyzer, timeout.
- Policy (blocking): ruleset schema violations in `overlay/al.ruleset.json` (invalid top-level keys, duplicate rule ids, invalid actions).
- Syntax/Security: PowerShell analyzer diagnostics (Error severity blocks).

Useful environment toggles (for development/testing):
- TIMEOUT_SECONDS=N (default 60)
- INJECT_SLEEP=N (simulate long work for timeout path)
- FORCE_NO_PSSA=1 (simulate missing PSScriptAnalyzer)

Line Endings and Encoding
-------------------------
- Use UTF‑8.
- PowerShell scripts (`*.ps1`) use CRLF. See `.gitattributes` in `AGENTS.md` for guidance.

Security & Dependencies
-----------------------
- Do not add network calls or new external dependencies without discussion.
- If credentials are needed for a task, read them from environment variables and never commit secrets.

Code Review
-----------
- Pull requests are reviewed by the code owners listed in `.github/CODEOWNERS`.
- Address feedback promptly; keep changes small for faster review.

Governance
----------
- For large changes or design proposals, open an issue first to discuss goals and approach.

Thank you for contributing!
