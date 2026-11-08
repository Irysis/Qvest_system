<#
switch_env.ps1 — 사용자 환경 변수를 R 4.6.2 · Python 3.15.2 로 전환(또는 -Rollback 으로 되돌림) · 2026-11-08
  ★도구 세션 밖에서(일회용 예약 작업) — Claude 도구 세션의 HKCU 쓰기는 가상화돼 다른 프로세스가 못 본다.
  - 백업: .cache\installers\env_backup_20261108.json (원래 값 · 종류) — 이미 있으면 덮지 않는다(첫 백업이 원본).
  - Path(ExpandString 유지): R-4.5.2\bin → R-4.6.2\bin · Python312\Scripts\ → Python315\Scripts\ · Python312\ → Python315\
  - QVEST_PY = C:\Users\99922\AppData\Local\Programs\Python\Python315\python.exe (원래와 같은 99922 경로 방식)
  - QVEST_RSCRIPT = C:\Program Files\R\R-4.6.2\bin\Rscript.exe (새로 만듦 — ${QVEST_RSCRIPT:-…} 를 보는 스크립트용)
  - WM_SETTINGCHANGE 방송(새로 뜨는 프로세스가 새 값을 받게) · 결과 = .cache\installers\switch_env.result.txt
#>
param([switch]$Rollback)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Dir = Join-Path $Root '.cache\installers'
$Backup = Join-Path $Dir 'env_backup_20261108.json'
$Result = Join-Path $Dir 'switch_env.result.txt'
function Write-Result([string]$Msg) { Add-Content -LiteralPath $Result -Value ('{0} [{1}] {2}' -f (Get-Date -Format s), $env:COMPUTERNAME, $Msg) -Encoding UTF8 }

$key = Get-Item 'HKCU:\Environment'
function Get-Raw($n) { $v = $key.GetValue($n, $null, 'DoNotExpandEnvironmentNames'); if ($null -eq $v) { $null } else { @{ value = $v; kind = $key.GetValueKind($n).ToString() } } }

Add-Type -Namespace Qv -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
function Send-SettingChange { $r = [UIntPtr]::Zero; [void][Qv.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r) }

if ($Rollback) {
  if (-not (Test-Path -LiteralPath $Backup)) { Write-Result 'STOP 백업 없음 — 되돌릴 수 없음'; exit 2 }
  $b = Get-Content -LiteralPath $Backup -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($n in 'Path', 'QVEST_PY', 'QVEST_RSCRIPT') {
    $e = $b.$n
    if ($null -eq $e) { Remove-ItemProperty -Path 'HKCU:\Environment' -Name $n -ErrorAction SilentlyContinue }
    else { Set-ItemProperty -Path 'HKCU:\Environment' -Name $n -Value $e.value -Type $e.kind }
  }
  Send-SettingChange
  Write-Result 'ROLLBACK OK — Path · QVEST_PY · QVEST_RSCRIPT 원래 값'
  exit 0
}

if (-not (Test-Path -LiteralPath 'C:\Program Files\R\R-4.6.2\bin\Rscript.exe')) { Write-Result 'STOP R 4.6.2 없음'; exit 2 }
$py315 = 'C:\Users\99922\AppData\Local\Programs\Python\Python315\python.exe'
if (-not (Test-Path -LiteralPath $py315)) { Write-Result 'STOP Python 3.15 없음'; exit 2 }

if (-not (Test-Path -LiteralPath $Backup)) {
  @{ Path = (Get-Raw 'Path'); QVEST_PY = (Get-Raw 'QVEST_PY'); QVEST_RSCRIPT = (Get-Raw 'QVEST_RSCRIPT'); at = (Get-Date -Format s) } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Backup -Encoding UTF8
}
$p = Get-Raw 'Path'
$parts = $p.value -split ';'
$new = foreach ($s in $parts) {
  $t = $s
  $t = $t -replace '(?i)\\R\\R-4\.5\.2\\bin', '\R\R-4.6.2\bin'
  $t = $t -replace '(?i)\\Python\\Python312\\Scripts', '\Python\Python315\Scripts'
  $t = $t -replace '(?i)\\Python\\Python312(\\?)$', '\Python\Python315$1'
  $t
}
$newPath = ($new -join ';')
Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value $newPath -Type $p.kind
Set-ItemProperty -Path 'HKCU:\Environment' -Name 'QVEST_PY' -Value $py315 -Type String
Set-ItemProperty -Path 'HKCU:\Environment' -Name 'QVEST_RSCRIPT' -Value 'C:\Program Files\R\R-4.6.2\bin\Rscript.exe' -Type String
Send-SettingChange
$chk = Get-Item 'HKCU:\Environment'
$pp = $chk.GetValue('Path', $null, 'DoNotExpandEnvironmentNames')
Write-Result ('OK · Path R={0} Py315={1} Py312={2} · QVEST_PY={3} · QVEST_RSCRIPT={4}' -f
  ($pp -match 'R-4\.6\.2\\bin'), ($pp -match 'Python315'), ($pp -match 'Python312'), $chk.GetValue('QVEST_PY'), $chk.GetValue('QVEST_RSCRIPT'))
exit 0
