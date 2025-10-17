#requires -Version 7.2

<#
.SYNOPSIS
    Display comprehensive AL project configuration information with structured formatting.

.DESCRIPTION
    Shows application configuration, compiler status, symbol cache status, and environment
    details in a structured format suitable for both interactive display and automation.

.PARAMETER AppDir
    Directory containing app.json (passed from al.build.ps1)

.PARAMETER TestDir
    Directory containing test app.json (optional, passed from al.build.ps1)

.NOTES
    This script uses standardized output functions from common.psm1 for consistent
    formatting across the build system.
#>

# PSScriptAnalyzer suppressions for intentional design choices
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM is preferred for cross-platform compatibility')]
param(
    [Parameter(Mandatory = $true)]
    [string]$AppDir,

    [Parameter(Mandatory = $false)]
    [string]$TestDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Import shared utilities
Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking

$Exit = Get-ExitCode

# Guard: require invocation via Invoke-Build orchestration
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via Invoke-Build (e.g., Invoke-Build show-config)"
    exit $Exit.Guard
}

Write-BuildHeader 'Application Configuration'

$appJson = Get-AppJsonObject $AppDir
if ($appJson) {
    Write-BuildMessage -Type Info -Message "APPLICATION MANIFEST:"
    Write-BuildMessage -Type Detail -Message "Name: $($appJson.name)"
    Write-BuildMessage -Type Detail -Message "Publisher: $($appJson.publisher)"
    Write-BuildMessage -Type Detail -Message "Version: $($appJson.version)"
} else {
    Write-BuildMessage -Type Error -Message "app.json not found or invalid"
}

Write-BuildHeader 'VS Code Configuration'

