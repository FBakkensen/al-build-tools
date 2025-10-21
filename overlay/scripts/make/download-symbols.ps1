#requires -Version 7.2

<#+
.SYNOPSIS
    Downloads Business Central symbol packages required by app.json into a shared cache.

.DESCRIPTION
    Parses app.json to resolve application/platform versions and dependencies, ensures the
    corresponding NuGet packages exist in the cache, and maintains a symbols.lock.json manifest.

.PARAMETER AppDir
    Directory that contains app.json (defaults to "app" like build.ps1). You can also set
    ALBT_APP_DIR to override when the parameter is omitted.

.NOTES
    Optional environment variables:
      - ALBT_APP_DIR: override for default app directory when -AppDir omitted.
#>

param(
    [string]$AppDir = 'app'
)

if (-not $PSBoundParameters.ContainsKey('AppDir') -and $env:ALBT_APP_DIR) {
    $AppDir = $env:ALBT_APP_DIR
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Import shared utilities
Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking

$Exit = Get-ExitCode

# Guard: require invocation via Invoke-Build orchestration
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via Invoke-Build (e.g., Invoke-Build download-symbols)"
    exit $Exit.Guard
}

# Initialize timing and data capture
$script:StartTime = Get-Date
$script:versionWarnings = @{}
$script:summaryRows = New-Object System.Collections.Generic.List[object]
$script:raiseRows = New-Object System.Collections.Generic.List[object]

Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

# --- Helper Functions for Display ---
function Get-CleanPackageName {
    param([string]$PackageId)
    # Remove .symbols.<guid> pattern first (for third-party packages)
    $cleaned = $PackageId -replace '\.symbols\.[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}', ''
    # Remove .symbols (for Microsoft packages)
    $cleaned = $cleaned -replace '\.symbols$', ''
    return $cleaned
}

# --- Defaults ---
$DefaultFeeds = @(
    'https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json',
    'https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json'
)

# --- Script-Specific Helper Functions ---
# Note: Common utilities (Read-JsonFile, Expand-FullPath, Ensure-Directory, ConvertTo-SafePathSegment)
# are imported from common.psm1. Only symbol-download-specific helpers are defined here.

function Compare-Version {
    param(
        [string]$Left,
        [string]$Right
    )
    if (-not $Left -and -not $Right) { return 0 }
    if (-not $Left) { return -1 }
    if (-not $Right) { return 1 }

    $normalize = {
        param([string]$v)
        $parts = ($v -split '\.') | Where-Object { $_ -ne '' }
        # Take first 4, pad with zeros
        $nums = @()
        for ($i = 0; $i -lt 4; $i++) {
            if ($i -lt $parts.Count) {
                $segment = $parts[$i]
                $n = 0
                if (-not [int]::TryParse($segment, [ref]$n)) {
                    # Non-numeric; fallback to original string compare later
                    return $null
                }
                $nums += $n
            } else {
                $nums += 0
            }
        }
        return ,$nums
    }

    $lArr = & $normalize $Left
    $rArr = & $normalize $Right

    if ($lArr -and $rArr) {
        for ($i=0; $i -lt 4; $i++) {
            if ($lArr[$i] -lt $rArr[$i]) { return -1 }
            if ($lArr[$i] -gt $rArr[$i]) { return 1 }
        }
        return 0
    }

    return [string]::Compare($Left, $Right, $true)
}

function Build-PackageMap {
    param($AppJson)

    $map = [ordered]@{}

    if ((Test-JsonProperty $AppJson 'application') -and $AppJson.application) {
        $map['Microsoft.Application.symbols'] = [string]$AppJson.application
    }

    if ((Test-JsonProperty $AppJson 'dependencies') -and $AppJson.dependencies) {
        foreach ($dep in $AppJson.dependencies) {
            if (-not ($dep.publisher) -or -not ($dep.name) -or -not ($dep.id) -or -not ($dep.version)) { continue }
            $publisher = ($dep.publisher -replace '\s+', '')
            $name = ($dep.name -replace '\s+', '')
            $appId = ($dep.id -replace '\s+', '')
            $packageId = "{0}.{1}.symbols.{2}" -f $publisher, $name, $appId
            $map[$packageId] = [string]$dep.version
        }
    }

    return $map
}

function Load-Manifest {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Read-JsonFile -Path $Path
    } catch {
        Write-Warning "Failed to load manifest ${Path}: $($_.Exception.Message)"
        return $null
    }
}

