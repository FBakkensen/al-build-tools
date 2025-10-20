#requires -Version 7.2

<#
.SYNOPSIS
    In-container test script for overlay provision workflow validation.

.DESCRIPTION
    Runs inside Windows container to test Invoke-Build provision tasks:
    - download-compiler: Installs AL compiler dotnet tool
    - download-symbols: Downloads BC symbol packages from NuGet

    Validates compiler installation and symbol cache integrity with full JSON validation.

.NOTES
    This script is executed inside the container by test-overlay-provision.ps1.
    Mounted paths:
      C:\overlay         - Overlay directory with al.build.ps1
      C:\testdata        - Test fixtures (BC 27 app with dependencies)
#>

param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ensure output is not buffered (critical for Windows containers)
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Test tracking
$script:TestsPassed = 0
$script:TestsFailed = 0

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
        'Step' { '[STEP]' }
        default { '[INFO]' }
    }

    Write-Host "$timestamp $prefix $Message"
    [Console]::Out.Flush()
    [Console]::Error.Flush()
}

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Description
    )

    if (Test-Path -LiteralPath $Path) {
        Write-TestMessage "$Description exists: $Path" -Type Success
        $script:TestsPassed++
        return $true
    } else {
        Write-TestMessage "$Description NOT found: $Path" -Type Error
        $script:TestsFailed++
        return $false
    }
}

function Assert-JsonContent {
    param(
        [string]$Path,
        [string]$Description,
        [hashtable]$ExpectedValues
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-TestMessage "$Description file not found: $Path" -Type Error
        $script:TestsFailed++
        return $false
    }

    try {
        $content = Get-Content -Path $Path -Raw | ConvertFrom-Json

        $allMatch = $true
        foreach ($key in $ExpectedValues.Keys) {
            $expectedValue = $ExpectedValues[$key]
            $actualValue = $content.$key

            if ($actualValue -eq $expectedValue) {
                Write-TestMessage "$Description.$key = $actualValue (correct)" -Type Success
            } else {
                Write-TestMessage "$Description.$key = $actualValue (expected: $expectedValue)" -Type Error
                $allMatch = $false
            }
        }

        if ($allMatch) {
            $script:TestsPassed++
            return $true
        } else {
            $script:TestsFailed++
            return $false
        }
    }
    catch {
        Write-TestMessage "Failed to parse $Description JSON: $_" -Type Error
        $script:TestsFailed++
        return $false
    }
}

function Get-UserHomeDirectory {
    if ($env:USERPROFILE) {
        return $env:USERPROFILE
    } elseif ($env:HOME) {
        return $env:HOME
    } else {
        return [Environment]::GetFolderPath('UserProfile')
    }
}

function ConvertTo-SafePathSegment {
    <#
    .SYNOPSIS
        Convert string to safe filesystem path segment (mirrors common.psm1 logic)
    .PARAMETER Value
        String to sanitize
    #>
    param([string]$Value)

    if (-not $Value) { return '_' }

    $invalid = [System.IO.Path]::GetInvalidFileNameChars() + [char]':'
    $result = $Value
    foreach ($char in $invalid) {
        $pattern = [regex]::Escape([string]$char)
        $result = $result -replace $pattern, '_'
    }
    $result = $result -replace '\s+', '_'
    if ([string]::IsNullOrWhiteSpace($result)) { return '_' }
    return $result
}

