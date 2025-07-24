
# Windows Show-Config Script
param([string]$AppDir)
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\json-parser.ps1"

$appJson = Get-AppJsonObject $AppDir
if ($appJson) {
    Write-Host "App.json configuration:" -ForegroundColor Cyan
    Write-Host "  Name: $($appJson.name)"
    Write-Host "  Publisher: $($appJson.publisher)"
    Write-Host "  Version: $($appJson.version)"
} else {
    Write-Host "ERROR: app.json not found or invalid." -ForegroundColor Red
}

$settingsJson = Get-SettingsJsonObject $AppDir
if ($settingsJson) {
    Write-Host "Settings.json configuration:" -ForegroundColor Cyan
    Write-Host "  Analyzers: $($settingsJson.'al.codeAnalyzers')"
} else {
    Write-Host "No .vscode/settings.json found or invalid." -ForegroundColor Yellow
}
exit 0
