
# Windows Build Script
param([string]$AppDir = "app")
# Import shared libraries (must be at the very top)
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\json-parser.ps1"

# Diagnostic: Confirm function availability
if (-not (Get-Command Get-EnabledAnalyzerPaths -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: Get-EnabledAnalyzerPaths is not available after import!"
    exit 1
}


# Discover AL compiler
$alcPath = Get-ALCompilerPath $AppDir
if (-not $alcPath) {
    Write-Error "AL Compiler not found. Please ensure AL extension is installed in VS Code."
    exit 1
}

# Get enabled analyzer DLL paths
$analyzerPaths = Get-EnabledAnalyzerPaths $AppDir


# Get output and package cache paths
$outputFullPath = Get-OutputPath $AppDir
if (-not $outputFullPath) {
    Write-Error "[ERROR] Output path could not be determined. Check app.json and Get-OutputPath function."
    exit 1
}
$packageCachePath = Get-PackageCachePath $AppDir
if (-not $packageCachePath) {
    Write-Error "[ERROR] Package cache path could not be determined."
    exit 1
}


if (Test-Path $outputFullPath -PathType Leaf) {
    try {
        Remove-Item $outputFullPath -Force
    } catch {
        Write-Error "[ERROR] Failed to remove ${outputFullPath}: $($_.Exception.Message)"
        exit 1
    }
} else {
}
# Also check and remove any directory with the same name as the output file
if (Test-Path $outputFullPath -PathType Container) {
    try {
        Remove-Item $outputFullPath -Recurse -Force
    } catch {
        Write-Error "[ERROR] Failed to remove conflicting directory ${outputFullPath}: $($_.Exception.Message)"
        exit 1
    }
}
# List contents of output directory after removal

Write-Output "Building $appName v$appVersion..."
if ($analyzerPaths.Count -gt 0) {
    Write-Output "Using analyzers from settings.json:"
    $analyzerPaths | ForEach-Object { Write-Output "  - $_" }
    Write-Output ""
} else {
    Write-Output "No analyzers found or enabled in settings.json"
    Write-Output ""
}



# Build analyzer arguments correctly
$cmdArgs = @("/project:$AppDir", "/out:$outputFullPath", "/packagecachepath:$packageCachePath", "/parallel+")

# Optional: pass ruleset if specified and the file exists and is non-empty
$rulesetPath = $env:RULESET_PATH
if ($rulesetPath) {
    $rsItem = Get-Item -LiteralPath $rulesetPath -ErrorAction SilentlyContinue
    if ($rsItem -and $rsItem.Length -gt 0) {
        Write-Output "Using ruleset: $($rsItem.FullName)"
        $cmdArgs += "/ruleset:$($rsItem.FullName)"
    } else {
        Write-Warning "Ruleset not found or empty, skipping: $rulesetPath"
    }
}
if ($analyzerPaths.Count -gt 0) {
    foreach ($analyzer in $analyzerPaths) {
        $cmdArgs += "/analyzer:$analyzer"
    }
}

# Optional: treat warnings as errors when requested via environment variable
if ($env:WARN_AS_ERROR -and ($env:WARN_AS_ERROR -eq '1' -or $env:WARN_AS_ERROR -match '^(?i:true|yes|on)$')) {
    $cmdArgs += '/warnaserror+'
}

& $alcPath @cmdArgs
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Output ""
    Write-Error "Build failed with errors above."
} else {
    Write-Output ""
    Write-Output "Build completed successfully: $outputFile"
}

exit $exitCode
# ...implementation to be added...
