# ==============================================================================
#  qw_refresh.ps1 - QuantiWise incremental refresh with kick-resilient retry
#  (ASCII-only for PowerShell 5.1 encoding safety) - validated 2026-07-01
# ==============================================================================
#  Dohoon mandate: a shared-account user (DESKTOP-GDS22UE etc.) may re-login and
#  kill our session; keep re-logging in and re-running until refresh completes.
#
#  Architecture:
#    1) Per-file state (.cache/qw_refresh_state.json) -> only process pending (idempotent)
#    2) Fast files first (Benchmark, OHLCVS) -> preserve partial progress across kicks
#    3) DialogWatcher (background job): takeover MessageBox Yes(id=6) / kick OK(id=1) auto
#    4) Round loop: ensure login -> refresh pending -> on kick re-login -> until all done
#
#  Validated refresh core: hyperlink with ScreenTip "Quantiwise*" .Follow() (login required)
#    proof: Benchmark Last Update 18:29 -> 18:39 ; ribbon Book 05-15 -> 06-30
#  Validated headless login: leftmost ThunderRT6PictureBoxDC click + watcher Yes -> loggedIn
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File qw_refresh.ps1                 # all, retry to done
#    powershell ... -File qw_refresh.ps1 -Only Benchmark,OHLCVS
#    powershell ... -File qw_refresh.ps1 -MaxRounds 50
#    powershell ... -File qw_refresh.ps1 -WhatIf                             # dry-run (compute only)
# ==============================================================================
param(
  [string[]]$Only = @(),
  [int]$MaxRounds = 40,
  [switch]$SkipLogin,
  [switch]$WhatIf,
  # ★2026-11-06 구멍 복구용(04_Research/01_reports/quantiwise_data_expansion_20261106/PLAN.md §0 단계 0):
  #   "Name=YYYYMMDD" 목록 — 그 책의 B5(From)를 캐시 기준 대신 지정 날짜로 쓰고, 상태 · 캐시 '이미 완료' 판정을 건너뛰어 1회 다시 받는다.
  #   쓰임 = 책당 앵커 1개(F2) 때문에 뒤처진 시트가 남긴 구멍을 사람이 지정한 창으로 다시 받기. 무인 체인은 쓰지 않는다.
  [string[]]$FromOverride = @()
)
$ErrorActionPreference = "Continue"
$ROOT = "C:\Users\99922\OneDrive\Quant_Module_Moltbot"
$UNIV = Join-Path $ROOT "03_Universe"
$UPD  = Join-Path $UNIV "Update_File"
$PY   = Join-Path $ROOT ".venv_qvest_ml\Scripts\python.exe"
$STATE= Join-Path $ROOT ".cache\qw_refresh_state.json"
$QWEXE= "C:\WISEfn\Common\Bin\qwMain.exe"
$QWLAUNCH = "C:\WISEfn\Quantiwise\Quantiwise.exe"  # 런처 경유(qwMain.exe 직접실행은 즉시종료됨 - 실측)
# -File 로 넘어온 comma-list("A,B,C")를 배열로 정규화 (PowerShell -File array 파싱 quirk)
$Only = @($Only | ForEach-Object { "$_" -split ',' } | Where-Object { $_ -ne '' })
$FROM_OVR = @{}
foreach ($kv in @($FromOverride | ForEach-Object { "$_" -split ',' } | Where-Object { $_ -ne '' })) {
  $p = $kv -split '=', 2
  if ($p.Count -ne 2 -or $p[1] -notmatch '^\d{8}$') { Write-Host "[from-override] 형식 오류(Name=YYYYMMDD): $kv"; exit 2 }
  $FROM_OVR[$p[0]] = $p[1]
}

