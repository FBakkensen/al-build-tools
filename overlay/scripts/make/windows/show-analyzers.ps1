
# Windows Show-Analyzers Script
param([string]$AppDir)
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\json-parser.ps1"

$enabledAnalyzers = Get-EnabledAnalyzers $AppDir
Write-Output "Enabled analyzers:"
if ($enabledAnalyzers -and $enabledAnalyzers.Count -gt 0) {
    $enabledAnalyzers | ForEach-Object { Write-Output "  $_" }
} else {
    Write-Output "  (none)"
}

$analyzerPaths = Get-EnabledAnalyzerPaths $AppDir
if ($analyzerPaths -and $analyzerPaths.Count -gt 0) {
    Write-Output "Analyzer DLL paths:"
    $analyzerPaths | ForEach-Object { Write-Output "  $_" }
} else {
    Write-Warning "No analyzer DLLs found."
}
exit 0
