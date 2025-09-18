#requires -Version 7.0

[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [psobject]$OverlayPayload,
    [string]$OutputPath,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:IsDotSourced = $MyInvocation.InvocationName -eq '.'
$script:DefaultRepoRoot = $null

function Get-RepositoryRootPath {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot
    )

    if ($RepositoryRoot) {
        $resolved = Resolve-Path -LiteralPath $RepositoryRoot -ErrorAction Stop
        return $resolved.Path
    }

    if (-not $script:DefaultRepoRoot) {
        $scriptsDir = Split-Path -Parent $PSScriptRoot
        $repoRootCandidate = Split-Path -Parent $scriptsDir
        $script:DefaultRepoRoot = (Resolve-Path -LiteralPath $repoRootCandidate -ErrorAction Stop).Path
    }

    return $script:DefaultRepoRoot
}

function Ensure-OverlayHelpersLoaded {
    if (Get-Command -Name Get-OverlayPayload -ErrorAction SilentlyContinue) {
        return
    }
    $overlayScript = Join-Path -Path $PSScriptRoot -ChildPath 'overlay.ps1'
    if (-not (Test-Path -LiteralPath $overlayScript)) {
        throw "Overlay helper script not found at $overlayScript"
    }
    . $overlayScript
}

function New-HashManifest {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [psobject]$OverlayPayload,
        [string]$RepositoryRoot,
        [string]$OutputPath
    )

    Ensure-OverlayHelpersLoaded
    $repoRoot = Get-RepositoryRootPath -RepositoryRoot $RepositoryRoot

    $payload = if ($OverlayPayload) {
        $OverlayPayload
    } else {
        Get-OverlayPayload -RepositoryRoot $repoRoot
    }

    $entries = @()
    $lines = @()

    foreach ($file in $payload.Files) {
        $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullPath
        $entry = [PSCustomObject]@{
            Path = $file.RelativePath
            Hash = $hash.Hash.ToLowerInvariant()
        }
        $entries += $entry
        $lines += "{0}:{1}" -f $entry.Path, $entry.Hash
    }

    $bodyText = if ($lines.Count -gt 0) { [string]::Join("`n", $lines) } else { '' }
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyText)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $rootHashBytes = $sha.ComputeHash($bodyBytes)
    } finally {
        $sha.Dispose()
    }
    $rootHash = -join ($rootHashBytes | ForEach-Object { $_.ToString('x2') })

    $manifestLines = @($lines)
    $manifestLines += "__ROOT__:$rootHash"
    $manifestText = [string]::Join("`n", $manifestLines)
    if ($manifestText.Length -gt 0) {
        $manifestText += "`n"
    }

    $resolvedOutput = $null
    if ($OutputPath) {
        $outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
        if ($PSCmdlet.ShouldProcess($outputFullPath, 'Write hash manifest file')) {
            $directory = Split-Path -Parent $outputFullPath
            if ($directory -and -not (Test-Path -LiteralPath $directory)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($outputFullPath, $manifestText, [System.Text.Encoding]::UTF8)
            $resolvedOutput = (Resolve-Path -LiteralPath $outputFullPath -ErrorAction Stop).Path
        } else {
            $resolvedOutput = $outputFullPath
        }
    }

    return [PSCustomObject]@{
        RepositoryRoot = $repoRoot
        FileCount = $payload.FileCount
        Algorithm = 'sha256'
        GeneratedUtc = (Get-Date).ToUniversalTime()
        Entries = $entries
        RootHash = $rootHash
        ManifestLines = $manifestLines
        ManifestText = $manifestText
        OutputPath = $resolvedOutput
    }
}

function Invoke-HashManifestMain {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot,
        [psobject]$OverlayPayload,
        [string]$OutputPath,
        [switch]$AsJson
    )

    $manifest = New-HashManifest -OverlayPayload $OverlayPayload -RepositoryRoot $RepositoryRoot -OutputPath $OutputPath
    if ($AsJson) {
        $manifest | ConvertTo-Json -Depth 6
    } else {
        $manifest
    }
}

if (-not $script:IsDotSourced) {
    Invoke-HashManifestMain -RepositoryRoot $RepositoryRoot -OverlayPayload $OverlayPayload -OutputPath $OutputPath -AsJson:$AsJson
}
