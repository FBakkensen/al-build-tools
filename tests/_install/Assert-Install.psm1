
#requires -Version 7.0
Set-StrictMode -Version Latest

$script:InstallTempLinePattern = '^\[install\]\s+temp\s+(?<Pairs>.+)$'
$script:InstallSuccessLinePattern = '^\[install\]\s+success\s+(?<Pairs>.+)$'
$script:InstallGuardLinePattern = '^\[install\]\s+guard\s+(?<Guard>[A-Za-z0-9]+)(?<Pairs>(?:\s+[A-Za-z0-9_-]+=.*)*)$'
$script:InstallDownloadFailurePattern = '^\[install\]\s+download\s+failure\s+(?<Pairs>.+)$'
$script:InstallDownloadCategories = @('NetworkUnavailable','NotFound','CorruptArchive','Timeout','Unknown')

function ConvertFrom-InstallQuotedValue {
    param(
        [string] $Value
    )

    if ($null -eq $Value) { return $null }
    $trim = $Value.Trim()
    if ($trim.Length -ge 2) {
        if ($trim.StartsWith('"') -and $trim.EndsWith('"')) {
            return $trim.Substring(1, $trim.Length - 2).Replace('""', '"')
        }
        if ($trim.StartsWith("'") -and $trim.EndsWith("'")) {
            return $trim.Substring(1, $trim.Length - 2).Replace("''", "'")
        }
    }
    return $trim
}

function Get-InstallKeyValueMap {
    param(
        [string] $Text
    )

    $map = [ordered]@{}
    if ([string]::IsNullOrWhiteSpace($Text)) { return $map }

    # Parse key=value segments while allowing spaces in values by stopping at the next key token.
    $pattern = '(?<Key>[A-Za-z0-9_-]+)=(?<Value>.*?)(?=\s+[A-Za-z0-9_-]+=|$)'
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        $key = $match.Groups['Key'].Value
        $value = ConvertFrom-InstallQuotedValue -Value ($match.Groups['Value'].Value.Trim())
        $map[$key] = $value
    }

    return $map
}

function Assert-InstallTempPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $Because = 'Expected installer temp workspace to reside under the system temporary directory.'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Temp workspace path is empty. $Because"
    }

    if (-not [IO.Path]::IsPathRooted($Path)) {
        throw "Temp workspace path '$Path' must be absolute. $Because"
    }

    try {
        $full = [IO.Path]::GetFullPath($Path)
    } catch {
        throw "Temp workspace path '$Path' is not a valid file system path. $Because`n$($_.Exception.Message)"
    }

    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $full.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Temp workspace path '$full' is not located under '$tempRoot'. $Because"
    }

    $leaf = Split-Path -Path $full -Leaf
    if ($leaf -notmatch '^[A-Za-z0-9][A-Za-z0-9_\.-]{2,}$') {
        throw "Temp workspace directory name '$leaf' does not match expected random pattern. $Because"
    }

    return $full
}

function Assert-InstallTempLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Line
    )

    $match = [regex]::Match($Line, $script:InstallTempLinePattern)
    if (-not $match.Success) {
        throw "Line '$Line' does not match expected '[install] temp' diagnostic pattern."
    }

    $pairs = Get-InstallKeyValueMap -Text $match.Groups['Pairs'].Value
    if (-not $pairs.Contains('workspace')) {
        throw "Temp diagnostic line '$Line' must include 'workspace=' token."
    }

    $normalized = Assert-InstallTempPath -Path $pairs['workspace']
    return [pscustomobject]@{
        Workspace = $normalized
        Pairs = $pairs
        RawLine = $Line
    }
}

