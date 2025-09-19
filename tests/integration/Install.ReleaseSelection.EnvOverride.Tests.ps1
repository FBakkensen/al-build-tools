#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer release selection: environment override' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $overlayRoot = Join-Path $script:RepoRoot 'overlay'
        $script:OverlaySnapshot = Get-InstallDirectorySnapshot -Path $overlayRoot -BasePath $overlayRoot
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-rel-env-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'honors ALBT_RELEASE and emits verbose override diagnostics' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        if (-not (Test-Path -LiteralPath $archiveWorkspace)) {
            New-Item -ItemType Directory -Path $archiveWorkspace | Out-Null
        }
        $latestArchive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace (Join-Path $archiveWorkspace 'latest') -Ref 'v4.1.0'
        $overrideArchive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace (Join-Path $archiveWorkspace 'override') -Ref 'v4.0.0'

        $server = $null
        try {
            $latestTag = 'v4.1.0'
            $overrideTag = 'v4.0.0'
            $releases = @(
                [pscustomobject]@{
                    Tag = $latestTag
                    ZipPath = $latestArchive.ZipPath
                    PublishedAt = (Get-Date).AddMinutes(-2)
                },
                [pscustomobject]@{
                    Tag = $overrideTag
                    ZipPath = $overrideArchive.ZipPath
                    PublishedAt = (Get-Date).AddHours(-3)
                }
            )

            $server = Start-InstallArchiveServer -BasePath ('albt-' + [Guid]::NewGuid().ToString('N')) -Releases $releases -LatestTag $latestTag

            $before = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest

            $scriptPath = Join-Path $script:RepoRoot 'bootstrap' 'install.ps1'
            $arguments = "-Dest `"$dest`" -Url `"$($server.BaseUrl)`" -Source overlay -Verbose"
            $env = @{ 'ALBT_RELEASE' = $overrideTag }
            $result = Invoke-ChildPwsh -ScriptPath $scriptPath -Arguments $arguments -WorkingDirectory $script:RepoRoot -Env $env -EngineVerbose

            $result.ExitCode | Should -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr

            $verboseLines = $lines | Where-Object { $_ -match 'Using env ALBT_RELEASE=' }
            $verboseLines | Should -Not -BeNullOrEmpty
            foreach ($line in $verboseLines) {
                $line | Should -Match "Using env ALBT_RELEASE=$overrideTag"
            }

            $successLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
            $successLine | Should -Not -BeNullOrEmpty

            $parsed = Assert-InstallSuccessLine -Line $successLine -ExpectedRef $overrideTag -ExpectedOverlay 'overlay' -ExpectedAsset 'overlay.zip' -MaxDurationSeconds 300
            $parsed.CanonicalRef | Should -Be $overrideTag

            $after = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest
            $expectedPaths = $script:OverlaySnapshot | ForEach-Object { $_.Path }
            $actualOverlay = $after | Where-Object { $expectedPaths -contains $_.Path }
            Assert-InstallSnapshotsEqual -Expected $script:OverlaySnapshot -Actual $actualOverlay -Because 'Override install did not copy expected overlay contents.'

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
