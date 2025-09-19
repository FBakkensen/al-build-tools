# Phase 0 Research: Release-Based Installer

## Decision: Release Metadata Retrieval
- **Decision**: Use GitHub REST API v3 endpoints (`/releases/latest` and `/releases/tags/{tag}`) to resolve the effective release tag and asset metadata.
- **Rationale**: The API surface distinguishes drafts and prereleases, honoring the spec requirement to target published releases. It also exposes asset IDs for authenticated downloads without guessing URLs.
- **Alternatives considered**:
  - Scraping the HTML releases page → brittle, decoding HTML, higher risk of breakage.
  - Hard-coding the `latest/download/overlay.zip` URL → fails to support explicit tag selection and loses diagnostics about the chosen release.
- **Compatibility outcome**: Legacy branch/tarball archive downloads are removed; the installer will return `NotFound` for any non-release ref.

## Decision: Asset Download Strategy
- **Decision**: Construct the asset download URL using `https://api.github.com/repos/{owner}/{repo}/releases/assets/{asset_id}` with the `Accept: application/octet-stream` header to download the binary payload.
- **Rationale**: This pattern is stable, works for both latest and explicit releases, and reuses a single HTTP pipeline. It avoids embedding version numbers in paths.
- **Alternatives considered**:
  - Using the tarball/zipball archive endpoints for tags → reintroduces branch-based retrieval (spec rejects) and does not guarantee overlay-only packaging.
  - Hosting assets on a CDN bucket → out of scope; increases maintenance burden.

## Decision: Tag Normalization
- **Decision**: Normalize explicit inputs by adding a leading `v` when missing; the canonical tag is stored with the leading `v` once resolved from GitHub metadata.
- **Rationale**: Aligns with existing release conventions and ensures logging remains consistent, meeting FR-Release-03.
- **Alternatives considered**:
  - Case-sensitive direct string match → forces consumers to remember exact tag formatting and produces avoidable NotFound exits.

## Decision: Diagnostics and Telemetry
- **Decision**: Extend the success log to include the resolved release tag and asset name while preserving existing wording and timing diagnostics.
- **Rationale**: Meets FR-Release-04 and maintains transparent contracts per the Constitution.
- **Alternatives considered**:
  - Emitting a new structured JSON object → larger breaking change for downstream tooling depending on current logs.

## Decision: Environment Variable Precedence
- **Decision**: Evaluate `ALBT_RELEASE` only when `Ref` is not supplied, and emit a verbose note when the env var influences selection.
- **Rationale**: Matches FR-Release-05 while keeping parameter precedence explicit for troubleshooting.
- **Alternatives considered**:
  - Merging both inputs (env as default, parameter appended to diagnostics) → invites confusion and contradicts spec direction.

## Open Verification Items
- Confirm the release pipeline publishes a single overlay ZIP asset (`overlay.zip` preferred; legacy `al-build-tools-<tag>.zip` remains supported) that contains the expected root folder.
- Validate GitHub API rate limits are acceptable for installer usage (unauthenticated limit of 60 requests/hour should suffice, but note in README for heavy automation).
