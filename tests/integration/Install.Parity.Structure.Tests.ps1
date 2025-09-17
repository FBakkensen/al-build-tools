#requires -Version 7.0
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Assert-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'Invoke-Install.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..' '_install' 'InstallArchiveServer.psm1') -Force

function Parse-InstallStepLine {
    param([string] $Line)

    $pattern = '^[[]install[]]\s+step\s+(?<Pairs>.+)$'
    $match = [regex]::Match($Line, $pattern)
    if (-not $match.Success) {
        throw "Line '$Line' does not match '[install] step' pattern."
    }

    $pairsText = $match.Groups['Pairs'].Value
    $pairs = @{}
    foreach ($segment in $pairsText -split '\s+') {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        if ($segment -notmatch '^(?<Key>[A-Za-z0-9_-]+)=(?<Value>.+)$') {
            throw "Segment '$segment' from '$Line' is not in key=value format."
        }

        $key = $Matches['Key']
        $value = $Matches['Value']
        $pairs[$key] = $value
    }

    foreach ($required in @('index','name')) {
        if (-not $pairs.ContainsKey($required)) {
            throw "Step diagnostic '$Line' missing required token '$required'."
        }
    }

    $index = 0
    if (-not [int]::TryParse($pairs['index'], [ref]$index)) {
        throw "Step index '$($pairs['index'])' from '$Line' is not an integer."
    }

    $name = $pairs['name']
    if ($name -notmatch '^[A-Za-z0-9_-]+$') {
        throw "Step name '$name' contains invalid characters for parity expectations."
    }

    return [pscustomobject]@{
        Index = $index
        Name = $name
        Pairs = $pairs
        RawLine = $Line
    }
}

Describe 'Installer parity structure' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:WorkspaceRoot = New-InstallTestWorkspace -Prefix 'albt-parity-'
    }

    AfterAll {
        if ($script:WorkspaceRoot -and (Test-Path -LiteralPath $script:WorkspaceRoot)) {
            Remove-Item -LiteralPath $script:WorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'emits sequential [install] step diagnostics with portable names' {
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
            $stepLines = $lines | Where-Object { $_ -match '^[[]install[]]\s+step\s+' }
            $stepLines | Should -Not -BeNullOrEmpty

            $parsed = @()
            foreach ($line in $stepLines) {
                $pattern = '^[[]install[]]\s+step\s+(?<Pairs>.+)$'
                $match = [regex]::Match($line, $pattern)
                if (-not $match.Success) {
                    throw "Line '$line' does not match '[install] step' pattern."
                }

                $pairsText = $match.Groups['Pairs'].Value
                $pairs = @{}
                foreach ($segment in $pairsText -split '\s+') {
                    if ([string]::IsNullOrWhiteSpace($segment)) { continue }
                    if ($segment -notmatch '^(?<Key>[A-Za-z0-9_-]+)=(?<Value>.+)$') {
                        throw "Segment '$segment' from '$line' is not in key=value format."
                    }

                    $key = $Matches['Key']
                    $value = $Matches['Value']
                    $pairs[$key] = $value
                }

                foreach ($required in @('index','name')) {
                    if (-not $pairs.ContainsKey($required)) {
                        throw "Step diagnostic '$line' missing required token '$required'."
                    }
                }

                $index = 0
                if (-not [int]::TryParse($pairs['index'], [ref]$index)) {
                    throw "Step index '$($pairs['index'])' from '$line' is not an integer."
                }

                $name = $pairs['name']
                if ($name -notmatch '^[A-Za-z0-9_-]+$') {
                    throw "Step name '$name' contains invalid characters for parity expectations."
                }

                $parsed += [pscustomobject]@{
                    Index = $index
                    Name = $name
                    Pairs = $pairs
                    RawLine = $line
                }
            }
            
            if ($parsed.Count -lt 4) {
                throw "Expected at least 4 step diagnostics, but found $($parsed.Count)"
            }

            $ordered = $parsed | Sort-Object -Property Index
            for ($i = 0; $i -lt $ordered.Count; $i++) {
                $expectedIndex = $i + 1
                $ordered[$i].Index | Should -Be $expectedIndex
            }

            $names = $ordered | ForEach-Object { $_.Name }
            foreach ($name in $names) {
                $name.Contains('/') | Should -BeFalse
                $name.Contains('\') | Should -BeFalse
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
