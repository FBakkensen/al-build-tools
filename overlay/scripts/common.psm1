#requires -Version 7.2

<#
.SYNOPSIS
    Shared utilities for AL Build System (Invoke-Build)

.DESCRIPTION
    Common helper functions used across build, test, and provisioning scripts.
    This module eliminates code duplication and provides a single source of truth
    for path resolution, JSON parsing, formatting, and configuration management.

.NOTES
    This module is dot-sourced by al.build.ps1 and imported by task scripts.
    Functions are organized by category for maintainability.
#>

Set-StrictMode -Version Latest

# =============================================================================
# Exit Codes
# =============================================================================

function Get-ExitCode {
    <#
    .SYNOPSIS
        Standard exit codes for build scripts
    #>
    return @{
        Success      = 0
        GeneralError = 1
        Guard        = 2
        Analysis     = 3
        Contract     = 4
        Integration  = 5
        MissingTool  = 6
    }
}

# =============================================================================
# Path Utilities
# =============================================================================

function Expand-FullPath {
    <#
    .SYNOPSIS
        Expand environment variables and resolve full path
    .PARAMETER Path
        Path to expand (supports ~, environment variables)
    #>
    param([string]$Path)

    if (-not $Path) { return $null }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)

    if ($expanded.StartsWith('~')) {
        $userHome = $env:HOME
        if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
        if ($userHome) {
            $suffix = $expanded.Substring(1).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            if ([string]::IsNullOrWhiteSpace($suffix)) {
                $expanded = $userHome
            } else {
                $expanded = Join-Path -Path $userHome -ChildPath $suffix
            }
        }
    }

    try {
        return (Resolve-Path -LiteralPath $expanded -ErrorAction Stop).ProviderPath
    } catch {
        return [System.IO.Path]::GetFullPath($expanded)
    }
}

function ConvertTo-SafePathSegment {
    <#
    .SYNOPSIS
        Convert string to safe filesystem path segment
    .PARAMETER Value
        String to sanitize
    #>
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

function Ensure-Directory {
    <#
    .SYNOPSIS
        Ensure directory exists (create if missing)
    .PARAMETER Path
        Directory path to ensure exists
    #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        [void](New-Item -ItemType Directory -Path $Path -Force)
    }
}

function New-TemporaryDirectory {
    <#
    .SYNOPSIS
        Create a new temporary directory with unique GUID-based name
    .DESCRIPTION
        Creates a uniquely named temporary directory in the system temp location.
        Useful for isolating temporary file operations across scripts.
    .OUTPUTS
        String path to the created temporary directory
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()

    $base = [System.IO.Path]::GetTempPath()
    $name = 'bc-temp-' + [System.Guid]::NewGuid().ToString('N')
    $path = Join-Path -Path $base -ChildPath $name
    $action = 'Create temporary directory'

    if (-not $PSCmdlet -or $PSCmdlet.ShouldProcess($path, $action)) {
        Ensure-Directory -Path $path
    }

    return $path
}

# =============================================================================
# JSON and App Configuration
# =============================================================================

function Get-AppJsonPath {
    <#
    .SYNOPSIS
        Locate app.json in project directory
    .PARAMETER AppDir
        Directory to search (defaults to current directory)
    #>
    param([string]$AppDir)
    $p1 = Join-Path -Path $AppDir -ChildPath 'app.json'
    $p2 = 'app.json'
    if (Test-Path $p1) { return $p1 }
    elseif (Test-Path $p2) { return $p2 }
    else { return $null }
}

function Get-SettingsJsonPath {
    <#
    .SYNOPSIS
        Locate .vscode/settings.json in project directory
    .PARAMETER AppDir
        Directory to search
    #>
    param([string]$AppDir)
    $p1 = Join-Path -Path $AppDir -ChildPath '.vscode/settings.json'
    if (Test-Path $p1) { return $p1 }
    $p2 = '.vscode/settings.json'
    if (Test-Path $p2) { return $p2 }
    return $null
}

