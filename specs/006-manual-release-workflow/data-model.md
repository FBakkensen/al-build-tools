# Data Model: Manual Release Workflow

Date: 2025-09-17

## Overview
Conceptual entities and relationships powering the manual release process. This is a logical (not code-level class) model guiding workflow variable naming, manifest structure, and validation sequencing.

## Entities
### Version
- Attributes: `rawInput`, `normalized` (e.g. v1.2.3), `major`, `minor`, `patch`.
- Constraints: Must start with `v`, semantic triplet, greater than latest existing tag unless dry-run.
- Relations: 1:1 with `ReleaseTag`, used by `ReleaseArtifact`, referenced in `ReleaseNotes` metadata block.

### ReleaseTag
- Attributes: `name` (== Version.normalized), `targetCommitSha`, `createdTimestampUtc`.
- Lifecycle: Created only after validation gates pass (unless dry-run). Immutable once created.

### OverlayPayload
- Attributes: `rootPath` (./overlay), `fileList[]` (relative paths), `byteSizeTotal`, `fileCount`.
- Constraints: Must exclude any non-overlay file; file list is deterministic, sorted lexicographically.

### HashManifest
- Attributes: `entries[]` (path, sha256), `rootHash` (sha256 over joined `path:hash` lines), `algorithm` ("sha256"), `generatedUtc`.
- Embedding: Stored inside archive at `manifest.sha256.txt`; may also appear in release notes JSON block.

### DiffSummary
- Attributes: `added[]`, `modified[]`, `removed[]`, `previousVersion` (nullable), `currentVersion`.
- First release: arrays empty, note = "Initial release".

### ReleaseArtifact
- Attributes: `fileName` (al-build-tools-<version>.zip), `sizeBytes`, `sha256` (archive), `containsManifest` (bool).
- Composition: Zip of raw files from OverlayPayload (no top-level directory wrapper).

### ReleaseNotes
- Attributes: `maintainerSummary` (optional), `bodyMarkdown`, `metadataJson` (parsable), `diffSection`, `guidanceLink`.
- Contains JSON block: `{version, commit, released, fileCount, rootSha256}`.

### ValidationGate
- Types: `CleanOverlay`, `UniqueVersion`, `MonotonicVersion`, `OverlayIsolation`, `HashManifestGenerated`, `DryRunSafety`.
- Attributes: `name`, `status` (pass/fail/skipped), `diagnostics`.

## Relationships Diagram (Textual)
```
Version -> ReleaseTag -> ReleaseArtifact
        -> DiffSummary --> ReleaseNotes
OverlayPayload -> HashManifest -> ReleaseArtifact
HashManifest.rootHash -> ReleaseNotes.metadataJson.rootSha256
ValidationGate[*] -> (collective) ReleaseDecision
```

## Process States
1. INPUT_COLLECTED (dispatch inputs read)
2. VERSION_VALIDATED (syntax + monotonic)
3. OVERLAY_SCANNED (file list built)
4. HASHES_COMPUTED (manifest + root hash)
5. DIFF_GENERATED
6. DRY_RUN_COMPLETE (if dry-run)
7. TAG_CREATED (non-dry-run)
8. ARTIFACT_PUBLISHED
9. RELEASE_PUBLISHED

## Invariants
- Once TAG_CREATED, failure must result in explicit human remediation; no silent rollback.
- Manifest file count == OverlayPayload.fileCount.
- rootHash reproducible across independent regenerations at same commit.
- ReleaseNotes.metadataJson.fileCount == Manifest entries length.

## Error Conditions Mapping
| Condition | Gate | Action |
|-----------|------|--------|
| Dirty overlay (untracked or modified) | CleanOverlay | Abort |
| Tag exists | UniqueVersion | Abort |
| Non-monotonic version vs latest | MonotonicVersion | Abort |
| Non-overlay file detected in staging dir | OverlayIsolation | Abort |
| Manifest missing or empty | HashManifestGenerated | Abort |
| Dry-run attempt to tag | DryRunSafety | Abort |

## Extensibility Points
- Add `Signature` entity later referencing ReleaseArtifact & HashManifest.
- Add `Channel` attribute to Version for pre-release qualifiers.
- Add `SizeBudgetGate` gate referencing historical size growth.

## Rationale
Explicit modeling reduces the risk of conflating version validation, packaging, and release metadata generation. Tracking gates as first-class entities improves auditability and aligns with Transparent Contracts and Repeatable Operations tenets.
