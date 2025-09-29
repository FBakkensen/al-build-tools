#requires -Version 7.2

<#
.SYNOPSIS
    Install or update the AL compiler dotnet tool with structured status reporting.

.DESCRIPTION
    Ensures the AL compiler dotnet tool is installed for the runtime declared in app.json.
    Parses app.json to determine the runtime, maintains a sentinel under ~/.bc-tool-cache/al,
    and installs/updates the Microsoft.Dynamics.BusinessCentral.Development.Tools dotnet tool
    when the runtime increases, the sentinel is missing, or the compiler binaries are absent.
    Also downloads the BusinessCentral.LinterCop analyzer.

.PARAMETER AppDir
    Directory that contains app.json (defaults to "app" like build.ps1). You can also set
    ALBT_APP_DIR to override when the parameter is omitted.

.NOTES
    Optional environment variables:
      - AL_TOOL_VERSION: explicit version passed through make to select a tool version.
      - ALBT_TOOL_CACHE_ROOT: override for the default ~/.bc-tool-cache location.
      - ALBT_APP_DIR: override for default app directory when -AppDir omitted.
      - ALBT_FORCE_LINTERCOP: set to 1/true/yes/on to force re-download of BusinessCentral.LinterCop analyzer.
      - ALBT_RUNTIME_VERSION: override runtime version from app.json for compiler selection.

    This script uses Write-Information for output to ensure compatibility with different
    PowerShell hosts and automation scenarios.
#>

# PSScriptAnalyzer suppressions for intentional design choices
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM is preferred for cross-platform compatibility')]

#[CmdletBinding()]
param(
    [string]$AppDir = 'app'
)

if (-not $PSBoundParameters.ContainsKey('AppDir') -and $env:ALBT_APP_DIR) {
    $AppDir = $env:ALBT_APP_DIR
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# --- Formatting Helpers ---
function Write-Section {
    param([string]$Title, [string]$SubInfo = '')
    $line = ''.PadLeft(80, '=')
    Write-Information "" # blank spacer
    Write-Information $line -InformationAction Continue
    $header = "🔧 COMPILER | {0}" -f $Title
    if ($SubInfo) { $header += " | {0}" -f $SubInfo }
    Write-Information $header -InformationAction Continue
    Write-Information $line -InformationAction Continue
}

function Write-InfoLine {
    param(
        [string]$Label,
        [string]$Value,
        [string]$Icon = '•'
    )
    $labelPadded = ($Label).PadRight(14)
    Write-Information ("  {0}{1}: {2}" -f $Icon, $labelPadded, $Value) -InformationAction Continue
}

function Write-StatusLine {
    param([string]$Message, [string]$Icon = '⚠️')
    Write-Information ("  {0} {1}" -f $Icon, $Message) -InformationAction Continue
}

function Write-Activity {
    param([string]$Activity, [string]$Status = '', [string]$Icon = '⏳')
    if ($Status) {
        Write-Information ("  {0} {1}: {2}" -f $Icon, $Activity, $Status) -InformationAction Continue
    } else {
        Write-Information ("  {0} {1}" -f $Icon, $Activity) -InformationAction Continue
    }
}

# --- Constants ---
$ToolExecutableNames = @('alc.exe', 'alc')

# --- Enhanced Runtime-Based Selection Functions ---
function Get-RuntimeMajorVersion {
    <#
    .SYNOPSIS
        Extract major version from runtime version string
    .PARAMETER RuntimeVersion
        Runtime version string from app.json (e.g., "15.2", "16.0")
    .OUTPUTS
        String containing major version number or $null if invalid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$RuntimeVersion
    )

    if ([string]::IsNullOrWhiteSpace($RuntimeVersion)) {
        return $null
    }

    # Extract major version from runtime (e.g., "15.2" -> "15")
    if ($RuntimeVersion -match '^(\d+)\.') {
        return $matches[1]
    }

    # Handle single digit versions like "15"
    if ($RuntimeVersion -match '^\d+$') {
        return $RuntimeVersion
    }

    return $null
}


function Get-NuGetPackageVersions {
    <#
    .SYNOPSIS
        Query NuGet API for available package versions with retry logic
    .PARAMETER PackageId
        NuGet package identifier
    .PARAMETER MajorVersion
        Optional major version filter
    .PARAMETER UseCache
        Whether to use cached results if available (default: true)
    .OUTPUTS
        Array of version strings sorted descending
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId,

        [Parameter(Mandatory=$false)]
        [string]$MajorVersion,

        [Parameter(Mandatory=$false)]
        [bool]$UseCache = $true
    )

    # Check cache first if enabled
    if ($UseCache) {
        $cacheKey = "${PackageId}:${MajorVersion}"
        $cachedResult = Get-CachedApiResponse -Key $cacheKey
        if ($cachedResult) {
            Write-Verbose "Using cached versions for $PackageId"
            return $cachedResult
        }
    }

    $apiUrl = "https://api.nuget.org/v3-flatcontainer/$($PackageId.ToLower())/index.json"

    try {
        Write-Verbose "Querying NuGet API: $apiUrl"
        $response = Invoke-ApiRequestWithRetry -Uri $apiUrl -ProgressActivity "NuGet API Query"

        if (-not $response -or -not $response.versions) {
            Write-Warning "Invalid API response from NuGet for package $PackageId"
            return @()
        }

        $versions = $response.versions

        if ($MajorVersion) {
            $pattern = "^$MajorVersion\.\d+\.\d+.*-beta$"
            $versions = $versions | Where-Object { $_ -match $pattern }
            Write-Verbose "Filtered to $($versions.Count) versions for major version $MajorVersion"
        }

        # Filter out versions below 15.2 that have analyzer dependency issues
        if ($MajorVersion -eq "15") {
            Write-Verbose "Filtering AL compiler versions to 15.2+ for analyzer compatibility"
            $versions = $versions | Where-Object {
                $version = [version]($_ -replace '-.*$', '')
                $version.Major -gt 15 -or ($version.Major -eq 15 -and $version.Minor -ge 2)
            }
            Write-Verbose "Filtered to $($versions.Count) versions 15.2+ for analyzer compatibility"
        }

        # Sort by semantic version (descending)
        $sortedVersions = $versions | Sort-Object { [version]($_ -replace '-.*$', '') } -Descending

        # Cache the result
        if ($UseCache -and $sortedVersions) {
            $cacheKey = "${PackageId}:${MajorVersion}"
            Set-CachedApiResponse -Key $cacheKey -Data $sortedVersions -ExpirationHours 1
        }

        return $sortedVersions
    } catch {
        Write-Warning "Failed to query NuGet API for $PackageId : $($_.Exception.Message)"

        # Try to return cached result as fallback
        if ($UseCache) {
            $cacheKey = "${PackageId}:${MajorVersion}"
            $fallbackResult = Get-CachedApiResponse -Key $cacheKey -IgnoreExpiration
            if ($fallbackResult) {
                Write-Warning "Using stale cached versions as fallback for $PackageId"
                return $fallbackResult
            }
        }

        return @()
    }
}

