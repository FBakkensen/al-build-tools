#requires -Version 5.1
# Container test script for bootstrap installer
# This script runs inside the Windows container to test the bootstrap installer

param(
    [string]$ReleaseTag = $env:ALBT_TEST_RELEASE_TAG,
    [string]$DestPath = 'C:\albt-workspace'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure output is not buffered
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-ContainerMessage {
    param(
        [string]$Message,
        [string]$Type = 'Info'
    )

    $timestamp = Get-Date -Format 'HH:mm:ss.fff'
    $prefix = switch ($Type) {
        'Info'    { '[INFO]' }
        'Success' { '[PASS]' }
        'Error'   { '[FAIL]' }
        'Debug'   { '[DEBUG]' }
        default   { '[INFO]' }
    }

    Write-Host "$timestamp $prefix $Message"
    # Force flush to ensure immediate output
    [Console]::Out.Flush()
    [Console]::Error.Flush()
}

try {
    Write-ContainerMessage "Container test starting..." -Type Info
    Write-ContainerMessage "PowerShell Version: $($PSVersionTable.PSVersion)" -Type Info
    Write-ContainerMessage "Windows Version: $([System.Environment]::OSVersion.VersionString)" -Type Info
    Write-ContainerMessage "Release Tag: $ReleaseTag" -Type Info
    Write-ContainerMessage "Destination: $DestPath" -Type Info

    # Step 1: Network connectivity test
    Write-ContainerMessage "Testing network connectivity..." -Type Info
    $networkTestUrls = @(
        'https://www.google.com',
        'https://api.github.com',
        'https://raw.githubusercontent.com'
    )

    $networkSuccess = $true
    foreach ($url in $networkTestUrls) {
        try {
            Write-ContainerMessage "Testing connection to $url" -Type Debug
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -Method Head
            Write-ContainerMessage "Connection to $url successful (Status: $($response.StatusCode))" -Type Success
        }
        catch {
            Write-ContainerMessage "Connection to $url failed: $($_.Exception.Message)" -Type Error
            $networkSuccess = $false
        }
    }

    if (-not $networkSuccess) {
        Write-ContainerMessage "Network connectivity test failed - some endpoints unreachable" -Type Error
        exit 1
    }

    Write-ContainerMessage "Network connectivity test passed" -Type Success

    # Step 2: Check bootstrap installer exists
    $installerPath = 'C:\bootstrap\install.ps1'
    if (-not (Test-Path $installerPath)) {
        Write-ContainerMessage "Bootstrap installer not found at: $installerPath" -Type Error
        exit 1
    }
    Write-ContainerMessage "Bootstrap installer found at: $installerPath" -Type Success

    # Step 3: Create destination directory and minimal Business Central app structure
    if (-not (Test-Path $DestPath)) {
        Write-ContainerMessage "Creating destination directory: $DestPath" -Type Info
        New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
    }

    # Create minimal app.json for provisioning to work
    Write-ContainerMessage "Creating minimal app.json for provision task" -Type Info
    $appJson = @{
        id = "00000000-0000-0000-0000-000000000000"
        name = "Test App"
        publisher = "Test Publisher"
        version = "1.0.0.0"
        brief = "Test application for installer validation"
        description = "Minimal Business Central app for testing the provision task"
        runtime = "13.0"
        platform = "24.0.0.0"
        application = "24.0.0.0"
        dataAccessIntent = "ReadWrite"
        dependencies = @()
        screenshots = @()
        privacyStatement = ""
        supportedLocales = @()
    } | ConvertTo-Json -Depth 10

    Set-Content -Path (Join-Path $DestPath "app.json") -Value $appJson -Encoding UTF8
    Write-ContainerMessage "app.json created at: $(Join-Path $DestPath 'app.json')" -Type Info

    # Create minimal AL code file structure
    Write-ContainerMessage "Creating AL code structure" -Type Info
    $srcDir = Join-Path $DestPath "src"
    if (-not (Test-Path $srcDir)) {
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
    }

    # Create minimal HelloWorld.al file
    $alCode = @"
codeunit 50100 "Hello World"
{
    procedure HelloWorld()
    begin
        Message('Hello World');
    end;
}
"@
    Set-Content -Path (Join-Path $srcDir "HelloWorld.al") -Value $alCode -Encoding UTF8
    Write-ContainerMessage "AL code structure created" -Type Info

    # Step 4: Run bootstrap installer
    # Note: Installer will handle git init and initial commit of all files
    # Note: Installer will initialize git repository automatically with ALBT_AUTO_INSTALL=1
    Write-ContainerMessage "Starting bootstrap installer..." -Type Info
    Write-ContainerMessage "Command: & $installerPath -Dest $DestPath -Ref $ReleaseTag" -Type Debug

    # Set environment variables for auto-installation
    $env:ALBT_AUTO_INSTALL = '1'
    $env:ALBT_HTTP_TIMEOUT_SEC = '300'

    # Run the installer and stream output
    $installerArgs = @{
        Dest = $DestPath
    }
    if ($ReleaseTag) {
        $installerArgs['Ref'] = $ReleaseTag
    }

    try {
        # Execute installer with real-time output streaming
        & $installerPath @installerArgs 2>&1 | ForEach-Object {
            # Pass through installer output
            Write-Host $_
            [Console]::Out.Flush()
        }

        $installerExitCode = $LASTEXITCODE

        if ($installerExitCode -ne 0) {
            Write-ContainerMessage "Bootstrap installer exited with code: $installerExitCode" -Type Error
            exit $installerExitCode
        }
    }
    catch {
        Write-ContainerMessage "Bootstrap installer failed with exception: $($_.Exception.Message)" -Type Error
        Write-ContainerMessage "Stack trace: $($_.ScriptStackTrace)" -Type Debug
        exit 1
    }

    Write-ContainerMessage "Bootstrap installer completed successfully" -Type Success

    # Step 5: Verify installation
    Write-ContainerMessage "Verifying installation..." -Type Info

    # Check for expected overlay files at the destination root (not in an 'overlay' subdirectory)
    $expectedFiles = @('al.build.ps1', 'al.ruleset.json', 'CLAUDE.md')
    $missingFiles = @()
    foreach ($file in $expectedFiles) {
        $filePath = Join-Path $DestPath $file
        if (-not (Test-Path $filePath)) {
            $missingFiles += $file
        }
    }

    if ($missingFiles.Count -gt 0) {
        Write-ContainerMessage "Expected overlay files not found: $($missingFiles -join ', ')" -Type Error
        Write-ContainerMessage "Directory contents:" -Type Debug
        Get-ChildItem $DestPath | ForEach-Object {
            Write-ContainerMessage "  - $($_.Name)" -Type Debug
        }
        exit 1
    }

    # Define overlay path for verification
    $overlayPath = $DestPath
    Write-ContainerMessage "Overlay directory found at: $overlayPath" -Type Success

    # Check for key files
    $requiredFiles = @(
        'al.build.ps1',
        'al.ruleset.json',
        'scripts\common.psm1'
    )

    $allFilesPresent = $true
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $overlayPath $file
        if (Test-Path $filePath) {
            Write-ContainerMessage "Required file present: overlay\$file" -Type Success
        }
        else {
            Write-ContainerMessage "Required file missing: overlay\$file" -Type Error
            $allFilesPresent = $false
        }
    }

    if (-not $allFilesPresent) {
        Write-ContainerMessage "Installation verification failed - missing required files" -Type Error
        exit 1
    }

    # Count total files installed
    $fileCount = (Get-ChildItem -Path $overlayPath -Recurse -File | Measure-Object).Count
    Write-ContainerMessage "Total files installed: $fileCount" -Type Info

    Write-ContainerMessage "Installation verification passed" -Type Success
    Write-ContainerMessage "Container test completed successfully" -Type Success

    exit 0
}
catch {
    Write-ContainerMessage "Unexpected error in container test: $($_.Exception.Message)" -Type Error
    Write-ContainerMessage "Stack trace: $($_.ScriptStackTrace)" -Type Debug
    exit 1
}
finally {
    # Final flush to ensure all output is written
    [Console]::Out.Flush()
    [Console]::Error.Flush()
}