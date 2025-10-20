#requires -Version 7.2

<#
.SYNOPSIS
    Builds the AL Build Tools test base Docker image.

.DESCRIPTION
    Creates a Windows container base image with:
    - .NET SDK 8
    - PowerShell 7.2+
    - InvokeBuild module
    - NuGet sources configured

    This image is used by overlay script tests to avoid repeated infrastructure setup.

.PARAMETER Tag
    Docker image tag (default: albt-test-base:windows-latest)

.PARAMETER NoBuildCache
    Disable Docker build cache (force rebuild all layers)

.EXAMPLE
    pwsh -File scripts/ci/docker/build-test-base.ps1

.EXAMPLE
    pwsh -File scripts/ci/docker/build-test-base.ps1 -Tag albt-test-base:custom -NoBuildCache
#>

[CmdletBinding()]
param(
    [string]$Tag = 'albt-test-base:windows-latest',
    [switch]$NoBuildCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[build-base] === Building AL Build Tools Test Base Image ===" -ForegroundColor Cyan

# Locate repository root (PSScriptRoot is scripts/ci/docker, go up to repo root)
$repoRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent
$dockerDir = Join-Path $repoRoot 'scripts' 'ci' 'docker'
$setupScriptPath = Join-Path $repoRoot 'scripts' 'ci' 'setup-infrastructure.ps1'
$dockerfilePath = Join-Path $dockerDir 'Dockerfile.albt-test-base'

Write-Host "[build-base] Repository root: $repoRoot" -ForegroundColor Gray
Write-Host "[build-base] Dockerfile: $dockerfilePath" -ForegroundColor Gray
Write-Host "[build-base] Image tag: $Tag" -ForegroundColor Gray

# Verify prerequisites
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker not found. Please install Docker Desktop with Windows container support."
    exit 1
}

if (-not (Test-Path $dockerfilePath)) {
    Write-Error "Dockerfile not found: $dockerfilePath"
    exit 1
}

if (-not (Test-Path $setupScriptPath)) {
    Write-Error "Setup script not found: $setupScriptPath"
    exit 1
}

# Create temporary build context
$buildContext = Join-Path $env:TEMP "albt-docker-build-$(Get-Date -Format 'yyyyMMddHHmmss')"
Write-Host "[build-base] Creating build context: $buildContext" -ForegroundColor Yellow

try {
    New-Item -ItemType Directory -Path $buildContext -Force | Out-Null

    # Copy required files to build context
    Copy-Item -Path $dockerfilePath -Destination (Join-Path $buildContext 'Dockerfile') -Force
    Copy-Item -Path $setupScriptPath -Destination (Join-Path $buildContext 'setup-infrastructure.ps1') -Force

    Write-Host "[build-base] Build context prepared" -ForegroundColor Green

    # Build Docker image
    Write-Host "[build-base] Starting Docker build..." -ForegroundColor Yellow

    # Change to build context directory for docker build
    Push-Location $buildContext
    try {
        $buildArgs = @('build', '-t', $Tag)

        if ($NoBuildCache) {
            $buildArgs += '--no-cache'
            Write-Host "[build-base] Build cache disabled" -ForegroundColor Gray
        }

        $buildArgs += '.'

        Write-Host "[build-base] Command: docker $($buildArgs -join ' ')" -ForegroundColor Gray

        & docker @buildArgs
        $exitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($exitCode -ne 0) {
        Write-Error "Docker build failed with exit code $exitCode"
        exit $exitCode
    }

    Write-Host "[build-base] === Build Complete ===" -ForegroundColor Green
    Write-Host "[build-base] Image tag: $Tag" -ForegroundColor Green

    # Verify image
    Write-Host "[build-base] Verifying image..." -ForegroundColor Yellow
    $imageInfo = docker images --filter "reference=$Tag" --format "{{.Repository}}:{{.Tag}} ({{.Size}})"
    if ($imageInfo) {
        Write-Host "[build-base] Image verified: $imageInfo" -ForegroundColor Green
    } else {
        Write-Warning "Image verification failed - image not found in docker images list"
    }
}
finally {
    # Clean up build context
    if (Test-Path $buildContext) {
        Write-Host "[build-base] Cleaning up build context..." -ForegroundColor Gray
        Remove-Item -Path $buildContext -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[build-base] Done" -ForegroundColor Cyan
exit 0
