#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Hash manifest determinism (T041)' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path -LiteralPath ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..'))).Path
        $script:HashManifestScript = Join-Path -Path $script:RepoRoot -ChildPath 'scripts/release/hash-manifest.ps1'
        if (-not (Test-Path -LiteralPath $script:HashManifestScript)) {
            throw "Expected hash manifest helper at $script:HashManifestScript"
        }
        . $script:HashManifestScript
        if (-not (Get-Command -Name Get-OverlayPayload -ErrorAction SilentlyContinue)) {
            $overlayScript = Join-Path -Path $script:RepoRoot -ChildPath 'scripts/release/overlay.ps1'
            if (-not (Test-Path -LiteralPath $overlayScript)) {
                throw "Expected overlay helper at $overlayScript"
            }
            . $overlayScript
        }
    }

    BeforeEach {
        $script:TempRepo = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("albt-hash-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TempRepo -Force | Out-Null
        $script:OverlayPath = Join-Path -Path $script:TempRepo -ChildPath 'overlay'
        New-Item -ItemType Directory -Path $script:OverlayPath -Force | Out-Null

        $bravo = Join-Path -Path $script:OverlayPath -ChildPath 'bravo'
        New-Item -ItemType Directory -Path $bravo -Force | Out-Null

        Set-Content -LiteralPath (Join-Path -Path $script:OverlayPath -ChildPath 'alpha.txt') -Value "Alpha`n"
        Set-Content -LiteralPath (Join-Path -Path $bravo -ChildPath 'config.json') -Value '{"setting":true}'
        Set-Content -LiteralPath (Join-Path -Path $bravo -ChildPath 'readme.md') -Value '# Sample'
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TempRepo) {
            Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'produces the same root hash for repeated generations' {
        $payload = Get-OverlayPayload -RepositoryRoot $script:TempRepo
        $first = New-HashManifest -OverlayPayload $payload -RepositoryRoot $script:TempRepo
        Start-Sleep -Milliseconds 10
        $second = New-HashManifest -OverlayPayload $payload -RepositoryRoot $script:TempRepo

        $first.RootHash | Should -Be $second.RootHash
        $first.ManifestLines[-1] | Should -Match '^__ROOT__:'
        $first.ManifestLines.Count | Should -Be ($payload.FileCount + 1)
    }

    It 'changes the root hash when file contents mutate' {
        $payload = Get-OverlayPayload -RepositoryRoot $script:TempRepo
        $baseline = New-HashManifest -OverlayPayload $payload -RepositoryRoot $script:TempRepo

        Set-Content -LiteralPath (Join-Path -Path $script:OverlayPath -ChildPath 'alpha.txt') -Value "Alpha updated`n"
        $updatedPayload = Get-OverlayPayload -RepositoryRoot $script:TempRepo
        $updated = New-HashManifest -OverlayPayload $updatedPayload -RepositoryRoot $script:TempRepo

        $baseline.RootHash | Should -Not -Be $updated.RootHash
    }
}
