#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer success path: basic overlay install' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $overlayRoot = Join-Path $script:RepoRoot 'overlay'
        $script:OverlaySnapshot = Get-InstallDirectorySnapshot -Path $overlayRoot -BasePath $overlayRoot
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-success-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'installs overlay files and reports success diagnostics' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        $archive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace $archiveWorkspace

        $server = $null
        try {
            $before = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest

            $server = Start-InstallArchiveServer -ZipPath $archive.ZipPath -BasePath ('albt-' + [Guid]::NewGuid().ToString('N'))
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref 'main'

            $result.ExitCode | Should -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $successLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
            $successLine | Should -Not -BeNullOrEmpty

            $null = Assert-InstallSuccessLine -Line $successLine[0] -ExpectedRef 'main' -ExpectedOverlay 'overlay' -MaxDurationSeconds 120

            $after = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest
            $expectedPaths = $script:OverlaySnapshot | ForEach-Object { $_.Path }
            $actualOverlay = $after | Where-Object { $expectedPaths -contains $_.Path }
            Assert-InstallSnapshotsEqual -Expected $script:OverlaySnapshot -Actual $actualOverlay -Because 'Installed overlay does not match repository overlay.'

            $beforeMap = @{}
            foreach ($item in $before) { $beforeMap[$item.Path] = $item }

            $changedPaths = @()
            foreach ($item in $after) {
                if ($beforeMap.ContainsKey($item.Path)) {
                    if ($beforeMap[$item.Path].Hash -ne $item.Hash) { $changedPaths += $item.Path }
                } else {
                    $changedPaths += $item.Path
                }
            }

            foreach ($path in $changedPaths) {
                $expectedPaths | Should -Contain $path
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
