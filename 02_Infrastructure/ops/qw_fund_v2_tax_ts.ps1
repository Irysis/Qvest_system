# qw_fund_v2_tax_ts.ps1 - Quantiwise fundamentals v2: tax-related B codes as a Time Series (Company) book (2026-11-09)
#   Decision: Dohoon 11-09 "jigeum sujip" (collect the 4 tax B codes for all firms from 2000Q1 into fundamentals DB v2).
#   Items (IFRS glossary, FCF1/FCF2 groups, defined for non-financial firms only):
#     B201700.M  other current liabilities incl. current tax payable  (= TXP + other cur. liab + (AP&other - trade AP))
#     B101400.M  non-interest-bearing current liabilities              (= AP&other + other cur. liab)
#     B201600.M  trade payables
#     B100300.M  deferred tax net change                               (= dDTL - dDTA)
#     => current tax payable TXP = B201700 - B101400 + B201600 (matched DART 109/109 exactly in the 10-firm test, 11-09)
#   Official XLA manual (http://seven.quantiwise.com/Manual/QW7_User Manual/Quantiwise7_XLA(Kor).pdf p.58, p.64):
#     a financial item in a Time Series sheet needs the report point in row 12 'Base Date' (FQ0 = latest fiscal quarter).
#     Blank Base Date -> no values (M codes) / '#INVALID OPTION' (B codes). With FQ0 the value on date row d is the fiscal
#     quarter d - 1Q (default 3-month lagging) in KRW thousand. Codes need the '.M' suffix; financial firms (bank, insurance,
#     securities) return '#INVALID OPTION' even with '.M' (B codes are defined for the 'manufacturing' type) -> left missing.
#   Steps: copy the template to a LOCAL work folder (saving an OneDrive xlsx through COM can leave the Office merge dialog
#     blocking Close) -> keep the 4 sheets + DATA_Key -> B5 From / B6 CPD-1TD / B10 code / B12:<last col>12 = FQ0 ->
#     follow the 'Quantiwise*' hyperlinks (synchronous refresh) -> check session after each sheet -> save locally -> file copy
#     to -Out. Ingest = 02_Infrastructure/data/qw_fund_v2_tax_ingest.py.
#   Session: a duplicate-login termination dialog (body has '(IP)]' or the word for 'duplicate') -> ONE
#     'qw_refresh.ps1 -LoginOnly' (standing delegation 11-06) and one retry of that sheet; kicked again -> stop (rc 4, no login war).
#     Any other dialog or a dead session -> stop (rc 3/4) and report. Never types credentials.
# Exit: 0 ok - 1 error - 3 no live session - 4 kicked twice / unknown dialog
param(
  [string]$Template = '',
  [string]$Out = '',
  [string]$From = '20000101',
  [string]$Work = '',
  [int]$CloseGuardSec = 120
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $Out) { $Out = Join-Path $Root '03_Universe\Fundamental_v2\FundV2_TAX_TS.xlsx' }
if (-not $Template) { $Template = if (Test-Path $Out) { $Out } else { Join-Path $Root '.cache\qw_test\TaxBTest.xlsx' } }
if (-not $Work) { $Work = Join-Path $env:TEMP 'qvest_qw_tax' }
$Log = Join-Path $Root '.cache\scheduler_logs\qw_fund_v2_tax_ts.log'
function Say([string]$m) { $l = "[tax-ts $(Get-Date -Format 'HH:mm:ss')] $m"; Write-Host $l; try { Add-Content -LiteralPath $Log -Value $l -Encoding UTF8 } catch {} }

Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class TW { public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public static string Txt(IntPtr h){ var s=new StringBuilder(1024); GetWindowText(h,s,1024); return s.ToString(); }
  public static string Cls(IntPtr h){ var s=new StringBuilder(128); GetClassName(h,s,128); return s.ToString(); }
  public static List<IntPtr> Wins(int pid0){ var r=new List<IntPtr>(); EnumWindows((h,l)=>{int p; GetWindowThreadProcessId(h,out p); if(p==pid0 && IsWindowVisible(h)) r.Add(h); return true;}, IntPtr.Zero); return r; }
  public static List<IntPtr> All(int pid0){ var r=new List<IntPtr>(); EnumWindows((h,l)=>{int p; GetWindowThreadProcessId(h,out p); if(p==pid0) r.Add(h); return true;}, IntPtr.Zero); return r; }
  public static List<IntPtr> Kids(IntPtr p0){ var r=new List<IntPtr>(); EnumChildWindows(p0,(h,l)=>{ r.Add(h); return true; }, IntPtr.Zero); return r; } }
