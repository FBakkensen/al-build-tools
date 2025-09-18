#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Diff summary classification (T042)' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path -LiteralPath ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..'))).Path
        $script:DiffSummaryScript = Join-Path -Path $script:RepoRoot -ChildPath 'scripts/release/diff-summary.ps1'
        if (-not (Test-Path -LiteralPath $script:DiffSummaryScript)) {
            throw "Expected diff summary helper at $script:DiffSummaryScript"
        }
        . $script:DiffSummaryScript

        if (-not (Get-Command -Name Get-VersionInfo -ErrorAction SilentlyContinue)) {
            $versionScript = Join-Path -Path $script:RepoRoot -ChildPath 'scripts/release/version.ps1'
            if (-not (Test-Path -LiteralPath $versionScript)) {
                throw "Expected version helper at $versionScript"
            }
            . $versionScript
        }
    }

    Context 'initial release' {
        BeforeAll {
            $script:InitialRepo = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("albt-diff-initial-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:InitialRepo -Force | Out-Null

            & git -C $script:InitialRepo init --quiet
            if ($LASTEXITCODE -ne 0) { throw 'git init failed for initial repo' }
            & git -C $script:InitialRepo config user.email 'albt-tests@example.com'
            & git -C $script:InitialRepo config user.name 'ALBT Tests'

            $overlay = Join-Path -Path $script:InitialRepo -ChildPath 'overlay'
            New-Item -ItemType Directory -Path $overlay -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $overlay -ChildPath 'first.txt') -Value 'hello'

            & git -C $script:InitialRepo add .
            & git -C $script:InitialRepo commit -m 'Bootstrap overlay' --quiet
            if ($LASTEXITCODE -ne 0) { throw 'initial commit failed' }
        }

        AfterAll {
            if (Test-Path -LiteralPath $script:InitialRepo) {
                Remove-Item -LiteralPath $script:InitialRepo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'flags an initial release when no lower tags exist' {
            $summary = Get-DiffSummary -Version 'v1.0.0' -RepositoryRoot $script:InitialRepo
            $summary.IsInitialRelease | Should -BeTrue
            $summary.PreviousVersion | Should -BeNullOrEmpty
            $summary.Notes | Should -Be 'Initial release'
            $summary.Added.Count | Should -Be 0
            $summary.Modified.Count | Should -Be 0
            $summary.Removed.Count | Should -Be 0
        }
    }

    Context 'classification against previous tag' {
        BeforeAll {
            $script:ClassRepo = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("albt-diff-class-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $script:ClassRepo -Force | Out-Null

            & git -C $script:ClassRepo init --quiet
            if ($LASTEXITCODE -ne 0) { throw 'git init failed for classification repo' }
            & git -C $script:ClassRepo config user.email 'albt-tests@example.com'
            & git -C $script:ClassRepo config user.name 'ALBT Tests'

            $overlay = Join-Path -Path $script:ClassRepo -ChildPath 'overlay'
            New-Item -ItemType Directory -Path $overlay -Force | Out-Null

            Set-Content -LiteralPath (Join-Path -Path $overlay -ChildPath 'keep.txt') -Value 'keep v1'
            Set-Content -LiteralPath (Join-Path -Path $overlay -ChildPath 'remove.txt') -Value 'remove me'

            & git -C $script:ClassRepo add .
            & git -C $script:ClassRepo commit -m 'Initial overlay' --quiet
            if ($LASTEXITCODE -ne 0) { throw 'initial commit failed for classification repo' }
            & git -C $script:ClassRepo tag v1.0.0
            if ($LASTEXITCODE -ne 0) { throw 'tag creation failed for classification repo' }

            Set-Content -LiteralPath (Join-Path -Path $overlay -ChildPath 'keep.txt') -Value 'keep v2'
            Remove-Item -LiteralPath (Join-Path -Path $overlay -ChildPath 'remove.txt') -Force
            Set-Content -LiteralPath (Join-Path -Path $overlay -ChildPath 'add.txt') -Value 'new file'

            & git -C $script:ClassRepo add -A
            & git -C $script:ClassRepo commit -m 'Overlay adjustments for v1.1.0' --quiet
            if ($LASTEXITCODE -ne 0) { throw 'second commit failed for classification repo' }
        }

        AfterAll {
            if (Test-Path -LiteralPath $script:ClassRepo) {
                Remove-Item -LiteralPath $script:ClassRepo -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'classifies added, modified, and removed overlay files' {
            $summary = Get-DiffSummary -Version 'v1.1.0' -RepositoryRoot $script:ClassRepo
            $summary.IsInitialRelease | Should -BeFalse
            $summary.PreviousVersion | Should -Be 'v1.0.0'
            $summary.Added | Should -Contain 'overlay/add.txt'
            $summary.Modified | Should -Contain 'overlay/keep.txt'
            $summary.Removed | Should -Contain 'overlay/remove.txt'
            $summary.CurrentCommit | Should -Not -BeNullOrEmpty
            $summary.PreviousCommit | Should -Not -BeNullOrEmpty
        }
    }
}