function Get-AppJsonObject {
    <#
    .SYNOPSIS
        Parse app.json as PowerShell object
    .PARAMETER AppDir
        Directory containing app.json
    #>
    param([string]$AppDir)
    $appJson = Get-AppJsonPath $AppDir
    if (-not $appJson) { return $null }
    try { Get-Content $appJson -Raw | ConvertFrom-Json } catch { $null }
}

function Get-SettingsJsonObject {
    <#
    .SYNOPSIS
        Parse .vscode/settings.json as PowerShell object
    .PARAMETER AppDir
        Directory containing .vscode
    #>
    param([string]$AppDir)
    $path = Get-SettingsJsonPath $AppDir
    if (-not $path) { return $null }
    try { Get-Content $path -Raw | ConvertFrom-Json } catch { $null }
}

function Get-OutputPath {
    <#
    .SYNOPSIS
        Compute expected output .app file path from app.json
    .PARAMETER AppDir
        Directory containing app.json
    #>
    param([string]$AppDir)
    $appJson = Get-AppJsonPath $AppDir
    if (-not $appJson) { return $null }
    try {
        $json = Get-Content $appJson -Raw | ConvertFrom-Json
        if (-not $json.name -or -not $json.version -or -not $json.publisher) {
            return $null
        }
        $name = $json.name
        $version = $json.version
        $publisher = $json.publisher
        $file = "${publisher}_${name}_${version}.app"
        return Join-Path -Path $AppDir -ChildPath $file
    } catch { return $null }
}

function Read-JsonFile {
    <#
    .SYNOPSIS
        Read and parse JSON file with error handling
    .PARAMETER Path
        Path to JSON file
    #>
    param([string]$Path)
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse JSON from ${Path}: $($_.Exception.Message)"
    }
}

function Resolve-AppJsonPath {
    <#
    .SYNOPSIS
        Resolve absolute path to app.json with validation
    .PARAMETER AppDirectory
        Directory to search
    #>
    param([string]$AppDirectory)

    if ($AppDirectory) {
        $candidate = Join-Path -Path $AppDirectory -ChildPath 'app.json'
        if (Test-Path -LiteralPath $candidate) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }
    if (Test-Path -LiteralPath 'app.json') {
        return (Get-Item -LiteralPath 'app.json').FullName
    }
    throw "app.json not found. Provide -AppDir or run from project root."
}

# =============================================================================
# Cache Management
# =============================================================================

function Get-ToolCacheRoot {
    <#
    .SYNOPSIS
        Get root directory for AL compiler tool cache
    #>
    $override = $env:ALBT_TOOL_CACHE_ROOT
    if ($override) { return Expand-FullPath -Path $override }

    $userHome = $env:HOME
    if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
    if (-not $userHome) { throw 'Unable to determine home directory for tool cache.' }

    return Join-Path -Path $userHome -ChildPath '.bc-tool-cache'
}

function Get-SymbolCacheRoot {
    <#
    .SYNOPSIS
        Get root directory for BC symbol package cache
    #>
    $userHome = $env:HOME
    if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
    if (-not $userHome) {
        throw 'Unable to determine home directory for symbol cache. Ensure HOME or USERPROFILE environment variable is set.'
    }
    return Join-Path -Path $userHome -ChildPath '.bc-symbol-cache'
}

function Get-LatestCompilerInfo {
    <#
    .SYNOPSIS
        Get AL compiler information from latest-only sentinel (no runtime-specific versions)
    .DESCRIPTION
        Uses the new "latest compiler only" principle - single compiler version for all projects.
        No runtime-specific caching, no version selection.
    .OUTPUTS
        PSCustomObject with AlcPath, Version, SentinelPath, IsLocalTool
    #>
    [CmdletBinding()]
    param()

    $toolCacheRoot = Get-ToolCacheRoot
    $alCacheDir = Join-Path -Path $toolCacheRoot -ChildPath 'al'
    $sentinelPath = Join-Path -Path $alCacheDir -ChildPath 'sentinel.json'

    if (-not (Test-Path -LiteralPath $sentinelPath)) {
        throw "Compiler not provisioned. Sentinel not found at: $sentinelPath. Run 'Invoke-Build download-compiler' first."
    }

    try {
        $sentinel = Get-Content -LiteralPath $sentinelPath -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse compiler sentinel at ${sentinelPath}: $($_.Exception.Message)"
    }

    $compilerVersion = if ($sentinel.PSObject.Properties.Match('compilerVersion').Count -gt 0) { [string]$sentinel.compilerVersion } else { $null }
    $toolPath = [string]$sentinel.toolPath

    if (-not $toolPath) {
        throw "Compiler sentinel at $sentinelPath is missing 'toolPath' property."
    }

    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "AL compiler executable not found at: $toolPath. Run 'Invoke-Build download-compiler' to reinstall."
    }

    $toolItem = Get-Item -LiteralPath $toolPath

    return [pscustomobject]@{
        AlcPath      = $toolItem.FullName
        Version      = $compilerVersion
        SentinelPath = $sentinelPath
        IsLocalTool  = ($sentinel.installationType -eq 'local-tool')
    }
}

