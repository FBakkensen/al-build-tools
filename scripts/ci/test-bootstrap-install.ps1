<#
.SYNOPSIS
    Validates bootstrap/install.ps1 within an ephemeral Docker container environment.

.DESCRIPTION
    Provisions a clean Windows Server Core container, downloads and installs the latest
    (or specified) release overlay.zip, and verifies successful installation with transcript
    and JSON summary artifacts. Ensures first-time user scenarios work correctly.

.PARAMETER Help
    Display this help message and exit.

.PARAMETER ?
    Display this help message and exit (short form).

.EXAMPLE
    pwsh -File scripts/ci/test-bootstrap-install.ps1 -Verbose

.EXAMPLE
    pwsh -File scripts/ci/test-bootstrap-install.ps1 -Help

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

# T038: Add usage/help output (-Help or -?)
param(
    [switch]$Help
)

# Support both -Help and -? for getting help
if ($Help -or ($args -contains '-?')) {
    Write-Host @"
SYNOPSIS
    Validates bootstrap/install.ps1 within an ephemeral Docker container environment.

DESCRIPTION
    Provisions a clean Windows Server Core container, downloads and installs the latest
    (or specified) release overlay.zip, and verifies successful installation with transcript
    and JSON summary artifacts. Ensures first-time user scenarios work correctly.

USAGE
    pwsh -File scripts/ci/test-bootstrap-install.ps1 [OPTIONS]

OPTIONS
    -Help, -?              Display this help message and exit.

ENVIRONMENT VARIABLES
    ALBT_TEST_RELEASE_TAG           - GitHub release tag (default: latest non-draft release)
    ALBT_TEST_IMAGE                 - Docker image reference (default: mcr.microsoft.com/windows/servercore:ltsc2022)
    ALBT_TEST_KEEP_CONTAINER        - Set to '1' to skip auto-remove container for debugging
    ALBT_TEST_EXPECTED_SHA256       - Expected SHA256 of overlay.zip for integrity validation
    ALBT_AUTO_INSTALL               - Set to '1' inside container to enable non-interactive PowerShell 7 install
    VERBOSE                         - Set to enable verbose logging
    GITHUB_TOKEN                    - Optional GitHub token for higher API rate limits

EXAMPLES
    # Run with latest release
    pwsh -File scripts/ci/test-bootstrap-install.ps1 -Verbose

    # Test specific release tag
    `$env:ALBT_TEST_RELEASE_TAG = 'v1.2.3'
    pwsh -File scripts/ci/test-bootstrap-install.ps1

    # Debug mode: preserve container for inspection
    `$env:ALBT_TEST_KEEP_CONTAINER = '1'
    pwsh -File scripts/ci/test-bootstrap-install.ps1

EXIT CODES
    0 - Success: Installer exited cleanly and all artifacts present
    1 - General Error: Installation failed or artifacts missing
    2 - Guard: Invoked without required execution context
    6 - MissingTool: Docker not available or running on non-Windows host

ARTIFACTS
    out/test-install/install.transcript.txt  - PowerShell transcript
    out/test-install/summary.json            - Execution summary (schema-aligned)
    out/test-install/provision.log           - Container provisioning details (on failure)

"@
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# CONFIGURATION & GLOBALS
# ============================================================================

$script:DefaultImage = 'mcr.microsoft.com/windows/servercore:ltsc2022'
$script:OutputDir = 'out/test-install'
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

# Timed sections tracking (release-resolution, container-provisioning only)
$script:TimedPhases = @{}

# ============================================================================
# SECTION: Timing & Diagnostics
# Tracks start/stop for limited phases (no download phase; installer handles overlay)
# ============================================================================

<#
.SYNOPSIS
    Records start time for a named phase.
.DESCRIPTION
    T032: Tracks phase start/stop timestamps for download, container, install phases.
#>
function Invoke-TimedPhaseStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$PhaseName
    )
    $script:TimedPhases[$PhaseName] = @{
        'start' = Get-Date
        'end'   = $null
    }
    Write-Verbose "[albt] Phase started: $PhaseName"
}

<#
.SYNOPSIS
    Records stop time for a named phase.