# ---- 책 -> 출력 표 (F2 · 2026-11-06 · PLAN §3.0 F2 · §3.3) -------------------------------------------------------------------
#  targets (fast -> slow). 책마다 B5(From) 앵커 = 그 책이 먹이는 출력 parquet **전부**의 Date max 중 가장 뒤처진 것 + 1일 = min(max)+1.
#  ★왜(실측 11-06 · PLAN §5.1): 구판은 책당 대표 parquet 1개(us_k200 · investor_all 전체 max · eps_1y)의 max+1 이었다. 대표가 앞서 있으면
#    뒤처진 시트를 건너뛰어 구멍이 남는다 — Universe_Support 는 us_k200 11-05 라 'cache already >= target' 로 받지 않았는데 us_sector_lv2 는 10-19,
#    Investor_Act 는 investor_all max 10-30 → B5=20261031 인데 개인 · 기타법인 10-19, Consensus 는 eps_1y 10-19 → B5=20261020 인데
#    coverage · esbr · escr · op_profit_fy1 10-16.
#  시트 -> 출력 매핑의 정본 = 적재기 파서(줄마다 출처). 파서와 이 표가 갈라지면(지표 추가 · 이름 변경) 앵커가 그 출력을 못 본다(구멍 은폐와
#    같은 부류) → 시험 08_Tests/data/test_qw_refresh_anchor.ps1 G축이 파서 · 적재기를 R · python 구문 분석기로 읽어 **값**(지표 · 시트 ·
#    투자자 유형 목록 · 출력 파일 이름)을 다시 뽑아 이 표와 대조한다(원문 모양 — 줄바꿈 · c()/list() · 대입 기호 — 에 묶이지 않는다 · 2차 11-06).
#  ★제안(이번 범위는 06_Registry 쓰기 금지라 미이행): 이 표를 PLAN §3.1 등록부(qw_updatefile_registry.json)로 옮겨 드라이버 · 적재기 ·
#    신선도 감사(F6)가 같은 목록을 읽게 한다. 그때까지는 이 함수가 단일 출처다.
#  anchor:  outputs = min(max)+1. 출력 하나라도 판단 불가(파일 없음 · 깨짐 · 행 0 · 그룹 행 0 · python 실패)면 keep = 통합문서에 남은 B5 를
#                     그대로 두고 받는다('이미 완료' 판정은 하지 않는다 — 모르는 채 done 으로 끝내지 않는다). ★keep 이 '더 많이 받는다'는
#                     보장은 아니다(남은 B5 = 직전에 쓴 값 · Get-BookAnchor 주석) — 처리 규칙은 결정 사항이라 WARN 줄로만 알린다.
#           qw_base = OHLCVS 전용(아래 OHLCVS 줄)
#  PIT: 앵커는 '어디서부터 다시 받나'만 정한다 — 날짜 의미 · 가용 규칙(소비자 Date < sig_date 등)은 바꾸지 않는다.
function New-QwBookTable([string]$root) {
  $c    = Join-Path $root ".cache"
  $univ = Join-Path $root "03_Universe"
  $upd  = Join-Path $univ "Update_File"
  # Universe_Support 8시트 -> .cache/universe_support/us_<cache_name>.parquet
  #   출처: parse_universe_support.R::UNIVERSE_SUPPORT_SHEET_META = us_update_stream_parse.py::SHEETS · 적재 incremental_update_file.R::incremental_universe_support
  $us = @(@('sector_lv1','sector_lv2','float','k200','kq150','trading_halt','admin_stock','unfaithful_disc') | ForEach-Object {
    @{ id = "us_$_"; path = (Join-Path $c "universe_support\us_$_.parquet") } })
  # Investor_Act 4시트(외인 · 기관 · 개인 · 기타법인) -> .cache/investor_stock/investor_all.parquet 의 InvestorType 그룹
  #   출처: incremental_update_file.R::incremental_investor sheet_map (investor_<type>.parquet · investor_wide 는 investor_all 에서 다시 만드는 파생이라 따로 보지 않는다)
  $inv = @(@('Foreign','Institutional','Individual','OtherCorp') | ForEach-Object {
    @{ id = "investor_all[$_]"; path = (Join-Path $c "investor_stock\investor_all.parquet"); group_col = "InvestorType"; group = $_ } })
  # Consensus 12시트 -> .cache/consensus/<metric>.parquet
  #   출처: consensus_parser.R::CONSENSUS_METRICS · 적재 incremental_update_file.R::.consensus_append_increment (ticker_map = 날짜 없는 종목명표라 제외)
  $cons = @(@('eps_1y','bps_1y','dps_1y','eps_chg_1m','eps_chg_3m','target_price','sue','revenue_fy1','escr','esbr','coverage','op_profit_fy1') | ForEach-Object {
    @{ id = $_; path = (Join-Path $c "consensus\$_.parquet") } })
  return @(
    # Benchmark - 출력 = benchmark.parquet 하나만 본다(구판과 같은 동작). indices.parquet 도 같은 시트에서 나오지만 일부러 넣지 않는다:
    #   Benchmark_price.xlsx 는 B5=19900103 전 이력 질의서이고 build_index_cache.py 가 그 통합문서 **전체**로 indices.parquet 를 통째로 다시 쓴다
    #   (benchmark.parquet 만 격자 보존). 앵커가 B5 를 증분 날짜로 바꾸면 통합문서에 증분만 남아 다음 [1pre] 재생성에서 indices 이력이 잘린다.
    #   목표일 = benchmark 최신일(Get-Target)이라 이 책은 언제나 'done' 으로 끝나 B5 를 쓰지 않는다(정본 수급 = daily_refresh.sh [1pre] quantiwise_fetch.py).
    @{ name="Benchmark";        path=(Join-Path $univ "Benchmark_price.xlsx");       anchor="outputs"; outputs=@(@{ id="benchmark"; path=(Join-Path $c "benchmark.parquet") }) }
    # OHLCVS - anchor=qw_base: B5 = Get-QwBaseNext(base OHLCVS.xlsx 마지막 거래일 + 1). 조정 주가라 update 창 전체를 매일 다시 받는 설계 —
    #   구 '기존 From 유지'가 base(~03-27)/update(04-30~) 이음매 구멍을 만들어 2026-04 rawdata 소실 사고 유발(incident 20260711). '이미 완료' 판정 없음(구판 cache=null 과 같음).
    @{ name="OHLCVS";           path=(Join-Path $upd "OHLCVS_update.xlsx");           anchor="qw_base"; outputs=@() }
    # Universe_Support - (2026-07-25 D1) B5 기준을 이 xlsx 가 실제 먹이는 us_* 패널로 정렬 · 구 universe.parquet(KRX 일간층, max 가 us_* 보다 앞섬) 기준은
    #   us_* 종점을 건너뛰어 월말 스냅샷 구멍을 냈다(incident 20260711 동형 · 07-01 런 B5=20260603 → 2026-04/05 월말 부재). F2 = 그 us_* 8개 전부.
    @{ name="Universe_Support"; path=(Join-Path $upd "Universe_Support_update.xlsx"); anchor="outputs"; outputs=$us }
    @{ name="Investor_Act";     path=(Join-Path $upd "Investor_Act_update.xlsx");     anchor="outputs"; outputs=$inv }
    @{ name="Consensus";        path=(Join-Path $upd "Consensus_update.xlsx");        anchor="outputs"; outputs=$cons }
  )
}
$FILES = @(New-QwBookTable $ROOT)

Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;using System.Collections.Generic;
public class Win{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumWindowsProc cb, IntPtr l);
 public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int ht,bool r);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint d,IntPtr e);
 [StructLayout(LayoutKind.Sequential)] public struct RECT{public int L,T,R,B;}
 public static string Txt(IntPtr h){var s=new StringBuilder(256);GetWindowText(h,s,256);return s.ToString();}
 public static string Cls(IntPtr h){var s=new StringBuilder(256);GetClassName(h,s,256);return s.ToString();}
 public static List<IntPtr> Wins(uint pid){var r=new List<IntPtr>();EnumWindows((h,l)=>{uint q;GetWindowThreadProcessId(h,out q);if(q==pid)r.Add(h);return true;},IntPtr.Zero);return r;}
 public static List<IntPtr> Kids(IntPtr p){var r=new List<IntPtr>();EnumChildWindows(p,(h,l)=>{r.Add(h);return true;},IntPtr.Zero);return r;}
 public static void Click(IntPtr h){RECT r;GetWindowRect(h,out r);int x=(r.L+r.R)/2,y=(r.T+r.B)/2;SetForegroundWindow(h);SetCursorPos(x,y);System.Threading.Thread.Sleep(120);mouse_event(0x2,0,0,0,IntPtr.Zero);System.Threading.Thread.Sleep(60);mouse_event(0x4,0,0,0,IntPtr.Zero);}
 public static int LeftOf(IntPtr h){RECT r;GetWindowRect(h,out r);return r.L;}
}
"@

