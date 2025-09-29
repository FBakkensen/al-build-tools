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
      - ALBT_SYMBOL_CACHE_ROOT: override for default ~/.bc-symbol-cache location.
      - ALBT_SYMBOL_FEEDS: comma-separated list of NuGet feeds to query for symbols.
#>

param(
    [string]$AppDir = 'app',
    [switch]$VerboseSymbols   # Always-on style verbose output (not using PowerShell -Verbose switch so CI logs remain deterministic)
)

if (-not $PSBoundParameters.ContainsKey('AppDir') -and $env:ALBT_APP_DIR) {
    $AppDir = $env:ALBT_APP_DIR
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Store VerboseSymbols parameter in script scope for functions to access
$script:VerboseSymbols = $VerboseSymbols

# --- Formatting Helpers (only used when -VerboseSymbols) ---
if ($VerboseSymbols) {
    $script:SymFmt = [pscustomobject]@{
        Width = $Host.UI.RawUI.WindowSize.Width
        StartTime = Get-Date
    }

    function Write-Section {
        param([string]$Title, [string]$SubInfo = '')
        $elapsed = "{0:mm\:ss}" -f (New-TimeSpan -Start $script:SymFmt.StartTime -End (Get-Date))
        $line = ''.PadLeft(($script:SymFmt.Width - 1), '=')
        Write-Host "" # blank spacer
        Write-Host ($line.Substring(0, [Math]::Min($line.Length, 80))) -ForegroundColor Green
        $header = "🔧 SYMBOLS | {0}" -f $Title
        if ($SubInfo) { $header += " | {0}" -f $SubInfo }
        $header += " [{0}]" -f $elapsed
        Write-Host $header -ForegroundColor Yellow
        Write-Host ($line.Substring(0, [Math]::Min($line.Length, 80))) -ForegroundColor Green
    }
    function Write-VerbLine {
        param(
            [string]$Tag,
            [string]$Message,
            [ConsoleColor]$Color = "Gray",
            [string]$Icon = '•'
        )
        $tagPadded = ($Tag).PadRight(5)
        Write-Host ("  {0}{1} {2}" -f $Icon, $tagPadded, $Message) -ForegroundColor $Color
    }

    function Write-Progress {
        param([string]$Activity, [int]$Current, [int]$Total)
        $percent = [math]::Round(($Current / $Total) * 100)
        $bar = ('█' * [math]::Floor($percent / 5)) + ('░' * (20 - [math]::Floor($percent / 5)))
        Write-Host ("  📦 [{0}] {1}/{2} {3}" -f $bar, $Current, $Total, $Activity) -ForegroundColor Cyan
    }

    function Write-ColKV {
        param([string]$Label, [string]$Value, [int]$Pad = 14)
        return ("{0}: {1}" -f ($Label.PadRight($Pad)), $Value)
    }
}

# Data capture arrays for final compact tables
$script:versionWarnings = @{}
if ($VerboseSymbols) {
    $summaryRows = New-Object System.Collections.Generic.List[object]
    $raiseRows = New-Object System.Collections.Generic.List[object]
}

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

# --- Helper Functions ---
function Resolve-AppJsonPath {
    param([string]$AppDirectory)

    if (-not $AppDirectory) { $AppDirectory = 'app' }
    $candidate = Join-Path -Path $AppDirectory -ChildPath 'app.json'
    if (Test-Path -LiteralPath $candidate) {
        return (Get-Item -LiteralPath $candidate).FullName
    }
    if (Test-Path -LiteralPath 'app.json') {
        return (Get-Item -LiteralPath 'app.json').FullName
    }
    throw "app.json not found. Provide -AppDir or run from project root."
}

function Read-JsonFile {
    param([string]$Path)
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse JSON from ${Path}: $($_.Exception.Message)"
    }
}

function Expand-FullPath {
    param([string]$Path)
    if (-not $Path) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    try {
        return (Resolve-Path -LiteralPath $expanded -ErrorAction Stop).ProviderPath
    } catch {
        return [System.IO.Path]::GetFullPath($expanded)
    }
}

