#requires -Version 7.0

. "$PSScriptRoot/_helpers.ps1"

Describe 'Show-config integration (via make)' {
    BeforeAll {
        . "$PSScriptRoot/_helpers.ps1"
    }

    It 'prints app and settings configuration with valid app.json' {
        $fx = New-AppFixture -Analyzers @()
        # Ensure Makefile uses the app subdir
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath

        $res = Invoke-Make -FixturePath $fx.FixturePath -Target 'show-config'
        $res.ExitCode | Should -Be 0
        $out = $res.StdOutNormalized

        # App.json header and keys (match anywhere in output)
        $out | Should -Match 'App\.json configuration:'
        $out | Should -Match "  Name: ${([regex]::Escape('SampleApp'))}"
        $out | Should -Match "  Publisher: ${([regex]::Escape('FBakkensen'))}"
        $out | Should -Match "  Version: ${([regex]::Escape('1.0.0.0'))}"

        # Settings.json block exists and lists analyzers or (none)
        # When settings.json exists (our fixture writes an empty one), script prints the header and Analyzers line
        $out | Should -Match 'Settings\.json configuration:'
        ($out -match '  Analyzers:') | Should -Be $true
    }

    It 'emits error on stderr when app.json is missing and still exits 0' {
        $fixture = New-Fixture
        $null = Install-Overlay -FixturePath $fixture
        $makefile = Join-Path $fixture 'Makefile'
        # Point APP_DIR to a non-existent app subdir
        (Get-Content -LiteralPath $makefile -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $makefile
        # Do not create app/app.json

        $res = Invoke-Make -FixturePath $fixture -Target 'show-config'
        $res.ExitCode | Should -Be 0
        $res.StdErrNormalized | Should -Match 'app\.json not found or invalid'
    }
}
