
# Windows Build Script
param([string]$AppDir = "app")
# Resolve $AppDir to its full path
$ResolvedAppDir = (Resolve-Path $AppDir).Path
# Import shared libraries (must be at the very top)
. "$PSScriptRoot\lib\common.ps1"
. "$PSScriptRoot\lib\json-parser.ps1"

# Diagnostic: Confirm function availability
if (-not (Get-Command Get-EnabledAnalyzerPaths -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Get-EnabledAnalyzerPaths is not available after import!" -ForegroundColor Red
    exit 1
}


# Discover AL compiler
$alcPath = Get-ALCompilerPath $ResolvedAppDir
if (-not $alcPath) {
    Write-Host "AL Compiler not found. Please ensure AL extension is installed in VS Code." -ForegroundColor Red
    exit 1
}

# Get enabled analyzer DLL paths
$analyzerPaths = Get-EnabledAnalyzerPaths $ResolvedAppDir


# Get output and package cache paths
$outputFullPath = Get-OutputPath $ResolvedAppDir
if (-not $outputFullPath) {
    Write-Host "[ERROR] Output path could not be determined. Check app.json and Get-OutputPath function." -ForegroundColor Red
    exit 1
}
$packageCachePath = Get-PackageCachePath $ResolvedAppDir
if (-not $packageCachePath) {
    Write-Host "[ERROR] Package cache path could not be determined." -ForegroundColor Red
    exit 1
}


if (Test-Path $outputFullPath -PathType Leaf) {
    try {
        Remove-Item $outputFullPath -Force
    } catch {
        Write-Host "[ERROR] Failed to remove ${outputFullPath}: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
}
# Also check and remove any directory with the same name as the output file
if (Test-Path $outputFullPath -PathType Container) {
    try {
        Remove-Item $outputFullPath -Recurse -Force
    } catch {
        Write-Host "[ERROR] Failed to remove conflicting directory ${outputFullPath}: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
# List contents of output directory after removal

Write-Host "Building $appName v$appVersion..."
if ($analyzerPaths.Count -gt 0) {
    Write-Host "Using analyzers from settings.json:"
    $analyzerPaths | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
} else {
    Write-Host "No analyzers found or enabled in settings.json"
    Write-Host ""
}



# Build analyzer arguments correctly
$cmdArgs = @("/project:$ResolvedAppDir", "/out:$outputFullPath", "/packagecachepath:$packageCachePath")
if ($analyzerPaths.Count -gt 0) {
    foreach ($analyzer in $analyzerPaths) {
        $cmdArgs += "/analyzer:$analyzer"
    }
}

& $alcPath @cmdArgs
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host ""; Write-Host "Build failed with errors above." -ForegroundColor Red
} else {
    Write-Host ""; Write-Host "Build completed successfully: $outputFile" -ForegroundColor Green
}

exit $exitCode
# ...implementation to be added...