function Get-SymbolCacheInfo {
    <#
    .SYNOPSIS
        Get symbol cache directory and manifest information
    .PARAMETER AppJson
        Parsed app.json object
    #>
    param($AppJson)

    if (-not $AppJson) {
        throw 'app.json is required to resolve the symbol cache. Ensure app.json exists and run `make download-symbols`.'
    }

    if (-not $AppJson.publisher) {
        throw 'app.json missing "publisher". Update the manifest and rerun `make download-symbols`.'
    }
    if (-not $AppJson.name) {
        throw 'app.json missing "name". Update the manifest and rerun `make download-symbols`.'
    }
    if (-not $AppJson.id) {
        throw 'app.json missing "id". Update the manifest and rerun `make download-symbols`.'
    }

    $cacheRoot = Get-SymbolCacheRoot

    $publisherDir = Join-Path -Path $cacheRoot -ChildPath (ConvertTo-SafePathSegment -Value $AppJson.publisher)
    $appDirPath = Join-Path -Path $publisherDir -ChildPath (ConvertTo-SafePathSegment -Value $AppJson.name)
    $cacheDir = Join-Path -Path $appDirPath -ChildPath (ConvertTo-SafePathSegment -Value $AppJson.id)

    if (-not (Test-Path -LiteralPath $cacheDir)) {
        throw "Symbol cache directory not found at $cacheDir. Run `make download-symbols` before `make build`."
    }

    $manifestPath = Join-Path -Path $cacheDir -ChildPath 'symbols.lock.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Symbol manifest missing at $manifestPath. Run `make download-symbols` before `make build`."
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    } catch {
        throw "Failed to parse symbol manifest at ${manifestPath}: $($_.Exception.Message). Run `make download-symbols` before `make build`."
    }

    return [pscustomobject]@{
        CacheDir     = (Get-Item -LiteralPath $cacheDir).FullName
        ManifestPath = $manifestPath
        Manifest     = $manifest
    }
}

# =============================================================================
# Standardized Output System (enforces consistent formatting)
# =============================================================================

function Write-BuildMessage {
    <#
    .SYNOPSIS
        Standardized output for all build scripts (enforces consistent formatting)
    .DESCRIPTION
        Central output function that ensures all build scripts use consistent message formatting.
        This is the ONLY function scripts should use for console output (except Write-BuildHeader).
    .PARAMETER Type
        Message type: Info, Success, Warning, Error, Step, Detail
    .PARAMETER Message
        The message text
    .EXAMPLE
        Write-BuildMessage -Type Step -Message "Downloading compiler..."
        Write-BuildMessage -Type Success -Message "Build completed"
        Write-BuildMessage -Type Error -Message "Compilation failed"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Step', 'Detail')]
        [string]$Type = 'Info',

        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    switch ($Type) {
        'Info'    { Write-Host "[INFO] " -NoNewline -ForegroundColor Cyan; Write-Host $Message }
        'Success' { Write-Host "[✓] " -NoNewline -ForegroundColor Green; Write-Host $Message }
        'Warning' { Write-Host "[!] " -NoNewline -ForegroundColor Yellow; Write-Host $Message }
        'Error'   { Write-Host "[✗] " -NoNewline -ForegroundColor Red; Write-Host $Message }
        'Step'    { Write-Host "[→] " -NoNewline -ForegroundColor Magenta; Write-Host $Message }
        'Detail'  { Write-Host "    • " -NoNewline -ForegroundColor Gray; Write-Host $Message -ForegroundColor Gray }
    }
}

