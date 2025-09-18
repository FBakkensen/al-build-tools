#requires -Version 7.0

[CmdletBinding()]
param(
    [string]$Version,
    [string]$RepositoryRoot,
    [psobject]$OverlayPayload,
    [psobject]$Manifest,
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

function Ensure-HelpersLoaded {
    if (-not (Get-Command -Name Get-OverlayPayload -ErrorAction SilentlyContinue)) {
        $overlayScript = Join-Path -Path $PSScriptRoot -ChildPath 'overlay.ps1'
        if (-not (Test-Path -LiteralPath $overlayScript)) {
            throw "Overlay helper script not found at $overlayScript"
        }
        . $overlayScript
    }

    if (-not (Get-Command -Name ConvertTo-ReleaseVersion -ErrorAction SilentlyContinue)) {
        $versionScript = Join-Path -Path $PSScriptRoot -ChildPath 'version.ps1'
        if (-not (Test-Path -LiteralPath $versionScript)) {
            throw "Version helper script not found at $versionScript"
        }
        . $versionScript
    }

    if (-not (Get-Command -Name New-HashManifest -ErrorAction SilentlyContinue)) {
        $manifestScript = Join-Path -Path $PSScriptRoot -ChildPath 'hash-manifest.ps1'
        if (-not (Test-Path -LiteralPath $manifestScript)) {
            throw "Hash manifest helper script not found at $manifestScript"
        }
        . $manifestScript
    }
}

function New-ReleaseArtifact {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$Version,
        [string]$RepositoryRoot,
        [psobject]$OverlayPayload,
        [psobject]$Manifest,
        [string]$OutputPath
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw 'ERROR: ReleaseArtifact - Version parameter is required to create release artifact.'
    }

    Ensure-HelpersLoaded

    $repoRoot = Get-RepositoryRootPath -RepositoryRoot $RepositoryRoot
    $versionInfo = ConvertTo-ReleaseVersion -Version $Version

    $overlay = if ($OverlayPayload) { $OverlayPayload } else { Get-OverlayPayload -RepositoryRoot $repoRoot }
    $manifestInfo = if ($Manifest) { $Manifest } else { New-HashManifest -OverlayPayload $overlay -RepositoryRoot $repoRoot }

    $defaultDir = Join-Path -Path $repoRoot -ChildPath 'artifacts/release'
    $outputCandidate = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        Join-Path -Path $defaultDir -ChildPath ("al-build-tools-{0}.zip" -f $versionInfo.Normalized)
    } else {
        $OutputPath
    }

    $outputFullPath = [System.IO.Path]::GetFullPath($outputCandidate)
    $targetDir = Split-Path -Parent $outputFullPath

    if (-not $PSCmdlet.ShouldProcess($outputFullPath, 'Create release artifact zip')) {
        return [PSCustomObject]@{
            RepositoryRoot = $repoRoot
            Version = $versionInfo.Normalized
            OutputPath = $outputFullPath
            FileName = [System.IO.Path]::GetFileName($outputFullPath)
            SizeBytes = 0
            Sha256 = $null
            ContainsManifest = $true
            FileCount = $overlay.FileCount
            Manifest = $manifestInfo
            Skipped = $true
        }
    }

    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $outputFullPath) {
        Remove-Item -LiteralPath $outputFullPath -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $fileMode = [System.IO.FileMode]::Create
    $fileAccess = [System.IO.FileAccess]::ReadWrite
    $fileShare = [System.IO.FileShare]::None
    $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal

    $stream = [System.IO.File]::Open($outputFullPath, $fileMode, $fileAccess, $fileShare)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create, $false, [System.Text.Encoding]::UTF8)
        try {
            foreach ($file in $overlay.Files) {
                $entry = $archive.CreateEntry($file.RelativePath, $compressionLevel)
                $entryStream = $entry.Open()
                try {
                    $sourceStream = [System.IO.File]::Open($file.FullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                    try {
                        $sourceStream.CopyTo($entryStream)
                    } finally {
                        $sourceStream.Dispose()
                    }
                } finally {
                    $entryStream.Dispose()
                }
            }

            $manifestEntry = $archive.CreateEntry('manifest.sha256.txt', $compressionLevel)
            $writer = New-Object System.IO.StreamWriter($manifestEntry.Open(), [System.Text.Encoding]::UTF8)
            try {
                $writer.Write($manifestInfo.ManifestText)
            } finally {
                $writer.Dispose()
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        $stream.Dispose()
    }

    $resolvedPath = (Resolve-Path -LiteralPath $outputFullPath -ErrorAction Stop).Path
    $fileInfo = Get-Item -LiteralPath $resolvedPath
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedPath

    return [PSCustomObject]@{
        RepositoryRoot = $repoRoot
        Version = $versionInfo.Normalized
        OutputPath = $resolvedPath
        FileName = [System.IO.Path]::GetFileName($resolvedPath)
        SizeBytes = [int64]$fileInfo.Length
        Sha256 = $hash.Hash.ToLowerInvariant()
        ContainsManifest = $true
        FileCount = $overlay.FileCount
        Manifest = $manifestInfo
        Skipped = $false
    }
}

function Invoke-ReleaseArtifactMain {
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$RepositoryRoot,
        [psobject]$OverlayPayload,
        [psobject]$Manifest,
        [string]$OutputPath,
        [switch]$AsJson
    )

    $artifact = New-ReleaseArtifact -Version $Version -RepositoryRoot $RepositoryRoot -OverlayPayload $OverlayPayload -Manifest $Manifest -OutputPath $OutputPath
    if ($AsJson) {
        $artifact | ConvertTo-Json -Depth 6
    } else {
        $artifact
    }
}

if (-not $script:IsDotSourced) {
    Invoke-ReleaseArtifactMain -Version $Version -RepositoryRoot $RepositoryRoot -OverlayPayload $OverlayPayload -Manifest $Manifest -OutputPath $OutputPath -AsJson:$AsJson
}
