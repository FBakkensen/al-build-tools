#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

Describe 'Installer guard: permission denied protection' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-perm-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails with PermissionDenied guard when destination denies write access' {
        $caseRoot = Join-Path $script:WorkspaceRoot ("case-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $caseRoot | Out-Null

        $destRoot = Join-Path $caseRoot 'repo'
        $dest = Initialize-InstallTestRepo -Path $destRoot

        $archiveWorkspace = Join-Path $caseRoot 'pkg'
        $archive = New-InstallArchive -RepoRoot $script:RepoRoot -Workspace $archiveWorkspace

        $server = $null
        try {
            $server = Start-InstallArchiveServer -ZipPath $archive.ZipPath -BasePath ('albt-' + [Guid]::NewGuid().ToString('N'))

            $originalAclSddl = $null
            $unixWriteRemoved = $false

            # Deny write access to the destination directory
            if ($IsWindows) {
                $originalAclSddl = (Get-Acl -Path $dest).GetSecurityDescriptorSddlForm('All')
                $acl = Get-Acl -Path $dest
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
                    'Write',
                    'Deny'
                )
                $acl.SetAccessRule($accessRule)
                Set-Acl -Path $dest -AclObject $acl
            } else {
                & chmod 'u-w' $dest | Out-Null
                $unixWriteRemoved = $true
            }

            $result = Invoke-InstallScript -RepoRoot $script:RepoRoot -Dest $dest -Url $server.BaseUrl -Ref 'main'

            $result.ExitCode | Should -Be 30

            $lines = Get-InstallOutputLines -StdOut $result.StdOut -StdErr $result.StdErr
            $guardLine = $lines | Where-Object { $_ -match '^[[]install[]]\s+guard\s+' }
            $guardLine | Should -Not -BeNullOrEmpty

            $null = Assert-InstallGuardLine -Line $guardLine -ExpectedGuard 'PermissionDenied'
        }
        finally {
            if ($server) { Stop-InstallArchiveServer -Server $server }

            if (Test-Path -LiteralPath $dest) {
                if ($IsWindows -and $originalAclSddl) {
                    $restoreAcl = New-Object System.Security.AccessControl.DirectorySecurity
                    $restoreAcl.SetSecurityDescriptorSddlForm($originalAclSddl)
                    Set-Acl -Path $dest -AclObject $restoreAcl
                } elseif (-not $IsWindows -and $unixWriteRemoved) {
                    & chmod 'u+w' $dest | Out-Null
                }
            }

            if (Test-Path -LiteralPath $caseRoot) {
                Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
