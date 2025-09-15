# Inventory: Windows PowerShell scripts and helpers (pre-relocation)

Scope: overlay/scripts/make/windows/*.ps1 and overlay/scripts/make/windows/lib/*.ps1
Date: 2025-09-15

## Entry scripts

### build.ps1
- Path: overlay/scripts/make/windows/build.ps1
- Signature: `param([string]$AppDir = "app")`
- Imports: `lib/common.ps1`, `lib/json-parser.ps1`
- Behavior:
  - Verifies helper function `Get-EnabledAnalyzerPaths` is available post-import.
  - Locates AL compiler (`alc.exe`) via highest AL VS Code extension found; exits if not found.
  - Computes output `.app` path from `app.json` and package cache path (`.alpackages`).
  - Removes pre-existing output file or conflicting directory with same name.
  - Discovers enabled analyzer DLLs from `.vscode/settings.json` and prints them (or a "No analyzers" notice).
  - Supports optional ruleset via `RULESET_PATH` env; warns and skips if invalid/empty.
  - Supports `WARN_AS_ERROR` env to append `/warnaserror+`.
  - Invokes `alc.exe` with: `/project:$AppDir /out:<output> /packagecachepath:<cache> /parallel+` plus any analyzers and ruleset.
  - Emits success/failure message; returns compiler exit code transparently.
- Exit codes (implicit):
  - 0 on successful compilation.
  - Non-zero passthrough from `alc.exe` on compilation errors.
  - 1 on internal early failures (missing compiler, bad output resolution, removal failures).

### clean.ps1
- Path: overlay/scripts/make/windows/clean.ps1
- Signature: `param([string]$AppDir)`
- Imports: `lib/common.ps1`, `lib/json-parser.ps1`
- Behavior:
  - Computes output `.app` path from `app.json` and removes it if present; prints status either way.
- Exit codes (implicit):
  - Always exits 0 (both when artifact removed and when nothing to clean).

### show-config.ps1
- Path: overlay/scripts/make/windows/show-config.ps1
- Signature: `param([string]$AppDir)`
- Imports: `lib/common.ps1`, `lib/json-parser.ps1`
- Behavior:
  - Reads `app.json`; prints Name, Publisher, Version. If missing/invalid, writes an error message.
  - Reads `.vscode/settings.json`; prints analyzer entries or `(none)`; warns if settings file missing.
- Exit codes (implicit):
  - Script ends with `exit 0`, even if an error was written when `app.json` is missing/invalid.

### show-analyzers.ps1
- Path: overlay/scripts/make/windows/show-analyzers.ps1
- Signature: `param([string]$AppDir)`
- Imports: `lib/common.ps1`, `lib/json-parser.ps1`
- Behavior:
  - Prints enabled analyzer IDs from settings.
  - Resolves and prints analyzer DLL paths (token and wildcard resolution); warns if none found.
- Exit codes (implicit):
  - Always exits 0.

## Helper libraries

### lib/common.ps1
- Functions:
  - `Get-AppJsonPath($AppDir)`: Resolve `app.json` from `$AppDir` or CWD.
  - `Get-SettingsJsonPath($AppDir)`: Resolve `.vscode/settings.json` from `$AppDir` or CWD.
  - `Get-OutputPath($AppDir)`: Build output `.app` filename from `app.json` (defaults: Publisher=FBakkensen, Name=CopilotAllTablesAndFields, Version=1.0.0.0) and place it under `$AppDir`.
  - `Get-PackageCachePath($AppDir)`: Return `$AppDir/.alpackages`.
  - `Write-ErrorAndExit($Message)`: Write-Error then `exit 1`.
  - `Get-HighestVersionALExtension()`: Search VS Code extension roots for `ms-dynamics-smb.al-*`, pick highest version (Insiders preferred on tie).
  - `Get-ALCompilerPath($AppDir)`: Return full path to `alc.exe` under the chosen AL extension.
  - `Get-EnabledAnalyzerPaths($AppDir)`: Parse settings for analyzers (new `al.codeAnalyzers` or legacy booleans); resolve tokens `${analyzerFolder}`, `${alExtensionPath}`, `${workspaceFolder}`, `${appDir}`; expand env vars and `~`; accept directories and wildcards; return distinct DLL file paths. Does not enable defaults when none configured.

### lib/json-parser.ps1
- Functions:
  - `Get-AppJsonObject($AppDir)`: Load and return `app.json` object or `$null`.
  - `Get-SettingsJsonObject($AppDir)`: Load and return `.vscode/settings.json` object or `$null`.
  - `Get-EnabledAnalyzer($AppDir)`: Return first analyzer from `al.codeAnalyzers` or `$null`.
  - `Get-EnabledAnalyzers($AppDir)`: Return analyzer array or empty array when none configured.

## Notes and gaps relative to upcoming guard/exit-code standardization
- No guard (`ALBT_VIA_MAKE`) present; scripts are directly invocable.
- No standardized exit code map comment block; codes are ad hoc (build returns `alc.exe` code; others always `0`).
- `show-config.ps1` writes an error if `app.json` invalid/missing but still exits `0`.

## Acceptance
- This inventory captures parameters, current behaviors, and implicit exit codes for build/clean/show-* and enumerates helper functions in lib/.