# ---- DialogWatcher: standard MessageBox control-id click (Yes=6 takeover / OK=1 kick) ----
function Start-DialogWatcher {
  Stop-DialogWatcher
  Start-Job -Name QWDlg -ScriptBlock {
    Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class WD{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
 public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h,int id);
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 public static string Txt(IntPtr h){var s=new StringBuilder(256);GetWindowText(h,s,256);return s.ToString();}
}
"@
    $BM=[uint32]0xF5
    while ($true) {
      [WD]::EnumWindows({ param($h,$l)
        if ([WD]::Txt($h) -like "*Quantiwise7*") {
          $yes=[WD]::GetDlgItem($h,6)          # IDYES  (takeover: proceed)
          if ($yes -ne [IntPtr]::Zero) { [WD]::SendMessage($yes,$BM,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null }
          else { $ok=[WD]::GetDlgItem($h,1)     # IDOK   (kick notice: dismiss)
                 if ($ok -ne [IntPtr]::Zero) { [WD]::SendMessage($ok,$BM,[IntPtr]::Zero,[IntPtr]::Zero)|Out-Null } }
        }
        return $true
      }, [IntPtr]::Zero) | Out-Null
      Start-Sleep -Milliseconds 350
    }
  } | Out-Null
}
function Stop-DialogWatcher { Get-Job -Name QWDlg -EA SilentlyContinue | Stop-Job -EA SilentlyContinue; Get-Job -Name QWDlg -EA SilentlyContinue | Remove-Job -Force -EA SilentlyContinue }

