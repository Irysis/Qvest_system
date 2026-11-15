# kill_worker_test.ps1 — 폴백 경로 시험(작업자 사망): 새 판을 작업자 2개 · 캐시 없이 돌리다가 작업자 하나를 강제 종료한다.
#   기대: '[engine] exec: parallel run interrupted (…) - remaining months in main process' 뒤 남은 달을 주 프로세스가 순차로 돌고
#         산출이 구판과 같다(비교는 run_equivalence.R compare).
#   사용: powershell -NoProfile -File kill_worker_test.ps1 <run_equivalence.R> <inputs.rds> <out.rds> <log> <dates> [kill_after_s]
param([string]$Eq, [string]$Inputs, [string]$Out, [string]$Log, [string]$Dates, [int]$KillAfter = 8)
$env:RP_2407_WORKERS = "2"
$env:RP_2407_CACHE = "0"
$p = Start-Process -FilePath "Rscript" -ArgumentList @($Eq, "run", "new", "sr_opt", $Inputs, $Out, $Dates) `
     -RedirectStandardOutput $Log -RedirectStandardError ($Log + ".err") -PassThru -NoNewWindow
$port = $null
for ($i = 0; $i -lt 600 -and -not $port; $i++) {
  Start-Sleep -Milliseconds 500
  if (Test-Path $Log) {
    $m = Select-String -Path $Log -Pattern 'PSOCK workers \(port (\d+)\)' | Select-Object -First 1
    if ($m) { $port = $m.Matches[0].Groups[1].Value }
  }
}
if (-not $port) { Write-Output "no port line seen"; exit 2 }
Start-Sleep -Seconds $KillAfter
$w = Get-CimInstance Win32_Process -Filter "Name='Rscript.exe'" | Where-Object { $_.CommandLine -match ("PORT=" + $port + "\b") } | Select-Object -First 1
if (-not $w) { Write-Output "no worker found for port $port"; exit 3 }
Stop-Process -Id $w.ProcessId -Force
Write-Output ("killed worker pid {0} (port {1}) at +{2}s after cluster start" -f $w.ProcessId, $port, $KillAfter)
$p.WaitForExit()
Write-Output ("run exit code {0}" -f $p.ExitCode)
