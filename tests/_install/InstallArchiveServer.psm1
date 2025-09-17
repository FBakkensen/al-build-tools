#requires -Version 7.0
Set-StrictMode -Version Latest

# Cache install archives per repo/ref to avoid repeated overlay packaging during test runs.

$script:InstallArchiveCache = [hashtable]::Synchronized(@{})
$script:InstallArchiveCacheRoot = $null

function Get-InstallArchiveCacheRoot {
    if (-not $script:InstallArchiveCacheRoot) {
        $base = Join-Path ([IO.Path]::GetTempPath()) 'albt-install-archive-cache'
        $sessionRoot = Join-Path $base ([System.Diagnostics.Process]::GetCurrentProcess().Id.ToString())
        if (-not (Test-Path -LiteralPath $sessionRoot)) {
            New-Item -ItemType Directory -Path $sessionRoot -Force | Out-Null
        }
        $script:InstallArchiveCacheRoot = (Resolve-Path -LiteralPath $sessionRoot).Path
    }
    return $script:InstallArchiveCacheRoot
}

function Get-InstallArchiveCacheKey {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Ref
    )

    $normalizedRepo = [IO.Path]::GetFullPath($RepoRoot)
    return '{0}|{1}' -f $normalizedRepo, $Ref
}

function Get-InstallArchiveCacheHash {
    param(
        [Parameter(Mandatory)] [string] $Key
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Key)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }

    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').Substring(0, 32)
}

function Get-InstallArchiveCacheEntry {
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Ref,
        [Parameter(Mandatory)] [string] $Key
    )

    if ($script:InstallArchiveCache.ContainsKey($Key)) {
        $cached = $script:InstallArchiveCache[$Key]
        if ($cached -and (Test-Path -LiteralPath $cached.ZipPath)) {
            return $cached
        }
    }

    $entry = New-InstallArchiveCacheEntry -RepoRoot $RepoRoot -Ref $Ref -Key $Key
    $script:InstallArchiveCache[$Key] = $entry
    return $entry
}


function New-InstallArchiveCacheEntry {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Ref,
        [Parameter(Mandatory)] [string] $Key
    )

    $target = '{0} (ref {1})' -f $RepoRoot, $Ref
    if (-not $PSCmdlet.ShouldProcess($target, 'Prepare install archive cache entry')) {
        return
    }

    $hash = Get-InstallArchiveCacheHash -Key $Key
    $entryRoot = Join-Path (Get-InstallArchiveCacheRoot) $hash

    if (Test-Path -LiteralPath $entryRoot) {
        Remove-Item -LiteralPath $entryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $entryRoot -Force | Out-Null

    $packageRoot = Join-Path $entryRoot 'archive'
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

    $topName = "al-build-tools-$Ref"
    $topRoot = Join-Path $packageRoot $topName
    New-Item -ItemType Directory -Path $topRoot -Force | Out-Null

    $overlaySource = Join-Path $RepoRoot 'overlay'
    Copy-Item -LiteralPath $overlaySource -Destination $topRoot -Recurse -Force

    $zipPath = Join-Path $entryRoot 'overlay-package.zip'
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -Force

    try {
        Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Verbose "[InstallArchiveCache] Failed to remove staging directory '$packageRoot': $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        ZipPath  = (Resolve-Path -LiteralPath $zipPath).Path
        RootName = $topName
    }
}



function New-InstallArchive {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Workspace,
        [string] $Ref = 'main'
    )

    $resolvedRepo = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $Workspace)) {
        New-Item -ItemType Directory -Path $Workspace | Out-Null
    }
    $resolvedWorkspace = (Resolve-Path -LiteralPath $Workspace -ErrorAction Stop).Path

    if (-not $PSCmdlet.ShouldProcess("workspace '$resolvedWorkspace'", 'Initialize install archive staging area')) {
        return
    }

    $cacheKey = Get-InstallArchiveCacheKey -RepoRoot $resolvedRepo -Ref $Ref
    $cacheEntry = Get-InstallArchiveCacheEntry -RepoRoot $resolvedRepo -Ref $Ref -Key $cacheKey

    $zipPath = Join-Path $resolvedWorkspace 'overlay-package.zip'
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }

    Copy-Item -LiteralPath $cacheEntry.ZipPath -Destination $zipPath -Force

    return [pscustomobject]@{
        ZipPath  = (Resolve-Path -LiteralPath $zipPath).Path
        RootName = $cacheEntry.RootName
    }
}


