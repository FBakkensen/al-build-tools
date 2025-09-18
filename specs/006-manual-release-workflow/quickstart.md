# Quickstart: Manual Release Workflow

This guide shows maintainers how to run the manual overlay-only release workflow and consumers how to fetch, verify, and adopt a release.

For a concise overview, see the `Manual Release Workflow` section in the [repository README](../../README.md#manual-release-workflow).

## Maintainer: Creating a Release
1. Ensure `main` branch is up to date and CI is green.
2. Confirm no uncommitted or untracked changes under `overlay/`.
3. Decide the next semantic version `vMAJOR.MINOR.PATCH` (see Versioning below).
4. Open GitHub → Actions → `Manual Overlay Release` workflow.
5. Provide inputs:
   - `version`: e.g., `v1.3.0` (must be greater than existing tags)
   - `summary` (optional): human context (Highlights, risks, migration notes)
   - `dry_run` (boolean): set true to preview without publishing
6. Dispatch the workflow.
7. (If dry run) Review planned diff, manifest preview, and version validation output. Re-run with `dry_run=false` to publish.
8. (If real) Verify run succeeded: new tag + release with asset `al-build-tools-<version>.zip` and notes containing hash metadata.

## Maintainer: Failure Cases & Recovery
| Failure | Likely Cause | Recovery |
|---------|--------------|----------|
| Abort: tag exists | Version already used | Pick next patch/minor/major version |
| Abort: non-monotonic | Provided version <= latest | Bump appropriately |
| Abort: dirty overlay | Untracked/modified files | Commit or stash, retry |
| Release creation failed after tag | Permissions / transient API issue | Delete tag if safe, retry or bump version |

## Consumer: Fetch & Verify
Download latest version (example for `v1.3.0`):
```
# PowerShell
Invoke-WebRequest -Uri https://github.com/FBakkensen/al-build-tools/releases/download/v1.3.0/al-build-tools-v1.3.0.zip -OutFile al-build-tools-v1.3.0.zip

# Bash
curl -sL -o al-build-tools-v1.3.0.zip \
  https://github.com/FBakkensen/al-build-tools/releases/download/v1.3.0/al-build-tools-v1.3.0.zip
```

Verify hash manifest:
```
# PowerShell
Expand-Archive al-build-tools-v1.3.0.zip -DestinationPath extracted
Get-Content extracted/manifest.sha256.txt | ForEach-Object {
  $parts = $_.Split(':'); if ($parts.Length -eq 2) {
    $path,$expected=$parts; $actual=(Get-FileHash -Algorithm SHA256 extracted/$path).Hash.ToLower();
    if ($actual -ne $expected) { Write-Error "Hash mismatch: $path"; exit 1 }
  }
}
Write-Host "All hashes verified."

# Bash
unzip -q al-build-tools-v1.3.0.zip -d extracted
awk -F':' 'NF==2 {print $2"  extracted/"$1}' manifest.sha256.txt > manifest.sum
sha256sum -c manifest.sum
```

Install / Upgrade in consumer repo:
```
# Replace existing overlay (will overwrite tracked files)
rm -rf overlay
cp -R extracted/overlay ./overlay
# or PowerShell
Remove-Item -Recurse -Force overlay; Copy-Item -Recurse extracted/overlay overlay
```
Commit the update referencing version + root hash.

Rollback:
1. Identify prior version tag (e.g., `v1.2.4`).
2. Download corresponding archive (same pattern as above).
3. Replace `overlay/` with that version.
4. Commit referencing rollback rationale.

## Versioning Semantics
- MAJOR: Breaking changes to overlay contract (script removal, incompatible flag change).
- MINOR: Additive, backward-compatible functionality.
- PATCH: Backward-compatible fixes / internal improvements.

## Support Info to Include
- Toolkit version (tag)
- Root hash (from release notes JSON block)
- Commit SHA (from release notes JSON block)
- Relevant script names / commands executed

## Best Practices
- Always dry-run before a new MAJOR bump.
- Keep `summary` concise (why & what changed, not how).
- Consumers should pin a specific version rather than relying on latest.

## Future Enhancements (Informational)
- Signature verification (planned)
- Automated changelog generation
- Pre-release channels (`-rc`, `-beta`)
