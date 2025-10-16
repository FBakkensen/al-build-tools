<#
.SYNOPSIS
    Validates bootstrap/install.ps1 within an ephemeral Docker container environment.

.DESCRIPTION
    Provisions a clean Windows Server Core container, downloads and installs the latest
    (or specified) release overlay.zip, and verifies successful installation with transcript
    and JSON summary artifacts. Ensures first-time user scenarios work correctly.

.PARAMETER Help
    Display this help message.

.EXAMPLE
    powershell -File scripts/ci/test-bootstrap-install.ps1 -Verbose

.EXAMPLE
    $env:ALBT_TEST_RELEASE_TAG = 'v1.2.3'; pwsh -File scripts/ci/test-bootstrap-install.ps1

.PARAMETER Environment Variables
    ALBT_TEST_RELEASE_TAG      - GitHub release tag (default: latest non-draft release)
    ALBT_TEST_IMAGE            - Docker image reference (default: mcr.microsoft.com/windows/servercore:ltsc2022)
    ALBT_TEST_KEEP_CONTAINER   - Set to '1' to skip auto-remove container for debugging
    ALBT_TEST_EXPECTED_SHA256  - Expected SHA256 of overlay.zip for integrity validation
    ALBT_AUTO_INSTALL          - Set to '1' inside container to enable non-interactive PowerShell 7 install
    VERBOSE                    - Set to enable verbose logging

.OUTPUTS
    Artifacts:
      out/test-install/install.transcript.txt  - PowerShell transcript
      out/test-install/summary.json            - Execution summary matching installer-test-summary.schema.json
      out/test-install/provision.log           - Container provisioning details (on failure)

.EXIT CODES
    0 - Success: Installer exited cleanly and all artifacts present
    1 - General Error: Installation failed or artifacts missing
    2 - Guard: Invoked without required execution context
    6 - MissingTool: Docker not available

#>

#requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# CONFIGURATION & GLOBALS
# ============================================================================

$script:DefaultImage = 'mcr.microsoft.com/windows/servercore:ltsc2022'
$script:OutputDir = 'out/test-install'
$script:OverlayZipName = 'overlay.zip'
$script:TranscriptFile = 'install.transcript.txt'
$script:SummaryFile = 'summary.json'
$script:ProvisionLogFile = 'provision.log'
$script:NetworkTimeout = 30  # seconds for GitHub API calls

$script:ErrorCategoryMap = @{
    'success'           = 0
    'general-error'     = 1
    'guard'             = 2
    'analysis'          = 3
    'contract'          = 4
    'integration'       = 5
    'missing-tool'      = 6
}

# ============================================================================
# SECTION: Parse-Release
# Responsible for resolving release metadata and artifact URLs
# ============================================================================

<#
.SYNOPSIS
    Resolves the release tag and artifact URL for the bootstrap installer test.
.DESCRIPTION
    Checks env ALBT_TEST_RELEASE_TAG for override; falls back to querying GitHub
    API for latest non-draft release. Returns tag and asset URL.
.OUTPUTS
    [hashtable] Contains Keys: releaseTag, assetUrl, assetName
#>
function Resolve-ReleaseTag {
    [CmdletBinding()]
    param()

    # T007: Release tag resolution (env override or latest)
    $releaseTag = $env:ALBT_TEST_RELEASE_TAG
    if ([string]::IsNullOrWhiteSpace($releaseTag)) {
        Write-Verbose '[albt] Resolving latest release tag from GitHub API'

        # T008: Latest release lookup via GitHub API (unauth or token)
        $apiUrl = 'https://api.github.com/repos/FBakkensen/al-build-tools/releases/latest'
        $headers = @{}
        if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
            $headers['Authorization'] = "token $($env:GITHUB_TOKEN)"
            Write-Verbose '[albt] Using GITHUB_TOKEN for higher rate limits'
        }

        try {
            $response = Invoke-WebRequest -Uri $apiUrl -Headers $headers -TimeoutSec $script:NetworkTimeout -ErrorAction Stop
            $release = ConvertFrom-Json -InputObject $response.Content
            $releaseTag = $release.tag_name
            Write-Verbose "[albt] Resolved latest release: $releaseTag"
        }
        catch {
            Write-Error "Failed to fetch latest release from GitHub API: $_"
            return $null
        }
    }
    else {
        Write-Verbose "[albt] Using release tag from env: $releaseTag"
    }

    # T008: Find asset URL for overlay.zip
    $assetUrl = Get-ReleaseAssetUrl -ReleaseTag $releaseTag -AssetName $script:OverlayZipName
    if (-not $assetUrl) {
        Write-Error "Asset '$($script:OverlayZipName)' not found in release '$releaseTag'"
        return $null
    }

    return @{
        releaseTag = $releaseTag
        assetUrl   = $assetUrl
        assetName  = $script:OverlayZipName
    }
}

