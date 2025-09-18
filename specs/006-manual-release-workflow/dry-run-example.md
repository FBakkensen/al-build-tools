# Dry Run Example (2025-09-18)

The following commands were executed locally to validate the manual release workflow helpers before publishing:

1. **Version helper preview**

   ```pwsh
   pwsh -NoProfile -Command ". scripts/release/version.ps1; Get-VersionInfo -Version 'v1.0.0' -RepositoryRoot (Resolve-Path '.') | ConvertTo-Json -Depth 4"
   ```

   ```json
   {
     "RepositoryRoot": "D:\repos\al-build-tools",
     "Candidate": {
       "RawInput": "v1.0.0",
       "Normalized": "v1.0.0",
       "Major": 1,
       "Minor": 0,
       "Patch": 0,
       "TagName": "v1.0.0"
     },
     "Latest": null,
     "ExistingTags": null,
     "ComparisonToLatest": 1,
     "IsGreaterThanLatest": true,
     "TagExists": false
   }
   ```

2. **Hash manifest determinism check**

   ```pwsh
   pwsh -NoProfile -Command ". scripts/release/overlay.ps1; . scripts/release/hash-manifest.ps1; New-HashManifest -RepositoryRoot (Resolve-Path '.') | Select-Object FileCount, RootHash"
   ```

   ```text
   FileCount RootHash
   -------- --------
         22 9b4d86ac044dd2610e30e625bd012410a0ea95f276a114c68c4ce51811d79249
   ```

3. **Diff summary snapshot**

   ```pwsh
   pwsh -NoProfile -Command ". scripts/release/version.ps1; . scripts/release/diff-summary.ps1; Get-DiffSummary -Version 'v1.0.0' -RepositoryRoot (Resolve-Path '.') | ConvertTo-Json -Depth 4"
   ```

   ```json
   {
     "RepositoryRoot": "D:\repos\al-build-tools",
     "CurrentVersion": "v1.0.0",
     "PreviousVersion": null,
     "CurrentRef": "HEAD",
     "CurrentCommit": "01c557277250419e47f67d516e45a3c41d876846",
     "PreviousCommit": null,
     "Added": [],
     "Modified": [],
     "Removed": [],
     "IsInitialRelease": true,
     "Notes": "Initial release",
     "RawDiffLines": []
   }
   ```

4. **Unit regression sweep for release helpers**

   ```pwsh
   pwsh -NoProfile -File scripts/run-tests.ps1 -Path tests/unit/release -CI
   ```

   Output: `Tests Passed: 9, Failed: 0`

These artifacts demonstrate the expected dry-run experience: the candidate version exceeds any existing tag, the overlay manifest root hash is stable, and the diff summary flags the run as the initial release (no previous tag).
