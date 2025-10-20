# Overlay Provision Test Fixtures

## Purpose

This directory contains AL project templates for overlay script testing. These fixtures are used by `scripts/ci/test-overlay-build.ps1` to validate provision workflows (download-compiler, download-symbols) in isolated Docker containers.

## Fixture Isolation

The test infrastructure uses dedicated fixture directories for separation of concerns:

- **`tests/fixtures/bootstrap-installer/`** - Reserved for bootstrap installer test fixtures (used by `test-bootstrap-install.ps1`)
- **`tests/fixtures/overlay-provision/`** - Overlay provision test fixtures (used by `test-overlay-build.ps1`)

Each test harness operates independently with its own fixture set, preventing cross-contamination between installer tests and overlay tests.

## Fixture Structure

Each scenario directory is a minimal AL project template with:

- **`app.json`** - Business Central app manifest with realistic UUID (not null GUID, as AL compiler requires valid GUIDs)
- **`.vscode/settings.json`** - VS Code AL extension settings (CodeCop, UICop analyzers)
- **`.gitignore`** - Standard AL project ignores (.alpackages/, .output/, *.app)

**Important:** Fixtures are pure AL project templates without git initialization. Tests copy fixtures to container workspace and run provision workflows in isolation.

## Test Scenarios

### Scenario 1: No Dependencies Property

**Directory:** `scenario1-no-dependencies/`

**Purpose:** Validates `download-symbols.ps1` handles missing `dependencies` property in app.json

**Fixture Details:**
- **App GUID:** `a1b2c3d4-e5f6-7890-abcd-ef1234567890`
- **App Name:** Test App Scenario 1
- **BC Version:** 24.0.0.0
- **Dependencies:** *Property NOT present* (tests null-coalescing fix at line 124)

**Validation:**
1. ✓ Provision exits with code 0
2. ✓ Baseline BC packages downloaded to `~/.bc-symbol-cache/`:
   - Microsoft.Application
   - Base Application (BaseApp)
   - System

### Scenario 2: Empty Dependencies Array

**Directory:** `scenario2-empty-dependencies/`

**Purpose:** Validates `download-symbols.ps1` handles empty `dependencies` array

**Fixture Details:**
- **App GUID:** `b2c3d4e5-f6a7-8901-bcde-f12345678901`
- **App Name:** Test App Scenario 2
- **BC Version:** 24.0.0.0
- **Dependencies:** `[]` (empty array)

**Validation:**
1. ✓ Provision exits with code 0
2. ✓ Baseline BC packages downloaded to `~/.bc-symbol-cache/`:
   - Microsoft.Application
   - Base Application (BaseApp)
   - System

### Scenario 3: With Dependency

**Directory:** `scenario3-with-dependency/`

**Purpose:** Validates real NuGet package download from AppSource feed

**Fixture Details:**
- **App GUID:** `c3d4e5f6-a7b8-9012-cdef-123456789012`
- **App Name:** Test App Scenario 3
- **BC Version:** 24.0.0.0
- **Dependencies:**
  ```json
  [
    {
      "id": "e340d5b5-f7eb-44db-b802-fd3b7896e0a7",
      "name": "9A Advanced Manufacturing - License",
      "publisher": "9altitudes",
      "version": "24.7.0.0"
    }
  ]
  ```

**Validation:**
1. ✓ Provision exits with code 0
2. ✓ 9altitudes package downloaded to `~/.bc-symbol-cache/9altitudes/9A Advanced Manufacturing - License/`
3. ✓ Baseline BC packages downloaded (Microsoft.Application, BaseApp, System)

## Test Harness Integration

### Container Test Flow

1. **Host:** `test-overlay-build.ps1` orchestrates Docker container
2. **Container:** `mcr.microsoft.com/dotnet/sdk:8.0-windowsservercore-ltsc2022`
3. **Mount Points:**
   - `overlay/` → `C:\overlay` (local overlay scripts under test)
   - `tests/fixtures/overlay-provision/` → `C:\fixtures` (fixture templates)
   - `overlay-test-template.ps1` → `C:\test\overlay-test.ps1` (test script)
4. **Execution:** Install PowerShell 7 → Run overlay-test-template.ps1
5. **Test Script:**
   - Copy fixtures from `C:\fixtures` to `C:\workspace\scenarioN`
   - Execute `Invoke-Build provision` in each scenario workspace
   - Validate exit code + symbol cache contents
   - Generate scenario results with detailed validation steps

### Artifacts

- **`out/test-overlay/overlay-summary.json`** - Structured test results (see `overlay-test-summary.schema.json`)
- **`out/test-overlay/overlay.transcript.txt`** - PowerShell transcript

### Summary Schema

Test results conform to JSON Schema: **`overlay-test-summary.schema.json`**

**Key Fields:**
- `image`, `imageDigest` - Container image identification
- `startTime`, `endTime`, `durationSeconds` - Timing
- `exitCode`, `success` - Overall result
- `psVersion`, `dotnetSdkVersion` - Environment versions
- `overlaySource` - `local` (mounted from host) or `github` (downloaded release)
- `scenarioResults[]` - Array of scenario results with `validationDetails[]` (step-by-step validation)
- `testedScripts[]` - List of overlay scripts tested (`download-compiler.ps1`, `download-symbols.ps1`)
- `cacheLocations` - Tool cache and symbol cache paths

## Design Rationale

### Why Realistic UUIDs?

AL compiler fails when encountering null GUIDs (`00000000-0000-0000-0000-000000000000`). Fixtures use realistic UUIDs like `a1b2c3d4-e5f6-7890-abcd-ef1234567890` to ensure compiler acceptance during provision workflows.

### Why No Git Initialization?

Fixtures are pure AL project templates. Git initialization is not needed for provision testing (download-compiler, download-symbols). This simplifies fixture maintenance and avoids git repository state pollution in test containers.

### Why Separate Fixture Directories?

Clear separation between installer tests (bootstrap-installer/) and overlay tests (overlay-provision/) prevents fixture coupling. Each test harness has a dedicated fixture set matching its validation scope.

## Maintenance

When adding new provision scenarios:

1. Create new scenario directory: `tests/fixtures/overlay-provision/scenarioN-<name>/`
2. Add `app.json` with unique GUID (realistic UUID, not null GUID)
3. Add `.vscode/settings.json` (AL analyzers)
4. Add `.gitignore` (standard AL ignores)
5. Update `overlay-test-template.ps1`:
   - Add `Setup-ScenarioN` function
   - Add `Validate-ScenarioN` function with validation steps
   - Add scenario execution block
6. Update this README with scenario details and validation criteria
7. Update `overlay-test-summary.schema.json` if adding new validation fields

## References

- **Test Harness:** `scripts/ci/test-overlay-build.ps1`
- **Container Script:** `scripts/ci/overlay-test-template.ps1`
- **Schema:** `overlay-test-summary.schema.json`
- **Related:** `tests/fixtures/bootstrap-installer/` (installer test fixtures)
