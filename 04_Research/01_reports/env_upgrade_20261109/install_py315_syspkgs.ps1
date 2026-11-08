<#
install_py315_syspkgs.ps1 — 시스템 Python 3.15.2(%LOCALAPPDATA%\Programs\Python\Python315)에 QVEST_PY 용 패키지 설치 · 2026-11-08
  지금 QVEST_PY(3.12)에 있는 것과 같은 묶음: openpyxl · numpy · pypdf · jsonschema (+ 의존) — 최신판
  + pymupdf(11-08 2차 — 00_Lawbook/tools/pdf_check.py 가 QVEST_PY 로 돈다 · 메인은 3.12 때도 없어 PDF 생성이 검사 단계에서 멈췄다 · 노트북엔 있었다 ·
    스트레스 일보 make_daily_report.py 실측 'No module named pymupdf' → rc 1) — 휠만(--only-binary)
- ★도구 세션 밖에서(일회용 예약 작업 또는 보통 PowerShell) — %LOCALAPPDATA% 쓰기 가상화.
- ★PowerShell 5.1 함정: $ErrorActionPreference='Stop' 에서 외부 명령의 stderr 줄(pip 경고)이 치명 오류가 돼 중간에 끊긴다
  (11-08 1차 실행 — pip 자기 업그레이드 도중 중단 · ~ip 임시 폴더 잔존) → 외부 명령은 cmd /c 로 돌리고 출력은 cmd 가 넘긴다.
- 결과 = .cache\installers\py315_syspkgs.result.txt · pip 기록 = py315_syspkgs.log (UTF-8)
#>
$ErrorActionPreference = 'Continue'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Dir = Join-Path $Root '.cache\installers'
$PyDir = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python315'
$Py = Join-Path $PyDir 'python.exe'
$Log = Join-Path $Dir 'py315_syspkgs.log'
$Result = Join-Path $Dir 'py315_syspkgs.result.txt'
function Write-Result([string]$Msg) {
  $line = '{0} [{1}] {2}' -f (Get-Date -Format s), $env:COMPUTERNAME, $Msg
  Add-Content -LiteralPath $Result -Value $line -Encoding UTF8
}
if (-not (Test-Path -LiteralPath $Py)) { Write-Result "STOP Python 3.15 없음: $Py"; exit 2 }
$env:PYTHONUTF8 = '1'
# 1차 실행이 남긴 pip 임시 폴더(~ip · ~ip-x.dist-info) 정리 — 남겨 두면 pip 가 'invalid distribution' 경고를 계속 낸다
Get-ChildItem -LiteralPath (Join-Path $PyDir 'Lib\site-packages') -Directory -Filter '~*' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
cmd /c "`"$Py`" -m pip install --upgrade pip >> `"$Log`" 2>&1"
cmd /c "`"$Py`" -m pip install --upgrade openpyxl numpy pypdf jsonschema >> `"$Log`" 2>&1"
$rc = $LASTEXITCODE
cmd /c "`"$Py`" -m pip install --upgrade --only-binary=:all: pymupdf >> `"$Log`" 2>&1"
if ($LASTEXITCODE -ne 0) { $rc = $LASTEXITCODE }
$probe = cmd /c "`"$Py`" -c `"import sys, openpyxl, numpy, pypdf, jsonschema, pymupdf; print(sys.version.split()[0], 'openpyxl', openpyxl.__version__, 'numpy', numpy.__version__, 'pypdf', pypdf.__version__, 'pymupdf', pymupdf.__version__)`" 2>&1"
$left = @(Get-ChildItem -LiteralPath (Join-Path $PyDir 'Lib\site-packages') -Directory -Filter '~*' -ErrorAction SilentlyContinue).Count
Write-Result ("{0} rc={1} · {2} · ~임시폴더 {3}" -f $(if ($rc -eq 0) { 'OK' } else { 'FAIL' }), $rc, (($probe | Out-String).Trim()), $left)
exit $rc
