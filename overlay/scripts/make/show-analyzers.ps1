
# Windows Show-Analyzers Script
# Exit codes: uses mapping from lib/common.ps1 (FR-024)
param([string]$AppDir)

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    . "$PSScriptRoot\lib\common.ps1"
    $Exit = Get-ExitCodes
    Write-Output "Run via make (e.g., make show-analyzers)"
    exit $Exit.Guard
}

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\json-parser.ps1"

$Exit = Get-ExitCodes

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
exit $Exit.Success
