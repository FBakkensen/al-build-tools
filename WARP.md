# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

Overview
- Purpose: This repo ships a self-contained AL (Microsoft Dynamics 365 Business Central) build “overlay” that can be copied into any AL project. Only overlay/ is intended to be consumed by downstream repos; everything else here exists to build, test, and maintain that payload.
- High-signal directories:
  - overlay/ — the product payload (Makefile wrapper; mirrored Linux/Windows build tooling; analyzer ruleset)
  - bootstrap/ — one-liner installers that copy overlay/* into a target repo
  - scripts/ci/ — static analysis quality gate for this repo
  - tests/ — contract and integration tests for the quality gate
  - .github/ — CI workflow and agent instructions (used by consumers and maintainers)

Common commands (this repo)
- Static analysis quality gate (bash)
  ```bash path=null start=null
  bash scripts/ci/run-static-analysis.sh
  ```
  - Useful env flags:
    - TIMEOUT_SECONDS=N — overall time budget for analysis (default 60)
    - INJECT_SLEEP=N — simulate long work (used in tests)
    - FORCE_NO_PSSA=1 — simulate missing PSScriptAnalyzer (PowerShell analyzer)

- Run the full test suite (bash)
  ```bash path=null start=null
  find tests -type f -name 'test_*.sh' -exec bash {} \;
  ```

- Run a single test (bash)
  ```bash path=null start=null
  bash tests/contract/test_shell_syntax.sh
  ```

- Optional: direct linters if installed
  - Shell scripts (Linux/macOS):
    ```bash path=null start=null
    shellcheck --version  # verify
    shellcheck overlay/**/*.sh scripts/**/*.sh
    ```
  - PowerShell (PS 7+, works on Linux/Windows):
    ```powershell path=null start=null
    pwsh -NoLogo -NoProfile -NonInteractive -Command "Invoke-ScriptAnalyzer -Path overlay,bootstrap"
    ```

Consumer usage (what overlay provides to downstream repos)
- Install/update overlay into a target repo
  - Linux/macOS:
    ```bash path=null start=null
    curl -fsSL https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.sh | bash -s -- --dest .
    ```
  - Windows (PowerShell 7+):
    ```powershell path=null start=null
    iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .
    ```
  - Re-run the same command to update; the installer re-copies overlay/*.

- After overlay is in a consumer repo (Linux; Windows has mirrored ps1 scripts):
  ```bash path=null start=null
  make build            # or: bash scripts/make/linux/build.sh [app]
  make clean            # or: bash scripts/make/linux/clean.sh [app]
  bash scripts/make/linux/show-config.sh [app]
  bash scripts/make/linux/show-analyzers.sh [app]
  ```
  Notes:
  - Defaults assume app directory is app with app/app.json present.
  - Environment toggles respected by build:
    - ALC_PATH — override AL compiler
    - RULESET_PATH — ruleset JSON (only if file exists and non-empty)
    - WARN_AS_ERROR (1/true/yes/on) — adds /warnaserror+

Big-picture architecture
- overlay/ (payload consumers receive)
  - Makefile — thin wrapper that dispatches to OS-specific scripts.
  - scripts/make/linux/ and scripts/make/windows/
    - build.sh|ps1 — compiles an AL app using the AL compiler (alc). Highlights:
      - Compiler discovery: prefers the highest ms-dynamics-smb.al-* VS Code extension; uses arch-aware paths (bin/linux-x64 or bin/linux-arm64) with fallbacks; honors ALC_PATH.
      - Analyzer resolution: reads .vscode/settings.json al.codeAnalyzers; expands tokens like ${analyzerFolder}, ${alExtensionPath}, ${workspaceFolder}; no implicit analyzer defaults when none are configured.
      - Output naming: {publisher}_{name}_{version}.app derived from app.json (jq on Linux; mirrored logic on Windows).
      - Optional ruleset: RULESET_PATH, only when file exists and is non-empty.
      - Warnings-as-errors: controlled by WARN_AS_ERROR.
    - show-config.sh|ps1 — prints key app.json and settings.json fields.
    - show-analyzers.sh|ps1 — prints enabled analyzer names and resolved DLL paths.
    - lib/common.* and lib/json-parser.* — shared helpers for path discovery, JSON (jq) parsing, analyzer token expansion, and compiler discovery.
  - al.ruleset.json — curated rules for AL analyzers; JSON validity is tested in this repo’s CI.

- bootstrap/ (installer)
  - install.sh | install.ps1 — download repo archive at a ref (default main), locate overlay/, and copy its contents into a destination. Update = install again.

- scripts/ci/run-static-analysis.sh (this repo’s quality gate)
  - What it does:
    - Fast bash syntax check over overlay/ and bootstrap/ scripts.
    - Optional shellcheck pass (advisory if tool missing).
    - PowerShell analysis via PSScriptAnalyzer (blocking when present; configurable for tests via FORCE_NO_PSSA=1).
    - JSON validation and policy checks (including duplicate keys via scripts/ci/json_dup_key_check.py and structural checks for overlay/al.ruleset.json).
    - Aggregates findings into “Blocking” vs “Advisory” categories and sets exit code accordingly.
  - Tests: see tests/contract/ and tests/integration/ for contract (clean/syntax/dup JSON/missing analyzer) and timeout simulation coverage.

- CI integration
  - .github/workflows/static-analysis.yml runs the quality gate on pull requests affecting overlay/** and bootstrap/**.

Important agent constraints (summarized from .github/copilot-instructions.md)
- Git safety when operating in this repo:
  - Do not run git commands unless explicitly asked to; prefer showing commands instead of running them.
  - If asked to run git: always use --no-pager, prefer non-interactive flags, avoid destructive operations, and never force-push unless the user explicitly includes it.
- Cross-platform parity requirement for overlay scripts: any new task added under overlay/scripts/make/linux must have a Windows peer with aligned arguments, output shape, and behavior.

Notes
- The overlay build expects a valid AL workspace (e.g., app/app.json) in consumer repos; running build locally here without such a workspace will fail by design.
- jq is required on Linux for JSON parsing paths in overlay scripts; PSScriptAnalyzer is recommended for Windows PowerShell analysis.

