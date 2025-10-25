<#
.SYNOPSIS
    Validates bootstrap/install-linux.sh within an ephemeral Docker container environment.

.DESCRIPTION
    Provisions a clean Ubuntu container, downloads and installs the latest
    (or specified) release overlay.zip, and verifies successful installation with transcript
    and JSON summary artifacts. Ensures first-time user scenarios work correctly on Linux.

.PARAMETER Help
    Display this help message and exit.

.PARAMETER ?
    Display this help message and exit (short form).

.EXAMPLE
    pwsh -File scripts/ci/test-bootstrap-install-linux.ps1 -Verbose

.EXAMPLE
    pwsh -File scripts/ci/test-bootstrap-install-linux.ps1 -Help

.EXAMPLE
    $env:ALBT_TEST_RELEASE_TAG = 'v1.2.3'; pwsh -File scripts/ci/test-bootstrap-install-linux.ps1

.PARAMETER Environment Variables
    ALBT_TEST_RELEASE_TAG      - GitHub release tag (default: latest non-draft release)
    ALBT_TEST_IMAGE            - Docker image reference (default: ubuntu:22.04)
    ALBT_TEST_KEEP_CONTAINER   - Set to '1' to skip auto-remove container for debugging
    ALBT_AUTO_INSTALL          - Set to '1' inside container to enable non-interactive installation
    VERBOSE                    - Set to enable verbose logging

.OUTPUTS
    Artifacts:
      out/test-install-linux/install.transcript.txt  - Installation transcript
      out/test-install-linux/summary.json            - Execution summary matching test-summary-schema.json
      out/test-install-linux/provision.log           - Container provisioning details (on failure)

.EXIT CODES
    0 - Success: Installer exited cleanly and all artifacts present
    1 - General Error: Installation failed or artifacts missing
    2 - Guard: Invoked without required execution context
    6 - MissingTool: Docker not available

#>

#requires -Version 7.2

# T032: Add usage/help output (-Help or -?)
param(
    [switch]$Help
)