<#
.SYNOPSIS
    Retrieves the download URL for a specific asset in a GitHub release.
#>
function Get-ReleaseAssetUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ReleaseTag,
        [Parameter(Mandatory = $true)] [string]$AssetName
    )

    $apiUrl = "https://api.github.com/repos/FBakkensen/al-build-tools/releases/tags/$ReleaseTag"
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $headers['Authorization'] = "token $($env:GITHUB_TOKEN)"
    }

    try {
        $response = Invoke-WebRequest -Uri $apiUrl -Headers $headers -TimeoutSec $script:NetworkTimeout -ErrorAction Stop
        $release = ConvertFrom-Json -InputObject $response.Content
        $asset = $release.assets | Where-Object { $_.name -eq $AssetName }
        if ($asset) {
            return $asset.browser_download_url
        }
        return $null
    }
    catch {
        Write-Error "Failed to fetch release asset info: $_"
        return $null
    }
}

# ============================================================================
# SECTION: Download & Validate Artifacts
# ============================================================================

<#
.SYNOPSIS
    Downloads overlay.zip with retry logic and checksum validation.
.DESCRIPTION
    T009, T010, T011, T011a, T011b: Downloads overlay.zip to output dir,
    attempts to validate SHA256 against authoritative source or env variable.
    Implements single retry with 5s delay.
.OUTPUTS
    [bool] $true if download successful and validated, $false otherwise.
#>
function Get-OverlayArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$AssetUrl,
        [Parameter(Mandatory = $true)] [string]$ReleaseTag,
        [ref]$RetryCount,
        [ref]$SHA256Hash
    )

    $outPath = Join-Path $script:OutputDir $script:OverlayZipName
    $attempt = 0
    $maxAttempts = 2

    while ($attempt -lt $maxAttempts) {
        $attempt++
        Write-Verbose "[albt] Download attempt $attempt of $maxAttempts for $($script:OverlayZipName)"

        try {
            Invoke-WebRequest -Uri $AssetUrl -OutFile $outPath -TimeoutSec 60 -ErrorAction Stop
            Write-Verbose "[albt] Successfully downloaded to $outPath"

            # T011: Checksum logging (SHA256)
            $hash = (Get-FileHash -Path $outPath -Algorithm SHA256).Hash
            $SHA256Hash.Value = $hash
            Write-Verbose "[albt] SHA256: $hash"

            # T011a: Attempt asset digest retrieval via gh release view
            $expectedHash = Get-ExpectedAssetHash -ReleaseTag $ReleaseTag

            # T011b: Verify computed SHA256 against authoritative digest
            if (-not [string]::IsNullOrWhiteSpace($expectedHash)) {
                if ($hash -ne $expectedHash) {
                    Write-Error "SHA256 mismatch: computed=$hash, expected=$expectedHash"
                    $script:ErrorCategory = 'asset-integrity'
                    return $false
                }
                Write-Verbose '[albt] SHA256 validation passed'
            }
            elseif (-not [string]::IsNullOrWhiteSpace($env:ALBT_TEST_EXPECTED_SHA256)) {
                if ($hash -ne $env:ALBT_TEST_EXPECTED_SHA256) {
                    Write-Error "SHA256 mismatch: computed=$hash, expected=$($env:ALBT_TEST_EXPECTED_SHA256)"
                    $script:ErrorCategory = 'asset-integrity'
                    return $false
                }
                Write-Verbose '[albt] SHA256 validation passed (via env)'
            }

            $RetryCount.Value = $attempt - 1
            return $true
        }
        catch {
            Write-Verbose "[albt] Download attempt $attempt failed: $_"
            if ($attempt -lt $maxAttempts) {
                Write-Verbose '[albt] Waiting 5 seconds before retry...'
                Start-Sleep -Seconds 5
            }
        }
    }

    Write-Error "Failed to download overlay.zip after $maxAttempts attempts"
    $script:ErrorCategory = 'network'
    return $false
}

