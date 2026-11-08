<#
install_py3152_user.ps1 — Python 3.15.2 사용자 설치(%LOCALAPPDATA%\Programs\Python\Python315 · UAC 없음) · 2026-11-09 실행
  계획서 = 같은 폴더 PLAN.md · 지금 QVEST_PY(Python 3.12.10)와 같은 방식(사용자 설치)

- ★Claude 도구 세션에서 돌리면 %LOCALAPPDATA% 쓰기가 가상화돼 가짜 설치가 된다 → 일회용 예약 작업(Interactive · Limited)이나
  도훈이 연 보통 PowerShell 에서 돌린다.
- 하는 일: SHA-256(python.org API) · 서명 대조 → 조용한 설치(PATH · 파일 연결 · 바로가기 · py 런처 손대지 않음)
          → python --version · pip 확인 → 결과 .cache\installers\python-3.15.2-install.result.txt
- Python 3.12 는 지우지 않는다(예약 작업 16개의 런처 pythonw · 되돌리기). QVEST_PY 갱신은 다음 단계(계획서 3-2)에서 따로.
- -DryRun: 대조와 명령만 기록한다.
#>
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Dir = Join-Path $Root '.cache\installers'
$Inst = Join-Path $Dir 'python-3.15.2-amd64.exe'
$ShaExpected = '06e225a228191b0f4d1dcf6905fbb21bf9f6970d13a2ec63137ab9bee76f15aa'
$Target = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python315'
$Log = Join-Path $Dir 'python-3.15.2-install.log'
$Result = Join-Path $Dir 'python-3.15.2-install.result.txt'

function Write-Result([string]$Msg) {
  $line = '{0} [{1}] {2}' -f (Get-Date -Format s), $env:COMPUTERNAME, $Msg
  Add-Content -LiteralPath $Result -Value $line -Encoding UTF8
  Write-Host $line
}

if (-not (Test-Path -LiteralPath $Inst)) { Write-Result "STOP 설치 파일 없음: $Inst"; exit 2 }
$sha = (Get-FileHash -LiteralPath $Inst -Algorithm SHA256).Hash.ToLower()
if ($sha -ne $ShaExpected) { Write-Result "STOP SHA-256 불일치: $sha"; exit 3 }
$sig = Get-AuthenticodeSignature -LiteralPath $Inst
if ($sig.Status -ne 'Valid') { Write-Result "STOP 서명 상태 $($sig.Status)"; exit 3 }

$instArgs = @('/quiet', 'InstallAllUsers=0', "TargetDir=`"$Target`"", 'PrependPath=0', 'AssociateFiles=0',
              'Shortcuts=0', 'Include_launcher=0', 'Include_doc=0', 'Include_test=0', 'Include_pip=1',
              '/log', "`"$Log`"")
$py = Join-Path $Target 'python.exe'

if ($DryRun) {
  Write-Result ('DRYRUN sha256 OK · 서명 {0} · 대상 {1} · 이미 설치={2} · 명령: "{3}" {4}' -f
    ($sig.SignerCertificate.Subject -replace ',.*', ''), $Target, (Test-Path -LiteralPath $py), $Inst, ($instArgs -join ' '))
  exit 0
}

if (Test-Path -LiteralPath $py) { Write-Result "SKIP 이미 설치됨: $Target"; exit 0 }
Write-Result "설치 시작 → $Target"
$p = Start-Process -FilePath $Inst -ArgumentList $instArgs -Wait -PassThru
if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $py)) {
  Write-Result ("FAIL exit={0} · python.exe 있음={1} · 기록 {2}" -f $p.ExitCode, (Test-Path -LiteralPath $py), $Log); exit 1
}
$ver = (& $py --version 2>&1 | Out-String).Trim()
$pip = (& $py -m pip --version 2>&1 | Out-String).Trim() -replace '\s+', ' '
Write-Result "OK exit=0 · $ver · $pip"
exit 0