function Assert-InstallSuccessLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Line,
        [string] $ExpectedRef,
        [string] $ExpectedOverlay,
        [double] $MaxDurationSeconds
    )

    $match = [regex]::Match($Line, $script:InstallSuccessLinePattern)
    if (-not $match.Success) {
        throw "Line '$Line' does not match expected '[install] success' diagnostic pattern."
    }

    $pairs = Get-InstallKeyValueMap -Text $match.Groups['Pairs'].Value
    foreach ($required in @('ref','overlay','duration')) {
        if (-not $pairs.Contains($required)) {
            throw "Success diagnostic line '$Line' is missing '$required='."
        }
    }

    try {
        $duration = [double]::Parse($pairs['duration'], [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        throw "Duration value '$($pairs['duration'])' from line '$Line' is not numeric."
    }

    if ($duration -lt 0) {
        throw "Duration value '$duration' from line '$Line' cannot be negative."
    }

    if ($PSBoundParameters.ContainsKey('ExpectedRef') -and $pairs['ref'] -ne $ExpectedRef) {
        throw "Expected ref '$ExpectedRef' but found '$($pairs['ref'])' in line '$Line'."
    }

    if ($PSBoundParameters.ContainsKey('ExpectedOverlay') -and $pairs['overlay'] -ne $ExpectedOverlay) {
        throw "Expected overlay '$ExpectedOverlay' but found '$($pairs['overlay'])' in line '$Line'."
    }

    if ($PSBoundParameters.ContainsKey('MaxDurationSeconds') -and $duration -gt $MaxDurationSeconds) {
        throw "Duration '$duration' from line '$Line' exceeds allowed max $MaxDurationSeconds seconds."
    }

    return [pscustomobject]@{
        Ref = $pairs['ref']
        Overlay = $pairs['overlay']
        DurationSeconds = $duration
        Pairs = $pairs
        RawLine = $Line
    }
}

function Assert-InstallGuardLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Line,
        [string] $ExpectedGuard
    )

    $match = [regex]::Match($Line, $script:InstallGuardLinePattern)
    if (-not $match.Success) {
        throw "Line '$Line' does not match expected '[install] guard <Name>' diagnostic pattern."
    }

    $guard = $match.Groups['Guard'].Value
    if ($PSBoundParameters.ContainsKey('ExpectedGuard') -and $guard -ne $ExpectedGuard) {
        throw "Expected guard '$ExpectedGuard' but found '$guard' in line '$Line'."
    }

    $pairs = Get-InstallKeyValueMap -Text $match.Groups['Pairs'].Value
    return [pscustomobject]@{
        Guard = $guard
        Pairs = $pairs
        RawLine = $Line
    }
}

function Assert-InstallDownloadFailureLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Line,
        [string] $ExpectedRef,
        [string] $ExpectedUrl,
        [string] $ExpectedCategory
    )

    $match = [regex]::Match($Line, $script:InstallDownloadFailurePattern)
    if (-not $match.Success) {
        throw "Line '$Line' does not match expected '[install] download failure' diagnostic pattern."
    }

    $pairs = Get-InstallKeyValueMap -Text $match.Groups['Pairs'].Value
    foreach ($required in @('ref','url','category','hint')) {
        if (-not $pairs.Contains($required)) {
            throw "Download failure diagnostic line '$Line' is missing '$required='."
        }
    }

    if ($script:InstallDownloadCategories -notcontains $pairs['category']) {
        $allowed = $script:InstallDownloadCategories -join ', '
        throw "Unexpected download failure category '$($pairs['category'])'. Allowed: $allowed."
    }

    try {
        [void][Uri]$pairs['url']
    } catch {
        throw "URL '$($pairs['url'])' from line '$Line' is not a valid URI."
    }

    if ($PSBoundParameters.ContainsKey('ExpectedRef') -and $pairs['ref'] -ne $ExpectedRef) {
        throw "Expected ref '$ExpectedRef' but found '$($pairs['ref'])' in line '$Line'."
    }

    if ($PSBoundParameters.ContainsKey('ExpectedUrl') -and $pairs['url'] -ne $ExpectedUrl) {
        throw "Expected url '$ExpectedUrl' but found '$($pairs['url'])' in line '$Line'."
    }

    if ($PSBoundParameters.ContainsKey('ExpectedCategory') -and $pairs['category'] -ne $ExpectedCategory) {
        throw "Expected category '$ExpectedCategory' but found '$($pairs['category'])' in line '$Line'."
    }

    return [pscustomobject]@{
        Ref = $pairs['ref']
        Url = $pairs['url']
        Category = $pairs['category']
        Hint = $pairs['hint']
        Pairs = $pairs
        RawLine = $Line
    }
}

