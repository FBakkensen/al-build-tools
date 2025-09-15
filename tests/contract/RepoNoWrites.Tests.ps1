#requires -Version 7.0

Describe 'Repo cleanliness: tests must not write artifacts to repo root' {
    It 'does not contain testResults.xml at repo root' {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
        $path = Join-Path $repoRoot 'testResults.xml'
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}