function Test-PackagePresent {
    param([string]$CacheDir, [string]$PackageId, [string]$Version = '')
    if ($Version) {
        # Use new naming format with version
        $cleanName = Get-CleanPackageName -PackageId $PackageId
        $fileName = (ConvertTo-SafePathSegment -Value "$cleanName.$Version") + '.app'
    } else {
        # Fallback to old format for compatibility
        $fileName = (ConvertTo-SafePathSegment -Value $PackageId) + '.app'
    }
    $packagePath = Join-Path -Path $CacheDir -ChildPath $fileName
    return Test-Path -LiteralPath $packagePath
}

function ConvertTo-VersionComparable {
    param([string]$Version)
    if (-not $Version) { return $null }
    $parts = ($Version -split '\.') | Where-Object { $_ -ne '' }
    $nums = @()
    for ($i = 0; $i -lt 4; $i++) {
        if ($i -lt $parts.Count) {
            $segment = $parts[$i]
            $n = 0
            if (-not [int]::TryParse($segment, [ref]$n)) { return $Version }
            $nums += $n
        } else { $nums += 0 }
    }
    # Construct System.Version with 4 components for consistent sorting
    try { return [System.Version]::new($nums[0], $nums[1], $nums[2], $nums[3]) } catch { return $Version }
}

function Select-PackageVersion {
    param(
        [string[]]$Versions,
        [string]$MinimumVersion
    )

    if (-not $Versions -or $Versions.Count -eq 0) { return $null }

    $ordered = $Versions |
        Sort-Object -Descending -Property { ConvertTo-VersionComparable $_ }

    foreach ($version in $ordered) {
        if (-not $MinimumVersion -or (Compare-Version -Left $version -Right $MinimumVersion) -ge 0) {
            return $version
        }
    }

    return $ordered[0]
}

function Get-PackageFeedMetadata {
    param(
        [string]$PackageId,
        [string[]]$Feeds
    )

    $packageIdLower = $PackageId.ToLowerInvariant()
    foreach ($feed in $Feeds) {
        if ([string]::IsNullOrWhiteSpace($feed)) { continue }
        $baseUrl = $feed.Trim()
        if ($baseUrl.EndsWith('/index.json')) {
            $baseUrl = $baseUrl.Substring(0, $baseUrl.Length - '/index.json'.Length)
        }
        $baseUrl = $baseUrl.TrimEnd('/')
        $indexUrl = "{0}/flat2/{1}/index.json" -f $baseUrl, $packageIdLower
        try {
            $response = Invoke-RestMethod -Method Get -Uri $indexUrl -ErrorAction Stop
            if ($response -and $response.versions) {
                return [pscustomobject]@{
                    Feed = $baseUrl
                    Versions = [string[]]$response.versions
                }
            }
        } catch {
            $httpResponse = $_.Exception.Response
            if ($httpResponse -and $httpResponse.StatusCode.value__ -eq 404) {
                continue
            }
            Write-Warning "Failed to query ${indexUrl}: $($_.Exception.Message)"
        }
    }

    return $null
}

function Get-OrAddPackageMetadata {
    param(
        [string]$PackageId,
        [string[]]$Feeds,
        [hashtable]$Cache
    )

    if ($Cache -and $Cache.ContainsKey($PackageId)) {
        return $Cache[$PackageId]
    }

    $metadata = Get-PackageFeedMetadata -PackageId $PackageId -Feeds $Feeds
    if ($metadata -and ($metadata.PSObject.Properties.Name -notcontains 'HighestVersion')) {
        $metadata | Add-Member -MemberType NoteProperty -Name HighestVersion -Value (Select-PackageVersion -Versions $metadata.Versions -MinimumVersion $null)
    }
    if ($Cache -and $metadata) {
        $Cache[$PackageId] = $metadata
    }

    return $metadata
}

function Download-PackageNupkg {
    param(
        [string]$Feed,
        [string]$PackageId,
        [string]$Version,
        [string]$DestinationDirectory
    )

    $packageIdLower = $PackageId.ToLowerInvariant()
    $fileName = "{0}.{1}.nupkg" -f $packageIdLower, $Version
    $downloadUrl = "{0}/flat2/{1}/{2}/{3}" -f $Feed.TrimEnd('/'), $packageIdLower, $Version, $fileName
    $destinationPath = Join-Path -Path $DestinationDirectory -ChildPath $fileName

    $cleanPackageName = Get-CleanPackageName -PackageId $PackageId
    Write-BuildMessage -Type Step -Message "Downloading: $cleanPackageName"
    Write-BuildMessage -Type Detail -Message "Version: $Version"
    Write-BuildMessage -Type Detail -Message "Source: $Feed"

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $destinationPath -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop | Out-Null
    } catch {
        throw "Failed to download package $PackageId@$Version from ${downloadUrl}: $($_.Exception.Message)"
    }

    if ((Get-Item -LiteralPath $destinationPath).Length -eq 0) {
        throw "Downloaded package $PackageId@$Version from $downloadUrl is empty."
    }

    return $destinationPath
}

