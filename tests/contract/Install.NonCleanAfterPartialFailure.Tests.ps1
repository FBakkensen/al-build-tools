#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force

Describe 'Installer guard: refuse rerun when working tree dirty after partial failure' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-partial-'
        $script:OverlaySampleFile = Join-Path $script:RepoRoot 'overlay' 'Makefile'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails with WorkingTreeNotClean guard when overlay residue exists from prior run' {
        $destRoot = Join-Path $script:WorkspaceRoot ("repo-" + [Guid]::NewGuid().ToString('N'))
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $overlayCopyTarget = Join-Path $dest 'Makefile'
        Copy-Item -LiteralPath $script:OverlaySampleFile -Destination $overlayCopyTarget -Force

        try {
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest

            $result.ExitCode | Should -Not -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $guardLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+guard\s+' }
            $guardLine | Should -Not -BeNullOrEmpty

            $guard = Assert-InstallGuardLine -Line $guardLine -ExpectedGuard 'WorkingTreeNotClean'
            $guard.Guard | Should -Be 'WorkingTreeNotClean'
        }
        finally {
            if (Test-Path -LiteralPath $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