function Write-BuildHeader {
    <#
    .SYNOPSIS
        Standardized section header for build scripts
    .DESCRIPTION
        Displays a consistent section header across all build scripts.
    .PARAMETER Title
        Section title
    .EXAMPLE
        Write-BuildHeader "AL Compiler Provisioning"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title
    )

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ("=" * 80) -ForegroundColor DarkGray
    Write-Host ""
}

function Write-TaskHeader {
    <#
    .SYNOPSIS
        Standardized task header for Invoke-Build tasks
    .DESCRIPTION
        Displays the colored "🔧 INVOKE-BUILD | TASK | Description" header used by tasks.
    .PARAMETER TaskName
        Name of the task (e.g., "BUILD", "HELP", "DOWNLOAD-COMPILER")
    .PARAMETER Description
        Brief description of the task
    .EXAMPLE
        Write-TaskHeader "BUILD" "AL Project Compilation"
        Write-TaskHeader "HELP" "AL Project Build System"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TaskName,

        [Parameter(Mandatory=$true)]
        [string]$Description
    )

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Yellow
    Write-Host "🔧 INVOKE-BUILD | $TaskName | $Description" -ForegroundColor Yellow
    Write-Host ("=" * 80) -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# Legacy Formatting Helpers (deprecated - use Write-BuildMessage instead)
# =============================================================================

function Write-Section {
    <#
    .SYNOPSIS
        Write formatted section header
    .PARAMETER Title
        Section title
    .PARAMETER SubInfo
        Optional subtitle
    .NOTES
        DEPRECATED: Use Write-BuildHeader instead
    #>
    param([string]$Title, [string]$SubInfo = '')
    $line = ''.PadLeft(80, '=')
    Write-Information "" # blank spacer
    Write-Information $line -InformationAction Continue
    $header = "🔧 BUILD | {0}" -f $Title
    if ($SubInfo) { $header += " | {0}" -f $SubInfo }
    Write-Information $header -InformationAction Continue
    Write-Information $line -InformationAction Continue
}

function Write-InfoLine {
    <#
    .SYNOPSIS
        Write formatted information line with label and value
    .PARAMETER Label
        Label text
    .PARAMETER Value
        Value text
    .PARAMETER Icon
        Icon character (defaults to •)
    .NOTES
        DEPRECATED: Use Write-BuildMessage -Type Detail instead
    #>
    param(
        [string]$Label,
        [string]$Value,
        [string]$Icon = '•'
    )
    $labelPadded = ($Label).PadRight(14)
    Write-Information ("  {0}{1}: {2}" -f $Icon, $labelPadded, $Value) -InformationAction Continue
}

function Write-StatusLine {
    <#
    .SYNOPSIS
        Write formatted status message
    .PARAMETER Message
        Status message
    .PARAMETER Icon
        Icon character (defaults to ⚠️)
    .NOTES
        DEPRECATED: Use Write-BuildMessage -Type Info/Warning instead
    #>
    param([string]$Message, [string]$Icon = '⚠️')
    Write-Information ("  {0} {1}" -f $Icon, $Message) -InformationAction Continue
}

function Write-ListItem {
    <#
    .SYNOPSIS
        Write formatted list item
    .PARAMETER Item
        Item text
    .PARAMETER Icon
        Icon character (defaults to →)
    .NOTES
        DEPRECATED: Use Write-BuildMessage -Type Detail instead
    #>
    param([string]$Item, [string]$Icon = '→')
    Write-Information ("    {0} {1}" -f $Icon, $Item) -InformationAction Continue
}

# =============================================================================
# Analyzer Utilities
# =============================================================================

