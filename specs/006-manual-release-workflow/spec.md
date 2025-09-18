# Feature Specification: Manual Release Workflow & Overlay-Only Versioned Artifacts

**Feature Branch**: `006-manual-release-workflow`
**Created**: 2025-09-17
**Status**: Draft
**Input**: User description: "Manual-release workflow – Human-triggered (workflow_dispatch) GitHub Action that builds the release. Why: every publish is deliberate and reviewed instead of fired by routine branch activity. Overlay-only artifact – Package strictly the overlay/ directory and ship it as a release asset. Why: guarantees consumers receive only the intended public payload, free of repo internals. Versioned release asset – Tag/name each manual run, attach the overlay bundle to the resulting release. Why: maintains an auditable history so users can adopt, pin, or roll back specific versions. Consumer guidance – Document how releases are produced, how to select versions, and what changes land per release. Why: sets expectations, smoothing upgrades and support conversations. Pre-release validation gates – Optionally add quick checks (hash manifests, linting) before uploading. Why: catches packaging mistakes while keeping the person-triggered nature of the workflow."

---

## Why (Core Drivers)
- Ensure every toolkit publication is an explicit, auditable decision (no accidental / noisy releases on routine merges).
- Deliver ONLY the supported public contract surface (`overlay/`) to consumers; exclude tests, specs, CI, bootstrap internals.
- Provide immutable, traceable versions so downstream repositories can pin, upgrade intentionally, or roll back with confidence.
- Offer authoritative documentation describing release cadence, artifact contents, semantic meaning of versions, and change visibility.
- Introduce lightweight pre‑publish validation gates to prevent shipping malformed or polluted artifacts while preserving human control.

## Scope (Overview)
In-scope activities establish a manual (human-dispatched) release workflow producing a single overlay-only bundle attached to a versioned GitHub Release (tagged). Release documentation and minimal validation gates are included. No automated publish on push/merge; no auto-increment or dependency publishing.

| Area | In Scope | Out of Scope (Deferred / Non-Goal) |
|------|----------|-------------------------------------|
| Trigger | Manual `workflow_dispatch` only | Automatic publish on tag push / merge to `main` |
| Artifact | Single archive containing ONLY `overlay/` (structure preserved) | Bundling tests, specs, CI scripts, bootstrap, or analyzers |
| Versioning | Deterministic tag + release name strategy (see Versioning Strategy) | Semantic version policy negotiation beyond initial scheme evolution |
| Validation | Hash manifest, size / diff sanity, ruleset JSON validation, optional linter pass | Full integration test matrix, long performance runs, security scanning |
| Documentation | Consumer guidance (how to obtain, verify, upgrade) | Release notes automation tooling (manual curation acceptable) |
| Integrity | Reproducible packaging from clean checkout | Supply chain signatures / provenance attestations |

---

## User Scenarios & Testing *(mandatory)*

### Primary User Story
As a toolkit maintainer, I want to manually trigger a release workflow that produces a clean, versioned archive containing only the supported overlay so that consumers can reliably adopt specific versions without risk of internal or experimental files leaking into their repositories.

### Additional Personas
- **Consumer Maintainer**: Needs to pin a specific toolkit version and verify artifact integrity before updating their project.
- **Reviewer**: Needs a concise checklist to confirm a release is safe (validation gates passed) before approving execution.

### Acceptance Scenarios
1. **Manual Trigger**: Given a maintainer dispatches the workflow manually, When it starts, Then it records triggering user + inputs and proceeds only after confirming a clean overlay state.
2. **Overlay Isolation**: Given the workflow completes, When the archive is inspected, Then only `overlay/` files with preserved relative paths are present.
3. **Version Tag Creation**: Given a successful run, When it publishes, Then a new (unique & monotonic) annotated tag and release are created and the asset filename embeds the version.
4. **Idempotent Protection**: Given an existing tag with the requested version, When the workflow runs (non dry-run), Then it aborts before packaging with a clear collision message.
5. **Hash Manifest**: Given publication succeeds, When a consumer opens the archive (or attached manifest), Then hashes (SHA-256) exist for every file plus an aggregate root hash.
6. **Release Notes Diff**: Given a prior release exists, When notes are generated, Then they list added / modified / removed overlay paths since that release.
7. **Maintainer Summary**: Given the maintainer supplies a custom summary input, When the release is created, Then the summary appears prominently in notes.
8. **Dry Run**: Given dry-run mode is selected, When the workflow finishes, Then no tag or release exists but planned version, diff summary, and manifest preview are available as outputs/artifacts.
9. **Rollback Availability**: Given multiple prior tags exist, When a consumer accesses an earlier version, Then its artifact and manifest remain downloadable.
10. **No Internal Leakage**: Given the artifact contents are reviewed, Then no non-overlay or CI/spec/test files appear.

