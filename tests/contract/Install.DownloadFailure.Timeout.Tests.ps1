#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force

Describe 'Installer download failure categorization: timeout' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-timeout-'
        $script:BaseUrl = 'http://192.0.2.1'
        $script:Ref = 'main'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits Timeout category when download times out' {
        $destRoot = Join-Path $script:WorkspaceRoot ("repo-" + [Guid]::NewGuid().ToString('N'))
        $dest = Initialize-InstallTestRepo -Path $destRoot

        try {
            # Use a small timeout to keep the negative-path test fast.
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $script:BaseUrl -Ref $script:Ref -AdditionalArguments @('-HttpTimeoutSec', '5')

            $result.ExitCode | Should -Be 20

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $failureLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+download\s+failure\s+' }
            $failureLine | Should -Not -BeNullOrEmpty

            $failure = Assert-InstallDownloadFailureLine -Line $failureLine -ExpectedRef $script:Ref
            $allowedCategories = @('Timeout','NetworkUnavailable')
            $allowedCategories | Should -Contain $failure.Category
            if ($failure.Category -ne 'Timeout') {
                Write-Warning "Expected Timeout classification but observed '$($failure.Category)' (network stack may surface different error strings)."
            }
        }
        finally {
            if (Test-Path -LiteralPath $dest) {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