function Select-BestCompilerVersion {
    <#
    .SYNOPSIS
        Select optimal compiler version based on runtime compatibility
    .PARAMETER RuntimeVersion
        Runtime version from app.json
    .PARAMETER RequestedVersion
        Explicitly requested version (highest priority)
    .PARAMETER PackageId
        NuGet package identifier
    .OUTPUTS
        String containing selected version or $null if none available
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$RuntimeVersion,

        [Parameter(Mandatory=$false)]
        [string]$RequestedVersion,

        [Parameter(Mandatory=$true)]
        [string]$PackageId
    )

    # Priority 1: Explicit version request
    if ($RequestedVersion) {
        Write-Information ("  📌 Using explicitly requested version: {0}" -f $RequestedVersion) -InformationAction Continue
        return $RequestedVersion
    }

    # Priority 2: Runtime-compatible version with analyzer support
    $majorVersion = Get-RuntimeMajorVersion -RuntimeVersion $RuntimeVersion
    if ($majorVersion) {
        Write-Verbose "Searching for versions compatible with runtime major version: $majorVersion"

        # Use AL compiler 16.x minimum for runtime 15.x (analyzer compatibility)
        # Runtime 16.x and 17.x use matching AL compiler versions
        if ($majorVersion -eq "15") {
            Write-Information ("  ℹ️  Runtime $RuntimeVersion detected, using AL compiler 16.x for analyzer compatibility") -InformationAction Continue
            $compatibleVersions = Get-NuGetPackageVersions -PackageId $PackageId -MajorVersion "16"
        } elseif ($majorVersion -eq "17") {
            Write-Information ("  ℹ️  Runtime $RuntimeVersion detected, using known AL compiler 17.x version") -InformationAction Continue
            $compatibleVersions = @("17.0.27.27275-beta")  # Known working version for 17.0
        } else {
            Write-Information ("  ℹ️  Runtime $RuntimeVersion detected, using matching AL compiler $majorVersion.x") -InformationAction Continue
            $compatibleVersions = Get-NuGetPackageVersions -PackageId $PackageId -MajorVersion $majorVersion
        }

        if ($compatibleVersions -and $compatibleVersions.Count -gt 0) {
            Write-Information ("  ✅ Selected runtime-compatible version: {0}" -f $compatibleVersions[0]) -InformationAction Continue
            return $compatibleVersions[0]  # Latest compatible version
        }
        Write-Warning "No compatible versions found for runtime major version $majorVersion"

        # Don't fall back to incompatible versions - this creates logical inconsistencies
        Write-Error "No AL compiler versions compatible with runtime $RuntimeVersion (major version $majorVersion) were found."
        Write-Error "Available options:"
        Write-Error "  1. Use a supported runtime version (15.x, 16.x, 17.x)"
        Write-Error "  2. Check if Business Central runtime $RuntimeVersion is supported"
        Write-Error "  3. Use a generic installation without runtime-specific caching"
        throw "Incompatible AL compiler and runtime version combination"
    }

    # Priority 3: Latest available version (only if no runtime specified)
    if (-not $RuntimeVersion) {
        Write-Verbose "No runtime specified, using latest available version"
        $allVersions = Get-NuGetPackageVersions -PackageId $PackageId
        if ($allVersions -and $allVersions.Count -gt 0) {
            Write-Information ("  ✅ Selected latest available version: {0}" -f $allVersions[0]) -InformationAction Continue
            return $allVersions[0]
        }
    }

    Write-Warning "No suitable compiler version found"
    return $null
}

function Get-RuntimeCacheDirectory {
    <#
    .SYNOPSIS
        Determine cache directory path for specific runtime
    .PARAMETER RuntimeVersion
        Runtime version string
    .PARAMETER CacheRoot
        Base cache directory path
    .OUTPUTS
        Absolute path to runtime-specific cache directory
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$RuntimeVersion,

        [Parameter(Mandatory=$true)]
        [string]$CacheRoot
    )

    $majorVersion = Get-RuntimeMajorVersion -RuntimeVersion $RuntimeVersion
    if ($majorVersion) {
        return Join-Path -Path $CacheRoot -ChildPath "runtime-$majorVersion"
    }

    # Fallback to default directory for legacy compatibility
    return $CacheRoot
}

function Initialize-RuntimeCache {
    <#
    .SYNOPSIS
        Create and initialize runtime-specific cache directory structure
    .PARAMETER RuntimeCacheDir
        Absolute path to runtime-specific cache directory
    .OUTPUTS
        Hashtable with cache directory structure info
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RuntimeCacheDir
    )

    $toolsDir = Join-Path -Path $RuntimeCacheDir -ChildPath 'tools'
    $compilerDir = Join-Path -Path $RuntimeCacheDir -ChildPath 'compiler'

    New-Item -Path $RuntimeCacheDir -ItemType Directory -Force | Out-Null
    New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
    New-Item -Path $compilerDir -ItemType Directory -Force | Out-Null

    return @{
        Root = $RuntimeCacheDir
        Tools = $toolsDir
        Compiler = $compilerDir
    }
}

function Read-SentinelFile {
    <#
    .SYNOPSIS
        Read and parse sentinel metadata file
    .PARAMETER Path
        Path to sentinel.json file
    .OUTPUTS
        Hashtable with sentinel metadata or $null if invalid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        return $content | ConvertFrom-Json -AsHashtable
    } catch {
        Write-Warning "Corrupted sentinel file: $Path - $($_.Exception.Message)"
        return $null
    }
}

function Write-SentinelFile {
    <#
    .SYNOPSIS
        Write sentinel metadata to file
    .PARAMETER Path
        Path to sentinel.json file
    .PARAMETER Metadata
        Hashtable containing sentinel metadata
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [hashtable]$Metadata
    )

    try {
        $json = $Metadata | ConvertTo-Json -Depth 4
        $json | Set-Content -LiteralPath $Path -Encoding UTF8
        Write-Verbose "Sentinel file written: $Path"
    } catch {
        Write-Warning "Failed to write sentinel file: $Path - $($_.Exception.Message)"
        throw
    }
}

function Test-CacheValidity {
    <#
    .SYNOPSIS
        Validate existing cache entry
    .PARAMETER SentinelPath
        Path to sentinel file
    .PARAMETER RequiredVersion
        Optional required compiler version
    .OUTPUTS
        Boolean indicating if cache is valid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SentinelPath,

        [Parameter(Mandatory=$false)]
        [string]$RequiredVersion
    )

    $sentinel = Read-SentinelFile -Path $SentinelPath
    if (-not $sentinel) {
        Write-Verbose "Cache invalid: No sentinel file or corrupted"
        return $false
    }

    # Check required fields
    $requiredFields = @('compilerVersion', 'runtime', 'toolPath', 'timestamp')
    foreach ($field in $requiredFields) {
        if (-not $sentinel.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($sentinel[$field])) {
            Write-Verbose "Cache invalid: Missing required field '$field'"
            return $false
        }
    }

    # Check if compiler executable exists
    if (-not (Test-Path -LiteralPath $sentinel.toolPath)) {
        Write-Verbose "Cache invalid: Compiler executable not found at $($sentinel.toolPath)"
        return $false
    }

    # Check version match if required
    if ($RequiredVersion -and $sentinel.compilerVersion -ne $RequiredVersion) {
        Write-Verbose "Cache invalid: Version mismatch (cached: $($sentinel.compilerVersion), required: $RequiredVersion)"
        return $false
    }

    Write-Verbose "Cache valid: $($sentinel.compilerVersion) at $($sentinel.toolPath)"
    return $true
}

function Import-LegacyInstallation {
    <#
    .SYNOPSIS
        Migrate legacy global installation to runtime-specific cache
    .PARAMETER LegacySentinelPath
        Path to legacy default.json sentinel
    .PARAMETER NewSentinelPath
        Path to new runtime-specific sentinel
    .PARAMETER RuntimeVersion
        Target runtime version
    .OUTPUTS
        Boolean indicating if migration was performed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LegacySentinelPath,

        [Parameter(Mandatory=$true)]
        [string]$NewSentinelPath,

        [Parameter(Mandatory=$true)]
        [string]$RuntimeVersion
    )

    if (-not (Test-Path -LiteralPath $LegacySentinelPath)) {
        return $false
    }

    try {
        $legacySentinel = Read-SentinelFile -Path $LegacySentinelPath
        if (-not $legacySentinel) {
            return $false
        }

        # Verify legacy installation is still valid
        if (-not (Test-Path -LiteralPath $legacySentinel.toolPath)) {
            Write-Verbose "Legacy installation invalid: Tool path not found"
            return $false
        }

        # Create new sentinel with enhanced metadata
        $runtimeMajor = Get-RuntimeMajorVersion -RuntimeVersion $RuntimeVersion
        $newMetadata = @{
            compilerVersion = $legacySentinel.compilerVersion
            runtime = $RuntimeVersion
            runtimeMajor = $runtimeMajor
            toolPath = $legacySentinel.toolPath
            packageId = if ($legacySentinel.ContainsKey('packageId')) { $legacySentinel.packageId } else { Get-ToolPackageId }
            installationType = 'migrated-global'
            timestamp = (Get-Date).ToUniversalTime().ToString('o')
            migratedFrom = $LegacySentinelPath
        }

        Write-SentinelFile -Path $NewSentinelPath -Metadata $newMetadata
        Write-Information ("  🔄 Migrated legacy installation: {0}" -f $legacySentinel.compilerVersion) -InformationAction Continue
        return $true
    } catch {
        Write-Warning "Failed to migrate legacy installation: $($_.Exception.Message)"
        return $false
    }
}