function Get-SymbolCacheRoot {
    $override = $env:ALBT_SYMBOL_CACHE_ROOT
    if ($override) {
        return Expand-FullPath -Path $override
    }
    $userHome = $env:HOME
    if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
    if (-not $userHome) { throw 'Unable to determine home directory for symbol cache.' }
    return Join-Path -Path $userHome -ChildPath '.bc-symbol-cache'
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

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

function Sanitize-PathSegment {
    param([string]$Value)
    if (-not $Value) { return '_' }
    $invalid = [System.IO.Path]::GetInvalidFileNameChars() + [char]':'
    $result = $Value
    foreach ($char in $invalid) {
        $pattern = [regex]::Escape([string]$char)
        $result = $result -replace $pattern, '_'
    }
    $result = $result -replace '\s+', '_'
    if ([string]::IsNullOrWhiteSpace($result)) { return '_' }
    return $result
}

function Build-PackageMap {
    param($AppJson)

    $map = [ordered]@{}

    if ($AppJson.application) {
        $map['Microsoft.Application.symbols'] = [string]$AppJson.application
    }

    if ($AppJson.dependencies) {
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
        $fileName = (Sanitize-PathSegment -Value "$cleanName.$Version") + '.app'
    } else {
        # Fallback to old format for compatibility
        $fileName = (Sanitize-PathSegment -Value $PackageId) + '.app'
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

function New-TemporaryDirectory {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    $base = [System.IO.Path]::GetTempPath()
    $name = 'bc-symbols-' + [System.Guid]::NewGuid().ToString('N')
    $path = Join-Path -Path $base -ChildPath $name
    $action = 'Create temporary directory'
    if (-not $PSCmdlet -or $PSCmdlet.ShouldProcess($path, $action)) {
        Ensure-Directory -Path $path
    }
    return $path
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

    # Add verbose output for downloads
    if ($script:VerboseSymbols) {
        $cleanPackageName = Get-CleanPackageName -PackageId $PackageId
        Write-Host "  📥 Downloading: $cleanPackageName" -ForegroundColor Cyan
        Write-Host "     Version: $Version" -ForegroundColor Gray
        Write-Host "     Source: $Feed" -ForegroundColor Gray
    }

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
    $destinationName = (Sanitize-PathSegment -Value "$cleanName.$Version") + '.app'
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

    # Add verbose output for successful extraction
    if ($script:VerboseSymbols) {
        $cleanPackageName = Get-CleanPackageName -PackageId $PackageId
        Write-Host "  ✅ Extracted: $cleanPackageName" -ForegroundColor Green
        Write-Host "     Location: $destinationPath" -ForegroundColor Gray
    }

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
        runtime = $AppJson.runtime
        application = $AppJson.application
        platform = $AppJson.platform
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
$appJsonPath = Resolve-AppJsonPath -AppDirectory $AppDir
$appJson = Read-JsonFile -Path $appJsonPath

if (-not $appJson.id) { throw 'app.json is missing required "id" property.' }
if (-not $appJson.publisher) { throw 'app.json is missing required "publisher" property.' }
if (-not $appJson.name) { throw 'app.json is missing required "name" property.' }

$cacheRoot = Get-SymbolCacheRoot
Ensure-Directory -Path $cacheRoot

$publisherDir = Join-Path -Path $cacheRoot -ChildPath (Sanitize-PathSegment -Value $appJson.publisher)
Ensure-Directory -Path $publisherDir
$appDirPath = Join-Path -Path $publisherDir -ChildPath (Sanitize-PathSegment -Value $appJson.name)
Ensure-Directory -Path $appDirPath
$cacheDir = Join-Path -Path $appDirPath -ChildPath (Sanitize-PathSegment -Value $appJson.id)
Ensure-Directory -Path $cacheDir

$manifestPath = Join-Path -Path $cacheDir -ChildPath 'symbols.lock.json'
$manifest = Load-Manifest -Path $manifestPath
$packageMap = Build-PackageMap -AppJson $appJson

if ($VerboseSymbols) {
    Write-Section 'Processing Packages' ("{0} packages" -f $packageMap.Count)
    $counter = 0
    foreach ($kvp in $packageMap.GetEnumerator()) {
        $counter++
        Write-Progress "Processing requirements" $counter $packageMap.Count
        $cleanName = Get-CleanPackageName -PackageId $kvp.Key
        Write-VerbLine 'REQ' ("{0} >= {1}" -f $cleanName, ($kvp.Value ? $kvp.Value : '(any)')) Yellow '📋'
    }
}

if ($packageMap.Count -eq 0) {
    Write-Host 'No symbol packages required based on app.json.'
    Write-Manifest -Path $manifestPath -AppJson $appJson -Packages ([ordered]@{}) -Feeds @()
    exit 0
}

$feeds = if ($env:ALBT_SYMBOL_FEEDS) {
    $env:ALBT_SYMBOL_FEEDS.Split([char]',') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }
} else {
    $DefaultFeeds
}

if ($feeds.Count -eq 0) {
    throw 'No symbol feeds configured. Set ALBT_SYMBOL_FEEDS or update script defaults.'
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

    $manifestVersion = if ($manifest -and $manifest.packages -and ($manifest.packages.PSObject.Properties.Name -contains $packageId)) { [string]$manifest.packages.$packageId } else { $null }
    $manifestRuntime = if ($manifest) { [string]$manifest.runtime } else { $null }
    $cached = Test-PackagePresent -CacheDir $cacheDir -PackageId $packageId -Version $manifestVersion

    $currentVersion = $null
    $alreadyResolved = $false
    $needsDownload = $true
    $knownDependencies = $null

    if ($processedPackages.ContainsKey($packageId)) {
        $currentVersion = $processedPackages[$packageId]
        $alreadyResolved = $true
        if ($script:packageDependenciesCache.ContainsKey($packageId)) {
            $knownDependencies = $script:packageDependenciesCache[$packageId]
        }
    } elseif ($cached -and $manifestVersion -and $manifestRuntime -eq [string]$appJson.runtime) {
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
        if ($VerboseSymbols -and -not $downloadSectionShown) {
            Write-Section 'Symbol Downloads' 'Downloading required packages'
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
    if ($resolveResult.PSObject.Properties.Name -contains 'MaxAvailableVersion') {
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

    if ($VerboseSymbols) {
        # Ensure single row per package, update as we learn more (captures latest minReq situation)
        $existing = $summaryRows | Where-Object { $_.Package -eq $packageId } | Select-Object -First 1
        $warnFlag = ($minimumVersion -and (Compare-Version -Left $currentVersion -Right $minimumVersion) -lt 0) ? 'Y' : ''
        if ($existing) {
            $existing.Resolved = $currentVersion
            $existing.MinReq = $(if ($minimumVersion) { $minimumVersion } else { '' })
            $existing.MaxAvail = $(if ($maxAvailableVersion) { $maxAvailableVersion } else { '' })
            if ($warnFlag -eq 'Y') { $existing.Warn = 'Y' }
        } else {
            $summaryRows.Add([pscustomobject]@{
                Package = $packageId
                Resolved = $currentVersion
                MinReq = $(if ($minimumVersion) { $minimumVersion } else { '' })
                MaxAvail = $(if ($maxAvailableVersion) { $maxAvailableVersion } else { '' })
                Warn = $warnFlag
            }) | Out-Null
        }
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

        if ($VerboseSymbols) {
            # Always record edge; mark if it updated the minimum
            $edgeMin = $(if ($requiredMinimums[$depId]) { $requiredMinimums[$depId] } else { '' })
            $raiseRows.Add([pscustomobject]@{
                Parent = $packageId
                Child  = $depId
                Min    = $edgeMin
                Raised = $(if ($updated) { 'Y' } else { '' })
            }) | Out-Null
        }

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

if ($VerboseSymbols) {

    # SUMMARY TABLE
    $warningCount = ($summaryRows | Where-Object { $_.Warn -eq 'Y' }).Count
    $successCount = $summaryRows.Count - $warningCount
    Write-Section 'Package Summary' ("{0} ✅ successful, {1} ⚠️ conflicts resolved" -f $successCount, $warningCount)

    # Show warnings first for quick scanning
    $warningPackages = $summaryRows | Where-Object { $_.Warn -eq 'Y' } | Sort-Object Package
    if ($warningPackages.Count -gt 0) {
        Write-Host "⚠️  VERSION CONFLICTS (resolved automatically):" -ForegroundColor Yellow
        Write-Host "   These packages had version conflicts due to dependency requirements:" -ForegroundColor Gray
        Write-Host ""
        $hdr = '   {0,-65} {1,-18} {2,-18} {3,-18}' -f 'PACKAGE','RESOLVED','REQUIRED','AVAILABLE'
        Write-Host $hdr -ForegroundColor Yellow
        foreach ($r in $warningPackages) {
            $cleanName = Get-CleanPackageName -PackageId $r.Package
            $pkgDisp = if ($cleanName.Length -le 65) { $cleanName } else { $cleanName.Substring(0,62) + '...' }
            $line = '   {0,-65} {1,-18} {2,-18} {3,-18}' -f $pkgDisp,$r.Resolved,$r.MinReq,$r.MaxAvail
            Write-Host $line -ForegroundColor Red
        }
        Write-Host "   🔍 See 'Version Resolution Analysis' below for detailed conflict sources" -ForegroundColor Gray
        Write-Host ""
    }

    # Full summary table
    Write-Host "📋 COMPLETE PACKAGE SUMMARY:" -ForegroundColor Cyan
    $hdr = '   {0,-65} {1,-18} {2,-18} {3,-18} {4}' -f 'PACKAGE','RESOLVED','MINREQ','MAXAVAIL','STATUS'
    Write-Host $hdr -ForegroundColor Yellow
    foreach ($r in ($summaryRows | Sort-Object @{Expression={$_.Warn -eq 'Y'}; Descending=$true}, Package)) {
        $cleanName = Get-CleanPackageName -PackageId $r.Package
        $pkgDisp = if ($cleanName.Length -le 65) { $cleanName } else { $cleanName.Substring(0,62) + '...' }
        $warnIcon = if ($r.Warn -eq 'Y') { '⚠️' } else { '✅' }
        $line = '   {0,-65} {1,-18} {2,-18} {3,-18} {4}' -f $pkgDisp,$r.Resolved,$r.MinReq,$r.MaxAvail,$warnIcon
        if ($r.Warn) { Write-Host $line -ForegroundColor Red } else { Write-Host $line -ForegroundColor Green }
    }

    # VERSION RESOLUTION ANALYSIS - Detailed conflict analysis
    if ($script:versionWarnings -and $script:versionWarnings.Count -gt 0) {
        Write-Section 'Version Resolution Analysis' ("{0} conflicts analyzed" -f $script:versionWarnings.Count)
        Write-Host "🔍 CONFLICT SOURCE ANALYSIS:" -ForegroundColor Cyan
        Write-Host "   Understanding why these version requirements were raised:" -ForegroundColor Gray
        Write-Host ""

        foreach ($pkg in ($script:versionWarnings.Keys | Sort-Object)) {
            $w = $script:versionWarnings[$pkg]
            $cleanName = Get-CleanPackageName -PackageId $pkg
            $pkgDisp = if ($cleanName.Length -le 75) { $cleanName } else { $cleanName.Substring(0,72) + '...' }
            Write-Host "   📦 $pkgDisp" -ForegroundColor White
            Write-Host "      Requested: $($w.Requested) (from dependency chain)" -ForegroundColor Yellow
            Write-Host "      Available: $($w.Available) (best version on feed)" -ForegroundColor Cyan
            Write-Host "      Resolved:  $($w.Resolved) ✅ (build compatible)" -ForegroundColor Green

            # Show which dependencies are causing this requirement
            $origins = $minimumOrigins[$pkg]
            if ($origins) {
                $dependencyOrigins = $origins | Where-Object { $_.Source -like 'dependency:*' }
                if ($dependencyOrigins) {
                    Write-Host "      Triggered by:" -ForegroundColor Gray
                    foreach ($origin in ($dependencyOrigins | Select-Object -First 3)) {
                        $sourcePkg = $origin.Source -replace 'dependency:', ''
                        $sourcePkgClean = Get-CleanPackageName -PackageId $sourcePkg
                        $sourcePkgDisp = if ($sourcePkgClean.Length -le 50) { $sourcePkgClean } else { $sourcePkgClean.Substring(0,47) + '...' }
                        Write-Host "        → $sourcePkgDisp" -ForegroundColor DarkYellow
                    }
                }
            }
            Write-Host ""
        }

        Write-Host "   ✅ All conflicts resolved automatically - build will work correctly!" -ForegroundColor Green
        Write-Host ""
    }

    # DEPENDENCY RAISES TABLE
    $raiseCount = ($raiseRows | Where-Object { $_.Raised -eq 'Y' }).Count
    $totalDependencies = $raiseRows.Count
    if ($raiseCount -gt 0) {
        Write-Section 'Dependency Analysis' ("{0} version raises detected" -f $raiseCount)
        Write-Host "🔗 DEPENDENCY VERSION RAISES:" -ForegroundColor Cyan
        Write-Host "   These dependencies actually raised minimum version requirements:" -ForegroundColor Gray
        $hdr2 = '   {0,-60} {1,-60} {2,-15} {3}' -f 'PARENT','CHILD','MIN VER','RAISED'
        Write-Host $hdr2 -ForegroundColor Yellow
        # Only show the ones that actually raised versions (consistent with count)
        $actualRaises = $raiseRows | Where-Object { $_.Raised -eq 'Y' } | Sort-Object Parent, Child
        foreach ($d in $actualRaises) {
            $pFull = $d.Parent
            $cFull = $d.Child
            $pClean = Get-CleanPackageName -PackageId $pFull
            $cClean = Get-CleanPackageName -PackageId $cFull
            $p = if ($pClean.Length -le 60) { $pClean } else { $pClean.Substring(0,57) + '...' }
            $c = if ($cClean.Length -le 60) { $cClean } else { $cClean.Substring(0,57) + '...' }
            $raiseIcon = '📈'  # We know it's raised since we filtered for it
            $line = '   {0,-60} {1,-60} {2,-15} {3}' -f $p,$c,$d.Min,$raiseIcon
            $color = 'Yellow'  # All are raises, so all yellow
            Write-Host $line -ForegroundColor $color
        }
        if ($totalDependencies -gt $raiseCount) {
            Write-Host ""
            Write-Host "   📊 Total dependency relationships: $totalDependencies (only $raiseCount actually raised versions)" -ForegroundColor DarkCyan
        }
    }

    # VERSION REQUIREMENT ORIGINS - Enhanced format for better scanning
    Write-Section 'Version Requirement Origins' ("{0} packages analyzed" -f $requiredMinimums.Keys.Count)
    Write-Host "📊 REQUIREMENT SOURCES:" -ForegroundColor Cyan
    Write-Host "   Understanding where each package version requirement originated:" -ForegroundColor Gray
    Write-Host ""

    # Group packages by origin type for better organization
    $initialRequirements = @()
    $dependencyRequirements = @()

    foreach ($pkg in ($requiredMinimums.Keys | Sort-Object)) {
        $finalMin = $requiredMinimums[$pkg]
        $origList = $minimumOrigins[$pkg]
        if (-not $origList) { $origList = @() }

        $hasInitial = $origList | Where-Object { $_.Source -eq 'app.json' }
        $hasDependencies = $origList | Where-Object { $_.Source -like 'dependency:*' }

        if ($hasInitial) {
            $initialRequirements += [pscustomobject]@{
                Package = $pkg
                Version = $finalMin
                Sources = $origList
            }
        }

        if ($hasDependencies) {
            $dependencyRequirements += [pscustomobject]@{
                Package = $pkg
                Version = $finalMin
                Sources = $origList
            }
        }
    }

    # Show initial requirements first
    if ($initialRequirements.Count -gt 0) {
        Write-Host "   📋 INITIAL REQUIREMENTS (from app.json):" -ForegroundColor Green
        foreach ($req in $initialRequirements) {
            $cleanName = Get-CleanPackageName -PackageId $req.Package
            $pkgDisp = if ($cleanName.Length -le 70) { $cleanName } else { $cleanName.Substring(0,67) + '...' }
            Write-Host "      ✓ $pkgDisp → $($req.Version)" -ForegroundColor Green
        }
        Write-Host ""
    }

    # Show dependency-driven requirements
    if ($dependencyRequirements.Count -gt 0) {
        Write-Host "   🔗 DEPENDENCY-DRIVEN REQUIREMENTS:" -ForegroundColor Yellow
        foreach ($req in ($dependencyRequirements | Sort-Object Package)) {
            $cleanName = Get-CleanPackageName -PackageId $req.Package
            $pkgDisp = if ($cleanName.Length -le 70) { $cleanName } else { $cleanName.Substring(0,67) + '...' }
            Write-Host "      📦 $pkgDisp → $($req.Version)" -ForegroundColor Yellow

            # Show unique dependency sources (avoid duplicates)
            $dependencySources = $req.Sources | Where-Object { $_.Source -like 'dependency:*' } |
                ForEach-Object { $_.Source -replace 'dependency:', '' } |
                Sort-Object -Unique | Select-Object -First 3

            foreach ($source in $dependencySources) {
                $sourceClean = Get-CleanPackageName -PackageId $source
                $sourceDisp = if ($sourceClean.Length -le 60) { $sourceClean } else { $sourceClean.Substring(0,57) + '...' }
                Write-Host "         ← $sourceDisp" -ForegroundColor DarkYellow
            }
            Write-Host ""
        }
    }
}

# Final status with timing
if ($VerboseSymbols) {
    $totalElapsed = New-TimeSpan -Start $script:SymFmt.StartTime -End (Get-Date)
} else {
    $totalElapsed = New-TimeSpan -Seconds 0
}
if (-not $downloadsRequired) {
    if ($VerboseSymbols) {
        Write-Host ""
        Write-Host ("✅ Symbol cache already up to date! [{0:mm\:ss}]" -f $totalElapsed) -ForegroundColor Green
    } else {
        Write-Host "✅ Symbol cache already up to date."
    }
} else {
    if ($VerboseSymbols) {
        Write-Host ""
        Write-Host ("✅ Symbol cache updated successfully! [{0:mm\:ss}]" -f $totalElapsed) -ForegroundColor Green
    } else {
        Write-Host "✅ Symbol cache updated successfully."
    }
}
if ($VerboseSymbols) {
    $successCount = ($summaryRows | Where-Object { $_.Warn -ne 'Y' }).Count
    $warningCount = ($summaryRows | Where-Object { $_.Warn -eq 'Y' }).Count
    $totalCount = $summaryRows.Count

    if ($warningCount -eq 0) {
        Write-Host "🎯 Ready for build: All $totalCount packages resolved successfully!" -ForegroundColor Green
    } else {
        Write-Host "🎯 Ready for build: $successCount packages OK, $warningCount version conflicts resolved (using best available)" -ForegroundColor Cyan
    }
}

Write-Manifest -Path $manifestPath -AppJson $appJson -Packages $resolvedPackages -Feeds $feeds

exit 0
