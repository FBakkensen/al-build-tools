# Research: Docker-Based Install Script Test

Date: 2025-10-16
Branch: 008-add-docker-install-test
Spec: `specs/008-add-docker-install-test/spec.md`

## Unknowns & Decisions

Each section lists: Decision, Rationale, Alternatives Considered.

### 1. Harness Location (Script vs Inline Workflow)
- Decision: Provide a reusable PowerShell script `scripts/ci/test-bootstrap-install.ps1` invoked by a thin GitHub Actions workflow for CI; allow local invocation.
- Rationale: Encapsulates logic for container lifecycle, logging, and artifact export; easier local reproduction and future extension (e.g., adding Pester) without editing workflow YAML.
- Alternatives Considered:
  - Inline all logic in workflow YAML: Harder to test locally; duplication if later adding more CI systems.
  - Add logic into `overlay/`: Bloats public contract; test concern not needed by consumers.

### 2. Structured Assertions (Pester Now or Later)
- Decision: Defer Pester introduction for MVP; rely on exit code + explicit checks in harness script.
- Rationale: Core value is verifying installer exit path and capturing logs; adding Pester adds module dependency and setup time. Can layer later for richer assertions (e.g., verifying specific files copied).
- Alternatives Considered:
  - Add Pester now: More formal tests but increases execution time and complexity.
  - Use simple custom assertion functions: Similar complexity to current approach; not standardized.

### 3. Release Artifact Selection Strategy
- Decision: Default to latest published GitHub release (non-draft) via REST API; allow override with env var `ALBT_TEST_RELEASE_TAG` (or commit artifact path) for pre-release validation.
- Rationale: Ensures baseline validation of what would be shipped; override supports testing candidate tags before publishing.
- Alternatives Considered:
  - Always test PR build artifact: PR may not reflect latest released installer; redundancy with build pipeline.
  - Hardcode tag: Not adaptable.

### 4. PowerShell Version Provisioning Strategy
- Decision: Treat PowerShell 7.2+ as an installation-time dependency satisfied by `bootstrap/install.ps1` itself (auto-install if host/container starts with Windows PowerShell 5.1). Harness must NOT pre-install PS7; container intentionally begins without it to validate this path.
- Rationale: Ensures real-world first-time user path works from legacy environments; reduces external preconditions for the test; aligns with requirement that container lacks PS7 initially.
- Alternatives Considered:
  - Pre-install PS7 in container: Masks installer logic and reduces coverage.
  - Require host PS7 prerequisite: Increases friction and diverges from requirement that script self-manages prerequisites.

### 5. Artifact Retrieval Method
- Decision: Use `Invoke-WebRequest` + GitHub REST API (unauthenticated for public repo) to download `overlay.zip` release asset.
- Rationale: Avoids adding GitHub CLI dependency and simplifies minimal container.
- Alternatives Considered:
  - GitHub CLI (`gh release download`): Nice ergonomics but extra install overhead.
  - curl: Not installed by default in Server Core image (PowerShell already available after installation step).

### 6. Diagnostics Artifact Naming
- Decision: Export collected logs to `out/test-install/` within workspace then upload as GitHub Actions artifact named `installer-test-logs`.
- Rationale: Clear, scoped naming; folder allows multiple future files.
- Alternatives Considered:
  - Single flat file: Harder to separate transcript vs summary.
  - Randomized directory names: Harder to script retrieval.

### 7. Windows-Only Initial Scope
- Decision: Limit MVP to Windows container test; document potential Linux future test for parity around cross-platform overlay (not required to validate Windows provisioning).
- Rationale: Installer behavior risk highest on Windows for Windows-specific provisioning flows; reduces initial complexity.
- Alternatives Considered:
  - Add Linux container simultaneously: Doubles surface; no immediate requirement from spec.

## Implementation Notes (Derived from Decisions)

1. Script responsibilities: Resolve release tag, copy `bootstrap/` directory into container, run container executing the actual `bootstrap/install.ps1` script, capture exit code and artifacts.
2. Container run: Use `docker create` + `docker cp` + `docker exec` to mount the repo root and copy only the bootstrap directory, then execute the installer inside the container.
3. Inside container sequence:
   - Harness copies `bootstrap/install.ps1` into container
   - Container runs the actual installer: `powershell -File bootstrap/install.ps1 -Dest C:\albt-repo -Ref $releaseTag`
   - Installer handles all logic: downloading overlay.zip, extracting, validating installation
   - Container execution validates the real first-time user path without bypassing installer logic
4. Logging: Harness wraps execution with `Start-Transcript` to `install.transcript.txt`; captures exit code; emits summary JSON (fields: image, start/end, exitCode, durationSeconds, releaseTag, assetName, psVersion).
5. Export: Container transcript and summary are written to host-mounted output directory, automatically available on host.
6. Failure handling: Non-zero exit triggers script exit code 1 after writing summary; CI workflow uploads artifacts in `always()` block.
7. Environment overrides for local use: `ALBT_TEST_RELEASE_TAG`, `ALBT_TEST_IMAGE` (default windows/servercore:ltsc2022), `ALBT_TEST_KEEP_CONTAINER=1` (debug; skip --rm), `VERBOSE=1` enabling verbose logging.

## Open Follow-Ups (Deferred)
- Add optional Pester assertions verifying expected overlay file set after install.
- Add Linux container variant validating non-Windows path expansions.
- Provide caching strategy for repeated PowerShell MSI downloads (careful: container ephemeral).

## Summary of Decisions Table

| Topic | Decision | Key Rationale |
|-------|----------|---------------|
| Harness location | Separate script + workflow | Local reproducibility |
| Assertions | Defer Pester | Reduce complexity/time |
| Release selection | Latest release, override env | Validates shipped artifact |
| PS version | >=7.2 latest stable | Security & constitution alignment |
| Download method | Invoke-WebRequest | No extra dependency |
| Diagnostics naming | installer-test-logs | Clarity & grouping |
| Platform scope | Windows-only MVP | Focus & speed |

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| GitHub rate limiting unauthenticated | Download failure | Allow optional GITHUB_TOKEN env to add header |
| PowerShell MSI URL changes | Install break | Centralize URL construction; fallback doc link |
| Slow image pulls | Timeouts | Document pre-pull step in quickstart |
| Release asset rename changes | Asset not found | Match by exact name with fallback search pattern |

## Decision Validation Against Spec
All unknowns resolved; aligns with success criteria SC-001..SC-004 by ensuring deterministic, logged install test with reproducible local run.

## Parity Principle (Local vs CI)
To guarantee reproducibility without hidden CI behavior:
1. Future workflow YAML will only: checkout repo, invoke harness script, upload artifacts (always), and fail on non-zero exit.
2. No pre-install steps (e.g., adding PowerShell 7) may appear in workflow; absence of pwsh in base container is a deliberate test surface.
3. Local invocation must create identical transcript lines (aside from timestamps and CI-provided env vars) to simplify triage.
4. Enhancements (e.g., adding Pester) must reside in harness logic, not workflow glue, preserving single execution path.
5. Any deviation requires updating this parity section and justification in plan Complexity Tracking.

Enforcement: During implementation PR, reviewer checklist will confirm workflow diff contains no provisioning logic beyond invoking the harness.
