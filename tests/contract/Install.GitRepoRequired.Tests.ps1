#requires -Version 7.0

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force

Describe 'Installer guard: Git repository required' {
    BeforeAll {
        $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $InstallScript = Join-Path $RepoRoot 'bootstrap' 'install.ps1'
        $GuardBypassUrl = 'https://127.0.0.1:65535/al-build-tools'
        $WorkspaceRoot = Join-Path ([IO.Path]::GetTempPath()) ("albt-gitrepo-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $WorkspaceRoot | Out-Null

        function Invoke-TestInstall {
            param(
                [Parameter(Mandatory)] [string] $Dest
            )

            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = 'pwsh'
            $psi.WorkingDirectory = $RepoRoot
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false

            $null = $psi.ArgumentList.Add('-NoLogo')
            $null = $psi.ArgumentList.Add('-NoProfile')
            $null = $psi.ArgumentList.Add('-File')
            $null = $psi.ArgumentList.Add($InstallScript)
            $null = $psi.ArgumentList.Add('-Dest')
            $null = $psi.ArgumentList.Add($Dest)
            $null = $psi.ArgumentList.Add('-Url')
            $null = $psi.ArgumentList.Add($GuardBypassUrl)
            $null = $psi.ArgumentList.Add('-Ref')
            $null = $psi.ArgumentList.Add('main')
            $null = $psi.ArgumentList.Add('-Source')
            $null = $psi.ArgumentList.Add('overlay')

            $proc = [System.Diagnostics.Process]::Start($psi)
            $proc.WaitForExit()

            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()

            return [pscustomobject]@{
                ExitCode = $proc.ExitCode
                StdOut   = $stdout
                StdErr   = $stderr
            }
        }
    }

    AfterAll {
        if (Test-Path $WorkspaceRoot) {
            Remove-Item -LiteralPath $WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails with GitRepoRequired guard when destination lacks git metadata' {
        $dest = Join-Path $WorkspaceRoot ("dest-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dest | Out-Null

        try {
            $result = Invoke-TestInstall -Dest $dest

            $result.ExitCode | Should -Not -Be 0

            $lines = @()
            if ($result.StdOut) { $lines += $result.StdOut -split "(`r`n|`n)" }
            if ($result.StdErr) { $lines += $result.StdErr -split "(`r`n|`n)" }
            $lines = $lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            $guardLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+guard\s+' }
            $guardLine | Should -Not -BeNullOrEmpty

            $null = Assert-InstallGuardLine -Line $guardLine -ExpectedGuard 'GitRepoRequired'
        }
        finally {
            if (Test-Path $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