# ---- state (idempotent) ----
function Load-State { $h=@{}; if (Test-Path $STATE) { try { $o=Get-Content $STATE -Raw | ConvertFrom-Json; foreach($p in $o.psobject.Properties){ $h[$p.Name]=$p.Value } } catch {} }; return $h }
function Save-State($s) {
  # HYG-05 guard (2026-07-03): past runs dropped state into repo ROOT with a
  # stringified-hashtable filename (e.g. 'System.Collections.Hashtable') when the
  # path variable did not resolve to the .json path. Enforce literal .json path
  # under $ROOT\.cache and ensure the directory exists before writing.
  $path = "$STATE"
  if (-not $path -or $path -notlike "*.json") { $path = Join-Path $ROOT ".cache\qw_refresh_state.json" }
  $dir = Split-Path -Parent $path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  ($s | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $path -Encoding UTF8
}
function Is-Done($state,$name,$target) { return ($state.ContainsKey($name) -and "$($state[$name].ymd)" -eq "$target") }
function Mark-Done($state,$name,$target) { $state[$name]=@{ ymd="$target"; ts=(Get-Date -Format s) }; Save-State $state }

# ---- dates ----
function Get-Target {
  # ★(2026-10-17 · 결정 RAWDATA-QW-ONLY-20261017 · BENCHMARK-QW-ONLY-20261017) 목표일 = 거래일 캘린더 정본(.cache/benchmark.parquet)의 최신일.
  #   벤치는 daily_refresh.sh [1pre] 가 이 수급보다 먼저 퀀티 정본(Benchmark_price.xlsx · CPD-1TD)으로 갱신한다.
  #   구판은 RAWDATA 최신일이었다 — 네이버 T+0 가 밤마다 RAWDATA 에 새 날짜를 먼저 붙여 줘서 목표가 전진했는데, 퀀티 단일(네이버 퇴역)에서는
  #   'RAWDATA 최신일 = 이미 받은 날'이라 퀀티가 새 날짜를 영영 받지 않는 순환이 된다. 벤치 판독 불능이면 구판(RAWDATA 최신일), 둘 다 불능이면 어제.
  foreach ($f in 'benchmark.parquet', 'RAWDATA.parquet') {
    $p = Join-Path $ROOT ".cache\$f"
    if (-not (Test-Path $p)) { continue }
    $code="import pyarrow.parquet as pq,pandas as pd" + [char]10 + "print(pd.to_datetime(pq.read_table(r'$p',columns=['Date']).to_pandas()['Date']).max().strftime('%Y%m%d'))"
    try { $r=(& $PY -c $code 2>$null); $r="$r".Trim(); if ($r -match '^\d{8}$') { return $r } } catch {}
  }
  return (Get-Date).AddDays(-1).ToString("yyyyMMdd")
}
function Get-QwBaseNext {
  # OHLCVS_update B5 = base OHLCVS.xlsx 마지막 거래일 + 1 (2026-07-11 incident fix).
  # trading_calendar.parquet의 source=='quantiwise' max = base xlsx 날짜열 max (동치).
  # 구 동작(B5 미설정 = 파일의 기존 From 유지)은 base와 update 사이 커버리지 구멍을
  # 방치 — 2026-03-30~04-29가 양쪽 어디에도 없어 rawdata 한 달 소실로 이어짐.
  # 실패 시 null 반환 = 구 동작 fallback (기존 From 유지).
  $cal = Join-Path $ROOT ".cache\trading_calendar.parquet"
  if (-not (Test-Path $cal)) { return $null }
  $code="import pyarrow.parquet as pq,pandas as pd" + [char]10 + "t=pq.read_table(r'$cal').to_pandas()" + [char]10 + "print((pd.to_datetime(t.loc[t['source']=='quantiwise','Date']).max()+pd.Timedelta(days=1)).strftime('%Y%m%d'))"
  try { $r=(& $PY -c $code 2>$null); $r="$r".Trim(); if ($r -match '^\d{8}$') { return $r } else { return $null } } catch { return $null }
}

# ---- anchor (F2 · 2026-11-06) : 출력 전부의 min(max)+1 ----------------------------------------------------------------------
#  Excel · 단말 없이 떼어 시험할 수 있게 함수로 둔다(08_Tests/data/test_qw_refresh_anchor.ps1 이 AST 로 이 함수들만 꺼내 모래상자 parquet 로 돌린다).
function Get-OutputMaxes($outputs) {
  # 출력마다 Date 열의 max 를 python 한 번으로 읽는다(그룹 출력 = 그 그룹 행만 · 같은 (파일, 그룹 열)은 한 번만 읽는다).
  # 반환 = 출력 순서대로 [pscustomobject]@{ id; ymd; status; rg } · status = ok | missing | empty | error:<예외> | no_result
  #   rg = 그룹 출력의 행 그룹 판독 수 '<파일> 읽음/전체'(로그 · 시험용) · 그 밖 = $null
  #   ★판독 실패를 '그 출력 없음'으로 접지 않는다 — 접으면 남은 출력만으로 min 을 잡아 뒤처진 출력을 다시 숨긴다(이 수리가 막는 그 병).
  #     python 이 죽으면(인터프리터 부재 · import 실패) 결과 줄이 없다 → no_result(판단 불가) → Get-BookAnchor 가 keep — 'done' 으로 새지 않는다.
  #   ★그룹 판독(grp_max · 2차 2026-11-06): parquet 행 그룹(row group)을 **뒤에서부터 하나씩** 읽고, 메타데이터 통계의 Date max 가 요청 그룹
  #     **전부**의 지금까지 max 이하인 행 그룹은 건너뛴다 — 그 행 그룹의 어떤 행도 어느 요청 그룹의 max 를 올릴 수 없다(파일 정렬 순서와
  #     무관하게 성립 · 통계가 없거나 못 읽으면 읽는다). 비교는 결과와 같은 날짜 단위(YYYYMMDD)다.
  #     통계가 틀려도 방향이 안전하다 — max 를 작게 적은 통계면 행 그룹을 건너뛰어 그 그룹 max 를 낮게 본다 → B5 가 앞당겨져 더 받는다
  #     (done 으로 새거나 구멍을 숨기지 않는다) · 크게 적은 통계면 더 읽을 뿐이다.
  #     왜: 구판은 investor_all(32.5M행 · 행 그룹 31개 · 날짜순)의 Date · InvestorType 을 통째로 읽었다 — 실측 11-06(python 판독 · 기동 제외)
  #     0.80초 · 최대 작업 집합 786MB(Excel 수급과 같은 시각에 돈다). 신판은 마지막 행 그룹 1개(약 1M행)만 읽는다 — 0.46초 · 129MB
  #     (드라이버 호출 전체 1.28 → 0.81초) · 운영 .cache 4책 판독 결과 구판과 동일
  #     (전량 판독과 같음은 시험 08_Tests/data/test_qw_refresh_anchor.ps1 P축이 행 그룹 여럿 · 날짜 뒤섞임 · 통계 없음 · 시각형 · 결측 자료로 고정).
  $outs = @($outputs)
  $res = @{}; $rgs = @{}
  if ($outs.Count -gt 0) {
    $argv = @($outs | ForEach-Object { "{0}|{1}|{2}|{3}" -f $_.id, $_.path, $_.group_col, $_.group })
    $code = @(
      "import sys, os, datetime",
      "import pyarrow.parquet as pq, pyarrow.compute as pc",
      "def ymd(v):",
      "    if v is None: return None",
      "    if isinstance(v, datetime.date): return v.strftime('%Y%m%d')",
      "    return datetime.date.fromisoformat(str(v)[:10]).strftime('%Y%m%d')",
      "def grp_max(p, gc, want):",
      "    pf = pq.ParquetFile(p)",
      "    nm = pf.schema_arrow.names",
      "    if 'Date' not in nm or gc not in nm: raise KeyError('Date/' + gc)",
      "    md = pf.metadata",
      "    di = [j for j in range(md.num_columns) if md.schema.column(j).path == 'Date'][0]",
      "    cur = {}",
      "    nread = 0",
      "    for r in range(md.num_row_groups - 1, -1, -1):",
      "        try:",
      "            st = md.row_group(r).column(di).statistics",
      "            rmax = ymd(st.max) if (st is not None and st.has_min_max) else None",
      "        except Exception:",
      "            rmax = None",
      "        if rmax is not None and all(g in cur and rmax <= cur[g][0] for g in want): continue",
      "        t = pf.read_row_group(r, columns=['Date', gc])",
      "        nread += 1",
      "        agg = t.group_by(gc).aggregate([('Date', 'max')])",
      "        for k, v in zip(agg.column(gc).to_pylist(), agg.column('Date_max').to_pylist()):",
      "            if k in want and v is not None:",
      "                y = ymd(v)",
      "                if k not in cur or y > cur[k][0]: cur[k] = (y, v)",
      "    return dict((k, cur[k][1]) for k in cur), nread, md.num_row_groups",
      "want = {}",
      "for a in sys.argv[1:]:",
      "    i, p, gc, g = a.split('|', 3)",
      "    if gc: want.setdefault((p, gc), set()).add(g)",
      "grp = {}",
      "for a in sys.argv[1:]:",
      "    i, p, gc, g = a.split('|', 3)",
      "    try:",
      "        if not os.path.isfile(p):",
      "            print(i + chr(9) + 'missing'); continue",
      "        if gc:",
      "            if (p, gc) not in grp:",
      "                try: grp[(p, gc)] = grp_max(p, gc, want[(p, gc)])",
      "                except Exception as e: grp[(p, gc)] = e",
      "            r = grp[(p, gc)]",
      "            if isinstance(r, Exception): raise r",
      "            v = r[0].get(g)",
      "        else:",
      "            v = pc.max(pq.read_table(p, columns=['Date']).column('Date')).as_py()",
      "        d = ymd(v)",
      "        print(i + chr(9) + ('ok' + chr(9) + d if d else 'empty'))",
      "    except Exception as e:",
      "        print(i + chr(9) + 'error' + chr(9) + type(e).__name__)",
      "for (p, gc), r in grp.items():",
      "    if not isinstance(r, Exception): print('#rg' + chr(9) + p + '|' + gc + chr(9) + '%d/%d' % (r[1], r[2]))"
    ) -join [char]10
    try {
      foreach ($ln in @(& $PY -c $code $argv 2>$null)) {
        $p = "$ln".Trim() -split [char]9
        if ($p.Count -ge 3 -and $p[0] -eq '#rg') { $rgs[$p[1]] = $p[2]; continue }
        if ($p.Count -ge 2) { $res[$p[0]] = @{ status = $p[1]; val = $(if ($p.Count -ge 3) { $p[2] } else { $null }) } }
      }
    } catch {}
  }
  return @($outs | ForEach-Object {
    $r = $res[$_.id]
    $rg = $null
    if ($_.group_col) { $n = $rgs["$($_.path)|$($_.group_col)"]; if ($n) { $rg = "{0} {1}" -f (Split-Path -Leaf $_.path), $n } }
    if (-not $r) { [pscustomobject]@{ id = $_.id; ymd = $null; status = 'no_result'; rg = $rg } }
    elseif ($r.status -eq 'ok' -and "$($r.val)" -match '^\d{8}$') { [pscustomobject]@{ id = $_.id; ymd = "$($r.val)"; status = 'ok'; rg = $rg } }
    elseif ($r.status -eq 'ok') { [pscustomobject]@{ id = $_.id; ymd = $null; status = "error:bad_date($($r.val))"; rg = $rg } }
    else { [pscustomobject]@{ id = $_.id; ymd = $null; status = $(if ($r.val) { "$($r.status):$($r.val)" } else { "$($r.status)" }); rg = $rg } }
  })
}
function Add-OneDay([string]$ymd) {
  # 달력일 +1 (구판 Get-CacheNext 의 pd.Timedelta(days=1) 와 같은 규약 — B5 가 비거래일이어도 받는다:
  #   실측 11-06 Investor_Act B5=20261031(토) 수급이 완료 기록됐다 · .cache/qw_refresh_state.json 10:14:02)
  return [datetime]::ParseExact($ymd, 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture).AddDays(1).ToString('yyyyMMdd')
}
function Get-BookAnchor($f, $target) {
  # 반환 [pscustomobject]@{ mode; b5; detail; warn }
  #   mode = b5   -> 통합문서 B5 를 b5 로 쓰고 받는다
  #          keep -> B5 를 건드리지 않고 받는다 = 통합문서에 남은 값(직전에 이 드라이버 · 사람이 쓴 B5). ★'더 많이 받는다'는 보장이 아니다 —
  #                  남은 B5 가 판단 불가 출력의 max 보다 뒤면 그 출력 구멍을 덮지 못하고, 표에 새 출력을 넣었는데 적재기가 그 parquet 를
  #                  아직 만들지 않으면 영구 keep(done 없음 · 매 라운드 수급)이다. 처리 규칙은 결정 사항(2차 보고) — 지금은 WARN 줄로만 알린다.
  #          done -> 모든 출력이 목표일에 닿았다(min(max)+1 > target) -> 받지 않는다. ★'done' 은 모든 출력이 ok 일 때만 나온다.
  #   warn = '' 또는 WARN 줄 본문(ASCII · Refresh-One 이 출력) — 뒤처진 출력이 앵커를 붙잡은 날(b5 + lagging) · keep.
  #          ★창 상한은 없다(낡은 출력 하나가 B5 를 끝없이 뒤로 밀 수 있다) — 상한 · 바닥은 근거와 함께 정할 결정 사항이라 숫자를 박지 않았다.
  if ($f.anchor -eq 'qw_base') {
    $b = Get-QwBaseNext
    if ($b) { return [pscustomobject]@{ mode = 'b5'; b5 = $b; detail = "qw_base next=$b (base xlsx max+1 - whole update window by design)"; warn = '' } }
    return [pscustomobject]@{ mode = 'keep'; b5 = $null; detail = "qw_base unreadable -> keep existing B5"; warn = 'anchor keep - workbook B5 left as its previous value (not guaranteed to cover the gap; decision pending PLAN 3.0 F2)' }
  }
  if ($f.anchor -ne 'outputs') { return [pscustomobject]@{ mode = 'keep'; b5 = $null; detail = "anchor '$($f.anchor)' unknown -> keep existing B5"; warn = 'anchor keep - unknown anchor kind' } }
  $rows = @(Get-OutputMaxes $f.outputs)
  $okRows = @($rows | Where-Object { $_.status -eq 'ok' })
  $bad = @($rows | Where-Object { $_.status -ne 'ok' })
  if ($bad.Count -gt 0 -or $okRows.Count -eq 0) {
    $why = if ($rows.Count -eq 0) { 'no outputs registered' } else { "unresolved outputs {0}/{1}: {2}" -f $bad.Count, $rows.Count, (($bad | ForEach-Object { "$($_.id)=$($_.status)" }) -join ' ') }
    return [pscustomobject]@{ mode = 'keep'; b5 = $null; detail = "$why -> keep existing B5, no done-check"
                              warn = 'anchor keep - workbook B5 left as its previous value; it may not cover the unresolved outputs (decision pending PLAN 3.0 F2)' }
  }
  $sorted = @($okRows | Sort-Object ymd)
  $lo = $sorted | Select-Object -First 1
  $hi = $sorted | Select-Object -Last 1
  $b5 = Add-OneDay $lo.ymd
  $lag = @($okRows | Where-Object { $_.ymd -lt $hi.ymd })
  $lagTxt = if ($lag.Count -gt 0) { ($lag | ForEach-Object { "$($_.id)=$($_.ymd)" }) -join ',' } else { 'none' }
  $detail = "outputs n={0} min={1} max={2} lagging=[{3}] -> next={4}" -f $okRows.Count, $lo.ymd, $hi.ymd, $lagTxt, $b5
  $rgTxt = @(@($rows | Where-Object { $_.rg } | ForEach-Object { $_.rg }) | Select-Object -Unique)
  if ($rgTxt.Count -gt 0) { $detail += (" rowgroups_read=[{0}]" -f ($rgTxt -join ',')) }
  if ([long]$b5 -gt [long]$target) { return [pscustomobject]@{ mode = 'done'; b5 = $b5; detail = $detail; warn = '' } }
  $warn = ''
  $held = ($lag.Count -gt 0)   # 뒤처진 출력이 앵커를 붙잡았다(평소엔 책의 모든 출력 max 가 같은 날이다)
  if ($held) {
    # 창 = B5 ~ 목표일 달력일 수(Add-OneDay 와 같은 달력일 규약) — 경고 문턱은 두지 않는다(뒤처진 출력이 있으면 언제나 낸다)
    $ci = [Globalization.CultureInfo]::InvariantCulture
    $win = ([datetime]::ParseExact("$target", 'yyyyMMdd', $ci) - [datetime]::ParseExact($b5, 'yyyyMMdd', $ci)).Days + 1
    $warn = "anchor held back by lagging outputs [{0}] - window {1}d (B5 {2} .. target {3}); no window cap (decision pending PLAN 3.0 F2)" -f $lagTxt, $win, $b5, $target
  }
  return [pscustomobject]@{ mode = 'b5'; b5 = $b5; detail = $detail; warn = $warn }
}
#  TODO(F2 권장안 · 이번 수리 범위 밖 — PLAN §3.0 F2): 앵커 = '최근 L 거래일 안의 첫 채움 미달일, 없으면 min(max)+1'.
#    min(max)+1 은 뒤로 처진(trailing) 출력만 본다 — 뒤 날짜가 이미 찬 **내부 구멍**(11-06 수급 개인 · 기타법인 10-20~10-30 · 컨센서스
#    4지표 10-19 가 다음 적재로 덮인 뒤)은 max 기반 앵커로는 영영 안 보인다. 권장안에 필요한 근거(지금은 없어 숫자를 박지 않았다):
#      ① L(되돌아볼 거래일 수) — 출력별 공표 지연 · 부분 수급 재발 간격의 실측 분포에서 산출해 등록부에 근거와 함께 둔다
#      ② '채움 미달' = 날짜별 채움 수 / 직전 W 거래일 중앙값 < 문턱 — W · 문턱은 항목 이력의 하위 분위에서 산출(F4 적재 관문과 같은 함수로)
#      ③ 거래일 목록 = .cache/trading_calendar.parquet 읽기만(달력 재빌드와 경합 금지) · 공매도 금지 기간처럼 기대 채움 0 인 구간의 예외 표(PLAN §3.5)
#      ④ 적재기가 '받은 창의 날짜 = 교체'여야 효과가 난다 — F3(2026-11-06 · incremental_update_file.R)로 수급(incremental_investor) ·
#         컨센서스(.consensus_append_increment · 지표별 창) · 유니버스(incremental_universe_support)가 모두 받은 창의 날짜를 교체한다
#         (구판 수급 · 컨센서스는 'Date > base_max' 라 앵커가 당겨 받은 앞 날짜와 -FromOverride 복구 창을 버렸다). 그래서 이 앵커 · 복구 수급이
#         실제로 구멍을 메운다. 남은 한계 = 위의 내부 구멍(max 기반 앵커는 못 본다)과 창 상한 없음(Get-BookAnchor 주석 · 결정 사항).

# ---- session ----
function QW-Alive {
  $p = Get-Process qwMain -EA SilentlyContinue
  if (-not $p) { return $false }
  foreach ($h in [Win]::Wins([uint32]$p.Id)) { $t=[Win]::Txt($h); if ($t -like "*Quantiwise7*" -and $t -notlike "*Login*") { return $true } }
  return $false
}
function Ensure-Login {
  if (QW-Alive) { return $true }
  Write-Host "[login] no session -> launching + login"
  Get-Process qwMain -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
  Start-Sleep 1
  Start-Process $QWLAUNCH -EA SilentlyContinue
  Start-Sleep 8
  $p = Get-Process qwMain -EA SilentlyContinue
  if ($p) {
    foreach ($h in [Win]::Wins([uint32]$p.Id)) {
      if ([Win]::Txt($h) -like "*Login*") {
        [Win]::ShowWindow($h,9)|Out-Null; [Win]::MoveWindow($h,150,150,430,330,$true)|Out-Null; [Win]::SetForegroundWindow($h)|Out-Null
        Start-Sleep 1
        $pics=@()
        foreach ($k in [Win]::Kids($h)) { if ([Win]::Cls($k) -eq "ThunderRT6PictureBoxDC") { $pics += [pscustomobject]@{ h=$k; L=[Win]::LeftOf($k) } } }
        $login = ($pics | Sort-Object L | Select-Object -First 1).h
        if ($login) { [Win]::Click([IntPtr]$login); Write-Host "[login] clicked LOGIN (leftmost PictureBox)" } else { Write-Host "[login] LOGIN PictureBox not found" }
      }
    }
  }
  Start-Sleep 9    # watcher auto-confirms takeover Yes
  return (QW-Alive)
}

# ---- refresh one file -> ok | kicked | skip | err ----
function Refresh-One($f,$target) {
  if (-not (Test-Path $f.path)) { Write-Host "[$($f.name)] missing, skip"; return "skip" }
  ## ★F2(2026-11-06): B5 앵커 = 책이 먹이는 출력 전부의 min(max)+1 (Get-BookAnchor · OHLCVS 는 qw_base = 이음매 구멍 방지 incident 20260711).
  ##   'cache already >= target -> done' 도 모든 출력 기준이고, 출력 하나라도 판단 불가면 done 대신 keep(기존 B5)으로 받는다.
  $a = Get-BookAnchor $f $target
  Write-Host "[$($f.name)] anchor $($a.mode): $($a.detail)"
  if ($a.warn) { Write-Host "[$($f.name)] WARN $($a.warn)" }   # 2차(11-06): 뒤처진 출력이 앵커를 붙잡음 · keep — 창 상한은 결정 사항(Get-BookAnchor 주석)
  $b5 = $a.b5
  if ($FROM_OVR.ContainsKey($f.name)) {
    Write-Host "[$($f.name)] from-override B5=$($FROM_OVR[$f.name]) (앵커 $($a.mode) $($a.b5) 대신 · 구멍 복구 1회)"
    $b5 = $FROM_OVR[$f.name]
  } elseif ($a.mode -eq 'done') { Write-Host "[$($f.name)] cache already >= target (all outputs: next $($a.b5) > $target) -> done"; return "ok" }
  Write-Host ("[{0}] refresh start (B5={1} B6=CPD-1TD) {2}" -f $f.name, $(if($b5){$b5}else{'keep'}), (Get-Date -Format HH:mm:ss))
  if ($WhatIf) { return "skip" }
  $xl=$null; $wb=$null; $result="err"
  try {
    $xl = New-Object -ComObject Excel.Application
    $xl.Visible=$true; $xl.DisplayAlerts=$false; $xl.EnableEvents=$true; $xl.AskToUpdateLinks=$false
    $wb = $xl.Workbooks.Open($f.path)
    foreach ($ws in $wb.Worksheets) {
      $ws.Activate()
      if ($b5 -and ("$($ws.Range('A5').Value2)" -like "Period*From*")) { $ws.Range("B5").Value2 = [double]$b5 }
      if ("$($ws.Range('A6').Value2)" -like "Period*To*") { $ws.Range("B6").Value2 = "CPD-1TD" }
      foreach ($h in $ws.Hyperlinks) { if ($h.ScreenTip -like "Quantiwise*") { $h.Follow() } }
    }
    Start-Sleep -Seconds 6
    if (-not (QW-Alive)) { Write-Host "[$($f.name)] session kicked"; $result="kicked" }
    else {
      # Completion = EVERY query sheet's resolved Period(To) (B6 bracket) >= target.
      #   (2026-09-19 fix) old check = sheet1 bracket == target. After midnight / before RAWDATA
      #   is appended, CPD-1TD resolves one day past target (e.g. [20260918] vs 20260917) and the
      #   old check looped 'target not reached' forever. It also ignored sheets 2..N of multi-sheet
      #   books (Consensus 12, Investor 4) - a sheet that failed mid-book was never seen.
      $b6 = ""; $ok = $true; $nq = 0
      foreach ($ws2 in $wb.Worksheets) {
        if ("$($ws2.Range('A6').Value2)" -like "Period*To*") {
          $nq++
          $t6 = "$($ws2.Range('B6').Value2)"
          if (-not $b6) { $b6 = $t6 }
          if ($t6 -match '\[(\d{8})\]') { if ([long]$Matches[1] -lt [long]$target) { $ok = $false; Write-Host "[$($f.name)] sheet '$($ws2.Name)' To=$t6 < $target" } }
          else { $ok = $false; Write-Host "[$($f.name)] sheet '$($ws2.Name)' To unresolved: $t6" }
        }
      }
      if ($nq -eq 0) { $ok = $false }
      $wb.Save()
      $b1 = "$($wb.Worksheets.Item(1).Range('B1').Value2)"
      if ($ok) { Write-Host "[$($f.name)] OK -> $b6 / $b1"; $result="ok" }
      else { Write-Host "[$($f.name)] target $target not reached: $b6 -> retry"; $result="err" }
    }
  } catch {
    Write-Host "[$($f.name)] exception: $($_.Exception.Message)"
    if (-not (QW-Alive)) { $result="kicked" } else { $result="err" }
  } finally {
    if ($wb) { try { $wb.Close($true) } catch {} }
    if ($xl) { try { $xl.Quit() } catch {}; [Runtime.InteropServices.Marshal]::ReleaseComObject($xl)|Out-Null }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
  }
  return $result
}

# ---- 사전 점검: 자동 로그인 자격이 실제로 저장돼 있는가 (2026-08-29 신설) ----
#   ★왜 필요한가 (실사고 2026-08-29): Ensure-Login 은 **LOGIN 버튼을 클릭만** 한다 —
#     ID/PW 는 앱이 기억한다는 전제다. 그런데 maincfg.ini [LOGIN] SAVEUSERPW 가 0 이면
#     실행할 때마다 PW 칸이 **빈 채로** 뜨고, 클릭은 매번 실패한다.
#     구판은 그 조건을 못 읽어 **40라운드를 빈 비밀번호로 클릭**했다(그날 실측: 로그인 창
#     ID=저장됨·PW len=0). 헛수고일 뿐 아니라 **반복 실패 로그인은 계정 잠금 위험**이다.
#   ⇒ 라운드를 돌기 전에 플래그를 읽고, 꺼져 있으면 **즉시 중단하고 사람이 할 일을 말한다**.
#     (자격 자체를 여기서 채우지 않는다 — 비밀번호 취급은 사람의 영역이다.)
#   ★건너뛰기: -SkipLogin 이면 이미 로그인된 세션 전제이므로 점검하지 않는다.
$MAINCFG = "C:\WISEfn\Common\Data\maincfg.ini"
if (-not $SkipLogin) {
  if (Test-Path $MAINCFG) {
    $cfg = Get-Content $MAINCFG -Encoding Default -EA SilentlyContinue
    $savepw = ($cfg | Where-Object { $_ -match '^\s*SAVEUSERPW\s*=' } | Select-Object -First 1) -replace '^[^=]+=', ''
    $savepw = "$savepw".Trim()
    if ($savepw -eq '0') {
      Write-Host ""
      Write-Host "XX ABORT [autologin] maincfg.ini [LOGIN] SAVEUSERPW=0 — 비밀번호 저장이 꺼져 있습니다."
      Write-Host "   이 스크립트는 LOGIN 버튼을 클릭만 하므로, 저장된 비밀번호 없이는 **몇 번을 돌려도 실패**합니다."
      Write-Host "   (반복 실패 로그인은 계정 잠금 위험이 있어 라운드를 시작하지 않습니다.)"
      Write-Host "   조치: Quantiwise 로그인 창에서 비밀번호를 1회 입력하되 **'비밀번호 저장' 체크박스를 켜고** 로그인하세요."
      Write-Host "         → maincfg.ini 가 SAVEUSERPW=1 로 바뀌면 이후 무인 실행이 복구됩니다."
      Write-Host "   확인:  Select-String -Path '$MAINCFG' -Pattern 'SAVEUSERPW'"
      exit 3
    }
    Write-Host "[autologin] SAVEUSERPW=$savepw (자격 저장 확인)"
  } else {
    Write-Host "[autologin] maincfg.ini 부재 — 사전 점검 생략(로그인 실패 시 원인 특정 불가)"
  }
}

# ---- main: resilient round loop ----
Write-Host "===== QW incremental refresh (kick-resilient) $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====="
$target = Get-Target
Write-Host "target (last trading day) = $target"
$state = Load-State
Start-DialogWatcher
## ★F1(2026-11-06 · PLAN §3.0): PowerShell 5.1 은 결과가 1개면 배열이 아니라 해시테이블 하나를 돌려주고 .Count = 키 수(3)다 →
##   'done 3/4'(실제 1/4) · 1개 선택 시 미완료가 숨었다. 결과는 언제나 @() 로 감싼다.
$sel = @(if ($Only.Count -gt 0) { $FILES | Where-Object { $Only -contains $_.name } } else { $FILES })
foreach ($k in @($FROM_OVR.Keys)) { if ($state.ContainsKey($k)) { $state.Remove($k) } }   # 지정 책은 상태 '완료'를 무시하고 1회 다시 받는다
$round = 0
while ($round -lt $MaxRounds) {
  $round++
  $pending = @($sel | Where-Object { -not (Is-Done $state $_.name $target) })
  if ($pending.Count -eq 0) { Write-Host "===== ALL DONE (round $round) ====="; break }
  Write-Host ("--- round {0}: pending {1} [{2}] ---" -f $round, $pending.Count, (($pending | ForEach-Object { $_.name }) -join ', '))
  if (-not $SkipLogin) { if (-not (Ensure-Login)) { Write-Host "[login] failed, retry"; Start-Sleep 5; continue } }
  $kicked=$false
  foreach ($f in $pending) {
    $r = Refresh-One $f $target
    if ($r -eq "ok") { Mark-Done $state $f.name $target }
    elseif ($r -eq "kicked") { $kicked=$true; break }
  }
  if ($kicked) { Write-Host "[round $round] kicked -> re-login next round"; Start-Sleep 3 }
}
Stop-DialogWatcher
$doneN = @($sel | Where-Object { Is-Done $state $_.name $target }).Count
Write-Host "===== END $(Get-Date -Format 'HH:mm:ss') / done $doneN/$($sel.Count) (target $target) ====="
if ($doneN -eq $sel.Count) { Write-Host "next: in R -> source('02_Infrastructure/data/incremental_update_file.R'); incremental_update_all()" }
else { Write-Host "pending remain -> re-run to resume (idempotent)." }
