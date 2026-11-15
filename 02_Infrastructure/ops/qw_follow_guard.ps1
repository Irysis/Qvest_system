# ==============================================================================
#  qw_follow_guard.ps1 - watchdog process for an add-in refresh (hyperlink .Follow()) in an automation Excel
#  (ASCII-only for PowerShell 5.1 encoding safety)
# ==============================================================================
#  Why (2026-11-15, Dohoon 11-15 'fix it' - decision FUNDV2-TAXTS-FIX-20261115):
#    11-14 13:38 Qvest_FundV2Update -> qw_fund_v2_tax_ts.ps1, sheet 2 (B101400_M): in the middle of the add-in call the
#    terminal (qwMain) showed its 'Item Lookup' form (a picker meant for a person), Excel showed 'waiting for another
#    application to complete an OLE action', and Follow() never returned. Nothing had a time limit: the scheduled job
#    hung 2 h+ until a person killed the tree (15:48). The thread that hangs is the caller's, so the guard is a separate
#    process. The picker did not appear in the 11-09 runs or in the 11-15 replay (20 tickers, same four sheets) - its
#    trigger is inside the terminal, so the guard handles the form and the stall, not one guessed cause.
#  -Once: one pass of 1) and 2) with no grace (callers use it before they start Excel), then exit 0.
#  What it does every -PollMs, until the caller exits, its Excel exits, or -StopFile appears:
#    1) terminal picker forms: a visible qwMain window titled 'Item Lookup' / 'Entity Lookup' / 'FISIS Item Lookup' /
#       'FISIS Entity Lookup' for -LookupGraceSec -> WM_CLOSE (an unattended run never picks anything) -> event lookup_closed
#    2) the terminal's content-update prompt '-Quantiwise7G Update-' (#32770, Yes 6 / No 7) -> No (do not update the
#       terminal under a running job; the prompt comes back at the next check) -> event update_declined
#    3) stall: heartbeat file -Beat (the caller writes '<label>|<unix milliseconds at start>' before each Follow and clears it
#       after); one Follow running longer than -StallSec -> kill the caller's Excel (pid AND start ticks match - a reused
#       pid is never killed) -> event excel_killed. The blocked COM call in the caller then throws, so the caller ends
#       instead of hanging. The book is the caller's temp work copy - nothing else is lost.
#    4) diagnostics only: first sight of any other visible qwMain window or dialog of that Excel -> event seen
#  Events: JSON lines in -Events {t (unix ms), kind, label, title, detail}. The caller reads them after each Follow. The first
#    event of a resident guard is 'ready' (the caller does not refresh before it sees it - no unguarded Follow).
#  Exit: 0 stopped | 9 killed the Excel | 2 bad arguments
# ==============================================================================
param(
  [int]$ExcelPid = 0,
  [long]$ExcelTicks = 0,
  [string]$Events = '',
  [string]$Beat = '',
  [int]$StallSec = 1800,
  [int]$LookupGraceSec = 5,
  [int]$PollMs = 1000,
  [int]$ParentPid = 0,
  [string]$StopFile = '',
  [int]$QwPid = 0,          # test hook: the 'terminal' process to watch (0 = the running qwMain)
  [int]$MaxSec = 86400,     # absolute life of the guard itself (never outlives a day)
  [switch]$Once
)
if ($Once) { $LookupGraceSec = 0 }
$ErrorActionPreference = 'Continue'
if (-not $Events) { exit 2 }
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class FG { public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h, int id);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public static string Txt(IntPtr h){ var s=new StringBuilder(512); GetWindowText(h,s,512); return s.ToString(); }
  public static string Cls(IntPtr h){ var s=new StringBuilder(128); GetClassName(h,s,128); return s.ToString(); }
  public static List<IntPtr> Wins(int pid0){ var r=new List<IntPtr>(); EnumWindows((h,l)=>{int p; GetWindowThreadProcessId(h,out p); if(p==pid0 && IsWindowVisible(h)) r.Add(h); return true;}, IntPtr.Zero); return r; }
  public static string KidText(IntPtr p0){ var a=new List<string>(); EnumChildWindows(p0,(h,l)=>{ var t=Txt(h); if(t.Length>0) a.Add(t); return true; }, IntPtr.Zero); return string.Join(" | ", a.ToArray()); } }