function Get-LocalCompilerPath {
    <#
    .SYNOPSIS
        Get path to installed compiler executable
    .PARAMETER ToolsPath
        Path to dotnet tools directory (not used, kept for compatibility)
    .PARAMETER Version
        Compiler version
    .PARAMETER PackageIds
        Array of package IDs to search
    .OUTPUTS
        Path to compiler executable or $null if not found
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ToolsPath,

        [Parameter(Mandatory=$false)]
        [string]$Version,

        [Parameter(Mandatory=$false)]
        [string[]]$PackageIds
    )

    if (-not $PackageIds -or $PackageIds.Count -eq 0) {
        $PackageIds = @(Get-ToolPackageId)
    }

    # Use global dotnet tools path
    $globalToolsRoot = Get-DotnetRoot
    return Get-CompilerPath -ToolsRoot $globalToolsRoot -ToolVersion $Version -PackageIds $PackageIds
}

function Resolve-CompilerInstallationPlan {
    <#
    .SYNOPSIS
        Analyze current state and determine installation actions needed
    .PARAMETER RuntimeVersion
        Runtime version from app.json
    .PARAMETER RequestedVersion
        Optional explicitly requested version
    .PARAMETER CacheRoot
        Base cache directory path
    .PARAMETER PackageIds
        Array of package IDs to consider
    .OUTPUTS
        Hashtable containing installation plan details
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$RuntimeVersion,

        [Parameter(Mandatory=$false)]
        [string]$RequestedVersion,

        [Parameter(Mandatory=$true)]
        [string]$CacheRoot,

        [Parameter(Mandatory=$true)]
        [string[]]$PackageIds
    )

    # Determine target version
    $packageId = Get-PlatformSpecificPackageId -PackageIds $PackageIds
    $targetVersion = Select-BestCompilerVersion -RuntimeVersion $RuntimeVersion -RequestedVersion $RequestedVersion -PackageId $packageId

    if (-not $targetVersion) {
        return @{
            ShouldInstall = $false
            TargetVersion = $null
            InstallationType = $null
            CacheDirectory = $null
            Reason = @("No suitable compiler version found")
        }
    }

    # Setup runtime-specific cache
    $runtimeCacheDir = Get-RuntimeCacheDirectory -RuntimeVersion $RuntimeVersion -CacheRoot $CacheRoot
    $cacheInfo = Initialize-RuntimeCache -RuntimeCacheDir $runtimeCacheDir
    $sentinelPath = Join-Path $cacheInfo.Root 'sentinel.json'

    # Check existing installation
    $reasons = @()
    $shouldInstall = $false

    if (Test-CacheValidity -SentinelPath $sentinelPath -RequiredVersion $targetVersion) {
        Write-Verbose "Valid cache found for version $targetVersion"
        $shouldInstall = $false
        $reasons += "Valid cached installation found"
    } else {
        $shouldInstall = $true

        # Check for legacy migration opportunity
        $legacyPath = Join-Path (Split-Path $runtimeCacheDir -Parent) 'default.json'
        if (Import-LegacyInstallation -LegacySentinelPath $legacyPath -NewSentinelPath $sentinelPath -RuntimeVersion $RuntimeVersion) {
            # Check if migration satisfied our needs
            if (Test-CacheValidity -SentinelPath $sentinelPath -RequiredVersion $targetVersion) {
                $shouldInstall = $false
                $reasons += "Migrated from legacy installation"
            } else {
                $reasons += "Legacy installation migrated but version mismatch"
            }
        } else {
            $reasons += "No valid cache or migration available"
        }
    }

    return @{
        ShouldInstall = $shouldInstall
        TargetVersion = $targetVersion
        InstallationType = 'local'
        CacheDirectory = $runtimeCacheDir
        SentinelPath = $sentinelPath
        CacheInfo = $cacheInfo
        PackageId = $packageId
        Reason = $reasons
    }
}

function Install-CompilerToLocalPath {
    <#
    .SYNOPSIS
        Install AL compiler using dotnet tool install --global (simplified approach)
    .PARAMETER PackageId
        NuGet package identifier
    .PARAMETER Version
        Compiler version to install
    .PARAMETER ToolsPath
        Local tools installation directory (not used, kept for compatibility)
    .OUTPUTS
        Boolean indicating success
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PackageId,

        [Parameter(Mandatory=$true)]
        [string]$Version,

        [Parameter(Mandatory=$true)]
        [string]$ToolsPath
    )

    try {
        Write-Information ("  📦 Installing {0} version {1}" -f $PackageId, $Version) -InformationAction Continue

        # Use global installation for simplicity and reliability
        $installArgs = @(
            'tool', 'install', '--global',
            $PackageId,
            '--version', $Version
        )

        Write-Verbose "Executing: dotnet $($installArgs -join ' ')"
        & dotnet @installArgs

        if ($LASTEXITCODE -ne 0) {
            # Try update if install fails (tool might already exist)
            $updateArgs = @(
                'tool', 'update', '--global',
                $PackageId,
                '--version', $Version
            )

            Write-Verbose "Install failed, trying update: dotnet $($updateArgs -join ' ')"
            & dotnet @updateArgs

            if ($LASTEXITCODE -ne 0) {
                throw "dotnet tool install and update both failed with exit code $LASTEXITCODE"
            }
        }

        Write-Information ("  ✅ Successfully installed {0}" -f $Version) -InformationAction Continue
        return $true

    } catch {
        Write-Warning "Failed to install compiler: $($_.Exception.Message)"
        return $false
    }
}

function Get-PlatformSpecificPackageId {
    <#
    .SYNOPSIS
        Get platform-specific package ID for current OS
    .PARAMETER PackageIds
        Array of available package IDs
    .OUTPUTS
        String containing the appropriate package ID for current platform
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$PackageIds
    )

    # Use existing logic from Get-ToolPackageId
    return Get-ToolPackageId
}

function New-LocalToolManifest {
    <#
    .SYNOPSIS
        Create or update local tool manifest with AL compiler version
    .PARAMETER CacheDir
        Cache directory containing .config subdirectory
    .PARAMETER PackageId
        AL compiler package ID
    .PARAMETER Version
        AL compiler version
    .OUTPUTS
        Path to created manifest file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CacheDir,

        [Parameter(Mandatory=$true)]
        [string]$PackageId,

        [Parameter(Mandatory=$true)]
        [string]$Version
    )

    # Ensure cache directory structure exists
    if (-not (Test-Path $CacheDir)) {
        New-Item -Path $CacheDir -ItemType Directory -Force | Out-Null
    }

    $configDir = Join-Path $CacheDir '.config'
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    # Create manifest
    $manifestPath = Join-Path $configDir 'dotnet-tools.json'
    $manifest = @{
        version = 1
        isRoot = $true
        tools = @{
            $PackageId = @{
                version = $Version
                commands = @('al')
            }
        }
    }

    # Save manifest
    $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding UTF8
    Write-InfoLine "Tool Manifest" "Created" '📄'
    Write-InfoLine "Location" $manifestPath '📁'

    return $manifestPath
}

function Install-LocalALCompiler {
    <#
    .SYNOPSIS
        Install AL compiler as local tool to trigger NuGet package download
    .PARAMETER CacheDir
        Cache directory for local tool installation
    .PARAMETER PackageId
        AL compiler package ID
    .PARAMETER Version
        AL compiler version to install
    .OUTPUTS
        Boolean indicating installation success
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CacheDir,

        [Parameter(Mandatory=$true)]
        [string]$PackageId,

        [Parameter(Mandatory=$true)]
        [string]$Version
    )

    try {
        # Create manifest first to enable local tool installation
        $manifestPath = New-LocalToolManifest -CacheDir $CacheDir -PackageId $PackageId -Version $Version

        # Install local tool (this downloads the package to NuGet cache)
        Push-Location $CacheDir
        try {
            Write-Information ("  📦 Installing {0} version {1} as local tool" -f $PackageId, $Version) -InformationAction Continue

            $installArgs = @(
                'tool', 'install',
                '--version', $Version,
                $PackageId
            )

            Write-Verbose "Executing in $CacheDir`: dotnet $($installArgs -join ' ')"
            & dotnet @installArgs

            if ($LASTEXITCODE -ne 0) {
                throw "dotnet tool install failed with exit code $LASTEXITCODE"
            }

            Write-Information ("  ✅ Successfully installed {0} as local tool" -f $Version) -InformationAction Continue
            return $true

        } finally {
            Pop-Location
        }

    } catch {
        Write-Warning "Failed to install local AL compiler: $($_.Exception.Message)"
        return $false
    }
}

