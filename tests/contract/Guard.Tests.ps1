#requires -Version 7.0

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force

Describe 'Guard enforcement for make-only entrypoints' {
    BeforeAll {
        $RepoRoot    = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
        $ScriptsRoot = Join-Path $RepoRoot 'overlay/scripts/make'
        $TempRoot    = Join-Path ([IO.Path]::GetTempPath()) ("albt-guard-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $TempRoot | Out-Null
    }

    AfterAll {
        if (Test-Path $TempRoot) { Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue }
    }

    Context 'direct invocation without ALBT_VIA_MAKE' {
        It 'exits 2 with guidance for clean.ps1' {
            $res = Invoke-ChildPwsh -ScriptPath (Join-Path $ScriptsRoot 'clean.ps1') -Arguments "`"$TempRoot`""
            $res.ExitCode | Should -Be 2
            $res.StdOut   | Should -Match 'Run via make'
        }

        It 'exits 2 with guidance for show-config.ps1' {
            $res = Invoke-ChildPwsh -ScriptPath (Join-Path $ScriptsRoot 'show-config.ps1') -Arguments "`"$TempRoot`""
            $res.ExitCode | Should -Be 2
            $res.StdOut   | Should -Match 'Run via make'
        }

        It 'exits 2 with guidance for show-analyzers.ps1' {
            $res = Invoke-ChildPwsh -ScriptPath (Join-Path $ScriptsRoot 'show-analyzers.ps1') -Arguments "`"$TempRoot`""
            $res.ExitCode | Should -Be 2
            $res.StdOut   | Should -Match 'Run via make'
        }

        It 'exits 2 with guidance for build.ps1' {
            $res = Invoke-ChildPwsh -ScriptPath (Join-Path $ScriptsRoot 'build.ps1') -Arguments "`"$TempRoot`""
            $res.ExitCode | Should -Be 2
            $res.StdOut   | Should -Match 'Run via make'
        }
    }

    Context 'invocation with ALBT_VIA_MAKE set' {
        It 'allows clean.ps1 to proceed (exit 0)' {
            $res = Invoke-ChildPwsh -ScriptPath (Join-Path $ScriptsRoot 'clean.ps1') -Arguments "`"$TempRoot`"" -Env @{ ALBT_VIA_MAKE = '1' }
            $res.ExitCode | Should -Be 0
        }
    }

    Context 'help-like args still guard' {
        It 'exits 2 when passing "/?" to clean.ps1' {
            $res = Invoke-ChildPwsh -ScriptPath (Join-Path $ScriptsRoot 'clean.ps1') -Arguments ' /?'
            $res.ExitCode | Should -Be 2
            $res.StdOut   | Should -Match 'Run via make'
        }
    }
}
