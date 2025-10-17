# Copilot Instructions for al-build-tools

Purpose: Provide AI coding agents with the minimal, stable knowledge needed to extend or maintain this repository safely and productively.

## 1. Core Model
- This repo publishes a versioned, copy-only "overlay" (contents of `overlay/`) plus a bootstrap installer (`bootstrap/install.ps1`).
- Consumers run the one-liner installer; it downloads a release asset and copies `overlay/*` into their repo. Every update overwrites those files. Therefore: treat everything under `overlay/` as a public, backwards‑compatibility contract.
- Internal maintenance scripts, tests, and planning docs live outside `overlay/` and must NOT leak into it.

## 2. Dual Build System Architecture
**Two orchestrators coexist:**
- **Invoke-Build** (`overlay/al.build.ps1`) - Primary, task-based PowerShell orchestrator. Entry point: `Invoke-Build <task>`. Uses three-tier config resolution (Param → Env → Default).
- **Make** (legacy wrapper) - Thin backwards-compatibility layer, delegates to PowerShell scripts with guard bypass.

**Always import `overlay/scripts/common.psm1`** for standardized utilities: `Get-ExitCode`, `Write-BuildMessage`, path expansion, JSON parsing, analyzer discovery, BC integration.

## 3. Public Contract (overlay/)
- Entry points: `overlay/al.build.ps1`, `overlay/scripts/make/*.ps1`, `overlay/al.ruleset.json`.
- Overlay scripts must be: (a) self‑contained (only import `common.psm1`, no repo-internal modules), (b) cross‑platform where paired (Windows/Linux), (c) free of secrets & unexpected network calls (only AL toolchain + declared downloads), (d) stable in name and primary flags.
- Never instruct users to modify overlay files; instead change them here and ship a new release.

## 4. Guard & Exit Code Policy
- PowerShell entry scripts in `overlay/scripts/make/*.ps1` refuse direct invocation unless `ALBT_VIA_MAKE=1`. Violations exit with code 2 (Guard).
- Standard exit codes from `Get-ExitCode`: 0 Success; 1 GeneralError; 2 Guard; 3 Analysis; 4 Contract; 5 Integration; 6 MissingTool. Preserve meanings when adding failure paths.
- **Use standardized output:** `Write-BuildMessage -Type <Info|Success|Warning|Error|Step|Detail>`, `Write-BuildHeader`, `Write-TaskHeader`.

## 5. AL Provisioning & Analyzer Resolution (Key Flows)
- **Compiler provisioning**: `download-compiler.ps1` resolves runtime from `app.json`, manages sentinel at `~/.bc-tool-cache/al/sentinel.json` (latest-only principle—no per-version caching), installs platform-specific dotnet tool (`microsoft.dynamics.businesscentral.development.tools[.linux|.osx]`).
- **Symbol cache**: `download-symbols.ps1` downloads NuGet packages into `~/.bc-symbol-cache/<publisher>/<name>/<id>/` and maintains `symbols.lock.json` manifest.
- **Analyzer discovery**: `Get-EnabledAnalyzerPath` from `common.psm1` reads `.vscode/settings.json` (modern: `al.codeAnalyzers` array; legacy: `al.enableCodeCop` flags). Supports built-in (CodeCop, UICop, AppSourceCop, PerTenantExtensionCop) and custom analyzers with path token expansion (`${analyzerFolder}`, `${workspaceFolder}`, etc.).
- Path expansion supports `~`, environment variables, and explicit overrides (`ALBT_TOOL_CACHE_ROOT`, `ALBT_SYMBOL_CACHE_ROOT`, `ALBT_ALC_PATH`, `AL_TOOL_VERSION`).

