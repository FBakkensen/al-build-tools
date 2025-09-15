#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Integration test helpers for fixture projects and make-level invocation
# Provided functions:
# - New-Fixture
# - Install-Overlay
# - Write-AppJson
# - Write-SettingsJson
# - Invoke-Make
# - _Normalize-Output
# - New-AppFixture               (T014.2)
# - Get-ExpectedOutputPath       (utility for T014.4)

function _Get-RepoRoot {
    # tests/integration/_helpers.ps1 -> tests -> repo root
    $testsDir = Resolve-Path (Join-Path $PSScriptRoot '..')
    $repoRoot = Resolve-Path (Join-Path $testsDir '..')
    return $repoRoot.Path
}

function New-Fixture {
    [CmdletBinding()]
    param(
        [string] $Prefix = 'albt-int'
    )
    $tmp = [IO.Path]::GetTempPath()
    $name = "${Prefix}-" + [Guid]::NewGuid().ToString('N')
    $path = Join-Path $tmp $name
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function Install-Overlay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FixturePath,
        [string] $OverlayPath
    )
    if (-not $OverlayPath) {
        $repo = _Get-RepoRoot
        $OverlayPath = Join-Path $repo 'overlay'
    }
    if (-not (Test-Path $OverlayPath)) {
        throw "Overlay path not found: $OverlayPath"
    }
    # Copy overlay payload contents into fixture root (Makefile, scripts/, etc.)
    Get-ChildItem -LiteralPath $OverlayPath -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $FixturePath -Recurse -Force
    }
    return (Test-Path (Join-Path $FixturePath 'Makefile'))
}

function Write-AppJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $AppDir,
        [string] $Name = 'SampleApp',
        [string] $Publisher = 'FBakkensen',
        [string] $Version = '1.0.0.0'
    )
    if (-not (Test-Path $AppDir)) { New-Item -ItemType Directory -Path $AppDir -Force | Out-Null }
    $appJsonPath = Join-Path $AppDir 'app.json'
    $json = [pscustomobject]@{
        id = ([Guid]::NewGuid().ToString())
        name = $Name
        publisher = $Publisher
        version = $Version
        application = "26.0.0.0"
        platform = "26.0.0.0"
        runtime = "13.0"
    } | ConvertTo-Json -Depth 5
    # Ensure stable newline
    $json = _Normalize-Output $json
    Set-Content -LiteralPath $appJsonPath -Value $json -NoNewline
    return $appJsonPath
}

function Write-SettingsJson {
    [CmdletBinding(DefaultParameterSetName='Analyzers')]
    param(
        [Parameter(Mandatory)] [string] $AppDir,
        [Parameter(ParameterSetName='Analyzers')] [string[]] $Analyzers,
        [Parameter(ParameterSetName='Raw')] [string] $RawJson
    )
    $vscodeDir = Join-Path $AppDir '.vscode'
    if (-not (Test-Path $vscodeDir)) { New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null }
    $settingsPath = Join-Path $vscodeDir 'settings.json'
    if ($PSCmdlet.ParameterSetName -eq 'Raw') {
        $content = if ($RawJson) { $RawJson } else { '{}' }
        $content = _Normalize-Output $content
        Set-Content -LiteralPath $settingsPath -Value $content -NoNewline
        return $settingsPath
    }
    $obj = if ($Analyzers) {
        [pscustomobject]@{ 'al.codeAnalyzers' = @($Analyzers) }
    } else {
        # Explicitly set none to match current behavior when not configured
        [pscustomobject]@{}
    }
    $json = $obj | ConvertTo-Json -Depth 5
    $json = _Normalize-Output $json
    Set-Content -LiteralPath $settingsPath -Value $json -NoNewline
    return $settingsPath
}

function Invoke-Make {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FixturePath,
        [string] $Target = 'help',
        [hashtable] $Env
    )
    if (-not (Test-Path (Join-Path $FixturePath 'Makefile'))) {
        throw "Makefile not found in fixture: $FixturePath"
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'make'
    $psi.Arguments = $Target
    $psi.WorkingDirectory = $FixturePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($Env) {
        foreach ($k in $Env.Keys) { $psi.Environment[$k] = [string]$Env[$k] }
    }
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    $exit = $proc.ExitCode
    $outStr = $proc.StandardOutput.ReadToEnd()
    $errStr = $proc.StandardError.ReadToEnd()
    return [pscustomobject]@{
        ExitCode = $exit
        StdOut   = $outStr
        StdErr   = $errStr
        StdOutNormalized = (_Normalize-Output $outStr)
        StdErrNormalized = (_Normalize-Output $errStr)
    }
}

