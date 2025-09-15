
# Windows Show-Config Script
# Exit codes: uses mapping from lib/common.ps1 (FR-024)
param([string]$AppDir)

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    . "$PSScriptRoot\lib\common.ps1"
    $Exit = Get-ExitCodes
    Write-Output "Run via make (e.g., make show-config)"
    exit $Exit.Guard
}

. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\json-parser.ps1"

$Exit = Get-ExitCodes

$appJson = Get-AppJsonObject $AppDir
if ($appJson) {
    Write-Output "App.json configuration:"
    Write-Output "  Name: $($appJson.name)"
    Write-Output "  Publisher: $($appJson.publisher)"
    Write-Output "  Version: $($appJson.version)"
} else {
    Write-Error "ERROR: app.json not found or invalid."
}

$settingsJson = Get-SettingsJsonObject $AppDir
if ($settingsJson) {
    Write-Output "Settings.json configuration:"
    if ($settingsJson.'al.codeAnalyzers' -and $settingsJson.'al.codeAnalyzers'.Count -gt 0) {
        Write-Output "  Analyzers: $($settingsJson.'al.codeAnalyzers')"
    } else {
        Write-Output "  Analyzers: (none)"
    }
} else {
    Write-Warning ".vscode/settings.json not found or invalid."
}
exit $Exit.Success