$settingsJson = Get-SettingsJsonObject $AppDir
if ($settingsJson) {
    Write-BuildMessage -Type Info -Message "VSCODE SETTINGS (MAIN APP):"
    if (($settingsJson.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $settingsJson.'al.codeAnalyzers' -and $settingsJson.'al.codeAnalyzers'.Count -gt 0) {
        $analyzerCount = $settingsJson.'al.codeAnalyzers'.Count
        Write-BuildMessage -Type Detail -Message "Analyzers: $analyzerCount configured"
        foreach ($analyzer in $settingsJson.'al.codeAnalyzers') {
            Write-BuildMessage -Type Detail -Message "  → $analyzer"
        }
    } else {
        Write-BuildMessage -Type Detail -Message "Analyzers: (none configured)"
    }
} else {
    Write-BuildMessage -Type Warning -Message ".vscode/settings.json not found or invalid"
}

# Test App Configuration (if available)
$testAppJson = $null
if ($TestDir) {
    $testAppJsonPath = Join-Path $TestDir 'app.json'
    if (Test-Path -LiteralPath $testAppJsonPath) {
        $testAppJson = Get-AppJsonObject $TestDir

        Write-BuildHeader 'Test Application Configuration'

        if ($testAppJson) {
            Write-BuildMessage -Type Info -Message "TEST APP MANIFEST:"
            Write-BuildMessage -Type Detail -Message "Name: $($testAppJson.name)"
            Write-BuildMessage -Type Detail -Message "Publisher: $($testAppJson.publisher)"
            Write-BuildMessage -Type Detail -Message "Version: $($testAppJson.version)"
        } else {
            Write-BuildMessage -Type Error -Message "Test app.json not found or invalid"
        }

        $testSettingsJson = Get-SettingsJsonObject $TestDir
        if ($testSettingsJson) {
            Write-BuildMessage -Type Info -Message "VSCODE SETTINGS (TEST APP):"
            if (($testSettingsJson.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $testSettingsJson.'al.codeAnalyzers' -and $testSettingsJson.'al.codeAnalyzers'.Count -gt 0) {
                $analyzerCount = $testSettingsJson.'al.codeAnalyzers'.Count
                Write-BuildMessage -Type Detail -Message "Analyzers: $analyzerCount configured"
                foreach ($analyzer in $testSettingsJson.'al.codeAnalyzers') {
                    Write-BuildMessage -Type Detail -Message "  → $analyzer"
                }
            } else {
                Write-BuildMessage -Type Detail -Message "Analyzers: (none configured)"
            }
        } else {
            Write-BuildMessage -Type Detail -Message "Test app: .vscode/settings.json not found (using main app settings)"
        }
    }
}

$compilerPathValue = '(missing)'
$compilerVersionValue = '(missing)'
$compilerSentinelValue = '(missing)'
$symbolCacheValue = '(missing)'
$symbolManifestValue = '(missing)'

$alcPath = $null
$compilerVersion = $null
$compilerSentinel = $null
$compilerWarning = $null

try {
    $compilerInfo = Get-LatestCompilerInfo
    if ($compilerInfo) {
        $alcPath = $compilerInfo.AlcPath
        $compilerVersion = $compilerInfo.Version
        $compilerSentinel = $compilerInfo.SentinelPath
    }
} catch {
    $compilerWarning = $_.Exception.Message
}

Write-BuildHeader 'Compiler Provisioning'

if ($alcPath) {
    Write-BuildMessage -Type Info -Message "COMPILER STATUS:"
    Write-BuildMessage -Type Detail -Message "Status: Ready (latest-only)"
    if ($compilerVersion) {
        Write-BuildMessage -Type Detail -Message "Version: $compilerVersion"
    } else {
        Write-BuildMessage -Type Detail -Message "Version: (unknown)"
    }
    Write-BuildMessage -Type Detail -Message "Path: $alcPath"
    if ($compilerSentinel) {
        Write-BuildMessage -Type Detail -Message "Sentinel: $compilerSentinel"
    }
    $compilerPathValue = $alcPath
    $compilerVersionValue = if ($compilerVersion) { $compilerVersion } else { '(unknown)' }
    $compilerSentinelValue = if ($compilerSentinel) { $compilerSentinel } else { '(missing)' }
} elseif ($compilerWarning) {
    Write-BuildMessage -Type Info -Message "COMPILER STATUS:"
    Write-BuildMessage -Type Error -Message $compilerWarning
} else {
    Write-BuildMessage -Type Info -Message "COMPILER STATUS:"
    Write-BuildMessage -Type Error -Message "Compiler provisioning info unavailable. Run 'Invoke-Build download-compiler'"
}

$symbolCacheInfo = $null
$symbolWarning = $null
if ($appJson) {
    try {
        $symbolCacheInfo = Get-SymbolCacheInfo -AppJson $appJson
    } catch {
        $symbolWarning = $_.Exception.Message
    }
}

Write-BuildHeader 'Symbol Cache Status'

if ($symbolCacheInfo) {
    Write-BuildMessage -Type Info -Message "SYMBOLS STATUS:"
    Write-BuildMessage -Type Detail -Message "Status: Ready"
    if ($symbolCacheInfo.Manifest -and $symbolCacheInfo.Manifest.packages) {
        $packageNode = $symbolCacheInfo.Manifest.packages
        $count = 0
        if ($packageNode -is [System.Collections.IDictionary]) {
            $count = $packageNode.Count
        } elseif ($packageNode.PSObject) {
            $count = @($packageNode.PSObject.Properties).Count
        }
        Write-BuildMessage -Type Detail -Message "Packages: $count cached"
    }
    Write-BuildMessage -Type Detail -Message "Directory: $($symbolCacheInfo.CacheDir)"
    Write-BuildMessage -Type Detail -Message "Manifest: $($symbolCacheInfo.ManifestPath)"
    $symbolCacheValue = $symbolCacheInfo.CacheDir
    $symbolManifestValue = $symbolCacheInfo.ManifestPath
} elseif ($symbolWarning) {
    Write-BuildMessage -Type Info -Message "SYMBOLS STATUS:"
    Write-BuildMessage -Type Error -Message $symbolWarning
} elseif ($appJson) {
    Write-BuildMessage -Type Info -Message "SYMBOLS STATUS:"
    Write-BuildMessage -Type Error -Message "Symbol cache info unavailable. Run 'Invoke-Build download-symbols'"
}

# Normalized deterministic key=value section (T010)
# This block is additive to keep backward compatibility with existing consumers/tests.
try {
    $platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } elseif ($IsLinux) { 'Linux' } else { ($PSVersionTable.Platform ?? 'Unknown') }
} catch { $platform = 'Unknown' }

$psver = try { $PSVersionTable.PSVersion.ToString() } catch { ($PSVersionTable.PSVersion.Major.ToString()) }

$appName = if ($appJson) { "$($appJson.name)" } else { '(missing)' }
$appPublisher = if ($appJson) { "$($appJson.publisher)" } else { '(missing)' }
$appVersion = if ($appJson) { "$($appJson.version)" } else { '(missing)' }

$testAppName = if ($testAppJson) { "$($testAppJson.name)" } else { '(none)' }
$testAppPublisher = if ($testAppJson) { "$($testAppJson.publisher)" } else { '(none)' }
$testAppVersion = if ($testAppJson) { "$($testAppJson.version)" } else { '(none)' }

$analyzersList = '(none)'
if ($settingsJson) {
    if (($settingsJson.PSObject.Properties.Match('al.codeAnalyzers').Count -gt 0) -and $settingsJson.'al.codeAnalyzers' -and $settingsJson.'al.codeAnalyzers'.Count -gt 0) {
        $analyzersList = ($settingsJson.'al.codeAnalyzers' | ForEach-Object { $_.ToString() }) -join ', '
    } else {
        $analyzersList = '(none)'
    }
} else {
    # Treat missing settings as no analyzers configured for normalized view
    $analyzersList = '(none)'
}

Write-BuildHeader 'System Environment'

Write-BuildMessage -Type Info -Message "PLATFORM INFO:"
Write-BuildMessage -Type Detail -Message "Platform: $platform"
Write-BuildMessage -Type Detail -Message "PowerShell: $psver"

Write-BuildHeader 'Configuration Summary'

Write-BuildMessage -Type Info -Message "NORMALIZED CONFIGURATION:"
Write-BuildMessage -Type Detail -Message "Machine-readable format for integration and debugging:"

# Emit in fixed, deterministic order
$normalized = [ordered]@{
    'App.Name'           = $appName
    'App.Publisher'      = $appPublisher
    'App.Version'        = $appVersion
    'TestApp.Name'       = $testAppName
    'TestApp.Publisher'  = $testAppPublisher
    'TestApp.Version'    = $testAppVersion
    'Platform'           = $platform
    'PowerShellVersion'  = $psver
    'Settings.Analyzers' = $analyzersList
    'Compiler.Path'      = $compilerPathValue
    'Compiler.Version'   = $compilerVersionValue
    'Compiler.Sentinel'  = $compilerSentinelValue
    'Symbols.Cache'      = $symbolCacheValue
    'Symbols.Manifest'   = $symbolManifestValue
}

foreach ($k in $normalized.Keys) {
    $value = $normalized[$k]
    $displayValue = if ($value.Length -gt 80) { $value.Substring(0, 77) + "..." } else { $value }
    Write-BuildMessage -Type Detail -Message "$k=$displayValue"
}

Write-Host ""
Write-BuildMessage -Type Success -Message "Configuration review complete!"
exit $Exit.Success
