<#
install_r462_admin.ps1 — R 4.6.2 관리자 설치(C:\Program Files\R\R-4.6.2) · 2026-11-09 실행
  도훈 11-08 "관리자 설치(PC 앞)" · 계획서 = 같은 폴더 PLAN.md

- 보통 PowerShell(또는 일회용 예약 작업)에서 시작한다. 관리자가 아니면 스스로 UAC 를 띄운다 → 화면에서 [예](약 100초 안).
- 하는 일: 설치 파일 MD5(CRAN md5sum.R-4.6.2.txt) · 서명 대조 → 조용한 설치 → Rscript --version 확인
          → 결과 한 줄씩 .cache\installers\R-4.6.2-install.result.txt (Q 가 읽는다) · 설치 기록 = R-4.6.2-install.log
- R 4.5.2 는 지우지 않는다(되돌리기 · 하드코딩 경로는 판 해석기로 바꾸기 전까지 4.5.2 를 계속 쓴다).
- -DryRun: 대조와 명령만 기록하고 설치 · UAC 는 하지 않는다.
#>
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Dir = Join-Path $Root '.cache\installers'
$Inst = Join-Path $Dir 'R-4.6.2-win.exe'
$Md5Expected = 'd01b7413cce5540a35eaf8295ef32197'
$Target = 'C:\Program Files\R\R-4.6.2'
$Log = Join-Path $Dir 'R-4.6.2-install.log'
$Result = Join-Path $Dir 'R-4.6.2-install.result.txt'

function Write-Result([string]$Msg) {
  $line = '{0} [{1}] {2}' -f (Get-Date -Format s), $env:COMPUTERNAME, $Msg
  Add-Content -LiteralPath $Result -Value $line -Encoding UTF8
  Write-Host $line
}

if (-not (Test-Path -LiteralPath $Inst)) { Write-Result "STOP 설치 파일 없음: $Inst"; exit 2 }
$md5 = (Get-FileHash -LiteralPath $Inst -Algorithm MD5).Hash.ToLower()
if ($md5 -ne $Md5Expected) { Write-Result "STOP MD5 불일치: $md5 (기대 $Md5Expected)"; exit 3 }
$sig = Get-AuthenticodeSignature -LiteralPath $Inst
if ($sig.Status -ne 'Valid') { Write-Result "STOP 서명 상태 $($sig.Status)"; exit 3 }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
$instArgs = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-',
              '/MERGETASKS="!desktopicon,!quicklaunchicon"', "/DIR=`"$Target`"", "/LOG=`"$Log`"")

if ($DryRun) {
  Write-Result ('DRYRUN md5 OK · 서명 {0} · 관리자={1} · 이미 설치={2} · 명령: "{3}" {4}' -f
    ($sig.SignerCertificate.Subject -replace ',.*', ''), $isAdmin,
    (Test-Path -LiteralPath (Join-Path $Target 'bin\Rscript.exe')), $Inst, ($instArgs -join ' '))
  exit 0
}

if (-not $isAdmin) {
  Write-Result 'UAC 요청 — 화면의 사용자 계정 컨트롤에서 [예]'
  $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -PassThru -Wait `
         -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
  exit $p.ExitCode
}

$rs = Join-Path $Target 'bin\Rscript.exe'
if (Test-Path -LiteralPath $rs) { Write-Result "SKIP 이미 설치됨: $Target"; exit 0 }
Write-Result "설치 시작 → $Target"
$p = Start-Process -FilePath $Inst -ArgumentList $instArgs -Wait -PassThru
if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $rs)) {
  Write-Result ("FAIL exit={0} · Rscript 있음={1} · 기록 {2}" -f $p.ExitCode, (Test-Path -LiteralPath $rs), $Log); exit 1
}
$ver = (& $rs --version 2>&1 | Out-String).Trim() -replace '\s+', ' '
Write-Result "OK exit=0 · $ver"
exit 0
