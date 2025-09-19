#requires -Version 7.0
Set-StrictMode -Version Latest

Describe 'Overlay payload completeness (T042)' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path -LiteralPath ([IO.Path]::Combine($PSScriptRoot, '..', '..', '..'))).Path
        $script:ReleaseScript = Join-Path -Path $script:RepoRoot -ChildPath 'scripts/release/release-artifact.ps1'
        if (-not (Test-Path -LiteralPath $script:ReleaseScript)) {
            throw "Expected release artifact helper at $script:ReleaseScript"
        }
        . $script:ReleaseScript

        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }

    BeforeEach {
        $script:TempRepo = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("albt-overlay-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:TempRepo -Force | Out-Null

        & git -C $script:TempRepo init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
        & git -C $script:TempRepo config user.email 'albt-tests@example.com'
        & git -C $script:TempRepo config user.name 'ALBT Tests'

        $script:OverlayRoot = Join-Path -Path $script:TempRepo -ChildPath 'overlay'
        New-Item -ItemType Directory -Path $script:OverlayRoot -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TempRepo) {
            Remove-Item -LiteralPath $script:TempRepo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'packages hidden and visible overlay files into artifacts and manifests' {
        Set-Content -LiteralPath (Join-Path -Path $script:OverlayRoot -ChildPath 'visible.txt') -Value 'visible'
        Set-Content -LiteralPath (Join-Path -Path $script:OverlayRoot -ChildPath '.hidden-root') -Value 'hidden'

        $dotGithub = Join-Path -Path $script:OverlayRoot -ChildPath '.github'
        New-Item -ItemType Directory -Path $dotGithub -Force | Out-Null

        $dotWorkflows = Join-Path -Path $dotGithub -ChildPath 'workflows'
        New-Item -ItemType Directory -Path $dotWorkflows -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $dotWorkflows -ChildPath 'ci.yml') -Value 'name: CI'

        $nestedHidden = Join-Path -Path $dotGithub -ChildPath '.configs'
        New-Item -ItemType Directory -Path $nestedHidden -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $nestedHidden -ChildPath 'settings.json') -Value '{"enabled":true}'

        $visibleScripts = Join-Path -Path $script:OverlayRoot -ChildPath 'scripts'
        New-Item -ItemType Directory -Path $visibleScripts -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $visibleScripts -ChildPath '.env.sample') -Value 'KEY=value'

        & git -C $script:TempRepo add -A
        & git -C $script:TempRepo commit -m 'Seed overlay payload' --quiet
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }

        $artifactPath = Join-Path -Path $script:TempRepo -ChildPath 'artifact.zip'
        $artifact = New-ReleaseArtifact -Version 'v9.9.9' -RepositoryRoot $script:TempRepo -OutputPath $artifactPath

        $expectedPaths = @(
            'overlay/visible.txt',
            'overlay/.hidden-root',
            'overlay/.github/workflows/ci.yml',
            'overlay/.github/.configs/settings.json',
            'overlay/scripts/.env.sample'
        )

        $artifact.FileCount | Should -Be $expectedPaths.Count

        $zip = [System.IO.Compression.ZipFile]::OpenRead($artifact.OutputPath)
        try {
            $zipEntries = $zip.Entries | Where-Object { $_.FullName -ne 'manifest.sha256.txt' } | ForEach-Object { $_.FullName }
        } finally {
            $zip.Dispose()
        }

        foreach ($path in $expectedPaths) {
            $zipEntries | Should -Contain $path
        }

        $manifestPaths = $artifact.Manifest.Entries | ForEach-Object { $_.Path }
        foreach ($path in $expectedPaths) {
            $manifestPaths | Should -Contain $path
        }
    }
}

