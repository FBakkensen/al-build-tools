# Changelog

## Unreleased

- feat(ci): add Docker-based installer test harness `scripts/ci/test-bootstrap-install.ps1` with GitHub Actions workflow `.github/workflows/test-bootstrap-install.yml`.
  - Validates the bootstrap installer in clean Windows containers to prevent shipping broken releases.
  - Harness runs the actual `bootstrap/install.ps1` (no duplicated download logic) and captures transcript, summary JSON, and diagnostics.
  - Local reproducibility: Maintainers can run `pwsh -File scripts/ci/test-bootstrap-install.ps1 -Verbose` to test locally before CI.
  - Rich failure diagnostics: Exit codes (0/1/2/6), errorSummary classification, prerequisite tracking, step progression, and guard conditions in summary.json.
  - Artifacts uploaded on all runs (success/failure): install.transcript.txt, summary.json, provision.log (failure only).
  - Environment overrides: `ALBT_TEST_RELEASE_TAG`, `ALBT_TEST_IMAGE`, `ALBT_TEST_KEEP_CONTAINER`, `VERBOSE`, `GITHUB_TOKEN` (optional for rate limits).
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
