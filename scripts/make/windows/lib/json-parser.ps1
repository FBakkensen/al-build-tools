

function Get-AppJsonObject {
    param([string]$AppDir)
    $appJson = Get-AppJsonPath $AppDir
    if (-not $appJson) { return $null }
    try {
        $json = Get-Content $appJson -Raw | ConvertFrom-Json
        return $json
    } catch {
        return $null
    }
}

function Get-SettingsJsonObject {
    param([string]$AppDir)
    $settingsPath = Get-SettingsJsonPath $AppDir
    if (-not $settingsPath) { return $null }
    try {
        $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
        return $json
    } catch {
        return $null
    }
}

function Get-EnabledAnalyzers {
    param([string]$AppDir)
    $settings = Get-SettingsJsonObject $AppDir
    if ($settings -and $settings.'al.codeAnalyzers') {
        return $settings.'al.codeAnalyzers' | ForEach-Object { $_.Replace('$${','').Replace('}','') }
    } else {
        return @('CodeCop','UICop')
    }
}
