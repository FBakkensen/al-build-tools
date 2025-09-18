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

function Ensure-VersionHelpersLoaded {
    if (Get-Command -Name ConvertTo-ReleaseVersion -ErrorAction SilentlyContinue) {
        return
    }
    $versionScript = Join-Path -Path $PSScriptRoot -ChildPath 'version.ps1'
    if (-not (Test-Path -LiteralPath $versionScript)) {
        throw "Version helper script not found at $versionScript"
    }
    . $versionScript
}

function Assert-GitAvailable {
    if ($script:GitVerified) { return }
    try { & git --version > $null 2>&1 } catch { throw 'git executable not found in PATH. Diff helper requires git.' }
    if ($LASTEXITCODE -ne 0) {
        throw 'git executable not found in PATH. Diff helper requires git.'
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
        [string]$RepositoryRoot,
        [psobject]$CandidateVersion,
        [string]$ExplicitPrevious
    )

    if ($ExplicitPrevious) { return $ExplicitPrevious }

    Ensure-VersionHelpersLoaded
    $tags = Get-VersionTags -RepositoryRoot $RepositoryRoot
    if ($tags.Count -eq 0) { return $null }

    $parsed = @()
    foreach ($tag in $tags) {
        try {
            $parsed += ConvertTo-ReleaseVersion -Version $tag
        } catch {
            continue
        }
    }

    if ($parsed.Count -eq 0) { return $null }

    $lower = @()
    foreach ($tagVersion in $parsed) {
        if (Compare-ReleaseVersion -Left $tagVersion -Right $CandidateVersion -lt 0) {
            $lower += $tagVersion
        }
    }

    if ($lower.Count -eq 0) { return $null }

    $sorted = $lower | Sort-Object -Property @{Expression = { $_.Major }; Descending = $true}, @{Expression = { $_.Minor }; Descending = $true}, @{Expression = { $_.Patch }; Descending = $true}
    return $sorted[0].TagName
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
        throw 'Version parameter is required to compute diff summary.'
    }

    Ensure-VersionHelpersLoaded
    Assert-GitAvailable

    $repoRoot = Get-RepositoryRootPath -RepositoryRoot $RepositoryRoot
    $currentRefEffective = if ($CurrentRef) { $CurrentRef } else { 'HEAD' }
    $versionInfo = Get-VersionInfo -Version $Version -RepositoryRoot $repoRoot
    $candidate = $versionInfo.Candidate
    $previousRefEffective = Get-PreviousReference -RepositoryRoot $repoRoot -CandidateVersion $candidate -ExplicitPrevious $PreviousRef

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
