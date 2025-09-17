#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer download failure categorization: not found' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-notfound-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits NotFound category when archive endpoint returns 404' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
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

            $result.ExitCode | Should -Not -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $failureLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+download\s+failure\s+' }
            $failureLine | Should -Not -BeNullOrEmpty

            $failure = Assert-InstallDownloadFailureLine -Line $failureLine -ExpectedRef $missingRef -ExpectedCategory 'NotFound'
            $failure.Category | Should -Be 'NotFound'
        }
        finally {
            if ($server) { Stop-InstallArchiveServer -Server $server }
            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