function Get-InstallDirectorySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $BasePath
    )

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    if ($PSBoundParameters.ContainsKey('BasePath')) {
        $baseResolved = Resolve-Path -LiteralPath $BasePath -ErrorAction Stop
    } else {
        $baseResolved = $resolved
    }

    $rootPath = [IO.Path]::GetFullPath($baseResolved.Path)
    $files = Get-ChildItem -LiteralPath $resolved.Path -Recurse -File | Sort-Object -Property FullName

    $snapshot = @()
    foreach ($file in $files) {
        $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
        $relative = [IO.Path]::GetRelativePath($rootPath, $file.FullName)
        $normalized = $relative -replace '\', '/'
        $snapshot += [pscustomobject]@{
            Path = $normalized
            Hash = $hash.Hash.ToLowerInvariant()
            Length = $file.Length
        }
    }

    return $snapshot
}

function Compare-InstallSnapshots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IEnumerable] $Expected,
        [Parameter(Mandatory)] [System.Collections.IEnumerable] $Actual
    )

    $expectedMap = @{}
    foreach ($item in $Expected) {
        if ($null -eq $item) { continue }
        if (-not $item.PSObject.Properties.Match('Path')) { continue }
        $expectedMap[$item.Path] = $item
    }

    $actualMap = @{}
    foreach ($item in $Actual) {
        if ($null -eq $item) { continue }
        if (-not $item.PSObject.Properties.Match('Path')) { continue }
        $actualMap[$item.Path] = $item
    }

    $missing = @()
    foreach ($path in $expectedMap.Keys) {
        if (-not $actualMap.ContainsKey($path)) { $missing += $path }
    }

    $extra = @()
    foreach ($path in $actualMap.Keys) {
        if (-not $expectedMap.ContainsKey($path)) { $extra += $path }
    }

    $hashMismatches = @()
    foreach ($path in $expectedMap.Keys) {
        if ($actualMap.ContainsKey($path)) {
            $expectedItem = $expectedMap[$path]
            $actualItem = $actualMap[$path]
            if ($expectedItem.Hash -ne $actualItem.Hash) {
                $hashMismatches += [pscustomobject]@{
                    Path = $path
                    ExpectedHash = $expectedItem.Hash
                    ActualHash = $actualItem.Hash
                    ExpectedLength = $expectedItem.Length
                    ActualLength = $actualItem.Length
                }
            }
        }
    }

    return [pscustomobject]@{
        Missing = $missing
        Extra = $extra
        HashMismatches = $hashMismatches
    }
}

function Assert-InstallSnapshotsEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IEnumerable] $Expected,
        [Parameter(Mandatory)] [System.Collections.IEnumerable] $Actual,
        [string] $Because = 'Directory fingerprints differ.'
    )

    $diff = Compare-InstallSnapshots -Expected $Expected -Actual $Actual

    $missingCount = ($diff.Missing | Measure-Object).Count
    $extraCount = ($diff.Extra | Measure-Object).Count
    $mismatchCount = ($diff.HashMismatches | Measure-Object).Count

    if ($missingCount -eq 0 -and $extraCount -eq 0 -and $mismatchCount -eq 0) {
        return $true
    }

    $parts = @()
    if ($missingCount -gt 0) { $parts += "missing: $($diff.Missing -join ', ')" }
    if ($extraCount -gt 0) { $parts += "extra: $($diff.Extra -join ', ')" }
    if ($mismatchCount -gt 0) {
        $summaries = $diff.HashMismatches | ForEach-Object { '{0} (expected={1} actual={2})' -f $_.Path, $_.ExpectedHash, $_.ActualHash }
        $parts += "hash mismatches: $($summaries -join '; ')"
    }

    $joined = $parts -join '; '
    throw "$Because Differences -> $joined"
}

Export-ModuleMember -Function `
    Assert-InstallTempPath, `
    Assert-InstallTempLine, `
    Assert-InstallSuccessLine, `
    Assert-InstallGuardLine, `
    Assert-InstallDownloadFailureLine, `
    Get-InstallDirectorySnapshot, `
    Compare-InstallSnapshots, `
    Assert-InstallSnapshotsEqual