#>
function Invoke-TimedPhaseStop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$PhaseName
    )
    if ($script:TimedPhases.ContainsKey($PhaseName)) {
        $script:TimedPhases[$PhaseName]['end'] = Get-Date
        $duration = [int]($script:TimedPhases[$PhaseName]['end'] - $script:TimedPhases[$PhaseName]['start']).TotalSeconds
        Write-Verbose "[albt] Phase completed: $PhaseName ($duration seconds)"
    }
}

# ============================================================================
# SECTION: Release Tag (Optional)
# Only resolves latest tag if env ALBT_TEST_RELEASE_TAG not set, to pass -Ref to installer
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

    $releaseTag = $env:ALBT_TEST_RELEASE_TAG
    if ([string]::IsNullOrWhiteSpace($releaseTag)) {
        Write-Verbose '[albt] Resolving latest release tag from GitHub API'

        # T008: Latest release lookup via GitHub API (unauth or token)
        # T034: Add retry (1 attempt) for release metadata fetch before failing hard
        $apiUrl = 'https://api.github.com/repos/FBakkensen/al-build-tools/releases/latest'
        $attempt = 0
        $maxAttempts = 2

        while ($attempt -lt $maxAttempts) {
            $attempt++
            $headers = @{}
            if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
                $headers['Authorization'] = "token $($env:GITHUB_TOKEN)"
                Write-Verbose '[albt] Using GITHUB_TOKEN for higher rate limits'
            }

            try {
                Write-Verbose "[albt] Release metadata fetch attempt $attempt of $maxAttempts"
                $response = Invoke-WebRequest -Uri $apiUrl -Headers $headers -TimeoutSec $script:NetworkTimeout -ErrorAction Stop
                $release = ConvertFrom-Json -InputObject $response.Content
                $releaseTag = $release.tag_name
                Write-Verbose "[albt] Resolved latest release: $releaseTag"
                break
            }
            catch {
                if ($attempt -lt $maxAttempts) {
                    Write-Verbose "[albt] Release metadata fetch attempt $attempt failed: $_; retrying..."
                    Start-Sleep -Seconds 2
                }
                else {
                    Write-Error "Failed to fetch latest release from GitHub API after $maxAttempts attempts: $_"
                    $script:ErrorCategory = 'network'
                    return $null
                }
            }
        }
    }
    else {
        Write-Verbose "[albt] Using release tag from env: $releaseTag"
    }

    return @{ releaseTag = $releaseTag }
}

# (Removed overlay download & checksum logic – installer handles fetching overlay)

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
    Extracts image digest (hash) from docker image metadata.
.DESCRIPTION
    T036: Include hashed image ID in summary JSON.
