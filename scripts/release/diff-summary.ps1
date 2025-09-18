#requires -Version 7.0

[CmdletBinding()]
param(
    [string]$Version,
    [string]$RepositoryRoot,
    [string]$PreviousRef,
    [string]$CurrentRef,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:IsDotSourced = $MyInvocation.InvocationName -eq '.'
$script:DefaultRepoRoot = $null
$script:GitVerified = $false

function ConvertTo-VersionNumber {
    param([string]$Input)

    if ([string]::IsNullOrWhiteSpace($Input)) {
        return $null
    }

    $match = [Regex]::Match($Input, '^v(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)$')
    if (-not $match.Success) {
        return $null
    }

    return [System.Version]::new(
        [int]$match.Groups['major'].Value,
        [int]$match.Groups['minor'].Value,
        [int]$match.Groups['patch'].Value
    )
}

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

function Assert-GitAvailable {
    if ($script:GitVerified) { return }
    try { & git --version > $null 2>&1 } catch { throw 'ERROR: DiffSummary - git executable not found in PATH. Install git to compute release diffs.' }
    if ($LASTEXITCODE -ne 0) {
        throw 'ERROR: DiffSummary - git executable not found in PATH. Install git to compute release diffs.'
    }
    $script:GitVerified = $true
}

function Get-CommitSha {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot,
        [string]$Ref = 'HEAD'
    )

    Assert-GitAvailable
    $gitArgs = @('-C', $RepositoryRoot, 'rev-parse', $Ref)
    $output = & git @gitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to resolve commit for ref '$Ref'"
    }
    return ($output | Select-Object -First 1).Trim()
}

function Get-PreviousReference {
    [CmdletBinding()]
    param(
        [psobject]$VersionInfo,
        [psobject]$CandidateVersion,
        [string]$ExplicitPrevious
    )

    if ($ExplicitPrevious) { return $ExplicitPrevious }

    if (-not $VersionInfo -or -not $VersionInfo.ExistingTags) {
        return $null
    }

    $candidateVersionValue = ConvertTo-VersionNumber $CandidateVersion.Normalized
    if (-not $candidateVersionValue) {
        return $null
    }

    $lower = @()
    foreach ($tagEntry in $VersionInfo.ExistingTags) {
        $normalized = $null
        if ($tagEntry.PSObject.Properties['Normalized']) {
            $normalized = $tagEntry.Normalized
        } elseif ($tagEntry.PSObject.Properties['TagName']) {
            $normalized = $tagEntry.TagName
        } elseif ($tagEntry.PSObject.Properties['RawInput']) {
            $normalized = $tagEntry.RawInput
        }

        if ([string]::IsNullOrWhiteSpace($normalized)) {
            continue
        }

        $tagVersionValue = ConvertTo-VersionNumber $normalized
        if (-not $tagVersionValue) {
            continue
        }

        if ($tagVersionValue -lt $candidateVersionValue) {
            $lower += [PSCustomObject]@{
                Tag = $normalized
                Version = $tagVersionValue
            }
        }
    }

    if ($lower.Count -eq 0) { return $null }

    ($lower | Sort-Object -Property Version | Select-Object -Last 1).Tag
}

function Get-DiffSummary {
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$RepositoryRoot,
        [string]$PreviousRef,
        [string]$CurrentRef
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw 'ERROR: DiffSummary - Version parameter is required to compute diff summary.'
    }

    Assert-GitAvailable

    $repoRoot = Get-RepositoryRootPath -RepositoryRoot $RepositoryRoot
    $currentRefEffective = if ($CurrentRef) { $CurrentRef } else { 'HEAD' }
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
    $previousRefEffective = Get-PreviousReference -VersionInfo $versionInfo -CandidateVersion $candidate -ExplicitPrevious $PreviousRef

    $added = [System.Collections.Generic.List[string]]::new()
    $modified = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()
    $rawLines = @()

    if ($previousRefEffective) {
        $gitArgs = @('-C', $repoRoot, 'diff', '--name-status', '--find-renames', '--diff-filter=AMDR', $previousRefEffective, $currentRefEffective, '--', 'overlay')
        $rawLines = & git @gitArgs
        if ($LASTEXITCODE -ne 0) {
            throw "git diff failed when comparing $previousRefEffective to $currentRefEffective"
        }

        foreach ($line in ($rawLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            $parts = $line -split "`t"
            if ($parts.Count -lt 2) { continue }
            $status = $parts[0]
            if ($status.StartsWith('R')) {
                # Rename: treat new path as modified
                if ($parts.Count -ge 3) {
                    $newPath = $parts[2]
                    $modified.Add($newPath)
                }
                continue
            }
            switch -Regex ($status) {
                '^A' { $added.Add($parts[1]); continue }
                '^M' { $modified.Add($parts[1]); continue }
                '^D' { $removed.Add($parts[1]); continue }
                '^C' { $added.Add($parts[1]); continue }
            }
        }
    }

    $addedArray = ($added | Sort-Object -Unique) ?? @()
    $modifiedArray = ($modified | Sort-Object -Unique) ?? @()
    $removedArray = ($removed | Sort-Object -Unique) ?? @()

    $currentCommit = Get-CommitSha -RepositoryRoot $repoRoot -Ref $currentRefEffective
    $previousCommit = if ($previousRefEffective) { Get-CommitSha -RepositoryRoot $repoRoot -Ref $previousRefEffective } else { $null }

    return [PSCustomObject]@{
        RepositoryRoot = $repoRoot
        CurrentVersion = $candidate.Normalized
        PreviousVersion = $previousRefEffective
        CurrentRef = $currentRefEffective
        CurrentCommit = $currentCommit
        PreviousCommit = $previousCommit
        Added = @($addedArray)
        Modified = @($modifiedArray)
        Removed = @($removedArray)
        IsInitialRelease = [string]::IsNullOrWhiteSpace($previousRefEffective)
        Notes = if ([string]::IsNullOrWhiteSpace($previousRefEffective)) { 'Initial release' } else { $null }
        RawDiffLines = $rawLines
    }
}

function Invoke-DiffSummaryMain {
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$RepositoryRoot,
        [string]$PreviousRef,
        [string]$CurrentRef,
        [switch]$AsJson
    )

    $summary = Get-DiffSummary -Version $Version -RepositoryRoot $RepositoryRoot -PreviousRef $PreviousRef -CurrentRef $CurrentRef
    if ($AsJson) {
        $summary | ConvertTo-Json -Depth 6
    } else {
        $summary
    }
}

if (-not $script:IsDotSourced) {
    Invoke-DiffSummaryMain -Version $Version -RepositoryRoot $RepositoryRoot -PreviousRef $PreviousRef -CurrentRef $CurrentRef -AsJson:$AsJson
}