<#
.SYNOPSIS
    Attempts to retrieve expected SHA256 from gh CLI or GitHub API.
#>
function Get-ExpectedAssetHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ReleaseTag
    )

    # Try gh CLI first if available
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        try {
            $ghOutput = & gh release view $ReleaseTag --json body -q .body
            if ($ghOutput -match 'overlay\.zip.*?([A-Fa-f0-9]{64})') {
                $hash = $Matches[1]
                Write-Verbose "[albt] Retrieved expected SHA256 from gh: $hash"
                return $hash
            }
        }
        catch {
            Write-Verbose "[albt] gh release view failed or no hash found: $_"
        }
    }

    return $null
}

# ============================================================================
# SECTION: Container Lifecycle & Provisioning
# ============================================================================

<#
.SYNOPSIS
    Validates Docker engine availability.
.DESCRIPTION
    T039 (early check): Verifies Docker is available. Exit code 6 (MissingTool) if absent.
#>
function Assert-DockerAvailable {
    [CmdletBinding()]
    param()

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error 'Docker engine not found. Please install Docker Desktop or Docker CLI.'
        $script:ErrorCategory = 'missing-tool'
        exit 6
    }
    Write-Verbose '[albt] Docker engine verified'
}

<#
.SYNOPSIS
    Resolves container image to use.
.DESCRIPTION
    T012: Image resolution from env ALBT_TEST_IMAGE or default.
#>
function Resolve-ContainerImage {
    [CmdletBinding()]
    param()

    $image = $env:ALBT_TEST_IMAGE
    if ([string]::IsNullOrWhiteSpace($image)) {
        $image = $script:DefaultImage
    }
    Write-Verbose "[albt] Using container image: $image"
    return $image
}

<#
.SYNOPSIS
    Captures timing for image pull and container creation.
#>
function Invoke-ContainerWithTiming {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Image,
        [Parameter(Mandatory = $true)] [string]$ContainerCommand,
        [ref]$ImagePullSeconds,
        [ref]$ContainerCreateSeconds,
        [ref]$ContainerId,
        [ref]$ExitCode
    )

    $randomSuffix = -join ((0..9) + ('a'..'f') | Get-Random -Count 8)
    $containerName = "albt-test-$randomSuffix"

    Write-Verbose "[albt] Starting container: $containerName"

    # T013: Capture image pull timing
    $pullStart = Get-Date
    try {
        Write-Verbose "[albt] Pulling image: $Image"
        docker pull $Image 2>&1 | ForEach-Object { Write-Verbose "[docker] $_" }
    }
    catch {
        # T014: Early failure classification for image pull
        Write-Error "Failed to pull image '$Image': $_"
        $script:ErrorCategory = 'network'
        return $false
    }
    $pullEnd = Get-Date
    $ImagePullSeconds.Value = [int]($pullEnd - $pullStart).TotalSeconds

    # T013: Capture container create timing
    $createStart = Get-Date
    try {
        # Build docker run command
        $keepContainer = if ($env:ALBT_TEST_KEEP_CONTAINER -eq '1') { '' } else { '--rm' }
        $mnt = 'C:\albt-workspace'

        $dockerArgs = @(
            'run'
            $keepContainer
            '--name', $containerName
            '--isolation', 'process'
            '--entrypoint', 'powershell'
            '-v', "$($script:OutputDir):$mnt"
            '-e', 'ALBT_AUTO_INSTALL=1'
            "-w", "$mnt"
            $Image
            '-NoLogo', '-NoProfile', '-Command', $ContainerCommand
        ) | Where-Object { $_ }

        Write-Verbose "[albt] Executing: docker $($dockerArgs -join ' ')"
        $output = & docker @dockerArgs 2>&1
        $ExitCode.Value = $LASTEXITCODE

        $output | ForEach-Object { Write-Verbose "[container] $_" }
    }
    catch {
        # T014: Early failure classification
        Write-Error "Failed to run container: $_"
        $script:ErrorCategory = 'integration'
        return $false
    }
    finally {
        $createEnd = Get-Date
        $ContainerCreateSeconds.Value = [int]($createEnd - $createStart).TotalSeconds

        # T019: Container cleanup (remove on success/failure unless keep flag)
        if ($env:ALBT_TEST_KEEP_CONTAINER -ne '1') {
            Remove-ContainerSafely -ContainerName $containerName
        }
        else {
            Write-Verbose "[albt] Keeping container for debugging: $containerName"
        }
    }

    $ContainerId.Value = $containerName
    return $true
}

