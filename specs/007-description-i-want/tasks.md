# Tasks: Release-Based Installer

**Input**: Design documents from `/specs/007-description-i-want/`
**Prerequisites**: plan.md (required), research.md, data-model.md, contracts/

> Reminder: Legacy branch/tarball installers are out of scope. Every task keeps the public contract strictly release-based.

## Phase 3.1: Setup
- [x] T001 Update `tests/_install/Assert-Install.psm1` so `Assert-InstallSuccessLine` and `Assert-InstallDownloadFailureLine` parse the new `asset` token, tolerate canonicalized refs, and expose helpers needed by release diagnostics; validate with `pwsh -NoProfile -Command "Import-Module tests/_install/Assert-Install.psm1; 'ok'"`.
- [x] T002 Enhance `tests/_install/InstallArchiveServer.psm1` to serve GitHub-style `/releases/latest`, `/releases/tags/{tag}`, and `/releases/assets/{id}` endpoints that stream the cached overlay zip, returning configurable 404s for missing tags.

## Phase 3.2: Tests First (TDD)
- [x] T003 Extend `tests/contract/Install.Diagnostics.Stability.Tests.ps1` to drive the release test server, assert the success log includes the resolved tag and `asset="overlay.zip"`, and cover the verbose `ALBT_RELEASE` diagnostic; run with `pwsh -NoProfile -Command "Invoke-Pester -Path tests/contract/Install.Diagnostics.Stability.Tests.ps1"`.
- [x] T004 [P] Update `tests/contract/Install.DownloadFailure.NotFound.Tests.ps1` to request an unprefixed tag, assert the failure log canonicalizes to a `v`-prefixed ref, and verify the `hint="Release tag not found"`; run with `pwsh -NoProfile -Command "Invoke-Pester -Path tests/contract/Install.DownloadFailure.NotFound.Tests.ps1"`.
- [x] T005 [P] Add `tests/integration/Install.ReleaseSelection.Latest.Tests.ps1` covering Quickstart step 3 by asserting default installs resolve the latest published release and reuse the overlay snapshot; execute via `pwsh -NoProfile -Command "Invoke-Pester -Path tests/integration/Install.ReleaseSelection.Latest.Tests.ps1"`.
- [x] T006 [P] Add `tests/integration/Install.ReleaseSelection.EnvOverride.Tests.ps1` covering Quickstart step 4 with `ALBT_RELEASE`, asserting the verbose note and success diagnostics reflect the override; run the new test file with `pwsh -NoProfile -Command "Invoke-Pester -Path tests/integration/Install.ReleaseSelection.EnvOverride.Tests.ps1"`.
- [x] T007 [P] Add `tests/integration/Install.ReleaseSelection.Normalize.Tests.ps1` covering Quickstart step 5 by installing with a tag lacking `v` and asserting success reports the canonical tag; validate with `pwsh -NoProfile -Command "Invoke-Pester -Path tests/integration/Install.ReleaseSelection.Normalize.Tests.ps1"`.

## Phase 3.3: Core Implementation (after tests are failing)
- [x] T008 Implement an `Resolve-EffectiveReleaseTag` helper inside `bootstrap/install.ps1` that applies `-Ref` > `ALBT_RELEASE` > latest release, normalizes missing `v` prefixes, and emits the verbose env note when the override wins.
- [x] T009 Add release metadata retrieval in `bootstrap/install.ps1`, calling `/releases/tags/{tag}` or `/releases/latest`, rejecting drafts/prereleases, and locating the `overlay.zip` asset with robust error messages.
- [x] T010 Replace the archive download block in `bootstrap/install.ps1` with a GitHub release asset download that sets `Accept: application/octet-stream`, streams to disk, and maps HTTP/status failures back to the existing guard categories.
- [x] T011 Update `bootstrap/install.ps1` diagnostics so success logs include `asset="overlay.zip"`, failure logs surface the resolved tag and new hint text, and guard codes remain unchanged.

## Phase 3.4: Integration
- [ ] T012 Adjust `tests/_install/Invoke-Install.psm1` so installer invocations can point at the release test server base URL, pass through `ALBT_RELEASE`, and capture combined stdout/stderr for the new verbose line.
- [ ] T013 [P] Refresh `tests/integration/Install.Success.Basic.Tests.ps1` to consume the release server helper, assert the new success diagnostic fields, and keep overlay snapshot comparisons intact.

## Phase 3.5: Polish
- [ ] T014 [P] Update `README.md` with release-based installation instructions, tag precedence order, and unauthenticated rate-limit guidance.
- [ ] T015 [P] Record the release asset migration and diagnostic changes in `CHANGELOG.md` under the unreleased section.
- [ ] T016 Run focused suites: `pwsh -File scripts/run-tests.ps1 -Path tests/contract` and `pwsh -File scripts/run-tests.ps1 -Path tests/integration` to confirm contracts and integrations pass.

## Dependencies
- T001 → T003, T004, T005, T006, T007
- T002 → T003, T004, T005, T006, T007
- T003, T004, T005, T006, T007 → T008
- T008 → T009 → T010 → T011 → T012
- T012 → T013
- T011, T013 → T014, T015
- T014, T015, T013 → T016

## Parallel Example
```
# After T001-T003 finish, execute the release selection integration tests together:
/task run "pwsh -NoProfile -Command 'Invoke-Pester -Path tests/integration/Install.ReleaseSelection.Latest.Tests.ps1'"  # T005
/task run "pwsh -NoProfile -Command 'Invoke-Pester -Path tests/integration/Install.ReleaseSelection.EnvOverride.Tests.ps1'"  # T006
/task run "pwsh -NoProfile -Command 'Invoke-Pester -Path tests/integration/Install.ReleaseSelection.Normalize.Tests.ps1'"  # T007
```
