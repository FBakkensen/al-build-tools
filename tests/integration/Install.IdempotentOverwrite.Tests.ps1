#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer success path: idempotent overwrite' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $overlayRoot = Join-Path $script:RepoRoot 'overlay'
        $script:OverlaySnapshot = Get-InstallDirectorySnapshot -Path $overlayRoot -BasePath $overlayRoot
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-idem-'
        $script:TamperTarget = 'Makefile'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'restores modified overlay files on subsequent runs' {
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

            $first = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref 'main'
            $first.ExitCode | Should -Be 0
            $firstLines = Get-InstallOutputLines -StdOut $first.StdOut -StdErr $first.StdErr
            $firstSuccess = $firstLines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
            $firstSuccess | Should -Not -BeNullOrEmpty
            $null = Assert-InstallSuccessLine -Line $firstSuccess[0] -ExpectedRef 'main' -ExpectedOverlay 'overlay' -MaxDurationSeconds 120

            $afterFirst = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest
            $expectedPaths = $script:OverlaySnapshot | ForEach-Object { $_.Path }
            $actualOverlay = $afterFirst | Where-Object { $expectedPaths -contains $_.Path }
            Assert-InstallSnapshotsEqual -Expected $script:OverlaySnapshot -Actual $actualOverlay -Because 'Initial install overlay mismatch.'

            $tamperPath = Join-Path $dest $script:TamperTarget
            Test-Path -LiteralPath $tamperPath | Should -BeTrue
            Set-Content -LiteralPath $tamperPath -Value 'tampered content' -NoNewline

            $second = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref 'main'
            $second.ExitCode | Should -Be 0
            $secondLines = Get-InstallOutputLines -StdOut $second.StdOut -StdErr $second.StdErr
            $secondSuccess = $secondLines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
            $secondSuccess | Should -Not -BeNullOrEmpty
            $null = Assert-InstallSuccessLine -Line $secondSuccess[0] -ExpectedRef 'main' -ExpectedOverlay 'overlay' -MaxDurationSeconds 120

            $afterSecond = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest
            $actualOverlaySecond = $afterSecond | Where-Object { $expectedPaths -contains $_.Path }
            Assert-InstallSnapshotsEqual -Expected $script:OverlaySnapshot -Actual $actualOverlaySecond -Because 'Second install overlay mismatch.'

            $tamperBaseline = $script:OverlaySnapshot | Where-Object { $_.Path -eq $script:TamperTarget }
            $tamperBaseline | Should -Not -BeNullOrEmpty
            $tamperedActual = $afterSecond | Where-Object { $_.Path -eq $script:TamperTarget }
            $tamperedActual | Should -Not -BeNullOrEmpty
            $tamperedActual[0].Hash | Should -Be $tamperBaseline[0].Hash

            $beforeMap = @{}
            foreach ($item in $before) { $beforeMap[$item.Path] = $item }

            $changedPaths = @()
            foreach ($item in $afterSecond) {
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
