#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer diagnostics stability' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-diag-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits anchored guard diagnostics' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("guard-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $dest = Join-Path $caseRoot 'dest'
        New-Item -ItemType Directory -Path $dest | Out-Null

        try {
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest

            $result.ExitCode | Should -Be 10

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $guardLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+guard\s+' }
            $guardLine | Should -Not -BeNullOrEmpty

            $parsed = Assert-InstallGuardLine -Line $guardLine
            $parsed.RawLine.StartsWith('[install] guard') | Should -BeTrue
        }
        finally {
            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'emits anchored success diagnostics' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("success-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        $archive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace $archiveWorkspace -Ref 'v1.2.3'

        $server = $null
        try {
            $releaseTag = 'v1.2.3'
            $server = Start-InstallArchiveServer -BasePath ('albt-' + [Guid]::NewGuid().ToString('N')) -Releases @(
                [pscustomobject]@{
                    Tag = $releaseTag
                    ZipPath = $archive.ZipPath
                    PublishedAt = (Get-Date).AddMinutes(-5)
                }
            ) -LatestTag $releaseTag

            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref $releaseTag

            $result.ExitCode | Should -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $successLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
            $successLine | Should -Not -BeNullOrEmpty

            $parsed = Assert-InstallSuccessLine -Line $successLine -ExpectedRef $releaseTag -ExpectedOverlay 'overlay' -ExpectedAsset 'overlay.zip' -MaxDurationSeconds 300
            $parsed.RawLine.StartsWith('[install] success') | Should -BeTrue
        }
        finally {
            if ($server) { Stop-InstallArchiveServer -Server $server }
            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'emits anchored download failure diagnostics' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("download-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        $archive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace $archiveWorkspace

        $server = $null
        try {
            $server = Start-InstallArchiveServer -ZipPath $archive.ZipPath -BasePath ('albt-' + [Guid]::NewGuid().ToString('N')) -StatusCode 404
            $missingRef = 'missing-' + [Guid]::NewGuid().ToString('N')
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref $missingRef

            $result.ExitCode | Should -Be 20

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $failureLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+download\s+failure\s+' }
            $failureLine | Should -Not -BeNullOrEmpty

            $parsed = Assert-InstallDownloadFailureLine -Line $failureLine -ExpectedRef $missingRef
            $parsed.RawLine.StartsWith('[install] download failure') | Should -BeTrue
        }
        finally {
            if ($server) { Stop-InstallArchiveServer -Server $server }
            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'emits verbose diagnostics when ALBT_RELEASE overrides the release selection' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("env-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        if (-not (Test-Path -LiteralPath $archiveWorkspace)) {
            New-Item -ItemType Directory -Path $archiveWorkspace | Out-Null
        }
        $latestArchive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace (Join-Path $archiveWorkspace 'latest') -Ref 'v9.9.9'
        $overrideArchive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace (Join-Path $archiveWorkspace 'override') -Ref 'v9.9.8'

        $server = $null
        try {
            $latestTag = 'v9.9.9'
            $overrideTag = 'v9.9.8'

            $releases = @(
                [pscustomobject]@{
                    Tag = $latestTag
                    ZipPath = $latestArchive.ZipPath
                    PublishedAt = (Get-Date).AddMinutes(-1)
                },
                [pscustomobject]@{
                    Tag = $overrideTag
                    ZipPath = $overrideArchive.ZipPath
                    PublishedAt = (Get-Date).AddHours(-1)
                }
            )

            $server = Start-InstallArchiveServer -BasePath ('albt-' + [Guid]::NewGuid().ToString('N')) -Releases $releases -LatestTag $latestTag

            $scriptPath = Join-Path $script:RepoRoot 'bootstrap' 'install.ps1'
            $arguments = "-Dest `"$dest`" -Url `"$($server.BaseUrl)`" -Source overlay -Verbose"
            $env = @{ 'ALBT_RELEASE' = $overrideTag }
            $result = Invoke-ChildPwsh -ScriptPath $scriptPath -Arguments $arguments -WorkingDirectory $script:RepoRoot -Env $env -EngineVerbose

            $result.ExitCode | Should -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr

            $verboseLine = $lines | Where-Object { $_ -match 'Using env ALBT_RELEASE=' }
            $verboseLine | Should -Not -BeNullOrEmpty
            $verboseLine | Should -Match "Using env ALBT_RELEASE=$overrideTag"

            $successLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
            $successLine | Should -Not -BeNullOrEmpty

            $parsed = Assert-InstallSuccessLine -Line $successLine -ExpectedRef $overrideTag -ExpectedOverlay 'overlay' -ExpectedAsset 'overlay.zip' -MaxDurationSeconds 300
            $parsed.CanonicalRef | Should -Be $overrideTag
        }
        finally {
            if ($server) { Stop-InstallArchiveServer -Server $server }
            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