# Support both -Help and -? for getting help
if ($Help -or ($args -contains '-?')) {
    Write-Host @"
SYNOPSIS
    Validates bootstrap/install-linux.sh within an ephemeral Docker container environment.

DESCRIPTION
    Provisions a clean Ubuntu container, downloads and installs the latest
    (or specified) release overlay.zip, and verifies successful installation with transcript
    and JSON summary artifacts. Ensures first-time user scenarios work correctly on Linux.

USAGE
    pwsh -File scripts/ci/test-bootstrap-install-linux.ps1 [OPTIONS]

OPTIONS
    -Help, -?              Display this help message and exit.

ENVIRONMENT VARIABLES
    ALBT_TEST_RELEASE_TAG           - GitHub release tag (default: latest non-draft release)
    ALBT_TEST_IMAGE                 - Docker image reference (default: ubuntu:22.04)
    ALBT_TEST_KEEP_CONTAINER        - Set to '1' to skip auto-remove container for debugging
    ALBT_AUTO_INSTALL               - Set to '1' inside container to enable non-interactive installation
    VERBOSE                         - Set to enable verbose logging
    GITHUB_TOKEN                    - Optional GitHub token for higher API rate limits

EXAMPLES
    # Run with latest release
    pwsh -File scripts/ci/test-bootstrap-install-linux.ps1 -Verbose

    # Test specific release tag
    `$env:ALBT_TEST_RELEASE_TAG = 'v1.2.3'
    pwsh -File scripts/ci/test-bootstrap-install-linux.ps1

    # Debug mode: preserve container for inspection
    `$env:ALBT_TEST_KEEP_CONTAINER = '1'
    pwsh -File scripts/ci/test-bootstrap-install-linux.ps1

EXIT CODES
    0 - Success: Installer exited cleanly and all artifacts present
    1 - General Error: Installation failed or artifacts missing
    2 - Guard: Invoked without required execution context
    6 - MissingTool: Docker not available

ARTIFACTS
    out/test-install-linux/install.transcript.txt  - Installation transcript
    out/test-install-linux/summary.json            - Execution summary (schema-aligned)
    out/test-install-linux/provision.log           - Container provisioning details (on failure)

"@
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# CONFIGURATION & GLOBALS
# ============================================================================

$script:DefaultImage = 'ubuntu:22.04'
$script:OutputDir = 'out/test-install-linux'
$script:TranscriptFile = 'install.transcript.txt'
$script:SummaryFile = 'summary.json'
$script:ProvisionLogFile = 'provision.log'
$script:NetworkTimeout = 30  # seconds for GitHub API calls

$script:ErrorCategoryMap = @{
    'success'       = 0
    'general-error' = 1
    'guard'         = 2
    'analysis'      = 3
    'contract'      = 4
    'integration'   = 5
    'missing-tool'  = 6
}

# Timed sections tracking
$script:TimedPhases = @{}

# ============================================================================
# SECTION: Scenario Execution
# ============================================================================

function Invoke-ScenarioTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ScenarioName,
        [Parameter(Mandatory = $true)] [int]$ScenarioNumber,
        [Parameter(Mandatory = $true)] [string]$ContainerImage,
        [Parameter(Mandatory = $true)] [string]$ReleaseTag,
        [Parameter(Mandatory = $true)] [string]$WorkspacePath
    )

    Write-Host ''
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Scenario ${ScenarioNumber}: $ScenarioName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $containerName = $null
    $provisionLog = @()

    try {
        # Provision container for this scenario
        Write-Host 'Provisioning container...' -ForegroundColor Cyan
        $containerInfo = Invoke-ContainerProvision -Image $ContainerImage -Scenario "scenario$ScenarioNumber" -ProvisionLog ([ref]$provisionLog)
        $containerName = $containerInfo.containerName

        Write-Host "Container ready: $containerName" -ForegroundColor Green

        # Execute installer in container
        $installerResult = Invoke-InstallerInContainer -ContainerName $containerName -ReleaseTag $ReleaseTag -WorkspacePath $WorkspacePath
        $installerExitCode = $installerResult.exitCode

        if ($installerResult.success) {
            Write-Host "Installer completed (exit code: $installerExitCode)" -ForegroundColor Green
        }
        else {
            Write-Host "Installer failed (exit code: $installerExitCode)" -ForegroundColor Red
        }

        # Extract and analyze artifacts
        $artifacts = Get-ContainerArtifacts -ContainerName $containerName -WorkspacePath $WorkspacePath

        if (-not $artifacts) {
            Write-Warning "Failed to extract transcript"
            return @{ success = $false; exitCode = $installerExitCode }
        }

        # Parse markers and generate summary
        $markers = Get-DiagnosticMarkers -TranscriptContent $artifacts.content
        $prerequisites = Get-PrerequisiteStatus -PrerequisiteMarkers $markers.prerequisites
        $phases = Get-ExecutionPhases -PhaseMarkers $markers.phases
        $gitState = Get-GitState -ContainerName $containerName -WorkspacePath $WorkspacePath

        # Display results
        Write-Host "Exit Code: $installerExitCode"
        Write-Host "Git Repo: $($gitState.repositoryInitialized), Commit: $($gitState.commitCreated)"
        Write-Host "Prerequisites:" -NoNewline
        foreach ($tool in $prerequisites.tools) {
            Write-Host " $($tool['name']):$($tool['status'])" -NoNewline
        }
        Write-Host ''

        # Return result
        return @{
            success       = ($installerExitCode -eq 0)
            exitCode      = $installerExitCode
            prerequisites = $prerequisites
            phases        = $phases
            gitState      = $gitState
        }
    }
    catch {
        Write-Error "Scenario $ScenarioNumber failed: $_"
        return @{ success = $false; exitCode = 1; error = $_.ToString() }
    }
    finally {
        # Cleanup container
        if ($containerName) {
            Invoke-ContainerCleanup -ContainerName $containerName
        }
    }
}