function Start-InstallArchiveServer {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [string] $ZipPath,
        [string] $BasePath = 'albt',
        [int] $StatusCode = 200,
        [int] $Port
    )

    $resolvedZip = (Resolve-Path -LiteralPath $ZipPath -ErrorAction Stop).Path

    if (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
        Import-Module ThreadJob -ErrorAction Stop
    }

    if (-not $PSBoundParameters.ContainsKey('Port') -or $Port -le 0) {
        $Port = Get-Random -Minimum 20000 -Maximum 45000
    }

    $prefix = "http://127.0.0.1:$Port/"
    if (-not $PSCmdlet.ShouldProcess($prefix, 'Start install archive server')) {
        return
    }

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($prefix)
    $listener.Start()

    $archiveBytes = [System.IO.File]::ReadAllBytes($resolvedZip)

    $job = Start-ThreadJob -ArgumentList $listener, $archiveBytes, $StatusCode -ScriptBlock {
        param($listener, $bytes, $statusCode)
        while ($true) {
            try {
                $context = $listener.GetContext()
            } catch {
                Write-Verbose "[InstallArchiveServer] Listener stopped: $($_.Exception.Message)"
                break
            }

            try {
                if ($statusCode -eq 200) {
                    $context.Response.StatusCode = 200
                    $context.Response.ContentType = 'application/zip'
                    $context.Response.ContentLength64 = $bytes.LongLength
                    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                } else {
                    $context.Response.StatusCode = $statusCode
                }
            } catch {
                Write-Verbose "[InstallArchiveServer] Failed to write response: $($_.Exception.Message)"
                try { $context.Response.StatusCode = 500 } catch { Write-Verbose "[InstallArchiveServer] Failed to set error status: $($_.Exception.Message)" }
            } finally {
                try { $context.Response.OutputStream.Flush() } catch { Write-Verbose "[InstallArchiveServer] Flush failed: $($_.Exception.Message)" }
                try { $context.Response.OutputStream.Close() } catch { Write-Verbose "[InstallArchiveServer] Close failed: $($_.Exception.Message)" }
            }
        }
    }

    return [pscustomobject]@{
        Listener   = $listener
        Job        = $job
        BaseUrl    = "http://127.0.0.1:$Port/$BasePath"
        Prefix     = $prefix
        StatusCode = $StatusCode
    }
}

function Stop-InstallArchiveServer {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)] [psobject] $Server
    )

    if ($null -eq $Server) { return }

    if (-not $PSCmdlet.ShouldProcess('install archive server resources', 'Stop install archive server')) {
        return
    }

    if ($Server.Listener) {
        try {
            $Server.Listener.Stop()
        } catch {
            Write-Verbose "[InstallArchiveServer] Listener stop failed: $($_.Exception.Message)"
        }

        try {
            $Server.Listener.Close()
        } catch {
            Write-Verbose "[InstallArchiveServer] Listener close failed: $($_.Exception.Message)"
        }
    }

    if ($Server.Job) {
        try {
            Wait-Job -Job $Server.Job -Timeout 2 | Out-Null
        } catch {
            Write-Verbose "[InstallArchiveServer] Wait-Job failed: $($_.Exception.Message)"
        }

        if ($Server.Job.State -notin @('Completed', 'Failed', 'Stopped')) {
            try {
                Stop-Job -Job $Server.Job -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Verbose "[InstallArchiveServer] Stop-Job failed: $($_.Exception.Message)"
            }
        }

        try {
            Receive-Job -Job $Server.Job -Wait -AutoRemoveJob | Out-Null
        } catch {
            Write-Verbose "[InstallArchiveServer] Receive-Job failed: $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function `
    New-InstallArchive, `
    Start-InstallArchiveServer, `
    Stop-InstallArchiveServer
