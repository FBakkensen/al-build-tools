# Tasks: Linux Installation Support

**Input**: Design documents from `/specs/009-linux-install-support/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Constitution Alignment**: This feature preserves overlay contract safety (no overlay changes), maintains Windows/Linux diagnostic parity, preserves guarded execution patterns and exit codes, and keeps copy-only release packaging.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare development environment and validate planning artifacts

- [x] T001 Verify constitution compliance per plan.md post-design re-check
- [x] T002 [P] Create development branch 009-linux-install-support
- [x] T003 [P] Validate contract schemas in specs/009-linux-install-support/contracts/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared utilities and patterns that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 Create bash utility functions for diagnostic markers in bootstrap/install-linux.sh (write_marker, write_step, write_prerequisite functions matching Windows format `[install] <type> key="value"`)
- [X] T005 [P] Create bash exit code constants in bootstrap/install-linux.sh (EXIT_SUCCESS=0, EXIT_GENERAL=1, EXIT_GUARD=2, EXIT_MISSING_TOOL=6)
- [X] T006 [P] Implement parameter parsing for Url, Ref, DestinationPath, Source with defaults in bootstrap/install-linux.sh
- [X] T007 [P] Implement git repository guard checks (is_git_repo, is_working_tree_clean) in bootstrap/install-linux.sh
- [X] T008 Implement unknown parameter guard check with usage message in bootstrap/install-linux.sh
- [X] T009 Validate bash version 4.0+ at script start and exit with diagnostic message if incompatible in bootstrap/install-linux.sh

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Fresh Installation on Ubuntu System (Priority: P1) 🎯 MVP

**Goal**: Enable complete AL Build Tools installation on Ubuntu from single command, handling all prerequisites automatically

**Independent Test**: Run installer on clean Ubuntu system with git repository, verify overlay files present in destination and build system functional (Invoke-Build commands work)

### Implementation for User Story 1

- [X] T010 [P] [US1] Implement prerequisite detection (check_git, check_powershell, check_dotnet, check_invokebuild) in bootstrap/install-prerequisites-linux.sh with version extraction
- [X] T011 [P] [US1] Implement sudo session validation (sudo -n true) with diagnostic marker in bootstrap/install-prerequisites-linux.sh
- [X] T012 [US1] Implement apt lock retry logic with exponential backoff (5s, 10s, 20s, max 3 retries) in bootstrap/install-prerequisites-linux.sh
- [X] T013 [US1] Implement Microsoft repository setup (download and install packages-microsoft-prod.deb) in bootstrap/install-prerequisites-linux.sh
- [X] T014 [US1] Implement apt cache update with retry logic in bootstrap/install-prerequisites-linux.sh
- [X] T015 [P] [US1] Implement git installation via apt (apt-get install -y git) in bootstrap/install-prerequisites-linux.sh
- [X] T016 [P] [US1] Implement PowerShell 7 installation via apt (apt-get install -y powershell) in bootstrap/install-prerequisites-linux.sh
- [X] T017 [P] [US1] Implement .NET SDK 8.0 installation via apt (apt-get install -y dotnet-sdk-8.0) in bootstrap/install-prerequisites-linux.sh
- [X] T018 [US1] Implement InvokeBuild module installation via pwsh (pwsh -Command "Install-Module InvokeBuild -Scope CurrentUser -Force") in bootstrap/install-prerequisites-linux.sh
- [X] T019 [US1] Implement prerequisite orchestration (detect all tools, install missing, emit status markers) in bootstrap/install-prerequisites-linux.sh with ALBT_AUTO_INSTALL support
- [X] T020 [US1] Implement GitHub release resolution (query GitHub API, parse latest non-draft release or specific tag) in bootstrap/install-linux.sh
- [X] T021 [US1] Implement overlay download via curl with timeout and diagnostic markers in bootstrap/install-linux.sh
- [X] T022 [US1] Implement overlay extraction (unzip) with corruption detection in bootstrap/install-linux.sh
- [X] T023 [US1] Implement file copy from extracted archive to destination (cp -r with progress markers) in bootstrap/install-linux.sh
- [X] T024 [US1] Implement git commit creation (git add, git commit) with initial commit detection in bootstrap/install-linux.sh
- [X] T025 [US1] Implement main installer orchestration (parameter validation, guards, prerequisite call, download, copy, commit, success message) in bootstrap/install-linux.sh
- [X] T026 [US1] Add execution phases with timing (release-resolution, prerequisite-installation, overlay-download, file-copy, git-commit) using phase_start/phase_end functions in bootstrap/install-linux.sh

**Checkpoint**: At this point, User Story 1 should be fully functional - installer works end-to-end on Ubuntu

---

## Phase 4: User Story 2 - Interactive Prerequisite Installation (Priority: P2)

**Goal**: Provide clear prompts and user control when prerequisites missing, building trust and transparency

**Independent Test**: Run installer without ALBT_AUTO_INSTALL on Ubuntu with missing prerequisites, verify interactive prompts appear for each tool, user can approve/decline each

### Implementation for User Story 2

- [X] T027 [US2] Implement interactive prompt function (read_user_input with validation, retry logic, 2s delay, example display) in bootstrap/install-prerequisites-linux.sh
- [X] T028 [US2] Add prerequisite installation prompts (display tool name, purpose, prompt for Y/n confirmation) for each missing tool in bootstrap/install-prerequisites-linux.sh
- [X] T029 [US2] Add graceful exit on user decline (emit diagnostic marker, exit with EXIT_MISSING_TOOL) in bootstrap/install-prerequisites-linux.sh
- [X] T030 [US2] Add prerequisite description messages (explain PowerShell 7 for overlay scripts, .NET SDK for AL compiler, InvokeBuild for build orchestration) in bootstrap/install-prerequisites-linux.sh
- [X] T031 [US2] Add apt cache update transparency message (display "Updating package cache..." during apt-get update) in bootstrap/install-prerequisites-linux.sh

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - auto-install mode (US1) and interactive mode (US2) both functional

---

## Phase 5: User Story 3 - Docker-Based Installation Testing (Priority: P3)

**Goal**: Validate installer reliability across clean Ubuntu installations, prerequisite scenarios, and failure modes using ephemeral Docker containers

**Independent Test**: Execute test harness with ubuntu:22.04 container and specific release tag, verify installer runs to completion, overlay files present in container, summary.json artifact generated with valid schema

### Implementation for User Story 3

- [X] T032 [P] [US3] Create test harness parameter parsing (ReleaseTag, BaseImage, KeepContainer, Verbose) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T033 [P] [US3] Implement Docker image pull and container provisioning (docker pull, docker run with volume mounts) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T034 [US3] Implement container setup script (install curl, git init, git config) generation in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T035 [US3] Implement installer execution in container (docker exec with environment variables ALBT_AUTO_INSTALL=1, ALBT_RELEASE) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T036 [US3] Implement transcript capture and artifact extraction (copy install.transcript.txt from container volume) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T037 [US3] Implement diagnostic marker parsing (extract prerequisite, step, guard, phase, diagnostic markers from transcript) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T038 [US3] Implement prerequisite status extraction (parse tool names, versions, status from markers) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T039 [US3] Implement execution phase extraction (parse phase names, start times, durations from markers) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T040 [US3] Implement git state validation (check repository created, commit hash extracted) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T041 [US3] Implement summary JSON generation (build InstallationSummary object with metadata, prerequisites, phases, gitState, release, exitCode, diagnostics) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T042 [US3] Implement JSON schema validation (validate summary.json against specs/009-linux-install-support/contracts/test-summary-schema.json) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T043 [US3] Implement provision log generation (capture container setup output separately) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T044 [US3] Implement container cleanup with ALBT_TEST_KEEP_CONTAINER support (docker rm unless keep flag set) in scripts/ci/test-bootstrap-install-linux.ps1
- [X] T045 [US3] Add test scenario support (fresh install, partial prerequisites, network failure simulation via environment variables) in scripts/ci/test-bootstrap-install-linux.ps1

**Checkpoint**: All three user stories should now be independently functional - installer works (US1), prompts work (US2), test harness validates (US3)

---

## Phase 6: User Story 4 - Diagnostic and Error Reporting Parity (Priority: P4)

**Goal**: Ensure consistent diagnostic output across Windows and Linux platforms for unified tooling, documentation, and support

**Independent Test**: Compare diagnostic output from Windows (bootstrap/install.ps1) and Linux (bootstrap/install-linux.sh) installers across equivalent scenarios (guard violations, missing prerequisites, successful install), verify marker format and exit codes match using diff or automated comparison script

### Implementation for User Story 4

- [ ] T046 [P] [US4] Validate exit code usage matches Windows installer (0=Success, 1=GeneralError, 2=Guard, 6=MissingTool) across all error paths in bootstrap/install-linux.sh
- [ ] T047 [P] [US4] Validate diagnostic marker format matches Windows pattern exactly (`[install] <type> key="value"`) in bootstrap/install-linux.sh
- [ ] T048 [P] [US4] Validate prerequisite markers match Windows (tool, status, version fields) in bootstrap/install-prerequisites-linux.sh
- [ ] T049 [P] [US4] Validate step markers match Windows (index, name fields) in bootstrap/install-linux.sh
- [ ] T050 [P] [US4] Validate guard markers match Windows (category field, usage message format) in bootstrap/install-linux.sh
- [ ] T051 [P] [US4] Validate phase markers match Windows (name, duration fields) in bootstrap/install-linux.sh
- [ ] T052 [US4] Create diagnostic comparison test script (run Windows and Linux installers in equivalent scenarios, extract markers, compare formats) in scripts/ci/validate-diagnostic-parity.ps1
- [ ] T053 [US4] Document Linux-specific diagnostic markers (sudoCached field in prerequisites) in specs/009-linux-install-support/contracts/installer-diagnostic-schema.json

**Checkpoint**: All user stories complete and diagnostic parity validated - Windows/Linux output consistent

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and prepare for release

- [ ] T054 [P] Add header banner to bootstrap/install-linux.sh matching Windows installer style (AL Build Tools Installation with version)
- [ ] T055 [P] Add help text and usage examples to bootstrap/install-linux.sh (display with -h or --help flag)
- [ ] T056 [P] Add verbose logging support (emit detailed output when VERBOSE=1 environment variable set) in bootstrap/install-linux.sh and bootstrap/install-prerequisites-linux.sh
- [ ] T057 [P] Update README.md with Linux installation instructions and one-liner curl command
- [ ] T058 [P] Create quickstart validation script (run through quickstart.md steps, verify expected behavior) in scripts/ci/validate-quickstart-linux.sh
- [ ] T059 [P] Add error message improvements (clear hints for common failures: no sudo, apt locked, network timeout) across all installer scripts
- [ ] T060 [P] Add platform detection to existing test harness (skip Linux tests on Windows hosts in scripts/ci/test-bootstrap-install-linux.ps1)
- [ ] T061 [P] Document ALBT environment variable overrides for Linux (ALBT_AUTO_INSTALL, ALBT_RELEASE, ALBT_TEST_IMAGE, VERBOSE) in specs/009-linux-install-support/contracts/README.md
- [ ] T062 Update CHANGELOG.md with Linux support feature description and breaking changes (none expected)
- [ ] T063 Run quickstart.md validation per specs/009-linux-install-support/quickstart.md testing scenarios
- [ ] T064 Execute full test suite (Pester tests if any, PSScriptAnalyzer, Docker test harness with multiple scenarios) to ensure no regressions

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can then proceed in priority order (P1 → P2 → P3 → P4)
  - Or with sufficient team capacity, US1 baseline → US2/US3/US4 in parallel
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories. **This is the MVP.**
- **User Story 2 (P2)**: Depends on User Story 1 completion (enhances US1 installer with interactive mode)
- **User Story 3 (P3)**: Can start after User Story 1 baseline complete (needs working installer to test)
- **User Story 4 (P4)**: Can start after User Story 1 baseline complete (validates US1 output against Windows)

### Within Each User Story

**User Story 1 (Core Installer)**:
- T010-T011 (prerequisite detection, sudo check) before T012-T018 (installations)
- T015-T017 (system packages: git, pwsh, dotnet) can run in parallel (marked [P])
- T018 (InvokeBuild) depends on T016 (PowerShell) being complete
- T019 (prerequisite orchestration) depends on all detection and installation tasks
- T020-T024 (overlay download, extract, copy, commit) must run sequentially
- T025-T026 (main orchestration, phases) depend on all above being complete

**User Story 2 (Interactive Mode)**:
- T027 (prompt function) before T028-T031 (using prompts)
- T028-T031 can be implemented in parallel after T027 complete (different prerequisites)

**User Story 3 (Test Harness)**:
- T032-T034 (setup) can run in parallel (marked [P])
- T035-T036 (execution, capture) must run after setup
- T037-T040 (parsing) can run in parallel after capture (marked [P])
- T041-T043 (summary, validation, provision log) run after parsing
- T044-T045 (cleanup, scenarios) run last

**User Story 4 (Parity Validation)**:
- T046-T051 (validation checks) can all run in parallel (marked [P]) - just validation/comparison tasks
- T052 (comparison script) can run in parallel with validations
- T053 (documentation) can run in parallel with validations

### Parallel Opportunities

**Phase 2 (Foundational)**:
- T005, T006, T007 can run in parallel (different concerns: exit codes, parameters, git checks)

**Phase 3 (User Story 1)**:
- T010, T011 (detection functions) in parallel
- T015, T016, T017 (git, pwsh, dotnet installation) in parallel after prerequisites ready

**Phase 4 (User Story 2)**:
- After T027 (prompt function) complete: T028, T029, T030, T031 in parallel (different prerequisite prompts)

**Phase 5 (User Story 3)**:
- T032, T033 in parallel (parameter parsing, Docker setup)
- T037, T038, T039, T040 in parallel (different marker types parsing)

**Phase 6 (User Story 4)**:
- T046, T047, T048, T049, T050, T051, T052, T053 all in parallel (validation checks, comparison, docs)

**Phase 7 (Polish)**:
- T054, T055, T056, T057, T058, T059, T060, T061 all in parallel (different files/concerns)

---

## Parallel Example: User Story 1 Core Implementation

```bash
# After foundational phase complete, start User Story 1:

