# Implementation Plan: CI: Unified cross-platform test discovery using Bats & Pester

**Branch**: `003-title-ci-unified` | **Date**: 2025-09-13 | **Spec**: `spec.md`
**Input**: Feature specification from `/specs/003-title-ci-unified/spec.md`

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
Introduce a dual-framework (Bats + Pester) test discovery mechanism executed sequentially inside a single `ubuntu-latest` CI job. The job auto-discovers `**/*.bats` and `**/*.Tests.ps1`, installs (or ensures) PowerShell 7 + Pester, enforces per-framework zero‑test guards, and removes legacy `test_*.sh` execution. Trade-off: native Windows filesystem/path semantics are not validated; a Windows runner can be reintroduced later if required.

## Technical Context
**Language/Version**: Bash (POSIX) & PowerShell 7 (invoked on Ubuntu)
**Primary Dependencies**: bats-core, PowerShell 7 + Pester v5 (installed on Ubuntu)
**Storage**: N/A (filesystem tests only)
**Testing**: Bats (`bats -r tests`), Pester (`pwsh -NoLogo -Command 'Invoke-Pester -Path tests -CI'`)
**Target Platform**: GitHub Actions runner: ubuntu-latest (single job)
**Project Type**: Single tooling repository (overlay scripts + tests)
**Performance Goals**: Keep added CI time < +2 min typical run
**Constraints**: No network beyond cloning bats-core; no new persistent artifacts
**Scale/Scope**: < 100 test files initially; recursive discovery must scale linearly.

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Simplicity**:
- Projects: 1 (repository root tooling + tests) ✔
- Using frameworks directly: Yes (bats / Pester) ✔
- Single conceptual model: Test discovery contract ✔
- Avoiding unnecessary patterns: No wrappers introduced ✔

**Architecture**:
- No new libraries; CI workflow only ✔
- Overlay untouched except tests added ✔
- No additional CLI entry points ✔
- Documentation updated in quickstart + contracts README ✔

**Testing (NON-NEGOTIABLE)**:
- RED-GREEN: New framework seed tests added first ✔
- Commit discipline: Port tests before removing legacy scripts (enforced via PR checklist) ✔
- Order: Contract (guard + discovery) → integration (existing behaviors) ✔
- Real dependencies: Executes actual scripts & filesystem ✔
- FORBIDDEN patterns avoided ✔

**Observability**:
- Framework native structured-ish summaries sufficient ✔
- Distinct guard error messages defined ✔
- Limitation documented: no native Windows filesystem semantics validated ✔

**Versioning**:
- External behavioral change (CI harness consolidation) documented ✔
- No semantic versioning artifact in repo; PR notes migration ✔
- Coverage parity table mitigates coverage regression ✔
- Future optional Windows runner addition considered non-breaking ✔

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

**Structure Decision**: Option 1 (single project) — no web/mobile segmentation required.

## Phase 0: Outline & Research
1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:
   ```
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: `research.md` (created) — contains decisions & rationale (see file).

## Phase 1: Design & Contracts
*Prerequisites: research.md complete*

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Generate API contracts** from functional requirements:
   - For each user action → endpoint
   - Use standard REST/GraphQL patterns
   - Output OpenAPI/GraphQL schema to `/contracts/`

3. **Generate contract tests** from contracts:
   - One test file per endpoint
   - Assert request/response schemas
   - Tests must fail (no implementation yet)

4. **Extract test scenarios** from user stories:
   - Each story → integration test scenario
   - Quickstart test = story validation steps

5. **Update agent file incrementally** (O(1) operation):
   - Run `/scripts/update-agent-context.sh [claude|gemini|copilot]` for your AI assistant
   - If exists: Add only NEW tech from current plan
   - Preserve manual additions between markers
   - Update recent changes (keep last 3)
   - Keep under 150 lines for token efficiency
   - Output to repository root

**Output**: `data-model.md`, `contracts/README.md`, `quickstart.md` (created). No API endpoints; contracts define discovery patterns & guard semantics.

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:
- Load `/templates/tasks-template.md` as base
- Generate tasks from Phase 1 design docs (contracts, data model, quickstart)
- Each contract → contract test task [P]
- Each entity → model creation task [P]
- Each user story → integration test task
- Implementation tasks to make tests pass

**Ordering Strategy**:
- TDD order: Tests before implementation
- Dependency order: Models before services before UI
- Mark [P] for parallel execution (independent files)

**Estimated Output**: 25-30 numbered, ordered tasks in tasks.md

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)
**Phase 4**: Implementation (execute tasks.md following constitutional principles)
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
No deviations—table intentionally empty.


## Progress Tracking
**Phase Status**:
- [x] Phase 0: Research complete (/plan command)
- [x] Phase 1: Design complete (/plan command)
- [ ] Phase 2: Task planning complete (/plan command - describe approach only)
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [x] Complexity deviations documented (none)

---
*Based on Constitution v2.1.1 - See `/memory/constitution.md`*