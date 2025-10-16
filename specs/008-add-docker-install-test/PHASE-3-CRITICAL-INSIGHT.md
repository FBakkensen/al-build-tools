# Phase 3 Implementation: Critical Insight & Updates

**Date**: 2025-10-16
**Phase**: 3 (User Story 1 - Validate Installer In Clean Container)
**Tasks Completed**: T024-T030 (all marked [x] COMPLETED)

## Critical Insight Discovered During Implementation

### The Problem
The initial implementation approach was **fundamentally flawed**:
- Harness would download `overlay.zip`
- Manually extract it inside the container
- Then invoke `bootstrap/install.ps1`

This bypassed the **actual installer logic** and invalidated the entire test objective.

### The Solution
The corrected approach (now implemented):
- Harness resolves the release tag
- **Copies the `bootstrap/` directory** into the container
- Container runs the **actual `bootstrap/install.ps1` script**
- Installer handles all logic: downloading overlay, extracting, validating
- This validates the real first-time user path

### Why This Matters
✅ **Tests what users actually experience**: The harness now executes the exact same logic that end users run
✅ **Prevents bypassing installer bugs**: If the installer has a bug downloading or extracting the overlay, the test catches it
✅ **Respects the bootstrap installer's design**: The installer is responsible for artifact management—the harness just orchestrates the container

## Implementation Changes

### 1. `scripts/ci/test-bootstrap-install.ps1`

**Key Changes**:
- ✅ Removed artifact download phase (installer handles this)
- ✅ Changed `docker cp` from `overlay.zip` to `bootstrap/` directory
- ✅ Updated container command to invoke actual installer:
  ```powershell
  & powershell -File bootstrap/install.ps1 `
      -Dest 'C:\albt-repo' `
      -Ref $env:ALBT_TEST_RELEASE_TAG
  ```
- ✅ Store release tag in `$script:ReleaseTag` for passing to container environment
- ✅ Summary now populated with real exit codes from actual installer execution

**New Container Setup**:
```powershell
# Copy bootstrap directory (not overlay.zip)
$cpArgs = @(
    'cp'
    '-r'
    "$bootstrapPath"
    "$($containerName):C:\albt-workspace\bootstrap"
)
```

### 2. `specs/008-add-docker-install-test/spec.md`

**Updated FR-002**:
- OLD: "execute the bootstrap installer exactly as a new consumer would (download release artifact, copy overlay)"
- NEW: "execute the **actual** `bootstrap/install.ps1` script...without bypassing the installer's own logic"

### 3. `specs/008-add-docker-install-test/plan.md`

**Updated Summary**:
- OLD: "downloads the latest release artifact, executes the installer..."
- NEW: "copies the **actual** bootstrap installer script, and lets the installer execute its real logic (downloading the release overlay, extracting, validating)..."

**Updated Technical Context**:
- Removed "Git", "Invoke-WebRequest", "Expand-Archive" as harness responsibilities
- Added note: "**Harness copies `bootstrap/` directory to container; container runs actual installer**"

### 4. `specs/008-add-docker-install-test/research.md`

**Implementation Notes** (completely rewritten):
```
1. Script responsibilities: Resolve release tag, copy bootstrap/ directory
   into container, run container executing the actual bootstrap/install.ps1
   script, capture exit code and artifacts.

2. Container run: Use docker create + docker cp + docker exec to mount
   the repo root and copy only the bootstrap directory...

3. Inside container sequence:
   - Harness copies bootstrap/install.ps1 into container
   - Container runs the actual installer: powershell -File bootstrap/install.ps1
     -Dest C:\albt-repo -Ref $releaseTag
   - Installer handles all logic: downloading overlay.zip, extracting,
     validating installation
   - Container execution validates the real first-time user path without
     bypassing installer logic
```

### 5. `specs/008-add-docker-install-test/quickstart.md`

**Updated Documentation**:
- Clarified that harness runs the **actual** `bootstrap/install.ps1`
- Explained that installer downloads the overlay for the specified release
- Updated "How It Works" section with correct sequence:
  1. Host: Harness copies `bootstrap/` directory into container
  2. Container: Runs `bootstrap/install.ps1` inside clean environment
  3. Installer: Downloads overlay, extracts, validates installation
  4. Host: Captures exit code and artifacts

### 6. `specs/008-add-docker-install-test/tasks.md`

**Phase 3 Tasks Updated** (all marked [x] COMPLETED):
- T024: Now notes "(invokes actual bootstrap/install.ps1)"
- T025: Now notes "(copy `bootstrap/` directory, not overlay.zip)"
- T026: Now notes "(runs installer with appropriate parameters)"

## Test Validation

### What Gets Tested
✅ `bootstrap/install.ps1` downloading release artifacts
✅ Overlay extraction logic within installer
✅ Installation sequence in clean Windows container
✅ PowerShell 7.2+ provisioning by installer
✅ Exit codes and error handling

### What Does NOT Get Tested (Intentionally)
❌ Overlay content validation (harness responsibility ends after run completes)
❌ CI-specific workflow logic (GitHub Actions merely orchestrates harness)
❌ Pre-release artifact build process (separate CI gate)

## Independent Test Criteria (US1: Phase 3)

For Phase 3 to be considered complete:
- ✅ Local harness execution produces exit code 0 on success
- ✅ Transcript (`install.transcript.txt`) exists and captures installer output
- ✅ Summary JSON (`summary.json`) contains required fields with `success=true`
- ✅ Container is automatically cleaned up after run
- ✅ Documented commands allow reproduction on maintainer machine

## Future Phases (Not Affected)

**Phase 4 (US2)**: Surface Actionable Failures
- Will add failure classification, timed sections, stderr capture

**Phase 5 (US3)**: Reproduce Test Locally
- Will add help, Docker detection, configuration printing

**Phase 6**: CI Integration
- GitHub Actions workflow will simply invoke the harness and upload artifacts

## Documentation Trail

All spec documents have been updated to reflect this correction:
1. ✅ `spec.md` - FR-002 clarified
2. ✅ `plan.md` - Summary and Technical Context updated
3. ✅ `research.md` - Implementation Notes completely rewritten
4. ✅ `quickstart.md` - Local run documentation updated
5. ✅ `tasks.md` - Phase 3 tasks descriptions clarified
6. ✅ `data-model.md` - No changes needed (describes data, not process)
7. ✅ `contracts/README.md` - No changes needed (schema remains valid)

## Key Takeaway

**The harness is an orchestrator, not a installer replacement.** It validates that the actual installer works in a clean container environment by running it exactly as users would.
