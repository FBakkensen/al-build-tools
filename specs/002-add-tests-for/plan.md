# Implementation Plan: Bootstrap Installer Contract Tests

**Branch**: `002-add-tests-for` | **Date**: 2025-09-11 | **Spec**: `/home/fbakkensen/repos/al-build-tools/specs/002-add-tests-for/spec.md`
**Input**: Feature specification from `/specs/002-add-tests-for/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → If not found: ERROR "No feature spec at {path}"
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → Detect Project Type from context (web=frontend+backend, mobile=app+api)
   → Set Structure Decision based on project type
3. Evaluate Constitution Check section below
   → If violations exist: Document in Complexity Tracking
   → If no justification possible: ERROR "Simplify approach first"
   → Update Progress Tracking: Initial Constitution Check
4. Execute Phase 0 → research.md
   → If NEEDS CLARIFICATION remain: ERROR "Resolve unknowns"
5. Execute Phase 1 → contracts, data-model.md, quickstart.md, agent-specific template file (e.g., `CLAUDE.md` for Claude Code, `.github/copilot-instructions.md` for GitHub Copilot, or `GEMINI.md` for Gemini CLI).
6. Re-evaluate Constitution Check section
   → If new violations: Refactor design, return to Phase 1
   → Update Progress Tracking: Post-Design Constitution Check
7. Plan Phase 2 → Describe task generation approach (DO NOT create tasks.md)
8. STOP - Ready for /tasks command
```

**IMPORTANT**: The /plan command STOPS at step 7. Phases 2-4 are executed by other commands:
- Phase 2: /tasks command creates tasks.md
- Phase 3-4: Implementation execution (manual or via tools)

## Summary
Add deterministic contract tests validating observable behaviors of `bootstrap/install.ps1`: successful initial install, idempotent re-run, git vs non-git messaging, custom destination creation, preservation of unrelated files, absence of side effects, and edge cases (spaces in path, read-only failure). Approach uses isolated temp directories, checksum hashing for idempotence, and invocation of PowerShell via `pwsh` on Linux.

## Technical Context
**Language/Version**: PowerShell 7, minimal coreutils
**Primary Dependencies**: PowerShell 7 (`pwsh`), git (detection), sha256sum
**Storage**: N/A (ephemeral temp dirs only)
**Testing**: Shell contract tests invoking `install.ps1` via `pwsh`
**Target Platform**: Linux CI runner (PowerShell executed cross-platform)
**Project Type**: single (tooling repo)
**Performance Goals**: Total added test runtime < 120s
**Constraints**: Deterministic; no network failure simulation; no external side effects
**Scale/Scope**: Small single-maintainer test addition; <10 new test scripts

## Constitution Check
*Initial Gate & Post-Design Review*

**Simplicity**:
- Projects: 1 (existing repo structure unchanged)
- No frameworks added; direct shell usage only.
- No additional abstraction layers; plain test scripts.
- No patterns introduced (Repository/UoW N/A).

**Architecture**:
- No new libraries; tests only.
- No CLI additions required.
- Documentation limited to spec artifacts created.

**Testing (NON-NEGOTIABLE)**:
- Contract tests added first (failing until implementation adjustments if any needed). Existing installer already behaves; tests assert current contract.
- Order: Only contract layer relevant (no integration/service layers needed).
- Real dependencies: yes (`pwsh`, git).
- No mocks.

**Observability**:
- Rely on existing script stderr/messages; no new logging required.
- Failure assertions check clarity of messages.

**Versioning**:
- No user‑visible contract change. One internal safety tweak added to `install.ps1` (dot‑source–safe auto‑run guard) to enable hermetic tests and prevent accidental repo pollution.
- No version bump needed.

Result: PASS (no violations). Re-check after Phase 1: PASS.

## Project Structure

### Documentation (this feature)
```
specs/[###-feature]/
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (/plan command)
├── data-model.md        # Phase 1 output (/plan command)
├── quickstart.md        # Phase 1 output (/plan command)
├── contracts/           # Phase 1 output (/plan command)
└── tasks.md             # Phase 2 output (/tasks command - NOT created by /plan)
```

### Source Code (repository root)
```
# Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
├── cli/
└── lib/

tests/
├── contract/
├── integration/
└── unit/

# Option 2: Web application (when "frontend" + "backend" detected)
backend/
├── src/
│   ├── models/
│   ├── services/
│   └── api/
└── tests/

frontend/
├── src/
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure]
```

**Structure Decision**: Option 1 (single project tests only)

## Phase 0: Outline & Research
Completed (see `research.md`). All unknowns resolved; decisions documented (tool hiding via PATH, hashing strategy, exclusion boundaries).

## Phase 1: Design & Contracts
Completed: `data-model.md`, `contracts/README.md`, `quickstart.md` produced. Contract mapping table enumerates each requirement. No additional agent context changes required (tech stack unchanged).

## Phase 2: Task Planning Approach
Each contract (C-INIT, C-IDEMP, C-GIT, C-CUSTOM-DEST, C-PRESERVE, C-GIT-METADATA, C-REPORT, C-NO-SIDE-EFFECTS, C-SPACES, C-READONLY) will yield one test task. Estimated 9–10 tasks (lean approach). Order: basic success first → idempotence → environment variations → edge cases.

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)
**Phase 4**: Implementation (execute tasks.md following constitutional principles)
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
No deviations; table intentionally empty.


## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command)
- [x] Phase 1: Design complete (/plan command)
- [x] Phase 2: Task planning complete (/plan command - describe approach only)
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [x] Complexity deviations documented

---
*Based on Constitution v2.1.1 - See `/memory/constitution.md`*
