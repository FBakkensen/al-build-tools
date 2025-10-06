#requires -Version 7.2

<#
.SYNOPSIS
    Clean AL project build artifacts with structured status reporting.

.DESCRIPTION
    Removes generated .app build artifacts from the AL project directory and provides
    detailed status information about the cleanup operation.

.PARAMETER AppDir
    Directory containing app.json and build artifacts

.NOTES
    This script uses Write-Information for output to ensure compatibility with different
    PowerShell hosts and automation scenarios.
#>

# PSScriptAnalyzer suppressions for intentional design choices
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM is preferred for cross-platform compatibility')]
param([string]$AppDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Import shared utilities
Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking

$Exit = Get-ExitCode

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via make (e.g., make clean)"
    exit $Exit.Guard
}

Write-BuildHeader "Clean - Build Artifact Analysis"

$outputPath = Get-OutputPath $AppDir
$fileName = if ($outputPath) { Split-Path $outputPath -Leaf } else { '(unknown)' }
$directory = if ($outputPath) { Split-Path $outputPath -Parent } else { '(unknown)' }

Write-BuildMessage -Type Step -Message "Detecting build artifacts..."
Write-BuildMessage -Type Detail -Message "Expected file: $fileName"
Write-BuildMessage -Type Detail -Message "Target directory: $directory"

$artifactExists = $outputPath -and (Test-Path $outputPath)
if ($artifactExists) {
    Write-BuildMessage -Type Success -Message "Artifact found"
} else {
    Write-BuildMessage -Type Warning -Message "Artifact not found"
}

Write-BuildHeader "Clean - Cleanup Operation"

if ($artifactExists) {
    Write-BuildMessage -Type Step -Message "Removing build artifacts..."

    try {
        # Get file info before deletion for reporting
        $fileInfo = Get-Item -LiteralPath $outputPath
        $fileSize = if ($fileInfo.Length -lt 1024) {
            "{0} bytes" -f $fileInfo.Length
        } elseif ($fileInfo.Length -lt 1048576) {
            "{0:N1} KB" -f ($fileInfo.Length / 1024)
        } else {
            "{0:N1} MB" -f ($fileInfo.Length / 1048576)
        }

        Remove-Item -Force $outputPath -ErrorAction Stop
        Write-BuildMessage -Type Success -Message "Removed: $fileName ($fileSize freed)"
        Write-BuildMessage -Type Detail -Message "Path: $outputPath"

        Write-BuildHeader "Clean - Summary"
        Write-BuildMessage -Type Success -Message "Cleanup completed successfully!"

    } catch {
        Write-BuildMessage -Type Error -Message "Failed to remove artifact: $($_.Exception.Message)"
        exit $Exit.GeneralError
    }
} else {
    Write-BuildMessage -Type Info -Message "No artifacts found to clean"
    if ($outputPath) {
        Write-BuildMessage -Type Detail -Message "Expected path: $outputPath"
    }

    Write-BuildHeader "Clean - Summary"
    Write-BuildMessage -Type Info -Message "Workspace is already clean - no cleanup needed"
}

exit $Exit.Success