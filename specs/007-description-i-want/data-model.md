# Phase 1 Data Model Notes

This feature does not introduce persistent application data or new entities beyond transient release metadata handled within `bootstrap/install.ps1`. For completeness, the installer manipulates the following in-memory structures:

| Entity | Fields | Description |
|--------|--------|-------------|
| `EffectiveSelector` | `SourceRef` (input parameter), `EnvOverride` (`ALBT_RELEASE`), `ResolvedTag` (canonical tag) | Represents the precedence chain that yields the release tag used for lookup. |
| `ReleaseMetadata` | `TagName`, `IsDraft`, `IsPrerelease`, `PublishedAt`, `Assets[]` | Payload returned by the GitHub Releases API. Only published releases with non-empty assets are accepted. |
| `ReleaseAsset` | `Id`, `Name`, `DownloadUrl` | Asset descriptor used to fetch the overlay zip. The installer prefers an asset named `overlay.zip` but can fall back to legacy `al-build-tools-<tag>.zip` packages. |

All structures remain transient within the script execution and are not exposed outside of the installer process. Branch/tarball archive descriptors are intentionally absent—release metadata is the sole supported install surface.
