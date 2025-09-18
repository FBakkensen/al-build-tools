# Research: Manual Release Workflow & Overlay-Only Artifact

Date: 2025-09-17
Branch: 006-manual-release-workflow

## Problem Restatement
We need a deliberate, human-triggered GitHub Actions workflow that produces an immutable, versioned archive containing only the `overlay/` payload. This enables downstream repositories to pin versions confidently while preserving the toolkit's contract surface minimalism and constitutional guarantees (cross‑platform parity, transparent contracts, overlay minimalism).

## Goals Alignment
| Goal | Spec References | Constitution Alignment |
|------|------------------|------------------------|
| Deliberate, auditable releases | FR-01, FR-04, Acceptance 1,3,8 | Spec Before Build, Transparent Contracts |
| Artifact minimalism | FR-02, Acceptance 2,10 | Overlay Minimalism |
| Integrity + trust | FR-06, FR-12, Acceptance 5 | Deterministic Artifacts, Security First |
| Change comprehension | FR-07, FR-08 | Transparent Contracts |
| Operational simplicity & speed | FR-14, FR-15 | Repeatable Operations |

## Alternatives Considered
1. Auto-publish on tag push: Rejected (risks accidental release; loses deliberate gate).
2. Multi-artifact bundle (overlay + docs + manifest separate): Rejected for now; single archive keeps UX simple.
3. Embedding manifest outside zip: Deferred; shipping inside archive is simplest; can also attach standalone copy later.
4. Full integration test suite during release: Duplicative; relies on earlier CI pipeline per spec assumptions.
5. Pre-building analyzer cache or shipping analyzers with artifact: Violates minimal surface and increases risk of staleness.

## GitHub Actions Implementation Notes (Research)
- Trigger: `workflow_dispatch` with inputs: `version` (required), `summary` (optional), `dry_run` (boolean), maybe `force` (future?).
- Need `fetch-depth: 0` to diff against previous tag and validate monotonicity.
- Tag collision detection: Use `git rev-parse --verify refs/tags/<tag>` or GitHub API call; prefer local git for speed.
- Version monotonicity: Parse existing `v*` tags; compare using semver precedence. Abort if not greater than latest (unless dry run).
- Archive packaging: Use `zip` on Linux / `Compress-Archive` on Windows. Since Action runs on a single runner OS per job, rely on default OS (ubuntu-latest) for packaging.
- Hash manifest: Generate deterministic sorted list of files with SHA-256. Include root hash computed over concatenated `path:hash` lines (newline separated). Store as `manifest.sha256.txt` inside archive and optionally upload separately for quick inspection.
- Diff summary: Compare tree at previous tag to current `HEAD` limited to `overlay/` path: categorize Added/Modified/Removed. Exclude unchanged. Provide empty notice if first release.
- Release notes composition order: (1) Maintainer summary (if provided) (2) Diff summary (3) Manifest root hash & metadata block (4) Guidance link.

## Edge Case Strategies
| Edge Case | Handling Strategy |
|-----------|------------------|
| First-ever release (no prior tag) | Skip diff; note "Initial release" |
| No overlay changes since last release | Warn in dry-run; abort real run unless `--allow-empty` future flag |
| Concurrent version attempts | Tag creation atomic; loser aborts gracefully |
| Large overlay (> expected size) | (Optional future gate) record baseline size; alert if growth > threshold |
| Time skew | Use UTC timestamps only |
| CRLF vs LF differences | Hash over file bytes as stored in Git checkout; consistent across consumers |

## Data & Metadata Plan
Will record in release body a JSON fenced block:
```
{"version":"<vX.Y.Z>","commit":"<sha>","released":"<UTC>","fileCount":N,"rootSha256":"<hash>"}
```
Ensures machine parsability without separate artifact.

## Risks Deep Dive
| Risk | Area | Impact | Mitigation |
|------|------|--------|------------|
| Tag misuse (wrong semver bump) | Governance | Chronology confusion | Dry-run preview + explicit doc examples |
| Internal leakage regression | Packaging | Contract break | Explicit path whitelist (`overlay/` only) |
| Hash manifest omission | Integrity | Reduced trust | Pipeline step with `if: always()` guard before release creation |
| Slow run due to git history scan | Performance | Exceeds FR-15 | Limit tag query to `git tag --list 'v*'` + simple sort |
| Diff parsing errors | Notes | Misleading release notes | Fail fast if diff step non-zero; abort before publishing |

## Open Technical Questions
None blocking; future iteration may add provenance signing.

## Out-of-Scope Confirmation
- No automated semantic bump.
- No multi-platform matrix (packaging is OS-agnostic for zip content).
- No SBOM/signatures yet.

## Go / No-Go Criteria for Implementation Plan Completion
- All functional requirements mapped to at least one workflow step.
- Clear failure exit paths for collision, dirty workspace, non-monotonic version.
- Draft artifact + manifest format defined.

## Conclusion
Research supports a lean, deterministic, integrity-focused manual release workflow with minimal risk and clear extensibility points.