function Test-AnalyzerDependencies {
    <#
    .SYNOPSIS
        Test if an analyzer has all required dependencies available
    .PARAMETER AnalyzerPath
        Path to the analyzer DLL to test
    #>
    param([string]$AnalyzerPath)

    if (-not (Test-Path -LiteralPath $AnalyzerPath)) {
        return $false
    }

    try {
        # Try to load the analyzer assembly to check for missing dependencies
        $bytes = [System.IO.File]::ReadAllBytes($AnalyzerPath)
        $assembly = [System.Reflection.Assembly]::Load($bytes)

        # Check if we can get the types (this will fail if dependencies are missing)
        $types = $assembly.GetTypes()
        return $true
    } catch {
        Write-Information "[albt] Analyzer dependency check failed for $(Split-Path -Leaf $AnalyzerPath): $($_.Exception.Message)" -InformationAction Continue
        return $false
    }
}

function Get-EnabledAnalyzerPath {
    <#
    .SYNOPSIS
        Get list of enabled analyzer DLL paths based on VS Code settings
    .PARAMETER AppDir
        Application directory
    .PARAMETER CompilerDir
        Compiler directory (for resolving analyzer paths)
    #>
    param(
        [string]$AppDir,
        [string]$CompilerDir
    )

    $settingsPath = Get-SettingsJsonPath $AppDir
    $dllMap = @{
        'CodeCop'               = 'Microsoft.Dynamics.Nav.CodeCop.dll'
        'UICop'                 = 'Microsoft.Dynamics.Nav.UICop.dll'
        'AppSourceCop'          = 'Microsoft.Dynamics.Nav.AppSourceCop.dll'
        'PerTenantExtensionCop' = 'Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll'
    }
    $supported = $dllMap.Keys
    $enabled = @()

    if ($settingsPath -and (Test-Path -LiteralPath $settingsPath)) {
        try {
            $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($json -and ($json.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $json.'al.codeAnalyzers') {
                $enabled = @($json.'al.codeAnalyzers')
            } elseif ($json) {
                if ($json.PSObject.Properties.Match('enableCodeCop').Count -gt 0 -and $json.enableCodeCop) { $enabled += 'CodeCop' }
                if ($json.PSObject.Properties.Match('enableUICop').Count -gt 0 -and $json.enableUICop) { $enabled += 'UICop' }
                if ($json.PSObject.Properties.Match('enableAppSourceCop').Count -gt 0 -and $json.enableAppSourceCop) { $enabled += 'AppSourceCop' }
                if ($json.PSObject.Properties.Match('enablePerTenantExtensionCop').Count -gt 0 -and $json.enablePerTenantExtensionCop) { $enabled += 'PerTenantExtensionCop' }
            }
        } catch {
            Write-Information "[albt] settings.json parse failed: $($_.Exception.Message)" -InformationAction Continue
        }
    }

    $dllPaths = New-Object System.Collections.Generic.List[string]
    if (-not $enabled -or $enabled.Count -eq 0) { return $dllPaths }

    $workspaceRoot = (Get-Location).Path
    $appFull = try { (Resolve-Path $AppDir -ErrorAction Stop).Path } catch { Join-Path $workspaceRoot $AppDir }

    # Find analyzers directory - check compiler directory only (no runtime-specific caches)
    $analyzersDir = $null

    if ($CompilerDir -and (Test-Path -LiteralPath $CompilerDir)) {
        $candidate = Join-Path -Path $CompilerDir -ChildPath 'Analyzers'
        if (Test-Path -LiteralPath $candidate) {
            $analyzersDir = (Get-Item -LiteralPath $candidate).FullName
        } else {
            $analyzersDir = (Get-Item -LiteralPath $CompilerDir).FullName
        }
    }

    function Resolve-AnalyzerEntry {
        param([string]$Entry)

        $val = $Entry
        if ($null -eq $val) { return @() }

        if ($val -match '^\$\{analyzerFolder\}(.*)$' -and $analyzersDir) {
            $tail = $matches[1]
            if ($tail -and $tail[0] -notin @('\\','/')) { $val = Join-Path $analyzersDir $tail } else { $val = "$analyzersDir$tail" }
        }
        if ($val -match '^\$\{alExtensionPath\}(.*)$' -and $CompilerDir) {
            $tail2 = $matches[1]
            if ($tail2 -and $tail2[0] -notin @('\\','/')) { $val = Join-Path $CompilerDir $tail2 } else { $val = "$CompilerDir$tail2" }
        }
        if ($val -match '^\$\{compilerRoot\}(.*)$' -and $CompilerDir) {
            $tail3 = $matches[1]
            if ($tail3 -and $tail3[0] -notin @('\\','/')) { $val = Join-Path $CompilerDir $tail3 } else { $val = "$CompilerDir$tail3" }
        }

        if ($CompilerDir) {
            $val = $val.Replace('${alExtensionPath}', $CompilerDir)
            $val = $val.Replace('${compilerRoot}', $CompilerDir)
        }
        if ($analyzersDir) {
            $val = $val.Replace('${analyzerFolder}', $analyzersDir)
        }

        $val = $val.Replace('${workspaceFolder}', $workspaceRoot).Replace('${workspaceRoot}', $workspaceRoot).Replace('${appDir}', $appFull)
        $val = [regex]::Replace($val, '\$\{([^}]+)\}', '$1')

        $expanded = [Environment]::ExpandEnvironmentVariables($val)
        if ($expanded.StartsWith('~')) {
            $userHome = $env:HOME
            if (-not $userHome -and $env:USERPROFILE) { $userHome = $env:USERPROFILE }
            if ($userHome) {
                $suffix = $expanded.Substring(1).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
                if ([string]::IsNullOrWhiteSpace($suffix)) {
                    $expanded = $userHome
                } else {
                    $expanded = Join-Path -Path $userHome -ChildPath $suffix
                }
            }
        }

        if (-not [IO.Path]::IsPathRooted($expanded)) {
            $expanded = Join-Path $workspaceRoot $expanded
        }

        if (Test-Path $expanded -PathType Container) {
            return Get-ChildItem -Path $expanded -Filter '*.dll' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        }

        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($expanded)) {
            return Get-ChildItem -Path $expanded -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        }

        if (Test-Path $expanded -PathType Leaf) { return @($expanded) }

        return @()
    }

    foreach ($item in $enabled) {
        $name = ($item | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name -match '^\$\{([A-Za-z]+)\}$') { $name = $matches[1] }

        if ($supported -contains $name) {
            if ($analyzersDir -or $CompilerDir) {
                $dll = $dllMap[$name]
                $searchRoots = @()
                if ($analyzersDir) { $searchRoots += $analyzersDir }
                if ($CompilerDir -and ($searchRoots -notcontains $CompilerDir)) { $searchRoots += $CompilerDir }

                $found = $null
                foreach ($root in $searchRoots) {
                    if (-not (Test-Path -LiteralPath $root)) { continue }
                    $candidate = Get-ChildItem -Path $root -Recurse -Filter $dll -File -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($candidate) { $found = $candidate; break }
                }

                if ($found -and -not $dllPaths.Contains($found.FullName)) {
                    $dllPaths.Add($found.FullName) | Out-Null
                } elseif (-not $found) {
                    Write-Information "[albt] Analyzer '$name' requested but $dll not found near compiler directory." -InformationAction Continue
                }
            } else {
                Write-Information "[albt] Analyzer '$name' requested but compiler directory unavailable for resolution." -InformationAction Continue
            }
        } else {
            (Resolve-AnalyzerEntry -Entry $name) | ForEach-Object {
                if ($_ -and -not $dllPaths.Contains($_)) { $dllPaths.Add($_) | Out-Null }
            }
        }
    }

    return $dllPaths
}