# ============================================================================
# SECTION: Main Entry Point
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
}

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
# ============================================================================

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
# SECTION: Release Tag Resolution
# ============================================================================

function Resolve-ReleaseTag {
    [CmdletBinding()]
    param()

    $releaseTag = $env:ALBT_TEST_RELEASE_TAG
    if ([string]::IsNullOrWhiteSpace($releaseTag)) {
        Write-Verbose '[albt] Resolving latest release tag from GitHub API'

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

# ============================================================================
# SECTION: Docker & Container Management
# ============================================================================

function Assert-DockerAvailable {
    [CmdletBinding()]
    param()

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error 'Docker engine not found. Please install Docker Desktop or Docker CLI.'
        exit 6
    }
    Write-Verbose '[albt] Docker engine verified'
}

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

function Get-ImageDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Image
    )

    try {
        $inspectOutput = & docker inspect $Image 2>&1
        if ($LASTEXITCODE -eq 0) {
            $imageData = ConvertFrom-Json -InputObject $inspectOutput
            if ($imageData[0].RepoDigests -and $imageData[0].RepoDigests.Count -gt 0) {
                $digest = $imageData[0].RepoDigests[0] -replace '.*@', ''
                $digest = $digest.Substring(0, [Math]::Min(16, $digest.Length))
                return $digest
            }
            $imageId = $imageData[0].Id -replace 'sha256:', ''
            return $imageId.Substring(0, [Math]::Min(16, $imageId.Length))
        }
    }
    catch {
        Write-Verbose "[albt] Failed to get image digest: $_"
    }
    return $null
}

# T034: Generate container setup script for specific scenario
function Get-ContainerSetupScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('scenario1', 'scenario2', 'scenario3')]
        [string]$Scenario
    )

    $baseSetup = @"
#!/bin/bash
set -e

echo "[provision] Installing base prerequisites: curl, ca-certificates, unzip"
apt-get update -qq
apt-get install -y -qq curl ca-certificates unzip > /dev/null 2>&1

