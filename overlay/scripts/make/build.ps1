#requires -Version 7.2

<#
.SYNOPSIS
    Build AL project with comprehensive status reporting and modern terminal output.

.DESCRIPTION
    Compiles the AL project using the provisioned compiler and symbols, with detailed
    progress tracking, analyzer configuration, and structured error reporting.

.PARAMETER AppDir
    Directory containing the AL project files and app.json

.NOTES
    This script uses the standardized Write-BuildMessage and Write-BuildHeader functions
    from common.psm1 to ensure consistent output formatting across all build scripts.
#>

# PSScriptAnalyzer suppressions for intentional design choices
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseBOMForUnicodeEncodedFile', '', Justification = 'UTF-8 without BOM is preferred for cross-platform compatibility')]
param([string]$AppDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Import shared utilities
Import-Module "$PSScriptRoot/../common.psm1" -Force -DisableNameChecking

$Exit = Get-ExitCode

# Guard: require invocation via make
if (-not $env:ALBT_VIA_MAKE) {
    Write-Output "Run via make (e.g., make build)"
    exit $Exit.Guard
}


Write-BuildHeader 'Project Analysis'

Write-BuildMessage -Type Step -Message "Analyzing project manifest (app.json)..."
$appJson = Get-AppJsonObject $AppDir
if (-not $appJson) {
    Write-BuildMessage -Type Error -Message "app.json not found or invalid"
    Write-BuildMessage -Type Error -Message "Ensure the project manifest exists before building"
    Write-Error "app.json not found or invalid under '$AppDir'. Ensure the project manifest exists before building."
    exit $Exit.GeneralError
}

$appName = if ($appJson -and $appJson.name) { $appJson.name } else { 'Unknown App' }
$appVersion = if ($appJson -and $appJson.version) { $appJson.version } else { '1.0.0.0' }
$appPublisher = if ($appJson -and $appJson.publisher) { $appJson.publisher } else { 'Unknown' }

Write-BuildMessage -Type Success -Message "Found valid app.json"
Write-BuildMessage -Type Detail -Message "App Name: $appName"
Write-BuildMessage -Type Detail -Message "Version: $appVersion"
Write-BuildMessage -Type Detail -Message "Publisher: $appPublisher"

Write-BuildHeader 'Compiler Discovery'

Write-BuildMessage -Type Step -Message "Resolving AL compiler..."
Write-BuildMessage -Type Detail -Message "Source: Provisioned tool (latest)"

try {
    $compilerInfo = Get-LatestCompilerInfo

    $alcPath = $compilerInfo.AlcPath
    $compilerVersion = if ($compilerInfo.Version) { $compilerInfo.Version } else { $null }
    $compilerRoot = Split-Path -Parent $alcPath

    Write-BuildMessage -Type Success -Message "Found latest compiler"
} catch {
    Write-BuildMessage -Type Error -Message "Compiler not found"
    Write-BuildMessage -Type Error -Message $_.Exception.Message
    Write-Error $_.Exception.Message
    exit $Exit.MissingTool
}

$displayVersion = if ($compilerVersion) { $compilerVersion } else { "(unknown)" }
Write-BuildMessage -Type Detail -Message "Version: $displayVersion"
Write-BuildMessage -Type Detail -Message "Path: $alcPath"

Write-BuildMessage -Type Step -Message "Configuring execution setup..."

# Normalize invocation path for cross-platform execution
$alcCommand = $alcPath
$alcLaunchPath = $alcPath
$alcPreArgs = @()

if (-not $IsWindows) {
    $alcDir = Split-Path -Parent $alcPath
    $dllCandidate = Join-Path -Path $alcDir -ChildPath 'alc.dll'

    if (Test-Path -LiteralPath $dllCandidate) {
        $alcLaunchPath = (Get-Item -LiteralPath $dllCandidate).FullName
        $alcCommand = 'dotnet'
        $alcPreArgs = @($alcLaunchPath)
        Write-BuildMessage -Type Detail -Message "Host: dotnet (via alc.dll)"
    } elseif ([IO.Path]::GetExtension($alcPath) -eq '.dll') {
        $alcLaunchPath = (Get-Item -LiteralPath $alcPath).FullName
        $alcCommand = 'dotnet'
        $alcPreArgs = @($alcLaunchPath)
        Write-BuildMessage -Type Detail -Message "Host: dotnet (direct dll)"
    } elseif ([IO.Path]::GetExtension($alcPath) -eq '.exe') {
        $alcLaunchPath = $alcPath
        $alcCommand = 'dotnet'
        $alcPreArgs = @($alcLaunchPath)
        Write-BuildMessage -Type Detail -Message "Host: dotnet (exe wrapper)"
    }
} else {
    Write-BuildMessage -Type Detail -Message "Host: native executable"
}

Write-BuildMessage -Type Detail -Message "Launch Path: $alcLaunchPath"

Write-BuildHeader 'Symbol Cache Resolution'

Write-BuildMessage -Type Step -Message "Resolving symbol cache..."
try {
    $symbolCacheInfo = Get-SymbolCacheInfo -AppJson $appJson
    Write-BuildMessage -Type Success -Message "Symbol cache found"
    $packageCount = 0
    if ($symbolCacheInfo.Manifest -and $symbolCacheInfo.Manifest.packages) {
        $packageNode = $symbolCacheInfo.Manifest.packages
        if ($packageNode -is [System.Collections.IDictionary]) {
            $packageCount = $packageNode.Count
        } elseif ($packageNode.PSObject) {
            $packageCount = @($packageNode.PSObject.Properties).Count
        }
    }
    Write-BuildMessage -Type Detail -Message "Packages: $packageCount available"
    Write-BuildMessage -Type Detail -Message "Path: $($symbolCacheInfo.CacheDir)"
} catch {
    Write-BuildMessage -Type Error -Message "Symbol cache not found"
    Write-BuildMessage -Type Error -Message $_.Exception.Message
    Write-Error $_.Exception.Message
    exit $Exit.MissingTool
}
$packageCachePath = $symbolCacheInfo.CacheDir

Write-BuildHeader 'Analyzer Configuration'

Write-BuildMessage -Type Step -Message "Configuring code analyzers..."
$analyzerPaths = Get-EnabledAnalyzerPath -AppDir $AppDir -CompilerDir $compilerRoot

# Filter out empty or non-existent analyzer paths (parity with Linux)
$filteredAnalyzers = New-Object System.Collections.Generic.List[string]
foreach ($p in $analyzerPaths) {
    if ($p -and (Test-Path $p -PathType Leaf)) { [void]$filteredAnalyzers.Add($p) }
}

if ($filteredAnalyzers.Count -gt 0) {
    Write-BuildMessage -Type Success -Message "$($filteredAnalyzers.Count) analyzers found"
    Write-BuildMessage -Type Info -Message "Configured analyzers:"
    $filteredAnalyzers | ForEach-Object {
        $fileName = Split-Path $_ -Leaf
        Write-BuildMessage -Type Detail -Message $fileName
    }
} else {
    Write-BuildMessage -Type Warning -Message "No analyzers configured"
    Write-BuildMessage -Type Info -Message "Consider enabling analyzers in .vscode/settings.json"
}

Write-BuildHeader 'Output Configuration'

Write-BuildMessage -Type Step -Message "Configuring build output..."
$outputFullPath = Get-OutputPath $AppDir
if (-not $outputFullPath) {
    Write-BuildMessage -Type Error -Message "Could not determine output path"
    Write-BuildMessage -Type Error -Message "Verify the manifest and rerun the provisioning targets"
    Write-Error "[ERROR] Output path could not be determined from app.json. Verify the manifest and rerun the provisioning targets."
    exit $Exit.GeneralError
}

$outputFile = Split-Path -Path $outputFullPath -Leaf
Write-BuildMessage -Type Detail -Message "Target File: $outputFile"
Write-BuildMessage -Type Detail -Message "Full Path: $outputFullPath"

Write-BuildHeader 'Pre-Build Cleanup'

Write-BuildMessage -Type Step -Message "Cleaning up previous build artifacts..."
$cleanupActions = 0

if (Test-Path $outputFullPath -PathType Leaf) {
    try {
        Remove-Item $outputFullPath -Force
        Write-BuildMessage -Type Info -Message "Removed previous build artifact (file)"
        $cleanupActions++
    } catch {
        Write-BuildMessage -Type Error -Message "Failed to remove existing file"
        Write-BuildMessage -Type Error -Message "Failed to remove ${outputFullPath}: $($_.Exception.Message)"
        Write-Error "[ERROR] Failed to remove ${outputFullPath}: $($_.Exception.Message)"
        exit 1
    }
}

if (Test-Path $outputFullPath -PathType Container) {
    try {
        Remove-Item $outputFullPath -Recurse -Force
        Write-BuildMessage -Type Info -Message "Removed conflicting directory"
        $cleanupActions++
    } catch {
        Write-BuildMessage -Type Error -Message "Failed to remove conflicting directory"
        Write-BuildMessage -Type Error -Message "Failed to remove conflicting directory ${outputFullPath}: $($_.Exception.Message)"
        Write-Error "[ERROR] Failed to remove conflicting directory ${outputFullPath}: $($_.Exception.Message)"
        exit 1
    }
}

if ($cleanupActions -eq 0) {
    Write-BuildMessage -Type Success -Message "No cleanup needed"
} else {
    Write-BuildMessage -Type Success -Message "$cleanupActions items cleaned"
}

Write-BuildHeader "Compilation - $appName v$appVersion"

Write-BuildMessage -Type Step -Message "Preparing compiler arguments..."

# Build analyzer arguments correctly
# Ensure all paths are absolute for the compiler
$absoluteAppDir = (Resolve-Path -Path $AppDir).Path
# Convert output path to absolute path - required by AL compiler's /out parameter
# (relative paths may cause compilation failures or incorrect output locations)
$absoluteOutputPath = [System.IO.Path]::GetFullPath($outputFullPath)
$cmdArgs = @("/project:$absoluteAppDir", "/out:$absoluteOutputPath", "/packagecachepath:$packageCachePath", "/parallel+", "/maxdegreeofparallelism:12")

Write-BuildMessage -Type Detail -Message "Project Dir: $AppDir"
Write-BuildMessage -Type Detail -Message "Output File: $outputFile"
Write-BuildMessage -Type Detail -Message "Symbol Cache: $packageCachePath"
Write-BuildMessage -Type Detail -Message "Parallel: Enabled (12 cores)"

# Optional: pass ruleset if specified and the file exists and is non-empty
$rulesetPath = $env:RULESET_PATH
if ($rulesetPath) {
    $rsItem = Get-Item -LiteralPath $rulesetPath -ErrorAction SilentlyContinue
    if ($rsItem -and $rsItem.Length -gt 0) {
        Write-BuildMessage -Type Detail -Message "Ruleset: $($rsItem.Name)"
        $cmdArgs += "/ruleset:$($rsItem.FullName)"
    } else {
        Write-BuildMessage -Type Warning -Message "Ruleset not found or empty: $rulesetPath"
    }
} else {
    Write-BuildMessage -Type Detail -Message "Ruleset: None specified"
}

if ($filteredAnalyzers.Count -gt 0) {
    Write-BuildMessage -Type Detail -Message "Analyzers: $($filteredAnalyzers.Count) configured"
    foreach ($analyzer in $filteredAnalyzers) {
        $cmdArgs += "/analyzer:$analyzer"
    }
} else {
    Write-BuildMessage -Type Detail -Message "Analyzers: None configured"
}

# Optional: treat warnings as errors when requested via environment variable
if ($env:WARN_AS_ERROR -and ($env:WARN_AS_ERROR -eq '1' -or $env:WARN_AS_ERROR -match '^(?i:true|yes|on)$')) {
    Write-BuildMessage -Type Warning -Message "Warnings will be treated as errors"
    $cmdArgs += '/warnaserror+'
} else {
    Write-BuildMessage -Type Detail -Message "Warnings: Allowed"
}

Write-BuildMessage -Type Step -Message "Executing compilation..."
$alcInvokeArgs = @()
if ($alcPreArgs.Count -gt 0) { $alcInvokeArgs += $alcPreArgs }
$alcInvokeArgs += $cmdArgs

$startTime = Get-Date
Write-BuildMessage -Type Detail -Message "Compiler: $alcCommand"
Write-BuildMessage -Type Detail -Message "Started: $($startTime.ToString('HH:mm:ss'))"

# Execute the compiler from its own directory to ensure analyzer dependencies are resolved correctly
$currentLocation = Get-Location
try {
    if ($compilerRoot -and (Test-Path -LiteralPath $compilerRoot)) {
        Set-Location -LiteralPath $compilerRoot
        Write-Information "[albt] Set working directory to compiler root: $compilerRoot" -InformationAction Continue
    }
    & $alcCommand @alcInvokeArgs
    $exitCode = $LASTEXITCODE
} finally {
    Set-Location $currentLocation.Path
}

$endTime = Get-Date
$duration = $endTime - $startTime

Write-BuildHeader 'Build Results'

Write-BuildMessage -Type Info -Message "Compilation completed"
Write-BuildMessage -Type Detail -Message "Duration: $("{0:mm\:ss\.fff}" -f $duration)"
Write-BuildMessage -Type Detail -Message "Exit Code: $exitCode"

if ($exitCode -ne 0) {
    Write-BuildMessage -Type Error -Message "Build compilation failed"

    Write-BuildHeader 'Summary'
    Write-BuildMessage -Type Error -Message "Build compilation failed"
    Write-BuildMessage -Type Info -Message "Review the error messages above and fix the reported issues"
    exit $Exit.Analysis
} else {
    Write-BuildMessage -Type Success -Message "Compilation succeeded"

    # Check if output file was actually created
    if (Test-Path $outputFullPath -PathType Leaf) {
        $outputInfo = Get-Item -LiteralPath $outputFullPath
        $fileSize = if ($outputInfo.Length -lt 1024) {
            "{0} bytes" -f $outputInfo.Length
        } elseif ($outputInfo.Length -lt 1048576) {
            "{0:N1} KB" -f ($outputInfo.Length / 1024)
        } else {
            "{0:N1} MB" -f ($outputInfo.Length / 1048576)
        }
        Write-BuildMessage -Type Detail -Message "Output Size: $fileSize"
        Write-BuildMessage -Type Detail -Message "Output File: $outputFile"
    }

    Write-BuildHeader 'Summary'
    Write-BuildMessage -Type Success -Message "Build completed successfully!"
    Write-BuildMessage -Type Info -Message "Application package is ready for deployment"
}

exit $Exit.Success
# ...implementation to be added...
