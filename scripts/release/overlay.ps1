#requires -Version 7.0

[CmdletBinding()]
param(
    [string]$RepositoryRoot,
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

function Get-OverlayPayload {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot
    )

    $repoRoot = Get-RepositoryRootPath -RepositoryRoot $RepositoryRoot
    $overlayPath = Join-Path -Path $repoRoot -ChildPath 'overlay'
    if (-not (Test-Path -LiteralPath $overlayPath)) {
        throw "Overlay directory not found at $overlayPath"
    }

    $resolvedOverlay = (Resolve-Path -LiteralPath $overlayPath -ErrorAction Stop).Path

    # Include dot-prefixed entries (e.g., overlay/.github) when enumerating payload files.
    $files = Get-ChildItem -LiteralPath $resolvedOverlay -Recurse -File -Force

    $payloadFiles = @()
    foreach ($file in $files) {
        $relativeToRepo = [IO.Path]::GetRelativePath($repoRoot, $file.FullName)
        $normalized = $relativeToRepo.Replace('\', '/')
        $payloadFiles += [PSCustomObject]@{
            RelativePath = $normalized
            FullPath = $file.FullName
            SizeBytes = [int64]$file.Length
            LastWriteTimeUtc = $file.LastWriteTimeUtc
        }
    }

    $payloadFiles = $payloadFiles | Sort-Object -Property RelativePath
    $totalBytes = 0
    foreach ($entry in $payloadFiles) { $totalBytes += $entry.SizeBytes }

    return [PSCustomObject]@{
        RepositoryRoot = $repoRoot
        RootPath = $resolvedOverlay
        FileCount = $payloadFiles.Count
        ByteSizeTotal = $totalBytes
        GeneratedUtc = (Get-Date).ToUniversalTime()
        Files = $payloadFiles
    }
}

function Invoke-OverlayScannerMain {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot,
        [switch]$AsJson
    )

    $payload = Get-OverlayPayload -RepositoryRoot $RepositoryRoot
    if ($AsJson) {
        $payload | ConvertTo-Json -Depth 6
    } else {
        $payload
    }
}

if (-not $script:IsDotSourced) {
    Invoke-OverlayScannerMain -RepositoryRoot $RepositoryRoot -AsJson:$AsJson
}
