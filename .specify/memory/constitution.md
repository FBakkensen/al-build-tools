# AL Build Tools Constitution

## Core Tenets

### 1. Cross-Platform Parity
Every user-facing capability ships with Linux and Windows entry points that share names, arguments, exit semantics, and observable output. Launching a task on one platform must feel indistinguishable from the other. Shipping a feature on a single OS violates this charter.

### 2. Repeatable Operations
Build, clean, and inspection commands are safe to run repeatedly. They act only on declared artifacts, leave unrelated files untouched, and produce deterministic results. Automation and humans can rerun the toolkit without fear of drift.

### 3. Workspace Purity
Tooling honors the repository as the source of truth. Behavior derives strictly from checked-in files, supplied arguments, and explicit environment variables. No hidden caches, implicit configuration, or silent mutation of user files are permitted.

### 4. Transparent Contracts
Published scripts emit clear status signals: documented exit codes, actionable errors routed to stderr, and stable stdout intended for chaining. Any change to those contracts requires deliberate versioning and communication before release.

### 5. Overlay Minimalism
The copied `overlay/` payload remains a thin, self-contained surface. Everything inside is treated as an external contract, stays free of internal coupling, avoids network access, and exposes only the entry points end users must invoke.

## Non-Negotiable Guardrails
- **Security First**: Secrets are never embedded; credentials flow only through environment variables or tooling already managed by users.
- **Environment Isolation**: Child processes must not leak or overwrite caller environment state. Any temporary context stays process-scoped or lives under disposable directories.
- **Deterministic Artifacts**: Output names, locations, and cleanup rules are predictable and reversible. Artifacts belong under the target app directory, with collisions resolved safely.
- **Analyzer Discipline**: Analyzers run only when explicitly configured. Discovery favors reporting over guessing; absence of configuration means analyzers stay disabled.
- **Safety Checks**: Scripts validate paths and inputs before deleting files or invoking compilers. Guard clauses prevent destructive operations outside the app boundary.

## Delivery Discipline
1. **Spec Before Build**: Significant work begins with a numbered spec describing motivation, scope, parity expectations, and verification strategy.
2. **Focused Changes**: Contributions touch only the files required for the stated objective. Opportunistic refactors or feature creep are deferred.
3. **Symmetric Testing**: Contributors validate Linux and Windows flows, including double-run idempotence, before declaring a change complete.
4. **Documentation in Lockstep**: Any new flag, behavior, or contract adjustment updates user guidance and agent instructions in the same change set.
5. **Observable Failures**: Errors are concise, single-line summaries with optional diagnostics beneath. Success paths are equally explicit about what occurred.

## Governance
This Constitution outranks ancillary notes when conflicts arise. Amending a tenet or guardrail demands: clear motivation, downstream impact analysis, parity verification, and documented maintainer approval. Emergency fixes may bypass documentation only to stop an active regression; remediation notes and (if needed) constitutional updates follow immediately.

**Version**: 1.1.0 | **Ratified**: 2025-09-10 | **Last Amended**: 2025-09-16
