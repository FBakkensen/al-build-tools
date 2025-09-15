# Quickstart: PowerShell-Only Build Toolkit (Relocated Scripts)

This guide shows how to use the consolidated PowerShell build scripts guarded by `make`. Existing Windows PowerShell scripts were RELOCATED to a neutral folder and Bash scripts were REMOVED—there are no per‑OS script variants now. Only the minimal script set under `overlay/scripts` is copied into consumer projects; internal tests and analyzer configuration remain in this repository.

## Prerequisites
- PowerShell 7.2+ available as `pwsh`
- GNU make installed (`make --version` shows GNU)
- Required modules installed (local development):
  - PSScriptAnalyzer
  - Pester (for running tests locally)

Install modules (example):
```
pwsh -NoLogo -Command "Install-Module PSScriptAnalyzer -Scope CurrentUser; Install-Module Pester -Scope CurrentUser"
```

## Core Commands (via make)
| Action | Command | Notes |
|--------|---------|-------|
| Build | `make build` | Guarded (C1); uses relocated PowerShell script; honors C2–C5, C8–C10 |
| Clean | `make clean` | Guarded (C1); idempotent artifact removal (C10) |
| Show Config | `make show-config` | Guarded; emits stable keys (C7) |
| Show Analyzers | `make show-analyzers` | Guarded; analyzer enumeration (C5,C6) |
| Next Object Number | `pwsh overlay/scripts/next-object-number.ps1 <Type>` | Unguarded utility (C11) |

Guarded targets MUST be invoked through `make` (C1). Direct guarded script execution returns exit code 2 with guidance (C9). The direct utility is exempt (C11). There is no longer any `linux/` or `windows/` subfolder—scripts are unified.

## Help & Guard Behavior
Attempting to run a guarded script directly:
```
pwsh overlay/scripts/make/build.ps1
# -> Exit 2, message includes: Run via make (e.g., make build)
```
Help when unguarded:
```
pwsh overlay/scripts/make/build.ps1 -?
# -> Same guard exit (2) + stub redirect to `make build -?` (future enhancement) or documentation.
```
Full help (after guard satisfied) TBD (implemented inside each script with standard `-? -h --help`).

## Verbosity
Set either flag or environment variable:
```
make build VERBOSE=1
# or
make build -- -Verbose   # if pass-through pattern adopted
```
Behavior: If `VERBOSE=1`, treat as if `-Verbose` passed; combine with PowerShell intrinsic `-Verbose` for consistency.

## Configuration Variables (C2, C3, C4)
Environment variables exported by `make` influence build behavior:
| Variable | Purpose | Behavior |
|----------|---------|----------|
| `WARN_AS_ERROR` | Promote warnings to errors | Values 1/true/yes/on (case-insensitive) enable (C4) |
| `RULESET_PATH` | Optional ruleset file | Passed only if file exists & non-empty (C3) |

Scripts do not mutate these values; they are read-only inputs (C2).

## Analyzer Discovery (C5, C6)
Analyzers are resolved from `.vscode/settings.json` keys:
```
"al.enableCodeAnalysis": true,
"al.codeAnalyzers": [ "path/to/Analyzer1.dll", "path/to/Analyzer2.dll" ]
```
Missing file, invalid JSON, disabled flag, or missing DLL paths → build continues with an empty analyzer set (C5). `make show-analyzers` reports either each valid path or the message `No analyzers found` (C6).

## Ruleset Handling (C3)
If `RULESET_PATH` points to an existing non-empty file it is passed to the compiler (`/ruleset:`). Otherwise a warning is emitted and the build proceeds (quality is optional not blocking). This avoids false negatives when contributors lack local copies.

## Environment Guard Lifecycle
Each make recipe sets `ALBT_VIA_MAKE=1` only for the spawned PowerShell process and unsets it immediately after. Tests verify the parent shell remains clean.

## Static Analysis
Run locally (repository contributors only – consumers typically rely on CI gate):
```
pwsh -NoLogo -File scripts/dev/run-pssa.ps1   # (future helper) or
Invoke-ScriptAnalyzer -Recurse -Path overlay/scripts,tests -EnableExit
```
Exit code 3 indicates violations (CI will fail fast before running tests). Consumers do not receive a separate analysis helper script—analysis is a repository concern.

## Running Tests Locally
Contract tests (fast):
```
pwsh -NoLogo -Command "Invoke-Pester -Path tests/contract -CI"
```
Integration tests:
```
pwsh -NoLogo -Command "Invoke-Pester -Path tests/integration -CI"
```
Ensure static analysis passes first.

## Expected Exit Codes
| Code | Meaning |
|------|---------|
| 0 | Success |
| 2 | Guard violation (invoke via make) |
| 3 | Static analysis failure |
| 4 | Contract test failure |
| 5 | Integration test failure |
| 6 | Missing required tool |
| >6 | Unexpected internal error |

Special Case: `next-object-number` uses exit 2 for range exhaustion (C11) and exit 1 for malformed `app.json`.

## Migration Notes
- Bash scripts have been removed; PowerShell scripts are canonical.
- Any older documentation referencing `overlay/scripts/make/linux/` or `windows/` should be updated to point directly to `overlay/scripts/make/`.

## Troubleshooting
| Symptom | Cause | Resolution |
|---------|-------|------------|
| Exit 2 running script directly | Guard enforced | Use `make <target>` |
| Exit 3 before tests | PSScriptAnalyzer violations | Fix reported diagnostics |
| Exit 6 early | Missing module | Install required module(s) |
| Verbose flag ignored | Env var not set or flag omitted | Use `VERBOSE=1 make build` or append `-- -Verbose` (if pass-through enabled) |
| No analyzers found | Disabled or settings.json missing | Optional; create `.vscode/settings.json` per C5 |
| Ruleset skipped | File missing or empty | Provide valid file & set `RULESET_PATH` |
| Range exhaustion (code 2) | All ids used in `idRanges` | Expand or add new range in `app.json` |

## Next Steps
Consult `contracts/README.md` for detailed behavior guarantees (C1–C14) and `tasks.md` for implementation progress.
