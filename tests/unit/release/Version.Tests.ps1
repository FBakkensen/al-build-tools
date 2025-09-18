#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Version helper semantics (T040)' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path -LiteralPath ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..'))).Path
        $script:VersionScript = Join-Path -Path $script:RepoRoot -ChildPath 'scripts/release/version.ps1'
        if (-not (Test-Path -LiteralPath $script:VersionScript)) {
            throw "Expected version helper at $script:VersionScript"
        }
        . $script:VersionScript
    }

    It 'normalizes trimmed semantic versions with v-prefix' {
        $result = ConvertTo-ReleaseVersion -Version '  v1.2.3  '
        $result.Normalized | Should -Be 'v1.2.3'
        $result.Major | Should -Be 1
        $result.Minor | Should -Be 2
        $result.Patch | Should -Be 3
        $result.TagName | Should -Be 'v1.2.3'
    }

    It 'rejects invalid versions without leading v' {
        try {
            ConvertTo-ReleaseVersion -Version '1.2.3' | Out-Null
            throw 'Expected ConvertTo-ReleaseVersion to reject missing leading v.'
        } catch {
            $_.Exception.Message | Should -Match "leading 'v'"
        }
    }

    It 'orders versions by major, minor, then patch' {
        Compare-ReleaseVersion -Left 'v2.0.0' -Right 'v1.9.9' | Should -BeGreaterThan 0
        Compare-ReleaseVersion -Left 'v1.5.0' -Right 'v1.10.0' | Should -BeLessThan 0
        $left = ConvertTo-ReleaseVersion -Version 'v1.2.5'
        $right = ConvertTo-ReleaseVersion -Version 'v1.2.4'
        Compare-ReleaseVersion -Left $left -Right $right | Should -BeGreaterThan 0
    }

    Context 'git-aware helpers' {
        BeforeAll {
            $script:TempRepo = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("albt-version-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:TempRepo -Force | Out-Null

            & git -C $script:TempRepo init --quiet
            if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
            & git -C $script:TempRepo config user.email 'albt-tests@example.com'
            & git -C $script:TempRepo config user.name 'ALBT Tests'

            $overlayPath = Join-Path -Path $script:TempRepo -ChildPath 'overlay'
            New-Item -ItemType Directory -Path $overlayPath -Force | Out-Null

            Set-Content -LiteralPath (Join-Path -Path $overlayPath -ChildPath 'keep.txt') -Value 'initial'
            Set-Content -LiteralPath (Join-Path -Path $overlayPath -ChildPath 'remove.txt') -Value 'remove'

            & git -C $script:TempRepo add .
            & git -C $script:TempRepo commit -m 'Initial overlay' --quiet
            if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
            & git -C $script:TempRepo tag v1.0.0
            if ($LASTEXITCODE -ne 0) { throw 'git tag failed' }

            Set-Content -LiteralPath (Join-Path -Path $overlayPath -ChildPath 'keep.txt') -Value 'updated'
            Remove-Item -LiteralPath (Join-Path -Path $overlayPath -ChildPath 'remove.txt') -Force
            Set-Content -LiteralPath (Join-Path -Path $overlayPath -ChildPath 'add.txt') -Value 'added'

            & git -C $script:TempRepo add -A
            & git -C $script:TempRepo commit -m 'Prepare next release' --quiet
            if ($LASTEXITCODE -ne 0) { throw 'second git commit failed' }
        }

        AfterAll {
            if (Test-Path -LiteralPath $script:TempRepo) {
                Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'detects when a tag already exists' {
            $info = Get-VersionInfo -Version 'v1.0.0' -RepositoryRoot $script:TempRepo
            $info.TagExists | Should -BeTrue
            $info.IsGreaterThanLatest | Should -BeFalse
        }

        It 'flags candidate versions greater than the latest tag' {
            $info = Get-VersionInfo -Version 'v1.1.0' -RepositoryRoot $script:TempRepo
            $info.TagExists | Should -BeFalse
            $info.IsGreaterThanLatest | Should -BeTrue
            $info.Latest.Normalized | Should -Be 'v1.0.0'
        }
    }
}