function Test-LocalToolInstallation {
    <#
    .SYNOPSIS
        Verify local tool installation is working
    .PARAMETER CacheDir
        Cache directory containing local tool
    .PARAMETER ExpectedVersion
        Expected compiler version
    .OUTPUTS
        Boolean indicating if installation is valid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CacheDir,

        [Parameter(Mandatory=$false)]
        [string]$ExpectedVersion
    )

    try {
        # Check if manifest exists
        $manifestPath = Join-Path (Join-Path $CacheDir '.config') 'dotnet-tools.json'
        if (-not (Test-Path $manifestPath)) {
            Write-Verbose "Tool manifest not found: $manifestPath"
            return $false
        }

        # Verify tool is available
        Push-Location $CacheDir
        try {
            Write-Verbose "Testing local tool availability in: $CacheDir"

            # Check tool list
            $listOutput = & dotnet tool list 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Verbose "dotnet tool list failed: $listOutput"
                return $false
            }

            # Test AL compiler help (quick validation)
            $helpOutput = & dotnet tool run al --help 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Verbose "AL compiler help test failed: $helpOutput"
                return $false
            }

            Write-Verbose "Local tool installation validated successfully"
            return $true

        } finally {
            Pop-Location
        }

    } catch {
        Write-Verbose "Local tool validation failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-CachedMetadata {
    <#
    .SYNOPSIS
        Read cached metadata from sentinel file
    .PARAMETER CacheDir
        Cache directory path
    .OUTPUTS
        Hashtable with cached metadata or $null if not found
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CacheDir
    )

    $sentinelPath = Join-Path $CacheDir 'cache-metadata.json'
    if (-not (Test-Path $sentinelPath)) {
        return $null
    }

    try {
        $content = Get-Content $sentinelPath -Raw -Encoding UTF8
        return $content | ConvertFrom-Json -AsHashtable
    } catch {
        Write-Warning "Corrupted cache metadata: $sentinelPath"
        return $null
    }
}

function Set-CachedMetadata {
    <#
    .SYNOPSIS
        Write cache metadata to sentinel file
    .PARAMETER CacheDir
        Cache directory path
    .PARAMETER Metadata
        Metadata hashtable to save
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CacheDir,

        [Parameter(Mandatory=$true)]
        [hashtable]$Metadata
    )

    $sentinelPath = Join-Path $CacheDir 'cache-metadata.json'

    try {
        $json = $Metadata | ConvertTo-Json -Depth 4
        $json | Set-Content $sentinelPath -Encoding UTF8
        Write-Verbose "Cache metadata written: $sentinelPath"
    } catch {
        Write-Warning "Failed to write cache metadata: $sentinelPath"
    }
}

function Get-LocalToolCompilerPath {
    <#
    .SYNOPSIS
        Find the actual alc.exe executable in NuGet package cache after local tool installation
    .PARAMETER CacheDir
        Local tool cache directory (not used but kept for compatibility)
    .PARAMETER PackageId
        Package identifier
    .PARAMETER Version
        Tool version
    .OUTPUTS
        Path to alc.exe executable or $null if not found
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CacheDir,

        [Parameter(Mandatory=$true)]
        [string]$PackageId,

        [Parameter(Mandatory=$false)]
        [string]$Version
    )

    # Local tools download packages to NuGet cache
    $userHome = $env:HOME ?? $env:USERPROFILE
    if (-not $userHome) {
        Write-Verbose "Cannot determine user home directory"
        return $null
    }

    $nugetCache = Join-Path $userHome '.nuget\packages'
    if (-not (Test-Path $nugetCache)) {
        Write-Verbose "NuGet package cache not found at: $nugetCache"
        return $null
    }

    # Package directory name in NuGet cache uses lowercase
    $packageDirName = $PackageId.ToLower()
    $packageRoot = Join-Path $nugetCache $packageDirName

    if (-not (Test-Path $packageRoot)) {
        Write-Verbose "Package directory not found at: $packageRoot"
        return $null
    }

    # Look for specific version directory
    if ($Version) {
        $versionDir = Join-Path $packageRoot $Version
        if (Test-Path $versionDir) {
            # Check both tools and lib directories for alc.exe
            $searchPaths = @(
                (Join-Path $versionDir 'tools\net8.0\any\alc.exe'),
                (Join-Path $versionDir 'lib\net8.0\win-x64\alc.exe'),
                (Join-Path $versionDir 'tools\net6.0\any\alc.exe'),
                (Join-Path $versionDir 'lib\net6.0\win-x64\alc.exe')
            )

            foreach ($path in $searchPaths) {
                if (Test-Path $path) {
                    Write-Verbose "Found AL compiler executable: $path"
                    return (Get-Item $path).FullName
                }
            }
        }
    }

    # Fallback: search all version directories
    $versionDirs = Get-ChildItem -Path $packageRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending

    foreach ($versionDir in $versionDirs) {
        $searchPaths = @(
            (Join-Path $versionDir.FullName 'tools\net8.0\any\alc.exe'),
            (Join-Path $versionDir.FullName 'lib\net8.0\win-x64\alc.exe'),
            (Join-Path $versionDir.FullName 'tools\net6.0\any\alc.exe'),
            (Join-Path $versionDir.FullName 'lib\net6.0\win-x64\alc.exe')
        )

        foreach ($path in $searchPaths) {
            if (Test-Path $path) {
                Write-Verbose "Found AL compiler executable: $path"
                return (Get-Item $path).FullName
            }
        }
    }

    Write-Verbose "AL compiler executable not found in NuGet cache for package $PackageId"
    return $null
}

function Install-ALCompilerEnhanced {
    <#
    .SYNOPSIS
        Install AL compiler using local tools in runtime-specific cache directories
    .PARAMETER RuntimeVersion
        Runtime version from app.json
    .PARAMETER RequestedVersion
        Optional explicitly requested version
    .PARAMETER CacheRoot
        Base cache directory (default: ~/.bc-tool-cache/al)
    .PARAMETER PackageIds
        Array of package IDs to consider
    .OUTPUTS
        String path to runtime-specific cache directory containing local tool
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RuntimeVersion,

        [Parameter(Mandatory=$false)]
        [string]$RequestedVersion,

        [Parameter(Mandatory=$false)]
        [string]$CacheRoot = (Join-Path (Join-Path $env:HOME '.bc-tool-cache') 'al'),

        [Parameter(Mandatory=$false)]
        [string[]]$PackageIds
    )

    if (-not $PackageIds -or $PackageIds.Count -eq 0) {
        $PackageIds = @(Get-ToolPackageId)
    }

    Write-Information "� LOCAL TOOLS COMPILER INSTALLATION:" -InformationAction Continue

    # Get package information
    $packageId = Get-PlatformSpecificPackageId -PackageIds $PackageIds
    Write-InfoLine "Package ID" $packageId '📦'

    # Determine target version
    $targetVersion = Select-BestCompilerVersion -RuntimeVersion $RuntimeVersion -RequestedVersion $RequestedVersion -PackageId $packageId
    if (-not $targetVersion) {
        throw "No suitable compiler version found for runtime $RuntimeVersion"
    }

    # Setup runtime-specific cache directory
    $runtimeCacheDir = Get-RuntimeCacheDirectory -RuntimeVersion $RuntimeVersion -CacheRoot $CacheRoot
    Write-InfoLine "Target Version" $targetVersion '🎯'
    Write-InfoLine "Cache Directory" $runtimeCacheDir '📁'

    # Check existing installation
    $cachedMetadata = Get-CachedMetadata -CacheDir $runtimeCacheDir
    $needsInstallation = $true

    if ($cachedMetadata -and $cachedMetadata.version -eq $targetVersion -and $cachedMetadata.packageId -eq $packageId) {
        Write-InfoLine "Cached Version" $cachedMetadata.version '📋'

        # Validate existing installation
        if (Test-LocalToolInstallation -CacheDir $runtimeCacheDir -ExpectedVersion $targetVersion) {
            Write-InfoLine "Installation Status" "Valid (cached)" '✅'
            $needsInstallation = $false
        } else {
            Write-InfoLine "Installation Status" "Invalid (needs reinstall)" '⚠️'
        }
    } else {
        Write-InfoLine "Installation Status" "Required" '🚀'
    }

    # Install if needed
    if ($needsInstallation) {
        Write-Information "  🔧 INSTALLING LOCAL TOOL:" -InformationAction Continue

        $installSuccess = Install-LocalALCompiler -CacheDir $runtimeCacheDir -PackageId $packageId -Version $targetVersion

        if (-not $installSuccess) {
            throw "Failed to install AL compiler version $targetVersion as local tool"
        }

        # Validate installation
        if (-not (Test-LocalToolInstallation -CacheDir $runtimeCacheDir -ExpectedVersion $targetVersion)) {
            throw "AL compiler installation validation failed"
        }

        # Update cache metadata
        $metadata = @{
            version = $targetVersion
            packageId = $packageId
            runtime = $RuntimeVersion
            runtimeMajor = Get-RuntimeMajorVersion -RuntimeVersion $RuntimeVersion
            installationType = 'local-tool'
            installedAt = (Get-Date).ToString('o')
            manifestPath = Join-Path (Join-Path $runtimeCacheDir '.config') 'dotnet-tools.json'
            toolPath = "dotnet tool run al"  # For compatibility with build system
        }

        Set-CachedMetadata -CacheDir $runtimeCacheDir -Metadata $metadata
        Write-Information ("  ✅ Local tool installation completed successfully") -InformationAction Continue
    }

    # ALWAYS find the actual AL compiler executable path (for both fresh and cached installations)
    $compilerPath = Get-LocalToolCompilerPath -CacheDir $runtimeCacheDir -PackageId $packageId -Version $targetVersion
    if (-not $compilerPath) {
        throw "Could not locate AL compiler executable after installation. Package: $packageId, Version: $targetVersion"
    }

    Write-InfoLine "AL Compiler Path" $compilerPath '🎯'

    # Install LinterCop directly to compiler directory
    $compilerDir = Split-Path -Parent $compilerPath
    Install-LinterCopAnalyzer -CompilerDir $compilerDir -CompilerVersion $targetVersion

    # Create compatibility sentinel for build system with actual executable path
    $legacySentinelPath = Join-Path $runtimeCacheDir 'sentinel.json'
    $legacySentinel = @{
        compilerVersion = $targetVersion
        runtime = $RuntimeVersion
        runtimeMajor = Get-RuntimeMajorVersion -RuntimeVersion $RuntimeVersion
        toolPath = $compilerPath
        packageId = $packageId
        installationType = 'local-tool'
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-SentinelFile -Path $legacySentinelPath -Metadata $legacySentinel

    return $runtimeCacheDir
}

