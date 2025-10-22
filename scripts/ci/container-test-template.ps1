#requires -Version 5.1
# Container test script for bootstrap installer - Multi-scenario testing
# This script runs inside the Windows container to test the bootstrap installer
# across 3 scenarios: no git, git pre-installed, and mixed setup

param(
    [string]$ReleaseTag = $env:ALBT_TEST_RELEASE_TAG,
    [string]$BaseDestPath = 'C:\albt-workspace'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure output is not buffered
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Track overall test results
$script:AllScenariosPass = $true
$script:ScenarioResults = @{}

function Write-ContainerMessage {
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

function Refresh-PathEnv {
    try {
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($machinePath -or $userPath) {
            $env:Path = "$machinePath;$userPath"
            Write-ContainerMessage "PATH refreshed from machine/user" -Type Debug
        }
    } catch {
        Write-ContainerMessage "Failed to refresh PATH: $($_.Exception.Message)" -Type Debug
    }
}

function Copy-TestFixture {
    param(
        [string]$ScenarioName,
        [string]$DestinationPath
    )

    # Inside container, testdata is mounted at C:\testdata
    $testdataPath = Join-Path "C:\testdata" $ScenarioName

    if (-not (Test-Path $testdataPath)) {
        Write-ContainerMessage "Test fixture not found at: $testdataPath" -Type Error
        throw "Missing test fixture for $ScenarioName"
    }

    Write-ContainerMessage "Copying test fixture from: $testdataPath to: $DestinationPath" -Type Debug
    Copy-Item -Path (Join-Path $testdataPath "*") -Destination $DestinationPath -Recurse -Force -ErrorAction Stop
    Write-ContainerMessage "Test fixture copied successfully" -Type Debug
}

function Setup-Scenario1 {
    Write-ContainerMessage "Setting up Scenario 1: No git, no config, no repo" -Type Scenario
    # No setup needed - Windows Server Core has no git by default
}

function Setup-Scenario2 {
    Write-ContainerMessage "Setting up Scenario 2: Git installed, configured, repo exists" -Type Scenario

    # Refresh PATH to ensure choco is available (already installed in Scenario 1)
    Refresh-PathEnv

    # Install git using choco
    Write-ContainerMessage "Installing git via Chocolatey..." -Type Info
    & choco install git -y --no-progress 2>&1 | Out-Null

    # Ensure PATH includes git
    Refresh-PathEnv

    # Configure git globally
    Write-ContainerMessage "Configuring git..." -Type Info
    & git config --global user.name "Pre-configured User" 2>&1 | Out-Null
    & git config --global user.email "preconfig@example.com" 2>&1 | Out-Null

    # Create workspace with initial content and repo
    $workspacePath = Join-Path $BaseDestPath "scenario2"
    Write-ContainerMessage "Creating workspace at: $workspacePath" -Type Info
    New-Item -ItemType Directory -Path $workspacePath -Force | Out-Null

    # Copy test fixture
    Copy-TestFixture -ScenarioName "scenario2" -DestinationPath $workspacePath

    # Initialize git repo with initial commit
    Write-ContainerMessage "Initializing git repo at workspace..." -Type Info
    & git -C $workspacePath init 2>&1 | Out-Null
    & git -C $workspacePath add . 2>&1 | Out-Null
    & git -C $workspacePath commit -m "Pre-existing commit" 2>&1 | Out-Null

    Write-ContainerMessage "Scenario 2 setup complete" -Type Success
}

function Setup-Scenario3 {
    Write-ContainerMessage "Setting up Scenario 3: Git installed and configured, no repo" -Type Scenario

    # Ensure PATH is up to date for git
    Refresh-PathEnv

    # Create workspace without repo
    $workspacePath = Join-Path $BaseDestPath "scenario3"
    Write-ContainerMessage "Creating workspace at: $workspacePath" -Type Info
    New-Item -ItemType Directory -Path $workspacePath -Force | Out-Null

    # Copy test fixture
    Copy-TestFixture -ScenarioName "scenario3" -DestinationPath $workspacePath

    Write-ContainerMessage "Scenario 3 setup complete" -Type Success
}

function Run-Installer {
    param(
        [string]$DestPath,
        [int]$ScenarioNum
    )

    $installerPath = 'C:\bootstrap\install.ps1'

    Write-ContainerMessage "Running installer for Scenario $ScenarioNum at: $DestPath" -Type Info

    # Ensure destination directory exists
    New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
    Write-ContainerMessage "Destination directory ensured: $DestPath" -Type Debug

    $env:ALBT_AUTO_INSTALL = '1'
    $env:ALBT_HTTP_TIMEOUT_SEC = '300'

    # Capture output for validation
    $installerOutput = @()

    try {
        # Create a temporary wrapper script to call the installer with the correct destination
        # Use environment variables to pass the destination - avoids PowerShell parameter binding issues
        $wrapperScript = @'
$DestinationPath = $env:ALBT_WRAPPER_DEST
$ReleaseRef = $env:ALBT_WRAPPER_REF

Write-Host "[wrapper] Destination from env: $DestinationPath"
Write-Host "[wrapper] Release from env: $ReleaseRef"

$installerPath = 'C:\bootstrap\install.ps1'

Write-Host "[wrapper] Calling: & '$installerPath' -Dest '$DestinationPath' -Ref '$ReleaseRef'"

Write-Verbose "[wrapper] DestinationPath type: $($DestinationPath.GetType().Name), length: $($DestinationPath.Length)"
Write-Verbose "[wrapper] Testing path resolution..."
try {
    $resolvedPath = Resolve-Path -Path $DestinationPath -ErrorAction Stop
    Write-Verbose "[wrapper] Resolved path: $($resolvedPath.Path)"
} catch {
    Write-Verbose "[wrapper] Path resolution failed: $_"
}

Write-Verbose "[wrapper] About to call installer..."

# Call installer with splatting to avoid parameter binding issues with call operator
$installerArgs = @{
    DestinationPath = $DestinationPath
}
if ($ReleaseRef) {
    $installerArgs['Ref'] = $ReleaseRef
    Write-Host "[wrapper] Calling with -Dest and -Ref (splatted)"
} else {
    Write-Host "[wrapper] Calling with -Dest only (splatted)"
}

& $installerPath @installerArgs

Write-Host "[wrapper] Installer completed with exit code: $LASTEXITCODE"
'@

        # Create temporary file for wrapper script
        $tempWrapper = Join-Path $env:TEMP "installer-wrapper-$(Get-Random).ps1"
        Set-Content -Path $tempWrapper -Value $wrapperScript -Encoding UTF8 -Force

        Write-ContainerMessage "Wrapper script created at: $tempWrapper" -Type Debug

        # Set environment variables for the wrapper script to read
        $env:ALBT_WRAPPER_DEST = $DestPath
        $env:ALBT_WRAPPER_REF = $ReleaseTag

        $psArgs = @(
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-File', $tempWrapper
        )

        # Build command line for logging
        $cmdLineDebug = "powershell.exe -File $tempWrapper"
        Write-ContainerMessage "Executing: $cmdLineDebug (with ALBT_WRAPPER_DEST=$DestPath, ALBT_WRAPPER_REF=$ReleaseTag)" -Type Debug

        # Run installer with piped input for auto-decline provision
        'n' | & powershell.exe @psArgs 2>&1 | ForEach-Object {
            Write-Host $_
            $installerOutput += $_
            [Console]::Out.Flush()
        }

        $exitCode = $LASTEXITCODE

        # Clean up wrapper script
        if (Test-Path $tempWrapper) {
            Remove-Item $tempWrapper -Force -ErrorAction SilentlyContinue
        }

        if ($exitCode -ne 0) {
            Write-ContainerMessage "Installer exited with code: $exitCode" -Type Error
            return @{ ExitCode = $exitCode; Output = $installerOutput }
        }
    }
    catch {
        Write-ContainerMessage "Installer failed with exception: $($_.Exception.Message)" -Type Error
        return @{ ExitCode = 1; Output = $installerOutput }
    }

    return @{ ExitCode = 0; Output = $installerOutput }
}

function Validate-Scenario1 {
    param([object[]]$Output, [string]$DestPath)

    Write-ContainerMessage "Validating Scenario 1..." -Type Info
    $pass = $true

    # Check for git installation attempt marker
    if ($Output -match 'prerequisite tool="git" status="installing"') {
        Write-ContainerMessage "Git installation marker found" -Type Success
    } else {
        Write-ContainerMessage "Git installation marker NOT found" -Type Error
        $pass = $false
    }

    # Git may not emit an explicit 'installed' marker; don't require it

    # Check for git config marker
    if ($Output -match 'prerequisite tool="git-config" status="configured"') {
        Write-ContainerMessage "Git config marker found" -Type Success
    } else {
        Write-ContainerMessage "Git config marker NOT found" -Type Error
        $pass = $false
    }

    # Check for repo initialization marker
    if ($Output -match 'prerequisite tool="git" status="initialized"') {
        Write-ContainerMessage "Git repo init marker found" -Type Success
    } else {
        Write-ContainerMessage "Git repo init marker NOT found" -Type Error
        $pass = $false
    }

    # Refresh PATH so git is available in this process
    Refresh-PathEnv

    # Check commit count (should be 1: initial commit before overlay only)
    try {
        $commitCount = (& git -C $DestPath log --oneline 2>&1 | Measure-Object).Count
        Write-ContainerMessage "Commit count: $commitCount" -Type Info
        if ($commitCount -eq 1) {
            Write-ContainerMessage "Expected 1 commit found (initial before overlay)" -Type Success
        } else {
            Write-ContainerMessage "Expected 1 commit but found $commitCount" -Type Error
            $pass = $false
        }
    }
    catch {
        Write-ContainerMessage "Failed to check commit count: $_" -Type Error
        $pass = $false
    }

    # Check for unauthorized post-overlay commit markers
    if ($Output -match '\[install\]\s+git\s+initial_commit=after') {
        Write-ContainerMessage "REGRESSION: Found unauthorized initial_commit=after marker" -Type Error
        $pass = $false
    } else {
        Write-ContainerMessage "No initial_commit=after marker (correct)" -Type Success
    }

    if ($Output -match '\[install\]\s+git\s+overlay_commit=true') {
        Write-ContainerMessage "REGRESSION: Found unauthorized overlay_commit=true marker" -Type Error
        $pass = $false
    } else {
        Write-ContainerMessage "No overlay_commit=true marker (correct)" -Type Success
    }

    # Check for overlay_staged=false marker
    if ($Output -match '\[install\]\s+overlay_staged=false') {
        Write-ContainerMessage "Found overlay_staged=false marker (correct)" -Type Success
    } else {
        Write-ContainerMessage "overlay_staged=false marker NOT found" -Type Error
        $pass = $false
    }

    return $pass
}

function Validate-Scenario2 {
    param([object[]]$Output, [string]$DestPath)

    Write-ContainerMessage "Validating Scenario 2..." -Type Info
    $pass = $true

    if ($Output -match 'prerequisite tool="git" status="present"') {
        Write-ContainerMessage "Git already present marker found (correct)" -Type Success
    } else {
        Write-ContainerMessage "Git already present marker NOT found" -Type Error
        $pass = $false
    }

    if ($Output -match 'prerequisite tool="git-config" status="present"') {
        Write-ContainerMessage "Git config already present marker found (correct)" -Type Success
    } else {
        Write-ContainerMessage "Git config already present marker NOT found" -Type Error
        $pass = $false
    }

    Refresh-PathEnv

    # For existing repos, commit count should remain unchanged (1 pre-existing commit only)
    try {
        $commitCount = (& git -C $DestPath log --oneline 2>&1 | Measure-Object).Count
        Write-ContainerMessage "Commit count: $commitCount" -Type Info
        if ($commitCount -eq 1) {
            Write-ContainerMessage "Expected 1 commit found (no new commits)" -Type Success
        } else {
            Write-ContainerMessage "Expected 1 commit but found $commitCount" -Type Error
            $pass = $false
        }
    }
    catch {
        Write-ContainerMessage "Failed to check commit count: $_" -Type Error
        $pass = $false
    }

    # Check for unauthorized post-overlay commit markers
    if ($Output -match '\[install\]\s+git\s+overlay_commit=true') {
        Write-ContainerMessage "REGRESSION: Found unauthorized overlay_commit=true marker" -Type Error
        $pass = $false
    } else {
        Write-ContainerMessage "No overlay_commit=true marker (correct)" -Type Success
    }

    # Check for overlay_staged=false marker
    if ($Output -match '\[install\]\s+overlay_staged=false') {
        Write-ContainerMessage "Found overlay_staged=false marker (correct)" -Type Success
    } else {
        Write-ContainerMessage "overlay_staged=false marker NOT found" -Type Error
        $pass = $false
    }

    try {
        $userName = & git config --global user.name 2>&1
        if ($userName -eq "Pre-configured User") {
            Write-ContainerMessage "Git config preserved correctly" -Type Success
        } else {
            Write-ContainerMessage "Git config was changed (expected: Pre-configured User, got: $userName)" -Type Error
            $pass = $false
        }
    }
    catch {
        Write-ContainerMessage "Failed to verify git config: $_" -Type Error
        $pass = $false
    }

    return $pass
}

function Validate-Scenario3 {
    param([object[]]$Output, [string]$DestPath)

    Write-ContainerMessage "Validating Scenario 3..." -Type Info
    $pass = $true

    if ($Output -match 'prerequisite tool="git" status="present"') {
        Write-ContainerMessage "Git already present marker found (correct)" -Type Success
    } else {
        Write-ContainerMessage "Git already present marker NOT found" -Type Error
        $pass = $false
    }

    if ($Output -match 'prerequisite tool="git-config" status="present"') {
        Write-ContainerMessage "Git config already present marker found (correct)" -Type Success
    } else {
        Write-ContainerMessage "Git config already present marker NOT found" -Type Error
        $pass = $false
    }

    # Check for repo initialization marker
    if ($Output -match 'prerequisite tool="git" status="initialized"') {
        Write-ContainerMessage "Git repo init marker found" -Type Success
    } else {
        Write-ContainerMessage "Git repo init marker NOT found" -Type Error
        $pass = $false
    }

    Refresh-PathEnv

    # Scenario 3: git/config present, but no repo - should have 1 commit (initial before overlay)
    try {
        $commitCount = (& git -C $DestPath log --oneline 2>&1 | Measure-Object).Count
        Write-ContainerMessage "Commit count: $commitCount" -Type Info
        if ($commitCount -eq 1) {
            Write-ContainerMessage "Expected 1 commit found (initial before overlay)" -Type Success
        } else {
            Write-ContainerMessage "Expected 1 commit but found $commitCount" -Type Error
            $pass = $false
        }
    }
    catch {
        Write-ContainerMessage "Failed to check commit count: $_" -Type Error
        $pass = $false
    }

    # Check for unauthorized post-overlay commit markers
    if ($Output -match '\[install\]\s+git\s+initial_commit=after') {
        Write-ContainerMessage "REGRESSION: Found unauthorized initial_commit=after marker" -Type Error
        $pass = $false
    } else {
        Write-ContainerMessage "No initial_commit=after marker (correct)" -Type Success
    }

    if ($Output -match '\[install\]\s+git\s+overlay_commit=true') {
        Write-ContainerMessage "REGRESSION: Found unauthorized overlay_commit=true marker" -Type Error
        $pass = $false
    } else {
        Write-ContainerMessage "No overlay_commit=true marker (correct)" -Type Success
    }

    # Check for overlay_staged=false marker
    if ($Output -match '\[install\]\s+overlay_staged=false') {
        Write-ContainerMessage "Found overlay_staged=false marker (correct)" -Type Success
    } else {
        Write-ContainerMessage "overlay_staged=false marker NOT found" -Type Error
        $pass = $false
    }

    return $pass
}

function Verify-OverlayInstalled {
    param([string]$DestPath)

    Write-ContainerMessage "Verifying overlay installation at: $DestPath" -Type Info

    $expectedFiles = @('al.build.ps1', 'al.ruleset.json')
    $missingFiles = @()
    foreach ($file in $expectedFiles) {
        $filePath = Join-Path $DestPath $file
        if (-not (Test-Path $filePath)) {
            $missingFiles += $file
        }
    }

    if ($missingFiles.Count -gt 0) {
        Write-ContainerMessage "Expected overlay files not found: $($missingFiles -join ', ')" -Type Error
        return $false
    }

    Write-ContainerMessage "Overlay files verified" -Type Success
    return $true
}

# Main execution
try {
    Write-ContainerMessage "Container test starting..." -Type Info
    Write-ContainerMessage "PowerShell Version: $($PSVersionTable.PSVersion)" -Type Info
    Write-ContainerMessage "Release Tag: $ReleaseTag" -Type Info

    # Scenario 1: No git, no config, no repo
    $s1Path = Join-Path $BaseDestPath "scenario1"
    Setup-Scenario1
    New-Item -ItemType Directory -Path $s1Path -Force | Out-Null

    # Copy test fixture
    Copy-TestFixture -ScenarioName "scenario1" -DestinationPath $s1Path

    $result = Run-Installer -DestPath $s1Path -ScenarioNum 1
    if ($result.ExitCode -eq 0) {
        $overlayOk = Verify-OverlayInstalled -DestPath $s1Path
        if ($overlayOk) {
            $validationPass = Validate-Scenario1 -Output $result.Output -DestPath $s1Path
            if ($validationPass) {
                Write-ContainerMessage "Scenario 1: PASSED" -Type Success
                $script:ScenarioResults[1] = $true
            }
            else {
                Write-ContainerMessage "Scenario 1: FAILED (validation)" -Type Error
                $script:ScenarioResults[1] = $false
                $script:AllScenariosPass = $false
            }
        }
        else {
            Write-ContainerMessage "Scenario 1: FAILED (overlay verification)" -Type Error
            $script:ScenarioResults[1] = $false
            $script:AllScenariosPass = $false
        }
    }
    else {
        Write-ContainerMessage "Scenario 1: FAILED (installer exit code: $($result.ExitCode))" -Type Error
        $script:ScenarioResults[1] = $false
        $script:AllScenariosPass = $false
    }

    # Scenario 2: Git installed, configured, repo exists
    Setup-Scenario2
    $s2Path = Join-Path $BaseDestPath "scenario2"

    $result = Run-Installer -DestPath $s2Path -ScenarioNum 2
    if ($result.ExitCode -eq 0) {
        $overlayOk = Verify-OverlayInstalled -DestPath $s2Path
        if ($overlayOk) {
            $validationPass = Validate-Scenario2 -Output $result.Output -DestPath $s2Path
            if ($validationPass) {
                Write-ContainerMessage "Scenario 2: PASSED" -Type Success
                $script:ScenarioResults[2] = $true
            }
            else {
                Write-ContainerMessage "Scenario 2: FAILED (validation)" -Type Error
                $script:ScenarioResults[2] = $false
                $script:AllScenariosPass = $false
            }
        }
        else {
            Write-ContainerMessage "Scenario 2: FAILED (overlay verification)" -Type Error
            $script:ScenarioResults[2] = $false
            $script:AllScenariosPass = $false
        }
    }
    else {
        Write-ContainerMessage "Scenario 2: FAILED (installer exit code: $($result.ExitCode))" -Type Error
        $script:ScenarioResults[2] = $false
        $script:AllScenariosPass = $false
    }

    # Scenario 3: Git installed and configured, no repo
    Setup-Scenario3
    $s3Path = Join-Path $BaseDestPath "scenario3"

    $result = Run-Installer -DestPath $s3Path -ScenarioNum 3
    if ($result.ExitCode -eq 0) {
        $overlayOk = Verify-OverlayInstalled -DestPath $s3Path
        if ($overlayOk) {
            $validationPass = Validate-Scenario3 -Output $result.Output -DestPath $s3Path
            if ($validationPass) {
                Write-ContainerMessage "Scenario 3: PASSED" -Type Success
                $script:ScenarioResults[3] = $true
            }
            else {
                Write-ContainerMessage "Scenario 3: FAILED (validation)" -Type Error
                $script:ScenarioResults[3] = $false
                $script:AllScenariosPass = $false
            }
        }
        else {
            Write-ContainerMessage "Scenario 3: FAILED (overlay verification)" -Type Error
            $script:ScenarioResults[3] = $false
            $script:AllScenariosPass = $false
        }
    }
    else {
        Write-ContainerMessage "Scenario 3: FAILED (installer exit code: $($result.ExitCode))" -Type Error
        $script:ScenarioResults[3] = $false
        $script:AllScenariosPass = $false
    }

    # Report overall results
    Write-ContainerMessage "========================================" -Type Info
    Write-ContainerMessage "Test Summary:" -Type Info
    Write-ContainerMessage "Scenario 1 (no git, no config, no repo): $(if ($script:ScenarioResults[1]) { 'PASSED' } else { 'FAILED' })" -Type Info
    Write-ContainerMessage "Scenario 2 (git+config+repo): $(if ($script:ScenarioResults[2]) { 'PASSED' } else { 'FAILED' })" -Type Info
    Write-ContainerMessage "Scenario 3 (git+config, no repo): $(if ($script:ScenarioResults[3]) { 'PASSED' } else { 'FAILED' })" -Type Info
    Write-ContainerMessage "========================================" -Type Info

    if ($script:AllScenariosPass) {
        Write-ContainerMessage "All scenarios PASSED" -Type Success
    exit 0
    }
    else {
        Write-ContainerMessage "Some scenarios FAILED" -Type Error
        exit 1
    }
}
catch {
    Write-ContainerMessage "Unexpected error: $($_.Exception.Message)" -Type Error
    Write-ContainerMessage "Stack trace: $($_.ScriptStackTrace)" -Type Debug
    exit 1
}
finally {
    [Console]::Out.Flush()
    [Console]::Error.Flush()
}