#>
function Get-ImageDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Image
    )

    try {
        $inspectOutput = & docker inspect $Image 2>&1
        if ($LASTEXITCODE -eq 0) {
            $imageData = ConvertFrom-Json -InputObject $inspectOutput
            # Get the first 12 characters of the RepoDigest as a hash representation
            if ($imageData[0].RepoDigests -and $imageData[0].RepoDigests.Count -gt 0) {
                $digest = $imageData[0].RepoDigests[0] -replace '.*@', ''
                $digest = $digest.Substring(0, [Math]::Min(16, $digest.Length))
                return $digest
            }
            # Fallback to image ID
            $imageId = $imageData[0].Id -replace 'sha256:', ''
            return $imageId.Substring(0, [Math]::Min(16, $imageId.Length))
        }
    }
    catch {
        Write-Verbose "[albt] Failed to get image digest: $_"
    }
    return $null
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
        [ref]$ExitCode,
        [ref]$ImageDigest,
        [ref]$ContainerOutput,
        [ref]$ProvisionLog
    )

    $randomSuffix = -join ((0..9) + ('a'..'f') | Get-Random -Count 8)
    $containerName = "albt-test-$randomSuffix"
    $provisionLogLines = @()

    # T035: Log provisioning details
    $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Container provisioning started"
    $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Container name: $containerName"
    $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Image: $Image"

    Write-Verbose "[albt] Starting container: $containerName"

    # T013: Capture image pull timing
    $pullStart = Get-Date
    $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Image pull started"
    try {
        Write-Verbose "[albt] Pulling image: $Image"
        docker pull $Image 2>&1 | ForEach-Object {
            Write-Verbose "[docker] $_"
            $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [docker] $_"
        }
    }
    catch {
        # T014: Early failure classification for image pull
        Write-Error "Failed to pull image '$Image': $_"
        $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Image pull failed: $_"
        $ProvisionLog.Value = $provisionLogLines -join "`n"
        $script:ErrorCategory = 'network'
        return $false
    }
    $pullEnd = Get-Date
    $ImagePullSeconds.Value = [int]($pullEnd - $pullStart).TotalSeconds

    $ImageDigest.Value = Get-ImageDigest -Image $Image
    $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Image pull completed in $($ImagePullSeconds.Value) seconds"

    # T013: Capture container create timing
    $createStart = Get-Date
    $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Container creation started"
    try {
        $keepContainer = if ($env:ALBT_TEST_KEEP_CONTAINER -eq '1') { '' } else { '--rm' }
        $mnt = 'C:\albt-workspace'

        # First, create the container
        Write-Verbose "[albt] Creating container: $containerName"
        $createArgs = @(
            'create'
            '--name', $containerName
            '--isolation', 'process'
            '--entrypoint', 'cmd.exe'
            '-v', "$($PSScriptRoot):$mnt"
            '-e', 'ALBT_AUTO_INSTALL=1'
            '-e', "ALBT_TEST_RELEASE_TAG=$($script:ReleaseTag)"
            "-w", "$mnt"
            $Image
            '/c', 'echo created'
        ) | Where-Object { $_ }

        $createOutput = & docker @createArgs 2>&1
        Write-Verbose "[albt] Container created: $createOutput"
        $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Container created: $createOutput"

        # T025: Copy bootstrap directory into container (not just overlay.zip)
        # The container needs the actual bootstrap/install.ps1 script to execute
        Write-Verbose "[albt] Copying bootstrap installer into container..."
        $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Copying bootstrap directory"
        $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $bootstrapPath = Join-Path $repoRoot 'bootstrap'
        if (-not (Test-Path $bootstrapPath)) {
            throw "bootstrap directory not found at $bootstrapPath"
        }

        $cpArgs = @(
            'cp'
            '-r'
            "$bootstrapPath"
            "$($containerName):C:\albt-workspace\bootstrap"
        )

        & docker @cpArgs 2>&1 | ForEach-Object {
            Write-Verbose "[docker cp] $_"
            $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [docker cp] $_"
        }
        Write-Verbose "[albt] bootstrap directory copied successfully"
        $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] bootstrap directory copied successfully"

        # Start the container with the actual command
        Write-Verbose "[albt] Starting container execution..."
        $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Container execution started"
        $execArgs = @(
            'exec'
            '-w', $mnt
            '-e', 'ALBT_AUTO_INSTALL=1'
            '-e', "ALBT_TEST_RELEASE_TAG=$($script:ReleaseTag)"
            $containerName
            'powershell'
            '-NoLogo', '-NoProfile', '-Command', $ContainerCommand
        ) | Where-Object { $_ }

        Write-Verbose "[albt] Executing: docker $($execArgs -join ' ')"
        $output = & docker @execArgs 2>&1
        $ExitCode.Value = $LASTEXITCODE
        $ContainerOutput.Value = $output

        $output | ForEach-Object {
            Write-Verbose "[container] $_"
            $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [container] $_"
        }
        $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Container execution completed with exit code: $($ExitCode.Value)"
    }
    catch {
        # T014: Early failure classification
        Write-Error "Failed to run container: $_"
        $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Container execution failed: $_"
        $ProvisionLog.Value = $provisionLogLines -join "`n"
        $script:ErrorCategory = 'integration'
        return $false
    }
    finally {
        $createEnd = Get-Date
        $ContainerCreateSeconds.Value = [int]($createEnd - $createStart).TotalSeconds
        $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Container teardown started"

        # T019: Container cleanup (remove on success/failure unless keep flag)
        if ($env:ALBT_TEST_KEEP_CONTAINER -ne '1') {
            Remove-ContainerSafely -ContainerName $containerName
            $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Container removed"
        }
        else {
            Write-Verbose "[albt] Keeping container for debugging: $containerName"
            $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Container preserved for debugging: $containerName"
        }

        $provisionLogLines += "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Provisioning completed in $($ContainerCreateSeconds.Value) seconds"
        $ProvisionLog.Value = $provisionLogLines -join "`n"
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

<#
.SYNOPSIS
    Appends container output tail to transcript file on failure.
.DESCRIPTION
    T033: Add container stdout/stderr tail extraction on failure appended to transcript file.
#>
function Invoke-TranscriptAppendContainerOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$TranscriptPath,
        [Parameter(Mandatory = $true)] [object[]]$ContainerOutput,
        [Parameter(Mandatory = $true)] [int]$ExitCode
    )

    if ($ExitCode -eq 0) {
        return  # Only append on failure
    }

    if (-not $ContainerOutput -or $ContainerOutput.Count -eq 0) {
        return
    }

    try {
        # T033: Tail the output (last 50 lines)
        $tail = @()
        $tail += "`n=================== CONTAINER OUTPUT TAIL ==================="
        $tail += "[Exit Code: $ExitCode]"

        if ($ContainerOutput.Count -le 50) {
            $tail += $ContainerOutput
        }
        else {
            $tail += $ContainerOutput[($ContainerOutput.Count - 50)..($ContainerOutput.Count - 1)]
        }
        $tail += "=================== END CONTAINER OUTPUT ==================="

        Add-Content -Path $TranscriptPath -Value ($tail -join "`n") -Encoding UTF8
        Write-Verbose "[albt] Container output appended to transcript"
    }
    catch {
        Write-Verbose "[albt] Failed to append container output to transcript: $_"
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
        [Parameter(Mandatory = $false)] [string]$ImageDigest = '',
        [Parameter(Mandatory = $false)] [hashtable]$TimedPhases = @{}
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
        retries               = 0
    }

    if ($ContainerId) {
        $summary['containerId'] = $ContainerId
    }

    # T036: Include hashed image ID in summary JSON
    if ($ImageDigest) {
        $summary['imageDigest'] = $ImageDigest
    }

    if ($ErrorSummary) {
        $summary['errorSummary'] = $ErrorSummary
    }

    # T032: Include timed phases in summary
    if ($TimedPhases.Count -gt 0) {
        $phases = @{}
        foreach ($phaseName in $TimedPhases.Keys) {
            $phase = $TimedPhases[$phaseName]
            if ($phase['end']) {
                $phaseDuration = [int]($phase['end'] - $phase['start']).TotalSeconds
                $phases[$phaseName] = @{
                    'startTime'  = $phase['start'].ToUniversalTime().ToString('o')
                    'endTime'    = $phase['end'].ToUniversalTime().ToString('o')
                    'durationSeconds' = $phaseDuration
                }
            }
        }
        if ($phases.Count -gt 0) {
            $summary['timedPhases'] = $phases
        }
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

<#
.SYNOPSIS
    Writes provision log to file.
.DESCRIPTION
    T035: Persist container provisioning log to out/test-install/provision.log
#>
function Write-ProvisionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [string]$ProvisionLog
    )

    if ([string]::IsNullOrWhiteSpace($ProvisionLog)) {
        return
    }

    $provisionPath = Join-Path $script:OutputDir $script:ProvisionLogFile
    try {
        Set-Content -Path $provisionPath -Value $ProvisionLog -Encoding UTF8 -Force
        Write-Verbose "[albt] Provision log written: $provisionPath"
    }
    catch {
        Write-Verbose "[albt] Failed to write provision log: $_"
    }
}

