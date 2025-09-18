#requires -Version 7.0

[CmdletBinding()]
param(
    [string]$Version,
    [string]$RepositoryRoot,
    [switch]$DryRun,
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
    try { & git --version > $null 2>&1 } catch { throw 'git executable not found in PATH. Validation gates require git.' }
    if ($LASTEXITCODE -ne 0) {
        throw 'git executable not found in PATH. Validation gates require git.'
    }
    $script:GitVerified = $true
}

function Ensure-HelpersLoaded {
    if (-not (Get-Command -Name ConvertTo-ReleaseVersion -ErrorAction SilentlyContinue)) {
        $versionScript = Join-Path -Path $PSScriptRoot -ChildPath 'version.ps1'
        . $versionScript
    }
    if (-not (Get-Command -Name Get-OverlayPayload -ErrorAction SilentlyContinue)) {
        $overlayScript = Join-Path -Path $PSScriptRoot -ChildPath 'overlay.ps1'
        . $overlayScript
    }
}

function New-GateResult {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$Name,
        [string]$Status,
        [string]$Diagnostics,
        [bool]$IsBlocking,
        $Data
    )

    if (-not $PSCmdlet.ShouldProcess($Name, "Create validation gate result")) {
        return $null
    }

    return [PSCustomObject]@{
        Name = $Name
        Status = $Status
        Diagnostics = $Diagnostics
        IsBlocking = $IsBlocking
        Data = $Data
    }
}

function Test-CleanOverlay {
    param(
        [string]$RepositoryRoot
    )

    Assert-GitAvailable
    $gitArgs = @('-C', $RepositoryRoot, 'status', '--short', '--untracked-files=all', 'overlay')
    $status = & git @gitArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to inspect git status for overlay directory.'
    }

    $lines = @($status | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -eq 0) {
        return New-GateResult -Name 'CleanOverlay' -Status 'Passed' -Diagnostics 'Overlay directory is clean.' -IsBlocking $true -Data @()
    }

    $preview = $lines | Select-Object -First 10
    $diag = "Overlay contains uncommitted changes:`n{0}" -f ($preview -join '`n')
    return New-GateResult -Name 'CleanOverlay' -Status 'Failed' -Diagnostics $diag -IsBlocking $true -Data $lines
}

function Test-UniqueVersion {
    param(
        [psobject]$VersionInfo,
        [bool]$DryRun
    )

    if (-not $VersionInfo) {
        throw 'VersionInfo is required for uniqueness gate.'
    }

    if (-not $VersionInfo.TagExists) {
        return New-GateResult -Name 'UniqueVersion' -Status 'Passed' -Diagnostics 'Proposed tag does not exist.' -IsBlocking (-not $DryRun) -Data @{}
    }

    $diag = "Tag {0} already exists." -f $VersionInfo.Candidate.TagName
    $isBlocking = -not $DryRun
    $status = if ($DryRun) { 'Failed (DryRun)' } else { 'Failed' }
    return New-GateResult -Name 'UniqueVersion' -Status $status -Diagnostics $diag -IsBlocking $isBlocking -Data @{ Existing = $true }
}

function Test-MonotonicVersion {
    param(
        [psobject]$VersionInfo,
        [bool]$DryRun
    )

    if (-not $VersionInfo) {
        throw 'VersionInfo is required for monotonicity gate.'
    }

    if (-not $VersionInfo.Latest) {
        return New-GateResult -Name 'MonotonicVersion' -Status 'Passed' -Diagnostics 'No prior release tags detected.' -IsBlocking (-not $DryRun) -Data @{}
    }

    if ($VersionInfo.IsGreaterThanLatest) {
        $diag = "Candidate {0} is greater than latest {1}." -f $VersionInfo.Candidate.Normalized, $VersionInfo.Latest.Normalized
        return New-GateResult -Name 'MonotonicVersion' -Status 'Passed' -Diagnostics $diag -IsBlocking (-not $DryRun) -Data @{}
    }

    $diagFail = "Candidate {0} is not greater than latest {1}." -f $VersionInfo.Candidate.Normalized, $VersionInfo.Latest.Normalized
    $status = if ($DryRun) { 'Failed (DryRun)' } else { 'Failed' }
    return New-GateResult -Name 'MonotonicVersion' -Status $status -Diagnostics $diagFail -IsBlocking (-not $DryRun) -Data @{ Latest = $VersionInfo.Latest.Normalized }
}