# =============================================================================
# Business Central Integration
# =============================================================================

function New-BCLaunchConfig {
    <#
    .SYNOPSIS
        Create minimal launch configuration for non-interactive BC operations
    .DESCRIPTION
        Creates a simplified launch configuration for publishing and testing.
        Removes interactive debugging settings (startupObjectId, breakpoints, browser launch).
    .PARAMETER ServerUrl
        Business Central server URL (e.g., http://bctest)
    .PARAMETER ServerInstance
        Business Central server instance name (e.g., BC)
    .PARAMETER Tenant
        BC tenant name (defaults to 'default')
    .OUTPUTS
        Hashtable with launch configuration for non-interactive operations
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServerUrl,

        [Parameter(Mandatory=$true)]
        [string]$ServerInstance,

        [string]$Tenant = 'default'
    )

    return @{
        name = "Publish: $ServerUrl"
        type = 'al'
        request = 'launch'
        environmentType = 'OnPrem'
        server = $ServerUrl
        serverInstance = $ServerInstance
        authentication = 'UserPassword'
        tenant = $Tenant
        usePublicURLFromServer = $true
    }
}

function Get-BCCredential {
    <#
    .SYNOPSIS
        Create PSCredential object for BC authentication
    .PARAMETER Username
        BC username (typically 'admin' for local containers)
    .PARAMETER Password
        BC password (plain text - non-secret for local dev environments)
    .OUTPUTS
        PSCredential object
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(Mandatory=$true)]
        [string]$Password
    )

    $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($Username, $securePassword)
}