# Launch prerequisite detection in parallel:
Task T010: "Implement prerequisite detection functions in bootstrap/install-prerequisites-linux.sh"
Task T011: "Implement sudo session validation in bootstrap/install-prerequisites-linux.sh"

# After detection complete, launch installations in parallel:
Task T015: "Implement git installation via apt in bootstrap/install-prerequisites-linux.sh"
Task T016: "Implement PowerShell 7 installation via apt in bootstrap/install-prerequisites-linux.sh"
Task T017: "Implement .NET SDK installation via apt in bootstrap/install-prerequisites-linux.sh"

# Then continue with sequential overlay installation tasks T020-T026
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (validate artifacts)
2. Complete Phase 2: Foundational (bash utilities, guards, parameter parsing) **CRITICAL BLOCKER**
3. Complete Phase 3: User Story 1 (full installer functionality)
4. **STOP and VALIDATE**: Test installer on clean Ubuntu 22.04 system
   - Run: `sudo -v && bash bootstrap/install-linux.sh`
   - Verify: overlay/ files copied, Invoke-Build works, git commit created
   - Expected: Exit code 0, all diagnostic markers present
5. Deploy/demo if ready - **Linux support MVP complete!**

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test on Ubuntu → **MVP release candidate**
3. Add User Story 2 → Test interactive prompts → Enhanced UX
4. Add User Story 3 → Test harness validates → CI integration ready
5. Add User Story 4 → Diagnostic parity confirmed → Production ready
6. Polish phase → Documentation, optimization → Final release