function _Normalize-Output {
    [CmdletBinding()]
    param(
        [AllowNull()][string] $Text
    )
    if ($null -eq $Text) { return '' }
    # Normalize CRLF to LF, then trim trailing spaces from each line
    $lf = ($Text -replace "`r`n?", "`n")
    $lines = $lf -split "`n", -1
    $trimmed = $lines | ForEach-Object { ($_ ?? '') -replace "[\t ]+$", '' }
    # Re-join ensuring a single trailing newline at most
    $joined = ($trimmed -join "`n")
    return $joined
}

function New-AppFixture {
    [CmdletBinding(DefaultParameterSetName='None')]
    param(
        [string] $AppSubDir = 'app',
        [string] $Name = 'SampleApp',
        [string] $Publisher = 'FBakkensen',
        [string] $Version = '1.0.0.0',
        [Parameter(ParameterSetName='Analyzers')] [string[]] $Analyzers,
        [Parameter(ParameterSetName='Raw')] [string] $RawSettingsJson
    )
    $fixture = New-Fixture
    $null = Install-Overlay -FixturePath $fixture
    $appDir = Join-Path $fixture $AppSubDir
    $null = Write-AppJson -AppDir $appDir -Name $Name -Publisher $Publisher -Version $Version
    switch ($PSCmdlet.ParameterSetName) {
        'Analyzers' { $null = Write-SettingsJson -AppDir $appDir -Analyzers $Analyzers }
        'Raw'       { $null = Write-SettingsJson -AppDir $appDir -RawJson $RawSettingsJson }
        default     { }
    }
    return [pscustomobject]@{
        FixturePath  = $fixture
        AppDir       = $appDir
        MakefilePath = (Join-Path $fixture 'Makefile')
    }
}

function Get-ExpectedOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $AppDir
    )
    $appJsonPath = Join-Path $AppDir 'app.json'
    if (-not (Test-Path $appJsonPath)) { throw "app.json not found at $appJsonPath" }
    $json = Get-Content -LiteralPath $appJsonPath -Raw | ConvertFrom-Json
    $name = if ($json.name) { $json.name } else { 'CopilotAllTablesAndFields' }
    $version = if ($json.version) { $json.version } else { '1.0.0.0' }
    $publisher = if ($json.publisher) { $json.publisher } else { 'FBakkensen' }
    $file = "${publisher}_${name}_${version}.app"
    return Join-Path $AppDir $file
}

# Minimal replicas of overlay helper functions used by integration tests
function Get-PackageCachePath {
    param([string]$AppDir)
    return Join-Path -Path $AppDir -ChildPath '.alpackages'
}

function Get-HighestVersionALExtension {
    $roots = @(
        (Join-Path $env:USERPROFILE '.vscode\extensions'),
        (Join-Path $env:USERPROFILE '.vscode-insiders\extensions'),
        (Join-Path $env:USERPROFILE '.vscode-server\extensions'),
        (Join-Path $env:USERPROFILE '.vscode-server-insiders\extensions')
    )
    $candidates = @()
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $items = Get-ChildItem -Path $root -Filter 'ms-dynamics-smb.al-*' -ErrorAction SilentlyContinue
        if ($items) { $candidates += $items }
    }
    if (-not $candidates -or $candidates.Count -eq 0) { return $null }
    $parseVersion = { param($name) if ($name -match 'ms-dynamics-smb\.al-([0-9]+(\.[0-9]+)*)') { [version]$matches[1] } else { [version]'0.0.0' } }
    $withVersion = $candidates | ForEach-Object { $ver = & $parseVersion $_.Name; $isInsiders = if ($_.FullName -match 'insiders') { 1 } else { 0 }; [PSCustomObject]@{ Ext = $_; Version = $ver; Insiders = $isInsiders } }
    $highest = $withVersion | Sort-Object -Property Version, Insiders -Descending | Select-Object -First 1
    if ($highest) { return $highest.Ext } else { return $null }
}

function Get-ALCompilerPath {
    param([string]$AppDir)
    $alExt = Get-HighestVersionALExtension
    if ($alExt) {
        $alc = Get-ChildItem -Path $alExt.FullName -Recurse -Filter 'alc.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($alc) { return $alc.FullName }
    }
    return $null
}
