#requires -Version 7.0

Describe 'RequiresVersion and help for next-object-number.ps1 (T011)' {
    It 'has #requires -Version 7.2 as the first non-empty line' {
        $scriptPath = Join-Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..' '..')) 'overlay/scripts') 'next-object-number.ps1'
        Test-Path $scriptPath | Should -BeTrue

        $lines = Get-Content -LiteralPath $scriptPath -Encoding UTF8
        $firstNonEmpty = ($lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | Select-Object -First 1)
        $firstNonEmpty | Should -Be '#requires -Version 7.2'
    }

    It 'Get-Help returns non-empty content' {
        $scriptPath = Join-Path (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..' '..')) 'overlay/scripts') 'next-object-number.ps1'
        $escaped = $scriptPath.Replace("'","''")
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'pwsh'
        $psi.Arguments = "-NoLogo -NoProfile -Command (Get-Help -Name '$escaped' -Full | Out-String)"
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        $out = $p.StandardOutput.ReadToEnd()
        $out.Trim().Length | Should -BeGreaterThan 0
    }
}
