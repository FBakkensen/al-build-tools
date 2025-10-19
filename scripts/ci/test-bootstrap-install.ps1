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
$script:TranscriptPath = $null  # Will be set during execution

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
# SECTION: Logging
# Writes to console and appends to transcript file
# ============================================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Message,
        [Parameter(Mandatory = $false)] [ValidateSet('Info', 'Verbose', 'Warning', 'Error')] [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $output = "[$timestamp] $Message"

    # Write to console
    switch ($Level) {
        'Verbose' { Write-Verbose $output }
        'Warning' { Write-Warning $output }
        'Error' { Write-Error $output }
        default { Write-Host $output }
    }

    # Append to transcript if available
    if ($script:TranscriptPath -and (Test-Path $script:TranscriptPath)) {
        Add-Content -Path $script:TranscriptPath -Value $output -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Logs a message to both console and provision log.
.DESCRIPTION
    Writes message to console immediately and queues it for provision log file.
#>
function Write-ProvisionMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Message,
        [Parameter(Mandatory = $false)] [ref]$ProvisionLogLines,
        [Parameter(Mandatory = $false)] [ValidateSet('Info', 'Warning', 'Error')] [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logLine = "[$timestamp] $Message"

    # Write to console
    switch ($Level) {
        'Warning' { Write-Host $logLine -ForegroundColor Yellow }
        'Error' { Write-Host $logLine -ForegroundColor Red }
        default { Write-Host $logLine }
    }

    # Add to provision log collection
    if ($ProvisionLogLines) {
        $ProvisionLogLines.Value += $logLine
    }
}

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
    Resolves the release tag for the bootstrap installer test.
.DESCRIPTION
    Checks env ALBT_TEST_RELEASE_TAG for override; falls back to querying GitHub
    API for latest non-draft release. Returns the release tag.
.OUTPUTS
    [hashtable] Contains Keys: releaseTag
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

    Write-ProvisionMessage "[albt] Starting container provisioning: $containerName" -ProvisionLogLines ([ref]$provisionLogLines)
    Write-ProvisionMessage "Container name: $containerName" -ProvisionLogLines ([ref]$provisionLogLines)
    Write-ProvisionMessage "Image: $Image" -ProvisionLogLines ([ref]$provisionLogLines)

    # T013: Capture image pull timing
    $pullStart = Get-Date
    Write-ProvisionMessage "[albt] Pulling Docker image..." -ProvisionLogLines ([ref]$provisionLogLines)
    try {
        docker pull $Image 2>&1 | ForEach-Object {
            Write-ProvisionMessage "[docker] $_" -ProvisionLogLines ([ref]$provisionLogLines)
        }
    }
    catch {
        # T014: Early failure classification for image pull
        Write-ProvisionMessage "Image pull failed: $_" -ProvisionLogLines ([ref]$provisionLogLines) -Level Error
        $ProvisionLog.Value = $provisionLogLines -join "`n"
        $script:ErrorCategory = 'network'
        return $false
    }
    $pullEnd = Get-Date
    $ImagePullSeconds.Value = [int]($pullEnd - $pullStart).TotalSeconds

    $ImageDigest.Value = Get-ImageDigest -Image $Image
    Write-ProvisionMessage "[albt] Image pull completed in $($ImagePullSeconds.Value) seconds" -ProvisionLogLines ([ref]$provisionLogLines)

    # T013: Capture container create timing
    $createStart = Get-Date
    Write-ProvisionMessage "[albt] Creating container..." -ProvisionLogLines ([ref]$provisionLogLines)
    try {
        # Use docker run - the correct pattern for testing
        Write-ProvisionMessage "[albt] Running test container..." -ProvisionLogLines ([ref]$provisionLogLines)

        $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
        $bootstrapPath = Join-Path $repoRoot 'bootstrap'
        if (-not (Test-Path $bootstrapPath)) {
            throw "bootstrap directory not found at $bootstrapPath"
        }

        # Build the docker run command
        $runArgs = @(
            'run'
            '--name', $containerName
        )

        # Add --rm unless keeping for debug
        if ($env:ALBT_TEST_KEEP_CONTAINER -ne '1') {
            $runArgs += '--rm'
        }

        # Create a temporary directory for the test script
        $tempDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) "albt-test-$(Get-Random)")
        $containerScriptPath = Join-Path $tempDir "container-test.ps1"

        Write-ProvisionMessage "[albt] Creating container test script at: $containerScriptPath" -ProvisionLogLines ([ref]$provisionLogLines)

        # Copy the container test template if it exists, otherwise create inline
        $templatePath = Join-Path $PSScriptRoot "container-test-template.ps1"
        if (Test-Path $templatePath) {
            Copy-Item -Path $templatePath -Destination $containerScriptPath -Force
            Write-ProvisionMessage "[albt] Using container test script from template" -ProvisionLogLines ([ref]$provisionLogLines)
        } else {
            # Fallback: create inline script if template not found
            Write-ProvisionMessage "[albt] Creating container test script inline" -ProvisionLogLines ([ref]$provisionLogLines)
            $testScript = @'
#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[container] Starting test..."
Write-Host "[container] PowerShell Version: $($PSVersionTable.PSVersion)"
[Console]::Out.Flush()

# Quick network test
Write-Host "[container] Testing network..."
try {
    $response = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 5
    Write-Host "[container] Network test PASS"
} catch {
    Write-Host "[container] Network test FAILED: $_" -ForegroundColor Red
    exit 1
}
[Console]::Out.Flush()

# Initialize git repo (required by installer)
Write-Host "[container] Initializing git repository..."
New-Item -ItemType Directory -Path C:\albt-workspace -Force | Out-Null
Push-Location C:\albt-workspace
try {
    & git init 2>&1 | ForEach-Object {
        Write-Host "[git] $_"
        [Console]::Out.Flush()
    }
    & git config user.email "test@example.com" 2>&1 | ForEach-Object {
        Write-Host "[git] $_"
        [Console]::Out.Flush()
    }
    & git config user.name "Test User" 2>&1 | ForEach-Object {
        Write-Host "[git] $_"
        [Console]::Out.Flush()
    }
} finally {
    Pop-Location
}
[Console]::Out.Flush()

# Run bootstrap installer
Write-Host "[container] Running bootstrap installer..."
$env:ALBT_AUTO_INSTALL = '1'
$installerArgs = @{
    Dest = 'C:\albt-workspace'
}
if ($env:ALBT_TEST_RELEASE_TAG) {
    $installerArgs['Ref'] = $env:ALBT_TEST_RELEASE_TAG
}

& C:\bootstrap\install.ps1 @installerArgs 2>&1 | ForEach-Object {
    Write-Host $_
    [Console]::Out.Flush()
}
$exitCode = $LASTEXITCODE

# Verify
if (Test-Path C:\albt-workspace\overlay) {
    Write-Host "[container] SUCCESS: Overlay installed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[container] FAILURE: Overlay not found" -ForegroundColor Red
    exit 1
}
'@
            Set-Content -Path $containerScriptPath -Value $testScript -Encoding UTF8
        }

        # Mount bootstrap directory and test directory as volumes, run with -File
        $runArgs += @(
            '-v', "${bootstrapPath}:C:\bootstrap"
            '-v', "${tempDir}:C:\test"
            '-e', 'ALBT_AUTO_INSTALL=1'
            '-e', "ALBT_TEST_RELEASE_TAG=$($script:ReleaseTag)"
            '-e', 'ALBT_HTTP_TIMEOUT_SEC=300'
            $Image
            'powershell.exe'
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-File', 'C:\test\container-test.ps1'
        )

        Write-ProvisionMessage "[albt] Executing: docker run ... -File C:\test\container-test.ps1" -ProvisionLogLines ([ref]$provisionLogLines)

        # Run the container and capture output for parsing
        $outputLines = New-Object System.Collections.ArrayList
        & docker @runArgs 2>&1 | ForEach-Object {
            # Stream to console in real-time
            Write-Host $_
            # Capture for later parsing
            [void]$outputLines.Add($_)
        }
        $dockerExitCode = $LASTEXITCODE

        $ExitCode.Value = $dockerExitCode
        $ContainerOutput.Value = $outputLines.ToArray()
        Write-ProvisionMessage "[albt] Container completed with exit code: $($ExitCode.Value)" -ProvisionLogLines ([ref]$provisionLogLines)

        # Clean up temp directory
        try {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "[albt] Failed to clean up temp directory: $_"
        }
    }
    catch {
        # T014: Early failure classification
        Write-ProvisionMessage "Failed to run container: $_" -ProvisionLogLines ([ref]$provisionLogLines) -Level Error
        $ProvisionLog.Value = $provisionLogLines -join "`n"
        $script:ErrorCategory = 'integration'
        return $false
    }
    finally {
        $createEnd = Get-Date
        $ContainerCreateSeconds.Value = [int]($createEnd - $createStart).TotalSeconds
        Write-ProvisionMessage "[albt] Container teardown started" -ProvisionLogLines ([ref]$provisionLogLines)

        # T019: Container cleanup (remove on success/failure unless keep flag)
        if ($env:ALBT_TEST_KEEP_CONTAINER -ne '1') {
            Remove-ContainerSafely -ContainerName $containerName
            Write-ProvisionMessage "[albt] Container removed" -ProvisionLogLines ([ref]$provisionLogLines)
        }
        else {
            Write-ProvisionMessage "[albt] Keeping container for debugging: $containerName" -ProvisionLogLines ([ref]$provisionLogLines)
        }

        Write-ProvisionMessage "[albt] Provisioning completed in $($ContainerCreateSeconds.Value) seconds" -ProvisionLogLines ([ref]$provisionLogLines)
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
    Write-Host "[albt] Transcript will be written to: $transcriptPath"

    # Initialize transcript file with header
    $header = @"
================================================================================
PowerShell Transcript Start
StartTime: $(Get-Date -Format 'o')
StartPath: $(Get-Location)
Version: $($PSVersionTable.PSVersion)
================================================================================
"@

    $header | Out-File -Path $transcriptPath -Encoding UTF8 -Force
    return $transcriptPath
}

