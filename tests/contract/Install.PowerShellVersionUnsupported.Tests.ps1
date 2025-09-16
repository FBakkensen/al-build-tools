#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force

Describe 'Installer guard: PowerShell version must be supported' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-psver-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails with PowerShellVersionUnsupported guard when simulated version is below requirement' {
        $destRoot = Join-Path $script:WorkspaceRoot ("repo-" + [Guid]::NewGuid().ToString('N'))
        $dest = Initialize-InstallTestRepo -Path $destRoot

        try {
            $envVars = @{ 'ALBT_TEST_FORCE_PSVERSION' = '5.1.0' }
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Environment $envVars

            $result.ExitCode | Should -Not -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $guardLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+guard\s+' }
            $guardLine | Should -Not -BeNullOrEmpty

            $guard = Assert-InstallGuardLine -Line $guardLine[0] -ExpectedGuard 'PowerShellVersionUnsupported'
            $guard.Guard | Should -Be 'PowerShellVersionUnsupported'
        }
        finally {
            if (Test-Path -LiteralPath $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
