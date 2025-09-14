# AL Build Tools Constitution

## Core Principles

### I. Parity (Cross-Platform Symmetry)
Every Linux entry script has an exact PowerShell peer with the same name, contract, stdout shape, and exit semantics. A feature is incomplete unless both OS variants are implemented. Divergence in arguments, defaults, or output format is a defect.

Clarification (2025-09-10): Feature spec 001 (static analysis quality gate) intentionally defers automated detection of missing cross-platform peers in its first phase. This deferral does NOT waive or weaken the Parity principle; maintainers must still ensure that any newly added task or entry script is introduced simultaneously for both Linux and Windows prior to merge. Future phases may add automated parity enforcement to complement, not redefine, this requirement.

### II. Idempotence (Safe Re-Runs)
All tasks can be executed repeatedly without corrupting state or requiring manual cleanup. Build and clean operations must deterministically recalculate outputs and only remove/replace artifacts they own. Pre-existing unrelated files are never touched.

### III. Zero Hidden State
Tooling derives behavior solely from the workspace, explicit environment variables, and passed arguments. No opaque caches, no silently persisted config, no mutation of repository contents outside declared output paths. Temporary runtime artifacts stay out of version control.

### IV. Discover Over Configure
We auto-discover AL compiler, analyzers, and project metadata. User configuration is honored only when explicitly provided (e.g., `al.codeAnalyzers` list, environment overrides). No implicit enabling of analyzers or rulesets; absence means disabled.

### V. Minimal Entry Points & Shared Logic
The `Makefile` and top-level scripts remain thin dispatch layers. Reusable behavior lives in shared `lib/` helpers (bash & PowerShell mirrors). New functionality prefers extension of shared helpers over duplication. Safety guardrails (path validation, destructive action checks) are mandatory before invoking compiler or deleting artifacts.

## Operational Constraints & Boundaries
1. Overlay Integrity: Only the `overlay/` directory is shipped to consuming projects; all other repository content supports its evolution and must not introduce runtime coupling.
2. No Relocation: Do not rename or move published entry scripts or bootstrap installers; stability for downstream automation is paramount.
3. Generic Scope: Prohibit business/customer-specific logic; overlay must remain applicable to any AL project.
4. Security & Secrets: Read secrets exclusively from environment variables; never hardcode credentials or tokens.
5. Style Enforcement: Bash uses `set -euo pipefail`; PowerShell uses strict mode and explicit `param()` blocks. Filenames are kebab-case; logic is function-scoped.
6. Analyzer Handling: Only resolvable analyzers explicitly configured are executed; unresolved tokens trigger clear errors, not silent fallback.
7. Deterministic Outputs: Output package name pattern `${publisher}_${name}_${version}.app` is mandatory; pre-existing conflicting files are removed safely before creation.
8. Architecture Awareness: Compiler resolution must handle architecture-specific folders with graceful fallback to legacy locations.
9. No Silent Mutation: Scripts never rewrite project configuration files (e.g., `.vscode/settings.json`); inspection tasks are read-only.

## Development Workflow & Quality Gates
1. Feature Inception: New functionality begins with a spec (feature number + directory) generated via automation scripts; plans and task tracking follow.
2. Branch Naming: Use scripted generation (`scripts/create-new-feature.sh`) ensuring consistent numeric prefix for ordering & traceability.
3. Change Scope: Pull requests are surgical—only modify files directly supporting the stated feature or fix. Unrelated refactors are deferred.
4. Testing Requirements: Run build & clean twice on both OS variants; confirm idempotence and absence of residual or orphan artifacts. Validate analyzer resolution output when analyzers are configured.
5. Review Checklist: Parity achieved, no hidden state introduced, discovery rules preserved, minimal entry points unchanged, helper reuse evaluated.
6. Failure Transparency: All errors are directed to stderr with actionable, single-line summaries; multi-line diagnostics only when necessary.
7. Version Discipline: Tooling changes that alter external contract (arguments, output format, file layout) require a documented rationale and potential migration notes.
8. Pitfall Avoidance: Explicitly verify no addition of default analyzers, no temp files added inside `overlay/`, and no drift between Linux/Windows implementations.
9. Automation Sync: After significant structural updates, regenerate AI instruction contexts using the provided update script to keep agent guidance current.
10. Documentation Currency: New tasks or flags require updating relevant guidance (`AGENTS.md`, `.github/copilot-instructions.md`) in the same PR.

## Governance
This Constitution supersedes ancillary style notes where conflicts arise. Compliance is a mandatory review gate; PRs that violate any core principle must be revised before merge. Amendments require: (a) explicit motivation, (b) impact analysis (including downstream repos), (c) parity considerations, and (d) versioning / migration guidance if external contracts change. Consensus of maintainers plus documented approval in the PR description is required. Emergency fixes may merge ahead of documentation only when resolving breakage; documentation and (if needed) constitutional amendments must follow immediately.

**Version**: 1.0.1 | **Ratified**: 2025-09-10 | **Last Amended**: 2025-09-10