"@
# Same detection as qw_refresh.ps1::Kick-Dialog (dialog body with '(IP)]' or the word for 'duplicate')
function Kick-Dialog {
  $p = Get-Process qwMain -EA SilentlyContinue | Select-Object -First 1
  if (-not $p) { return $null }
  $dup = "$([char]0xC911)$([char]0xBCF5)"
  foreach ($h in [TW]::Wins([int]$p.Id)) {
    if ([TW]::Cls($h) -eq '#32770' -and [TW]::Txt($h) -like '*Quantiwise*') {
      foreach ($k in [TW]::Kids($h)) { $t = [TW]::Txt($k); if ($t -match '\(\d{1,3}(\.\d{1,3}){3}\)\]' -or $t.Contains($dup)) { return $h } }
    }
  }
  return $null
}
function Other-Dialog {
  $p = Get-Process qwMain -EA SilentlyContinue | Select-Object -First 1
  if (-not $p) { return $false }
  foreach ($h in [TW]::Wins([int]$p.Id)) { if ([TW]::Cls($h) -eq '#32770' -and [TW]::Txt($h) -like '*Quantiwise*') { return $true } }
  return $false
}
# Same rule as qw_refresh.ps1::QW-Alive (any window of qwMain titled *Quantiwise7* and not *Login*, after the kick check)
function QW-Alive {
  $p = Get-Process qwMain -EA SilentlyContinue | Select-Object -First 1
  if (-not $p) { return $false }
  if (Kick-Dialog) { return $false }
  foreach ($h in [TW]::All([int]$p.Id)) { $t = [TW]::Txt($h); if ($t -like '*Quantiwise7*' -and $t -notlike '*Login*') { return $true } }
  return $false
}
function ColName([int]$n) { $s = ''; while ($n -gt 0) { $r = ($n - 1) % 26; $s = [char](65 + $r) + $s; $n = [int][Math]::Floor(($n - 1) / 26) }; return $s }

