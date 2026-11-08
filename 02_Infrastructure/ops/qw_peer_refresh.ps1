# ==============================================================================
#  qw_peer_refresh.ps1 - refresh a Quantiwise "Peer Analysis" book (fundamentals) via the
#  same add-in trigger qw_refresh.ps1 uses: hyperlink ScreenTip 'Quantiwise*' .Follow()
#  (ASCII-only for PowerShell 5.1 encoding safety)
# ==============================================================================
#  Why (2026-11-08, BUILD_20261108.md s2): qw_refresh.ps1 judges completion by the Time Series
#    Period(To) bracket in B6 (A6 like Period*To*). Peer Analysis sheets have no Period(To), so
#    that driver would mark a fundamentals book 'not reached' forever. Here completion = every
#    item sheet's B1 'Last Update' stamp changed during this run AND the session stayed alive.
#  Login: never clicks a login button. Requires a live session ([[Quantiwise7]] window),
#    same test as qw_refresh.ps1 QW-Alive. Re-login is the caller's job (qw_refresh.ps1).
#  Usage: powershell -File qw_peer_refresh.ps1 -Book <xlsx> [-Sheets a,b] [-Log <path>]
#  Exit: 0 all sheets refreshed + saved | 1 some sheet not refreshed (saved anyway, see log)
#        | 3 precondition (no session / busy / book locked) | 4 session kicked mid-run
# ==============================================================================
param(
  [Parameter(Mandatory = $true)][string]$Book,
  [string[]]$Sheets = @(),
  [switch]$NoBusyCheck,
  # close guard (11-08): seconds Workbook.Close/Excel.Quit may take before a guard process kills this Excel
  [int]$CloseGuardSec = 120
)
$ErrorActionPreference = "Continue"
$Sheets = @($Sheets | ForEach-Object { "$_" -split ',' } | Where-Object { $_ -ne '' })
Add-Type -TypeDefinition @"
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public class QpWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  public static List<string> Titles(int pid0) {
    var res = new List<string>();
    EnumWindows((h, l) => { int pid; GetWindowThreadProcessId(h, out pid); if (pid == pid0) { var t = new StringBuilder(256); GetWindowText(h, t, 256); if (t.Length > 0) res.Add(t.ToString()); } return true; }, IntPtr.Zero);
    return res; }
  // texts of the children of every '#32770' dialog of the process whose title contains 'Quantiwise'
  public static List<string> DialogTexts(int pid0) {
    var res = new List<string>();
    EnumWindows((h, l) => { int pid; GetWindowThreadProcessId(h, out pid);
      if (pid == pid0) { var c = new StringBuilder(64); GetClassName(h, c, 64); var t = new StringBuilder(256); GetWindowText(h, t, 256);
        if (c.ToString() == "#32770" && t.ToString().Contains("Quantiwise")) {
          EnumChildWindows(h, (k, l2) => { var s = new StringBuilder(1024); GetWindowText(k, s, 1024); if (s.Length > 0) res.Add(s.ToString()); return true; }, IntPtr.Zero); } }
      return true; }, IntPtr.Zero);
    return res; }
}
"@
# 2026-11-08: the duplicate-login termination dialog (#32770, title 'Quantiwise7G', text '[HOST(IP)]... (dup) ...')
#   matched '*Quantiwise7*' below, so a kicked session looked alive and every later sheet "refreshed" in 0 s with
#   no data (FundV2_IS / FundV2_BS 81 sheets, 17:15). A visible kick dialog = no session.
function Kick-Dialog {
  $p = Get-Process qwMain -EA SilentlyContinue
  if (-not $p) { return $false }
  $dup = "$([char]0xC911)$([char]0xBCF5)"   # Korean 'jung-bok' (duplicate)
  foreach ($t in [QpWin]::DialogTexts([int]$p.Id)) { if ($t -match '\(\d{1,3}(\.\d{1,3}){3}\)\]' -or $t.Contains($dup)) { return $true } }
  return $false
}
function QW-Alive {
  $p = Get-Process qwMain -EA SilentlyContinue
  if (-not $p) { return $false }
  if (Kick-Dialog) { return $false }
  foreach ($t in [QpWin]::Titles([int]$p.Id)) { if ($t -like "*Quantiwise7*" -and $t -notlike "*Login*") { return $true } }
  return $false
}
function Get-Busy {
  $p = Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'qw_refresh[^ ]*\.ps1|qw_excel_refresh\.ps1|qw_datakey_sync\.ps1|qw_fundamental_book\.ps1') -or
    ($_.Name -eq 'bash.exe' -and $_.CommandLine -match 'qw_updatefile_unattended\.sh') -or
    ($_.Name -eq 'python.exe' -and $_.CommandLine -match 'quantiwise_fetch\.py') -or
    ($_.Name -eq 'EXCEL.EXE' -and $_.CommandLine -match '/automation')
  }
  return @($p)
}

