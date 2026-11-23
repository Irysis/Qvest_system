# ==============================================================================
#  qw_kick_rule.ps1 - the one place that decides "this terminal dialog is the duplicate-login termination notice"
#  (ASCII-only for PowerShell 5.1 encoding safety)
# ==============================================================================
#  Why (2026-11-23, Dohoon 11-23 '2beon-eun gyuchik bogang' - include the cut notice in the standing re-login
#  delegation and strengthen the rule):
#    11-23 18:17 another device logged in with the same id. The terminal (qwMain) showed its usual notice - '#32770',
#    title 'Quantiwise7G', one OK button - but the body was cut inside the device tag: '[' + three Korean letters (a
#    device named after a person) instead of '[HOST(IP)] ... duplicate ... terminated'. The drivers' rule (body has
#    '(a.b.c.d)]' or the Korean word for 'duplicate') did not match, so
#      - collectors stopped on 'unknown Quantiwise dialog' (qw_fund_v2_tax_ts.ps1 rc 4), and
#      - QW-Alive saw the hidden '[[Quantiwise7]]' forms and called the dead session alive: 'qw_refresh.ps1 -LoginOnly'
#        and the nightly session check would have passed it (code reading + the 20:39 run: pressing OK ended the
#        terminal exactly like the full notice; the login that followed came alive in 33 s).
#  Rule A (unchanged): a visible '#32770' dialog of the terminal whose title contains 'Quantiwise' and one of whose
#    child texts has the device tag '(a.b.c.d)]' or the Korean word for 'duplicate'.
#  Rule B (new): the same notice with the body cut inside the device tag - title exactly 'Quantiwise7G', exactly ONE
#    button, exactly ONE non-empty non-button text, and that text starts with '[', has no ']' and is at most 64
#    characters. A bracketed notice that closes its bracket ('[notice] ...'), a dialog with two buttons, or another
#    title is NOT matched - it stays an 'unknown dialog' (collectors stop and report; nothing is pressed).
#  The three drivers (qw_refresh.ps1, qw_fund_v2_tax_ts.ps1, qw_peer_refresh.ps1) dot-source this file and call
#    Get-QwKickDialog - they used to carry three copies of rule A.
#  Test: 08_Tests/scenarios/test_scn_qw_kick_shape.sh (real windows of fake processes; never the real terminal).
#  Use:  . qw_kick_rule.ps1
#        Get-QwKickDialog <process id>  -> window handle (IntPtr) of the notice, or $null
#        Test-QwKickShape <title> <child classes> <child texts>  -> $true / $false (pure)
# ==============================================================================
if (-not ('QwKick' -as [type])) {
  Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class QwKick { public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  static string Txt(IntPtr h){ var s=new StringBuilder(1024); GetWindowText(h,s,1024); return s.ToString(); }
  static string Cls(IntPtr h){ var s=new StringBuilder(128); GetClassName(h,s,128); return s.ToString(); }
  // visible '#32770' dialogs of the process whose title contains 'Quantiwise': { handle, title, child classes, child texts }
  public static List<object[]> Dialogs(int pid0){
    var res=new List<object[]>();
    EnumWindows((h,l)=>{ int p; GetWindowThreadProcessId(h,out p);
      if(p==pid0 && IsWindowVisible(h) && Cls(h)=="#32770"){ var t=Txt(h);
        if(t.Contains("Quantiwise")){ var c=new List<string>(); var x=new List<string>();
          EnumChildWindows(h,(k,l2)=>{ c.Add(Cls(k)); x.Add(Txt(k)); return true; }, IntPtr.Zero);
          res.Add(new object[]{ h, t, c.ToArray(), x.ToArray() }); } }
      return true; }, IntPtr.Zero);
    return res; } }
"@
}
$script:QW_KICK_BODY_MAX = 64   # rule B: longest cut body taken for a device tag ('[' + a device name fragment)
function Test-QwKickShape([string]$Title, [string[]]$Classes, [string[]]$Texts) {
  $dup = "$([char]0xC911)$([char]0xBCF5)"   # Korean 'jung-bok' (duplicate)
  foreach ($t in @($Texts)) { if ($t -and ($t -match '\(\d{1,3}(\.\d{1,3}){3}\)\]' -or $t.Contains($dup))) { return $true } }   # rule A
  if ($Title -ne 'Quantiwise7G') { return $false }                                                                              # rule B
  $btn = 0; $body = @()
  for ($i = 0; $i -lt @($Classes).Count; $i++) {
    if (@($Classes)[$i] -eq 'Button') { $btn++ }
    elseif (@($Texts)[$i] -and @($Texts)[$i].Trim().Length -gt 0) { $body += @($Texts)[$i] }
  }
  return ($btn -eq 1 -and $body.Count -eq 1 -and $body[0].StartsWith('[') -and -not $body[0].Contains(']') -and $body[0].Length -le $script:QW_KICK_BODY_MAX)
}
function Get-QwKickDialog([int]$ProcId) {
  foreach ($d in [QwKick]::Dialogs($ProcId)) { if (Test-QwKickShape ([string]$d[1]) ([string[]]$d[2]) ([string[]]$d[3])) { return [IntPtr]$d[0] } }
  return $null
}
