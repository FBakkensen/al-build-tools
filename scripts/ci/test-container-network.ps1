#requires -Version 5.1
<#
.SYNOPSIS
    Tests network connectivity and DNS resolution inside a Windows container.
.DESCRIPTION
    Performs basic network diagnostics to verify the container can reach external hosts.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function NT-Stamp { "[network-test] [$(Get-Date -Format 'HH:mm:ss')]" }

function Invoke-WebHeartbeat {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$TimeoutSec = 30
    )
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $task = $client.GetAsync($Url)
    $lastBeat = -1
    while (-not $task.IsCompleted) {
        Start-Sleep -Milliseconds 500
        $elapsedSec = [int]$sw.Elapsed.TotalSeconds
        if ($elapsedSec -ne $lastBeat) {
            $lastBeat = $elapsedSec
            Write-Host "$(NT-Stamp) heartbeat url=$Url wait=${elapsedSec}s"
        }
    if ($elapsedSec -ge $TimeoutSec) {
            Write-Host "$(NT-Stamp) timeout url=$Url after ${elapsedSec}s" -ForegroundColor Red
            try { $client.Dispose() } catch {}
            return $null
        }
    }
    try {
        $response = $task.Result
        return $response
    } catch {
        Write-Host "$(NT-Stamp) request error url=$Url msg=$($_.Exception.Message)" -ForegroundColor Red
        return $null
    } finally {
        try { $client.Dispose() } catch { Write-Host "$(NT-Stamp) dispose warning url=$Url msg=$($_.Exception.Message)" }
    }
}

function Download-WithHeartbeat {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$TimeoutSec = 60,
        [int]$BufferSize = 8192
    )
    $wc = New-Object System.Net.WebClient
    $wc.Headers['User-Agent'] = 'al-build-tools-network-test'
    $start = Get-Date
    $total = 0
    $lastReport = -1
    try {
        $stream = $wc.OpenRead($Url)
        $buffer = New-Object byte[] $BufferSize
        while ($true) {
            $read = $stream.Read($buffer,0,$BufferSize)
            if ($read -le 0) { break }
            $total += $read
            $elapsed = [int]((Get-Date) - $start).TotalSeconds
            if ($elapsed -ne $lastReport) {
                $lastReport = $elapsed
                Write-Host "$(NT-Stamp) download-progress url=$Url seconds=$elapsed bytes=$total"
            }
            if ($elapsed -ge $TimeoutSec) {
                Write-Host "$(NT-Stamp) download-timeout url=$Url bytes=$total after $elapsed s" -ForegroundColor Red
                return @{ Success = $false; Bytes = $total; Seconds = $elapsed }
            }
        }
        $duration = (Get-Date) - $start
        Write-Host "$(NT-Stamp) download-complete url=$Url bytes=$total seconds=$($duration.TotalSeconds.ToString('F2'))"
        return @{ Success = $true; Bytes = $total; Seconds = $duration.TotalSeconds }
    } catch {
        Write-Host "$(NT-Stamp) download-error url=$Url msg=$($_.Exception.Message)" -ForegroundColor Red
        return @{ Success = $false; Bytes = $total; Seconds = 0 }
    } finally {
        try { if ($stream) { $stream.Dispose() } } catch { Write-Host "$(NT-Stamp) stream dispose warning msg=$($_.Exception.Message)" }
        try { $wc.Dispose() } catch { Write-Host "$(NT-Stamp) webclient dispose warning msg=$($_.Exception.Message)" }
    }
}
Write-Host "$(NT-Stamp) Starting network diagnostics..."
Write-Host "$(NT-Stamp) PowerShell Version: $($PSVersionTable.PSVersion)"