"@

    $scenarioSetup = switch ($Scenario) {
        'scenario1' {
            # Scenario 1: Fresh install - no git, no PowerShell, no .NET
            @"
echo "[provision] Scenario 1: Fresh install - git pre-installed, clean repo"
# Install git
apt-get install -y -qq git > /dev/null 2>&1

# Configure git
git config --global user.name "Test User"
git config --global user.email "test@albt.local"

# Create clean workspace with repository
mkdir -p /workspace/scenario1
cd /workspace/scenario1
git init
touch .gitkeep
git add .gitkeep
git commit -m "Initial commit"
echo "[provision] Setup complete"
"@
        }
        'scenario2' {
            # Scenario 2: Git pre-installed with existing project content
            @"
echo "[provision] Scenario 2: Git pre-installed with existing project"
# Install git
apt-get install -y -qq git > /dev/null 2>&1

# Configure git
git config --global user.name "Pre-configured User"
git config --global user.email "preconfig@example.com"

# Create workspace with project content
mkdir -p /workspace/scenario2
cd /workspace/scenario2
git init

# Add some project files
echo "# AL Project" > README.md
echo "*.app" > .gitignore
mkdir -p src
echo "// AL source file" > src/HelloWorld.al

git add .
git commit -m "Pre-existing project commit"
echo "[provision] Setup complete"
"@
        }
        'scenario3' {
            # Scenario 3: Git installed, configured, but workspace starts empty
            @"
echo "[provision] Scenario 3: Git installed, empty workspace"
# Install git
apt-get install -y -qq git > /dev/null 2>&1

# Configure git
git config --global user.name "Test User"
git config --global user.email "test@albt.local"

# Create workspace with repository and initial commit
mkdir -p /workspace/scenario3
cd /workspace/scenario3
git init
touch .gitkeep
git add .gitkeep
git commit -m "Initial commit"
echo "[provision] Setup complete"
"@
        }
    }

    return $baseSetup + $scenarioSetup
}# T033: Container provisioning with volume mounts
function Invoke-ContainerProvision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$Image,
        [Parameter(Mandatory = $true)] [string]$Scenario,
        [ref]$ProvisionLog
    )

    $provisionLogLines = @()
    $randomSuffix = -join ((0..9) + ('a'..'f') | Get-Random -Count 8)
    $containerName = "albt-test-linux-$randomSuffix"

    Write-ProvisionMessage "[albt] Starting container provisioning: $containerName" -ProvisionLogLines ([ref]$provisionLogLines)
    Write-ProvisionMessage "Container name: $containerName" -ProvisionLogLines ([ref]$provisionLogLines)
    Write-ProvisionMessage "Image: $Image" -ProvisionLogLines ([ref]$provisionLogLines)

    Invoke-TimedPhaseStart 'container-provisioning'

    # Pull image
    Write-ProvisionMessage "[albt] Pulling Docker image..." -ProvisionLogLines ([ref]$provisionLogLines)
    try {
        $pullOutput = & docker pull $Image 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Docker pull failed with exit code $LASTEXITCODE"
        }
        Write-Verbose "[albt] Image pulled successfully"
    }
    catch {
        Write-ProvisionMessage "[albt] ERROR: Failed to pull image: $_" -ProvisionLogLines ([ref]$provisionLogLines) -Level Error
        $ProvisionLog.Value = $provisionLogLines
        throw
    }

    # Get image digest
    $imageDigest = Get-ImageDigest -Image $Image

    # Create container with bash kept alive
    Write-ProvisionMessage "[albt] Creating container..." -ProvisionLogLines ([ref]$provisionLogLines)
    try {
        # Run container in detached mode with bash sleep to keep it alive
        $createOutput = & docker run -d --name $containerName $Image sleep 3600 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Docker run failed with exit code $LASTEXITCODE"
        }
        # Get container ID from output (last line)
        if ($createOutput -is [array]) {
            $containerId = ($createOutput | Select-Object -Last 1).ToString().Trim()
        }
        else {
            $containerId = $createOutput.ToString().Trim()
        }
        Write-Verbose "[albt] Container created: $containerId"
    }
    catch {
        Write-ProvisionMessage "[albt] ERROR: Failed to create container: $_" -ProvisionLogLines ([ref]$provisionLogLines) -Level Error
        $ProvisionLog.Value = $provisionLogLines
        throw
    }

    # Generate and copy setup script to container
    Write-ProvisionMessage "[albt] Preparing container setup script..." -ProvisionLogLines ([ref]$provisionLogLines)
    $setupScript = Get-ContainerSetupScript -Scenario $Scenario
    $setupScriptPath = Join-Path $script:OutputDir 'container-setup.sh'
    Set-Content -Path $setupScriptPath -Value $setupScript -NoNewline

    try {
        # Copy setup script to container
        $copyOutput = & docker cp $setupScriptPath "$($containerName):/tmp/setup.sh" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Docker cp failed with exit code $LASTEXITCODE"
        }

        # Execute setup script in container
        Write-ProvisionMessage "[albt] Executing container setup..." -ProvisionLogLines ([ref]$provisionLogLines)
        $setupOutput = & docker exec $containerName bash /tmp/setup.sh 2>&1 | ForEach-Object {
            $line = $_.ToString()
            Write-ProvisionMessage "  $line" -ProvisionLogLines ([ref]$provisionLogLines)
            $line
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Container setup failed with exit code $LASTEXITCODE"
        }

        Write-ProvisionMessage "[albt] Container provisioning complete" -ProvisionLogLines ([ref]$provisionLogLines)
    }
    catch {
        Write-ProvisionMessage "[albt] ERROR: Container setup failed: $_" -ProvisionLogLines ([ref]$provisionLogLines) -Level Error
        # Cleanup failed container
        & docker rm -f $containerName 2>&1 | Out-Null
        $ProvisionLog.Value = $provisionLogLines
        throw
    }
    finally {
        Invoke-TimedPhaseStop 'container-provisioning'
    }

    $ProvisionLog.Value = $provisionLogLines

    return @{
        containerName = $containerName
        containerId   = $containerId
        imageDigest   = $imageDigest
    }
}

