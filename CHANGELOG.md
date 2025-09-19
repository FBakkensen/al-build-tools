# Changelog

## Unreleased

- docs(install): describe release-based installer flow, tag precedence, and rate limit expectations in README.
- docs(install): capture the migration to GitHub release assets and the expanded success/failure diagnostics.

## 2025-09-18

- tests(release): add unit coverage for version, hash manifest, and diff summary helpers; fix semver tag discovery edge cases.
- docs(release): document manual release workflow in README and cross-link quickstart guidance.
- chore(release): standardize ERROR-prefixed diagnostics across helper scripts and mark integration suite pending with opt-in flag.
- docs(release): captured local dry-run sample outputs in specs/006-manual-release-workflow/dry-run-example.md.

## 2025-09-15

- feat(make): Entry scripts are now self-contained; removed `overlay/scripts/make/lib/`.
  - Affected scripts: `overlay/scripts/make/build.ps1`, `clean.ps1`, `show-config.ps1`, `show-analyzers.ps1`.
  - Rationale: Align with overlay payload principles (copy-only, minimal public surface).
  - Backward compatibility: If you previously dot-sourced `overlay/scripts/make/lib/common.ps1` or `json-parser.ps1` in your own repo, switch to invoking the public entrypoints via `make` instead. Helpers are not public API.
  - PowerShell requirements: All entry scripts declare `#requires -Version 7.2`, enable `Set-StrictMode -Version Latest`, and set `$ErrorActionPreference = 'Stop'`.

- docs(spec): Updated `specs/003-powershell-only-build/tasks.md` to mark T004 complete and remove references to the old `lib` paths.
