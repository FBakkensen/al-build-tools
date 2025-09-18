#requires -Version 7.0

[CmdletBinding()]
param(
    [string]$Version,
    [string]$RepositoryRoot,
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

function Assert-GitAvailable {
    if ($script:GitVerified) { return }
    try {
        & git --version > $null 2>&1
    } catch {
        throw 'ERROR: VersionHelper - git executable not found in PATH. Install git to inspect release tags.'
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'ERROR: VersionHelper - git executable not found in PATH. Install git to inspect release tags.'
    }
    $script:GitVerified = $true
}

function ConvertTo-ReleaseVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $trimmed = $Version.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'ERROR: VersionHelper - Version value is required.'
    }

    $match = [Regex]::Match($trimmed, '^v(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)$')
    if (-not $match.Success) {
        throw "Version '$Version' is not a valid semantic version with leading 'v' (e.g. v1.2.3)."
    }

    $major = [int]$match.Groups['major'].Value
    $minor = [int]$match.Groups['minor'].Value
    $patch = [int]$match.Groups['patch'].Value

    return [PSCustomObject]@{
        RawInput  = $Version
        Normalized = "v{0}.{1}.{2}" -f $major, $minor, $patch
        Major = $major
        Minor = $minor
        Patch = $patch
        TagName = "v{0}.{1}.{2}" -f $major, $minor, $patch
    }
}

function Compare-ReleaseVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Left,
        [Parameter(Mandatory = $true)]
        $Right
    )

    if ($Left -isnot [psobject] -or -not ($Left | Get-Member -Name 'Major' -ErrorAction SilentlyContinue)) {
        $Left = ConvertTo-ReleaseVersion -Version ($Left.ToString())
    }

    if ($Right -isnot [psobject] -or -not ($Right | Get-Member -Name 'Major' -ErrorAction SilentlyContinue)) {
        $Right = ConvertTo-ReleaseVersion -Version ($Right.ToString())
    }

    $compare = $Left.Major.CompareTo($Right.Major)
    if ($compare -ne 0) { return $compare }

    $compare = $Left.Minor.CompareTo($Right.Minor)
    if ($compare -ne 0) { return $compare }

    return $Left.Patch.CompareTo($Right.Patch)
}

function Get-VersionTags {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    Assert-GitAvailable
    $gitArgs = @('-C', $RepositoryRoot, 'tag', '--list', 'v*')
    $result = & git @gitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to enumerate git tags from $RepositoryRoot."
    }

    if ($null -eq $result) { return @() }

    $tags = @()
    foreach ($line in $result) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $tags += $line.Trim()
        }
    }
    return $tags
}

function Get-LatestReleaseVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $tags = @(Get-VersionTags -RepositoryRoot $RepositoryRoot)
    if ($tags.Count -eq 0) { return $null }

    $parsed = @()
    foreach ($tag in $tags) {
        try {
            $version = ConvertTo-ReleaseVersion -Version $tag
            $parsed += [PSCustomObject]@{
                RawTag = $tag
                Version = $version
            }
        } catch {
            continue
        }
    }

    if ($parsed.Count -eq 0) { return $null }

    $sorted = $parsed | Sort-Object -Property @{ Expression = { $_.Version.Major }; Descending = $true }, @{ Expression = { $_.Version.Minor }; Descending = $true }, @{ Expression = { $_.Version.Patch }; Descending = $true }
    return $sorted[0]
}

function Test-ReleaseTagExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,
        [Parameter(Mandatory = $true)]
        [string]$TagName
    )

    Assert-GitAvailable
    $gitArgs = @('-C', $RepositoryRoot, 'rev-parse', '--quiet', '--verify', "refs/tags/$TagName")
    & git @gitArgs > $null 2>&1
    $exists = $LASTEXITCODE -eq 0

    # Ensure downstream callers don't inherit git's non-zero exit code when the tag is absent.
    Set-Variable -Scope Global -Name LASTEXITCODE -Value 0

    return $exists
}

function Get-VersionInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [string]$RepositoryRoot
    )

    $repoRoot = Get-RepositoryRootPath -RepositoryRoot $RepositoryRoot
    $candidate = ConvertTo-ReleaseVersion -Version $Version

    $tags = @(Get-VersionTags -RepositoryRoot $repoRoot)
    $parsedTags = @()
    foreach ($tag in $tags) {
        try {
            $parsedTags += ConvertTo-ReleaseVersion -Version $tag
        } catch {
            continue
        }
    }

    $latestInfo = Get-LatestReleaseVersion -RepositoryRoot $repoRoot
    $latestVersion = if ($latestInfo) { $latestInfo.Version } else { $null }

    $comparisonToLatest = if ($latestVersion) { Compare-ReleaseVersion -Left $candidate -Right $latestVersion } else { 1 }
    $tagExists = Test-ReleaseTagExists -RepositoryRoot $repoRoot -TagName $candidate.TagName

    return [PSCustomObject]@{
        RepositoryRoot = $repoRoot
        Candidate = $candidate
        Latest = $latestVersion
        ExistingTags = $parsedTags | Sort-Object -Property @{ Expression = { $_.Major } }, @{ Expression = { $_.Minor } }, @{ Expression = { $_.Patch } }
        ComparisonToLatest = $comparisonToLatest
        IsGreaterThanLatest = $comparisonToLatest -gt 0
        TagExists = $tagExists
    }
}

function Invoke-VersionHelperMain {
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$RepositoryRoot,
        [switch]$AsJson
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw 'ERROR: VersionHelper - Version parameter is required when executing version.ps1 directly.'
    }

    $info = Get-VersionInfo -Version $Version -RepositoryRoot $RepositoryRoot
    if ($AsJson) {
        $info | ConvertTo-Json -Depth 6
    } else {
        $info
    }
}

if (-not $script:IsDotSourced) {
    Invoke-VersionHelperMain -Version $Version -RepositoryRoot $RepositoryRoot -AsJson:$AsJson
}
