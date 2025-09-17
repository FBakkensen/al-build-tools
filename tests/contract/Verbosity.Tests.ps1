#requires -Version 7.0

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force

Describe 'Verbosity behavior via env flag and -Verbose' {
    BeforeAll {
        $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
        $OverlayMake = Join-Path $RepoRoot 'overlay/scripts/make'
        $Tmp = Join-Path ([IO.Path]::GetTempPath()) ("albt-verbosity-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $Tmp | Out-Null
    }

    AfterAll {
        if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
    }

    It 'honors VERBOSE=1 without -Verbose' {
        $script = Join-Path $OverlayMake 'show-config.ps1'
        $res = Invoke-ChildPwsh -ScriptPath $script -Arguments "`"$Tmp`"" -Env @{ ALBT_VIA_MAKE = '1'; VERBOSE = '1' }
        # Verbose messages may land on StdErr depending on host; check both
        ($res.StdOut + $res.StdErr) | Should -Match 'VERBOSE: .*verbose.*enabled'
        $res.ExitCode | Should -Be 0
    }

    It 'emits verbose output when -Verbose is used' {
        $script = Join-Path $OverlayMake 'show-config.ps1'
        $res = Invoke-ChildPwsh -ScriptPath $script -Arguments "`"$Tmp`"" -Env @{ ALBT_VIA_MAKE = '1' } -EngineVerbose
        ($res.StdOut + $res.StdErr) | Should -Match 'VERBOSE: .*verbose.*enabled'
        $res.ExitCode | Should -Be 0
    }
}
