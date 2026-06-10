# =============================================================================
# _lo_batch_oomfix.ps1 — long-only screen batch, OOM 근본 fix (2026-06-06)
# =============================================================================
#  ★ 도훈 mandate: short 전면 금지 → driver_lo_screen.R(long-only top25)만 사용.
#
#  ★ OOM 근본 원인(기존 _lo_batch_run.ps1):
#     - `$res = & $RS -e "..." 2>&1` : 자식 R의 stdout/stderr(55KB 로그 + arrow 경고)를
#       부모 PowerShell 세션이 *객체로 누적 캡처*. 26 factor면 수 MB + arrow 메모리맵
#       핸들이 부모 세션에 잔류 → factor_db arrow 연속 실행서 핸들/메모리 누적 → 2번째
#       run부터 비결정 segfault/OOM. call operator `&`는 완전 프로세스 격리도 약함.
#  ★ fix 3축(작업 명세):
#     (1) 각 factor = Start-Process -Wait (완전 새 프로세스, 완료까지 대기). 출력은
#         *파일로만* 리다이렉트(-RedirectStandardOutput/Error) → 부모 메모리 누적 0.
#         자식이 죽으면 .ExitCode로만 판정(출력 객체 안 받음).
#     (2) 다음 launch 전: [GC]::Collect() + WaitForPendingFinalizers() + 5초 sleep +
#         free RAM 확인(<30% free면 추가 대기 루프 — 최대 6회=30초).
#     (3) 5종 청크: 청크 경계마다 더 긴 정리(10초) + 청크 완주분 JSON 즉시 집계 출력.
#         한 factor가 2회(launch + retry) 모두 json 미생성이면 skip+기록 후 다음.
# =============================================================================
$ErrorActionPreference = 'Continue'
$env:CLAUDE_PROJECT_DIR = 'G:/Quant_Module_Moltbot'
$env:PYTHONUTF8 = '1'
$RS     = 'C:/Program Files/R/R-4.5.2/bin/Rscript.exe'
$DRIVER = 'G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/driver_lo_screen.R'
$LODIR  = 'G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/lo_screen'
$LOG    = Join-Path $LODIR '_batch_oomfix.log'
New-Item -ItemType Directory -Force -Path $LODIR | Out-Null

# 대상 26종 (CR01 완주 skip). 5종 청크.
$factors = @(
  'CR02_Volume_Concentration','CR03_Herding_Dispersion','CR04_Ownership_Concentration',
  'CR05_Short_Pressure_Proxy','CR06_DTC_Proxy','CR07_Momentum_Crowding',
  'CR08_Volume_Price_Divergence','CR09_Money_Flow_Ratio','CR10_Convergence_Premium',
  'CR11_Idiosyncratic_Return',
  'V10_FCF_Yield','V15_NetDebt_Adj_EP','V17_Payout_Ratio','V19_Debt_to_Market','V21_Composite_Equity_Issuance',
  'AC09_NNI','AC13_Abnormal_Accruals','AC24_NOA_Growth',
  'IN01_CapEx_to_Assets','IN02_CapEx_to_Revenue','IN05_Net_Debt_Issuance',
  'XF_DU02_AssetTurnover','XF_LL01_DebtToCapital','XF_PR05_EBITDA_to_Assets',
  'C16_EPS_Acceleration','C19_Composite_Earnings'
)
$CHUNK = 5