# Main execution
try {
    Write-TestMessage "Container provision test starting..." -Type Info
    Write-TestMessage "PowerShell Version: $($PSVersionTable.PSVersion)" -Type Info

    # Step 1: Verify mounted paths
    Write-TestMessage "=== Verifying Mounted Paths ===" -Type Step

    Assert-PathExists -Path 'C:\overlay' -Description 'Overlay directory'
    Assert-PathExists -Path 'C:\overlay\al.build.ps1' -Description 'Invoke-Build script'
    Assert-PathExists -Path 'C:\testdata' -Description 'Test data directory'
    Assert-PathExists -Path 'C:\testdata\provision\bc27-with-dep' -Description 'BC 27 test fixture'

    # Step 2: Copy test fixture to workspace
    Write-TestMessage "=== Setting Up Test Workspace ===" -Type Step

    $workspacePath = 'C:\albt-test\workspace'
    $fixturePath = 'C:\testdata\provision\bc27-with-dep'

    Write-TestMessage "Creating workspace: $workspacePath" -Type Info
    New-Item -ItemType Directory -Path $workspacePath -Force | Out-Null

    Write-TestMessage "Copying test fixture..." -Type Info
    Copy-Item -Path (Join-Path $fixturePath '*') -Destination $workspacePath -Recurse -Force

    Assert-PathExists -Path (Join-Path $workspacePath 'app.json') -Description 'Workspace app.json'
    Assert-PathExists -Path (Join-Path $workspacePath 'app') -Description 'Workspace app directory'

    # Step 3: Import InvokeBuild
    Write-TestMessage "=== Importing InvokeBuild Module ===" -Type Step

    try {
        Import-Module InvokeBuild -ErrorAction Stop
        Write-TestMessage "InvokeBuild module imported successfully" -Type Success
        $script:TestsPassed++
    }
    catch {
        Write-TestMessage "Failed to import InvokeBuild: $_" -Type Error
        $script:TestsFailed++
        exit 1
    }

    # Step 4: Run Invoke-Build provision
    Write-TestMessage "=== Running Invoke-Build provision ===" -Type Step

    Push-Location 'C:\overlay'
    try {
        Write-TestMessage "Executing: Invoke-Build provision -AppDir $workspacePath" -Type Info

        Invoke-Build provision -AppDir $workspacePath 2>&1 | ForEach-Object {
            Write-Host $_
            [Console]::Out.Flush()
        }

        $provisionExitCode = $LASTEXITCODE
        if ($provisionExitCode -eq 0) {
            Write-TestMessage "Provision task completed successfully" -Type Success
            $script:TestsPassed++
        } else {
            Write-TestMessage "Provision task failed with exit code: $provisionExitCode" -Type Error
            $script:TestsFailed++
            exit 1
        }
    }
    finally {
        Pop-Location
    }

    # Step 5: Validate compiler installation
    Write-TestMessage "=== Validating Compiler Installation ===" -Type Step

    $homeDir = Get-UserHomeDirectory
    $compilerSentinelPath = Join-Path $homeDir '.bc-tool-cache' 'al' 'sentinel.json'

    Write-TestMessage "Checking compiler sentinel: $compilerSentinelPath" -Type Info

    if (Assert-PathExists -Path $compilerSentinelPath -Description 'Compiler sentinel') {
        # Validate sentinel content
        try {
            $sentinel = Get-Content -Path $compilerSentinelPath -Raw | ConvertFrom-Json

            if ($sentinel.packageId) {
                Write-TestMessage "Compiler package ID: $($sentinel.packageId)" -Type Success
                $script:TestsPassed++
            } else {
                Write-TestMessage "Sentinel missing packageId field" -Type Error
                $script:TestsFailed++
            }

            if ($sentinel.compilerVersion) {
                Write-TestMessage "Compiler version: $($sentinel.compilerVersion)" -Type Success
                $script:TestsPassed++
            } else {
                Write-TestMessage "Sentinel missing compilerVersion field" -Type Error
                $script:TestsFailed++
            }
        }
        catch {
            Write-TestMessage "Failed to parse compiler sentinel: $_" -Type Error
            $script:TestsFailed++
        }
    }

    # Verify compiler is in dotnet tool list
    Write-TestMessage "Checking dotnet tool list..." -Type Info
    try {
        $toolList = & dotnet tool list --global 2>&1 | Out-String
        if ($toolList -match '\bal\b') {
            Write-TestMessage "Compiler found in dotnet tool list (command: al)" -Type Success
            $script:TestsPassed++
        } else {
            Write-TestMessage "Compiler NOT found in dotnet tool list" -Type Error
            Write-TestMessage "Tool list output: $toolList" -Type Debug
            $script:TestsFailed++
        }
    }
    catch {
        Write-TestMessage "Failed to query dotnet tool list: $_" -Type Error
        $script:TestsFailed++
    }

    # Step 6: Validate symbol cache
    Write-TestMessage "=== Validating Symbol Cache ===" -Type Step

    $symbolCacheRoot = Join-Path $homeDir '.bc-symbol-cache'
    Write-TestMessage "Symbol cache root: $symbolCacheRoot" -Type Info

    Assert-PathExists -Path $symbolCacheRoot -Description 'Symbol cache root'

    # Parse app.json to get expected dependencies
    $appJsonPath = Join-Path $workspacePath 'app.json'
    $appJson = Get-Content -Path $appJsonPath -Raw | ConvertFrom-Json

    Write-TestMessage "Checking dependencies from app.json..." -Type Info
    Write-TestMessage "App Publisher: $($appJson.publisher)" -Type Info
    Write-TestMessage "App Name: $($appJson.name)" -Type Info
    Write-TestMessage "App ID: $($appJson.id)" -Type Info

    # Cache structure: ~/.bc-symbol-cache/{app_publisher}/{app_name}/{app_id}/symbols.lock.json
    $safeAppPublisher = ConvertTo-SafePathSegment -Value $appJson.publisher
    $safeAppName = ConvertTo-SafePathSegment -Value $appJson.name
    $safeAppId = ConvertTo-SafePathSegment -Value $appJson.id

    $appCacheDir = Join-Path $symbolCacheRoot $safeAppPublisher | Join-Path -ChildPath $safeAppName | Join-Path -ChildPath $safeAppId
    Write-TestMessage "App cache directory: $appCacheDir" -Type Info

    if (Assert-PathExists -Path $appCacheDir -Description 'App symbol cache directory') {
        # Check for symbols.lock.json
        $lockFilePath = Join-Path $appCacheDir 'symbols.lock.json'

        if (Assert-PathExists -Path $lockFilePath -Description 'symbols.lock.json') {
            # Validate lock file contains all dependencies
            try {
                $lockFile = Get-Content -Path $lockFilePath -Raw | ConvertFrom-Json

                if ($lockFile.appId -eq $appJson.id) {
                    Write-TestMessage "Lock file app ID matches" -Type Success
                    $script:TestsPassed++
                } else {
                    Write-TestMessage "Lock file app ID mismatch: $($lockFile.appId) vs $($appJson.id)" -Type Error
                    $script:TestsFailed++
                }

                # Check dependencies are listed in lock file packages
                if ($appJson.dependencies -and $appJson.dependencies.Count -gt 0) {
                    Write-TestMessage "Validating $($appJson.dependencies.Count) dependencies in lock file" -Type Info

                    foreach ($dep in $appJson.dependencies) {
                        # Dependencies are in the packages hashtable
                        # Format: publisher.name.symbols.id (name has spaces removed in key)
                        $nameNoSpaces = $dep.name.Replace(' ', '')
                        $packageKey = "$($dep.publisher).$nameNoSpaces.symbols.$($dep.id)"

                        # Check if package exists in lockFile.packages
                        $packageFound = $lockFile.packages.PSObject.Properties.Name -contains $packageKey

                        if ($packageFound) {
                            Write-TestMessage "Dependency $($dep.publisher)/$($dep.name) found in lock file (key: $packageKey)" -Type Success
                            $script:TestsPassed++

                            # Verify .app file exists for this dependency
                            $appFiles = Get-ChildItem -Path $appCacheDir -Filter "*.app" -ErrorAction SilentlyContinue
                            # Match publisher and name (with spaces removed)
                            $depAppFile = $appFiles | Where-Object {
                                $_.Name -like "$($dep.publisher).$nameNoSpaces*"
                            }

                            if ($depAppFile) {
                                Write-TestMessage "Symbol .app file exists: $($depAppFile.Name)" -Type Success
                                $script:TestsPassed++
                            } else {
                                Write-TestMessage "Symbol .app file NOT found for $($dep.publisher)/$($dep.name)" -Type Error
                                Write-TestMessage "Available .app files: $($appFiles.Name -join ', ')" -Type Debug
                                $script:TestsFailed++
                            }
                        } else {
                            Write-TestMessage "Dependency $($dep.publisher)/$($dep.name) NOT found in lock file" -Type Error
                            Write-TestMessage "Expected key: $packageKey" -Type Debug
                            Write-TestMessage "Available package keys: $($lockFile.packages.PSObject.Properties.Name -join ', ')" -Type Debug
                            $script:TestsFailed++
                        }
                    }
                }
            }
            catch {
                Write-TestMessage "Failed to parse lock file: $_" -Type Error
                $script:TestsFailed++
            }
        }
    }

    # Step 7: Report summary
    Write-TestMessage "========================================" -Type Info
    Write-TestMessage "Test Summary:" -Type Info
    Write-TestMessage "Tests Passed: $script:TestsPassed" -Type Success
    Write-TestMessage "Tests Failed: $script:TestsFailed" -Type $(if ($script:TestsFailed -gt 0) { 'Error' } else { 'Success' })
    Write-TestMessage "========================================" -Type Info

    if ($script:TestsFailed -eq 0) {
        Write-TestMessage "All provision tests PASSED" -Type Success
        exit 0
    } else {
        Write-TestMessage "Some provision tests FAILED" -Type Error
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
