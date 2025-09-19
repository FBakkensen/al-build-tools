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


function Get-InstallReleaseField {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string] $Name
    )

    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $Object[$key]
            }
        }
    } elseif ($null -ne $Object) {
        $prop = $Object.PSObject.Properties | Where-Object { $_.Name -eq $Name -or $_.Name -ieq $Name } | Select-Object -First 1
        if ($prop) { return $prop.Value }
    }

    return $null
}

function Get-InstallDeterministicAssetId {
    param(
        [Parameter(Mandatory)] [string] $Tag,
        [Parameter(Mandatory)] [string] $AssetName
    )

    $input = "$Tag::$AssetName"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($input)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }

    return [uint32][System.BitConverter]::ToUInt32($hash, 0)
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
        [string] $ZipPath,
        [string] $BasePath = 'albt',
        [int] $StatusCode = 200,
        [int] $Port,
        [object[]] $Releases,
        [string] $LatestTag,
        [string[]] $NotFoundTags = @()
    )

    if (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
        Import-Module ThreadJob -ErrorAction Stop
    }

    if (-not $PSBoundParameters.ContainsKey('Port') -or $Port -le 0) {
        $Port = Get-Random -Minimum 20000 -Maximum 45000
    }

    $prefix = "http://127.0.0.1:$Port/"

    $normalizedBasePath = if ([string]::IsNullOrWhiteSpace($BasePath)) { '' } else { $BasePath.Trim('/') }
    $baseUrl = if ([string]::IsNullOrEmpty($normalizedBasePath)) {
        "http://127.0.0.1:$Port"
    } else {
        "http://127.0.0.1:$Port/$normalizedBasePath"
    }

    $archiveBytes = $null
    $resolvedZip = $null
    if ($PSBoundParameters.ContainsKey('ZipPath') -and $ZipPath) {
        $resolvedZip = (Resolve-Path -LiteralPath $ZipPath -ErrorAction Stop).Path
        $archiveBytes = [System.IO.File]::ReadAllBytes($resolvedZip)
    }

    $releaseDescriptors = @()
    if ($Releases) {
        foreach ($entry in $Releases) {
            $tag = Get-InstallReleaseField -Object $entry -Name 'Tag'
            if ([string]::IsNullOrWhiteSpace($tag)) {
                throw "Release entry is missing required 'Tag' value."
            }

            $releaseZipPath = Get-InstallReleaseField -Object $entry -Name 'ZipPath'
            if ([string]::IsNullOrWhiteSpace($releaseZipPath)) {
                if (-not $resolvedZip) {
                    throw "Release '$tag' does not define ZipPath and no default ZipPath was provided."
                }
                $releaseZipPath = $resolvedZip
            }
            $releaseZipResolved = (Resolve-Path -LiteralPath $releaseZipPath -ErrorAction Stop).Path
            $bytes = [System.IO.File]::ReadAllBytes($releaseZipResolved)

            $assetName = Get-InstallReleaseField -Object $entry -Name 'AssetName'
            if ([string]::IsNullOrEmpty($assetName)) { $assetName = 'overlay.zip' }

            $assetId = Get-InstallReleaseField -Object $entry -Name 'AssetId'
            if ($null -eq $assetId) {
                $assetId = Get-InstallDeterministicAssetId -Tag $tag -AssetName $assetName
            }

            $publishedAt = Get-InstallReleaseField -Object $entry -Name 'PublishedAt'
            if ($publishedAt) {
                if ($publishedAt -is [DateTime]) {
                    $publishedAt = ([DateTime]$publishedAt).ToUniversalTime()
                } else {
                    try {
                        $publishedAt = [DateTime]::Parse([string]$publishedAt, $null, [System.Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
                    } catch {
                        throw "Release '$tag' provided invalid PublishedAt value '$publishedAt'."
                    }
                }
            } else {
                $publishedAt = (Get-Date).ToUniversalTime()
            }

            $isDraft = [bool](Get-InstallReleaseField -Object $entry -Name 'Draft')
            $isPrerelease = [bool](Get-InstallReleaseField -Object $entry -Name 'Prerelease')

            $descriptor = [pscustomobject]@{
                Tag = $tag
                AssetId = [uint32]$assetId
                AssetName = $assetName
                Bytes = $bytes
                Size = $bytes.LongLength
                PublishedAt = $publishedAt.ToString('o')
                Draft = $isDraft
                Prerelease = $isPrerelease
            }

            $releaseDescriptors += $descriptor
        }
    }

    $hasReleaseEndpoints = ($releaseDescriptors | Measure-Object).Count -gt 0
    $effectiveLatestTag = $LatestTag

    if (-not $hasReleaseEndpoints -and $archiveBytes) {
        $defaultTag = if (-not [string]::IsNullOrWhiteSpace($LatestTag)) { $LatestTag } else { 'main' }
        $assetName = 'overlay.zip'
        $assetId = Get-InstallDeterministicAssetId -Tag $defaultTag -AssetName $assetName
        $descriptor = [pscustomobject]@{
            Tag = $defaultTag
            AssetId = [uint32]$assetId
            AssetName = $assetName
            Bytes = $archiveBytes
            Size = $archiveBytes.LongLength
            PublishedAt = (Get-Date).ToUniversalTime().ToString('o')
            Draft = $false
            Prerelease = $false
        }
        $releaseDescriptors = @($descriptor)
        $hasReleaseEndpoints = $true
        if ([string]::IsNullOrWhiteSpace($effectiveLatestTag)) {
            $effectiveLatestTag = $defaultTag
        }
    }

    if ($hasReleaseEndpoints -and [string]::IsNullOrWhiteSpace($effectiveLatestTag)) {
        $effectiveLatestTag = $releaseDescriptors[0].Tag
    }

    if (-not $PSCmdlet.ShouldProcess($prefix, 'Start install archive server')) {
        return
    }

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($prefix)
    $listener.Start()

    $config = [pscustomobject]@{
        BaseUrl = $baseUrl
        BasePath = $normalizedBasePath
        LegacyStatusCode = $StatusCode
        ArchiveBytes = $archiveBytes
        Releases = $releaseDescriptors
        LatestTag = $effectiveLatestTag
        NotFoundTags = $NotFoundTags
    }

    $job = Start-ThreadJob -ArgumentList $listener, $config -ScriptBlock {
        param($listener, $config)

        $shouldHandleTag = {
            param([string] $Tag, [string[]] $NotFound)
            if (-not $Tag) { return $false }
            foreach ($nf in $NotFound) {
                if ([string]::Equals($nf, $Tag, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $false
                }
            }
            return $true
        }

        while ($true) {
            try {
                $context = $listener.GetContext()
            } catch {
                Write-Verbose "[InstallArchiveServer] Listener stopped: $($_.Exception.Message)"
                break
            }

            $response = $context.Response
            try {
                $requestPath = $context.Request.Url.AbsolutePath.Trim('/')
                $basePath = $config.BasePath
                if ($basePath) {
                    if ($requestPath.StartsWith($basePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $requestPath = $requestPath.Substring($basePath.Length).Trim('/')
                    }
                }

                $handled = $false

                if (($config.Releases | Measure-Object).Count -gt 0) {
                    if ([string]::Equals($requestPath, 'releases/latest', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $handled = $true
                        $latestTag = $config.LatestTag
                        if ($latestTag -and (& $shouldHandleTag $latestTag $config.NotFoundTags)) {
                            $release = $config.Releases | Where-Object { $_.Tag -eq $latestTag } | Select-Object -First 1
                            if ($release) {
                                $payload = [ordered]@{
                                    tag_name = $release.Tag
                                    name = $release.Tag
                                    draft = $release.Draft
                                    prerelease = $release.Prerelease
                                    published_at = $release.PublishedAt
                                    assets = @([ordered]@{
                                            id = [uint32]$release.AssetId
                                            name = $release.AssetName
                                            browser_download_url = "{0}/releases/assets/{1}" -f $config.BaseUrl, $release.AssetId
                                            content_type = 'application/zip'
                                            size = $release.Size
                                        })
                                }
                                $json = ($payload | ConvertTo-Json -Depth 4)
                                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                                $response.StatusCode = 200
                                $response.ContentType = 'application/json'
                                $response.ContentLength64 = $bytes.LongLength
                                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                            } else {
                                $response.StatusCode = 404
                            }
                        } else {
                            $response.StatusCode = 404
                        }
                    } elseif ($requestPath.StartsWith('releases/tags/', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $handled = $true
                        $tag = $requestPath.Substring('releases/tags/'.Length)
                        if (& $shouldHandleTag $tag $config.NotFoundTags) {
                            $release = $config.Releases | Where-Object { $_.Tag -eq $tag } | Select-Object -First 1
                            if ($release) {
                                $payload = [ordered]@{
                                    tag_name = $release.Tag
                                    name = $release.Tag
                                    draft = $release.Draft
                                    prerelease = $release.Prerelease
                                    published_at = $release.PublishedAt
                                    assets = @([ordered]@{
                                            id = [uint32]$release.AssetId
                                            name = $release.AssetName
                                            browser_download_url = "{0}/releases/assets/{1}" -f $config.BaseUrl, $release.AssetId
                                            content_type = 'application/zip'
                                            size = $release.Size
                                        })
                                }
                                $json = ($payload | ConvertTo-Json -Depth 4)
                                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                                $response.StatusCode = 200
                                $response.ContentType = 'application/json'
                                $response.ContentLength64 = $bytes.LongLength
                                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                            } else {
                                $response.StatusCode = 404
                            }
                        } else {
                            $response.StatusCode = 404
                        }
                    } elseif ($requestPath.StartsWith('releases/assets/', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $handled = $true
                        $idSegment = $requestPath.Substring('releases/assets/'.Length)
                        $assetId = 0
                        if ([uint32]::TryParse($idSegment, [ref]$assetId)) {
                            $release = $config.Releases | Where-Object { $_.AssetId -eq $assetId } | Select-Object -First 1
                            if ($release) {
                                $response.StatusCode = 200
                                $response.ContentType = 'application/zip'
                                $response.ContentLength64 = $release.Bytes.LongLength
                                $response.OutputStream.Write($release.Bytes, 0, $release.Bytes.Length)
                            } else {
                                $response.StatusCode = 404
                            }
                        } else {
                            $response.StatusCode = 404
                        }
                    }
                }

                if (-not $handled) {
                    if ($config.ArchiveBytes) {
                        if ($config.LegacyStatusCode -eq 200) {
                            $response.StatusCode = 200
                            $response.ContentType = 'application/zip'
                            $response.ContentLength64 = $config.ArchiveBytes.LongLength
                            $response.OutputStream.Write($config.ArchiveBytes, 0, $config.ArchiveBytes.Length)
                        } else {
                            $response.StatusCode = $config.LegacyStatusCode
                        }
                    } else {
                        $response.StatusCode = 404
                    }
                }
            } catch {
                Write-Verbose "[InstallArchiveServer] Failed to write response: $($_.Exception.Message)"
                try { $response.StatusCode = 500 } catch { Write-Verbose "[InstallArchiveServer] Failed to set error status: $($_.Exception.Message)" }
            } finally {
                try { $response.OutputStream.Flush() } catch { Write-Verbose "[InstallArchiveServer] Flush failed: $($_.Exception.Message)" }
                try { $response.OutputStream.Close() } catch { Write-Verbose "[InstallArchiveServer] Close failed: $($_.Exception.Message)" }
            }
        }
    }

    return [pscustomobject]@{
        Listener   = $listener
        Job        = $job
        BaseUrl    = if ([string]::IsNullOrEmpty($normalizedBasePath)) { $baseUrl } else { "$baseUrl" }
        Prefix     = $prefix
        StatusCode = $StatusCode
        Releases   = $releaseDescriptors
        LatestTag  = $effectiveLatestTag
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
