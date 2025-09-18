#requires -Version 7.0

[CmdletBinding()]
param(
    [string]$Version,
    [string]$MaintainerSummary,
    [psobject]$Diff,
    [psobject]$Manifest,
    [psobject]$OverlayPayload,
    [string]$RepositoryRoot,
    [string]$CurrentCommit,
    [datetime]$ReleaseDateUtc,
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

function Get-CommitSha {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot,
        [string]$Ref = 'HEAD'
    )

    if (Get-Command -Name Assert-GitAvailable -ErrorAction SilentlyContinue) {
        Assert-GitAvailable
    }
    $gitArgs = @('-C', $RepositoryRoot, 'rev-parse', $Ref)
    $output = & git @gitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to resolve commit for ref '$Ref'"
    }
    return ($output | Select-Object -First 1).Trim()
}

function New-ReleaseNotes {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$Version,
        [string]$MaintainerSummary,
        [psobject]$Diff,
        [psobject]$Manifest,
        [psobject]$OverlayPayload,
        [string]$RepositoryRoot,
        [string]$CurrentCommit,
        [datetime]$ReleaseDateUtc
    )

    if (-not $PSCmdlet.ShouldProcess('release notes', 'Compose release notes payload')) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw 'ERROR: ReleaseNotes - Version parameter is required to compose release notes.'
    }

    $repoRoot = Get-RepositoryRootPath -RepositoryRoot $RepositoryRoot
    $versionScript = Join-Path -Path $PSScriptRoot -ChildPath 'version.ps1'
    if (-not (Test-Path -LiteralPath $versionScript)) {
        throw "Version helper script not found at $versionScript"
    }

    $versionJson = & $versionScript -Version $Version -RepositoryRoot $repoRoot -AsJson
    if ([string]::IsNullOrWhiteSpace($versionJson)) {
        throw "Version helper returned empty response for $Version."
    }

    $versionInfo = $versionJson | ConvertFrom-Json -Depth 6
    $candidate = $versionInfo.Candidate

    $overlay = if ($OverlayPayload) {
        $OverlayPayload
    } else {
        $overlayScript = Join-Path -Path $PSScriptRoot -ChildPath 'overlay.ps1'
        if (-not (Test-Path -LiteralPath $overlayScript)) {
            throw "Overlay helper script not found at $overlayScript"
        }
        & $overlayScript -RepositoryRoot $repoRoot
    }

    $manifestInfo = if ($Manifest) {
        $Manifest
    } else {
        $manifestScript = Join-Path -Path $PSScriptRoot -ChildPath 'hash-manifest.ps1'
        if (-not (Test-Path -LiteralPath $manifestScript)) {
            throw "Hash manifest helper script not found at $manifestScript"
        }
        $manifestJson = & $manifestScript -RepositoryRoot $repoRoot -OverlayPayload $overlay -AsJson
        if ([string]::IsNullOrWhiteSpace($manifestJson)) {
            throw 'Hash manifest helper returned empty response.'
        }
        $manifestJson | ConvertFrom-Json -Depth 6
    }

    $diffInfo = if ($Diff) {
        $Diff
    } else {
        $diffScript = Join-Path -Path $PSScriptRoot -ChildPath 'diff-summary.ps1'
        if (-not (Test-Path -LiteralPath $diffScript)) {
            throw "Diff summary helper script not found at $diffScript"
        }
        $diffJson = & $diffScript -Version $candidate.Normalized -RepositoryRoot $repoRoot -AsJson
        if ([string]::IsNullOrWhiteSpace($diffJson)) {
            throw 'Diff summary helper returned empty response.'
        }
        $diffJson | ConvertFrom-Json -Depth 6
    }

    $commitSha = if ($CurrentCommit) { $CurrentCommit } elseif ($diffInfo.CurrentCommit) { $diffInfo.CurrentCommit } else { Get-CommitSha -RepositoryRoot $repoRoot -Ref 'HEAD' }
    $releasedUtc = if ($ReleaseDateUtc) { $ReleaseDateUtc.ToUniversalTime() } else { (Get-Date).ToUniversalTime() }

    $metadata = [PSCustomObject]@{
        version = $candidate.Normalized
        commit = $commitSha
        released = $releasedUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        fileCount = if ($overlay.FileCount) { [int]$overlay.FileCount } else { $manifestInfo.FileCount }
        rootSha256 = $manifestInfo.RootHash
    }
    $metadataJson = $metadata | ConvertTo-Json -Compress

    $lines = @()

    if ($MaintainerSummary) {
        $lines += ($MaintainerSummary.Trim())
        $lines += ''
    }

    $lines += '## Diff Summary'
    if ($diffInfo.IsInitialRelease) {
        $lines += '- Initial release of overlay payload.'
    } else {
        if ($diffInfo.Added.Count -gt 0) {
            $lines += '- Added:'
            foreach ($path in $diffInfo.Added) {
                $entryLine = [string]::Format('  - `{0}`', $path)
                $lines += $entryLine
            }
        }
        if ($diffInfo.Modified.Count -gt 0) {
            $lines += '- Modified:'
            foreach ($path in $diffInfo.Modified) {
                $entryLine = [string]::Format('  - `{0}`', $path)
                $lines += $entryLine
            }
        }
        if ($diffInfo.Removed.Count -gt 0) {
            $lines += '- Removed:'
            foreach ($path in $diffInfo.Removed) {
                $entryLine = [string]::Format('  - `{0}`', $path)
                $lines += $entryLine
            }
        }
        if (($diffInfo.Added.Count + $diffInfo.Modified.Count + $diffInfo.Removed.Count) -eq 0) {
            $lines += '- No overlay file changes detected since previous release.'
        }
    }

    $lines += ''
    $lines += '## Integrity'
    $lines += [string]::Format('- Files in overlay: {0}', $overlay.FileCount)
    $lines += [string]::Format('- Root SHA-256: `{0}`', $manifestInfo.RootHash)

    $lines += ''
    $lines += '```json'
    $lines += $metadataJson
    $lines += '```'

    $lines += ''
    $lines += 'Guidance: https://github.com/FBakkensen/al-build-tools/blob/main/specs/006-manual-release-workflow/quickstart.md'

    $body = [string]::Join("`n", $lines)

    return [PSCustomObject]@{
        Version = $candidate.Normalized
        MaintainerSummary = $MaintainerSummary
        BodyMarkdown = $body
        MetadataJson = $metadataJson
        Metadata = $metadata
        Diff = $diffInfo
        Manifest = $manifestInfo
        Overlay = $overlay
        Released = $releasedUtc
        Commit = $commitSha
    }
}

function Invoke-ReleaseNotesMain {
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$MaintainerSummary,
        [psobject]$Diff,
        [psobject]$Manifest,
        [psobject]$OverlayPayload,
        [string]$RepositoryRoot,
        [string]$CurrentCommit,
        [datetime]$ReleaseDateUtc,
        [switch]$AsJson
    )

    $notes = New-ReleaseNotes -Version $Version -MaintainerSummary $MaintainerSummary -Diff $Diff -Manifest $Manifest -OverlayPayload $OverlayPayload -RepositoryRoot $RepositoryRoot -CurrentCommit $CurrentCommit -ReleaseDateUtc $ReleaseDateUtc
    if ($AsJson) {
        $notes | ConvertTo-Json -Depth 6
    } else {
        $notes
    }
}

if (-not $script:IsDotSourced) {
    Invoke-ReleaseNotesMain -Version $Version -MaintainerSummary $MaintainerSummary -Diff $Diff -Manifest $Manifest -OverlayPayload $OverlayPayload -RepositoryRoot $RepositoryRoot -CurrentCommit $CurrentCommit -ReleaseDateUtc $ReleaseDateUtc -AsJson:$AsJson
}
