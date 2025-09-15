#requires -Version 7.0

Describe 'Show-config normalized key ordering (T010)' {
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

        # Minimal app.json for deterministic values
        @{
            id = "00000000-0000-0000-0000-000000000000"
            name = "SampleApp"
            publisher = "FBakkensen"
            version = "1.0.0.0"
            platform = "23.0.0.0"
            application = "23.0.0.0"
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $TempRoot 'app.json')

        # Optional settings.json with empty analyzers array
        $settingsDir = Join-Path $TempRoot '.vscode'
        New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
        @{ 'al.codeAnalyzers' = @() } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $settingsDir 'settings.json')
    }

    AfterAll {
        if (Test-Path $TempRoot) { Remove-Item -Recurse -Force $TempRoot -ErrorAction SilentlyContinue }
    }

    It 'emits deterministic ordered key=value lines with required keys' {
        $script = Join-Path $OverlayMake 'show-config.ps1'

        $r1 = Invoke-ChildPwsh -ScriptPath $script -Arguments "`"$TempRoot`"" -Env @{ ALBT_VIA_MAKE = '1' }
        $r1.ExitCode | Should -Be 0
        $lines1 = ($r1.StdOut -split "`r?`n") | Where-Object { $_ -match '^[A-Za-z0-9\.]+=' }

        $r2 = Invoke-ChildPwsh -ScriptPath $script -Arguments "`"$TempRoot`"" -Env @{ ALBT_VIA_MAKE = '1' }
        $r2.ExitCode | Should -Be 0
        $lines2 = ($r2.StdOut -split "`r?`n") | Where-Object { $_ -match '^[A-Za-z0-9\.]+=' }

        # Two consecutive runs identical
        ($lines1 -join "`n") | Should -Be ($lines2 -join "`n")

        # Keys appear in a stable, expected order
        $keys = $lines1 | ForEach-Object { ($_ -split '=',2)[0] }
        $expected = @('App.Name','App.Publisher','App.Version','Platform','PowerShellVersion','Settings.Analyzers')
        $keys.Count | Should -Be $expected.Count
        for ($i=0; $i -lt $expected.Count; $i++) { $keys[$i] | Should -Be $expected[$i] }

        # App.* values reflect app.json (exact equality for stability)
        ($lines1 | Where-Object { $_ -like 'App.Name=*' } | Select-Object -First 1) | Should -Be 'App.Name=SampleApp'
        ($lines1 | Where-Object { $_ -like 'App.Publisher=*' } | Select-Object -First 1) | Should -Be 'App.Publisher=FBakkensen'
        ($lines1 | Where-Object { $_ -like 'App.Version=*' } | Select-Object -First 1) | Should -Be 'App.Version=1.0.0.0'

        # Presence (not exact value) for Platform and PowerShellVersion
        @($lines1 | Where-Object { $_ -like 'Platform=*' }).Count | Should -Be 1
        @($lines1 | Where-Object { $_ -like 'PowerShellVersion=*' }).Count | Should -Be 1
    }
}

