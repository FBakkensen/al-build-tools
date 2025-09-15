#requires -Version 7.0

Describe 'Verbosity behavior via env flag and -Verbose' {
    BeforeAll {
        function Invoke-ChildPwsh {
            param(
                [Parameter(Mandatory)] [string] $ScriptPath,
                [string] $Arguments,
                [string] $WorkingDirectory,
                [hashtable] $Env,
                [switch] $EngineVerbose
            )
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = 'pwsh'
            if ($EngineVerbose) {
                # Use -Command to force verbose preference on in child scope
                $cmd = "& { `$VerbosePreference = 'Continue'; & `"$ScriptPath`" $Arguments }"
                $psi.Arguments = "-NoLogo -NoProfile -Command $cmd"
            } else {
                $psi.Arguments = "-NoLogo -NoProfile -File `"$ScriptPath`" $Arguments"
            }
            if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            if ($Env) {
                foreach ($k in $Env.Keys) { $psi.Environment[$k] = [string]$Env[$k] }
            }
            $proc = [System.Diagnostics.Process]::Start($psi)
            $proc.WaitForExit()
            $exit = $proc.ExitCode
            $outStr = $proc.StandardOutput.ReadToEnd()
            $errStr = $proc.StandardError.ReadToEnd()
            return [pscustomobject]@{ ExitCode = $exit; StdOut = $outStr; StdErr = $errStr }
        }

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
