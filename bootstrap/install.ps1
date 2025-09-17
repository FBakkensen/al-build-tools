#requires -Version 7.0
param(
    [string]$Url = 'https://github.com/FBakkensen/al-build-tools',
    [string]$Ref = 'main',
    [string]$Dest = '.',
    [string]$Source = 'overlay'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Check for unknown parameters by inspecting command line arguments
if ($args.Count -gt 0) {
    $firstArg = $args[0]
    $argName = if ($firstArg.StartsWith('-')) { $firstArg.Substring(1) } else { $firstArg }
    Write-Host "[install] guard UnknownParameter argument=`"$argName`""
    Write-Host "Usage: Install-AlBuildTools [-Url <url>] [-Ref <ref>] [-Dest <path>] [-Source <folder>]"
    throw "Unknown parameter: $firstArg"
}

function Write-Note($msg) { Write-Host "[al-build-tools] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[ok] $msg" -ForegroundColor Green }
function Write-Warn2($m)  { Write-Warning $m }
function Write-Step($n, $msg) { Write-Host ("[{0}] {1}" -f $n, $msg) }

function Install-AlBuildTools {
    [CmdletBinding()]
    param(
        [string]$Url = 'https://github.com/FBakkensen/al-build-tools',
        [string]$Ref = 'main',
        [string]$Dest = '.',
        [string]$Source = 'overlay'
    )

    # Check PowerShell version requirement
    if ($PSVersionTable.PSVersion -lt [System.Version]'7.0') {
        Write-Host "[install] guard PowerShellVersionUnsupported"
        throw "PowerShell 7.0 or higher required. Current version: $($PSVersionTable.PSVersion)"
    }

    $startTime = Get-Date
    $step = 0
    $step++; Write-Step $step "Resolve destination"
    try {
        $destFull = (Resolve-Path -Path $Dest -ErrorAction Stop).Path
    } catch {
        # Create the destination if it does not exist, then resolve the actual path
        $created = New-Item -ItemType Directory -Force -Path $Dest
        $destFull = (Resolve-Path -Path $created.FullName).Path
    }
    Write-Note "Install/update from $Url@$Ref into $destFull (source: $Source)"

    $step++; Write-Step $step "Detect git repository"
    $gitOk = $false
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = 'git'
        $pinfo.Arguments = "-C `"$destFull`" rev-parse --git-dir"
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $p.WaitForExit()
        if ($p.ExitCode -eq 0) { $gitOk = $true }
    } catch {
        Write-Verbose "[install] git check failed: $($_.Exception.Message)"
    }
    if (-not $gitOk -and -not (Test-Path (Join-Path $destFull '.git'))) {
        Write-Host "[install] guard GitRepoRequired"
        throw "Installation requires a git repository. Initialize with 'git init' first."
    }
    
    # Check working tree cleanliness if this is a git repo
    if ($gitOk -or (Test-Path (Join-Path $destFull '.git'))) {
        try {
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = 'git'
            $pinfo.Arguments = "-C `"$destFull`" status --porcelain"
            $pinfo.RedirectStandardOutput = $true
            $pinfo.RedirectStandardError = $true
            $pinfo.UseShellExecute = $false
            $p = [System.Diagnostics.Process]::Start($pinfo)
            $p.WaitForExit()
            if ($p.ExitCode -eq 0) {
                $statusOutput = $p.StandardOutput.ReadToEnd().Trim()
                if (-not [string]::IsNullOrEmpty($statusOutput)) {
                    Write-Host "[install] guard WorkingTreeNotClean"
                    throw "Working tree must be clean. Commit or stash changes first."
                }
            }
        } catch {
            Write-Verbose "[install] working tree check failed: $($_.Exception.Message)"
        }
    }
    Write-Ok "Working in: $destFull"

    $tmp = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName()))
    Write-Host "[install] temp workspace=`"$($tmp.FullName)`""
    try {
        $step++; Write-Step $step "Download repository archive"
        $zip = Join-Path $tmp.FullName 'src.zip'
        $base = $Url.TrimEnd('/')
        $tryUrls = @(
            "$base/archive/refs/heads/$Ref.zip",
            "$base/archive/refs/tags/$Ref.zip",
            "$base/archive/$Ref.zip"
        )

        $downloaded = $false
        $lastError = $null
        foreach ($u in $tryUrls) {
            try {
                Write-Note "Downloading: $u"
                Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop
                $downloaded = $true
                break
            } catch {
                $lastError = $_
                continue
            }
        }
        if (-not $downloaded) {
            # Classify the download failure
            $category = 'Unknown'
            if ($lastError) {
                $errorMessage = $lastError.Exception.Message.ToLower()
                if ($errorMessage -match 'network|connection|timeout|unreachable') {
                    $category = 'NetworkUnavailable'
                } elseif ($errorMessage -match '404|not found') {
                    $category = 'NotFound'
                } elseif ($errorMessage -match 'timeout') {
                    $category = 'Timeout'
                } elseif ($errorMessage -match 'corrupt|invalid|archive') {
                    $category = 'CorruptArchive'
                }
            }
            Write-Host "[install] download failure category=$category"
            throw "Failed to download repo archive for ref '$Ref' from $Url."
        }

        $step++; Write-Step $step "Extract and locate '$Source'"
        $extract = Join-Path $tmp.FullName 'x'
        try {
            Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force -ErrorAction Stop
        } catch {
            Write-Host "[install] download failure category=CorruptArchive"
            throw "Failed to extract archive: $($_.Exception.Message)"
        }
        $top = Get-ChildItem -Path $extract -Directory | Select-Object -First 1
        if (-not $top) { 
            Write-Host "[install] download failure category=CorruptArchive"
            throw 'Archive appears empty or unreadable.' 
        }
        $src = Join-Path $top.FullName $Source
        if (-not (Test-Path $src -PathType Container)) {
            # last-chance scan
            $cand = Get-ChildItem -Path $extract -Recurse -Directory -Filter $Source | Select-Object -First 1
            if ($cand) { 
                $src = $cand.FullName 
            } else { 
                Write-Host "[install] download failure category=NotFound"
                throw "Expected subfolder '$Source' not found in archive at ref '$Ref'." 
            }
        }
        
        # Validate extraction completed successfully before proceeding
        if (-not (Get-ChildItem -Path $src -File -ErrorAction SilentlyContinue)) {
            Write-Host "[install] download failure category=CorruptArchive"
            throw "Source directory '$src' contains no files."
        }
        
        Write-Ok "Source directory: $src"

        $step++; Write-Step $step "Copy files into destination"
        
        # Verify all source files would stay within destination boundary
        $overlayFiles = Get-ChildItem -Path $src -Recurse -File
        foreach ($file in $overlayFiles) {
            $relativePath = $file.FullName.Substring($src.Length).TrimStart('\', '/')
            $targetPath = Join-Path $destFull $relativePath
            $resolvedTarget = [System.IO.Path]::GetFullPath($targetPath)
            if (-not $resolvedTarget.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "[install] guard RestrictedWrites"
                throw "File '$relativePath' would write outside destination scope."
            }
        }
        
        $fileCount = (Get-ChildItem -Path $src -Recurse -File | Measure-Object).Count
        $dirCount  = (Get-ChildItem -Path $src -Recurse -Directory | Measure-Object).Count + 1
        try {
            Copy-Item -Path (Join-Path $src '*') -Destination $destFull -Recurse -Force -ErrorAction Stop
        } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            Write-Host "[install] guard PermissionDenied"
            throw "Permission denied copying to destination. Check write access to '$destFull'."
        }
        Write-Ok "Copied $fileCount files across $dirCount directories"

        $endTime = Get-Date
        $durationSeconds = ($endTime - $startTime).TotalSeconds
        Write-Host "[install] success ref=`"$Ref`" overlay=`"$Source`" duration=$($durationSeconds.ToString('F2', [System.Globalization.CultureInfo]::InvariantCulture))"
        Write-Note "Completed: $Source from $Url@$Ref into $destFull"
    } finally {
        try { Remove-Item -Recurse -Force -LiteralPath $tmp.FullName -ErrorAction SilentlyContinue } catch { Write-Verbose "[install] cleanup failed: $($_.Exception.Message)" }
    }
}

# Auto-run only when executed as a script (not dot-sourced),
# and allow tests to disable via ALBT_NO_AUTORUN=1.
# - When dot-sourced, $MyInvocation.InvocationName is '.'
# - When executed via -File or &, InvocationName is the script name/path
if ($PSCommandPath -and ($MyInvocation.InvocationName -ne '.') -and -not $env:ALBT_NO_AUTORUN) {
    Install-AlBuildTools -Url $Url -Ref $Ref -Dest $Dest -Source $Source
}