# --- API Response Caching Functions ---
$script:ApiCache = @{}

function Get-CachedApiResponse {
    <#
    .SYNOPSIS
        Retrieve cached API response
    .PARAMETER Key
        Cache key
    .PARAMETER IgnoreExpiration
        Whether to ignore cache expiration (for fallback scenarios)
    .OUTPUTS
        Cached data or $null if not found/expired
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key,

        [Parameter(Mandatory=$false)]
        [switch]$IgnoreExpiration
    )

    if (-not $script:ApiCache.ContainsKey($Key)) {
        return $null
    }

    $cacheEntry = $script:ApiCache[$Key]

    if (-not $IgnoreExpiration -and $cacheEntry.ExpiresAt -lt (Get-Date)) {
        Write-Verbose "Cache expired for key: $Key"
        $script:ApiCache.Remove($Key)
        return $null
    }

    Write-Verbose "Cache hit for key: $Key"
    return $cacheEntry.Data
}

function Set-CachedApiResponse {
    <#
    .SYNOPSIS
        Store API response in cache
    .PARAMETER Key
        Cache key
    .PARAMETER Data
        Data to cache
    .PARAMETER ExpirationHours
        Cache expiration in hours (default: 1)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key,

        [Parameter(Mandatory=$true)]
        $Data,

        [Parameter(Mandatory=$false)]
        [int]$ExpirationHours = 1
    )

    $expiresAt = (Get-Date).AddHours($ExpirationHours)

    $script:ApiCache[$Key] = @{
        Data = $Data
        Timestamp = Get-Date
        ExpiresAt = $expiresAt
    }

    Write-Verbose "Cached data for key: $Key (expires: $expiresAt)"
}

function Test-CacheCorruption {
    <#
    .SYNOPSIS
        Detect cache corruption and validate integrity
    .PARAMETER SentinelPath
        Path to sentinel file
    .PARAMETER CompilerPath
        Expected compiler executable path
    .OUTPUTS
        Boolean indicating if cache is corrupted
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SentinelPath,

        [Parameter(Mandatory=$false)]
        [string]$CompilerPath
    )

    # Check if sentinel file is corrupted
    try {
        if (-not (Test-Path -LiteralPath $SentinelPath)) {
            Write-Verbose "Sentinel file missing: $SentinelPath"
            return $true
        }

        $sentinel = Read-SentinelFile -Path $SentinelPath
        if (-not $sentinel) {
            Write-Verbose "Sentinel file corrupted (parse failed): $SentinelPath"
            return $true
        }

        # Check required fields
        $requiredFields = @('compilerVersion', 'runtime', 'toolPath', 'timestamp')
        foreach ($field in $requiredFields) {
            if (-not $sentinel.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($sentinel[$field])) {
                Write-Verbose "Sentinel missing required field '$field': $SentinelPath"
                return $true
            }
        }

        # Check if compiler executable exists
        if (-not (Test-Path -LiteralPath $sentinel.toolPath)) {
            Write-Verbose "Compiler executable missing: $($sentinel.toolPath)"
            return $true
        }

        # Validate timestamp format
        try {
            [DateTime]::Parse($sentinel.timestamp) | Out-Null
        } catch {
            Write-Verbose "Invalid timestamp format in sentinel: $($sentinel.timestamp)"
            return $true
        }

        return $false
    } catch {
        Write-Verbose "Exception during cache corruption check: $($_.Exception.Message)"
        return $true
    }
}

function Repair-CacheCorruption {
    <#
    .SYNOPSIS
        Attempt to repair corrupted cache
    .PARAMETER CacheDirectory
        Cache directory path
    .PARAMETER SentinelPath
        Sentinel file path
    .PARAMETER BackupSentinel
        Whether to backup corrupted sentinel (default: true)
    .OUTPUTS
        Boolean indicating if repair was successful
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$CacheDirectory,

        [Parameter(Mandatory=$true)]
        [string]$SentinelPath,

        [Parameter(Mandatory=$false)]
        [bool]$BackupSentinel = $true
    )

    try {
        Write-Information ("  🔧 Attempting cache repair: {0}" -f $CacheDirectory) -InformationAction Continue

        # Backup corrupted sentinel if requested
        if ($BackupSentinel -and (Test-Path -LiteralPath $SentinelPath)) {
            $backupPath = "$SentinelPath.corrupted.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            try {
                Copy-Item -LiteralPath $SentinelPath -Destination $backupPath -Force
                Write-Verbose "Backed up corrupted sentinel to: $backupPath"
            } catch {
                Write-Warning "Failed to backup corrupted sentinel: $($_.Exception.Message)"
            }
        }

        # Remove corrupted sentinel
        if (Test-Path -LiteralPath $SentinelPath) {
            Remove-Item -LiteralPath $SentinelPath -Force
            Write-Verbose "Removed corrupted sentinel: $SentinelPath"
        }

        # Clean up cache directory if it exists
        if (Test-Path -LiteralPath $CacheDirectory) {
            try {
                Remove-Item -LiteralPath $CacheDirectory -Recurse -Force
                Write-Verbose "Cleaned up cache directory: $CacheDirectory"
            } catch {
                Write-Warning "Failed to clean cache directory: $($_.Exception.Message)"
            }
        }

        Write-Information ("  ✅ Cache repair completed") -InformationAction Continue
        return $true
    } catch {
        Write-Warning "Cache repair failed: $($_.Exception.Message)"
        return $false
    }
}

