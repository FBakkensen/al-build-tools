# Contract: Installer Diagnostics

Only release-driven installs are supported; diagnostics below assume the installer is communicating with GitHub Releases APIs rather than branch/tarball archives.

## Success Log
- **Trigger**: `Install-AlBuildTools` completes copy of `overlay/` from selected release.
- **Output**: `[install] success ref="<resolved-tag>" overlay="overlay" asset="overlay.zip" duration=<seconds>`
- **Acceptance**:
  - `resolved-tag` equals the canonical release tag returned by GitHub.
  - `asset` field matches the downloaded asset name.
  - Duration remains formatted with two decimal places, matching existing contract.

## NotFound Failure (Explicit Tag)
- **Trigger**: `Install-AlBuildTools -Ref <nonexistent-tag>`.
- **Output**: `[install] download failure ref="<nonexistent-tag>" url="https://github.com/FBakkensen/al-build-tools" category=NotFound hint="Release tag not found"`
- **Acceptance**:
  - Category remains `NotFound`.
  - Diagnostic includes canonicalized tag (with leading `v` if normalization applied).
  - No files copied into destination after failure guard.

## Environment Override Diagnostic (Verbose)
- **Trigger**: `ALBT_RELEASE` set and `-Ref` omitted with `-Verbose` flag.
- **Output**: Verbose line `Using env ALBT_RELEASE=<value>` emitted before release lookup.
- **Acceptance**:
  - Verbose note appears only when environment override is effective.
  - Override does not alter success/failure guard semantics.