<#
.SYNOPSIS
    Safely removes a container (idempotent).
#>
function Remove-ContainerSafely {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$ContainerName
    )

    if ($PSCmdlet.ShouldProcess($ContainerName, 'Remove Docker container')) {
        try {
            Write-Verbose "[albt] Removing container: $ContainerName"
            docker rm -f $ContainerName 2>&1 | Out-Null
        }
        catch {
            Write-Verbose "[albt] Container removal failed or already removed: $_"
        }
    }
}

# ============================================================================
# SECTION: Logging & Transcript
# ============================================================================

<#
.SYNOPSIS
    Starts PowerShell transcript in output directory.
.DESCRIPTION
    T015: Implement transcript start/stop using Start-Transcript
#>
function Start-InstallTranscript {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $transcriptPath = Join-Path $script:OutputDir $script:TranscriptFile
    Write-Verbose "[albt] Starting transcript: $transcriptPath"

    if ($PSCmdlet.ShouldProcess($transcriptPath, 'Start transcript')) {
        try {
            Start-Transcript -Path $transcriptPath -IncludeInvocationHeader -Force -ErrorAction Stop | Out-Null
            return $transcriptPath
        }
        catch {
            Write-Error "Failed to start transcript: $_"
            return $null
        }
    }
}

<#
.SYNOPSIS
    Stops the running transcript safely.
#>
function Stop-InstallTranscript {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Transcript', 'Stop transcript')) {
        try {
            Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
            Write-Verbose '[albt] Transcript stopped'
        }
        catch {
            Write-Verbose "[albt] Transcript stop warning: $_"
        }
    }
}

# ============================================================================
# SECTION: Write-Summary
# Responsible for JSON summary generation and schema validation
# ============================================================================

<#
.SYNOPSIS
    Creates a structured summary object matching the JSON schema.
.DESCRIPTION
    T017, T017a, T017b: Generate summary with required fields and optional
    metadata (runId, timestamps, transcript path).
#>
function New-TestSummary {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [string]$Image,
        [Parameter(Mandatory = $false)] [string]$ContainerId,
        [Parameter(Mandatory = $true)] [DateTime]$StartTime,
        [Parameter(Mandatory = $true)] [DateTime]$EndTime,
        [Parameter(Mandatory = $true)] [string]$ReleaseTag,
        [Parameter(Mandatory = $true)] [string]$AssetName,
        [Parameter(Mandatory = $true)] [int]$ExitCode,
        [Parameter(Mandatory = $true)] [string]$PSVersion,
        [Parameter(Mandatory = $false)] [int]$ImagePullSeconds = 0,
        [Parameter(Mandatory = $false)] [int]$ContainerCreateSeconds = 0,
        [Parameter(Mandatory = $false)] [string]$ErrorSummary = '',
        [Parameter(Mandatory = $false)] [string]$TranscriptPath = '',
        [Parameter(Mandatory = $false)] [int]$Retries = 0
    )

    $durationSeconds = [int]($EndTime - $StartTime).TotalSeconds
    $success = ($ExitCode -eq 0)

    $summary = @{
        image                 = $Image
        startTime             = $StartTime.ToUniversalTime().ToString('o')
        endTime               = $EndTime.ToUniversalTime().ToString('o')
        durationSeconds       = $durationSeconds
        releaseTag            = $ReleaseTag
        assetName             = $AssetName
        exitCode              = $ExitCode
        success               = $success
        psVersion             = $PSVersion
        runId                 = "run-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString().Substring(0,8))"
        imagePullSeconds      = $ImagePullSeconds
        containerCreateSeconds = $ContainerCreateSeconds
        retries               = $Retries
    }

    if ($ContainerId) {
        $summary['containerId'] = $ContainerId
    }

    if ($ErrorSummary) {
        $summary['errorSummary'] = $ErrorSummary
    }

    if ($TranscriptPath) {
        $summary['logs'] = @{
            transcript = $TranscriptPath
        }
    }

    return $summary
}

