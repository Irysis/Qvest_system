<#
install_r46_packages.ps1 — install_r46_packages.R 를 R 4.6.2 로 낮은 우선순위에서 돌린다(도구 세션 밖 · 일회용 예약 작업) · 2026-11-08
  결과 = .cache\installers\r46_packages.result.txt · R 출력 = r46_packages.log
#>
$ErrorActionPreference = 'Continue'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Dir = Join-Path $Root '.cache\installers'
$Rs = 'C:\Program Files\R\R-4.6.2\bin\Rscript.exe'
$R = Join-Path $PSScriptRoot 'install_r46_packages.R'
$Log = Join-Path $Dir 'r46_packages.log'
if (-not (Test-Path -LiteralPath $Rs)) { Add-Content (Join-Path $Dir 'r46_packages.result.txt') "STOP Rscript 4.6.2 없음" -Encoding UTF8; exit 2 }
cmd /c "start `"`" /belownormal /wait `"$Rs`" `"$R`" `"$Dir`" >> `"$Log`" 2>&1"
exit $LASTEXITCODE
