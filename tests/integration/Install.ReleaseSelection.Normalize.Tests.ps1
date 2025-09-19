#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer release selection: tag normalization' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $overlayRoot = Join-Path $script:RepoRoot 'overlay'
        $script:OverlaySnapshot = Get-InstallDirectorySnapshot -Path $overlayRoot -BasePath $overlayRoot
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-rel-norm-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'canonicalizes unprefixed tags to v-prefixed release identifiers' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        if (-not (Test-Path -LiteralPath $archiveWorkspace)) {
            New-Item -ItemType Directory -Path $archiveWorkspace | Out-Null
        }
        $releaseArchive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace $archiveWorkspace -Ref 'v5.0.1'

        $server = $null
        try {
            $canonicalTag = 'v5.0.1'
            $releases = @(
                [pscustomobject]@{
                    Tag = $canonicalTag
                    ZipPath = $releaseArchive.ZipPath
                    PublishedAt = (Get-Date).AddMinutes(-30)
                }
            )

            $server = Start-InstallArchiveServer -BasePath ('albt-' + [Guid]::NewGuid().ToString('N')) -Releases $releases -LatestTag $canonicalTag

            $before = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest

            $unprefixedTag = '5.0.1'
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref $unprefixedTag

            $result.ExitCode | Should -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $successLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
            $successLine | Should -Not -BeNullOrEmpty

            $parsed = Assert-InstallSuccessLine -Line $successLine -ExpectedRef $canonicalTag -ExpectedOverlay 'overlay' -ExpectedAsset 'overlay.zip' -MaxDurationSeconds 300
            $parsed.CanonicalRef | Should -Be $canonicalTag

            $after = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest
            $expectedPaths = $script:OverlaySnapshot | ForEach-Object { $_.Path }
            $actualOverlay = $after | Where-Object { $expectedPaths -contains $_.Path }
            Assert-InstallSnapshotsEqual -Expected $script:OverlaySnapshot -Actual $actualOverlay -Because 'Normalized install did not copy expected overlay contents.'

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
