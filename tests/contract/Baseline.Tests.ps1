#requires -Version 7.0

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force

Describe 'Baseline contracts for current behavior' {
    BeforeAll {
        $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
        $OverlayMake = Join-Path $RepoRoot 'overlay/scripts/make'

        $TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("albt-tests-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $TempRoot | Out-Null
    }

    AfterAll {
        if (Test-Path $TempRoot) { Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue }
    }

    Context 'clean.ps1' {
        It 'exits 0 and reports no artifact when app.json is absent' {
            $script = Join-Path $OverlayMake 'clean.ps1'
            $res = Invoke-ChildPwsh -ScriptPath $script -Arguments "`"$TempRoot`"" -Env @{ ALBT_VIA_MAKE = '1' }
            $res.ExitCode | Should -Be 0
            $res.StdOut | Should -Match 'No build artifact found'
        }
    }

    Context 'show-analyzers.ps1' {
        It 'exits 0 and prints header with (none) when no analyzers configured' {
            $script = Join-Path $OverlayMake 'show-analyzers.ps1'
            $res = Invoke-ChildPwsh -ScriptPath $script -Arguments "`"$TempRoot`"" -Env @{ ALBT_VIA_MAKE = '1' }
            $res.ExitCode | Should -Be 0
            $res.StdOut | Should -Match 'Enabled analyzers:'
            $res.StdOut | Should -Match '\(none\)'
        }
    }

    Context 'show-config.ps1' {
        It 'exits 0 even when app.json/settings.json are missing' {
            $script = Join-Path $OverlayMake 'show-config.ps1'
            $res = Invoke-ChildPwsh -ScriptPath $script -Arguments "`"$TempRoot`"" -Env @{ ALBT_VIA_MAKE = '1' }
            $res.ExitCode | Should -Be 0
            # Do not assert specific output content yet; behavior is currently lenient
        }
    }
}