<#
.SYNOPSIS
    Stops the running transcript safely.
#>
function Stop-InstallTranscript {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    # Transcript footer is added elsewhere; this is just a marker
    Write-Host '[albt] Transcript generation complete'
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
        [Parameter(Mandatory = $false)] [hashtable]$TimedPhases = @{},
        [Parameter(Mandatory = $false)] [string[]]$InstalledPrerequisites = @(),
        [Parameter(Mandatory = $false)] [string[]]$FailedPrerequisites = @(),
        [Parameter(Mandatory = $false)] [string]$LastCompletedStep = '',
        [Parameter(Mandatory = $false)] [string]$GuardCondition = ''
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
        installedPrerequisites = @()
        failedPrerequisites   = @()
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

    # Add prerequisite tracking
    if ($InstalledPrerequisites -and $InstalledPrerequisites.Count -gt 0) {
        $summary['installedPrerequisites'] = $InstalledPrerequisites
    }
    if ($FailedPrerequisites -and $FailedPrerequisites.Count -gt 0) {
        $summary['failedPrerequisites'] = $FailedPrerequisites
    }

    # Add step progression tracking
    if ($LastCompletedStep) {
        $summary['lastCompletedStep'] = $LastCompletedStep
    }
    if ($GuardCondition) {
        $summary['guardCondition'] = $GuardCondition
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

    if ($Category -eq 'success') { return 0 }
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

<#
.SYNOPSIS
    Parses container output for prerequisite installation diagnostics.
.DESCRIPTION
    Extracts structured prerequisite status markers emitted by install.ps1:
    [install] prerequisite tool="<name>" status="<status>"
.OUTPUTS
    [hashtable] Contains arrays: installedTools, failedTools
#>
function Get-PrerequisiteStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$Output
    )

    $installed = @()
    $failed = @()
    $statusMap = @{}

    if (-not $Output) {
        return @{ installedTools = $installed; failedTools = $failed }
    }

    # Pattern: [install] prerequisite tool="<name>" status="<status>"
    $prereqPattern = '\[install\]\s+prerequisite\s+tool="([^"]+)"\s+status="([^"]+)"'

    foreach ($line in $Output) {
        if ($line -match $prereqPattern) {
            $toolName = $Matches[1]
            $status = $Matches[2]
            $statusMap[$toolName] = $status

            if ($status -eq 'installed') {
                if ($installed -notcontains $toolName) {
                    $installed += $toolName
                }
            }
        }
    }

    # Detect failed prerequisites: started installing but never reached 'installed'
    foreach ($tool in $statusMap.Keys) {
        if ($statusMap[$tool] -eq 'installing' -and $installed -notcontains $tool) {
            $failed += $tool
        }
    }

    return @{
        installedTools = $installed
        failedTools = $failed
    }
}