## 6. Coding Conventions
- PowerShell: `#requires -Version 7.2`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference='Stop'`, PascalCase function names.
- **Always use `common.psm1` functions**: Import with `Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking`.
- Keep logic inline inside overlay scripts (no `lib/` folders). Share via `common.psm1` only.
- Maintain Windows/Linux parity: if you alter a Windows script, update the corresponding Linux script or document exception.
- Use `Write-Verbose '[albt] ...'` for debug output; honor `$VerbosePreference`.

## 7. Static Analysis & Quality Gates
- CI enforces PSScriptAnalyzer using `PSScriptAnalyzerSettings.psd1`. Blocking rules (exit code 3): `PSAvoidUsingEmptyCatchBlock`, `PSAvoidAssignmentToAutomaticVariable`, `PSReviewUnusedParameter`, `PSUseShouldProcessForStateChangingFunctions`.
- Run locally: `Invoke-ScriptAnalyzer -Path overlay, bootstrap/install.ps1 -Recurse -Settings PSScriptAnalyzerSettings.psd1`.
- Prefer minimal, behavior‑neutral fixes (rename vars) over suppressions.

## 8. Testing & Development Workflow
- **Test suite**: Pester tests in `tests/contract/` (guard behavior, diagnostics, FR-* requirements) and `tests/integration/` (end-to-end). Run: `pwsh -NoProfile -File scripts/run-tests.ps1 -CI` or `Invoke-Pester -CI`.
- **CI-specific scripts**: `scripts/ci/` contains test harnesses (e.g., `test-bootstrap-install.ps1` validates installer in Docker containers). These delegate to overlay scripts and collect diagnostics.
- **Spec-driven development**: New features have specs in `specs/<number>-<name>/` with `plan.md`, `quickstart.md`, `spec.md`, `tasks.md`, `contracts/` (acceptance criteria, schemas). Reference spec directories when implementing features.

## 9. Release & Versioning
- Manual release workflow (GitHub Actions) packages ONLY `overlay/` into `overlay.zip` with SHA-256 manifest and semantic tag `vMAJOR.MINOR.PATCH`.
- Adding files to overlay increases public surface; justify necessity (execution-time vs internal). Avoid shipping dev-only artifacts.

## 10. Common Environment Overrides
- `ALBT_APP_DIR` (fallback app directory)
- `ALBT_VIA_MAKE=1` (guard bypass for direct script invocation in controlled contexts)
- `ALBT_ALC_PATH` / `ALBT_ALC_SHIM` (explicit compiler path)
- `AL_TOOL_VERSION` (compiler tool version selection)
- `ALBT_TOOL_CACHE_ROOT`, `ALBT_SYMBOL_CACHE_ROOT` (cache relocation)
- `VERBOSE=1` (enables `Write-Verbose`)
- `ALBT_TEST_*` (CI test harness overrides, e.g., `ALBT_TEST_RELEASE_TAG`, `ALBT_TEST_KEEP_CONTAINER`)

## 11. Safe Contribution Checklist (Agents)
Before opening a PR that changes overlay or bootstrap:
1. Does the change alter public script names, parameters, or exit codes? If yes, document migration or justify compatibility.
2. Run PSScriptAnalyzer locally and ensure zero blocking findings.
3. Confirm no new network endpoints other than existing feeds / official tool downloads.
4. Ensure Windows & Linux parity or explicitly document exception.
5. Keep changes minimal; use `common.psm1` for shared logic instead of creating new modules in overlay.
6. If adding compiler caching logic, remember: **latest-only principle**—single sentinel at `~/.bc-tool-cache/al/sentinel.json`, no per-version selection.

## 12. Examples
- Invoke-Build workflow: `Invoke-Build provision`, `Invoke-Build build`, `Invoke-Build test`
- Guarded direct script: `ALBT_VIA_MAKE=1 pwsh -File overlay/scripts/make/build.ps1 app`
- Show config: `Invoke-Build show-config` or `make show-config`
- Local analyzer run: `Invoke-ScriptAnalyzer -Path overlay -Settings PSScriptAnalyzerSettings.psd1`

## 13. Docker Windows Container Output Patterns
When working with Windows containers and PowerShell scripts that run inside them:
- **Critical**: Windows applications do NOT log to STDOUT/STDERR by default (unlike Linux). They log to ETW, Event Logs, or files.
- **Inside container scripts**: Use `Write-Host` for console output, followed by `[Console]::Out.Flush()` to ensure immediate streaming.
- **For subprocess calls inside containers**: Pipe output through `ForEach-Object { Write-Host $_; [Console]::Out.Flush() }` to ensure visibility. Example: `& git init 2>&1 | ForEach-Object { Write-Host "[git] $_"; [Console]::Out.Flush() }`
- **Host-side docker invocation**: Use `& docker run @args 2>&1 | ForEach-Object { Write-Host $_ }` to capture and stream output in real-time. Do NOT use `-it` flags for automated testing.
- **Always capture exit code**: `$exitCode = $LASTEXITCODE` immediately after docker command.
- Avoid `Start-Process` with output redirection (`RedirectStandardOutput/Error`) - it hides output from docker streams.
- Reference: https://learn.microsoft.com/en-us/virtualization/windowscontainers/troubleshooting#docker-container-logs

Keep instructions concise: update this file when contract rules, analyzer set, or provisioning flows change.