"@
$PICKER = '^(FISIS )?(Item|Entity) Lookup$'
$UPDATE = '-Quantiwise7G Update-'
# times are unix MILLISECONDS (events and heartbeat): a caller that retries a sheet within the same second must not
#   count the previous attempt's event again
function Now-Unix { return [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) }
function Beat-Label { if (-not $Beat) { return '' }; try { return ("$(Get-Content -LiteralPath $Beat -Raw -EA Stop)".Trim() -split '\|')[0] } catch { return '' } }
function Mask([string]$s) { return ($s -replace '\[[^\]\(]*\(\d{1,3}(\.\d{1,3}){3}\)\]', '[<host>(<ip>)]' -replace '\b\d{1,3}(\.\d{1,3}){3}\b', '<ip>') }
# events are written BEFORE the action: the caller's Follow can return only after the form or prompt is gone, so the
#   event is already in the file when the caller reads it (written after, a fast return could miss it)
function Emit([string]$kind, [string]$title, [string]$detail) {
  $o = [ordered]@{ t = (Now-Unix); kind = $kind; label = (Beat-Label); title = (Mask $title); detail = (Mask $detail) }
  $line = $o | ConvertTo-Json -Compress
  for ($i = 0; $i -lt 5; $i++) { try { Add-Content -LiteralPath $Events -Value $line -Encoding UTF8 -EA Stop; return } catch { Start-Sleep -Milliseconds 100 } }
}
function Excel-Ours { if ($ExcelPid -le 0) { return $false }; $p = Get-Process -Id $ExcelPid -EA SilentlyContinue; return [bool]($p -and $p.StartTime.Ticks -eq $ExcelTicks) }
function Kill-Excel([string]$why) {
  if (-not (Excel-Ours)) { return $false }
  Stop-Process -Id $ExcelPid -Force -EA SilentlyContinue
  Emit 'excel_killed' '' $why
  return $true
}
$t0 = Get-Date; $first = @{}; $nextAct = @{}; $killed = $false
if (-not $Once) { Emit 'ready' '' ("guard pid=$PID excel=$ExcelPid stall=${StallSec}s") }   # the caller waits for this
while ($true) {
  if ($StopFile -and (Test-Path -LiteralPath $StopFile)) { break }
  if ($ParentPid -gt 0 -and -not (Get-Process -Id $ParentPid -EA SilentlyContinue)) { break }
  if ($ExcelPid -gt 0 -and -not (Excel-Ours)) { break }
  if (((Get-Date) - $t0).TotalSeconds -gt $MaxSec) { break }
  $qp = $QwPid
  if ($qp -le 0) { $q = Get-Process qwMain -EA SilentlyContinue | Select-Object -First 1; if ($q) { $qp = [int]$q.Id } }
  if ($qp -gt 0) {
    foreach ($h in [FG]::Wins($qp)) {
      $title = [FG]::Txt($h); $cls = [FG]::Cls($h); $key = "q$h"
      if ($cls -eq 'ThunderRT6Main') { continue }   # the terminal's own main window
      if (-not $first.ContainsKey($key)) {
        $first[$key] = Get-Date
        if ($title -notmatch $PICKER -and $title -ne $UPDATE) { Emit 'seen' $title ("terminal window cls=$cls text: " + [FG]::KidText($h)) }
      }
      if ($title -match $PICKER -and ((Get-Date) - $first[$key]).TotalSeconds -ge $LookupGraceSec) {
        Emit 'lookup_closed' $title ("open {0:n0}s -> WM_CLOSE; text: {1}" -f ((Get-Date) - $first[$key]).TotalSeconds, [FG]::KidText($h))
        [void][FG]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)          # WM_CLOSE
        Start-Sleep -Milliseconds 800
        if ([FG]::IsWindow($h) -and [FG]::IsWindowVisible($h)) { $r = [IntPtr]::Zero; [void][FG]::SendMessageTimeout($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero, 2, 5000, [ref]$r) }
        if ([FG]::IsWindow($h) -and [FG]::IsWindowVisible($h)) { Emit 'lookup_close_failed' $title 'still open after WM_CLOSE - retry after the grace'; $first[$key] = Get-Date }
        else { $first.Remove($key) }
      }
      elseif ($cls -eq '#32770' -and $title -eq $UPDATE -and (-not $nextAct.ContainsKey($key) -or (Get-Date) -ge $nextAct[$key])) {
        $no = [FG]::GetDlgItem($h, 7)
        if ($no -ne [IntPtr]::Zero) {
          Emit 'update_declined' $title ("No (id 7); text: " + [FG]::KidText($h))
          $r = [IntPtr]::Zero; [void][FG]::SendMessageTimeout($no, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero, 2, 5000, [ref]$r)   # BM_CLICK 'No'
          Start-Sleep -Milliseconds 500
          if ([FG]::IsWindow($h) -and [FG]::IsWindowVisible($h)) { $nextAct[$key] = (Get-Date).AddSeconds(10) }   # not closed: again in 10 s, not every poll
          else { $first.Remove($key); $nextAct.Remove($key) }
        }
      }
    }
  }
  if ($ExcelPid -gt 0) {
    foreach ($h in [FG]::Wins($ExcelPid)) {
      $cls = [FG]::Cls($h); $key = "x$h"
      if ($cls -eq 'XLMAIN' -or $first.ContainsKey($key)) { continue }
      $first[$key] = Get-Date; Emit 'seen' ([FG]::Txt($h)) ("excel window cls=$cls text: " + [FG]::KidText($h))
    }
  }
  if ($Beat -and (Test-Path -LiteralPath $Beat)) {
    $b = ''; try { $b = "$(Get-Content -LiteralPath $Beat -Raw -EA Stop)".Trim() } catch {}
    if ($b -match '\|(\d+)$') {
      $age = [int64](((Now-Unix) - [int64]$Matches[1]) / 1000)
      if ($age -gt $StallSec) { if (Kill-Excel ("stall: '{0}' ran {1}s > {2}s" -f ($b -split '\|')[0], $age, $StallSec)) { $killed = $true } }
    }
  }
  if ($Once) { break }
  Start-Sleep -Milliseconds $PollMs
}
if ($killed) { exit 9 }
exit 0
