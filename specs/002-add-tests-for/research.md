# Research: Bootstrap Installer Contract Tests

Date: 2025-09-11
Feature: 002-add-tests-for

## Decisions
- Test Focus: Contract-level behavioral verification of `bootstrap/install.ps1`.
- Scope Limitation: Exclude network failure simulation to keep determinism.
- Fallback Extraction: Simulate absence of `unzip` by PATH manipulation; rely on python3 fallback.
- Dual Absence Failure: Simulate removal/absence of both `unzip` and `python3` via PATH isolation to assert hard failure path.
- Temp Isolation: Use `mktemp -d` per test to guarantee no cross contamination.
- PowerShell Invocation: Execute a tiny entry script with `pwsh -File` that dot-sources `bootstrap/install.ps1` and then calls `Install-AlBuildTools` explicitly. This relies on the installer’s dot-source–safe auto‑run guard.
- Idempotence Signal: Re-run installer and compare file lists + checksums (hash) for stability; only timestamps may vary (ignored).
- Git vs Non-Git: Initialize a temp git repo (`git init`) for git-context scenarios without committing overlay artifacts to avoid side effects.
- File Preservation: Place a sentinel file before re-run to ensure untouched.

## Rationale
- Deterministic, hermetic tests reduce CI flakiness and maintenance burden for a single maintainer.
- PATH-based tool hiding avoids system package mutation and is reversible within test scope.
- Hash comparison ensures deep idempotence beyond mere file count.

## Alternatives Considered
| Option | Rejected Because |
|--------|------------------|
| Containerized matrix (Docker) | Adds runtime + complexity not needed for scripts.
| Mocking network via local archive | Diverges from real bootstrap path; risk of drift.
| Copying overlay via git submodule for comparison | Unnecessary indirection; archive fetch already validated by installer logic.

## Open Items
None – all unknowns resolved.

## Constitution Alignment
- Idempotence: Explicit verification through re-run hashing.
- Zero Hidden State: No persistent artifacts outside temp dirs.
- Discover Over Configure: Tests observe real discovery logic, do not inject config.
- Minimal Entry Points: One minimal installer change implemented for safety (dot‑source–safe auto‑run guard in `install.ps1`); no end‑user behavior change.
