#requires -Version 7.0
param([Parameter(ValueFromRemainingArguments=$true)] $Args)
$ErrorActionPreference = 'Stop'
# Log args to a file if requested
$log = $env:ALBT_SHIM_LOG
if ($log) {
    $text = ($Args | ForEach-Object { [string]$_ }) -join "`n"
    Set-Content -LiteralPath $log -Value $text -NoNewline
}
# Exit code override (default 0)
$code = 0
if ($env:ALBT_SHIM_EXIT) { $null = [int]::TryParse($env:ALBT_SHIM_EXIT, [ref]$code) }
exit $code
