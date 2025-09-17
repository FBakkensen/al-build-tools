#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force

Describe 'Installer download failure categorization: network unavailable' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-netfail-'
        $script:BaseUrl = 'http://127.0.0.1:9/albt'
        $script:Ref = 'main'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits NetworkUnavailable category when connection cannot be established' {
        $destRoot = Join-Path $script:WorkspaceRoot ("repo-" + [Guid]::NewGuid().ToString('N'))
        $dest = Initialize-InstallTestRepo -Path $destRoot

        try {
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $script:BaseUrl -Ref $script:Ref

            $result.ExitCode | Should -Not -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $failureLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+download\s+failure\s+' }
            $failureLine | Should -Not -BeNullOrEmpty

            $failure = Assert-InstallDownloadFailureLine -Line $failureLine -ExpectedRef $script:Ref -ExpectedCategory 'NetworkUnavailable'
            $failure.Category | Should -Be 'NetworkUnavailable'
        }
        finally {
            if (Test-Path -LiteralPath $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
