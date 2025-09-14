# Quickstart: PowerShell-Only Build Toolkit

This guide shows how to use the consolidated PowerShell build scripts guarded by `make`.

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
| Build | `make build` | Invokes `overlay/scripts/make/build.ps1` guarded |
| Clean | `make clean` | Removes artifacts |
| Show Config | `make show-config` | Prints resolved build configuration |
| Show Analyzers | `make show-analyzers` | Lists installed analyzer tooling |

All above targets: MUST be invoked through `make`. Direct script execution results in exit code 2 with guidance.

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

## Environment Guard Lifecycle
Each make recipe sets `ALBT_VIA_MAKE=1` only for the spawned PowerShell process and unsets it immediately after. Tests verify the parent shell remains clean.

## Static Analysis
Run locally:
```
pwsh -NoLogo -File scripts/dev/run-pssa.ps1   # (future helper) or
Invoke-ScriptAnalyzer -Recurse -Path overlay/scripts,tests -EnableExit
```
Exit code 3 indicates violations.

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

## Migration Notes
- Bash scripts remain temporarily for parity; do not modify—PowerShell is canonical.
- After successful CI validation & release, Bash counterparts will be removed in a follow-up change.

## Troubleshooting
| Symptom | Cause | Resolution |
|---------|-------|------------|
| Exit 2 running script directly | Guard enforced | Use `make <target>` |
| Exit 3 before tests | PSScriptAnalyzer violations | Fix reported diagnostics |
| Exit 6 early | Missing module | Install required module(s) |
| Verbose flag ignored | Not mapped yet / env var unset | Use `VERBOSE=1 make build` |

## Next Steps
Consult `contracts/README.md` for detailed behavior guarantees and `tasks.md` for implementation progress.
