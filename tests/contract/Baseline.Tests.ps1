#requires -Version 7.0

Describe 'Baseline contracts for current behavior' {
    BeforeAll {
        function Invoke-ChildPwsh {
            param(
                [Parameter(Mandatory)] [string] $ScriptPath,
                [string] $Arguments,
                [string] $WorkingDirectory,
                [hashtable] $Env
            )
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "pwsh"
            $psi.Arguments = "-NoLogo -NoProfile -File `"$ScriptPath`" $Arguments"
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
            $res.ExitCode | Should Be 0
            $res.StdOut | Should Match 'No build artifact found'
        }
    }

    Context 'show-analyzers.ps1' {
        It 'exits 0 and prints header with (none) when no analyzers configured' {
            $script = Join-Path $OverlayMake 'show-analyzers.ps1'
            $res = Invoke-ChildPwsh -ScriptPath $script -Arguments "`"$TempRoot`"" -Env @{ ALBT_VIA_MAKE = '1' }
            $res.ExitCode | Should Be 0
            $res.StdOut | Should Match 'Enabled analyzers:'
            $res.StdOut | Should Match '\(none\)'
        }
    }

    Context 'show-config.ps1' {
        It 'exits 0 even when app.json/settings.json are missing' {
            $script = Join-Path $OverlayMake 'show-config.ps1'
            $res = Invoke-ChildPwsh -ScriptPath $script -Arguments "`"$TempRoot`"" -Env @{ ALBT_VIA_MAKE = '1' }
            $res.ExitCode | Should Be 0
            # Do not assert specific output content yet; behavior is currently lenient
        }
    }
}
