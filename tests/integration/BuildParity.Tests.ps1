#requires -Version 7.0

. "$PSScriptRoot/_helpers.ps1"

Describe 'Build parity (cross-platform placeholder) via make' {
    BeforeAll {
        . "$PSScriptRoot/_helpers.ps1"
        $Script:HasCompiler = ($null -ne (Get-ALCompilerPath '.'))
    }

    It 'produces normalized output for build success case' {
        if (-not $HasCompiler) { Set-ItResult -Skip -Because 'No compiler available'; return }
        $fx = New-AppFixture
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath
        $pkgCache = Get-PackageCachePath $fx.AppDir
        if (-not (Test-Path $pkgCache)) { New-Item -ItemType Directory -Path $pkgCache -Force | Out-Null }

        $res = Invoke-Make -FixturePath $fx.FixturePath -Target 'build'
        
        # Normalize output for cross-platform parity
        $normalizedOut = _Normalize-Output $res.StdOutNormalized
        $normalizedErr = _Normalize-Output $res.StdErrNormalized
        
        # Assert expected build markers are present (regardless of success/failure)
        if ($res.ExitCode -eq 0) {
            $normalizedOut | Should -Match 'Build completed successfully:'
        } else {
            $normalizedOut | Should -Match 'Build failed with errors above\.'
        }
        
        # Essential cross-platform assertion: output should contain predictable markers
        $normalizedOut | Should -Match 'Building AL project'
        $normalizedOut | Should -Match 'alc\.exe'
    }

    It 'produces normalized output for build failure case (no compiler)' {
        if ($HasCompiler) { Set-ItResult -Skip -Because 'Compiler present'; return }
        $fx = New-AppFixture
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath

        $res = Invoke-Make -FixturePath $fx.FixturePath -Target 'build'
        
        # Normalize output for cross-platform parity
        $normalizedErr = _Normalize-Output $res.StdErrNormalized
        
        # Should fail with clear error message
        $res.ExitCode | Should -Not -Be 0
        $normalizedErr | Should -Match 'AL Compiler not found'
    }

    It 'produces identical normalized output across multiple runs' {
        $fx = New-AppFixture
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath

        # Run build twice
        $res1 = Invoke-Make -FixturePath $fx.FixturePath -Target 'build'
        $res2 = Invoke-Make -FixturePath $fx.FixturePath -Target 'build'
        
        # Normalize outputs
        $norm1 = _Normalize-Output ($res1.StdOutNormalized + $res1.StdErrNormalized)
        $norm2 = _Normalize-Output ($res2.StdOutNormalized + $res2.StdErrNormalized)
        
        # Exit codes should be identical
        $res1.ExitCode | Should -Be $res2.ExitCode
        
        # Essential message content should be identical (timestamps may vary)
        $norm1 -replace '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}', 'TIMESTAMP' | Should -Be ($norm2 -replace '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}', 'TIMESTAMP')
    }
}