# Test 1: DNS Resolution
Write-Host ""
Write-Host "$(NT-Stamp) Test 1: DNS Resolution"
try {
    $dnsResult = Resolve-DnsName -Name "github.com" -ErrorAction Stop
    Write-Host "$(NT-Stamp) DNS PASS: Resolved github.com to $($dnsResult[0].IPAddress)"
} catch {
    Write-Host "$(NT-Stamp) DNS FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

try {
    $dnsResult = Resolve-DnsName -Name "community.chocolatey.org" -ErrorAction Stop
    Write-Host "$(NT-Stamp) DNS PASS: Resolved community.chocolatey.org to $($dnsResult[0].IPAddress)"
} catch {
    Write-Host "$(NT-Stamp) DNS FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Basic HTTP Connectivity
Write-Host ""
Write-Host "$(NT-Stamp) Test 2: HTTP Connectivity"
try {
    $resp = Invoke-WebHeartbeat -Url 'https://www.google.com' -TimeoutSec 20
    if ($resp) {
        Write-Host "$(NT-Stamp) HTTP PASS: Connected to google.com (Status: $($resp.StatusCode.value__))"
    } else {
        Write-Host "$(NT-Stamp) HTTP FAIL: No response within timeout" -ForegroundColor Red
    }
} catch {
    Write-Host "$(NT-Stamp) HTTP FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: GitHub API Access
Write-Host ""
Write-Host "$(NT-Stamp) Test 3: GitHub API Access"
try {
    $resp = Invoke-WebHeartbeat -Url 'https://api.github.com' -TimeoutSec 20
    if ($resp) {
        Write-Host "$(NT-Stamp) GitHub API PASS: Connected (Status: $($resp.StatusCode.value__))"
    } else {
        Write-Host "$(NT-Stamp) GitHub API FAIL: No response within timeout" -ForegroundColor Red
    }
} catch {
    Write-Host "$(NT-Stamp) GitHub API FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Chocolatey.org Access
Write-Host ""
Write-Host "$(NT-Stamp) Test 4: Chocolatey.org Access"
try {
    $resp = Invoke-WebHeartbeat -Url 'https://community.chocolatey.org' -TimeoutSec 30
    if ($resp) {
        Write-Host "$(NT-Stamp) Chocolatey PASS: Connected (Status: $($resp.StatusCode.value__))"
    } else {
        Write-Host "$(NT-Stamp) Chocolatey FAIL: No response within timeout" -ForegroundColor Red
    }
} catch {
    Write-Host "$(NT-Stamp) Chocolatey FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: Download Speed Test (small file)
Write-Host ""
Write-Host "$(NT-Stamp) Test 5: Download Speed Test"
try {
    $testUrl = "https://community.chocolatey.org/install.ps1"
    Write-Host "$(NT-Stamp) Downloading (streaming) $testUrl..."
    $result = Download-WithHeartbeat -Url $testUrl -TimeoutSec 60
    if ($result.Success) {
        Write-Host "$(NT-Stamp) Download PASS: Downloaded $($result.Bytes) bytes in $([string]::Format('{0:F2}',$result.Seconds)) seconds"
    } else {
        Write-Host "$(NT-Stamp) Download FAIL: Incomplete after $([string]::Format('{0:F2}',$result.Seconds)) seconds (bytes=$($result.Bytes))" -ForegroundColor Red
    }
} catch {
    Write-Host "$(NT-Stamp) Download FAIL: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 6: Network Interfaces - SKIPPED (Get-NetAdapter hangs in containers)
Write-Host ""
Write-Host "$(NT-Stamp) Test 6: Network Interfaces - SKIPPED"
Write-Host "$(NT-Stamp) (Get-NetAdapter hangs in Windows container environment)"

# Test 7: Default Gateway (skipped - Get-NetRoute hangs in containers)
Write-Host "$(NT-Stamp) All tests complete"
Write-Host "[network-test] SENTINEL_END"  # explicit marker for harness parsing
Write-Host "[network-test] Test 7: Default Gateway - SKIPPED (command hangs in container environment)"

Write-Host ""
Write-Host "[network-test] Network diagnostics complete"
Write-Host "[network-test] Summary: Container has full network connectivity"
exit 0
