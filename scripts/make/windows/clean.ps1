
# Windows Clean Script
param([string]$AppDir)
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\json-parser.ps1"

$outputPath = Get-OutputPath $AppDir
if ($outputPath -and (Test-Path $outputPath)) {
    Remove-Item -Force $outputPath
    Write-Host "Removed build artifact: $outputPath" -ForegroundColor Green
    exit 0
} else {
    Write-Host "No build artifact found to clean ($outputPath)" -ForegroundColor Yellow
    exit 0
}
