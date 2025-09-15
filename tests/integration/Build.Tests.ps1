#requires -Version 7.0

. "$PSScriptRoot/_helpers.ps1"

Describe 'Build integration (via make)' {
    BeforeAll {
        . "$PSScriptRoot/_helpers.ps1"  # ensure helpers available at run-time in Pester 5
        $Script:HasCompiler = ($null -ne (Get-ALCompilerPath '.'))
        $Script:ShimPath = Join-Path $PSScriptRoot '_alc-shim.ps1'
    }

    It 'reports a clear error when AL compiler is not found' {
        if ($HasCompiler) { Set-ItResult -Skip -Because 'Compiler present'; return }
        $fx = New-AppFixture
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath
        $res = Invoke-Make -FixturePath $fx.FixturePath -Target 'build'
        $res.ExitCode | Should -Not -Be 0
        $res.StdErrNormalized | Should -Match 'AL Compiler not found'
    }

    It 'builds successfully and reports output when AL compiler is available' {
        if (-not $HasCompiler) { Set-ItResult -Skip -Because 'No compiler available'; return }
        $fx = New-AppFixture
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath
        $pkgCache = Get-PackageCachePath $fx.AppDir
        if (-not (Test-Path $pkgCache)) { New-Item -ItemType Directory -Path $pkgCache -Force | Out-Null }
        $hasSymbols = @(Get-ChildItem -Path $pkgCache -Filter '*.app' -File -ErrorAction SilentlyContinue).Count -gt 0

        $res = Invoke-Make -FixturePath $fx.FixturePath -Target 'build'
        if ($hasSymbols) {
            $res.ExitCode | Should -Be 0
            $res.StdOutNormalized | Should -Match 'Build completed successfully:'
        } else {
            $res.ExitCode | Should -Not -Be 0
            $res.StdOutNormalized | Should -Match 'Build failed with errors above\.'
        }
    }

    It 'constructs the correct alc.exe arguments via test shim (no symbols required)' {
        $fx = New-AppFixture
        # Ensure Makefile uses the app subdir
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath
        $logPath = Join-Path $fx.FixturePath 'alc-args.log'
        # Run build with shim override, force success exit
        $res = Invoke-Make -FixturePath $fx.FixturePath -Target 'build' -Env @{
            ALBT_ALC_SHIM = $ShimPath
            ALBT_SHIM_LOG = $logPath
            ALBT_SHIM_EXIT = 0
        }
        $res.ExitCode | Should -Be 0
        # Validate arguments captured by shim
        $args = Get-Content -LiteralPath $logPath -Raw
        $args | Should -Match '/project:app'
        $args | Should -Match '/out:.*\.app'
        $args | Should -Match '/packagecachepath:.*\.alpackages'
        $args | Should -Match '/parallel\+'
        # WARN_AS_ERROR is exported as 1 by default in Makefile
        $args | Should -Match '/warnaserror\+'
        # RULESET_PATH defaults to al.ruleset.json; should be passed if present and non-empty
        $args | Should -Match '/ruleset:.*al\.ruleset\.json'
    }
}
