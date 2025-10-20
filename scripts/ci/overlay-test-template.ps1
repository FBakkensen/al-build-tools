#requires -Version 7.2
# Container test script for overlay provision - Scenario testing
# This script runs inside the Windows container to test overlay/ scripts
# across 3 provision scenarios: no dependencies, empty dependencies, with dependency
#
# SCOPE: Tests ONLY overlay provision scripts (download-compiler.ps1, download-symbols.ps1).
# Does NOT test bootstrap installer functionality.

param(
    [string]$OverlayPath = 'C:\overlay',
    [string]$FixturesPath = 'C:\fixtures',
    [string]$WorkspacePath = 'C:\workspace'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure output is not buffered
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Track overall test results
$script:AllScenariosPass = $true
$script:ScenarioResults = @{}

# ============================================================================
# Setup: Run infrastructure setup script once at container startup
# ============================================================================
Write-Host "[container] Running infrastructure setup..."
[Console]::Out.Flush()

# Infrastructure setup script should be mounted by test harness at C:\bootstrap
$setupScript = "C:\bootstrap\setup-infrastructure.ps1"
if (-not (Test-Path $setupScript)) {
    Write-Host "[container] ERROR: Infrastructure setup script not found at $setupScript" -ForegroundColor Red
    [Console]::Out.Flush()
    exit 1
}

# Run setup in non-interactive mode (skip Git, focus on .NET and InvokeBuild)
$env:ALBT_AUTO_INSTALL = '1'
& pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript -SkipGit -Verbose 2>&1 | ForEach-Object {
    Write-Host "[setup] $_"
    [Console]::Out.Flush()
}
$setupExitCode = $LASTEXITCODE

if ($setupExitCode -ne 0) {
    Write-Host "[container] ERROR: Infrastructure setup failed with exit code $setupExitCode" -ForegroundColor Red
    [Console]::Out.Flush()
    exit 1
}

Write-Host "[container] Infrastructure setup complete"
[Console]::Out.Flush()

# Verify InvokeBuild is available
$ibModule = Get-Module -ListAvailable -Name InvokeBuild -ErrorAction SilentlyContinue
if (-not $ibModule) {
    Write-Host "[container] ERROR: InvokeBuild module not found after setup" -ForegroundColor Red
    [Console]::Out.Flush()
    exit 1
}

# Import module
Import-Module InvokeBuild -Force
Write-Host "[container] InvokeBuild module loaded (version: $($ibModule.Version))"
[Console]::Out.Flush()

# ============================================================================
# Test Helper Functions
# ============================================================================


function Write-TestMessage {
    param(
        [string]$Message,
        [string]$Type = 'Info'
    )

    $timestamp = Get-Date -Format 'HH:mm:ss.fff'
    $prefix = switch ($Type) {
        'Info' { '[INFO]' }
        'Success' { '[PASS]' }
        'Error' { '[FAIL]' }
        'Debug' { '[DEBUG]' }
        'Scenario' { '[SCEN]' }
        default { '[INFO]' }
    }

    Write-Host "$timestamp $prefix $Message"
    [Console]::Out.Flush()
    [Console]::Error.Flush()
}

function Setup-Scenario1 {
    Write-TestMessage "Setting up Scenario 1: No dependencies property" -Type Scenario

    $scenarioPath = Join-Path $WorkspacePath "scenario1"
    $fixturePath = Join-Path $FixturesPath "scenario1-no-dependencies"

    Write-TestMessage "Copying fixture from $fixturePath to $scenarioPath" -Type Info
    Copy-Item -Path $fixturePath -Destination $scenarioPath -Recurse -Force

    Write-TestMessage "Scenario 1 setup complete" -Type Success
    return $scenarioPath
}

function Setup-Scenario2 {
    Write-TestMessage "Setting up Scenario 2: Empty dependencies array" -Type Scenario

    $scenarioPath = Join-Path $WorkspacePath "scenario2"
    $fixturePath = Join-Path $FixturesPath "scenario2-empty-dependencies"

    Write-TestMessage "Copying fixture from $fixturePath to $scenarioPath" -Type Info
    Copy-Item -Path $fixturePath -Destination $scenarioPath -Recurse -Force

    Write-TestMessage "Scenario 2 setup complete" -Type Success
    return $scenarioPath
}

function Setup-Scenario3 {
    Write-TestMessage "Setting up Scenario 3: With dependency" -Type Scenario

    $scenarioPath = Join-Path $WorkspacePath "scenario3"
    $fixturePath = Join-Path $FixturesPath "scenario3-with-dependency"

    Write-TestMessage "Copying fixture from $fixturePath to $scenarioPath" -Type Info
    Copy-Item -Path $fixturePath -Destination $scenarioPath -Recurse -Force

    Write-TestMessage "Scenario 3 setup complete" -Type Success
    return $scenarioPath
}

function Run-Provision {
    param(
        [string]$ScenarioPath,
        [int]$ScenarioNum
    )

    Write-TestMessage "Running provision for Scenario $ScenarioNum at: $ScenarioPath" -Type Info

    $provisionOutput = @()
    $exitCode = 0

    try {
        Push-Location $ScenarioPath

        # Run provision task using InvokeBuild
        $buildScript = Join-Path $OverlayPath "al.build.ps1"
        Write-TestMessage "Running provision task: Invoke-Build -File $buildScript provision -AppDir $ScenarioPath" -Type Debug

        # Run Invoke-Build directly
        Write-Host "[container] Executing: Invoke-Build -File $buildScript provision -AppDir $ScenarioPath"
        [Console]::Out.Flush()

        Invoke-Build -File $buildScript provision -AppDir $ScenarioPath 2>&1 | ForEach-Object {
            Write-Host $_
            $provisionOutput += $_
            [Console]::Out.Flush()
        }

        $exitCode = $LASTEXITCODE
        Write-Host "[container] Invoke-Build completed with exit code: $exitCode"
        [Console]::Out.Flush()

        if ($exitCode -ne 0) {
            Write-TestMessage "Provision failed with exit code: $exitCode" -Type Error
        } else {
            Write-TestMessage "Provision completed successfully" -Type Success
        }
    }
    catch {
        Write-TestMessage "Provision failed with exception: $($_.Exception.Message)" -Type Error
        $exitCode = 1
    }
    finally {
        Pop-Location
    }

    return @{ ExitCode = $exitCode; Output = $provisionOutput }
}

function Validate-Scenario1 {
    param([object[]]$Output)

    Write-TestMessage "Validating Scenario 1 (no dependencies property)..." -Type Info
    $validationSteps = @()
    $pass = $true

    # Step 1: Check exit code
    $step1 = @{ step = "Provision exit code 0"; passed = $false }
    if ($Output.ExitCode -eq 0) {
        Write-TestMessage "✓ Provision exited successfully" -Type Success
        $step1.passed = $true
    } else {
        Write-TestMessage "✗ Provision failed with exit code: $($Output.ExitCode)" -Type Error
        $pass = $false
    }
    $validationSteps += $step1

    # Step 2: Check for baseline BC packages in symbol cache
    $symbolCache = Join-Path $env:USERPROFILE ".bc-symbol-cache"
    $expectedPackages = @("Microsoft", "System", "Base")

    $step2 = @{ step = "Baseline BC packages downloaded"; passed = $false }
    $foundPackages = 0
    foreach ($pkg in $expectedPackages) {
        $pkgPath = Join-Path $symbolCache $pkg
        if (Test-Path $pkgPath) {
            $foundPackages++
            Write-TestMessage "  Found package directory: $pkg" -Type Debug
        }
    }

    if ($foundPackages -ge 2) {
        Write-TestMessage "✓ Baseline BC packages found ($foundPackages/$($expectedPackages.Count))" -Type Success
        $step2.passed = $true
    } else {
        Write-TestMessage "✗ Expected baseline packages not found ($foundPackages/$($expectedPackages.Count))" -Type Error
        $pass = $false
    }
    $validationSteps += $step2

    return @{ passed = $pass; validationDetails = $validationSteps }
}

function Validate-Scenario2 {
    param([object[]]$Output)

    Write-TestMessage "Validating Scenario 2 (empty dependencies array)..." -Type Info
    $validationSteps = @()
    $pass = $true

    # Step 1: Check exit code
    $step1 = @{ step = "Provision exit code 0"; passed = $false }
    if ($Output.ExitCode -eq 0) {
        Write-TestMessage "✓ Provision exited successfully" -Type Success
        $step1.passed = $true
    } else {
        Write-TestMessage "✗ Provision failed with exit code: $($Output.ExitCode)" -Type Error
        $pass = $false
    }
    $validationSteps += $step1

    # Step 2: Check for baseline BC packages
    $symbolCache = Join-Path $env:USERPROFILE ".bc-symbol-cache"
    $expectedPackages = @("Microsoft", "System", "Base")

    $step2 = @{ step = "Baseline BC packages downloaded"; passed = $false }
    $foundPackages = 0
    foreach ($pkg in $expectedPackages) {
        $pkgPath = Join-Path $symbolCache $pkg
        if (Test-Path $pkgPath) {
            $foundPackages++
            Write-TestMessage "  Found package directory: $pkg" -Type Debug
        }
    }

    if ($foundPackages -ge 2) {
        Write-TestMessage "✓ Baseline BC packages found ($foundPackages/$($expectedPackages.Count))" -Type Success
        $step2.passed = $true
    } else {
        Write-TestMessage "✗ Expected baseline packages not found ($foundPackages/$($expectedPackages.Count))" -Type Error
        $pass = $false
    }
    $validationSteps += $step2

    return @{ passed = $pass; validationDetails = $validationSteps }
}

function Validate-Scenario3 {
    param([object[]]$Output)

    Write-TestMessage "Validating Scenario 3 (with dependency)..." -Type Info
    $validationSteps = @()
    $pass = $true

    # Step 1: Check exit code
    $step1 = @{ step = "Provision exit code 0"; passed = $false }
    if ($Output.ExitCode -eq 0) {
        Write-TestMessage "✓ Provision exited successfully" -Type Success
        $step1.passed = $true
    } else {
        Write-TestMessage "✗ Provision failed with exit code: $($Output.ExitCode)" -Type Error
        $pass = $false
    }
    $validationSteps += $step1

    # Step 2: Check for 9altitudes package
    $symbolCache = Join-Path $env:USERPROFILE ".bc-symbol-cache"
    $altitudesPath = Join-Path $symbolCache "9altitudes"

    $step2 = @{ step = "9altitudes package downloaded"; passed = $false }
    if (Test-Path $altitudesPath) {
        # Look for 9A Advanced Manufacturing - License subdirectory
        $advMfgPath = Get-ChildItem -Path $altitudesPath -Directory | Where-Object { $_.Name -like "*9A*Advanced*Manufacturing*" } | Select-Object -First 1
        if ($advMfgPath) {
            Write-TestMessage "✓ 9altitudes package found at: $($advMfgPath.FullName)" -Type Success
            $step2.passed = $true
        } else {
            Write-TestMessage "✗ 9altitudes directory exists but package not found" -Type Error
            $pass = $false
        }
    } else {
        Write-TestMessage "✗ 9altitudes package not found" -Type Error
        $pass = $false
    }
    $validationSteps += $step2

    # Step 3: Check for baseline BC packages
    $expectedPackages = @("Microsoft", "System", "Base")

    $step3 = @{ step = "Baseline BC packages downloaded"; passed = $false }
    $foundPackages = 0
    foreach ($pkg in $expectedPackages) {
        $pkgPath = Join-Path $symbolCache $pkg
        if (Test-Path $pkgPath) {
            $foundPackages++
            Write-TestMessage "  Found package directory: $pkg" -Type Debug
        }
    }

    if ($foundPackages -ge 2) {
        Write-TestMessage "✓ Baseline BC packages found ($foundPackages/$($expectedPackages.Count))" -Type Success
        $step3.passed = $true
    } else {
        Write-TestMessage "✗ Expected baseline packages not found ($foundPackages/$($expectedPackages.Count))" -Type Error
        $pass = $false
    }
    $validationSteps += $step3

    return @{ passed = $pass; validationDetails = $validationSteps }
}

# Main execution
try {
    Write-TestMessage "Overlay test starting..." -Type Info
    Write-TestMessage "PowerShell Version: $($PSVersionTable.PSVersion)" -Type Info
    Write-TestMessage "Overlay Path: $OverlayPath" -Type Info
    Write-TestMessage "Fixtures Path: $FixturesPath" -Type Info
    Write-TestMessage "Workspace Path: $WorkspacePath" -Type Info

    # Create workspace directory
    if (-not (Test-Path $WorkspacePath)) {
        New-Item -ItemType Directory -Path $WorkspacePath -Force | Out-Null
    }

    # Scenario 1: No dependencies property
    $s1Path = Setup-Scenario1
    $s1Start = Get-Date
    $result = Run-Provision -ScenarioPath $s1Path -ScenarioNum 1
    $s1Duration = [int]((Get-Date) - $s1Start).TotalSeconds

    $validation = Validate-Scenario1 -Output $result
    if ($validation.passed) {
        Write-TestMessage "Scenario 1: PASSED" -Type Success
        $script:ScenarioResults[1] = @{
            scenarioId = 1
            name = "No dependencies property"
            passed = $true
            durationSeconds = $s1Duration
            validationDetails = $validation.validationDetails
        }
    } else {
        Write-TestMessage "Scenario 1: FAILED" -Type Error
        $script:ScenarioResults[1] = @{
            scenarioId = 1
            name = "No dependencies property"
            passed = $false
            durationSeconds = $s1Duration
            validationDetails = $validation.validationDetails
        }
        $script:AllScenariosPass = $false
    }

    # Scenario 2: Empty dependencies array
    $s2Path = Setup-Scenario2
    $s2Start = Get-Date
    $result = Run-Provision -ScenarioPath $s2Path -ScenarioNum 2
    $s2Duration = [int]((Get-Date) - $s2Start).TotalSeconds

    $validation = Validate-Scenario2 -Output $result
    if ($validation.passed) {
        Write-TestMessage "Scenario 2: PASSED" -Type Success
        $script:ScenarioResults[2] = @{
            scenarioId = 2
            name = "Empty dependencies array"
            passed = $true
            durationSeconds = $s2Duration
            validationDetails = $validation.validationDetails
        }
    } else {
        Write-TestMessage "Scenario 2: FAILED" -Type Error
        $script:ScenarioResults[2] = @{
            scenarioId = 2
            name = "Empty dependencies array"
            passed = $false
            durationSeconds = $s2Duration
            validationDetails = $validation.validationDetails
        }
        $script:AllScenariosPass = $false
    }

    # Scenario 3: With dependency
    $s3Path = Setup-Scenario3
    $s3Start = Get-Date
    $result = Run-Provision -ScenarioPath $s3Path -ScenarioNum 3
    $s3Duration = [int]((Get-Date) - $s3Start).TotalSeconds

    $validation = Validate-Scenario3 -Output $result
    if ($validation.passed) {
        Write-TestMessage "Scenario 3: PASSED" -Type Success
        $script:ScenarioResults[3] = @{
            scenarioId = 3
            name = "With dependency"
            passed = $true
            durationSeconds = $s3Duration
            validationDetails = $validation.validationDetails
        }
    } else {
        Write-TestMessage "Scenario 3: FAILED" -Type Error
        $script:ScenarioResults[3] = @{
            scenarioId = 3
            name = "With dependency"
            passed = $false
            durationSeconds = $s3Duration
            validationDetails = $validation.validationDetails
        }
        $script:AllScenariosPass = $false
    }

    # Report overall results
    Write-TestMessage "========================================" -Type Info
    Write-TestMessage "Test Summary:" -Type Info
    Write-TestMessage "Scenario 1 (no dependencies): $(if ($script:ScenarioResults[1].passed) { 'PASSED' } else { 'FAILED' })" -Type Info
    Write-TestMessage "Scenario 2 (empty dependencies): $(if ($script:ScenarioResults[2].passed) { 'PASSED' } else { 'FAILED' })" -Type Info
    Write-TestMessage "Scenario 3 (with dependency): $(if ($script:ScenarioResults[3].passed) { 'PASSED' } else { 'FAILED' })" -Type Info
    Write-TestMessage "========================================" -Type Info

    if ($script:AllScenariosPass) {
        Write-TestMessage "All scenarios PASSED" -Type Success
        exit 0
    } else {
        Write-TestMessage "Some scenarios FAILED" -Type Error
        exit 1
    }
}
catch {
    Write-TestMessage "Unexpected error: $($_.Exception.Message)" -Type Error
    Write-TestMessage "Stack trace: $($_.ScriptStackTrace)" -Type Debug
    exit 1
}
finally {
    [Console]::Out.Flush()
    [Console]::Error.Flush()
}