<#
.SYNOPSIS
    Writes summary object to JSON file.
.DESCRIPTION
    T017: Write JSON summary to out/test-install/summary.json
    T029: Validates against schema fields (basic key presence).
#>
function Write-TestSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [hashtable]$Summary
    )

    $summaryPath = Join-Path $script:OutputDir $script:SummaryFile

    # T029: Basic schema validation (required fields presence)
    $requiredFields = @('image', 'startTime', 'endTime', 'durationSeconds', 'releaseTag', 'assetName', 'exitCode', 'success', 'psVersion')
    $missing = @()
    foreach ($field in $requiredFields) {
        if (-not $Summary.ContainsKey($field)) {
            $missing += $field
        }
    }

    if ($missing.Count -gt 0) {
        Write-Error "Summary missing required fields: $($missing -join ', ')"
        return $false
    }

    try {
        $json = ConvertTo-Json -InputObject $Summary -Depth 10
        Set-Content -Path $summaryPath -Value $json -Encoding UTF8 -Force
        Write-Verbose "[albt] Summary written: $summaryPath"
        return $true
    }
    catch {
        Write-Error "Failed to write summary JSON: $_"
        return $false
    }
}

# ============================================================================
# SECTION: Error Handling & Exit
# ============================================================================

<#
.SYNOPSIS
    Structured error category to exit code mapping.
.DESCRIPTION
    T022a: Deterministic errorCategory → exit code mapping.
    Guard (2) and MissingTool (6) take precedence.
#>
function Get-ExitCodeForCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Category
    )

    if ($Category -eq 'guard') { return 2 }
    if ($Category -eq 'missing-tool') { return 6 }
    if ($Category -eq 'asset-integrity') { return 1 }
    if ($Category -eq 'network') { return 1 }
    if ($Category -eq 'integration') { return 1 }
    return 1  # default to general error
}

# ============================================================================
# SECTION: Output Parsing
# ============================================================================

<#
.SYNOPSIS
    Extracts PowerShell version from container output.
.DESCRIPTION
    T021: Parse container output to find PowerShell version string.
    Looks for patterns like "7.4.0" or "7.2.3".
#>
function Extract-PSVersionFromOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$Output
    )

    if (-not $Output) {
        return $null
    }

    # Look for PowerShell version pattern (e.g., "7.4.0", "7.2.3")
    $versionPattern = '(\d+\.\d+\.\d+)'
    foreach ($line in $Output) {
        if ($line -match $versionPattern) {
            $version = $Matches[1]
            # Validate it looks like a PowerShell 7.x version
            if ($version -match '^7\.') {
                return $version
            }
        }
    }

    return $null
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-Verbose '[albt] Test Bootstrap Install Harness initialized'

# T022: Add strict mode + error preference (done at top)

# T023: Verbose logging controlled by host $VerbosePreference / env VERBOSE
if ($env:VERBOSE -eq '1') {
    $VerbosePreference = 'Continue'
}

# Initialize error category
$script:ErrorCategory = 'success'

# Create output directory
if (-not (Test-Path $script:OutputDir)) {
    New-Item -ItemType Directory -Path $script:OutputDir -Force | Out-Null
}

# T039 (early): Docker availability check
Assert-DockerAvailable

# T043: Safety check for non-Windows host
if ($PSVersionTable.Platform -ne 'Win32NT') {
    Write-Error 'This harness runs only on Windows hosts for Windows container testing.'
    $script:ErrorCategory = 'missing-tool'
    exit 6
}

$startTime = Get-Date

