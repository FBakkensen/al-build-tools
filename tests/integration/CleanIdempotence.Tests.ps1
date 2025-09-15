#requires -Version 7.0

. "$PSScriptRoot/_helpers.ps1"

Describe 'Clean idempotence (via make)' {
    BeforeAll {
        . "$PSScriptRoot/_helpers.ps1"
    }

    It 'removes existing artifact on first run and reports none on second run' {
        $fx = New-AppFixture
        # Ensure Makefile uses the app subdir
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath

        # Pre-seed a fake .app artifact at the expected output path
        $artifactPath = Get-ExpectedOutputPath -AppDir $fx.AppDir
        Set-Content -LiteralPath $artifactPath -Value '' -NoNewline
        (Test-Path -LiteralPath $artifactPath) | Should -Be $true

        # First clean: should remove the artifact and exit 0
        $res1 = Invoke-Make -FixturePath $fx.FixturePath -Target 'clean'
        $res1.ExitCode | Should -Be 0
        (Test-Path -LiteralPath $artifactPath) | Should -Be $false
        # Optional: message about removal
        $res1.StdOutNormalized | Should -Match 'Removed build artifact'

        # Second clean: nothing to remove; still exit 0 with clear message
        $res2 = Invoke-Make -FixturePath $fx.FixturePath -Target 'clean'
        $res2.ExitCode | Should -Be 0
        $res2.StdOutNormalized | Should -Match 'No build artifact found'
    }
}
