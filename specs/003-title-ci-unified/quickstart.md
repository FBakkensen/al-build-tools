## Quickstart: Adding & Running Tests (Single Ubuntu Runner)

### 1. Add a Linux Test (Bats)
Create a file `tests/contract/example.bats`:
```bash
#!/usr/bin/env bash
set -euo pipefail
@test "example passes" {
  run bash -c 'echo hello'
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}
```

Run locally:
```bash
git clone --depth 1 https://github.com/bats-core/bats-core.git .bats-core
sudo .bats-core/install.sh /usr/local
bats -r tests
```

### 2. Add a PowerShell Test (Pester on Ubuntu)
Create `tests/contract/Example.Tests.ps1`:
```powershell
#requires -Version 7.0
Describe "Example" {
  It "passes" {
    "hello" | Should -Be "hello"
  }
}
```

Run locally (PowerShell 7, install if needed on Ubuntu):
```powershell
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester -Path tests -CI
```

### 3. Naming Rules
- Bats: `*.bats`
- Pester: `*.Tests.ps1`
- Place anywhere under `tests/`; subfolders allowed (`contract`, `integration`).

### 4. Zero-Test Guards
The single CI job fails if a framework has zero tests:
- Bats: `No Bats tests (*.bats) found under tests/.`
- Pester: `No Pester tests (*.Tests.ps1) found under tests/.`

### 5. Migrating Legacy Shell Tests
Port each `test_*.sh` to a framework file. Keep semantics; remove the legacy file only after new test passes.

### 6. Local Tips
- Use `bats -f <pattern>` to run subset (Linux).
- Use `pwsh -NoLogo -Command "Invoke-Pester -Path tests/contract -CI -TestName <name>"` to narrow scope.
- To install PowerShell on Ubuntu quickly (APT):
```bash
sudo apt-get update
sudo apt-get install -y wget apt-transport-https software-properties-common
source /etc/os-release
wget -q https://packages.microsoft.com/config/ubuntu/$VERSION_ID/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell
```

### 7. Troubleshooting
| Symptom | Cause | Fix |
|---------|-------|-----|
| Bats guard failure | No `*.bats` files committed | Add at least one Bats test |
| Pester guard failure | No `*.Tests.ps1` files | Add a Pester test |
| `pwsh` not found | PowerShell not installed | Install via APT (see above) |
| Pester not found | Module not installed locally | Install-Module Pester (see above) |

### 8. Future Extensions (Non-blocking)
- Reintroduce Windows runner for native semantics validation
- Export JUnit for test summaries
- Lint misnamed test files
