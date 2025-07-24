
param([string]$AppDir = "app")

function Get-AppJsonPath {
    param([string]$AppDir)
    $appJsonPath1 = Join-Path -Path $AppDir -ChildPath "app.json"
    $appJsonPath2 = "app.json"
    if (Test-Path $appJsonPath1) { return $appJsonPath1 }
    elseif (Test-Path $appJsonPath2) { return $appJsonPath2 }
    else { return $null }
}

function Get-SettingsJsonPath {
    param([string]$AppDir)
    $settingsPath = Join-Path -Path $AppDir -ChildPath ".vscode/settings.json"
    if (Test-Path $settingsPath) { return $settingsPath }
    $settingsPath = ".vscode/settings.json"
    if (Test-Path $settingsPath) { return $settingsPath }
    return $null
}

function Get-OutputPath {
    param([string]$AppDir)
    $appJson = Get-AppJsonPath $AppDir
    if (-not $appJson) { return $null }
    try {
        $json = Get-Content $appJson -Raw | ConvertFrom-Json
        $name = $json.name
        $version = $json.version
        $publisher = $json.publisher
        if (-not $name) { $name = "CopilotAllTablesAndFields" }
        if (-not $version) { $version = "1.0.0.0" }
        if (-not $publisher) { $publisher = "FBakkensen" }
        $outputFile = "${publisher}_${name}_${version}.app"
        # Place the .app file directly in the app directory
        return Join-Path -Path $AppDir -ChildPath $outputFile
    } catch {
        return $null
    }
}

function Get-PackageCachePath {
    param([string]$AppDir)
    return Join-Path -Path $AppDir -ChildPath ".alpackages"
}

function Write-ErrorAndExit {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
    exit 1
}

# Discover AL compiler (alc.exe) in VS Code extensions
function Get-HighestVersionALExtension {
    $alExtDir = Join-Path $env:USERPROFILE ".vscode\extensions"
    if (-not (Test-Path $alExtDir)) { return $null }
    $alExts = Get-ChildItem -Path $alExtDir -Filter "ms-dynamics-smb.al-*" -ErrorAction SilentlyContinue
    if (-not $alExts -or $alExts.Count -eq 0) { return $null }
    $parseVersion = {
        param($name)
        if ($name -match "ms-dynamics-smb\.al-(\d+\.\d+\.\d+)") {
            return [version]$matches[1]
        } else {
            return [version]"0.0.0"
        }
    }
    $alExtsWithVersion = $alExts | ForEach-Object {
        $ver = & $parseVersion $_.Name
        [PSCustomObject]@{ Ext = $_; Version = $ver }
    }
    $highest = $alExtsWithVersion | Sort-Object Version -Descending | Select-Object -First 1
    if ($highest) { return $highest.Ext } else { return $null }
}

function Get-ALCompilerPath {
    param([string]$AppDir)
    $alExt = Get-HighestVersionALExtension
    if ($alExt) {
        $alc = Get-ChildItem -Path $alExt.FullName -Recurse -Filter "alc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($alc) { return $alc.FullName }
    }
    return $null
}

# Discover enabled analyzer DLL paths from settings.json and AL extension
function Get-EnabledAnalyzerPaths {
    param([string]$AppDir)
    $settingsPath = Get-SettingsJsonPath $AppDir
    $dllMap = @{ 'CodeCop' = 'Microsoft.Dynamics.Nav.CodeCop.dll';
                 'UICop' = 'Microsoft.Dynamics.Nav.UICop.dll';
                 'AppSourceCop' = 'Microsoft.Dynamics.Nav.AppSourceCop.dll';
                 'PerTenantExtensionCop' = 'Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll' }
    $supported = @('CodeCop','UICop','AppSourceCop','PerTenantExtensionCop')
    $enabled = @()
    if ($settingsPath -and (Test-Path $settingsPath)) {
        try {
            $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($json.'al.codeAnalyzers') {
                $enabled = $json.'al.codeAnalyzers' | ForEach-Object { $_ -replace '\$\{|\}', '' }
            } elseif ($json.enableCodeCop -or $json.enableUICop -or $json.enableAppSourceCop -or $json.enablePerTenantExtensionCop) {
                if ($json.enableCodeCop) { $enabled += 'CodeCop' }
                if ($json.enableUICop) { $enabled += 'UICop' }
                if ($json.enableAppSourceCop) { $enabled += 'AppSourceCop' }
                if ($json.enablePerTenantExtensionCop) { $enabled += 'PerTenantExtensionCop' }
            }
        } catch {}
    }
    if (-not $enabled -or $enabled.Count -eq 0) {
        $enabled = @('CodeCop','UICop')
    }
    # Filter and deduplicate
    $enabled = $enabled | Where-Object { $supported -contains $_ } | Select-Object -Unique
    $alExt = Get-HighestVersionALExtension
    $dllPaths = @()
    if ($alExt) {
        foreach ($name in $enabled) {
            $dll = $dllMap[$name]
            if ($dll) {
                $found = Get-ChildItem -Path $alExt.FullName -Recurse -Filter $dll -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $dllPaths += $found.FullName
                }
            }
        }
    }
    return $dllPaths
}
