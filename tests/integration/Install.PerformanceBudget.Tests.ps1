#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer performance budget' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-perf-'
        $script:WarningThresholdSeconds = 25
        $script:FailThresholdSeconds = 30
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'completes within the documented performance budget' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        $archive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace $archiveWorkspace

        $server = $null
        try {
            $server = Start-InstallArchiveServer -ZipPath $archive.ZipPath -BasePath ('albt-' + [Guid]::NewGuid().ToString('N'))
            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref 'main'

            $result.ExitCode | Should -Be 0

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $successLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+success\s+' }
            $successLine | Should -Not -BeNullOrEmpty

            # Use the existing Assert-InstallSuccessLine function but handle the result differently
            $null = Assert-InstallSuccessLine -Line $successLine -ExpectedRef 'main' -ExpectedOverlay 'overlay'
            
            # Manually parse the duration from the success line to avoid parameter binding issues
            $durationMatch = [regex]::Match($successLine, 'duration=([0-9.]+)')
            $durationMatch.Success | Should -BeTrue
            $duration = [double]::Parse($durationMatch.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
            
            # Validate duration bounds
            if ($duration -lt 0) {
                throw "Duration cannot be negative: $duration"
            }
            
            if ($duration -gt $script:WarningThresholdSeconds) {
                Write-Warning ("Installer duration {0:N2}s exceeded warning threshold {1}s" -f $duration, $script:WarningThresholdSeconds)
            }
            
            if ($duration -ge $script:FailThresholdSeconds) {
                throw "Installer duration {0:N2}s exceeded failure threshold {1}s" -f $duration, $script:FailThresholdSeconds
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