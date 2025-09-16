#requires -Version 7.0
Set-StrictMode -Version Latest

function New-InstallTestWorkspace {
    [CmdletBinding()]
    param(
        [string] $Prefix = 'albt-install-'
    )

    $root = Join-Path ([IO.Path]::GetTempPath()) ($Prefix + [Guid]::NewGuid().ToString('N'))
    if (-not (Test-Path -LiteralPath $root)) {
        New-Item -ItemType Directory -Path $root | Out-Null
    }

    return (Resolve-Path -LiteralPath $root).Path
}

function Initialize-InstallTestRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }

    & git -C $Path init | Out-Null
    & git -C $Path config user.email 'albt-tests@example.com' | Out-Null
    & git -C $Path config user.name 'ALBT Tests' | Out-Null
    & git -C $Path config commit.gpgsign false | Out-Null

    $tracked = Join-Path $Path 'README.md'
    Set-Content -Path $tracked -Value 'bootstrap install test repository' -NoNewline
    & git -C $Path add README.md | Out-Null
    & git -C $Path commit -m 'Initial commit for install guard tests' | Out-Null

    return (Resolve-Path -LiteralPath $Path).Path
}

function Invoke-InstallScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $Dest,
        [string] $Url = 'https://127.0.0.1:65535/al-build-tools',
        [string] $Ref = 'main',
        [string] $Source = 'overlay',
        [hashtable] $Environment = @{},
        [string[]] $AdditionalArguments = @()
    )

    $scriptPath = Join-Path $RepoRoot 'bootstrap' 'install.ps1'

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'pwsh'
    $psi.WorkingDirectory = $RepoRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $null = $psi.ArgumentList.Add('-NoLogo')
    $null = $psi.ArgumentList.Add('-NoProfile')
    $null = $psi.ArgumentList.Add('-File')
    $null = $psi.ArgumentList.Add($scriptPath)
    $null = $psi.ArgumentList.Add('-Dest')
    $null = $psi.ArgumentList.Add($Dest)
    $null = $psi.ArgumentList.Add('-Url')
    $null = $psi.ArgumentList.Add($Url)
    $null = $psi.ArgumentList.Add('-Ref')
    $null = $psi.ArgumentList.Add($Ref)
    $null = $psi.ArgumentList.Add('-Source')
    $null = $psi.ArgumentList.Add($Source)

    foreach ($arg in $AdditionalArguments) {
        if ([string]::IsNullOrWhiteSpace($arg)) { continue }
        $null = $psi.ArgumentList.Add($arg)
    }

    foreach ($key in $Environment.Keys) {
        $psi.Environment[$key] = [string]$Environment[$key]
    }

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        StdOut   = $proc.StandardOutput.ReadToEnd()
        StdErr   = $proc.StandardError.ReadToEnd()
    }
}

function Get-InstallOutputLines {
    [CmdletBinding()]
    param(
        [string] $StdOut,
        [string] $StdErr
    )

    $lines = @()
    if ($StdOut) { $lines += $StdOut -split "(`r`n|`n)" }
    if ($StdErr) { $lines += $StdErr -split "(`r`n|`n)" }
    return $lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

Export-ModuleMember -Function `
    New-InstallTestWorkspace, `
    Initialize-InstallTestRepo, `
    Invoke-InstallScript, `
    Get-InstallOutputLines