$runs = @(
  @{ sheet = 'B201700_M'; code = 'B201700.M' },
  @{ sheet = 'B101400_M'; code = 'B101400.M' },
  @{ sheet = 'B201600_M'; code = 'B201600.M' },
  @{ sheet = 'B100300_M'; code = 'B100300.M' }
)
Say "start template=$Template out=$Out from=$From work=$Work"
if (-not (Test-Path $Template)) { Say "template missing"; exit 1 }
if (Kick-Dialog) { Say "duplicate-login dialog at start - not handled here (run qw_refresh.ps1 -LoginOnly first)"; exit 4 }
if (Other-Dialog) { Say "unknown Quantiwise dialog at start - stop and report"; exit 4 }
if (-not (QW-Alive)) { Say "no live Quantiwise session"; exit 3 }
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$local = Join-Path $Work 'FundV2_TAX_TS.xlsx'
Copy-Item -LiteralPath $Template -Destination $local -Force
$today = Get-Date -Format 'yyyy-MM-dd'
$xl = $null; $wb = $null; $xp = 0; $tk = 0; $rc = 1; $relogged = $false
try {
  $xl = New-Object -ComObject Excel.Application
  $xl.Visible = $true; $xl.DisplayAlerts = $false; $xl.EnableEvents = $true; $xl.AskToUpdateLinks = $false
  [void][TW]::GetWindowThreadProcessId([IntPtr]$xl.Hwnd, [ref]$xp); $tk = (Get-Process -Id $xp).StartTime.Ticks
  $wb = $xl.Workbooks.Open($local)
  $keep = @($runs | ForEach-Object { $_.sheet }) + 'DATA_Key'
  foreach ($ws in @($wb.Worksheets)) { if ($keep -notcontains $ws.Name) { $ws.Delete() } }
  foreach ($r in $runs) { try { [void]$wb.Worksheets.Item($r.sheet) } catch { throw "sheet missing in template: $($r.sheet)" } }
  $nk = [int]$xl.WorksheetFunction.CountA($wb.Worksheets.Item('DATA_Key').Range('D2:D10002'))
  $lastC = ColName (1 + $nk)
  Say "tickers=$nk last column=$lastC"
  foreach ($r in $runs) {
    for ($attempt = 1; $attempt -le 2; $attempt++) {
      $ws = $wb.Worksheets.Item($r.sheet); $ws.Activate()
      $ws.Range('B5').Value2 = $From; $ws.Range('B6').Value2 = 'CPD-1TD'; $ws.Range('B10').Value2 = $r.code
      [void]$ws.Range("B12:$($lastC)12").ClearContents(); $ws.Range("B12:$($lastC)12").Value2 = 'FQ0'
      $before = "$($ws.Range('B1').Text)"; $t0 = Get-Date
      foreach ($h in $ws.Hyperlinks) { if ($h.ScreenTip -like 'Quantiwise*') { $h.Follow() } }
      $secs = [int]((Get-Date) - $t0).TotalSeconds
      $after = "$($ws.Range('B1').Text)"
      $ur = $ws.UsedRange; $last = $ur.Row + $ur.Rows.Count - 1
      $rng = $ws.Range("B15:$($lastC)$last")
      $num = [int]$xl.WorksheetFunction.Count($rng); $inv = [int]$xl.WorksheetFunction.CountIf($rng, '#INVALID*')
      Say ("{0} code={1} B12='{2}' rows={3} numeric={4} invalid={5} B1 '{6}' -> '{7}' | {8}s" -f $r.sheet, $r.code, $ws.Range('B12').Text, [Math]::Max(0, $last - 14), $num, $inv, $before, $after, $secs)
      $kicked = [bool](Kick-Dialog)
      # refreshed = stamp moved AND dated today (a same-day rerun keeps today's old stamp if the refresh silently did nothing)
      if (-not $kicked -and (QW-Alive) -and $after -ne $before -and $after -like "*$today*" -and $num -gt 0) { break }
      if ($kicked -and -not $relogged -and $attempt -eq 1) {
        Say "duplicate-login dialog -> qw_refresh.ps1 -LoginOnly (once) and retry $($r.sheet)"
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'qw_refresh.ps1') -LoginOnly | ForEach-Object { Say "  $_" }
        $relogged = $true
        if (-not (QW-Alive)) { throw 'relogin failed' }
        continue
      }
      if ($kicked) { $rc = 4; throw "kicked again on $($r.sheet) - stop (no login war)" }
      if (Other-Dialog) { $rc = 4; throw "unknown Quantiwise dialog on $($r.sheet)" }
      if (-not (QW-Alive)) { $rc = 3; throw "session lost on $($r.sheet)" }
      throw "sheet $($r.sheet) not refreshed (B1 '$after' numeric=$num)"
    }
  }
  $wb.Save(); Say "saved local copy $local"
  $rc = 0
} catch { Say "ERROR: $($_.Exception.Message)"; if ($rc -eq 0) { $rc = 1 } }
finally {
  if ($wb) { try { $wb.Close($false) } catch {} }
  if ($xl) { try { $xl.Quit() } catch {}; try { [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null } catch {} }
  [GC]::Collect(); [GC]::WaitForPendingFinalizers()
  if ($xp -gt 0) {
    for ($i = 0; $i -lt $CloseGuardSec; $i++) { if (-not (Get-Process -Id $xp -EA SilentlyContinue)) { break }; Start-Sleep 1 }
    $p = Get-Process -Id $xp -EA SilentlyContinue
    if ($p -and $p.StartTime.Ticks -eq $tk) { Stop-Process -Id $xp -Force; Say "closed own Excel $xp by guard" }
  }
}
if ($rc -eq 0) { Copy-Item -LiteralPath $local -Destination $Out -Force; Say "copied -> $Out" }
Say "END rc=$rc"
exit $rc
