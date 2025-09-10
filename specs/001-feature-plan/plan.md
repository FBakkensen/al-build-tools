# Implementation Plan: Automated Static Analysis Quality Gate on Pull Requests

**Branch**: `001-feature-plan` | **Date**: 2025-09-10 | **Spec**: `/home/fbakkensen/repos/al-build-tools/specs/001-feature-plan/spec.md`
**Input**: Feature specification from `/specs/001-feature-plan/spec.md`

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
Introduce a simple, fast quality gate that runs on every pull request affecting distributed tooling (`overlay/` & `bootstrap/`). Gate performs static checks for shell & PowerShell scripts plus JSON & ruleset validation. Goal: surface obvious defects (syntax, structural issues, disallowed patterns) in <30s typical runtime and block merges on blocking categories. Keep implementation minimal: a single GitHub Actions workflow invoking lightweight local scripts (no external services, no complex orchestration).

## Technical Context
**Language/Version**: Bash (GNU Bash 5+), PowerShell 7+
**Primary Dependencies**: `shellcheck` (bash lint), `pwsh` builtin parser (`-NoLogo -Command {}`), `PSScriptAnalyzer` (REQUIRED), `jq` for JSON structural checks
**Storage**: N/A (ephemeral CI workspace only)
**Testing**: Manual verification via repeated PR runs; future phase may add scripted tests
**Target Platform**: GitHub Actions Ubuntu runner (Linux); Windows script syntax check executed via PowerShell Core on Linux (parsing only)
**Project Type**: Single tooling repository
**Performance Goals**: 95% runs ≤30s, hard timeout 60s
**Constraints**: No network installs beyond what runner already provides; must fail fast if required tool missing
**Scale/Scope**: Small codebase (<1K lines in scope); single maintainer oriented

## Constitution Check
Satisfies core principles:
Simplicity: Single repository, no new subprojects, minimal one workflow + helper script. No abstraction layers introduced.
Architecture: No libraries added; simple scripts under `scripts/ci/` (non-shipped) keep overlay untouched; parity preserved because no runtime path changes for shipped scripts.
Testing: Manual validation acceptable for initial gate; future automated tests deferred (documented). Failing workflow run acts as RED signal. `PSScriptAnalyzer` absence is a blocking Configuration failure to prevent silent reduction in coverage.
Observability: CI step outputs concise per-file diagnostics (stderr for failures). No additional logging stack required.
Versioning: No external contract changes; documentation update only. No version bump required.

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

**Structure Decision**: Option 1 (single project) retained; no new src/ layout needed.

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

**Output**: `research.md` confirms approach & tool availability assumptions (all resolved).

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

**Output**: `data-model.md` (trivial: no persistent entities), `contracts/README.md` (no external API), `quickstart.md` (how to trigger & interpret workflow). No agent file changes needed beyond existing instructions.

## Phase 2: Task Planning Approach
Minimal tasks (already generated in `tasks.md` for simplicity) focus on: adding workflow, adding validation script, implementing JSON/ruleset checks, wiring diagnostics & docs. Parallelism unnecessary due to small scope.

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)
**Phase 4**: Implementation (execute tasks.md following constitutional principles)
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |


## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command)
- [x] Phase 1: Design complete (/plan command)
- [x] Phase 2: Task planning complete (/plan command - simplified)
- [ ] Phase 3: Tasks generated (/tasks command) – already pre-created for speed
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [ ] Complexity deviations documented (none needed)

---
*Based on Constitution v2.1.1 - See `/memory/constitution.md`*