function Get-BCContainerName {
    <#
    .SYNOPSIS
        Resolve BC container name from launch config or environment
    .PARAMETER LaunchConfig
        Launch configuration object (optional)
    .OUTPUTS
        Container name string
    #>
    param(
        [object]$LaunchConfig = $null
    )

    # Try to extract from launch config server URL
    if ($LaunchConfig -and $LaunchConfig.server) {
        $serverUrl = $LaunchConfig.server
        # Extract hostname from URL (e.g., http://bctest -> bctest)
        if ($serverUrl -match '://([^:/]+)') {
            return $matches[1]
        }
    }

    # Fallback to environment variable
    if ($env:ALBT_BC_CONTAINER_NAME) {
        return $env:ALBT_BC_CONTAINER_NAME
    }

    # Final fallback to default
    return 'bctest'
}

function Import-BCContainerHelper {
    <#
    .SYNOPSIS
        Import BcContainerHelper PowerShell module
    .DESCRIPTION
        Centralized import of BcContainerHelper with error handling and validation.
        Provides helpful error messages if the module is not installed.
    #>
    [CmdletBinding()]
    param()

    if (Get-Module -Name BcContainerHelper -ListAvailable) {
        Import-Module BcContainerHelper -DisableNameChecking -Force -ErrorAction Stop
        Write-BuildMessage -Type Detail -Message "BcContainerHelper module loaded"
    } else {
        Write-BuildMessage -Type Error -Message "BcContainerHelper PowerShell module not found."
        Write-BuildMessage -Type Detail -Message "Install from: Install-Module BcContainerHelper -Scope CurrentUser"
        Write-BuildMessage -Type Detail -Message "Or see: https://github.com/microsoft/navcontainerhelper"
        throw "BcContainerHelper module is required for BC container operations."
    }
}

# =============================================================================
# Module Exports
# =============================================================================

Export-ModuleMember -Function @(
    # Exit Codes
    'Get-ExitCode'

    # Path Utilities
    'Expand-FullPath'
    'ConvertTo-SafePathSegment'
    'Ensure-Directory'
    'New-TemporaryDirectory'

    # JSON and App Configuration
    'Get-AppJsonPath'
    'Get-SettingsJsonPath'
    'Get-AppJsonObject'
    'Get-SettingsJsonObject'
    'Get-OutputPath'
    'Read-JsonFile'
    'Resolve-AppJsonPath'

    # Cache Management
    'Get-ToolCacheRoot'
    'Get-SymbolCacheRoot'
    'Get-LatestCompilerInfo'
    'Get-SymbolCacheInfo'

    # Standardized Output (recommended for all scripts)
    'Write-BuildMessage'
    'Write-BuildHeader'
    'Write-TaskHeader'

    # Legacy Formatting Helpers (deprecated - use Write-BuildMessage instead)
    'Write-Section'
    'Write-InfoLine'
    'Write-StatusLine'
    'Write-ListItem'

    # Analyzer Utilities
    'Test-AnalyzerDependencies'
    'Get-EnabledAnalyzerPath'

    # Business Central Integration
    'New-BCLaunchConfig'
    'Get-BCCredential'
    'Get-BCContainerName'
    'Import-BCContainerHelper'
)
