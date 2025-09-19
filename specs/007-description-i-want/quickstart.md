# Quickstart: Validating Release-Based Installer

> Installs now communicate exclusively with GitHub release APIs—legacy branch archive URLs no longer succeed by design.

1. Create a disposable git repository and ensure the working tree is clean.
2. Publish or identify two GitHub releases for `FBakkensen/al-build-tools` that each contain an `overlay.zip` asset.
3. Run `pwsh -File bootstrap/install.ps1 -Dest <repo> -Source overlay` without specifying `-Ref` and confirm the script reports the latest release tag in the success diagnostic.
4. Export `ALBT_RELEASE=<older-tag>` and rerun the installer without `-Ref`; verify the reported release matches the environment override.
5. Invoke `pwsh -File bootstrap/install.ps1 -Ref <older-tag-without-v>` and confirm the installer normalizes and reports the canonical `v`-prefixed tag.
6. Attempt installation with a nonexistent tag (e.g., `-Ref v0.0.0-does-not-exist`) and observe the `NotFound` download classification without partial copies in the destination.
