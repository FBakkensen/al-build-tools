# Changelog

## 2025-09-15

- feat(make): Entry scripts are now self-contained; removed `overlay/scripts/make/lib/`.
  - Affected scripts: `overlay/scripts/make/build.ps1`, `clean.ps1`, `show-config.ps1`, `show-analyzers.ps1`.
  - Rationale: Align with overlay payload principles (copy-only, minimal public surface).
  - Backward compatibility: If you previously dot-sourced `overlay/scripts/make/lib/common.ps1` or `json-parser.ps1` in your own repo, switch to invoking the public entrypoints via `make` instead. Helpers are not public API.
  - PowerShell requirements: All entry scripts declare `#requires -Version 7.2`, enable `Set-StrictMode -Version Latest`, and set `$ErrorActionPreference = 'Stop'`.

- docs(spec): Updated `specs/003-powershell-only-build/tasks.md` to mark T004 complete and remove references to the old `lib` paths.

