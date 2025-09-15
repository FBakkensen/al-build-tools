
# Windows Clean Script
# Exit codes: uses mapping from lib/common.ps1 (FR-024)
param([string]$AppDir)

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    . "$PSScriptRoot\lib\common.ps1"
    $Exit = Get-ExitCodes
    Write-Output "Run via make (e.g., make clean)"
    exit $Exit.Guard
}

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\json-parser.ps1"

$Exit = Get-ExitCodes

$outputPath = Get-OutputPath $AppDir
if ($outputPath -and (Test-Path $outputPath)) {
    Remove-Item -Force $outputPath
    Write-Output "Removed build artifact: $outputPath"
    exit $Exit.Success
} else {
    Write-Output "No build artifact found to clean ($outputPath)"
    exit $Exit.Success
}