function Write-ProgressReport {
    <#
    .SYNOPSIS
        Report progress for long-running operations
    .PARAMETER Activity
        Name of the activity being performed
    .PARAMETER Status
        Current status message
    .PARAMETER PercentComplete
        Percentage complete (0-100)
    .PARAMETER CurrentOperation
        Detailed operation description
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Activity,

        [Parameter(Mandatory=$false)]
        [string]$Status = "",

        [Parameter(Mandatory=$false)]
        [int]$PercentComplete = -1,

        [Parameter(Mandatory=$false)]
        [string]$CurrentOperation = ""
    )

    # Use Write-Progress for interactive sessions, Write-Information for automation
    if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -eq 'Windows PowerShell ISE Host') {
        if ($PercentComplete -ge 0) {
            Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -CurrentOperation $CurrentOperation
        } else {
            Write-Progress -Activity $Activity -Status $Status -CurrentOperation $CurrentOperation
        }
    } else {
        # Non-interactive or automated environment
        $message = if ($Status) { "$Activity - $Status" } else { $Activity }
        if ($CurrentOperation) {
            $message += " ($CurrentOperation)"
        }
        Write-Information "  ⏳ $message" -InformationAction Continue
    }
}

function Complete-ProgressReport {
    <#
    .SYNOPSIS
        Complete progress reporting for an activity
    .PARAMETER Activity
        Name of the completed activity
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Activity
    )

    if ($Host.Name -eq 'ConsoleHost' -or $Host.Name -eq 'Windows PowerShell ISE Host') {
        Write-Progress -Activity $Activity -Completed
    }
}

function Invoke-ApiRequestWithRetry {
    <#
    .SYNOPSIS
        Invoke REST request with retry logic, exponential backoff, and progress reporting
    .PARAMETER Uri
        API endpoint URL
    .PARAMETER MaxRetries
        Maximum number of retry attempts (default: 3)
    .PARAMETER BackoffSeconds
        Array of backoff delays in seconds (default: 2, 4, 8)
    .PARAMETER ProgressActivity
        Progress activity name for long operations
    .OUTPUTS
        API response object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Uri,

        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory=$false)]
        [int[]]$BackoffSeconds = @(2, 4, 8),

        [Parameter(Mandatory=$false)]
        [string]$ProgressActivity = "API Request"
    )

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Write-Verbose "API request attempt $attempt/$MaxRetries to: $Uri"

            if ($attempt -gt 1) {
                $progressPercent = [math]::Round(($attempt - 1) / $MaxRetries * 100)
                Write-ProgressReport -Activity $ProgressActivity -Status "Attempt $attempt of $MaxRetries" -PercentComplete $progressPercent -CurrentOperation "Requesting: $Uri"
            } else {
                Write-ProgressReport -Activity $ProgressActivity -Status "Querying API..." -CurrentOperation $Uri
            }

            $result = Invoke-RestMethod -Uri $Uri -UseBasicParsing -TimeoutSec 30 -UserAgent "HelloWorld-AL-BuildTools/1.0"

            Complete-ProgressReport -Activity $ProgressActivity
            return $result
        } catch [System.Net.WebException] {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode
            }

            $isRetryableError = $true
            if ($statusCode -eq 'NotFound' -or $statusCode -eq 'Unauthorized' -or $statusCode -eq 'Forbidden') {
                $isRetryableError = $false
            }

            if ($attempt -eq $MaxRetries -or -not $isRetryableError) {
                Complete-ProgressReport -Activity $ProgressActivity
                Write-Warning "API request failed after $attempt attempts: $($_.Exception.Message)"
                throw
            }

            $waitTime = if ($attempt -le $BackoffSeconds.Count) { $BackoffSeconds[$attempt - 1] } else { $BackoffSeconds[-1] }
            Write-Warning "API request failed (attempt $attempt/$MaxRetries). Retrying in $waitTime seconds... Error: $($_.Exception.Message)"

            Write-ProgressReport -Activity $ProgressActivity -Status "Waiting to retry..." -CurrentOperation "Next attempt in $waitTime seconds"
            Start-Sleep -Seconds $waitTime
        } catch {
            if ($attempt -eq $MaxRetries) {
                Complete-ProgressReport -Activity $ProgressActivity
                Write-Warning "API request failed after $attempt attempts: $($_.Exception.Message)"
                throw
            }

            $waitTime = if ($attempt -le $BackoffSeconds.Count) { $BackoffSeconds[$attempt - 1] } else { $BackoffSeconds[-1] }
            Write-Warning "API request failed (attempt $attempt/$MaxRetries). Retrying in $waitTime seconds... Error: $($_.Exception.Message)"

            Write-ProgressReport -Activity $ProgressActivity -Status "Waiting to retry..." -CurrentOperation "Next attempt in $waitTime seconds"
            Start-Sleep -Seconds $waitTime
        }
    }
}

function Get-ComprehensiveErrorMessage {
    <#
    .SYNOPSIS
        Generate comprehensive error message with troubleshooting guidance
    .PARAMETER ErrorType
        Type of error encountered
    .PARAMETER Context
        Additional context information
    .PARAMETER Exception
        Original exception if available
    .OUTPUTS
        Formatted error message with guidance
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('NetworkFailure', 'CacheCorruption', 'InstallationFailure', 'VersionNotFound', 'PermissionDenied')]
        [string]$ErrorType,

        [Parameter(Mandatory=$false)]
        [hashtable]$Context = @{},

        [Parameter(Mandatory=$false)]
        [System.Exception]$Exception
    )

    $errorMessages = @{
        'NetworkFailure' = @{
            Title = "Network connectivity issue"
            Description = "Unable to connect to required APIs after multiple retries"
            Troubleshooting = @(
                "1. Check internet connectivity and firewall settings",
                "2. Verify access to api.nuget.org and api.github.com",
                "3. Try running with cached versions: `$env:ALBT_USE_CACHE = '1'",
                "4. Consider using an explicit version: `$env:AL_TOOL_VERSION = 'specific-version'"
            )
        }
        'CacheCorruption' = @{
            Title = "Cache corruption detected"
            Description = "Compiler cache is corrupted or inconsistent"
            Troubleshooting = @(
                "1. Clear cache manually: Remove-Item '~/.bc-tool-cache/al' -Recurse -Force",
                "2. Re-run compiler provisioning to rebuild cache",
                "3. Check disk space and permissions for cache directory",
                "4. If issue persists, set ALBT_TOOL_CACHE_ROOT to different location"
            )
        }
        'InstallationFailure' = @{
            Title = "Compiler installation failed"
            Description = "Unable to install AL compiler via dotnet tool command"
            Troubleshooting = @(
                "1. Verify dotnet CLI is installed and functional: dotnet --version",
                "2. Check NuGet package feeds configuration: dotnet nuget list source",
                "3. Try installing manually: dotnet tool install -g Microsoft.Dynamics.BusinessCentral.Development.Tools --prerelease",
                "4. Check for sufficient disk space in user profile directory"
            )
        }
        'VersionNotFound' = @{
            Title = "Compatible compiler version not found"
            Description = "No suitable compiler version available for target runtime"
            Troubleshooting = @(
                "1. Verify runtime version in app.json is correct and supported",
                "2. Check available versions at: https://www.nuget.org/packages/Microsoft.Dynamics.BusinessCentral.Development.Tools",
                "3. Try with explicit version: `$env:AL_TOOL_VERSION = 'available-version'",
                "4. Consider updating runtime version to supported version"
            )
        }
        'PermissionDenied' = @{
            Title = "Permission denied"
            Description = "Insufficient permissions for cache or tool operations"
            Troubleshooting = @(
                "1. Run PowerShell as administrator (Windows) or check sudo permissions (Linux/macOS)",
                "2. Verify write access to user home directory",
                "3. Check cache directory permissions: Test-Path -LiteralPath '~/.bc-tool-cache' -PathType Container",
                "4. Set custom cache location: `$env:ALBT_TOOL_CACHE_ROOT = '/custom/path'"
            )
        }
    }

    $errorInfo = $errorMessages[$ErrorType]
    $contextStr = if ($Context.Count -gt 0) { ($Context.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ", " } else { "None" }

    $message = @"
❌ ERROR: $($errorInfo.Title)

🔍 DESCRIPTION:
   $($errorInfo.Description)

📋 CONTEXT:
   $contextStr

🛠️  TROUBLESHOOTING:
$($errorInfo.Troubleshooting | ForEach-Object { "   $_" })

"@

    if ($Exception) {
        $message += @"
🔬 TECHNICAL DETAILS:
   Exception: $($Exception.GetType().Name)
   Message: $($Exception.Message)

"@
    }

    $message += @"
📖 ADDITIONAL HELP:
   - Documentation: See project README.md for setup instructions
   - Issues: Report issues via GitHub issue tracker
   - Environment: Run 'Invoke-Build show-config' to display current configuration

"@

    return $message
}