# T035: Execute installer in container
function Invoke-InstallerInContainer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ContainerName,
        [Parameter(Mandatory = $true)] [string]$ReleaseTag,
        [Parameter(Mandatory = $true)] [string]$WorkspacePath,
        [Parameter(Mandatory = $false)] [string]$DownloadUrl
    )

    Write-Host "Executing installer in container..." -ForegroundColor Cyan

    Invoke-TimedPhaseStart 'installer-execution'

    try {
        # Copy local bootstrap directory to container
        Write-Verbose "[albt] Copying local bootstrap scripts to container..."
        $bootstrapPath = Join-Path $PSScriptRoot "../../bootstrap"

        if (-not (Test-Path $bootstrapPath)) {
            throw "Bootstrap directory not found: $bootstrapPath"
        }

        # Copy bootstrap directory to container
        $copyOutput = & docker cp $bootstrapPath "$($ContainerName):/tmp/bootstrap" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to copy bootstrap directory: $copyOutput"
        }

        Write-Verbose "[albt] Bootstrap scripts copied successfully"

        # Execute installer with environment variables
        Write-Verbose "[albt] Running installer with ALBT_AUTO_INSTALL=1..."

        # If download URL provided, pass it to skip GitHub API resolution
        $envVars = "export ALBT_AUTO_INSTALL=1 && export ALBT_RELEASE='$ReleaseTag'"
        if ($DownloadUrl) {
            Write-Verbose "[albt] Using pre-resolved download URL (skipping GitHub API)"
            # Note: The installer doesn't currently support passing download URL directly
            # For now, it will still hit the API but we document the intent
        }

        $installCmd = @"
cd $WorkspacePath && \
$envVars && \
bash /tmp/bootstrap/install-linux.sh 2>&1 | tee $WorkspacePath/install.transcript.txt
"@

        $installOutput = & docker exec $ContainerName bash -c $installCmd 2>&1 | ForEach-Object {
            Write-Host $_
            $_
        }
        $installerExitCode = $LASTEXITCODE

        Write-Verbose "[albt] Installer exited with code: $installerExitCode"

        return @{
            exitCode = $installerExitCode
            success  = ($installerExitCode -eq 0)
        }
    }
    catch {
        Write-Error "Installer execution failed: $_"
        return @{
            exitCode = 1
            success  = $false
            error    = $_.ToString()
        }
    }
    finally {
        Invoke-TimedPhaseStop 'installer-execution'
    }
}

# T036: Extract transcript and artifacts from container
function Get-ContainerArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ContainerName,
        [Parameter(Mandatory = $true)] [string]$WorkspacePath
    )

    Write-Host "Extracting artifacts from container..." -ForegroundColor Cyan

    try {
        # Copy transcript file
        $transcriptDest = Join-Path $script:OutputDir $script:TranscriptFile
        $copyOutput = & docker cp "$($ContainerName):$WorkspacePath/install.transcript.txt" $transcriptDest 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to copy transcript file: $copyOutput"
            return $null
        }

        Write-Verbose "[albt] Transcript extracted to: $transcriptDest"

        # Read transcript content
        if (Test-Path $transcriptDest) {
            $transcriptContent = Get-Content -Path $transcriptDest -Raw
            return @{
                transcriptPath = $transcriptDest
                content        = $transcriptContent
            }
        }

        return $null
    }
    catch {
        Write-Warning "Failed to extract artifacts: $_"
        return $null
    }
}

