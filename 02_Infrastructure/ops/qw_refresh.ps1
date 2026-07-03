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
  [switch]$WhatIf
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

# targets (fast -> slow). cache = parquet used to compute incremental B5 (null = keep existing B5)
$FILES = @(
  @{ name="Benchmark";        path=(Join-Path $UNIV "Benchmark_price.xlsx");         cache=(Join-Path $ROOT ".cache\benchmark.parquet") }
  @{ name="OHLCVS";           path=(Join-Path $UPD  "OHLCVS_update.xlsx");           cache=$null }  # RAWDATA는 KRX로 항상 신선 -> 스킵 방지 위해 null(파일 기존 From 유지, B6만 06-30). 4MB라 빠름
  @{ name="Universe_Support"; path=(Join-Path $UPD  "Universe_Support_update.xlsx"); cache=(Join-Path $ROOT ".cache\universe.parquet") }
  @{ name="Investor_Act";     path=(Join-Path $UPD  "Investor_Act_update.xlsx");     cache=(Join-Path $ROOT ".cache\investor_stock\investor_all.parquet") }
  @{ name="Consensus";        path=(Join-Path $UPD  "Consensus_update.xlsx");        cache=(Join-Path $ROOT ".cache\consensus\eps_1y.parquet") }
)

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
  $code="import pyarrow.parquet as pq,pandas as pd" + [char]10 + "print(pd.to_datetime(pq.read_table(r'$ROOT\.cache\RAWDATA.parquet',columns=['Date']).to_pandas()['Date']).max().strftime('%Y%m%d'))"
  try { $r=(& $PY -c $code 2>$null); return "$r".Trim() } catch { return (Get-Date).AddDays(-1).ToString("yyyyMMdd") }
}
function Get-CacheNext($cache) {
  if (-not $cache -or -not (Test-Path $cache)) { return $null }
  $code="import pyarrow.parquet as pq,pandas as pd" + [char]10 + "print((pd.to_datetime(pq.read_table(r'$cache',columns=['Date']).to_pandas()['Date']).max()+pd.Timedelta(days=1)).strftime('%Y%m%d'))"
  try { $r=(& $PY -c $code 2>$null); return "$r".Trim() } catch { return $null }
}

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
  $b5 = Get-CacheNext $f.cache
  if ($f.cache -and $b5 -and ([long]$b5 -gt [long]$target)) { Write-Host "[$($f.name)] cache already >= target (next $b5 > $target) -> done"; return "ok" }
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
      $b6 = "$($wb.Worksheets.Item(1).Range('B6').Value2)"
      $ok = $b6 -match "\[$target\]"
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

# ---- main: resilient round loop ----
Write-Host "===== QW incremental refresh (kick-resilient) $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====="
$target = Get-Target
Write-Host "target (last trading day) = $target"
$state = Load-State
Start-DialogWatcher
$sel = if ($Only.Count -gt 0) { $FILES | Where-Object { $Only -contains $_.name } } else { $FILES }
$round = 0
while ($round -lt $MaxRounds) {
  $round++
  $pending = $sel | Where-Object { -not (Is-Done $state $_.name $target) }
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
$doneN = ($sel | Where-Object { Is-Done $state $_.name $target }).Count
Write-Host "===== END $(Get-Date -Format 'HH:mm:ss') / done $doneN/$($sel.Count) (target $target) ====="
if ($doneN -eq $sel.Count) { Write-Host "next: in R -> source('02_Infrastructure/data/incremental_update_file.R'); incremental_update_all()" }
else { Write-Host "pending remain -> re-run to resume (idempotent)." }
