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
  - Any OS‑specific considerations (Linux/Windows) and manual verification notes.

Development Guidelines
----------------------
- Cross‑platform parity: when adding a new task, provide both a Linux (`.sh`) and Windows (PowerShell, `.ps1`) implementation with the same behavior.
- Do not break existing entry points under `overlay/` (see `AGENTS.md`).
- Shell (Linux):
  - Use `#!/usr/bin/env bash` and `set -euo pipefail`.
  - Prefer portable Bash; check for required external tools and emit helpful errors.
- PowerShell (Windows):
  - Require PowerShell 7+ with `#requires -Version 7.0`.
  - Use `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.
- Logging & verbosity: support a `--verbose`/`VERBOSE` option mirrored across platforms.
- JSON & config: reuse `overlay/scripts/make/*/lib/json-parser.*` helpers rather than duplicating parsing logic.

Local Checks (Recommended)
--------------------------
- Linux:
  - Run: `bash overlay/scripts/make/linux/show-analyzers.sh` to see recommended analyzers.
  - If available, run `shellcheck` on new/changed `.sh` files.
- Windows:
  - Run: `pwsh -File overlay/scripts/make/windows/show-analyzers.ps1`.
  - If available, run `PSScriptAnalyzer` on new/changed `.ps1` files.

Static Analysis Quality Gate
----------------------------
Pull requests that modify files under `overlay/` or `bootstrap/` are checked by a static analysis quality gate in GitHub Actions. Findings appear as GitHub annotations and as a category summary.

Run locally (Linux):
```
bash scripts/ci/run-static-analysis.sh
```

Categories and exit behavior:
- Blocking: Syntax, Security, Configuration, Policy
- Advisory (non-blocking): Style

Examples:
- Configuration (blocking): invalid JSON, duplicate JSON keys, missing PSScriptAnalyzer, timeout.
- Policy (blocking): ruleset schema violations in `overlay/al.ruleset.json` (invalid top-level keys, duplicate rule ids, invalid actions).
- Syntax/Security: shellcheck/PowerShell analyzer diagnostics. Note: shellcheck warnings are treated as advisory Style; PowerShell warnings map to Security and can block.

Useful environment toggles (for development/testing):
- TIMEOUT_SECONDS=N (default 60)
- INJECT_SLEEP=N (simulate long work for timeout path)
- FORCE_NO_PSSA=1 (simulate missing PSScriptAnalyzer)

Line Endings and Encoding
-------------------------
- Use UTF‑8.
- Shell scripts (`*.sh`) use LF; PowerShell scripts (`*.ps1`) use CRLF. See `.gitattributes` in `AGENTS.md` for guidance.

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