### Edge Cases
- Uncommitted or untracked overlay changes → Abort (clean state required for reproducibility).
- Attempted run from non-default branch (policy: only `main`) → Abort with provenance warning (unless future override input added).
- Tag collision (tag already exists) → Abort prior to packaging.
- Concurrent dispatch requesting same version → One succeeds; subsequent detects collision and aborts.
- Tag creation failure (race or permission) → Abort without partial release; no asset uploaded.
- Hash algorithm future change → Add parallel algorithm while retaining SHA-256; manifest format forward compatible.

---

## Requirements *(mandatory)*

### Functional Requirements (Lean)
- **FR-01**: Manual trigger only via `workflow_dispatch` (no automatic triggers).
- **FR-02**: Produce a single archive containing only `overlay/` files (no wrapper directory).
- **FR-03**: Enforce clean overlay state (abort on uncommitted/untracked overlay changes).
- **FR-04**: Enforce version monotonicity and tag uniqueness (abort if tag exists or not greater than latest).
- **FR-05**: Embed deterministic version in tag, release name, and asset filename.
- **FR-06**: Generate per-file SHA-256 hashes plus an aggregate root hash manifest shipped with or inside the archive.
- **FR-07**: Generate release notes diff summary (added / modified / removed overlay paths since previous release) when a prior release exists.
- **FR-08**: Accept optional maintainer-provided summary input appended/prepended to release notes.
- **FR-09**: Provide dry-run mode (no tag/release) outputting planned version, diff summary, and manifest preview.
- **FR-10**: Abort rather than overwrite existing version artifacts (idempotence guarantee).
- **FR-11**: Ensure published asset immutability (no post-publish modification path; corrections require new version).
- **FR-12**: Publish machine-readable metadata (JSON or manifest section) including version, commit SHA, UTC timestamp, file count, root hash.
- **FR-13**: Provide consumer documentation covering fetch, verify, install/update, rollback, and version semantics.
- **FR-14**: Avoid external network dependencies beyond GitHub API calls required for tagging/release (packaging is offline over repo content).
- **FR-15**: Typical execution ≤1 minute (P95 ≤2 minutes); exceed hard cap → fail with timeout status.

### Non-Goals
- Automated semantic version bump calculation (manual input / deterministic rule outside scope of implementation specifics).
- Code signing, attestations, or SBOM generation (future hardening phase).
- Multi-artifact releases (only single overlay bundle plus manifests/text notes now).
- Automatic changelog generation from commit messages beyond minimal file diff summary.
- Integration test execution as a release gate (assumed already enforced earlier in CI pipeline).

### Assumptions
- `main` branch reflects the integration-tested state suitable for release; earlier CI gates (tests, static analysis) already passed.
- Maintainers possess required GitHub permissions to create tags and releases.
- Consumers have basic tooling (PowerShell 7+, Bash coreutils, or OpenSSL) to verify hashes.
- Overlay contents are self-contained (no runtime dependency on repository-internal scripts once copied).

### Dependencies
- GitHub Actions infrastructure availability.
- Existing repository changelog or commit history usable for summarizing changes.
- Prior features establishing overlay contracts (guards, analyzer, build scripts) are implemented and stable.

### Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Wrong version/tag input | Confusing chronology | Dry-run preview + explicit version input validation (FR-04) |
| Internal file leakage | Breaks minimal surface contract | Restrict packaging to overlay path only (FR-02) |
| Missing or incorrect hash manifest | Undermines integrity verification | Always generate & publish manifest (FR-06) |
| Tag collision race | Failed or partial perception | Atomic tag creation & abort on existing (FR-04/FR-10) |
| Slow manual process | Reduced release cadence | Lean steps + runtime cap (FR-15) |
| Diff summary omission | Harder change comprehension | Automated diff summary (FR-07) |
| Dry-run misuse (forget to publish) | Delay in actual release | Clear dry-run output labeling |

### Open Questions (Mark if unresolved)
Currently none blocking; future clarifications may address: multi-channel versioning (preview vs stable), adding detached signatures, automation for changelog generation.

---

