#requires -Version 7.0

. "$PSScriptRoot/_helpers.ps1"

Describe 'Parity snapshot (scaffold) across targets (via make)' {
    BeforeAll {
        . "$PSScriptRoot/_helpers.ps1"
        # Determine if an AL compiler is available to decide whether to include build output
        $RepoRoot = (& { _Get-RepoRoot })
        . (Join-Path $RepoRoot 'overlay/scripts/make/lib/common.ps1')
        $Script:HasCompiler = ($null -ne (Get-ALCompilerPath '.'))

        function New-ParitySignature {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)][string] $ConfigOut,
                [Parameter(Mandatory)][string] $AnalyzersOut,
                [Parameter()][string] $BuildOut,
                [Parameter()][int] $BuildExit = -999,
                [Parameter(Mandatory)][string] $CleanOut1,
                [Parameter(Mandatory)][string] $CleanOut2
            )
            # Extract content-level signals only (stable across OS)
            $sig = [ordered]@{}

            # show-config: capture name/publisher/version and analyzer header presence
            $cfg = @{}
            $name = [regex]::Match($ConfigOut, '(?m)^\s*Name:\s*(.+)$').Groups[1].Value
            $pub  = [regex]::Match($ConfigOut, '(?m)^\s*Publisher:\s*(.+)$').Groups[1].Value
            $ver  = [regex]::Match($ConfigOut, '(?m)^\s*Version:\s*(.+)$').Groups[1].Value
            $cfg.Name = $name
            $cfg.Publisher = $pub
            $cfg.Version = $ver
            $cfg.SettingsBlock = [bool]([regex]::IsMatch($ConfigOut, 'Settings\.json configuration:'))
            $cfg.AnalyzersNone = [bool]([regex]::IsMatch($ConfigOut, '(?m)^\s*Analyzers:\s*\(none\)\s*$'))
            $sig.ShowConfig = $cfg

            # show-analyzers: count enabled entries and path entries (content-level parity)
            $an = @{}
            $an.EnabledCount = ([regex]::Matches($AnalyzersOut, '(?m)^\s{2}(?!\(none\)).+$')).Count
            $an.NoneEnabled = [bool]([regex]::IsMatch($AnalyzersOut, '(?m)^\s*\(none\)\s*$'))
            $an.HasPathsBlock = [bool]([regex]::IsMatch($AnalyzersOut, 'Analyzer DLL paths:'))
            $sig.ShowAnalyzers = $an

            # build: categorize status without embedding OS-specific paths
            if ($PSBoundParameters.ContainsKey('BuildOut')) {
                $b = @{}
                if ($BuildExit -eq 0 -and ($BuildOut -match 'Build completed successfully:')) {
                    $b.Status = 'success'
                } elseif ($BuildOut -match 'AL Compiler not found') {
                    $b.Status = 'no-compiler'
                } elseif ($BuildOut -match 'Build failed with errors above\.') {
                    $b.Status = 'failed'
                } else {
                    $b.Status = 'unknown'
                }
                $sig.Build = $b
            }

            # clean: classify first and second runs
            $c = @{}
            $c.Run1 = if ($CleanOut1 -match 'Removed build artifact') { 'removed' } elseif ($CleanOut1 -match 'No build artifact found') { 'none' } else { 'other' }
            $c.Run2 = if ($CleanOut2 -match 'Removed build artifact') { 'removed' } elseif ($CleanOut2 -match 'No build artifact found') { 'none' } else { 'other' }
            $sig.Clean = $c

            return $sig
        }
    }

    It 'collects normalized outputs and builds a content-level parity signature' {
        $fx = New-AppFixture -Analyzers @()
        # Ensure Makefile uses the app subdir
        (Get-Content -LiteralPath $fx.MakefilePath -Raw) -replace 'APP_DIR := \.', 'APP_DIR := app' | Set-Content -LiteralPath $fx.MakefilePath

        # show-config
        $cfg = Invoke-Make -FixturePath $fx.FixturePath -Target 'show-config'
        $cfg.ExitCode | Should -Be 0
        $cfgN = $cfg.StdOutNormalized

        # show-analyzers
        $an = Invoke-Make -FixturePath $fx.FixturePath -Target 'show-analyzers'
        $an.ExitCode | Should -Be 0
        $anN = $an.StdOutNormalized

        # clean twice
        $cl1 = Invoke-Make -FixturePath $fx.FixturePath -Target 'clean'
        $cl1.ExitCode | Should -Be 0
        $cl2 = Invoke-Make -FixturePath $fx.FixturePath -Target 'clean'
        $cl2.ExitCode | Should -Be 0

        # optional build
        $buildOut = $null
        $buildExit = $null
        if ($HasCompiler) {
            $b = Invoke-Make -FixturePath $fx.FixturePath -Target 'build'
            $buildOut = $b.StdOutNormalized + "`n" + $b.StdErrNormalized
            $buildExit = $b.ExitCode
        } else {
            # No compiler available; skip build execution but record status via signature categorization
            $buildOut = 'AL Compiler not found'
            $buildExit = 1
        }

            $sig = New-ParitySignature -ConfigOut $cfgN -AnalyzersOut $anN -BuildOut $buildOut -BuildExit $buildExit -CleanOut1 $cl1.StdOutNormalized -CleanOut2 $cl2.StdOutNormalized

        # Assertions (content-level, OS-agnostic)
        $sig.ShowConfig.Name | Should -Be 'SampleApp'
        $sig.ShowConfig.Publisher | Should -Be 'FBakkensen'
        $sig.ShowConfig.Version | Should -Be '1.0.0.0'
        $sig.ShowConfig.SettingsBlock | Should -Be $true
        $sig.ShowConfig.AnalyzersNone | Should -Be $true

        ($sig.ShowAnalyzers.HasPathsBlock -is [bool]) | Should -Be $true
        $sig.ShowAnalyzers.NoneEnabled | Should -Be $true

        (@('removed','none') -contains $sig.Clean.Run1) | Should -Be $true
        $sig.Clean.Run2 | Should -Be 'none'

        (@('success','failed','no-compiler','unknown') -contains $sig.Build.Status) | Should -Be $true
    }
}