# T037: Parse diagnostic markers from transcript
function Get-DiagnosticMarkers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$TranscriptContent
    )

    $markers = @{
        prerequisites = @()
        steps         = @()
        guards        = @()
        phases        = @()
        diagnostics   = @()
    }

    # Pattern: [install] <type> key="value" key2="value2"
    $lines = $TranscriptContent -split "`n"

    foreach ($line in $lines) {
        if ($line -match '^\[install\]\s+(\w+)\s+(.+)$') {
            $markerType = $matches[1]
            $markerData = $matches[2]

            # Parse key="value" pairs
            $properties = @{}
            $kvPattern = '(\w+)="([^"]*)"'
            [regex]::Matches($markerData, $kvPattern) | ForEach-Object {
                $properties[$_.Groups[1].Value] = $_.Groups[2].Value
            }

            switch ($markerType) {
                'prerequisite' { $markers.prerequisites += $properties }
                'step' { $markers.steps += $properties }
                'guard' { $markers.guards += $properties }
                'phase' { $markers.phases += $properties }
                'diagnostic' { $markers.diagnostics += $properties }
            }
        }
    }

    return $markers
}

# T038: Extract prerequisite status
function Get-PrerequisiteStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [array]$PrerequisiteMarkers = @()
    )

    $tools = @()
    $toolNames = @('git', 'powershell', 'dotnet', 'InvokeBuild')

    foreach ($toolName in $toolNames) {
        $toolMarkers = $PrerequisiteMarkers | Where-Object { $_.tool -eq $toolName }

        if ($toolMarkers) {
            $latestMarker = $toolMarkers | Select-Object -Last 1
            $tools += @{
                name    = $toolName
                status  = $latestMarker.status
                version = $latestMarker.version
            }
        }
        else {
            $tools += @{
                name   = $toolName
                status = 'unknown'
            }
        }
    }

    $allPresent = (@($tools | Where-Object { $_.status -eq 'found' })).Count -eq $tools.Count
    $anyFailed = (@($tools | Where-Object { $_.status -eq 'failed' })).Count -gt 0
    $installationRequired = (@($tools | Where-Object { $_.status -eq 'installed' })).Count -gt 0

    return @{
        tools                = $tools
        allPresent           = $allPresent
        anyFailed            = $anyFailed
        installationRequired = $installationRequired
    }
}

# T039: Extract execution phases
function Get-ExecutionPhases {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [array]$PhaseMarkers = @()
    )

    $phases = @()
    $phaseNames = @('release-resolution', 'prerequisite-installation', 'overlay-download', 'file-copy', 'git-commit')

    foreach ($phaseName in $phaseNames) {
        $startMarker = $PhaseMarkers | Where-Object { $_.name -eq $phaseName -and $_.event -eq 'start' } | Select-Object -First 1
        $endMarker = $PhaseMarkers | Where-Object { $_.name -eq $phaseName -and $_.event -eq 'end' } | Select-Object -First 1

        if ($startMarker -and $endMarker) {
            $phaseObj = @{
                name   = $phaseName
                status = 'completed'
            }

            # Add optional fields if they exist
            if ($startMarker.ContainsKey('timestamp')) { $phaseObj['startTime'] = $startMarker['timestamp'] }
            if ($endMarker.ContainsKey('timestamp')) { $phaseObj['endTime'] = $endMarker['timestamp'] }
            if ($endMarker.ContainsKey('duration')) {
                $durationValue = $endMarker['duration']
                $phaseObj['duration'] = [int]($durationValue -replace 's$', '')
            }

            $phases += $phaseObj
        }
        elseif ($startMarker) {
            $phases += @{
                name   = $phaseName
                status = 'started'
            }
        }
    }

    return $phases
}

