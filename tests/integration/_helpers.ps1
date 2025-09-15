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

function _Get-RepoRoot {
    # tests/integration/_helpers.ps1 -> tests -> repo root
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path | ForEach-Object { (Resolve-Path $_).Path }
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
    $lf = ($Text -replace "\r\n?", "\n")
    $lines = $lf -split "\n", -1
    $trimmed = $lines | ForEach-Object { ($_ ?? '') -replace "[\t ]+$", '' }
    # Re-join ensuring a single trailing newline at most
    $joined = ($trimmed -join "\n")
    return $joined
}

