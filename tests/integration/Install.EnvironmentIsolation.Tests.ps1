#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer environment isolation' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:OverlayRoot = Join-Path $script:RepoRoot 'overlay'
        $script:OverlaySnapshot = Get-InstallDirectorySnapshot -Path $script:OverlayRoot -BasePath $script:OverlayRoot
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-iso-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'handles sequential installs in separate repos without cross-contamination' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        $archive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace $archiveWorkspace

        $server = $null
        $runs = @()
        try {
            $server = Start-InstallArchiveServer -ZipPath $archive.ZipPath -BasePath ('albt-' + [Guid]::NewGuid().ToString('N'))

            for ($i = 1; $i -le 2; $i++) {
                $destRoot = Join-Path $caseRoot ("repo-" + $i)
                $dest = Initialize-InstallTestRepo -Path $destRoot

                $before = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest

                $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref 'main'
                $result.ExitCode | Should -Be 0

                $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
                $successLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
                $successLine | Should -Not -BeNullOrEmpty
                $success = Assert-InstallSuccessLine -Line $successLine[0] -ExpectedRef 'main' -ExpectedOverlay 'overlay'

                $tempLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+temp\s+' }
                $tempLine | Should -Not -BeNullOrEmpty
                $temp = Assert-InstallTempLine -Line $tempLine[-1]
                Test-Path -LiteralPath $temp.Workspace | Should -BeFalse

                $after = Get-InstallDirectorySnapshot -Path $dest -BasePath $dest

                $runs += [pscustomobject]@{
                    Dest = $dest
                    Before = $before
                    After = $after
                    Success = $success
                    Temp = $temp
                }
            }

            $runs.Count | Should -Be 2

            $expectedPaths = $script:OverlaySnapshot | ForEach-Object { $_.Path }
            foreach ($run in $runs) {
                $actualOverlay = $run.After | Where-Object { $expectedPaths -contains $_.Path }
                Assert-InstallSnapshotsEqual -Expected $script:OverlaySnapshot -Actual $actualOverlay -Because 'Installed overlay does not match repository overlay.'

                $beforeMap = @{}
                foreach ($item in $run.Before) { $beforeMap[$item.Path] = $item }

                $changedPaths = @()
                foreach ($item in $run.After) {
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

            $uniqueTemps = $runs | ForEach-Object { $_.Temp.Workspace } | Sort-Object -Unique
            $uniqueTemps.Count | Should -Be $runs.Count

            $firstAfter = $runs[0].After
            $firstFinal = Get-InstallDirectorySnapshot -Path $runs[0].Dest -BasePath $runs[0].Dest
            Assert-InstallSnapshotsEqual -Expected $firstAfter -Actual $firstFinal -Because 'First install changed after running second install.'
        }
        finally {
            if ($server) { Stop-InstallArchiveServer -Server $server }
            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
