# Allow execution under Windows PowerShell 5.1; script performs its own PS 7+ installation logic when needed.
[CmdletBinding()]
param(
    [string]$Url = 'https://api.github.com/repos/FBakkensen/al-build-tools',
    [string]$Ref,
    [string]$DestinationPath = '.',
    [string]$Source = 'overlay',
    [int]$HttpTimeoutSec = 0,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Source prerequisite installer functions
if ($PSScriptRoot) {
    # Running as a file - dot-source from disk
    . "$PSScriptRoot/install-prerequisites.ps1"
} else {
    # Running via iex (piped from web) - download and execute in memory
    $prereqUrl = 'https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install-prerequisites.ps1'
    $prereqScript = Invoke-WebRequest -Uri $prereqUrl -UseBasicParsing -ErrorAction Stop | Select-Object -ExpandProperty Content
    Invoke-Expression $prereqScript
}

# Handle $IsWindows for PowerShell 5.1 compatibility (added in PS 6.0)
if (-not (Get-Variable -Name 'IsWindows' -Scope Global -ErrorAction SilentlyContinue)) {
    $script:IsWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

if (-not $IsWindows) {
    $linuxInstaller = Join-Path $PSScriptRoot 'install-linux.ps1'
    if (Test-Path $linuxInstaller) {
        & $linuxInstaller @PSBoundParameters
        return
    }
    Write-Error "Installation failed: Windows installer invoked on a non-Windows platform. Run install-linux.ps1 instead."
}

    # FR-008: Reject unsupported parameters (usage guard)
if (-not (Get-Variable -Name 'args' -Scope 0 -ErrorAction SilentlyContinue)) {
    $scriptArgs = @()
} else {
    $scriptArgs = $args
}
$unknownArgs = @()
if ($RemainingArguments) {
    $unknownArgs += $RemainingArguments
}
if ($scriptArgs -and $scriptArgs.Count -gt 0) {
    $unknownArgs += $scriptArgs
}
if ($unknownArgs.Count -gt 0) {
    $firstArg = $unknownArgs[0]
    $argName = if ($firstArg.StartsWith('-')) { $firstArg.Substring(1) } else { $firstArg }
    Write-Host "[install] guard UnknownParameter argument=`"$argName`""
    Write-Host "Usage: Install-AlBuildTools [-Url <url>] [-Ref <ref>] [-Dest <path>] [-Source <folder>]"
    Write-Error "Installation failed: Unknown parameter '$argName'. Use: Install-AlBuildTools [-Url <url>] [-Ref <ref>] [-Dest <path>] [-Source <folder>]"
}

# Note: Write-BuildMessage, Write-BuildHeader, and AutoInstallPrereqs are now sourced from install-prerequisites.ps1

# Legacy functions for backward compatibility with diagnostics
function Write-Step($n, $msg) {
    Write-BuildMessage -Type Step -Message $msg
    # Emit standardized step diagnostic for cross-platform parity testing
    $stepName = $msg -replace '[^\w\s]', '' -replace '\s+', '_' -replace '^_|_$', ''
    Write-Host ("[install] step index={0} name={1}" -f $n, $stepName)
}


function ConvertTo-CanonicalReleaseTag {
    param(
        [string]$Tag
    )

    if ([string]::IsNullOrWhiteSpace($Tag)) {
        return $Tag
    }

    $trimmed = $Tag.Trim()
    if ($trimmed.Length -gt 1 -and ($trimmed[0] -eq 'v' -or $trimmed[0] -eq 'V') -and [char]::IsDigit($trimmed[1])) {
        return 'v' + $trimmed.Substring(1)
    }

    if ($trimmed.Length -gt 0 -and [char]::IsDigit($trimmed[0])) {
        return 'v' + $trimmed
    }

    return $trimmed
}

function Resolve-EffectiveReleaseTag {
    param(
        [string]$ParameterRef,
        [string]$EnvRelease,
        [bool]$EmitVerboseNote = $false
    )

    if (-not [string]::IsNullOrWhiteSpace($ParameterRef)) {
        return [pscustomobject]@{
            Tag = ConvertTo-CanonicalReleaseTag -Tag $ParameterRef
            Source = 'Parameter'
            Original = $ParameterRef
            NoteMessage = $null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($EnvRelease)) {
        $canonical = ConvertTo-CanonicalReleaseTag -Tag $EnvRelease
        Write-Verbose "Using env ALBT_RELEASE=$canonical"
        $noteMessage = $null
        if ($EmitVerboseNote) {
            $noteMessage = "[install] note Using env ALBT_RELEASE=$canonical"
        }
        return [pscustomobject]@{
            Tag = $canonical
            Source = 'Environment'
            Original = $EnvRelease
            NoteMessage = $noteMessage
        }
    }

    return [pscustomobject]@{
        Tag = $null
        Source = 'Latest'
        Original = $null
        NoteMessage = $null
    }
}

function Get-HttpStatusCodeFromError {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if ($null -eq $ErrorRecord) { return $null }

    $exception = $ErrorRecord.Exception
    while ($exception) {
        $response = $null
        try { $response = $exception.Response } catch { $response = $null }
        if ($response) {
            $statusCandidate = $null
            try { $statusCandidate = $response.StatusCode } catch { $statusCandidate = $null }
            if ($null -ne $statusCandidate) {
                try {
                    return [int]$statusCandidate
                } catch {
                    Write-Verbose "[install] Failed to convert status candidate to int: $($_.Exception.Message)"
                }
            }
        }

        $status = $null
        try { $status = $exception.StatusCode } catch { $status = $null }
        if ($null -ne $status) {
            if ($status -is [int]) { return $status }
            if ($status -is [System.Net.HttpStatusCode]) { return [int]$status }

            $valueCandidate = $null
            try { $valueCandidate = $status.value__ } catch { $valueCandidate = $null }
            if ($valueCandidate -is [int]) { return $valueCandidate }
        }

        $exception = $exception.InnerException
    }

    return $null
}

function Resolve-DownloadFailureDetails {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$DefaultHint = 'Check network connectivity and repository URL',
        [hashtable]$StatusHints
    )

    $category = 'Unknown'
    $hint = $DefaultHint

    if ($null -eq $ErrorRecord) {
        return [pscustomobject]@{ Category = $category; Hint = $hint }
    }

    $message = $ErrorRecord.Exception.Message
    $statusCode = Get-HttpStatusCodeFromError -ErrorRecord $ErrorRecord

    if ($ErrorRecord.Exception -is [System.OperationCanceledException]) {
        return [pscustomobject]@{ Category = 'Timeout'; Hint = 'Request timed out' }
    }

    if ($message -match 'timed out|timeout') {
        return [pscustomobject]@{ Category = 'Timeout'; Hint = 'Request timed out' }
    }

    if ($message -match 'name or service not known|No such host|Temporary failure in name resolution|network is unreachable|connection refused|connect failed|actively refused') {
        return [pscustomobject]@{ Category = 'NetworkUnavailable'; Hint = 'Network connectivity issues' }
    }

    if ($statusCode) {
        if ($StatusHints -and $StatusHints.ContainsKey($statusCode)) {
            $entry = $StatusHints[$statusCode]
            if ($entry -and $entry.Category) { $category = $entry.Category }
            if ($entry -and $entry.Hint) { $hint = $entry.Hint }
        } else {
            switch ($statusCode) {
                404 { $category = 'NotFound'; $hint = 'Resource not found' }
                408 { $category = 'Timeout'; $hint = 'Request timed out' }
                429 { $category = 'Unknown'; $hint = 'Rate limited retrieving resource' }
                500 { $category = 'Unknown'; $hint = 'Server error retrieving resource' }
                502 { $category = 'NetworkUnavailable'; $hint = 'Bad gateway retrieving resource' }
                503 { $category = 'NetworkUnavailable'; $hint = 'Service unavailable' }
                504 { $category = 'Timeout'; $hint = 'Gateway timeout retrieving resource' }
                default { $category = 'Unknown'; $hint = $DefaultHint }
            }
        }
        return [pscustomobject]@{ Category = $category; Hint = $hint }
    }

    return [pscustomobject]@{ Category = $category; Hint = $hint }
}


function Install-AlBuildTools {
    [CmdletBinding()]
    param(
        [string]$Url = 'https://api.github.com/repos/FBakkensen/al-build-tools',
        [string]$Ref,
        [string]$DestinationPath = '.',
        [string]$Source = 'overlay',
        [int]$HttpTimeoutSec = 0
    )

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
    # Resolve to absolute path - handle both relative and absolute paths correctly
    Write-Verbose "[install] Input DestinationPath parameter: '$DestinationPath'"
    Write-Verbose "[install] DestinationPath type: $($DestinationPath.GetType().Name)"
    Write-Verbose "[install] DestinationPath length: $($DestinationPath.Length)"
    Write-Verbose "[install] First char: '$($DestinationPath[0])' (code: $([int]$DestinationPath[0]))"
    Write-Verbose "[install] Current location: '$(Get-Location)'"
    Write-Verbose "[install] IsPathRooted: $([System.IO.Path]::IsPathRooted($DestinationPath))"

    if ([System.IO.Path]::IsPathRooted($DestinationPath)) {
        $destAbsolute = $DestinationPath
        Write-Verbose "[install] Path is rooted, using as-is: '$destAbsolute'"
    } else {
        $destAbsolute = Join-Path (Get-Location).Path $DestinationPath
        Write-Verbose "[install] Path is relative, joined: '$destAbsolute'"
    }
    # Normalize the path (remove any .\ or ..\ segments)
    $destAbsolute = [System.IO.Path]::GetFullPath($destAbsolute)
    Write-Verbose "[install] After GetFullPath: '$destAbsolute'"

    if (-not (Test-Path -LiteralPath $destAbsolute)) {
        New-Item -ItemType Directory -Force -Path $destAbsolute | Out-Null
    }
    $destFull = $destAbsolute
    Write-BuildMessage -Type Info -Message "Install/update from $Url into $destFull (source: $Source)"

    $step++; Write-Step $step "Verify prerequisites"

    # Call the prerequisite installer (idempotent - checks before installing)
    $prereqResult = Install-Prerequisites -Dest $destFull

    # Track whether this is a new git repository (installer will handle initial commit)
    $script:IsNewGitRepo = -not (Test-Path (Join-Path $destFull '.git'))

    # Initialize git repository if not present (init + initial commit before overlay copy)
    if ($script:IsNewGitRepo) {
        if ($script:AutoInstallPrereqs) {
            Write-BuildMessage -Type Info -Message "Initializing git repository at $destFull..."

            $prevErrorAction = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                & git -C "$destFull" init 2>&1 | Out-Null
                & git -C "$destFull" add . 2>&1 | Out-Null
                & git -C "$destFull" commit -m "Initial commit before AL Build Tools installation" 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[install] git initial_commit=before"
                    Write-Host "[install] prerequisite tool=`"git`" status=`"initialized`""
                    Write-BuildMessage -Type Success -Message "Git repository initialized with initial commit"
                } else {
                    Write-Host "[install] git initial_commit=before status=failed exit_code=$LASTEXITCODE"
                    Write-Warning "Git commit returned exit code: $LASTEXITCODE"
                }
            } catch {
                Write-Host "[install] prerequisite tool=`"git`" status=`"init_failed`""
                Write-Error "Failed to initialize git repository: $($_.Exception.Message)"
            } finally {
                $ErrorActionPreference = $prevErrorAction
            }
        } else {
            $shouldInit = Confirm-Installation -ToolName "Git repository initialization" -Purpose "Managing overlay files and tracking changes"
            if ($shouldInit) {
                Write-BuildMessage -Type Info -Message "Initializing git repository at $destFull..."

                $prevErrorAction = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    & git -C "$destFull" init 2>&1 | Out-Null
                    & git -C "$destFull" add . 2>&1 | Out-Null
                    & git -C "$destFull" commit -m "Initial commit before AL Build Tools installation" 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[install] git initial_commit=before"
                        Write-Host "[install] prerequisite tool=`"git`" status=`"initialized`""
                        Write-BuildMessage -Type Success -Message "Git repository initialized with initial commit"
                    } else {
                        Write-Host "[install] git initial_commit=before status=failed exit_code=$LASTEXITCODE"
                        Write-Warning "Git commit returned exit code: $LASTEXITCODE"
                    }
                } catch {
                    Write-Host "[install] prerequisite tool=`"git`" status=`"init_failed`""
                    Write-Error "Failed to initialize git repository: $($_.Exception.Message)"
                } finally {
                    $ErrorActionPreference = $prevErrorAction
                }
            } else {
                Write-Host "[install] guard GitRepoRequired declined=true"
                Write-Error "Installation failed: Git repository required. Please initialize with 'git init' or decline to continue."
            }
        }
    }

    # Note: .NET SDK, PowerShell 7, and InvokeBuild checks now handled by Install-Prerequisites

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
        Write-Error "Installation failed: Destination '$destFull' is not a git repository. Please initialize git first with 'git init' or clone an existing repository."
    }

    # FR-024: Require clean working tree before copying overlay (only for existing repos)
    # For new repos (IsNewGitRepo=true), we'll handle the initial commit after copying overlay
    if (-not $script:IsNewGitRepo) {
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
                    Write-Error "Installation failed: Working tree is not clean. Please commit or stash your changes before running the installation."
                }
            }
        }
    }
    Write-BuildMessage -Type Success -Message "Working in: $destFull"

    $tmp = New-Item -ItemType Directory -Path ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName()))
    Write-Host "[install] temp workspace=`"$($tmp.FullName)`""
    $selectedReleaseTag = $null
    $assetName = 'overlay.zip'
    $assetDownloadUrl = $null
    $releaseRequestUrl = $null
    $refForFailure = $null
    try {
        $step++; Write-Step $step "Select release"
        $apiBase = $Url.TrimEnd('/')
        $emitVerboseNote = $false
        if ($PSCmdlet) {
            if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose')) { $emitVerboseNote = $true }
        }
        if (-not $emitVerboseNote) {
            if ($VerbosePreference -eq 'Continue' -or $VerbosePreference -eq 'Inquire') {
                $emitVerboseNote = $true
            }
        }

        $selection = Resolve-EffectiveReleaseTag -ParameterRef $Ref -EnvRelease $env:ALBT_RELEASE -EmitVerboseNote:$emitVerboseNote
        $noteProperty = if ($selection) { $selection.PSObject.Properties['NoteMessage'] } else { $null }
        if ($noteProperty -and $selection.NoteMessage) {
            Write-Output $selection.NoteMessage
        }
        $refForFailure = if ($selection.Tag) { $selection.Tag } else { 'latest' }

        if ([string]::IsNullOrWhiteSpace($apiBase)) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$Url`" category=Unknown hint=`"Release service URL is empty`""
            Write-Error "Installation failed: Release service URL is empty or invalid."
        }

        if ($selection.Tag) {
            $encodedTag = [System.Net.WebUtility]::UrlEncode($selection.Tag)
            $releaseRequestUrl = "$apiBase/releases/tags/$encodedTag"
        } else {
            $releaseRequestUrl = "$apiBase/releases/latest"
        }

        $metadataStatusHints = @{
            401 = @{ Category = 'Unknown'; Hint = 'Authentication required for release metadata' }
            403 = @{ Category = 'Unknown'; Hint = 'Access denied retrieving release metadata' }
            404 = @{ Category = 'NotFound'; Hint = 'Release tag not found' }
        }

        try {
            $metadataRequest = @{
                Uri = $releaseRequestUrl
                Method = 'Get'
                Headers = @{
                    'Accept' = 'application/vnd.github+json'
                    'User-Agent' = 'al-build-tools-installer'
                }
                ErrorAction = 'Stop'
            }
            if ($effectiveTimeoutSec -gt 0) {
                $metadataRequest['TimeoutSec'] = $effectiveTimeoutSec
            }
            $releaseMetadata = Invoke-RestMethod @metadataRequest
        } catch {
            $failure = Resolve-DownloadFailureDetails -ErrorRecord $_ -DefaultHint 'Unable to retrieve release metadata' -StatusHints $metadataStatusHints
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=$($failure.Category) hint=`"$($failure.Hint)`""
            Write-Error "Installation failed: Unable to retrieve release metadata. $($failure.Hint)"
        }

        if ($null -eq $releaseMetadata) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=NotFound hint=`"Release metadata missing`""
            Write-Error "Installation failed: Release metadata is missing or invalid."
        }

        $selectedReleaseTag = ConvertTo-CanonicalReleaseTag -Tag ($releaseMetadata.tag_name)
        if (-not $selectedReleaseTag) {
            $selectedReleaseTag = if ($selection.Tag) { $selection.Tag } else { $null }
        }
        if (-not $selectedReleaseTag) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=Unknown hint=`"Release tag could not be determined`""
            Write-Error "Installation failed: Release tag could not be determined from the release metadata."
        }
        $refForFailure = $selectedReleaseTag

        if ($releaseMetadata.draft -eq $true -or $releaseMetadata.prerelease -eq $true) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=NotFound hint=`"Release not published`""
            Write-Error "Installation failed: Release '$refForFailure' is not published (it may be a draft or prerelease)."
        }

        $assets = @()
        $assetsProperty = $releaseMetadata.PSObject.Properties['assets']
        if ($assetsProperty -and $releaseMetadata.assets) {
            if ($releaseMetadata.assets -is [System.Array]) {
                $assets = $releaseMetadata.assets
            } else {
                $assets = @($releaseMetadata.assets)
            }
        }

        $asset = $null
        $fallbackAsset = $null
        foreach ($candidate in $assets) {
            if ($null -eq $candidate) { continue }
            $nameProp = $candidate.PSObject.Properties | Where-Object { $_.Name -eq 'name' } | Select-Object -First 1
            if (-not $nameProp) { continue }
            $candidateName = [string]$nameProp.Value
            if ([string]::IsNullOrWhiteSpace($candidateName)) { continue }

            if ($candidateName -ieq 'overlay.zip') {
                $asset = $candidate
                break
            }

            if (-not $fallbackAsset -and $candidateName -like 'al-build-tools-*.zip') {
                $fallbackAsset = $candidate
            }
        }

        if (-not $asset) {
            if ($fallbackAsset) {
                $asset = $fallbackAsset
                Write-Verbose "[install] asset fallback Using release asset '$(($fallbackAsset.name))'"
            } else {
                Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=NotFound hint=`"Release asset overlay.zip not found`""
                Write-Error "Installation failed: Release asset 'overlay.zip' not found in release '$refForFailure'."
            }
        }

        $assetNameProp = $asset.PSObject.Properties | Where-Object { $_.Name -eq 'name' } | Select-Object -First 1
        if ($assetNameProp) {
            $assetName = [string]$assetNameProp.Value
        }

        $assetUrlProp = $asset.PSObject.Properties | Where-Object { $_.Name -eq 'browser_download_url' } | Select-Object -First 1
        if ($assetUrlProp) {
            $assetDownloadUrl = [string]$assetUrlProp.Value
        }

        if ([string]::IsNullOrWhiteSpace($assetDownloadUrl)) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$releaseRequestUrl`" category=Unknown hint=`"Release asset download URL missing`""
            Write-Error "Installation failed: Release asset download URL is missing or invalid."
        }

        Write-BuildMessage -Type Info -Message "Selected release: $selectedReleaseTag (asset: $assetName)"

        $step++; Write-Step $step "Download release asset"
        $zip = Join-Path $tmp.FullName 'overlay.zip'
        $assetStatusHints = @{
            401 = @{ Category = 'Unknown'; Hint = 'Authentication required for release asset' }
            403 = @{ Category = 'Unknown'; Hint = 'Access denied retrieving release asset' }
            404 = @{ Category = 'NotFound'; Hint = "Release asset $assetName not found" }
        }

        try {
            $downloadParams = @{
                Uri = $assetDownloadUrl
                OutFile = $zip
                Headers = @{
                    'Accept' = 'application/octet-stream'
                    'User-Agent' = 'al-build-tools-installer'
                }
                MaximumRedirection = 5
                ErrorAction = 'Stop'
            }
            if ($effectiveTimeoutSec -gt 0) {
                $downloadParams['TimeoutSec'] = $effectiveTimeoutSec
            }
            Invoke-WebRequest @downloadParams
        } catch {
            $failure = Resolve-DownloadFailureDetails -ErrorRecord $_ -DefaultHint 'Unable to download release asset' -StatusHints $assetStatusHints
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$assetDownloadUrl`" category=$($failure.Category) hint=`"$($failure.Hint)`""
            Write-Error "Installation failed: Unable to download release asset. $($failure.Hint)"
        }

        $step++; Write-Step $step "Extract and locate '$Source'"
        $extract = Join-Path $tmp.FullName 'x'
        try {
            Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force -ErrorAction Stop
        } catch {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$assetDownloadUrl`" category=CorruptArchive hint=`"Failed to extract asset`""
            Write-Error "Installation failed: Failed to extract the downloaded archive. The file may be corrupted."
        }
        $top = Get-ChildItem -Path $extract -Directory | Select-Object -First 1
        if (-not $top) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$assetDownloadUrl`" category=CorruptArchive hint=`"Asset archive appears empty`""
            Write-Error "Installation failed: Downloaded archive appears to be empty or corrupted."
        }
        $src = Join-Path $top.FullName $Source
        if (-not (Test-Path $src -PathType Container)) {
            $cand = Get-ChildItem -Path $extract -Recurse -Directory -Filter $Source | Select-Object -First 1
            if ($cand) {
                $src = $cand.FullName
            } else {
                Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$assetDownloadUrl`" category=NotFound hint=`"Source folder '$Source' not found in asset`""
                Write-Error "Installation failed: Source folder '$Source' not found in the downloaded archive."
            }
        }

        if (-not (Get-ChildItem -Path $src -File -ErrorAction SilentlyContinue)) {
            Write-Host "[install] download failure ref=`"$refForFailure`" url=`"$assetDownloadUrl`" category=CorruptArchive hint=`"Source directory contains no files`""
            Write-Error "Installation failed: Source directory contains no files to install."
        }

        Write-BuildMessage -Type Success -Message "Source directory: $src"

        $step++; Write-Step $step "Copy files into destination"

        # FR-007: Verify all source files remain within destination boundary
        $overlayFiles = Get-ChildItem -Path $src -Recurse -File
        foreach ($file in $overlayFiles) {
            $relativePath = $file.FullName.Substring($src.Length).TrimStart('\', '/')
            $targetPath = Join-Path $destFull $relativePath
            $resolvedTarget = [System.IO.Path]::GetFullPath($targetPath)
            if (-not $resolvedTarget.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "[install] guard RestrictedWrites"
                Write-Error "Installation failed: Security violation - attempt to write outside the destination directory."
            }
        }

        $fileCount = (Get-ChildItem -Path $src -Recurse -File | Measure-Object).Count
        $dirCount  = (Get-ChildItem -Path $src -Recurse -Directory | Measure-Object).Count + 1
        try {
            Copy-Item -Path (Join-Path $src '*') -Destination $destFull -Recurse -Force -ErrorAction Stop
        } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            Write-Host "[install] guard PermissionDenied"
            Write-Error "Installation failed: Permission denied. Please check that you have write permissions to the destination directory."
        }
        Write-BuildMessage -Type Success -Message "Copied $fileCount files across $dirCount directories"

        # For new git repos, create the overlay commit after copying overlay files
        if ($script:IsNewGitRepo) {
            Write-BuildMessage -Type Info -Message "Creating overlay installation commit..."

            $prevErrorAction = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $gitOutput = & git -C "$destFull" add . 2>&1
                $gitOutput = & git -C "$destFull" commit -m "Install AL Build Tools overlay" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[install] git initial_commit=after"
                    Write-BuildMessage -Type Success -Message "Overlay commit created"
                } else {
                    Write-Warning "Git commit returned exit code: $LASTEXITCODE"
                    Write-Host "[install] git initial_commit=after status=failed exit_code=$LASTEXITCODE"
                }
            } finally {
                $ErrorActionPreference = $prevErrorAction
            }
        } else {
            # For existing repos, create overlay commit
            Write-BuildMessage -Type Info -Message "Creating overlay installation commit..."

            $prevErrorAction = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $gitOutput = & git -C "$destFull" add . 2>&1
                $gitOutput = & git -C "$destFull" commit -m "Install AL Build Tools overlay" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[install] git overlay_commit=true"
                    Write-BuildMessage -Type Success -Message "Overlay commit created"
                } else {
                    Write-Warning "Git commit returned exit code: $LASTEXITCODE"
                    Write-Host "[install] git overlay_commit=false exit_code=$LASTEXITCODE"
                }
            } finally {
                $ErrorActionPreference = $prevErrorAction
            }
        }

        $endTime = Get-Date
        $durationSeconds = ($endTime - $startTime).TotalSeconds
        Write-Host "[install] success ref=`"$selectedReleaseTag`" overlay=`"$Source`" asset=`"$assetName`" duration=$($durationSeconds.ToString('F2', [System.Globalization.CultureInfo]::InvariantCulture))"
        Write-BuildMessage -Type Success -Message "Completed: $Source from $Url@$selectedReleaseTag into $destFull"

        # Offer to run provision task
        $step++; Write-Step $step "Optional: Run environment provisioning"

        # Detect non-interactive mode
        $isInteractive = $true
        try {
            if ($null -eq $Host.UI.RawUI -or $Host.Name -eq 'ServerRemoteHost') {
                $isInteractive = $false
            }
        } catch {
            $isInteractive = $false
        }

        if ($isInteractive) {
            Write-Host ""
            Write-Host "NEXT STEP: Environment Provisioning" -ForegroundColor Yellow
            Write-Host "The 'provision' task will:" -ForegroundColor Cyan
            Write-Host "  - Download and install the AL compiler as a .NET tool" -ForegroundColor White
            Write-Host "  - Download Business Central symbol packages based on your app.json" -ForegroundColor White
            Write-Host "  - Cache everything in your user profile for reuse across projects" -ForegroundColor White
            Write-Host ""
            Write-Host "This is a one-time setup per machine (or when dependencies change)." -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Run provision now? (Y/n): " -NoNewline -ForegroundColor Yellow
            $response = Read-Host

            if ([string]::IsNullOrWhiteSpace($response) -or $response -ieq 'y' -or $response -ieq 'yes') {
                Write-Host "[install] provision accepted=true"
                Write-Host ""
                Write-BuildMessage -Type Info -Message "Running: Invoke-Build provision"
                Write-Host ""

                # Change to destination directory and run provision
                Push-Location $destFull
                try {
                    # Use pwsh (PowerShell 7) since Install-Prerequisites ensures it's available
                    $pwshCmd = 'pwsh'
                    # Check if pwsh is available at standard location
                    $standardPwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe'
                    if (Test-Path $standardPwshPath) {
                        $pwshCmd = $standardPwshPath
                    }

                    # Ensure PATH is updated in the new process (includes dotnet, git, etc.)
                    $currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
                    $env:Path = $currentPath

                    # Stream output in real-time (critical for Windows container environments)
                    & $pwshCmd -NoProfile -Command "Invoke-Build provision" 2>&1 | ForEach-Object {
                        Write-Host $_
                        [Console]::Out.Flush()
                    }
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host ""
                        Write-BuildMessage -Type Success -Message "Provision completed successfully!"
                        Write-Host ""
                        Write-Host "You're all set! Try building your project:" -ForegroundColor Green
                        Write-Host "  Invoke-Build build" -ForegroundColor Cyan
                    } else {
                        Write-Warning "Provision task completed with errors (exit code: $LASTEXITCODE)"
                        Write-Host ""
                        Write-Host "You can retry manually by running:" -ForegroundColor Yellow
                        Write-Host "  Invoke-Build provision" -ForegroundColor Cyan
                    }
                } catch {
                    Write-Warning "Failed to run provision: $($_.Exception.Message)"
                    Write-Host ""
                    Write-Host "You can run it manually by executing:" -ForegroundColor Yellow
                    Write-Host "  Invoke-Build provision" -ForegroundColor Cyan
                } finally {
                    Pop-Location
                }
            } else {
                Write-Host "[install] provision accepted=false"
                Write-Host ""
                Write-BuildMessage -Type Info -Message "Skipping provision step"
                Write-Host ""
                Write-Host "To provision your environment later, run:" -ForegroundColor Cyan
                Write-Host "  Invoke-Build provision" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Or provision and build in one command:" -ForegroundColor Cyan
                Write-Host "  Invoke-Build all" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[install] provision skipped (non-interactive mode)"
            Write-Verbose "[install] Non-interactive mode - skipping provision prompt"
            Write-Host ""
            Write-BuildMessage -Type Info -Message "Installation complete. To provision your environment, run: Invoke-Build provision"
        }
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
        Write-Verbose "[install] Auto-run: DestinationPath='$DestinationPath', Ref='$Ref'"
        $installParams = @{
            Url = $Url
            Ref = $Ref
            DestinationPath = $DestinationPath
            Source = $Source
        }
        if ($PSBoundParameters.ContainsKey('HttpTimeoutSec')) {
            $installParams['HttpTimeoutSec'] = $HttpTimeoutSec
        }
        Install-AlBuildTools @installParams
    } catch {
        Write-Host "[install] error unhandled=$(ConvertTo-Json $_.Exception.Message -Compress)"
        Write-Error "Installation failed: An unexpected error occurred during installation. $($_.Exception.Message)"
    }
}
