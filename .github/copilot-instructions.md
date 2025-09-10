# GitHub Copilot Project Instructions

Concise, actionable guidance for AI coding agents contributing to `al-build-tools`.

## Purpose & Core Concept
This repo ships a self‑contained build "overlay" for Microsoft AL projects. Only `overlay/` is copied into target repos via the bootstrap (curl | bash / iwr | iex). Everything else here exists to maintain and evolve that payload. Keep `overlay/` stable, minimal, cross‑platform, and idempotent.

## High‑Value Directories
- `overlay/` (the product): Makefile + mirrored `scripts/make/{linux,windows}` toolchain.
- `overlay/scripts/make/linux|windows/`: Paired script sets; any new task must exist in both with same semantics & name.
- `overlay/scripts/make/**/lib/`: Shared helpers (`common.*`, `json-parser.*`). Avoid duplication; extend here when logic is reused.
- `bootstrap/`: One‑liner installers (do not add heavy logic here; they only copy `overlay/*`).
- `scripts/`: Internal contributor automation (feature spec workflow, context updaters). Never copied to consuming repos.
- `templates/`: Markdown scaffolds used by scripts in `scripts/`.

## Build & Inspection Workflow (Post‑Install in a Target Repo)
```bash
bash scripts/make/linux/build.sh [AppDir]
bash scripts/make/linux/clean.sh [AppDir]
bash scripts/make/linux/show-config.sh [AppDir]
bash scripts/make/linux/show-analyzers.sh [AppDir]
# Windows equivalents: pwsh -File scripts/make/windows/<same>.ps1
# Optional make wrapper: make build | make clean
```
Defaults assume `AppDir=app` and presence of `app/app.json`.

## Script Design Principles
1. Parity: Every Linux script has a PowerShell peer; keep argument contract, stdout shape, return codes aligned.
2. Idempotence: Re-running build or clean must not corrupt state; guard deletions and re-compute dynamically.
3. Zero hidden state: Derive everything from the workspace (no caches, no temp config files committed).
4. Discover vs configure: Auto-detect AL extension & analyzers; only honor explicit user configuration (no silent defaults for analyzers when unset).
5. Minimal entry points: Keep `Makefile` a thin dispatcher; heavy logic lives in libs.

## Key Implementation Details (Linux side mirrors Windows)
- Compiler resolution: `get_al_compiler_path` searches highest `ms-dynamics-smb.al-*` extension and architecture-aware `bin/linux-<arch>/alc` fallback.
- Analyzer resolution: Reads `.vscode/settings.json` `al.codeAnalyzers` list; supports tokens like `${analyzerFolder}` & `${alExtensionPath}`; no implicit enabling.
- Output naming: `${publisher}_${name}_${version}.app` derived via `jq`; ensure `jq` availability before relying on it.
- Environment toggles: `ALC_PATH` (override compiler), `RULESET_PATH` (ruleset file, only if non-empty), `WARN_AS_ERROR=1` (adds /warnaserror+).
- Safety: Build script deletes an existing output file (or conflicting directory) before invoking `alc`.

## Adding a New Task (Example: 'package-info')
1. Create `overlay/scripts/make/linux/package-info.sh` and `overlay/scripts/make/windows/package-info.ps1`.
2. Source respective `lib/common` + `lib/json-parser` modules.
3. Accept optional `[AppDir]` positional argument (default `app`).
4. Implement logic (e.g., dump parsed `app.json` summary) using existing helper functions where possible.
5. Keep output concise, plain text; return non‑zero on hard errors only.
6. (Optional) Add a thin `Makefile` target if symmetry with others is useful.

## Feature / Spec Workflow (Maintainers Only)
- Branch naming: auto via `scripts/create-new-feature.sh "Description"` → `NNN-key-words`.
- Generated structure under `specs/NNN-*`: `spec.md`, later `plan.md`, `tasks.md`, etc.
- Validation helpers: `scripts/get-feature-paths.sh`, `scripts/check-task-prerequisites.sh`.
- Plan setup: `scripts/setup-plan.sh` creates/updates `plan.md` from template.
- Agent context refresh: `scripts/update-agent-context.sh [copilot|claude|gemini]` updates `.github/copilot-instructions.md` or other agent files incrementally.

## Modification Boundaries
- Do NOT rename or relocate existing entry scripts under `overlay/scripts/make/*` or bootstrap installers.
- Avoid introducing external network calls or dependencies (keep offline except during bootstrap download by user).
- Keep POSIX sh-compatible constructs where practical (but repo uses bash features deliberately where helpful; do not downgrade if clarity suffers).
- PowerShell: Maintain `Set-StrictMode`, `$ErrorActionPreference='Stop'`, explicit `param()` blocks.

## Testing & Verification
- Manual smoke: Run build & clean twice; verify no residual artifacts or errors.
- Analyzer display: `show-analyzers.sh` must list enabled names + resolved DLL paths; confirm token expansion.
- Cross-arch fallback: Ensure `get_al_compiler_path` still resolves when preferred arch subfolder absent (legacy `bin/linux/alc`).

## Common Pitfalls to Avoid
- Adding default analyzers when user has none configured.
- Writing temp files into `overlay/` during build (must remain pure tooling).
- Diverging stdout formats between OS variants.
- Embedding business/project specifics (overlay must stay generic for any AL project).

## When Unsure
Prefer extending shared libs or adding a new helper function instead of duplicating logic. Keep diffs surgical. Ask in PR if a pattern feels repo‑wide.