function ColNameP([int]$n) { $s = ''; while ($n -gt 0) { $r = ($n - 1) % 26; $s = [char](65 + $r) + $s; $n = [int][Math]::Floor(($n - 1) / 26) }; return $s }
if (-not (Test-Path -LiteralPath $Book)) { Write-Host "[peer-refresh] missing $Book"; exit 3 }
if (-not (QW-Alive)) { Write-Host "[peer-refresh] no live Quantiwise session ([[Quantiwise7]] window) - log in first"; exit 3 }
if (-not $NoBusyCheck) { $b = Get-Busy; if ($b.Count -gt 0) { Write-Host "[peer-refresh] BUSY:"; $b | ForEach-Object { Write-Host ("  pid {0} {1}" -f $_.ProcessId, $_.Name) }; exit 3 } }

# items that may legitimately come back empty (2026-11-09): same rule as the loader qw_fund_v2_ingest.py G1 -
#   registry fundamentals_v2.items[].allow_empty or glossary_basis 'gaap' (pre-2007 GAAP lines are empty in recent windows).
#   11-09 FundV2_META_upd: 'CompInfo' (text item, 0 cells on every refresh since 11-08) counted as NOT REFRESHED -> rc 1 -> the
#   rolling update stopped before FundV2_INFO_upd. Registry unreadable = empty set = strict (never more lenient than before).
$emptyOk = @{}
try {
  $regPath = Join-Path $PSScriptRoot "..\data\qw_updatefile_registry.json"
  $regItems = @((Get-Content -LiteralPath $regPath -Raw -Encoding UTF8 | ConvertFrom-Json).fundamentals_v2.items | ForEach-Object { $_ })
  foreach ($it in $regItems) { if ($it.allow_empty -eq $true -or "$($it.glossary_basis)" -eq 'gaap') { $emptyOk["$($it.sheet)"] = $true } }
} catch { Write-Host "[peer-refresh] registry not read ($($_.Exception.Message)) - empty sheets count as NOT REFRESHED" }

