#requires -Version 7.0
param(
    [string]$Url = 'https://github.com/FBakkensen/al-build-tools',
    [string]$Ref = 'main',
    [string]$Dest = '.',
    [string]$Source = 'overlay'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
        Write-Warn2 "Destination '$destFull' does not look like a git repo. Proceeding anyway."
    }
    Write-Ok "Working in: $destFull"

    $tmp = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName()))
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
        foreach ($u in $tryUrls) {
            try {
                Write-Note "Downloading: $u"
                Invoke-WebRequest -Uri $u -OutFile $zip -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop
                $downloaded = $true
                break
            } catch {
                continue
            }
        }
        if (-not $downloaded) {
            throw "Failed to download repo archive for ref '$Ref' from $Url."
        }

        $step++; Write-Step $step "Extract and locate '$Source'"
        $extract = Join-Path $tmp.FullName 'x'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $top = Get-ChildItem -Path $extract -Directory | Select-Object -First 1
        if (-not $top) { throw 'Archive appears empty or unreadable.' }
        $src = Join-Path $top.FullName $Source
        if (-not (Test-Path $src -PathType Container)) {
            # last-chance scan
            $cand = Get-ChildItem -Path $extract -Recurse -Directory -Filter $Source | Select-Object -First 1
            if ($cand) { $src = $cand.FullName } else { throw "Expected subfolder '$Source' not found in archive at ref '$Ref'." }
        }
        Write-Ok "Source directory: $src"

        $step++; Write-Step $step "Copy files into destination"
        $fileCount = (Get-ChildItem -Path $src -Recurse -File | Measure-Object).Count
        $dirCount  = (Get-ChildItem -Path $src -Recurse -Directory | Measure-Object).Count + 1
        Copy-Item -Path (Join-Path $src '*') -Destination $destFull -Recurse -Force
        Write-Ok "Copied $fileCount files across $dirCount directories"

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