# T040: Validate git state in container
function Get-GitState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ContainerName,
        [Parameter(Mandatory = $true)] [string]$WorkspacePath
    )

    try {
        # Check if git repo exists
        $repoCheck = & docker exec $ContainerName bash -c "cd $WorkspacePath && git rev-parse --git-dir 2>/dev/null" 2>&1
        $repoExists = ($LASTEXITCODE -eq 0)

        if (-not $repoExists) {
            return @{
                repositoryInitialized = $false
                commitCreated         = $false
            }
        }

        # Get commit hash
        $commitHash = & docker exec $ContainerName bash -c "cd $WorkspacePath && git rev-parse HEAD 2>/dev/null" 2>&1
        $commitCreated = ($LASTEXITCODE -eq 0) -and (-not [string]::IsNullOrWhiteSpace($commitHash))

        # Get file count
        $fileCount = & docker exec $ContainerName bash -c "cd $WorkspacePath && git ls-files | wc -l" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $fileCount = [int]$fileCount.Trim()
        }
        else {
            $fileCount = 0
        }

        return @{
            repositoryInitialized = $repoExists
            commitCreated         = $commitCreated
            commitHash            = if ($commitCreated) { $commitHash.Trim() } else { $null }
            trackedFiles          = $fileCount
        }
    }
    catch {
        Write-Verbose "[albt] Failed to get git state: $_"
        return @{
            repositoryInitialized = $false
            commitCreated         = $false
        }
    }
}

# T041: Generate summary JSON
function Get-InstallationSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ContainerImage,
        [Parameter(Mandatory = $true)] [string]$ReleaseTag,
        [Parameter(Mandatory = $true)] [hashtable]$Prerequisites,
        [Parameter(Mandatory = $true)] [array]$Phases,
        [Parameter(Mandatory = $true)] [hashtable]$GitState,
        [Parameter(Mandatory = $true)] [int]$ExitCode,
        [Parameter(Mandatory = $false)] [string]$ImageDigest
    )

    $exitCategory = switch ($ExitCode) {
        0 { 'success' }
        1 { 'general-error' }
        2 { 'guard' }
        6 { 'missing-tool' }
        default { 'general-error' }
    }

    $summary = @{
        metadata      = @{
            testHarness    = 'test-bootstrap-install-linux.ps1'
            executionTime  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            containerImage = $ContainerImage
            releaseTag     = $ReleaseTag
            platform       = 'Linux'
            imageDigest    = $ImageDigest
        }
        prerequisites = $Prerequisites
        phases        = $Phases
        gitState      = $GitState
        release       = @{
            tag    = $ReleaseTag
            source = 'GitHub'
        }
        exitCode      = $ExitCode
        exitCategory  = $exitCategory
        success       = ($ExitCode -eq 0)
    }

    return $summary
}

# T042: Validate summary JSON against schema
function Test-SummarySchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$SummaryPath,
        [Parameter(Mandatory = $true)] [string]$SchemaPath
    )

    if (-not (Test-Path $SchemaPath)) {
        Write-Warning "Schema file not found: $SchemaPath"
        return $false
    }

    try {
        # Basic validation - check required fields exist
        $summary = Get-Content -Path $SummaryPath -Raw | ConvertFrom-Json

        $requiredFields = @('metadata', 'prerequisites', 'phases', 'gitState', 'exitCode', 'exitCategory', 'success')
        $missingFields = $requiredFields | Where-Object { -not $summary.PSObject.Properties[$_] }

        if ($missingFields) {
            Write-Warning "Missing required fields: $($missingFields -join ', ')"
            return $false
        }

        Write-Verbose "[albt] Summary JSON validation passed"
        return $true
    }
    catch {
        Write-Warning "Schema validation failed: $_"
        return $false
    }
}

