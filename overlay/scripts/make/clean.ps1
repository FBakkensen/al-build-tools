
# Windows Clean Script
param([string]$AppDir)

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via make (e.g., make clean)"
    exit 2
}

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\json-parser.ps1"

$outputPath = Get-OutputPath $AppDir
if ($outputPath -and (Test-Path $outputPath)) {
    Remove-Item -Force $outputPath
    Write-Output "Removed build artifact: $outputPath"
    exit 0
} else {
    Write-Output "No build artifact found to clean ($outputPath)"
    exit 0
}