function Get-PackageDependenciesFromArchive {
    param([System.IO.Compression.ZipArchive]$Archive)

    $nuspecEntry = $Archive.Entries | Where-Object { $_.FullName -match '\.nuspec$' } | Select-Object -First 1
    if (-not $nuspecEntry) { return @() }

    $reader = New-Object System.IO.StreamReader($nuspecEntry.Open())
    try {
        $content = $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }

    if (-not $content) { return @() }

    try {
        $xml = [xml]$content
    } catch {
        Write-Warning "Failed to parse nuspec for package: $($_.Exception.Message)"
        return @()
    }

    $namespaceUri = $xml.DocumentElement.NamespaceURI
    $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    if ($namespaceUri) {
        $namespaceManager.AddNamespace('ns', $namespaceUri)
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ($namespaceUri) {
        $directDependencies = $xml.SelectNodes('//ns:package/ns:metadata/ns:dependencies/ns:dependency', $namespaceManager)
        foreach ($dep in $directDependencies) {
            if (-not $dep) { continue }
            $id = [string]$dep.Attributes['id']?.Value
            if (-not $id) { continue }
            $range = [string]$dep.Attributes['version']?.Value
            $minVersion = Get-MinimumVersionFromRange -Range $range
            $results.Add([pscustomobject]@{ Id = $id; MinimumVersion = $minVersion }) | Out-Null
        }

        $groupDependencies = $xml.SelectNodes('//ns:package/ns:metadata/ns:dependencies/ns:group/ns:dependency', $namespaceManager)
        foreach ($dep in $groupDependencies) {
            if (-not $dep) { continue }
            $id = [string]$dep.Attributes['id']?.Value
            if (-not $id) { continue }
            $range = [string]$dep.Attributes['version']?.Value
            $minVersion = Get-MinimumVersionFromRange -Range $range
            $results.Add([pscustomobject]@{ Id = $id; MinimumVersion = $minVersion }) | Out-Null
        }
    } else {
        $directDependencies = $xml.SelectNodes('//package/metadata/dependencies/dependency')
        foreach ($dep in $directDependencies) {
            if (-not $dep) { continue }
            $id = [string]$dep.Attributes['id']?.Value
            if (-not $id) { continue }
            $range = [string]$dep.Attributes['version']?.Value
            $minVersion = Get-MinimumVersionFromRange -Range $range
            $results.Add([pscustomobject]@{ Id = $id; MinimumVersion = $minVersion }) | Out-Null
        }

        $groupDependencies = $xml.SelectNodes('//package/metadata/dependencies/group/dependency')
        foreach ($dep in $groupDependencies) {
            if (-not $dep) { continue }
            $id = [string]$dep.Attributes['id']?.Value
            if (-not $id) { continue }
            $range = [string]$dep.Attributes['version']?.Value
            $minVersion = Get-MinimumVersionFromRange -Range $range
            $results.Add([pscustomobject]@{ Id = $id; MinimumVersion = $minVersion }) | Out-Null
        }
    }

    return $results.ToArray()
}

function Get-MinimumVersionFromRange {
    param([string]$Range)

    if (-not $Range) { return $null }

    $trimmed = $Range.Trim()
    if (-not $trimmed) { return $null }

    if ($trimmed.StartsWith('[') -or $trimmed.StartsWith('(')) {
        $trimmed = $trimmed.TrimStart('[', '(').TrimEnd(']', ')')
        $parts = $trimmed.Split(',')
        if ($parts.Count -eq 0 -or [string]::IsNullOrWhiteSpace($parts[0])) { return $null }
        return $parts[0].Trim()
    }

    return $trimmed
}

function Extract-SymbolApp {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$PackageId,
        [string]$Version,
        [string]$OutputDirectory
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $appEntry = $Archive.Entries | Where-Object { $_.FullName.ToLowerInvariant().EndsWith('.app') } | Select-Object -First 1
    if (-not $appEntry) {
        Write-Warning "No .app file found inside package $PackageId."
        return $null
    }

    # Create filename using clean package name + version instead of full package ID
    $cleanName = Get-CleanPackageName -PackageId $PackageId
    $destinationName = (ConvertTo-SafePathSegment -Value "$cleanName.$Version") + '.app'
    $destinationPath = Join-Path -Path $OutputDirectory -ChildPath $destinationName

    $sourceStream = $appEntry.Open()
    try {
        $fileStream = [System.IO.File]::Open($destinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $sourceStream.CopyTo($fileStream)
        } finally {
            $fileStream.Dispose()
        }
    } finally {
        $sourceStream.Dispose()
    }

    $cleanPackageName = Get-CleanPackageName -PackageId $PackageId
    Write-BuildMessage -Type Success -Message "Extracted: $cleanPackageName"
    Write-BuildMessage -Type Detail -Message "Location: $destinationPath"

    return $destinationPath
}

function Resolve-SymbolPackage {
    param(
        [string]$PackageId,
        [string]$MinimumVersion,
        [string[]]$Feeds,
        [string]$CacheDir
    )

    $metadata = Get-PackageFeedMetadata -PackageId $PackageId -Feeds $Feeds
    if (-not $metadata) {
        throw "Unable to locate package $PackageId on the configured feeds."
    }

    $selectedVersion = Select-PackageVersion -Versions $metadata.Versions -MinimumVersion $MinimumVersion
    if (-not $selectedVersion) {
        throw "No available versions found for package $PackageId"
    }

    $maxAvailableVersion = Select-PackageVersion -Versions $metadata.Versions -MinimumVersion $null

    $tempDir = New-TemporaryDirectory
    $downloadedNupkg = $null
    try {
        $downloadedNupkg = Download-PackageNupkg -Feed $metadata.Feed -PackageId $PackageId -Version $selectedVersion -DestinationDirectory $tempDir
        $archive = [System.IO.Compression.ZipFile]::OpenRead($downloadedNupkg)
        try {
            $appPath = Extract-SymbolApp -Archive $archive -PackageId $PackageId -Version $selectedVersion -OutputDirectory $CacheDir
            if (-not $appPath) {
                throw "Package $PackageId@$selectedVersion did not contain a .app file."
            }

            $dependencies = Get-PackageDependenciesFromArchive -Archive $archive

            $uniqueDependencies = @{}
            foreach ($dependency in $dependencies) {
                $depId = [string]$dependency.Id
                if (-not $depId) { continue }
                $depMinimum = $dependency.MinimumVersion

                if ($uniqueDependencies.ContainsKey($depId)) {
                    $existing = $uniqueDependencies[$depId]
                    if ($depMinimum -and (-not $existing.MinimumVersion -or (Compare-Version -Left $depMinimum -Right $existing.MinimumVersion) -gt 0)) {
                        $uniqueDependencies[$depId] = [pscustomobject]@{ Id = $depId; MinimumVersion = $depMinimum }
                    }
                } else {
                    $uniqueDependencies[$depId] = [pscustomobject]@{ Id = $depId; MinimumVersion = $depMinimum }
                }
            }

            $script:packageDependenciesCache[$PackageId] = @($uniqueDependencies.Values)

            return [pscustomobject]@{
                Version = $selectedVersion
                MaxAvailableVersion = $maxAvailableVersion
                Dependencies = @($uniqueDependencies.Values)
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        if ($downloadedNupkg -and (Test-Path -LiteralPath $downloadedNupkg)) {
            Remove-Item -LiteralPath $downloadedNupkg -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-Manifest {
    param([string]$Path, $AppJson, [hashtable]$Packages, [string[]]$Feeds)

    $payload = [ordered]@{
        application = if ((Test-JsonProperty $AppJson 'application') -and $AppJson.application) { $AppJson.application } else { $null }
        platform = if ((Test-JsonProperty $AppJson 'platform') -and $AppJson.platform) { $AppJson.platform } else { $null }
        appId = $AppJson.id
        appName = $AppJson.name
        publisher = $AppJson.publisher
        packages = $Packages
        feeds = $Feeds
        updated = (Get-Date).ToUniversalTime().ToString('o')
    }
    $json = $payload | ConvertTo-Json -Depth 6
    $json | Set-Content -LiteralPath $Path -Encoding UTF8
}

# --- Execution ---
$appJsonPath = Get-AppJsonPath $AppDir
if (-not $appJsonPath) {
    throw "app.json not found in '$AppDir'"
}
$appJson = Read-JsonFile -Path $appJsonPath

if (-not $appJson.id) { throw 'app.json is missing required "id" property.' }
if (-not $appJson.publisher) { throw 'app.json is missing required "publisher" property.' }
if (-not $appJson.name) { throw 'app.json is missing required "name" property.' }

$cacheRoot = Get-SymbolCacheRoot
Ensure-Directory -Path $cacheRoot

$publisherDir = Join-Path -Path $cacheRoot -ChildPath (ConvertTo-SafePathSegment -Value $appJson.publisher)
Ensure-Directory -Path $publisherDir
$appDirPath = Join-Path -Path $publisherDir -ChildPath (ConvertTo-SafePathSegment -Value $appJson.name)
Ensure-Directory -Path $appDirPath
$cacheDir = Join-Path -Path $appDirPath -ChildPath (ConvertTo-SafePathSegment -Value $appJson.id)
Ensure-Directory -Path $cacheDir

$manifestPath = Join-Path -Path $cacheDir -ChildPath 'symbols.lock.json'
$manifest = Load-Manifest -Path $manifestPath
$packageMap = Build-PackageMap -AppJson $appJson

Write-BuildHeader 'Package Requirements'
Write-BuildMessage -Type Info -Message "$($packageMap.Count) packages required"

if ($packageMap.Count -gt 0) {
    Write-BuildMessage -Type Step -Message "Processing package requirements..."
    foreach ($kvp in $packageMap.GetEnumerator()) {
        $cleanName = Get-CleanPackageName -PackageId $kvp.Key
        $versionInfo = if ($kvp.Value) { ">= $($kvp.Value)" } else { "(any)" }
        Write-BuildMessage -Type Detail -Message "$cleanName $versionInfo"
    }
}

if ($packageMap.Count -eq 0) {
    Write-BuildMessage -Type Success -Message 'No symbol packages required'
    Write-Manifest -Path $manifestPath -AppJson $appJson -Packages ([ordered]@{}) -Feeds @()
    exit 0
}

$feeds = $DefaultFeeds

if ($feeds.Count -eq 0) {
    throw 'No symbol feeds configured. Update script defaults.'
}

$downloadsRequired = $false
$resolvedPackages = [ordered]@{}
$processedPackages = @{}
$requiredMinimums = @{}
<# Track origin of each minimum version so we can explain why it exists.
   Structure: $minimumOrigins[packageId] = @(
       [pscustomobject]@{ Source = 'AppJson|Dependency:<parentPackage>'; Version = 'x.y.z.w'; Reason = 'initial|propagated|raised' }
   )
 #>
$minimumOrigins = @{}
$script:packageMetadataCache = @{}
$script:packageDependenciesCache = @{}
$queue = [System.Collections.Generic.Queue[string]]::new()
$packagesInQueue = @{}
$downloadSectionShown = $false

foreach ($kvp in $packageMap.GetEnumerator()) {
    $packageId = $kvp.Key
    $minimumVersion = if ($kvp.Value) { [string]$kvp.Value } else { $null }
    $requiredMinimums[$packageId] = $minimumVersion
    $queue.Enqueue($packageId)
    $packagesInQueue[$packageId] = $true
    $originList = @()
    $originList += [pscustomobject]@{ Source = 'app.json'; Version = $minimumVersion; Reason = 'initial' }
    $minimumOrigins[$packageId] = $originList
}

while ($queue.Count -gt 0) {
    $packageId = $queue.Dequeue()
    if ($packagesInQueue.ContainsKey($packageId)) { $packagesInQueue.Remove($packageId) | Out-Null }
    $minimumVersion = if ($requiredMinimums.ContainsKey($packageId)) { $requiredMinimums[$packageId] } else { $null }

    $manifestVersion = if ($manifest -and $manifest.packages -and (Test-JsonProperty $manifest.packages $packageId)) { [string]$manifest.packages.$packageId } else { $null }
    $manifestApplication = if ($manifest) { [string]$manifest.application } else { $null }
    $manifestPlatform = if ($manifest) { [string]$manifest.platform } else { $null }
    $cached = Test-PackagePresent -CacheDir $cacheDir -PackageId $packageId -Version $manifestVersion

    $currentVersion = $null
    $alreadyResolved = $false
    $needsDownload = $true
    $knownDependencies = $null

    # Cache is valid if: package exists AND (application+platform match OR both are null)
    $appJsonApplication = if (Test-JsonProperty $appJson 'application') { $appJson.application } else { $null }
    $appJsonPlatform = if (Test-JsonProperty $appJson 'platform') { $appJson.platform } else { $null }
    $cacheValid = $cached -and $manifestVersion -and (
        ([string]$manifestApplication -eq [string]$appJsonApplication -and [string]$manifestPlatform -eq [string]$appJsonPlatform) -or
        (-not $manifestApplication -and -not $appJsonApplication -and -not $manifestPlatform -and -not $appJsonPlatform)
    )

    if ($processedPackages.ContainsKey($packageId)) {
        $currentVersion = $processedPackages[$packageId]
        $alreadyResolved = $true
        if ($script:packageDependenciesCache.ContainsKey($packageId)) {
            $knownDependencies = $script:packageDependenciesCache[$packageId]
        }
    } elseif ($cacheValid) {
        $currentVersion = $manifestVersion
        $alreadyResolved = $true
        if ($script:packageDependenciesCache.ContainsKey($packageId)) {
            $knownDependencies = $script:packageDependenciesCache[$packageId]
        }
    }

    $resolveResult = $null

    if ($alreadyResolved -and (-not $minimumVersion -or (Compare-Version -Left $currentVersion -Right $minimumVersion) -ge 0)) {
        if ($knownDependencies) {
            $metadata = Get-OrAddPackageMetadata -PackageId $packageId -Feeds $feeds -Cache $script:packageMetadataCache
            $maxAvailableVersion = $metadata?.HighestVersion
            $resolveResult = [pscustomobject]@{
                Version = $currentVersion
                MaxAvailableVersion = $maxAvailableVersion
                Dependencies = @($knownDependencies)
            }
            $needsDownload = $false
        } else {
            $needsDownload = $true
        }
    }

    if (-not $resolveResult -and $needsDownload) {
        # Show download section header before first download
        if (-not $downloadSectionShown) {
            Write-BuildHeader 'Symbol Downloads'
            $downloadSectionShown = $true
        }

        try {
            $resolveResult = Resolve-SymbolPackage -PackageId $packageId -MinimumVersion $minimumVersion -Feeds $feeds -CacheDir $cacheDir
        } catch {
            throw "Failed to download package ${packageId}: $($_.Exception.Message)"
        }
        $downloadsRequired = $true
        $currentVersion = $resolveResult.Version
    }

    if (-not $resolveResult) {
        throw "Failed to resolve package ${packageId}."
    }

    $processedPackages[$packageId] = $currentVersion
    $resolvedPackages[$packageId] = $currentVersion

    $maxAvailableVersion = $null
    if (Test-JsonProperty $resolveResult 'MaxAvailableVersion') {
        $maxAvailableVersion = $resolveResult.MaxAvailableVersion
    }

    if ($minimumVersion) {
        if ((Compare-Version -Left $currentVersion -Right $minimumVersion) -lt 0) {
            # Collect warning for structured display later (suppress immediate warning)
            if (-not $script:versionWarnings) { $script:versionWarnings = @{} }
            $script:versionWarnings[$packageId] = @{
                Requested = $minimumVersion
                Resolved = $currentVersion
                Available = $maxAvailableVersion
                Reason = 'Version conflict resolved automatically'
            }
        }

        if ($maxAvailableVersion -and (Compare-Version -Left $maxAvailableVersion -Right $minimumVersion) -lt 0) {
            $requiredMinimums[$packageId] = $maxAvailableVersion
            # Adjustment details captured in warning collection above
        } elseif ((Compare-Version -Left $currentVersion -Right $minimumVersion) -lt 0) {
            $requiredMinimums[$packageId] = $currentVersion
            # Adjustment details captured in warning collection above
        }
    }

    # Track package resolution for summary
    $existing = $script:summaryRows | Where-Object { $_.Package -eq $packageId } | Select-Object -First 1
    $warnFlag = ($minimumVersion -and (Compare-Version -Left $currentVersion -Right $minimumVersion) -lt 0) ? 'Y' : ''
    if ($existing) {
        $existing.Resolved = $currentVersion
        $existing.MinReq = $(if ($minimumVersion) { $minimumVersion } else { '' })
        $existing.MaxAvail = $(if ($maxAvailableVersion) { $maxAvailableVersion } else { '' })
        if ($warnFlag -eq 'Y') { $existing.Warn = 'Y' }
    } else {
        $script:summaryRows.Add([pscustomobject]@{
            Package = $packageId
            Resolved = $currentVersion
            MinReq = $(if ($minimumVersion) { $minimumVersion } else { '' })
            MaxAvail = $(if ($maxAvailableVersion) { $maxAvailableVersion } else { '' })
            Warn = $warnFlag
        }) | Out-Null
    }

    foreach ($dependency in $resolveResult.Dependencies) {
        $depId = [string]$dependency.Id
        if (-not $depId) { continue }
        $depMinimum = $dependency.MinimumVersion

        $existingMinimum = $null
        if ($requiredMinimums.ContainsKey($depId)) { $existingMinimum = $requiredMinimums[$depId] }

        $updated = $false
        if ($depMinimum) {
            if ($requiredMinimums.ContainsKey($depId)) {
                if (-not $existingMinimum -or (Compare-Version -Left $depMinimum -Right $existingMinimum) -gt 0) {
                    $requiredMinimums[$depId] = $depMinimum
                    $updated = $true
                }
            } else {
                $requiredMinimums[$depId] = $depMinimum
                $updated = $true
            }
        } elseif (-not $requiredMinimums.ContainsKey($depId)) {
            $requiredMinimums[$depId] = $null
            $updated = $true
        }

        # Track dependency edges for analysis
        $edgeMin = $(if ($requiredMinimums[$depId]) { $requiredMinimums[$depId] } else { '' })
        $script:raiseRows.Add([pscustomobject]@{
            Parent = $packageId
            Child  = $depId
            Min    = $edgeMin
            Raised = $(if ($updated) { 'Y' } else { '' })
        }) | Out-Null

        if ($updated) {
            if (-not $minimumOrigins.ContainsKey($depId)) { $minimumOrigins[$depId] = @() }
            $minimumOrigins[$depId] += [pscustomobject]@{ Source = "dependency:$packageId"; Version = $requiredMinimums[$depId]; Reason = ($depMinimum ? 'propagated' : 'introduced') }
        }

        $needsProcessing = $false
        if (-not $processedPackages.ContainsKey($depId)) {
            $needsProcessing = $true
        } elseif ($depMinimum -and (Compare-Version -Left $processedPackages[$depId] -Right $depMinimum) -lt 0) {
            [void]$processedPackages.Remove($depId)
            if ($resolvedPackages.Contains($depId)) {
                [void]$resolvedPackages.Remove($depId)
            }
            $needsProcessing = $true
        }

        if ($needsProcessing -and -not $packagesInQueue.ContainsKey($depId)) {
            $queue.Enqueue($depId)
            $packagesInQueue[$depId] = $true
        }
    }
}

Write-BuildHeader 'Package Summary'

$warningCount = @($script:summaryRows | Where-Object { $_.Warn -eq 'Y' }).Count
$successCount = $script:summaryRows.Count - $warningCount
Write-BuildMessage -Type Info -Message "$successCount packages resolved successfully, $warningCount conflicts resolved"

# Show warning packages first
$warningPackages = @($script:summaryRows | Where-Object { $_.Warn -eq 'Y' } | Sort-Object Package)
if ($warningPackages.Count -gt 0) {
    Write-BuildMessage -Type Warning -Message "Version conflicts detected (resolved automatically)"
    foreach ($r in $warningPackages) {
        $cleanName = Get-CleanPackageName -PackageId $r.Package
        Write-BuildMessage -Type Detail -Message "$cleanName - Resolved: $($r.Resolved), Required: $($r.MinReq), Available: $($r.MaxAvail)"
    }
}

# Full package summary
Write-BuildMessage -Type Step -Message "Package resolution details:"
foreach ($r in ($script:summaryRows | Sort-Object @{Expression={$_.Warn -eq 'Y'}; Descending=$true}, Package)) {
    $cleanName = Get-CleanPackageName -PackageId $r.Package
    $status = if ($r.Warn -eq 'Y') { 'Conflict' } else { 'OK' }
    Write-BuildMessage -Type Detail -Message "$cleanName - Resolved: $($r.Resolved) ($status)"
}

# VERSION RESOLUTION ANALYSIS
if ($script:versionWarnings -and $script:versionWarnings.Count -gt 0) {
    Write-BuildHeader 'Version Resolution Analysis'
    Write-BuildMessage -Type Info -Message "$($script:versionWarnings.Count) conflicts analyzed"

    foreach ($pkg in ($script:versionWarnings.Keys | Sort-Object)) {
        $w = $script:versionWarnings[$pkg]
        $cleanName = Get-CleanPackageName -PackageId $pkg
        Write-BuildMessage -Type Warning -Message "Conflict: $cleanName"
        Write-BuildMessage -Type Detail -Message "Requested: $($w.Requested) (from dependency chain)"
        Write-BuildMessage -Type Detail -Message "Available: $($w.Available) (best version on feed)"
        Write-BuildMessage -Type Detail -Message "Resolved: $($w.Resolved) (build compatible)"

        # Show which dependencies are causing this requirement
        $origins = $minimumOrigins[$pkg]
        if ($origins) {
            $dependencyOrigins = @($origins | Where-Object { $_.Source -like 'dependency:*' })
            if ($dependencyOrigins.Count -gt 0) {
                foreach ($origin in ($dependencyOrigins | Select-Object -First 3)) {
                    $sourcePkg = $origin.Source -replace 'dependency:', ''
                    $sourcePkgClean = Get-CleanPackageName -PackageId $sourcePkg
                    Write-BuildMessage -Type Detail -Message "Triggered by: $sourcePkgClean"
                }
            }
        }
    }

    Write-BuildMessage -Type Success -Message "All conflicts resolved automatically - build will work correctly"
}

# DEPENDENCY ANALYSIS
$raiseCount = @($script:raiseRows | Where-Object { $_.Raised -eq 'Y' }).Count
$totalDependencies = $script:raiseRows.Count
if ($raiseCount -gt 0) {
    Write-BuildHeader 'Dependency Analysis'
    Write-BuildMessage -Type Info -Message "$raiseCount version raises detected (out of $totalDependencies total dependencies)"

    $actualRaises = @($script:raiseRows | Where-Object { $_.Raised -eq 'Y' } | Sort-Object Parent, Child)
    foreach ($d in $actualRaises) {
        $pClean = Get-CleanPackageName -PackageId $d.Parent
        $cClean = Get-CleanPackageName -PackageId $d.Child
        Write-BuildMessage -Type Detail -Message "$pClean → $cClean (Min: $($d.Min))"
    }
}

# VERSION REQUIREMENT ORIGINS
Write-BuildHeader 'Version Requirement Origins'
Write-BuildMessage -Type Info -Message "$($requiredMinimums.Keys.Count) packages analyzed"

# Group packages by origin type
$initialRequirements = @()
$dependencyRequirements = @()

foreach ($pkg in ($requiredMinimums.Keys | Sort-Object)) {
    $finalMin = $requiredMinimums[$pkg]
    $origList = $minimumOrigins[$pkg]
    if (-not $origList) { $origList = @() }

    $hasInitial = @($origList | Where-Object { $_.Source -eq 'app.json' })
    $hasDependencies = @($origList | Where-Object { $_.Source -like 'dependency:*' })

    if ($hasInitial.Count -gt 0) {
        $initialRequirements += [pscustomobject]@{
            Package = $pkg
            Version = $finalMin
            Sources = $origList
        }
    }

    if ($hasDependencies.Count -gt 0) {
        $dependencyRequirements += [pscustomobject]@{
            Package = $pkg
            Version = $finalMin
            Sources = $origList
        }
    }
}

# Show initial requirements
if ($initialRequirements.Count -gt 0) {
    Write-BuildMessage -Type Step -Message "Initial requirements (from app.json):"
    foreach ($req in $initialRequirements) {
        $cleanName = Get-CleanPackageName -PackageId $req.Package
        Write-BuildMessage -Type Detail -Message "$cleanName → $($req.Version)"
    }
}

# Show dependency-driven requirements
if ($dependencyRequirements.Count -gt 0) {
    Write-BuildMessage -Type Step -Message "Dependency-driven requirements:"
    foreach ($req in ($dependencyRequirements | Sort-Object Package)) {
        $cleanName = Get-CleanPackageName -PackageId $req.Package
        Write-BuildMessage -Type Detail -Message "$cleanName → $($req.Version)"

        # Show unique dependency sources
        $dependencySources = @($req.Sources | Where-Object { $_.Source -like 'dependency:*' } |
            ForEach-Object { $_.Source -replace 'dependency:', '' } |
            Sort-Object -Unique | Select-Object -First 3)

        foreach ($source in $dependencySources) {
            $sourceClean = Get-CleanPackageName -PackageId $source
            Write-BuildMessage -Type Detail -Message "  ← $sourceClean"
        }
    }
}

Write-BuildHeader 'Summary'

$totalElapsed = New-TimeSpan -Start $script:StartTime -End (Get-Date)
$elapsedFormatted = "{0:mm\:ss}" -f $totalElapsed

if (-not $downloadsRequired) {
    Write-BuildMessage -Type Success -Message "Symbol cache already up to date! (Elapsed: $elapsedFormatted)"
} else {
    Write-BuildMessage -Type Success -Message "Symbol cache updated successfully! (Elapsed: $elapsedFormatted)"
}

$successCount = @($script:summaryRows | Where-Object { $_.Warn -ne 'Y' }).Count
$warningCount = @($script:summaryRows | Where-Object { $_.Warn -eq 'Y' }).Count
$totalCount = $script:summaryRows.Count

if ($warningCount -eq 0) {
    Write-BuildMessage -Type Success -Message "Ready for build: All $totalCount packages resolved successfully"
} else {
    Write-BuildMessage -Type Info -Message "Ready for build: $successCount packages OK, $warningCount version conflicts resolved (using best available)"
}

Write-Manifest -Path $manifestPath -AppJson $appJson -Packages $resolvedPackages -Feeds $feeds

exit 0