Each story adds value without breaking previous stories.

### Parallel Team Strategy

With multiple developers after Foundational phase complete:

1. **Developer A (Priority)**: User Story 1 (T010-T026) - Core installer - MUST complete first
2. Once US1 baseline working:
   - **Developer B**: User Story 2 (T027-T031) - Interactive mode enhancements
   - **Developer C**: User Story 3 (T032-T045) - Test harness
   - **Developer D**: User Story 4 (T046-T053) - Parity validation

---

## Task Summary

- **Total Tasks**: 64 tasks (increased from 63 due to FR-018 bash version check)
- **Phase 1 (Setup)**: 3 tasks
- **Phase 2 (Foundational)**: 6 tasks (BLOCKS all user stories) - added T009 for bash version validation
- **Phase 3 (User Story 1 - Core Installer)**: 17 tasks ⭐ **MVP**
- **Phase 4 (User Story 2 - Interactive Mode)**: 5 tasks
- **Phase 5 (User Story 3 - Test Harness)**: 14 tasks
- **Phase 6 (User Story 4 - Diagnostic Parity)**: 8 tasks
- **Phase 7 (Polish)**: 11 tasks

**Parallel Opportunities**: 26 tasks marked [P] can run in parallel with their phase siblings

**Independent Test Criteria**:
- **US1**: Run installer on clean Ubuntu → overlay present, build works
- **US2**: Run installer without auto-install → prompts appear, user can control
- **US3**: Run test harness → summary.json generated, schema valid
- **US4**: Compare Windows/Linux output → markers match, exit codes consistent

**Suggested MVP Scope**: Phase 1 + Phase 2 + Phase 3 (User Story 1) = 26 tasks

---

## Notes

- **[P]** tasks target different files or have no dependencies within their phase
- **[Story]** label maps task to specific user story for traceability and independent validation
- Each user story should be independently completable and testable
- **Critical**: Bootstrap installer MUST be bash (PowerShell is a prerequisite being installed)
- After PowerShell installed, bash may delegate to pwsh for InvokeBuild module installation
- Test harness is PowerShell (runs on host with Docker, not inside container)
- No overlay changes needed - existing scripts already cross-platform compatible
- Constitution compliance validated: no overlay contract changes, Windows/Linux parity maintained, exit codes preserved
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Validate against contracts in specs/009-linux-install-support/contracts/ after implementation
