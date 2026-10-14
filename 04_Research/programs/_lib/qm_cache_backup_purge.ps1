# .cache(= C:\qm_cache) 백업 영구 삭제 — 2026-10-14 도훈 "백업은 지워"
#   목록 = 같은 폴더 qm_cache_backup_purge_list_20261014.txt (102항목 · 약 45 GB)
#   목록 선정: 이름에 bak/backup/pre_ 가 든 최상위 항목 중 살아 있는 코드·검사가 경로로 쓰지 않는 것(superseded/ 는 cleaner 가 써서 제외).
#   지금 쓰는 데이터(RAWDATA.parquet · factor_db · factor_db_daily · pins 등)는 목록에 없다. 되돌릴 수 없다.
# 실행(도훈): powershell -ExecutionPolicy Bypass -File 04_Research\programs\_lib\qm_cache_backup_purge.ps1
$cache = 'C:\qm_cache'
$list  = Join-Path $PSScriptRoot 'qm_cache_backup_purge_list_20261014.txt'
$names = Get-Content $list -Encoding UTF8 | Where-Object { $_.Trim() -ne '' }
$keep  = @('RAWDATA.parquet', 'factor_db', 'factor_db_daily', 'pins', 'superseded')
$tot = 0; $n = 0
foreach ($nm in $names) {
  if ($keep -contains $nm) { Write-Host "건너뜀(보호): $nm"; continue }
  $p = Join-Path $cache $nm
  if (-not (Test-Path -LiteralPath $p)) { continue }
  $sz = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  if ((Get-Item -LiteralPath $p).PSIsContainer -eq $false) { $sz = (Get-Item -LiteralPath $p).Length }
  Remove-Item -LiteralPath $p -Recurse -Force
  $tot += $sz; $n += 1
}
"삭제 {0}항목 · {1:N1} GB 확보" -f $n, ($tot / 1GB)
