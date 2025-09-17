# Behavioral Contracts: install.ps1

Although no network API is exposed, the installer publishes observable contracts enforced by tests.

## Diagnostic Line Formats
- Success summary (example): `[install] success ref=<ref> overlay=<path> duration=<seconds>`
- Download failure: `[install] download failure ref=<ref> url=<url> category=<CategoryName> hint=<hint>`
- Guard rail failures include stable prefix `[install] guard` followed by reason category token (e.g., `GitRepoRequired`, `WorkingTreeNotClean`, `PowerShellVersionUnsupported`).

## Exit Codes (Current Behavior)
| Scenario | Exit Code | Notes |
|----------|-----------|-------|
| Success | 0 | Normal completion; overlay copied successfully. |
| Guard rail failure (preconditions/arguments) | 10 | e.g., `GitRepoRequired`, `WorkingTreeNotClean`, `PowerShellVersionUnsupported`, `UnknownParameter`. |
| Download failure | 20 | Includes `NetworkUnavailable`, `NotFound`, `CorruptArchive`, `Timeout`, `Unknown` acquisition categories. |
| Permission/IO failure | 30 | Raised for guard lines such as `RestrictedWrites` and `PermissionDenied` when the filesystem blocks writes. |
| Unknown/unhandled failure | 99 | Top-level catch-all from the autorun exception handler. |

Tests under `tests/contract` and `tests/integration` assert these exit codes; update docs and tests together when behavior changes.

## Overwrite Semantics
- Second execution must fully replace all files under overlay path with fresh ref content regardless of prior modifications.

## Temp Workspace
- Created under system temp (`[install] temp <path>` optional log line recommended for test discovery) and removed before exit.

## Non-Goals
- No caching, diff detection, or partial updates.
