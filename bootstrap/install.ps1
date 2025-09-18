#requires -Version 7.0
param(
    [string]$Url = 'https://github.com/FBakkensen/al-build-tools',
    [string]$Ref = 'main',
    [string]$Dest = '.',
    [string]$Source = 'overlay',
    [int]$HttpTimeoutSec = 0
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

    # FR-008: Reject unsupported parameters (usage guard)
    if ($args.Count -gt 0) {
        $firstArg = $args[0]
        $argName = if ($firstArg.StartsWith('-')) { $firstArg.Substring(1) } else { $firstArg }
        Write-Host "[install] guard UnknownParameter argument=`"$argName`""
        Write-Host "Usage: Install-AlBuildTools [-Url <url>] [-Ref <ref>] [-Dest <path>] [-Source <folder>]"
        exit 10
    }

function Write-Note($msg) { Write-Host "[al-build-tools] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[ok] $msg" -ForegroundColor Green }
function Write-Warn2($m)  { Write-Warning $m }
function Write-Step($n, $msg) { 
    Write-Host ("[{0}] {1}" -f $n, $msg) 
    # Emit standardized step diagnostic for cross-platform parity testing
    $stepName = $msg -replace '[^\w\s]', '' -replace '\s+', '_' -replace '^_|_$', ''
    Write-Host ("[install] step index={0} name={1}" -f $n, $stepName)
}

function Install-AlBuildTools {
    [CmdletBinding()]
    param(
        [string]$Url = 'https://github.com/FBakkensen/al-build-tools',
        [string]$Ref = 'main',
        [string]$Dest = '.',
        [string]$Source = 'overlay',
        [int]$HttpTimeoutSec = 0
    )

    # FR-004: Enforce minimum PowerShell version guard
    $psVersion = if ($env:ALBT_TEST_FORCE_PSVERSION) { 
        [System.Version]$env:ALBT_TEST_FORCE_PSVERSION 
    } else { 
        $PSVersionTable.PSVersion 
    }
    if ($psVersion -lt [System.Version]'7.0') {
        Write-Host "[install] guard PowerShellVersionUnsupported"
        exit 10
    }

    $effectiveTimeoutSec = $HttpTimeoutSec
    if ($effectiveTimeoutSec -le 0) {
        $envTimeoutRaw = $env:ALBT_HTTP_TIMEOUT_SEC
        if ($envTimeoutRaw) {
            $parsedTimeout = 0
            if ([int]::TryParse($envTimeoutRaw, [ref]$parsedTimeout) -and $parsedTimeout -gt 0) {
                $effectiveTimeoutSec = $parsedTimeout
            } else {
                Write-Warning "[install] env ALBT_HTTP_TIMEOUT_SEC value '$envTimeoutRaw' is not a positive integer; ignoring."
            }
        }
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
    # FR-023: Abort when destination is not a git repository
    if (-not $gitOk -and -not (Test-Path (Join-Path $destFull '.git'))) {
        Write-Host "[install] guard GitRepoRequired"
        exit 10
    }
    
    # FR-024: Require clean working tree before copying overlay
    if ($gitOk -or (Test-Path (Join-Path $destFull '.git'))) {
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
                exit 10
            }
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
                $invokeWebRequestParameters = @{
                    Uri = $u
                    OutFile = $zip
                    UseBasicParsing = $true
                    MaximumRedirection = 5
                    ErrorAction = 'Stop'
                }
                if ($effectiveTimeoutSec -gt 0) {
                    $invokeWebRequestParameters['TimeoutSec'] = $effectiveTimeoutSec
                }
                Invoke-WebRequest @invokeWebRequestParameters
                $downloaded = $true
                break
            } catch {
                $lastError = $_
                continue
            }
        }
        if (-not $downloaded) {
            # FR-014: Classify archive acquisition failures by category
            $category = 'Unknown'
            $hint = 'Check network connectivity and repository URL'
            if ($lastError) {
                $errorMessage = $lastError.Exception.Message.ToLower()
                if ($errorMessage -match 'timeout') {
                    $category = 'Timeout'
                    $hint = 'Request timed out'
                } elseif ($errorMessage -match 'network|connection|unreachable') {
                    $category = 'NetworkUnavailable'
                    $hint = 'Network connectivity issues'
                } elseif ($errorMessage -match '404|not found') {
                    $category = 'NotFound'
                    $hint = 'Repository or reference does not exist'
                } elseif ($errorMessage -match 'corrupt|invalid|archive') {
                    $category = 'CorruptArchive'
                    $hint = 'Archive file is corrupted or invalid'
                }
            }
            Write-Host "[install] download failure ref=`"$Ref`" url=`"$base`" category=$category hint=`"$hint`""
            exit 20
        }

        $step++; Write-Step $step "Extract and locate '$Source'"
        $extract = Join-Path $tmp.FullName 'x'
        try {
            Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force -ErrorAction Stop
        } catch {
            Write-Host "[install] download failure ref=`"$Ref`" url=`"$base`" category=CorruptArchive hint=`"Failed to extract archive`""
            exit 20
        }
        $top = Get-ChildItem -Path $extract -Directory | Select-Object -First 1
        if (-not $top) { 
            Write-Host "[install] download failure ref=`"$Ref`" url=`"$base`" category=CorruptArchive hint=`"Archive appears empty`""
            exit 20
        }
        $src = Join-Path $top.FullName $Source
        if (-not (Test-Path $src -PathType Container)) {
            # last-chance scan
            $cand = Get-ChildItem -Path $extract -Recurse -Directory -Filter $Source | Select-Object -First 1
            if ($cand) { 
                $src = $cand.FullName 
            } else { 
                Write-Host "[install] download failure ref=`"$Ref`" url=`"$base`" category=NotFound hint=`"Source folder '$Source' not found in archive`""
                exit 20
            }
        }
        
        # Validate extraction completed successfully before proceeding
        if (-not (Get-ChildItem -Path $src -File -ErrorAction SilentlyContinue)) {
            Write-Host "[install] download failure ref=`"$Ref`" url=`"$base`" category=CorruptArchive hint=`"Source directory contains no files`""
            exit 20
        }
        
        Write-Ok "Source directory: $src"

        $step++; Write-Step $step "Copy files into destination"
        
        # FR-007: Verify all source files remain within destination boundary
        $overlayFiles = Get-ChildItem -Path $src -Recurse -File
        foreach ($file in $overlayFiles) {
            $relativePath = $file.FullName.Substring($src.Length).TrimStart('\', '/')
            $targetPath = Join-Path $destFull $relativePath
            $resolvedTarget = [System.IO.Path]::GetFullPath($targetPath)
            if (-not $resolvedTarget.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "[install] guard RestrictedWrites"
                exit 30
            }
        }
        
        $fileCount = (Get-ChildItem -Path $src -Recurse -File | Measure-Object).Count
        $dirCount  = (Get-ChildItem -Path $src -Recurse -Directory | Measure-Object).Count + 1
        # FR-020: Surface permission failures as guard diagnostics
        try {
            Copy-Item -Path (Join-Path $src '*') -Destination $destFull -Recurse -Force -ErrorAction Stop
        } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            Write-Host "[install] guard PermissionDenied"
            exit 30
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
    try {
        $installParams = @{
            Url = $Url
            Ref = $Ref
            Dest = $Dest
            Source = $Source
        }
        if ($PSBoundParameters.ContainsKey('HttpTimeoutSec')) {
            $installParams['HttpTimeoutSec'] = $HttpTimeoutSec
        }
        Install-AlBuildTools @installParams
    } catch {
        Write-Host "[install] error unhandled=$(ConvertTo-Json $_.Exception.Message -Compress)"
        exit 99
    }
}