## Versioning Strategy
Initial pragmatic approach (subject to later formalization): `vMAJOR.MINOR.PATCH` where:
- MAJOR increments for breaking changes to overlay public contract (file removals, incompatible behavior shifts).
- MINOR increments for additive, backward-compatible enhancements or new scripts.
- PATCH increments for backwards-compatible fixes or internal refactors with no contract change.

Derivation: Maintainer supplies desired next version as dispatch input; workflow validates monotonicity (FR-027) relative to existing tags. No automatic inference to avoid accidental bumps.

Rollback: Consumers can pin any prior `v*` tag; documentation includes quick command examples.

---

## Pre-Release Validation (Lean)
Only minimal gates are retained because deeper quality / policy checks already run earlier in the CI pipeline on pull requests. The release job trusts the validated `main` state and re-validates only what can change between CI and packaging time.

Retained minimal steps:
1. Clean Overlay State (no uncommitted or untracked overlay changes).
2. Version Monotonicity (proposed version tag does not already exist; is greater than latest).
3. Overlay Packaging (collect only `overlay/` files; enforce allowlist of that root).
4. Hash Manifest Generation (SHA-256 per file + aggregate root hash) for consumer verification.
5. Tag & Release Creation (atomic; aborts cleanly on failure).

All other previously listed gates (ruleset structural re-validation, size growth thresholds, license header scan, binary execute permission scan, size/diff thresholds, empty diff guard, lint repetition) are intentionally omitted to keep the manual workflow fast, deterministic, and narrowly scoped. Rationale: those concerns are enforced (or should be moved) into PR CI so that release is a packaging formality, not a secondary quality decision point.

---

## Consumer Guidance (Documentation Requirements)
Must cover:
1. Purpose (manual, deliberate releases; overlay-only minimal surface).
2. Fetch patterns for latest & specific version (tag/asset URL examples).
3. Hash verification examples (PowerShell + Bash/OpenSSL) using manifest.
4. Install/upgrade procedure (replace overlay directory; note overwrite semantics).
5. Version semantics (MAJOR/MINOR/PATCH) & rollback steps.
6. Rollback example (download prior tag, replace overlay, commit).
7. Support ticket info to include: version, commit SHA, root hash.

---

## Success Metrics
- 100% artifact purity (only overlay files) in sampled releases.
- Hash manifest verification success for sampled releases (root hash match).
- P95 workflow duration ≤2 minutes (target median ≤1 minute).
- ≥80% support issues include version + root hash.
- Zero internal (non-overlay) file leakage incidents.

---

## Review & Acceptance Checklist
### Content Quality
- [x] Focus on WHAT (no YAML implementation specifics)
- [x] Clear user value articulation (repeatability, integrity, minimal surface)
- [x] All mandatory sections present

### Requirement Completeness
- [x] Functional requirements testable & uniquely identifiable (lean set)
- [x] Non-goals explicitly bounded
- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Risks enumerated with mitigations
- [x] Minimal validation sequence defined (lean)

### Release Governance
- [x] Version scheme defined
- [x] Integrity verification path defined
- [x] Manual control preserved (no auto triggers)

---

## Execution Status
Initial draft complete; ready for planning & implementation tasks (authoring workflow, validation scripts, documentation updates).

---

## Traceability (High-Level)
| Goal | Supporting FRs / Elements |
|------|--------------------------|
| Deliberate Releases | FR-01, FR-03, FR-04 |
| Artifact Minimalism | FR-02 |
| Integrity & Trust | FR-06, FR-12 |
| Change Awareness | FR-07, FR-08 |
| Consumer Confidence | FR-05, FR-13 |
| Governance & Versioning | FR-04, FR-05, FR-09, FR-10, FR-11 |
| Performance & Simplicity | FR-14, FR-15 |

---

## Future Extensions (Non-Blocking Ideas)
- Add cryptographic signing (Sigstore / minisign) for artifact + manifest.
- Automate changelog generation with conventional commit parsing.
- Introduce SBOM or provenance attestations for supply chain transparency.
- Add multi-channel release types (e.g., `-rc`, `-beta`) with policy gating.
- Provide a small CLI that fetches & verifies latest release programmatically.

---

## Conclusion
This specification defines a controlled, integrity-focused manual release process ensuring only the public supported overlay is versioned and distributed with strong traceability, minimal surface area, and clear consumer guidance. Implementation will concentrate on creating a reliable workflow, robust validation gates, and concise documentation without over-engineering future enhancements prematurely.

