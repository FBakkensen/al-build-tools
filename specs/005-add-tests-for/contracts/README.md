# Behavioral Contracts: install.ps1

Although no network API is exposed, the installer publishes observable contracts enforced by tests.

## Diagnostic Line Formats
- Success summary (example): `[install] success ref=<ref> overlay=<path> duration=<seconds>`
- Download failure: `[install] download failure ref=<ref> url=<url> category=<CategoryName> hint=<hint>`
- Guard rail failures include stable prefix `[install] guard` followed by reason category token (e.g., `GitRepoRequired`, `WorkingTreeNotClean`, `PowerShellVersionUnsupported`).

## Exit Codes (Proposed for Test Alignment)
| Scenario | Exit Code |
|----------|-----------|
| Success | 0 |
| Guard rail failure | 10 |
| Download failure | 20 |
| Permission/IO failure | 30 |
| Unknown/unhandled failure | 99 |

(If current implementation differs, align tests to actual codes and update this table.)

## Overwrite Semantics
- Second execution must fully replace all files under overlay path with fresh ref content regardless of prior modifications.

## Temp Workspace
- Created under system temp (`[install] temp <path>` optional log line recommended for test discovery) and removed before exit.

## Non-Goals
- No caching, diff detection, or partial updates.