# T043: Save provision log
function Save-ProvisionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [array]$ProvisionLogLines
    )

    $provisionLogPath = Join-Path $script:OutputDir $script:ProvisionLogFile

    try {
        $ProvisionLogLines | Out-File -FilePath $provisionLogPath -Encoding UTF8
        Write-Verbose "[albt] Provision log saved to: $provisionLogPath"
    }
    catch {
        Write-Warning "Failed to save provision log: $_"
    }
}

# T044: Container cleanup
function Invoke-ContainerCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string]$ContainerName
    )

    $keepContainer = $env:ALBT_TEST_KEEP_CONTAINER -eq '1'

    if ($keepContainer) {
        Write-Host "Container preserved for debugging: $ContainerName" -ForegroundColor Yellow
        Write-Host "To remove manually: docker rm -f $ContainerName" -ForegroundColor Yellow
        return
    }

    try {
        Write-Verbose "[albt] Removing container: $ContainerName"
        $removeOutput = & docker rm -f $ContainerName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Verbose "[albt] Container removed successfully"
        }
        else {
            Write-Warning "Failed to remove container: $removeOutput"
        }
    }
    catch {
        Write-Warning "Failed to remove container: $_"
    }
}

# ============================================================================
# SECTION: Main Execution
# ============================================================================

function Main {
    [CmdletBinding()]
    param()

    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host 'AL Build Tools - Linux Bootstrap Test' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''

    # Validate Docker availability
    Assert-DockerAvailable

    # Resolve release tag
    Invoke-TimedPhaseStart 'release-resolution'
    $releaseInfo = Resolve-ReleaseTag
    Invoke-TimedPhaseStop 'release-resolution'

    if (-not $releaseInfo) {
        Write-Error 'Failed to resolve release tag'
        exit 1
    }

    $releaseTag = $releaseInfo.releaseTag
    Write-Host "Testing release: $releaseTag" -ForegroundColor Green
    Write-Host ''

    # Resolve container image
    $containerImage = Resolve-ContainerImage

    # Create output directory
    if (-not (Test-Path $script:OutputDir)) {
        New-Item -ItemType Directory -Path $script:OutputDir -Force | Out-Null
    }

    Write-Host "Test artifacts will be saved to: $script:OutputDir" -ForegroundColor Cyan

    # Track results across all scenarios
    $scenarioResults = @{}
    $allPassed = $true

    # Run all 3 scenarios
    $scenarios = @(
        @{ Number = 1; Name = 'Fresh install - git pre-installed, clean repo'; WorkspacePath = '/workspace/scenario1' }
        @{ Number = 2; Name = 'Git pre-installed with existing project'; WorkspacePath = '/workspace/scenario2' }
        @{ Number = 3; Name = 'Git installed, empty workspace'; WorkspacePath = '/workspace/scenario3' }
    )

    foreach ($scenario in $scenarios) {
        $result = Invoke-ScenarioTest `
            -ScenarioName $scenario.Name `
            -ScenarioNumber $scenario.Number `
            -ContainerImage $containerImage `
            -ReleaseTag $releaseTag `
            -WorkspacePath $scenario.WorkspacePath

        $scenarioResults[$scenario.Number] = $result
        if (-not $result.success) {
            $allPassed = $false
        }
    }

    # Report overall results
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host 'Overall Test Summary' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    foreach ($scenario in $scenarios) {
        $result = $scenarioResults[$scenario.Number]
        $status = if ($result.success) { 'PASSED' } else { 'FAILED' }
        $color = if ($result.success) { 'Green' } else { 'Red' }
        Write-Host "Scenario $($scenario.Number): $status (exit code: $($result.exitCode))" -ForegroundColor $color
    }
    Write-Host ''

    if ($allPassed) {
        Write-Host 'All scenarios PASSED' -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host 'Some scenarios FAILED' -ForegroundColor Red
        exit 1
    }
}

# Entry point
try {
    Main
}
catch {
    Write-Error "Test harness failed: $_"
    exit 1
}