$xl = $null; $wb = $null; $rc = 1; $t0 = Get-Date
Write-Host ("[peer-refresh] start {0} {1}" -f $t0.ToString('HH:mm:ss'), $Book)
try {
  $xl = New-Object -ComObject Excel.Application
  $xl.Visible = $true; $xl.DisplayAlerts = $false; $xl.EnableEvents = $true; $xl.AskToUpdateLinks = $false
  $wb = $xl.Workbooks.Open($Book)
  $todo = @(); foreach ($ws in $wb.Worksheets) { if ("$($ws.Range('A3').Value2)" -like 'Peer Analysis*') { if ($Sheets.Count -eq 0 -or $Sheets -contains $ws.Name) { $todo += $ws } } }
  Write-Host ("[peer-refresh] {0} item sheets" -f $todo.Count)
  $okN = 0; $kicked = $false
  foreach ($ws in $todo) {
    $before = "$($ws.Range('B1').Value2)"; $ts = Get-Date
    if (-not (QW-Alive)) { Write-Host "[peer-refresh] session gone before '$($ws.Name)' (kick dialog or no window)"; $kicked = $true; break }
    $ws.Activate()
    $n = 0; foreach ($h in $ws.Hyperlinks) { if ($h.ScreenTip -like "Quantiwise*") { $h.Follow(); $n++ } }
    $after = "$($ws.Range('B1').Value2)"
    $sec = [int]((Get-Date) - $ts).TotalSeconds
    # completion = B1 stamp changed AND the data area actually holds values (11-08: a kicked session still
    #   rewrote B1 on every sheet in 0 s with no data - the stamp alone counted 81 empty sheets as refreshed)
    $lastC = 4; while ("$($ws.Range("$(ColNameP ($lastC + 1))10").Value2)" -ne '') { $lastC++ }
    $filled = [int]$xl.WorksheetFunction.CountA($ws.Range("D14:$(ColNameP $lastC)5000"))
    # partial transfer (11-08: CF 'Capex' stopped at 201209 of 115 periods in 17 s): data present but the
    #   second-to-last period column empty -> refresh the sheet once more (the last column may be the
    #   reporting season in progress). Items that really end early (pre-2006 GAAP lines) stay empty after the retry.
    if ($filled -gt 0 -and $lastC -gt 5) {
      $pen = ColNameP ($lastC - 1)
      if ([int]$xl.WorksheetFunction.CountA($ws.Range("$($pen)14:$($pen)5000")) -eq 0) {
        Write-Host ("  [{0}] period {1} empty (cells {2}) -> retry once" -f $ws.Name, "$($ws.Range("$($pen)10").Value2)", $filled)
        if (QW-Alive) { foreach ($h in $ws.Hyperlinks) { if ($h.ScreenTip -like "Quantiwise*") { $h.Follow() } } }
        $after = "$($ws.Range('B1').Value2)"; $sec = [int]((Get-Date) - $ts).TotalSeconds
        $filled = [int]$xl.WorksheetFunction.CountA($ws.Range("D14:$(ColNameP $lastC)5000"))
        $penN = [int]$xl.WorksheetFunction.CountA($ws.Range("$($pen)14:$($pen)5000"))
        Write-Host ("  [{0}] after retry: cells {1} | period {2} cells {3}{4}" -f $ws.Name, $filled, "$($ws.Range("$($pen)10").Value2)", $penN, $(if ($penN -eq 0) { ' (still empty - ends early or vendor gap)' } else { '' }))
      }
    }
    $allowEmpty = $emptyOk.ContainsKey($ws.Name)
    $changed = ($after -ne $before -and $after -like '*Last Update*' -and ($filled -gt 0 -or $allowEmpty))
    Write-Host ("  [{0}] links {1} | {2}s | cells {3} | B1 '{4}' -> '{5}' | {6}" -f $ws.Name, $n, $sec, $filled, $before, $after, $(if (-not $changed) { 'NOT REFRESHED' } elseif ($filled -eq 0) { 'OK (empty allowed by registry)' } else { 'OK' }))
    if ($changed) { $okN++ }
    if (-not (QW-Alive)) { Write-Host "[peer-refresh] session kicked"; $kicked = $true; break }
  }
  $wb.Save()
  Write-Host ("[peer-refresh] saved | refreshed {0}/{1} | {2:n0}s total" -f $okN, $todo.Count, ((Get-Date) - $t0).TotalSeconds)
  $rc = if ($kicked) { 4 } elseif ($okN -eq $todo.Count -and $todo.Count -gt 0) { 0 } else { 1 }
} catch {
  Write-Host "[peer-refresh] ERROR: $($_.Exception.Message)"; $rc = 1
} finally {
  # close guard (11-08 22:01, FundV2_IS): Save() had written the book, then an Office dialog for the OneDrive-synced
  #   file ('cannot merge your changes with the latest changes', class NUIDialog) blocked Workbook.Close for 30 min
  #   and stalled the chain. Close($false) keeps nothing that was not saved, so killing this Excel while it hangs in
  #   close/quit loses nothing. The guard is a separate process (this thread is the one that hangs) and is stopped
  #   as soon as close/quit return.
  #   The guard matches pid AND start time (a reused pid is never killed) and exits 9 only when it killed.
  $guard = $null; $xlPid = 0; $xlTicks = 0L
  if ($xl) {
    try { [void][QpWin]::GetWindowThreadProcessId([IntPtr]$xl.Hwnd, [ref]$xlPid) } catch {}
    if ($xlPid -gt 0) { try { $xlTicks = (Get-Process -Id $xlPid -EA Stop).StartTime.Ticks } catch {} }
    if ($xlTicks -gt 0) {
      $gcmd = "Start-Sleep $CloseGuardSec; `$p = Get-Process -Id $xlPid -EA SilentlyContinue; " +
              "if (`$p -and `$p.ProcessName -eq 'EXCEL' -and `$p.StartTime.Ticks -eq $xlTicks) { Stop-Process -Id $xlPid -Force; exit 9 }; exit 0"
      try { $guard = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-Command', $gcmd); $null = $guard.Handle }
      catch { Write-Host "[peer-refresh] close guard not started: $($_.Exception.Message)" }
    } else { Write-Host "[peer-refresh] close guard not armed (Excel pid not resolved)" }
  }
  $tc = Get-Date
  if ($wb) { try { $wb.Close($false) } catch {} }
  if ($xl) { try { $xl.Quit() } catch {}; try { [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null } catch {} }
  [GC]::Collect(); [GC]::WaitForPendingFinalizers()
  if ($guard) {
    # $null = .Handle above keeps ExitCode readable (PS 5.1 Start-Process -PassThru quirk)
    if (((Get-Date) - $tc).TotalSeconds -ge ($CloseGuardSec - 1)) { [void]$guard.WaitForExit(5000) }
    if ($guard.HasExited) {
      if ($guard.ExitCode -eq 9) { Write-Host ("[peer-refresh] close guard fired: Excel pid {0} did not close within {1}s - killed (book state = last Save)" -f $xlPid, $CloseGuardSec) }
    } else { try { $guard.Kill() } catch {} }
  }
}
Write-Host "[peer-refresh] END rc=$rc"
exit $rc
