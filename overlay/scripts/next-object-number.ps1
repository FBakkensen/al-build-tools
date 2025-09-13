#requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true, Position=0)]
  [ValidateNotNullOrEmpty()]
  [string]$ObjectType
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-IdRanges([string]$AppJsonPath) {
  if (-not (Test-Path -LiteralPath $AppJsonPath -PathType Leaf)) {
    throw "app.json not found at '$AppJsonPath'"
  }
  $json = Get-Content -Raw -LiteralPath $AppJsonPath | ConvertFrom-Json
  if (-not $json.idRanges) {
    throw "No 'idRanges' found in app.json"
  }
  foreach ($r in $json.idRanges) {
    if ($null -ne $r.from -and $null -ne $r.to) {
      [pscustomobject]@{ From = [int]$r.from; To = [int]$r.to }
    }
  }
}

function Get-UsedIds([string]$Root, [string]$ObjType) {
  $files = Get-ChildItem -LiteralPath $Root -Recurse -File -Include *.al -ErrorAction SilentlyContinue
  # Always return a HashSet for stable semantics
  $ids = [System.Collections.Generic.HashSet[int]]::new()
  if (-not $files) { return $ids }
  # Build regex with explicit escapes; avoid backspace escape in double-quoted strings
  $pattern = '\b' + [Regex]::Escape($ObjType) + '\s+(\d+)\b'
  foreach ($f in $files) {
    try {
      $matches = Select-String -LiteralPath $f.FullName -Pattern $pattern -AllMatches -Encoding UTF8 -ErrorAction SilentlyContinue
      foreach ($m in $matches) {
        foreach ($g in $m.Matches) { [void]$ids.Add([int]$g.Groups[1].Value) }
      }
    } catch { continue }
  }
  return $ids
}

try {
  $appJson = Join-Path -Path 'app' -ChildPath 'app.json'
  $ranges = @(Get-IdRanges -AppJsonPath $appJson)
  $used = Get-UsedIds -Root 'app' -ObjType $ObjectType
  $usedArr = @($used)
  foreach ($r in $ranges) {
    for ($i = $r.From; $i -le $r.To; $i++) {
      if (-not ($usedArr -contains $i)) { Write-Output $i; exit 0 }
    }
  }
  Write-Output "No available $ObjectType number found in the specified ranges."
  exit 2
} catch {
  $msg = ''
  if ($null -ne $PSItem) {
    if ($null -ne $PSItem.Exception) { $msg = $PSItem.Exception.Message }
    else { $msg = [string]$PSItem }
  } else { $msg = 'Unknown error' }
  Write-Error $msg
  exit 1
}