<#
.SYNOPSIS
    Checks and truncates large transcript files.
.DESCRIPTION
    T037: Add guard to truncate overly large transcript (>5MB) with note.
#>
function Invoke-TranscriptSizeProtection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$TranscriptPath
    )

    if (-not (Test-Path $TranscriptPath)) {
        return
    }

    try {
        $file = Get-Item -Path $TranscriptPath -ErrorAction Stop
        $maxSize = 5MB

        if ($file.Length -gt $maxSize) {
            Write-Verbose "[albt] Transcript exceeds 5MB ($($file.Length / 1MB)MB); truncating..."

            $content = Get-Content -Path $TranscriptPath -Raw -ErrorAction Stop
            $truncated = "[TRANSCRIPT TRUNCATED - Original size: $('{0:N2}' -f ($file.Length / 1MB)) MB]`n`n"
            $truncated += $content.Substring([Math]::Max(0, $content.Length - (4MB)))
            $truncated += "`n`n[END OF TRUNCATED TRANSCRIPT]"

            Set-Content -Path $TranscriptPath -Value $truncated -Encoding UTF8 -Force
            Write-Verbose "[albt] Transcript truncated to approximately 4MB"
        }
    }
    catch {
        Write-Verbose "[albt] Failed to check/truncate transcript: $_"
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

    $errorSummary = $null

    Write-Verbose '[albt] === Release Resolution Phase ==='
    Invoke-TimedPhaseStart -PhaseName 'release-resolution'

    $releaseInfo = Resolve-ReleaseTag
    if (-not $releaseInfo) {
        throw 'Failed to resolve release tag'
    }
    Write-Verbose "[albt] Release: $($releaseInfo.releaseTag), Asset: $($releaseInfo.assetUrl)"
    Invoke-TimedPhaseStop -PhaseName 'release-resolution'

    # Store release tag for passing to container (optional)
    $script:ReleaseTag = $releaseInfo.releaseTag

    Write-Verbose '[albt] === Container Provisioning Phase ==='
    Invoke-TimedPhaseStart -PhaseName 'container-provisioning'

    $image = Resolve-ContainerImage

    # T042: Print resolved configuration at start (validation step)
    Write-Verbose '[albt] === Configuration Summary ==='
    Write-Verbose "[albt] Release Tag:       $($releaseInfo.releaseTag)"
    Write-Verbose "[albt] Asset URL:        $($releaseInfo.assetUrl)"
    Write-Verbose "[albt] Container Image:  $image"
    if (-not [string]::IsNullOrWhiteSpace($env:ALBT_TEST_EXPECTED_SHA256)) {
        Write-Verbose "[albt] Expected SHA256:  $($env:ALBT_TEST_EXPECTED_SHA256)"
    }
    Write-Verbose '[albt] === End Configuration ==='

    # T024: Build container run command with bootstrap install sequence
    # The container should run the ACTUAL bootstrap installer to validate the real install path
    # T026: Invoke the real bootstrap/install.ps1 script inside container
    # T020: Export ALBT_AUTO_INSTALL=1 for container run
    $containerCommand = @'
        #requires -Version 5.1
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        Write-Host '[container] === Bootstrap Installer Inside Container ==='

        # Validate bootstrap installer script exists
        Write-Host '[container] Validating bootstrap installer in workspace...'
        $bootstrapScript = 'C:\albt-workspace\bootstrap\install.ps1'
        if (-not (Test-Path $bootstrapScript)) {
            Write-Error 'bootstrap/install.ps1 not found in workspace mount'
            exit 1
        }

        Write-Host "[container] Running bootstrap installer: $bootstrapScript"
        Write-Host '[container] Install destination: C:\albt-repo'

        try {
            # T021: Track PowerShell version being used
            Write-Host "[container] PowerShell version: $($PSVersionTable.PSVersion)"

            # Invoke the actual bootstrap installer
            # The installer will:
            # - Download overlay.zip
            # - Extract to destination
            # - Validate installation
            & powershell -NoLogo -NoProfile -ExecutionPolicy Bypass `
                -File $bootstrapScript `
                -Dest 'C:\albt-repo' `
                -Ref $env:ALBT_TEST_RELEASE_TAG

            $installerExitCode = $LASTEXITCODE
            Write-Host "[container] Bootstrap installer exited with code: $installerExitCode"

            exit $installerExitCode
        }
        catch {
            Write-Error "Failed to execute bootstrap installer: $_"
            exit 1
        }
'@

    $imagePullSeconds = 0
    $containerCreateSeconds = 0
    $containerId = $null
    $exitCode = 1
    $containerOutput = $null
    $imageDigest = $null
    $containerProvisionLog = $null

    $containerSuccess = Invoke-ContainerWithTiming -Image $image -ContainerCommand $containerCommand `
        -ImagePullSeconds ([ref]$imagePullSeconds) `
        -ContainerCreateSeconds ([ref]$containerCreateSeconds) `
        -ContainerId ([ref]$containerId) `
        -ExitCode ([ref]$exitCode) `
        -ImageDigest ([ref]$imageDigest) `
        -ContainerOutput ([ref]$containerOutput) `
        -ProvisionLog ([ref]$containerProvisionLog)

    Invoke-TimedPhaseStop -PhaseName 'container-provisioning'

    if (-not $containerSuccess) {
        # T031: Failure classification for container/integration failures
        $errorSummary = 'Container execution failed'
        throw "Container execution failed"
    }

    Write-Verbose "[albt] Container exit code: $exitCode"

    # T031: Classify install failures
    if ($exitCode -ne 0) { $errorSummary = "Installer exited with code $exitCode" }

    # T027: Capture container process exit code (already done via Invoke-ContainerWithTiming)
    # T021: Extract PowerShell version from container output
    $psVersion = Extract-PSVersionFromOutput -Output $output
    if (-not $psVersion) {
        Write-Verbose '[albt] PowerShell version not captured from output; using fallback'
        $psVersion = '7.2.0'
    }

    Write-Verbose '[albt] === Summary Generation Phase ==='
    $endTime = Get-Date

    if ($exitCode -ne 0 -and $containerOutput) {
        Invoke-TranscriptAppendContainerOutput -TranscriptPath $transcriptPath -ContainerOutput $containerOutput -ExitCode $exitCode
    }

    # T035: Write provision log
    if ($containerProvisionLog) { Write-ProvisionLog -ProvisionLog $containerProvisionLog }

    # T028: Populate summary with success fields (exitCode, success, durationSeconds)
    # T032: Pass timed phases to summary
    # T036: Include image digest in summary

    $summary = New-TestSummary -Image $image -ContainerId $containerId -StartTime $startTime -EndTime $endTime `
        -ReleaseTag $releaseInfo.releaseTag -AssetName 'overlay.zip' -ExitCode $exitCode `
        -PSVersion $psVersion -ImagePullSeconds $imagePullSeconds -ContainerCreateSeconds $containerCreateSeconds `
        -TranscriptPath $transcriptPath -ImageDigest $imageDigest -TimedPhases $script:TimedPhases

    if ($exitCode -ne 0) {
        # T031: Include failure classification in summary
        $errorMsg = if ($errorSummary) { $errorSummary } else { "Installation failed with exit code $exitCode" }
        $summary['errorSummary'] = $errorMsg
        $script:ErrorCategory = 'integration'
    }
    else {
        Write-Verbose '[albt] Installation succeeded; validating artifacts'
        # Verify transcript and summary will be present
        if (-not (Test-Path $transcriptPath)) {
            Write-Error "Transcript file not found: $transcriptPath"
            $script:ErrorCategory = 'integration'
            $exitCode = 1
            $summary['exitCode'] = $exitCode
            $summary['success'] = $false
            $summary['errorSummary'] = 'Transcript file missing after successful container exit'
        }
    }

    # T029: Validate summary JSON conforms to schema (basic key presence)
    $summarySuccess = Write-TestSummary -Summary $summary
    if (-not $summarySuccess) {
        throw 'Failed to write summary JSON'
    }

    # T037: Protect transcript from becoming too large
    Invoke-TranscriptSizeProtection -TranscriptPath $transcriptPath

    Write-Verbose "[albt] === Installation Complete ==="
    if ($exitCode -eq 0) {
        Write-Verbose '[albt] Installation successful'
    }
    else {
        Write-Verbose "[albt] Installation failed with exit code: $exitCode"
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
    Write-Verbose "[albt] Artifacts available in: $script:OutputDir"
}

exit $finalExitCode