function Log($msg) {
  $line = "$(Get-Date -Format 'HH:mm:ss')  $msg"
  Write-Output $line
  $line | Out-File -FilePath $LOG -Append -Encoding utf8
}
function FreePctUsed() {
  $os = Get-CimInstance Win32_OperatingSystem
  [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/$os.TotalVisibleMemorySize)*100,1)
}
# GC + RAM 게이트: <30% free(=>70% used)면 추가 대기. 최대 6회(30초).
function CleanupGate([int]$baseSleep) {
  [System.GC]::Collect()
  [System.GC]::WaitForPendingFinalizers()
  [System.GC]::Collect()
  Start-Sleep -Seconds $baseSleep
  for ($g = 0; $g -lt 6; $g++) {
    $used = FreePctUsed
    if ($used -lt 70) { return $used }
    Log "  [RAM-WAIT] used=${used}% (>=70%, free<30%) wait 5s ($($g+1)/6)"
    [System.GC]::Collect(); Start-Sleep -Seconds 5
  }
  return (FreePctUsed)
}
# 단일 factor 1회 실행 = 완전 독립 프로세스, 출력은 파일로만(부모 메모리 누적 0)
function RunOne([string]$f, [string]$tag) {
  $env:FACTOR_NAME = $f
  $outR = Join-Path $LODIR ("_run_" + $f + "_" + $tag + ".out")
  $errR = Join-Path $LODIR ("_run_" + $f + "_" + $tag + ".err")
  $args = @('-e', "source('$DRIVER')")
  $p = Start-Process -FilePath $RS -ArgumentList $args -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $outR -RedirectStandardError $errR
  return $p.ExitCode
}

"=== LO OOM-fix batch start $(Get-Date -Format o) | $($factors.Count) factors | chunk=$CHUNK ===" | Out-File $LOG -Encoding utf8
Log "RAM used at start: $(FreePctUsed)%"
$done = New-Object System.Collections.ArrayList
$skip = New-Object System.Collections.ArrayList
$idx = 0
for ($c = 0; $c -lt $factors.Count; $c += $CHUNK) {
  $chunk = $factors[$c..([math]::Min($c+$CHUNK-1, $factors.Count-1))]
  Log "----- CHUNK $([int]($c/$CHUNK)+1) : $($chunk -join ', ') -----"
  foreach ($f in $chunk) {
    $idx++
    $outjson = Join-Path $LODIR "$f.json"
    if (Test-Path $outjson) { Log "[$idx/$($factors.Count)] SKIP $f (json exists)"; [void]$done.Add($f); continue }
    Log "[$idx/$($factors.Count)] START $f"
    $ec = RunOne $f 'a'
    if (-not (Test-Path $outjson)) {
      Log "  [retry] $f (1st died/no-json, exit=$ec). cleanup+retry"
      CleanupGate 5 | Out-Null
      $ec2 = RunOne $f 'b'
      if (-not (Test-Path $outjson)) {
        $tailErr = if (Test-Path (Join-Path $LODIR ("_run_"+$f+"_b.err"))) { (Get-Content (Join-Path $LODIR ("_run_"+$f+"_b.err")) -Tail 4 -ErrorAction SilentlyContinue) -join ' | ' } else { '' }
        Log "  [SKIP] $f 2회 모두 json 미생성(exit a=$ec b=$ec2). err: $tailErr"
        [void]$skip.Add($f)
        $cu = CleanupGate 5; Log "  cleaned, used=${cu}%"
        continue
      }
    }
    # 완주 — DONE 라인 추출(파일에서, 부모 메모리 누적 없음)
    $doneLine = if (Test-Path (Join-Path $LODIR ("_run_"+$f+"_a.out"))) { (Get-Content (Join-Path $LODIR ("_run_"+$f+"_a.out")) -ErrorAction SilentlyContinue | Select-String 'LO-DONE' | Select-Object -Last 1).Line } else { $null }
    if (-not $doneLine) { $doneLine = if (Test-Path (Join-Path $LODIR ("_run_"+$f+"_b.out"))) { (Get-Content (Join-Path $LODIR ("_run_"+$f+"_b.out")) -ErrorAction SilentlyContinue | Select-String 'LO-DONE' | Select-Object -Last 1).Line } else { $null } }
    Log "  [OK] $f$(if($doneLine){' '+$doneLine.Trim()})"
    [void]$done.Add($f)
    $cu = CleanupGate 5; Log "  cleaned, used=${cu}%"
  }
  # 청크 경계: 더 긴 정리 + 완주분 즉시 집계
  Log "  [CHUNK done] cleanup 10s"; CleanupGate 10 | Out-Null
}
Log "=== LO OOM-fix batch DONE $(Get-Date -Format o) | done=$($done.Count) skip=$($skip.Count) ==="
Log "DONE factors: $($done -join ', ')"
Log "SKIP factors: $($skip -join ', ')"
