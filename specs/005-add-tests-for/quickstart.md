# Quickstart: Validating install.ps1 Behavior

## Prerequisites
- PowerShell 7+
- Git installed and in PATH

## Steps (Windows or Ubuntu)
```pwsh
# 1. Clone a clean copy
git clone https://github.com/FBakkensen/al-build-tools demo-install-test
cd demo-install-test

# 2. Run installer (default)
pwsh -File bootstrap/install.ps1

# 3. Re-run to verify overwrite idempotence
pwsh -File bootstrap/install.ps1

# 4. Introduce dirty state (expect failure)
Set-Content overlay/TEST-DIRTY.txt 'local change'
pwsh -File bootstrap/install.ps1 # should abort due to non-clean working tree

# 5. Simulate missing git repo (expect failure)
mkdir ..\no-git
Copy-Item -Recurse * ..\no-git
cd ..\no-git
pwsh -File bootstrap/install.ps1 # should abort (no .git)
```

## Expected Outcomes
- Two successful runs with identical success summaries.
- Third run aborts with guidance about cleaning working tree.
- Non-git directory run aborts with guidance about initializing git repository.

## Performance Check
Execution time for a default run should be <30s (network dependent). Use `Measure-Command` locally if concerned about regressions.

## Parity Confirmation
Run the same steps in Ubuntu shell (`pwsh`) with only path differences; outputs must be structurally comparable.
