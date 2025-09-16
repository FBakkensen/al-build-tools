#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer guard: permission denied protection' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-perm-'
        $script:TargetRelativePath = 'Makefile'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails with PermissionDenied guard when overlay contains read-only files' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        $archive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace $archiveWorkspace

        $server = $null
        try {
            $server = Start-InstallArchiveServer -ZipPath $archive.ZipPath -BasePath ('albt-' + [Guid]::NewGuid().ToString('N'))

            $first = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref 'main'
            $first.ExitCode | Should -Be 0

            $targetPath = Join-Path $dest $script:TargetRelativePath
            Test-Path -LiteralPath $targetPath | Should -BeTrue

            if ($IsWindows) {
                $fileInfo = Get-Item -LiteralPath $targetPath -ErrorAction Stop
                $fileInfo.IsReadOnly = $true
            } else {
                & chmod 400 -- $targetPath
            }

            try {
                $second = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref 'main'

                $second.ExitCode | Should -Not -Be 0

                $lines = Get-InstallOutputLines -StdOut $second.StdOut -StdErr $second.StdErr
                $guardLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+guard\s+' }
                $guardLine | Should -Not -BeNullOrEmpty

                $guard = Assert-InstallGuardLine -Line $guardLine[0] -ExpectedGuard 'PermissionDenied'
                $guard.Guard | Should -Be 'PermissionDenied'

                ($lines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }) | Should -BeNullOrEmpty
            }
            finally {
                if (Test-Path -LiteralPath $targetPath) {
                    if ($IsWindows) {
                        $fileInfo = Get-Item -LiteralPath $targetPath -ErrorAction SilentlyContinue
                        if ($fileInfo) { $fileInfo.IsReadOnly = $false }
                    } else {
                        & chmod 600 -- $targetPath 2>$null
                    }
                }
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
