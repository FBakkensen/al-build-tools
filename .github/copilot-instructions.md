# Copilot Instructions for al-build-tools

Purpose: Provide AI coding agents with the minimal, stable knowledge needed to extend or maintain this repository safely and productively.

## 1. Core Model
- This repo publishes a versioned, copy-only "overlay" (contents of `overlay/`) plus a bootstrap installer (`bootstrap/install.ps1`).
- Consumers run the one-liner installer; it downloads a release asset and copies `overlay/*` into their repo. Every update overwrites those files. Therefore: treat everything under `overlay/` as a public, backwards‑compatibility contract.
- Internal maintenance scripts, tests, and planning docs live outside `overlay/` and must NOT leak into it.

## 2. Public Contract (overlay/)
- Entry points: `overlay/Makefile`, `overlay/scripts/make/*.ps1`, `overlay/scripts/next-object-number.*`, `overlay/al.ruleset.json`.
- Overlay scripts must be: (a) self‑contained (no importing repo-internal modules), (b) cross‑platform where paired (Windows/Unix parity), (c) free of secrets & unexpected network calls (only AL toolchain + declared downloads), (d) stable in name and primary flags.
- Never instruct users to modify overlay files; instead change them here and ship a new release.

## 3. Guard & Execution Model
- PowerShell entry scripts in `overlay/scripts/make/*.ps1` refuse direct invocation unless `ALBT_VIA_MAKE=1` (Makefile sets this automatically). Violations exit with code 2 (Guard).
- Standard exit codes (shared map): 0 Success; 1 GeneralError; 2 Guard; 3 Analysis; 4 Contract; 5 Integration; 6 MissingTool. Preserve meanings when adding new failure paths.

## 4. AL Provisioning & Analyzer Resolution (Key Flows)
- Compiler provisioning: `download-compiler.ps1` resolves runtime from `app.json`, manages a sentinel JSON under `~/.bc-tool-cache/al/<version or default>.json`, and installs/updates the appropriate platform-specific dotnet tool package (`microsoft.dynamics.businesscentral.development.tools[.linux|.osx]`).
- Symbol cache: `download-symbols.ps1` normalizes feed list, resolves required symbol package IDs (app + dependencies), downloads NuGet packages into `~/.bc-symbol-cache/<publisher>/<name>/<id>/`, and maintains `symbols.lock.json` manifest.
- Analyzer paths: `show-analyzers.ps1` / logic in `build.ps1` expands `${analyzerFolder}`, `${alExtensionPath}`, `${compilerRoot}`, `${workspaceFolder}` style tokens; must remain deterministic.
- Path expansion intentionally supports `~`, environment variables, and explicit overrides (`ALBT_TOOL_CACHE_ROOT`, `ALBT_SYMBOL_CACHE_ROOT`, `ALBT_ALC_PATH`, `AL_TOOL_VERSION`).

## 5. Coding Conventions
- PowerShell: `#requires -Version 7.2`, `Set-StrictMode -Version Latest`, `$ErrorActionPreference='Stop'`, PascalCase function names, verbose logging with `Write-Verbose '[albt] ...'` when value-add. Avoid assigning to automatic vars (`$HOME`, `$args`).
- Keep logic inline inside overlay scripts instead of creating reusable internal modules (avoids breaking self‑contained contract).
- Maintain Windows/Linux parity: if you add/alter functionality in a Windows script, update the corresponding bash script (and vice versa) or explain why parity does not apply.

## 6. Static Analysis & Quality Gates
- CI enforces PSScriptAnalyzer using `PSScriptAnalyzerSettings.psd1`. Blocking rules currently include: `PSAvoidUsingEmptyCatchBlock`, `PSAvoidAssignmentToAutomaticVariable`, `PSReviewUnusedParameter`, `PSUseShouldProcessForStateChangingFunctions`.
- Run locally: `Invoke-ScriptAnalyzer -Path overlay, bootstrap/install.ps1 -Recurse -Settings PSScriptAnalyzerSettings.psd1`.
- When fixing analyzer findings, prefer minimal, behavior‑neutral edits (e.g., rename local vars instead of suppressing rules).

## 7. Release & Versioning Notes
- Manual release workflow (GitHub Actions) packages ONLY the `overlay/` directory into `overlay.zip` and publishes with semantic tag `vMAJOR.MINOR.PATCH`.
- Adding files to overlay increases surface area; justify necessity (execution-time required vs internal concern). Avoid shipping dev-only artifacts.

## 8. Common Environment Overrides
- `ALBT_APP_DIR` (fallback when script parameter omitted)
- `ALBT_VIA_MAKE=1` (guard bypass when calling scripts directly in controlled contexts)
- `ALBT_ALC_PATH` / `ALBT_ALC_SHIM` (explicit compiler path override)
- `AL_TOOL_VERSION` (select specific compiler tool version)
- `ALBT_TOOL_CACHE_ROOT`, `ALBT_SYMBOL_CACHE_ROOT` (cache relocation)
- `VERBOSE=1` (enables `Write-Verbose`)

## 9. Safe Contribution Checklist (Agents)
Before opening a PR that changes overlay or bootstrap:
1. Does the change alter public script names, parameters, or exit codes? If yes, document migration or justify compatibility.
2. Run PSScriptAnalyzer locally and ensure zero blocking findings.
3. Confirm no new network endpoints other than existing feeds / official tool downloads.
4. Ensure Windows & Linux parity or explicitly document exception.
5. Keep changes minimal; avoid introducing shared helper modules into overlay.

## 10. Examples
- Guarded direct build: `ALBT_VIA_MAKE=1 pwsh -File overlay/scripts/make/build.ps1 app`
- Analyzer listing after provisioning: `make show-analyzers`
- Local analyzer run (repo root): `Invoke-ScriptAnalyzer -Path overlay -Settings PSScriptAnalyzerSettings.psd1`

## 11. Out of Scope for Overlay
- Pester modules, CI harness, large helper frameworks, secrets, experimental feature toggles.

Keep instructions concise: update this file when contract rules, analyzer set, or provisioning flows change.
