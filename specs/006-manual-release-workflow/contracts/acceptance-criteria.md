# Acceptance Criteria: Manual Release Workflow

| ID | Scenario | Criteria |
|----|----------|----------|
| AC-01 | Manual Trigger | Workflow available with `workflow_dispatch` only; no other triggers in YAML. |
| AC-02 | Inputs Validation | Run fails fast if required `version` missing or malformed. |
| AC-03 | Clean Overlay State | Run aborts with explicit message if any uncommitted or untracked file exists under `overlay/`. |
| AC-04 | Overlay Isolation | Published archive contains only files that currently exist under `overlay/` with identical relative paths and no root folder wrapper. |
| AC-05 | Version Monotonicity | Provided version strictly greater than highest existing `v*` tag (semver compare) unless dry run. |
| AC-06 | Tag Collision | If tag already exists, run aborts pre-packaging. |
| AC-07 | Dry Run Mode | When `dry_run=true`, no tag or release created; diff + manifest preview produced as artifact/output. |
| AC-08 | Hash Manifest | Archive includes `manifest.sha256.txt` listing every file and root hash; counts match actual files. |
| AC-09 | Diff Summary | Release notes include Added/Modified/Removed sections (or "Initial release") limited to overlay paths. |
| AC-10 | Maintainer Summary | Optional `summary` input appears at top of release notes when provided. |
| AC-11 | Metadata Block | Release notes contain JSON block with version, commit SHA, UTC timestamp, file count, root hash. |
| AC-12 | Immutability | Post-success run does not overwrite existing tag/asset (must bump version for changes). |
| AC-13 | Performance | P95 duration ≤ 2 minutes for current overlay size (< ~500 files). |
| AC-14 | Failure Transparency | Any abort condition logs a single-line reason and uses non-zero exit code. |
| AC-15 | No Internal Leakage | No files outside overlay appear in archive (validated by random audit / diff script). |
