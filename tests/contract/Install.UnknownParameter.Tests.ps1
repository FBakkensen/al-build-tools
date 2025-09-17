#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force

Describe 'Installer guard: unknown parameters must be rejected with guidance' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-arg-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails with UnknownParameter guard when unsupported argument is provided' {
        $destRoot = Join-Path $script:WorkspaceRoot ("repo-" + [Guid]::NewGuid().ToString('N'))
        $dest = Initialize-InstallTestRepo -Path $destRoot

        try {
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -AdditionalArguments @('-Nope123')

            $result.ExitCode | Should -Be 10

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $guardLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+guard\s+' }
            $guardLine | Should -Not -BeNullOrEmpty

            $guard = Assert-InstallGuardLine -Line $guardLine -ExpectedGuard 'UnknownParameter'
            $guard.Guard | Should -Be 'UnknownParameter'
            $guard.Pairs.Contains('argument') | Should -BeTrue
            $guard.Pairs['argument'] | Should -Be 'Nope123'
        }
        finally {
            if (Test-Path -LiteralPath $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