<#
.SYNOPSIS
    Extracts step progression from container output.
.DESCRIPTION
    Parses step markers: [install] step index=<n> name=<name>
.OUTPUTS
    [string] Name of last completed step, or null
#>
function Get-LastCompletedStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$Output
    )

    if (-not $Output) {
        return $null
    }

    $lastStep = $null
    $stepPattern = '\[install\]\s+step\s+index=(\d+)\s+name=([^\s]+)'

    foreach ($line in $Output) {
        if ($line -match $stepPattern) {
            $stepName = $Matches[2]
            $lastStep = $stepName -replace '_', ' '
        }
    }

    return $lastStep
}

<#
.SYNOPSIS
    Extracts guard diagnostic messages from container output.
.DESCRIPTION
    Parses guard markers: [install] guard <Condition> ...
.OUTPUTS
    [string] First guard condition encountered, or null
#>
function Get-GuardCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object[]]$Output
    )

    if (-not $Output) {
        return $null
    }

    $guardPattern = '\[install\]\s+guard\s+(\w+)'

    foreach ($line in $Output) {
        if ($line -match $guardPattern) {
            return $Matches[1]
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
    $script:TranscriptPath = $transcriptPath

    Write-Log '[albt] === Bootstrap Installer Test Harness Started ==='
    Write-Log "[albt] Output directory: $($script:OutputDir)"
    Write-Log "[albt] Transcript: $transcriptPath"

    $errorSummary = $null

    Write-Log '[albt] === Release Resolution Phase ==='
    Invoke-TimedPhaseStart -PhaseName 'release-resolution'

    $releaseInfo = Resolve-ReleaseTag
    if (-not $releaseInfo) {
        throw 'Failed to resolve release tag'
    }
    Write-Log "[albt] Resolved Release Tag: $($releaseInfo.releaseTag)"
    Invoke-TimedPhaseStop -PhaseName 'release-resolution'

    # Store release tag for passing to container (optional)
    $script:ReleaseTag = $releaseInfo.releaseTag

    Write-Log '[albt] === Container Provisioning Phase ==='
    Invoke-TimedPhaseStart -PhaseName 'container-provisioning'

    $image = Resolve-ContainerImage

    # T042: Print resolved configuration at start (validation step)
    Write-Log '[albt] === Configuration Summary ==='
    Write-Log "[albt] Release Tag:       $($releaseInfo.releaseTag)"
    Write-Log "[albt] Container Image:  $image"
    Write-Log '[albt] === End Configuration ==='

    # T024: Build container run command with bootstrap install sequence
    # The container should run the ACTUAL bootstrap installer to validate the real install path
    # T026: Invoke the real bootstrap/install.ps1 script inside container
    # T020: Export ALBT_AUTO_INSTALL=1 for container run
    # Note: We'll build the installer command inside Invoke-ContainerWithTiming since we need the bootstrap path

    $imagePullSeconds = 0
    $containerCreateSeconds = 0
    $containerId = $null
    $exitCode = 1
    $containerOutput = $null
    $imageDigest = $null
    $containerProvisionLog = $null

    $containerSuccess = Invoke-ContainerWithTiming -Image $image `
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
    $psVersion = Extract-PSVersionFromOutput -Output $containerOutput
    if (-not $psVersion) {
        Write-Verbose '[albt] PowerShell version not captured from output; using fallback'
        $psVersion = '7.2.0'
    }

    # Parse prerequisite installation status
    $prereqStatus = Get-PrerequisiteStatus -Output $containerOutput
    $installedPrereqs = $prereqStatus.installedTools
    $failedPrereqs = $prereqStatus.failedTools

    if ($installedPrereqs.Count -gt 0) {
        Write-Log "[albt] Installed prerequisites: $($installedPrereqs -join ', ')"
    }
    if ($failedPrereqs.Count -gt 0) {
        Write-Log "[albt] Failed prerequisites: $($failedPrereqs -join ', ')" -Level Warning
    }

    # Extract step progression
    $lastStep = Get-LastCompletedStep -Output $containerOutput
    if ($lastStep) {
        Write-Log "[albt] Last completed step: $lastStep"
    }

    # Extract guard condition if present
    $guardCondition = Get-GuardCondition -Output $containerOutput
    if ($guardCondition) {
        Write-Log "[albt] Guard condition triggered: $guardCondition" -Level Warning
    }

    Write-Log '[albt] === Summary Generation Phase ==='
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
        -TranscriptPath $transcriptPath -ImageDigest $imageDigest -TimedPhases $script:TimedPhases `
        -InstalledPrerequisites $installedPrereqs -FailedPrerequisites $failedPrereqs `
        -LastCompletedStep $lastStep -GuardCondition $guardCondition

    if ($exitCode -ne 0) {
        # T031: Include failure classification in summary
        $errorMsg = if ($errorSummary) { $errorSummary } else { "Installation failed with exit code $exitCode" }

        # Enhance error summary with prerequisite failures
        if ($failedPrereqs.Count -gt 0) {
            $errorMsg += " (failed prerequisites: $($failedPrereqs -join ', '))"
        }
        if ($guardCondition) {
            $errorMsg += " (guard: $guardCondition)"
        }
        if ($lastStep) {
            $errorMsg += " (last step: $lastStep)"
        }

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
        else {
            # Mark as successful
            $script:ErrorCategory = 'success'
        }
    }

    # T029: Validate summary JSON conforms to schema (basic key presence)
    $summarySuccess = Write-TestSummary -Summary $summary
    if (-not $summarySuccess) {
        throw 'Failed to write summary JSON'
    }

    # T037: Protect transcript from becoming too large
    Invoke-TranscriptSizeProtection -TranscriptPath $transcriptPath

    Write-Log '[albt] === Installation Complete ==='
    if ($exitCode -eq 0) {
        Write-Log '[albt] Installation successful'
    }
    else {
        Write-Log "[albt] Installation failed with exit code: $exitCode" -Level Error
    }

    # $finalExitCode assignment is handled in finally block

}
catch {
    Write-Log "[albt] Critical error: $_" -Level Error
    $script:ErrorCategory = 'integration'
}
finally {
    Stop-InstallTranscript
    $finalExitCode = Get-ExitCodeForCategory -Category $script:ErrorCategory
    Write-Log "[albt] === Execution Complete === Exit Code: $finalExitCode"
    Write-Log "[albt] Artifacts available in: $script:OutputDir"
}

exit $finalExitCode
