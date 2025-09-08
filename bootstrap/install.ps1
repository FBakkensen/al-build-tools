#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Note($msg) { Write-Host "[al-build-tools] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[ok] $msg" -ForegroundColor Green }
function Write-Warn2($m)  { Write-Warning $m }
function Write-Step($n, $msg) { Write-Host ("[{0}] {1}" -f $n, $msg) -ForegroundColor White }

function Install-AlBuildTools {
    [CmdletBinding()]
    param(
        [string]$Url = 'https://github.com/FBakkensen/al-build-tools',
        [string]$Ref = 'main',
        [string]$Dest = '.',
        [string]$Source = 'overlay'
    )

    $step = 0
    function NextStep([string]$msg) { $script:step++; Write-Step $script:step $msg }

    NextStep "Resolve destination"
    try {
        $destFull = (Resolve-Path -Path $Dest -ErrorAction Stop).Path
    } catch {
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
        $destFull = (Resolve-Path -Path $Dest).Path
    }
    Write-Note "Install/update from $Url@$Ref into $destFull (source: $Source)"

    NextStep "Detect git repository"
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
    } catch {}
    if (-not $gitOk -and -not (Test-Path (Join-Path $destFull '.git'))) {
        Write-Warn2 "Destination '$destFull' does not look like a git repo. Proceeding anyway."
    }
    Write-Ok "Working in: $destFull"

    $tmp = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName()))
    try {
        NextStep "Download repository archive"
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

        NextStep "Extract and locate '$Source'"
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

        NextStep "Copy files into destination"
        $fileCount = (Get-ChildItem -Path $src -Recurse -File | Measure-Object).Count
        $dirCount  = (Get-ChildItem -Path $src -Recurse -Directory | Measure-Object).Count + 1
        Copy-Item -Path (Join-Path $src '*') -Destination $destFull -Recurse -Force
        Write-Ok "Copied $fileCount files across $dirCount directories"

        Write-Note "Completed: $Source from $Url@$Ref into $destFull"
    } finally {
        try { Remove-Item -Recurse -Force -LiteralPath $tmp.FullName -ErrorAction SilentlyContinue } catch {}
    }
}

# If the script is executed (not dot-sourced), nothing else to do. The typical one-liner is:
#   iwr -useb https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.ps1 | iex; Install-AlBuildTools -Dest .
