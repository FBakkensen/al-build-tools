
# Windows Show-Analyzers Script
param([string]$AppDir)
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\json-parser.ps1"

$enabledAnalyzers = Get-EnabledAnalyzers $AppDir
Write-Host "Enabled analyzers:" -ForegroundColor Cyan
$enabledAnalyzers | ForEach-Object { Write-Host "  $_" }

$analyzerPaths = Get-EnabledAnalyzerPaths $AppDir
if ($analyzerPaths -and $analyzerPaths.Count -gt 0) {
    Write-Host "Analyzer DLL paths:" -ForegroundColor Cyan
    $analyzerPaths | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "No analyzer DLLs found." -ForegroundColor Yellow
}
exit 0