function Get-ToolPackageId {
    # Mirror https://github.com/StefanMaron/AL-Dependency-MCP-Server/src/cli/al-installer.ts logic:
    # Windows uses the generic package, Linux/macOS use platform-specific IDs.
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        return 'microsoft.dynamics.businesscentral.development.tools'
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) {
        return 'microsoft.dynamics.businesscentral.development.tools.linux'
    }
    if ([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) {
        return 'microsoft.dynamics.businesscentral.development.tools.osx'
    }
    return 'microsoft.dynamics.businesscentral.development.tools'
}

$ToolPackageId = Get-ToolPackageId
$AllToolPackageIds = @(
    'microsoft.dynamics.businesscentral.development.tools',
    'microsoft.dynamics.businesscentral.development.tools.linux',
    'microsoft.dynamics.businesscentral.development.tools.osx'
)
$candidatePackageIds = @()
foreach ($pkgId in @($ToolPackageId) + $AllToolPackageIds) {
    if ($pkgId -and -not ($candidatePackageIds -contains $pkgId)) {
        $candidatePackageIds += $pkgId
    }
}

# --- Helpers ---
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

function Get-ToolCacheRoot {
    $override = $env:ALBT_TOOL_CACHE_ROOT
    if ($override) {
        return Expand-FullPath -Path $override
    }

    $userHome = $env:HOME
    if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
    if (-not $userHome) {
        throw 'Unable to determine home directory for tool cache.'
    }
    return Join-Path -Path $userHome -ChildPath '.bc-tool-cache'
}

function Initialize-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

function ConvertTo-Version {
    param([Alias('Input')][string]$Value)
    try {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
        return [version]$Value
    } catch {
        return $null
    }
}

function Get-DotnetRoot {
    if ($env:DOTNET_CLI_HOME) {
        $candidate = Join-Path -Path $env:DOTNET_CLI_HOME -ChildPath (Join-Path '.dotnet' 'tools')
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).ProviderPath }
    }
    $userHome = $env:HOME
    if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
    if (-not $userHome) { throw 'Unable to locate dotnet tools root.' }
    return Join-Path -Path $userHome -ChildPath (Join-Path '.dotnet' 'tools')
}

