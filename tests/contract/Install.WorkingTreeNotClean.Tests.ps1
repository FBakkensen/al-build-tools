#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force

Describe 'Installer guard: Working tree must be clean' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-dirty-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails with WorkingTreeNotClean guard when repo has uncommitted changes' {
        $destRoot = Join-Path $script:WorkspaceRoot ("repo-" + [Guid]::NewGuid().ToString('N'))
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $trackedFile = Join-Path $dest 'README.md'
        Set-Content -Path $trackedFile -Value 'updated baseline for dirty state'

        $untrackedFile = Join-Path $dest 'scratch.tmp'
        Set-Content -Path $untrackedFile -Value 'untracked change'

        try {
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest

            $result.ExitCode | Should -Be 10

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
