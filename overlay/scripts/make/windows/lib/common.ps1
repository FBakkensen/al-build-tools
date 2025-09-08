
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
    # Search multiple VS Code roots: stable, insiders, local/server variants
    $roots = @(
        (Join-Path $env:USERPROFILE ".vscode\extensions"),
        (Join-Path $env:USERPROFILE ".vscode-insiders\extensions"),
        (Join-Path $env:USERPROFILE ".vscode-server\extensions"),
        (Join-Path $env:USERPROFILE ".vscode-server-insiders\extensions")
    )
    $candidates = @()
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $items = Get-ChildItem -Path $root -Filter "ms-dynamics-smb.al-*" -ErrorAction SilentlyContinue
        if ($items) { $candidates += $items }
    }
    if (-not $candidates -or $candidates.Count -eq 0) { return $null }

    $parseVersion = {
        param($name)
        # Extract numeric prefix; tolerate suffixes like -preview
        if ($name -match "ms-dynamics-smb\.al-([0-9]+(\.[0-9]+)*)") {
            return [version]$matches[1]
        } else {
            return [version]"0.0.0"
        }
    }

    $withVersion = $candidates | ForEach-Object {
        $ver = & $parseVersion $_.Name
        $isInsiders = if ($_.FullName -match 'insiders') { 1 } else { 0 }
        [PSCustomObject]@{ Ext = $_; Version = $ver; Insiders = $isInsiders }
    }
    # Prefer Insiders when versions are equal
    $highest = $withVersion | Sort-Object -Property Version, Insiders -Descending | Select-Object -First 1
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
                $enabled = @($json.'al.codeAnalyzers')
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

    $alExt = Get-HighestVersionALExtension
    $workspaceRoot = (Get-Location).Path
    $appFull = try { (Resolve-Path $AppDir -ErrorAction Stop).Path } catch { Join-Path $workspaceRoot $AppDir }
    $analyzersDir = if ($alExt) { Join-Path $alExt.FullName 'bin/Analyzers' } else { $null }

    function Resolve-AnalyzerEntry {
        param([string]$Entry)
        $val = $Entry
        if ($null -eq $val) { return @() }
        # Token-aware join when a token is concatenated with a filename
        if ($val -match '^\$\{analyzerFolder\}(.*)$' -and $analyzersDir) {
            $tail = $matches[1]
            if ($tail -and $tail[0] -notin @('\\','/')) { $val = Join-Path $analyzersDir $tail }
            else { $val = "$analyzersDir$tail" }
        }
        if ($val -match '^\$\{alExtensionPath\}(.*)$' -and $alExt) {
            $tail2 = $matches[1]
            if ($tail2 -and $tail2[0] -notin @('\\','/')) { $val = Join-Path $alExt.FullName $tail2 }
            else { $val = "$($alExt.FullName)$tail2" }
        }
        # Placeholder expansion
        if ($alExt) {
            $val = $val.Replace('${alExtensionPath}', $alExt.FullName)
            $val = $val.Replace('${analyzerFolder}', $analyzersDir)
        }
        $val = $val.Replace('${workspaceFolder}', $workspaceRoot)
        $val = $val.Replace('${workspaceRoot}', $workspaceRoot)
        $val = $val.Replace('${appDir}', $appFull)
        # Strip remaining ${}
        $val = [regex]::Replace($val, '\$\{([^}]+)\}', '$1')
        # Expand env vars and ~
        $val = [Environment]::ExpandEnvironmentVariables($val)
        if ($val.StartsWith('~')) { $val = $val -replace '^~', $env:USERPROFILE }
        # Make absolute if relative
        if (-not [IO.Path]::IsPathRooted($val)) { $val = Join-Path $workspaceRoot $val }

        # Directory => *.dll inside
        if (Test-Path $val -PathType Container) {
            return Get-ChildItem -Path $val -Filter '*.dll' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        }
        # Wildcards
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($val)) {
            return Get-ChildItem -Path $val -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        }
        # File exists
        if (Test-Path $val -PathType Leaf) { return @($val) }
        return @()
    }

    $dllPaths = New-Object System.Collections.Generic.List[string]
    foreach ($item in $enabled) {
        $name = ($item | Out-String).Trim()
        if ($name -match '^\$\{([A-Za-z]+)\}$') { $name = $matches[1] }
        if ($supported -contains $name) {
            if ($alExt) {
                $dll = $dllMap[$name]
                if ($dll) {
                    $found = Get-ChildItem -Path $alExt.FullName -Recurse -Filter $dll -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) { $dllPaths.Add($found.FullName) }
                }
            }
        } else {
            (Resolve-AnalyzerEntry -Entry $name) | ForEach-Object { if ($_ -and -not $dllPaths.Contains($_)) { $dllPaths.Add($_) } }
        }
    }
    return $dllPaths
}