function Test-DotnetAvailable {
    try {
        $null = Get-Command -Name 'dotnet' -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-InstalledToolInfo {
    param([string]$ToolsRoot, [string[]]$PackageIds)

    if (-not $PackageIds -or $PackageIds.Count -eq 0) {
        $PackageIds = @($ToolPackageId)
    }

    $orderedCandidates = @()
    foreach ($candidate in $PackageIds) {
        if ($candidate) { $orderedCandidates += $candidate.ToLowerInvariant() }
    }

    $dotnetListArgs = @('tool', 'list', '--global', '--format', 'json')
    # IMPORTANT: A previous implementation incorrectly set DOTNET_CLI_HOME to the *parent* of the tools root (the .dotnet folder).
    # The dotnet global tools layout is: <DOTNET_CLI_HOME>/.dotnet/tools. Therefore, for a tools root of <Home>/.dotnet/tools,
    # DOTNET_CLI_HOME must be <Home>, not <Home>/.dotnet. Setting it to <Home>/.dotnet caused dotnet to inspect <Home>/.dotnet/.dotnet/tools
    # which does not exist, yielding an empty tool list and preventing version detection after install.
    $originalDotnetCliHome = $env:DOTNET_CLI_HOME
    $restoreDotnetCliHome = $false
    try {
        if ($ToolsRoot) {
            try {
                $resolvedToolsRoot = (Resolve-Path -LiteralPath $ToolsRoot -ErrorAction Stop).ProviderPath
            } catch { $resolvedToolsRoot = $ToolsRoot }
            $leaf = Split-Path -Leaf $resolvedToolsRoot
            if ($leaf -ieq 'tools') {
                $parent = Split-Path -Parent $resolvedToolsRoot -ErrorAction SilentlyContinue
                $parentLeaf = if ($parent) { Split-Path -Leaf $parent } else { $null }
                if ($parentLeaf -ieq '.dotnet') {
                    # Home directory is one level above '.dotnet'
                    $candidateHome = Split-Path -Parent $parent -ErrorAction SilentlyContinue
                } else {
                    # Unexpected layout; fall back to parent of tools
                    $candidateHome = $parent
                }
                if ($candidateHome -and (Test-Path -LiteralPath $candidateHome)) {
                    $env:DOTNET_CLI_HOME = $candidateHome
                    $restoreDotnetCliHome = $true
                }
            }
        }
        $jsonText = & dotnet @dotnetListArgs
    } finally {
        if ($restoreDotnetCliHome) { $env:DOTNET_CLI_HOME = $originalDotnetCliHome }
    }
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    try {
        $parsed = $jsonText | ConvertFrom-Json
        if (-not $parsed -or -not $parsed.data) { return $null }
        foreach ($preferred in $orderedCandidates) {
            foreach ($entry in $parsed.data) {
                $entryId = if ($entry.packageId) { $entry.packageId.ToString().ToLowerInvariant() } else { $null }
                if ($entryId -eq $preferred) {
                    return [pscustomobject]@{
                        packageId = $entryId
                        version = [string]$entry.version
                    }
                }
            }
        }
        return $null
    } catch {
        return $null
    }
}

function Get-CompilerPath {
    param([string]$ToolsRoot, [string]$ToolVersion, [string[]]$PackageIds)

    if (-not $PackageIds -or $PackageIds.Count -eq 0) {
        $PackageIds = @($ToolPackageId)
    }

    $storeRoot = Join-Path -Path $ToolsRoot -ChildPath '.store'
    if (-not (Test-Path -LiteralPath $storeRoot)) { return $null }

    foreach ($candidatePackageId in $PackageIds) {
        if (-not $candidatePackageId) { continue }
        $packageDirName = $candidatePackageId.ToLower()
        $packageRoot = Join-Path -Path $storeRoot -ChildPath $packageDirName
        if (-not (Test-Path -LiteralPath $packageRoot)) { continue }

        $searchDepth = 6

        $items = Get-ChildItem -Path $packageRoot -Recurse -File -Depth $searchDepth -ErrorAction SilentlyContinue |
            Where-Object { $ToolExecutableNames -contains $_.Name }

        if ($ToolVersion) {
            $items = $items | Where-Object { $_.FullName -match [regex]::Escape($ToolVersion) }
        }

        $candidate = $items | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    return $null
}





function Get-LinterCopUrlForCompilerVersion {
    <#
    .SYNOPSIS
        Get the correct LinterCop download URL for a specific AL compiler version
    .PARAMETER CompilerVersion
        AL compiler version (e.g., "15.0.24.31795-beta")
    .OUTPUTS
        String URL for downloading the version-specific LinterCop DLL
    #>
    [CmdletBinding()]
    param([string]$CompilerVersion)

    if (-not $CompilerVersion) {
        Write-Warning "No compiler version provided for LinterCop URL determination"
        return $null
    }

    # Extract base version from full version string (e.g., "15.0.24.31795-beta" -> "15.0.24.31795")
    $baseVersion = $CompilerVersion -replace '-.*$', ''

    # Parse version components
    $versionParts = $baseVersion -split '\.'
    if ($versionParts.Count -lt 3) {
        Write-Warning "Invalid compiler version format: $CompilerVersion"
        return Get-GenericLinterCopUrl
    }

    # Try different version patterns in order of preference
    $versionCandidates = @(
        $CompilerVersion,                                    # Full version with suffix (15.0.24.31795-beta)
        $baseVersion,                                        # Full version without suffix (15.0.24.31795)
        "$($versionParts[0]).$($versionParts[1]).$($versionParts[2])"  # Major.Minor.Build (15.0.24)
    )

    # Add some common version patterns based on known available versions
    if ($versionParts[0] -eq "15" -and $versionParts[1] -eq "0") {
        # For 15.0.x versions, try some common available patterns
        $versionCandidates += @("15.0.1433841", "15.0.1410565")
    } elseif ($versionParts[0] -eq "15" -and $versionParts[1] -eq "2") {
        # For 15.2.x versions, try the known available version
        $versionCandidates += @("15.2.1630495")
    } elseif ($versionParts[0] -eq "16" -and $versionParts[1] -eq "0") {
        # For 16.0.x versions, try some common available patterns
        $versionCandidates += @("16.0.1743592", "16.0.1418343", "16.0.1433787")
    } elseif ($versionParts[0] -eq "17" -and $versionParts[1] -eq "0") {
        # For 17.0.x versions, try available patterns
        $versionCandidates += @("17.0.1750311")
    }

    foreach ($versionCandidate in $versionCandidates) {
        $versionSpecificUrl = "https://github.com/StefanMaron/BusinessCentral.LinterCop/releases/latest/download/BusinessCentral.LinterCop.AL-$versionCandidate.dll"

        # Test if version-specific URL exists by making a HEAD request
        try {
            $headResponse = Invoke-WebRequest -Uri $versionSpecificUrl -Method Head -UseBasicParsing -ErrorAction Stop
            if ($headResponse.StatusCode -eq 200) {
                Write-Verbose "Found version-specific LinterCop: $versionSpecificUrl"
                Write-InfoLine "LinterCop Version" "AL-$versionCandidate (version-matched)" '🎯'
                return $versionSpecificUrl
            }
        } catch {
            Write-Verbose "Version-specific LinterCop not available: $versionSpecificUrl"
        }
    }

    # Fall back to generic version
    Write-Warning "No version-specific LinterCop found for AL compiler $CompilerVersion. Using generic version."
    Write-Warning "Version compatibility not guaranteed. Consider using a supported AL compiler version."

    return Get-GenericLinterCopUrl
}

function Get-GenericLinterCopUrl {
    <#
    .SYNOPSIS
        Get the generic LinterCop download URL (latest version)
    #>
    Write-InfoLine "LinterCop Version" "Generic (latest)" '⚠️'
    return "https://github.com/StefanMaron/BusinessCentral.LinterCop/releases/latest/download/BusinessCentral.LinterCop.dll"
}

function Install-LinterCopAnalyzer {
    <#
    .SYNOPSIS
        Install LinterCop analyzer directly to AL compiler directory
    .PARAMETER CompilerDir
        AL compiler directory where Microsoft analyzers are located
    .PARAMETER CompilerVersion
        AL compiler version to match for LinterCop compatibility
    #>
    [CmdletBinding()]
    param(
        [string]$CompilerDir,
        [string]$CompilerVersion
    )

    if (-not $CompilerDir -or -not (Test-Path $CompilerDir)) {
        Write-Verbose "Compiler directory not provided or doesn't exist: $CompilerDir"
        return
    }

    try {
        # Determine the correct LinterCop version URL based on AL compiler version
        $linterCopUrl = Get-LinterCopUrlForCompilerVersion -CompilerVersion $CompilerVersion
        if (-not $linterCopUrl) {
            Write-Warning "Unable to determine LinterCop URL for compiler version: $CompilerVersion"
            return
        }

        $forceLinterCop = $false
        if ($env:ALBT_FORCE_LINTERCOP -and ($env:ALBT_FORCE_LINTERCOP -match '^(?i:1|true|yes|on)$')) { $forceLinterCop = $true }

        # Create analyzers directory in cache
        $analyzersDir = $CompilerDir
        if (-not (Test-Path -LiteralPath $analyzersDir)) {
            try {
                New-Item -ItemType Directory -Path $analyzersDir -Force | Out-Null
                Write-Verbose "Created analyzers directory: $analyzersDir"
            } catch {
                throw "Unable to create analyzers directory at ${analyzersDir}: $($_.Exception.Message)"
            }
        }

        # Always use generic filename for consistent analyzer reference
        $dllFileName = "BusinessCentral.LinterCop.dll"
        $targetDll = Join-Path -Path $analyzersDir -ChildPath $dllFileName
        $needDownload = $true
        if ((Test-Path -LiteralPath $targetDll) -and -not $forceLinterCop) { $needDownload = $false }

        # Extract version info from URL for informative output
        $versionInfo = if ($linterCopUrl -match 'BusinessCentral\.LinterCop\.AL-(.+)\.dll') { $matches[1] } else { "generic" }

        if (-not $needDownload) {
            Write-InfoLine "LinterCop Status" "Already present" '✅'
            Write-InfoLine "Location" $targetDll '📁'
            Write-StatusLine "Set ALBT_FORCE_LINTERCOP=1 to force re-download" 'ℹ️'
        } else {
            Write-Information ("  📥 Downloading LinterCop analyzer from {0}" -f $linterCopUrl) -InformationAction Continue
            Write-Information ("  🔄 Will be saved as generic filename: {0}" -f $dllFileName) -InformationAction Continue
            Write-Information ("  📦 LinterCop version: {0}" -f $versionInfo) -InformationAction Continue
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                Invoke-WebRequest -Uri $linterCopUrl -OutFile $tempFile -UseBasicParsing -ErrorAction Stop
                $fileInfo = Get-Item -LiteralPath $tempFile -ErrorAction Stop
                if ($fileInfo.Length -le 0) { throw 'Downloaded file is empty.' }
                Move-Item -LiteralPath $tempFile -Destination $targetDll -Force
                Write-InfoLine "LinterCop Status" "Downloaded and installed to compiler directory" '✅'
                Write-InfoLine "Location" $targetDll '📁'
                Write-Information ("  ✨ Installed alongside Microsoft analyzers for seamless integration") -InformationAction Continue
            } catch {
                Write-Warning "Failed to download LinterCop analyzer: $($_.Exception.Message)"
                try {
                    if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
                } catch {
                    Write-Verbose "[albt] temp file cleanup failed: $($_.Exception.Message)"
                }
            }
        }
    } catch {
        Write-Warning "Unexpected error while ensuring LinterCop analyzer: $($_.Exception.Message)"
    }
}

# --- Enhanced Runtime-Based Execution ---
Write-Section 'Environment Analysis'



# --- Legacy Execution Method ---
Write-Section 'Environment Analysis'

Write-Information "🔍 PREREQUISITE CHECK:" -InformationAction Continue
if (-not (Test-DotnetAvailable)) {
    Write-InfoLine "dotnet CLI" "Not found" '❌'
    Write-StatusLine "Install .NET SDK to provision the AL compiler" '❌'
    throw 'dotnet CLI not found on PATH. Install .NET SDK to provision the AL compiler.'
}
Write-InfoLine "dotnet CLI" "Available" '✅'

Write-Information "📋 PROJECT CONFIGURATION:" -InformationAction Continue
$appJsonPath = Resolve-AppJsonPath -AppDirectory $AppDir
$appJson = Read-JsonFile -Path $appJsonPath
if (-not $appJson.runtime) {
    Write-InfoLine "app.json" "Found" '⚠️'
    Write-StatusLine 'Runtime not specified in app.json ("runtime" property missing)' '❌'
    throw 'Runtime not specified in app.json ("runtime" property missing).'
}
$appRuntime = [string]$appJson.runtime

# Allow runtime override via environment variable
if ($env:ALBT_RUNTIME_VERSION) {
    $appRuntime = $env:ALBT_RUNTIME_VERSION
    Write-InfoLine "app.json" "Found" '✅'
    Write-InfoLine "Target Runtime" "$appRuntime (overridden)" '🎯'
} else {
    Write-InfoLine "app.json" "Found" '✅'
    Write-InfoLine "Target Runtime" $appRuntime '🎯'
}

$requestedToolVersion = $env:AL_TOOL_VERSION
if ($requestedToolVersion) {
    Write-InfoLine "Requested Version" $requestedToolVersion '📌'
}

Write-Section 'Runtime-Based Compiler Selection'
Write-Information "🚀 RUNTIME-BASED SELECTION:" -InformationAction Continue
Write-InfoLine "Mode" "Enhanced runtime-based selection" '⚡'
Write-InfoLine "Runtime" $appRuntime '🎯'

# Use enhanced local tools workflow
$toolCacheRoot = Get-ToolCacheRoot
$alCacheDir = Join-Path -Path $toolCacheRoot -ChildPath 'al'
$cacheDirectory = Install-ALCompilerEnhanced -RuntimeVersion $appRuntime -RequestedVersion $requestedToolVersion -CacheRoot $alCacheDir -PackageIds $candidatePackageIds

Write-Section 'Summary'
Write-Information "✅ Runtime-based compiler provisioning complete!" -InformationAction Continue
exit 0


