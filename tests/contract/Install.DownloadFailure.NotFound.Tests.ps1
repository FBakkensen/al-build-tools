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
        $knownArchive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace $archiveWorkspace -Ref 'v0.1.0'

        $server = $null
        try {
            $missingRefInput = '1.2.3'
            $missingCanonical = 'v1.2.3'

            $releases = @(
                [pscustomobject]@{
                    Tag = 'v0.1.0'
                    ZipPath = $knownArchive.ZipPath
                    PublishedAt = (Get-Date).AddHours(-2)
                }
            )

            $server = Start-InstallArchiveServer -BasePath ('albt-' + [Guid]::NewGuid().ToString('N')) -Releases $releases -LatestTag 'v0.1.0' -NotFoundTags @($missingRefInput, $missingCanonical)

            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref $missingRefInput

            $result.ExitCode | Should -Be 20

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $failureLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+download\s+failure\s+' }
            $failureLine | Should -Not -BeNullOrEmpty

            $failure = Assert-InstallDownloadFailureLine -Line $failureLine -ExpectedRef $missingRefInput -ExpectedCategory 'NotFound'
            $failure.Category | Should -Be 'NotFound'
            $failure.CanonicalRef | Should -Be $missingCanonical
            $failure.Hint | Should -Be 'Release tag not found'
        }
        finally {
            if ($server) { Stop-InstallArchiveServer -Server $server }
            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
