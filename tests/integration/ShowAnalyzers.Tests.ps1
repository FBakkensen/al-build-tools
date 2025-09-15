#requires -Version 7.0

. "$PSScriptRoot/_helpers.ps1"

Describe 'Show-analyzers integration (via make)' {
    It 'prints header and (none) when no analyzers are configured' {
        $fx = New-AppFixture
        # Ensure Makefile uses the app subdir
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath

        $res = Invoke-Make -FixturePath $fx.FixturePath -Target 'show-analyzers'
        $res.ExitCode | Should Be 0
        $out = $res.StdOutNormalized

        $out | Should Match 'Enabled analyzers:'
        $out | Should Match '(?m)^  \(none\)$'
    }

    It 'resolves workspace-local analyzer DLL via tokens and wildcard' {
        $fx = New-AppFixture -Analyzers @('${appDir}/analyzers/*.dll')
        # Ensure Makefile uses the app subdir
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath

        # Create a fake analyzer DLL inside app/analyzers
        $anDir = Join-Path $fx.AppDir 'analyzers'
        if (-not (Test-Path $anDir)) { New-Item -ItemType Directory -Path $anDir -Force | Out-Null }
        $fakeDll = Join-Path $anDir 'MyAnalyzer.dll'
        Set-Content -LiteralPath $fakeDll -Value '' -NoNewline
        (Test-Path -LiteralPath $fakeDll) | Should Be $true

        $res = Invoke-Make -FixturePath $fx.FixturePath -Target 'show-analyzers'
        $res.ExitCode | Should Be 0
        $out = $res.StdOutNormalized

        $out | Should Match 'Analyzer DLL paths:'
        $escaped = [regex]::Escape($fakeDll)
        $out | Should Match $escaped
    }
}
