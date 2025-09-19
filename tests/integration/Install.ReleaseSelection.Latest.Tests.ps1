#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer release selection: latest published release' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $overlayRoot = Join-Path $script:RepoRoot 'overlay'
        $script:OverlaySnapshot = Get-InstallDirectorySnapshot -Path $overlayRoot -BasePath $overlayRoot
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-rel-latest-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'selects the latest release when -Ref is omitted' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        if (-not (Test-Path -LiteralPath $archiveWorkspace)) {
            New-Item -ItemType Directory -Path $archiveWorkspace | Out-Null
        }
        $latestArchive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace (Join-Path $archiveWorkspace 'latest') -Ref 'v2.1.0'
        $previousArchive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace (Join-Path $archiveWorkspace 'previous') -Ref 'v2.0.5'

        $server = $null
        try {
            $latestTag = 'v2.1.0'
            $previousTag = 'v2.0.5'
            $releases = @(
                [pscustomobject]@{
                    Tag = $latestTag
                    ZipPath = $latestArchive.ZipPath
                    PublishedAt = (Get-Date).AddMinutes(-5)
                },
                [pscustomobject]@{
                    Tag = $previousTag
                    ZipPath = $previousArchive.ZipPath
                    PublishedAt = (Get-Date).AddHours(-2)
                }
            )

            $server = Start-InstallArchiveServer -BasePath ('albt-' + [Guid]::NewGuid().ToString('N')) -Releases $releases -LatestTag $latestTag

            $before = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest

            $scriptPath = Join-Path $script:RepoRoot 'bootstrap' 'install.ps1'
            $arguments = "-Dest `"$dest`" -Url `"$($server.BaseUrl)`" -Source overlay"
            $result = Invoke-ChildPwsh -ScriptPath $scriptPath -Arguments $arguments -WorkingDirectory $script:RepoRoot

            $result.ExitCode | Should -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $successLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
            $successLine | Should -Not -BeNullOrEmpty

            $parsed = Assert-InstallSuccessLine -Line $successLine -ExpectedRef $latestTag -ExpectedOverlay 'overlay' -ExpectedAsset 'overlay.zip' -MaxDurationSeconds 300
            $parsed.CanonicalRef | Should -Be $latestTag

            $after = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest
            $expectedPaths = $script:OverlaySnapshot | ForEach-Object { $_.Path }
            $actualOverlay = $after | Where-Object { $expectedPaths -contains $_.Path }
            Assert-InstallSnapshotsEqual -Expected $script:OverlaySnapshot -Actual $actualOverlay -Because 'Installed overlay snapshot diverged from expected release contents.'

            $beforeMap = @{}
            foreach ($item in $before) { $beforeMap[$item.Path] = $item }
            foreach ($item in $after) {
                if ($beforeMap.ContainsKey($item.Path) -and $beforeMap[$item.Path].Hash -eq $item.Hash) { continue }
                $expectedPaths | Should -Contain $item.Path
            }
        }
        finally {
            if ($server) { Stop-InstallArchiveServer -Server $server }
            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'falls back to versioned asset names when overlay.zip is missing' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        if (-not (Test-Path -LiteralPath $archiveWorkspace)) {
            New-Item -ItemType Directory -Path $archiveWorkspace | Out-Null
        }
        $latestTag = 'v3.0.0'
        $latestAssetName = 'al-build-tools-v3.0.0.zip'
        $latestArchive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace (Join-Path $archiveWorkspace 'latest') -Ref $latestTag

        $server = $null
        try {
            $releases = @(
                [pscustomobject]@{
                    Tag = $latestTag
                    ZipPath = $latestArchive.ZipPath
                    AssetName = $latestAssetName
                    PublishedAt = (Get-Date).AddMinutes(-5)
                }
            )

            $server = Start-InstallArchiveServer -BasePath ('albt-' + [Guid]::NewGuid().ToString('N')) -Releases $releases -LatestTag $latestTag

            $before = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest

            $scriptPath = Join-Path $script:RepoRoot 'bootstrap' 'install.ps1'
            $arguments = "-Dest `"$dest`" -Url `"$($server.BaseUrl)`" -Source overlay"
            $result = Invoke-ChildPwsh -ScriptPath $scriptPath -Arguments $arguments -WorkingDirectory $script:RepoRoot

            $result.ExitCode | Should -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $successLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
            $successLine | Should -Not -BeNullOrEmpty

            $parsed = Assert-InstallSuccessLine -Line $successLine -ExpectedRef $latestTag -ExpectedOverlay 'overlay' -ExpectedAsset $latestAssetName -MaxDurationSeconds 300
            $parsed.CanonicalRef | Should -Be $latestTag

            $after = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest
            $expectedPaths = $script:OverlaySnapshot | ForEach-Object { $_.Path }
            $actualOverlay = $after | Where-Object { $expectedPaths -contains $_.Path }
            Assert-InstallSnapshotsEqual -Expected $script:OverlaySnapshot -Actual $actualOverlay -Because 'Installed overlay snapshot diverged from expected release contents.'

            $beforeMap = @{}
            foreach ($item in $before) { $beforeMap[$item.Path] = $item }
            foreach ($item in $after) {
                if ($beforeMap.ContainsKey($item.Path) -and $beforeMap[$item.Path].Hash -eq $item.Hash) { continue }
                $expectedPaths | Should -Contain $item.Path
            }
        }
        finally {
            if ($server) { Stop-InstallArchiveServer -Server $server }
            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