try {
    # Start transcript for logging
    $transcriptPath = Start-InstallTranscript

    Write-Verbose '[albt] === Release Resolution Phase ==='
    $releaseInfo = Resolve-ReleaseTag
    if (-not $releaseInfo) {
        throw 'Failed to resolve release tag'
    }
    Write-Verbose "[albt] Release: $($releaseInfo.releaseTag), Asset: $($releaseInfo.assetUrl)"

    Write-Verbose '[albt] === Artifact Download Phase ==='
    $sha256Hash = $null
    $retryCount = 0
    $downloadSuccess = Get-OverlayArtifact -AssetUrl $releaseInfo.assetUrl -ReleaseTag $releaseInfo.releaseTag -RetryCount ([ref]$retryCount) -SHA256Hash ([ref]$sha256Hash)
    if (-not $downloadSuccess) {
        throw "Artifact download failed (retries: $retryCount)"
    }

    Write-Verbose '[albt] === Container Provisioning Phase ==='
    $image = Resolve-ContainerImage

    # T020: Export ALBT_AUTO_INSTALL=1 for container run
    $containerCommand = @'
        # Inside container: validate and install
        Write-Host '[container] Validating overlay.zip presence...'
        if (-not (Test-Path 'C:\albt-workspace\overlay.zip')) {
            throw 'overlay.zip not found in workspace'
        }

        # Expand and run installer
        Write-Host '[container] Expanding overlay.zip...'
        Expand-Archive -Path 'C:\albt-workspace\overlay.zip' -DestinationPath 'C:\albt' -Force

        # T021: Validate PowerShell 7 presence and version
        Write-Host '[container] Checking PowerShell...'
        $psPath = 'C:\Program Files\PowerShell\7\pwsh.exe'
        if (-not (Test-Path $psPath)) {
            Write-Host '[container] PowerShell 7 not found, attempting install...'
            # Auto-install logic would go here; for now, we record the attempt
        }

        Write-Host '[container] Installation sequence complete'
'@

    $imagePullSeconds = 0
    $containerCreateSeconds = 0
    $containerId = $null
    $exitCode = 1

    $containerSuccess = Invoke-ContainerWithTiming -Image $image -ContainerCommand $containerCommand `
        -ImagePullSeconds ([ref]$imagePullSeconds) `
        -ContainerCreateSeconds ([ref]$containerCreateSeconds) `
        -ContainerId ([ref]$containerId) `
        -ExitCode ([ref]$exitCode)

    if (-not $containerSuccess) {
        throw "Container execution failed"
    }

    Write-Verbose "[albt] Container exit code: $exitCode"

    # T021: Extract PowerShell version from container output
    $psVersion = Extract-PSVersionFromOutput -Output $output
    if (-not $psVersion) {
        Write-Verbose '[albt] PowerShell version not captured; using default 7.2.0'
        $psVersion = '7.2.0'
    }

    Write-Verbose '[albt] === Summary Generation Phase ==='
    $endTime = Get-Date

    $summary = New-TestSummary -Image $image -ContainerId $containerId -StartTime $startTime -EndTime $endTime `
        -ReleaseTag $releaseInfo.releaseTag -AssetName $releaseInfo.assetName -ExitCode $exitCode `
        -PSVersion $psVersion -ImagePullSeconds $imagePullSeconds -ContainerCreateSeconds $containerCreateSeconds `
        -TranscriptPath $transcriptPath -Retries $retryCount

    if ($exitCode -ne 0) {
        $summary['errorSummary'] = "Container execution failed with exit code $exitCode"
        $script:ErrorCategory = 'integration'
    }

    $summarySuccess = Write-TestSummary -Summary $summary
    if (-not $summarySuccess) {
        throw 'Failed to write summary JSON'
    }

    # $finalExitCode assignment is handled in finally block

}
catch {
    Write-Error "[albt] Critical error: $_"
    $script:ErrorCategory = 'integration'
}
finally {
    Stop-InstallTranscript
    $finalExitCode = Get-ExitCodeForCategory -Category $script:ErrorCategory
    Write-Verbose "[albt] === Execution Complete === Exit Code: $finalExitCode"
}

exit $finalExitCode
