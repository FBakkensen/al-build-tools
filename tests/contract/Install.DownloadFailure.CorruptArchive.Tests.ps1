#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer download failure categorization: corrupt archive' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-corrupt-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits CorruptArchive category when downloaded bytes are not a valid zip' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        $archive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace $archiveWorkspace

        $corruptZip = $archive.ZipPath
        Set-Content -LiteralPath $corruptZip -Value 'not-a-zip-archive' -NoNewline

        $server = $null
        try {
            $server = Start-InstallArchiveServer -ZipPath $corruptZip -BasePath ('albt-' + [Guid]::NewGuid().ToString('N'))

            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref 'main'

            $result.ExitCode | Should -Be 20

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $failureLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+download\s+failure\s+' }
            $failureLine | Should -Not -BeNullOrEmpty

            $failure = Assert-InstallDownloadFailureLine -Line $failureLine -ExpectedRef 'main' -ExpectedCategory 'CorruptArchive'
            $failure.Category | Should -Be 'CorruptArchive'
        }
        finally {
            if ($server) { Stop-InstallArchiveServer -Server $server }
            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