function Test-OverlayIsolation {
    param(
        [psobject]$OverlayPayload
    )

    if (-not $OverlayPayload) {
        throw 'OverlayPayload is required for overlay isolation gate.'
    }

    $outliers = @()
    foreach ($file in $OverlayPayload.Files) {
        if (-not ($file.RelativePath -like 'overlay/*')) {
            $outliers += $file.RelativePath
        }
    }

    if ($outliers.Count -eq 0) {
        return New-GateResult -Name 'OverlayIsolation' -Status 'Passed' -Diagnostics 'Overlay file list limited to overlay/.' -IsBlocking $true -Data @{}
    }

    $diag = "Non-overlay files detected: {0}" -f ($outliers -join ', ')
    return New-GateResult -Name 'OverlayIsolation' -Status 'Failed' -Diagnostics $diag -IsBlocking $true -Data $outliers
}

function Test-DryRunSafety {
    param(
        [bool]$DryRun
    )

    if ($DryRun) {
        return New-GateResult -Name 'DryRunSafety' -Status 'Passed' -Diagnostics 'Dry-run: publishing steps disabled.' -IsBlocking $false -Data @{ DryRun = $true }
    }

    return New-GateResult -Name 'DryRunSafety' -Status 'Passed' -Diagnostics 'Real run: irreversible steps allowed after validations.' -IsBlocking $false -Data @{ DryRun = $false }
}

function Invoke-ValidationGates {
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$RepositoryRoot,
        [bool]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw 'Version parameter is required for validation gates.'
    }

    Ensure-HelpersLoaded
    Assert-GitAvailable

    $repoRoot = Get-RepositoryRootPath -RepositoryRoot $RepositoryRoot
    $versionInfo = Get-VersionInfo -Version $Version -RepositoryRoot $repoRoot
    $overlayPayload = Get-OverlayPayload -RepositoryRoot $repoRoot

    $gates = @()
    $gates += Test-CleanOverlay -RepositoryRoot $repoRoot
    $gates += Test-UniqueVersion -VersionInfo $versionInfo -DryRun:$DryRun
    $gates += Test-MonotonicVersion -VersionInfo $versionInfo -DryRun:$DryRun
    $gates += Test-OverlayIsolation -OverlayPayload $overlayPayload
    $gates += Test-DryRunSafety -DryRun:$DryRun

    $blockingFailures = $gates | Where-Object { $_.IsBlocking -and $_.Status -notlike 'Passed*' }

    return [PSCustomObject]@{
        RepositoryRoot = $repoRoot
        VersionInfo = $versionInfo
        Overlay = $overlayPayload
        DryRun = [bool]$DryRun
        Gates = $gates
        BlockingFailures = @($blockingFailures)
        AllPassed = ($blockingFailures.Count -eq 0)
    }
}

function Invoke-ValidationGatesMain {
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$RepositoryRoot,
        [switch]$DryRun,
        [switch]$AsJson
    )

    $dryRunFlag = [bool]$DryRun
    $result = Invoke-ValidationGates -Version $Version -RepositoryRoot $RepositoryRoot -DryRun:$dryRunFlag
    if ($AsJson) {
        $result | ConvertTo-Json -Depth 6
    } else {
        $result
    }
}

if (-not $script:IsDotSourced) {
    Invoke-ValidationGatesMain -Version $Version -RepositoryRoot $RepositoryRoot -DryRun:$DryRun -AsJson:$AsJson
}
