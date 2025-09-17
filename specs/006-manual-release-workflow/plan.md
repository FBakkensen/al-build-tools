# Implementation Plan: Manual Release Workflow

Feature Spec: `spec.md`
Branch: `006-manual-release-workflow`
Date: 2025-09-17

## 1. Objectives Summary
Establish a deliberate, human-triggered (`workflow_dispatch`) GitHub Actions workflow that packages only the `overlay/` directory into a versioned release artifact (`al-build-tools-<version>.zip`) with integrity verification (hash manifest) and concise release notes (diff + metadata + optional maintainer summary). Preserve governance, minimal surface, and parity principles.

## 2. Scope Confirmation
In scope: manual trigger, overlay-only archive, semver validation, diff summary, hash manifest, release notes metadata, dry-run path. Out of scope: signing, SBOM, automated changelog generation, multi-channel pre-releases.

## 3. Requirements Mapping (Condensed)
- FR-01..FR-15 mapped in `tasks.md` Traceability section.
- Acceptance criteria enumerated in `contracts/acceptance-criteria.md`.

## 4. Architecture Overview
Single GitHub Actions workflow with linear gated steps:
Inputs -> Checkout -> Validation Gates -> Manifest & Diff -> (Dry Run? stop) -> Tag -> Archive -> Release Creation -> Verification.
Failure at any gate aborts prior to irreversible operations (tag push) except where tag creation itself is atomic. No external services; pure git + core utilities.

## 5. Workflow Step Design
| Step | Purpose | Abort Conditions |
|------|---------|------------------|
| Inputs & Setup | Normalize version | Missing/invalid version |
| Tag/State Inspection | Monotonicity & uniqueness | Tag exists / non-monotonic |
| Clean Check | Reproducibility | Dirty overlay |
| File Enumeration | Build deterministic list | (Should not abort unless IO failure) |
| Hash Manifest | Integrity | Hash command failure / empty list |
| Diff Summary | Change awareness | Diff command error |
| Dry Run Gate | Preview path | n/a |
| Tag Creation | Immutable reference | Tag push failure |
| Archive Packaging | Bundle artifact | Packaging failure |
| Release Publish | Distribute | API failure (exit non-zero) |

## 6. Data & Artifacts
- Manifest: `manifest.sha256.txt` (inside archive)
- Archive: `al-build-tools-<version>.zip`
- Release notes JSON block for machine parsing.
- Dry run artifacts: manifest preview + diff summary (uploaded via actions/upload-artifact).

## 7. Risks & Mitigations (Delta)
Mostly captured in research; emphasize tag race (mitigated by existence check before create + atomic create).

## 8. Testing Strategy
- Dry run with future version (ensures no tag created).
- Real run on temporary test tag (e.g., `v0.1.0` in fork) verifying acceptance criteria.
- Hash verification reproduction locally.
- Negative tests: dirty overlay, duplicate version, non-monotonic version.

## 9. Rollout & Follow-Up
- Implement workflow on feature branch.
- Run dry-run example; attach logs to PR.
- After review, merge to `main` and perform first official release (e.g., `v1.0.0`).
- Add README section referencing release process (separate doc task if not already present).

## Progress Tracking
| Phase | Description | Status | Artifacts |
|-------|-------------|--------|-----------|
| 0 | Research | Complete | `research.md` |
| 1 | Modeling & Contracts | Complete | `data-model.md`, `contracts/*`, `quickstart.md` |
| 2 | Execution Plan | Complete | `tasks.md`, `plan.md` |

All required artifacts generated; no ERROR states encountered.

## Completion Statement
Phases 0–2 complete. Ready to implement `.github/workflows/release-overlay.yml` according to `tasks.md`.
