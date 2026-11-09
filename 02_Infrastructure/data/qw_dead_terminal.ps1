# qw_dead_terminal.ps1 — 죽은 퀀티 단말(종료를 알리는 대화상자만 남은 qwMain) 감지 · 정리
#   dot-source 전용. qw_excel_refresh.ps1 가 '단말 이미 기동 중' 판정 전에 부른다.
#   검사 = 08_Tests/data/test_qw_dead_terminal.sh (실제 메시지 창을 띄우는 양성 · 음성 대조 + 뮤테이션 테스트).
#
# 왜 (2026-11-08 메인 PC 실측): 00:38:48 EXCEL.EXE 가 0xc0000409 로 죽은 뒤 qwMain(pid 4284)은
#   '오류 — 예기치 않은 오류가 발생하였습니다. 종료합니다.' 창(#32770) 하나만 남긴 채 몇 시간 살아 있었다.
#   qw_excel_refresh.ps1 의 QwProc 는 그 창을 주 창(MainWindowHandle)으로 읽어 '단말 이미 기동 중'으로,
#   LoginWindowOpen 은 로그인 창이 없으니 '세션 있음'으로 판정한다 → 그 창이 남아 있는 한 매 밤 애드인 무응답(rc=3)
#   → 벤치 rc=3 이 Update_File(QWUF)까지 건너뛰게 한다. (ops/qw_refresh.ps1 의 QW-Alive 는 제목 기준이라 이 상태를
#   죽은 것으로 보지만, 벤치 단계가 먼저 실패해 거기까지 가지 않는다.)
#
# 판정: 대상 프로세스가 띄운 **보이는 #32770 대화상자** 가운데
#   ① 본문(버튼 밖 자식 컨트롤 글자)이 '종료합니다 | 종료됩니다 | 예기치 않은 오류' 를 담고
#   ② 예(id 6) · 아니오(id 7) 버튼이 없는 것(= 묻는 창이 아니라 알리는 창)  → 죽은 단말.
#   로그인 때의 중복 로그인 경고('…정상적으로 종료되지 않았습니다. 로그인 하시겠습니까?' · 예/아니오)는 ①②로 둘 다 빠진다.
#   다른 기기 로그인으로 끊긴 단말('…아이디 중복사용으로 프로그램을 종료…' · 확인)은 걸린다 — 도훈 11-06 상시 위임
#   "다른 기기에서 로그인 되서 종료되면 나한테 묻지말고 재로그인해" 범위다. 그 밖의 문구(계정 잠금 · 암호 요구 등)는 안 걸린다.
#
# 정리: 확인(id 1, 없으면 2)에 BM_CLICK 게시(버튼이 없으면 WM_CLOSE) = 사람이 '확인'을 누르는 것과 같다 → 단말이 스스로
#   끝나기를 $WaitSec 초 기다린다 → 남으면 강제 종료(10초 확인). PID 재사용 방지: 감지 때 본 시작 시각과 같은 프로세스만 다룬다.
#   숫자 근거: 15초 = 메시지 창 확인 뒤 VB 단말의 종료 처리 여유(실측 전 보수값 — 넘으면 강제 종료로 넘어가므로 결과는 같다).

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
namespace QwDead {
  public class Dlg { public long Hwnd; public uint Pid; public string Title = ""; public string Text = ""; public bool HasYesNo; }
  public static class W {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageTimeoutW")]
    static extern IntPtr SmtText(IntPtr h, uint msg, IntPtr w, StringBuilder l, uint flags, uint ms, out IntPtr res);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
    static extern IntPtr SmtNum(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint ms, out IntPtr res);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h, int id);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    const uint SMTO_ABORTIFHUNG = 0x0002;
    // WM_GETTEXT 는 다른 프로세스의 컨트롤 글자도 읽는다(GetWindowText 는 못 읽는다) · 멈춘 창에 묶이지 않게 시간 제한
    public static string Text(IntPtr h) {
      IntPtr n;
      if (SmtNum(h, 0x000E, IntPtr.Zero, IntPtr.Zero, SMTO_ABORTIFHUNG, 1000, out n) == IntPtr.Zero) return "";
      int len = n.ToInt32(); if (len <= 0) return "";
      var sb = new StringBuilder(len + 1); IntPtr r;
      if (SmtText(h, 0x000D, (IntPtr)(len + 1), sb, SMTO_ABORTIFHUNG, 1000, out r) == IntPtr.Zero) return "";
      return sb.ToString();
    }
    static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    public static Dlg[] Dialogs(uint[] pids) {
      var set = new HashSet<uint>(pids); var r = new List<Dlg>();
      EnumWindows(delegate (IntPtr h, IntPtr l) {
        uint q; GetWindowThreadProcessId(h, out q);
        if (!set.Contains(q) || !IsWindowVisible(h) || Cls(h) != "#32770") return true;
        var d = new Dlg(); d.Hwnd = h.ToInt64(); d.Pid = q; d.Title = Text(h);
        var parts = new List<string>();
        EnumChildWindows(h, delegate (IntPtr c, IntPtr l2) {
          if (string.Equals(Cls(c), "Button", StringComparison.OrdinalIgnoreCase)) {
            int id = GetDlgCtrlID(c); if (id == 6 || id == 7) d.HasYesNo = true;
          } else {
            var s = Text(c); if (s.Length > 0) parts.Add(s.Replace("\r", " ").Replace("\n", " ").Trim());
          }
          return true;
        }, IntPtr.Zero);
        d.Text = string.Join(" / ", parts.ToArray());
        r.Add(d); return true;
      }, IntPtr.Zero);
      return r.ToArray();
    }
  }
}
'@ -ErrorAction SilentlyContinue

$QW_DEAD_TEXT_RE = '종료합니다|종료됩니다|예기치 않은 오류'

function Get-QwDeadDialogs([int[]]$Pids) {
  # 출력: 죽음을 알리는 대화상자마다 한 개 [pid · start(감지 때 프로세스 시작 시각) · hwnd · title · text] — 없으면 출력 없음.
  #   ★부르는 쪽은 반드시 @( ) 로 감싼다: $dead = @(Get-QwDeadDialogs $pids). (초판의 `return ,$out` 는 빈 배열을 한 덩어리로
  #     내보내 @( ) 안에서 Count=1 이 됐다 — 음성 대조 L3~L5 가 전부 '감지 1' 로 나와 잡혔다 · 11-08)
  if (-not $Pids -or $Pids.Count -eq 0) { return }
  $starts = @{}
  foreach ($p in @(Get-Process -Id $Pids -ErrorAction SilentlyContinue)) {
    try { $starts[[int]$p.Id] = $p.StartTime } catch { $starts[[int]$p.Id] = $null }
  }
  if ($starts.Count -eq 0) { return }
  foreach ($d in [QwDead.W]::Dialogs([uint32[]]@($starts.Keys))) {
    if ($d.HasYesNo) { continue }                         # 묻는 창(중복 로그인 경고 등)은 죽음의 표지가 아니다
    if ($d.Text -notmatch $QW_DEAD_TEXT_RE) { continue }
    [pscustomobject]@{ pid = [int]$d.Pid; start = $starts[[int]$d.Pid]; hwnd = [long]$d.Hwnd; title = $d.Title; text = $d.Text }
  }
}

function Test-QwSameProc([int]$Id, $Start) {
  # 같은 pid · 같은 시작 시각일 때만 '그 프로세스' — 끝난 뒤 pid 가 재사용돼도 남의 프로세스를 건드리지 않는다
  $p = Get-Process -Id $Id -ErrorAction SilentlyContinue
  if (-not $p) { return $false }
  if ($null -eq $Start) { return $false }
  try { return ($p.StartTime -eq $Start) } catch { return $false }
}

function Close-QwDeadTerminal($Dead, [int]$WaitSec = 15) {
  # 반환: 'closed'(확인으로 스스로 끝남) | 'killed'(강제 종료) | 'kill_failed'
  $procs = @($Dead | Group-Object pid | ForEach-Object { $_.Group[0] })
  foreach ($d in $Dead) {
    $h = [IntPtr]$d.hwnd; $btn = [IntPtr]::Zero
    foreach ($id in 1, 2) { $btn = [QwDead.W]::GetDlgItem($h, $id); if ($btn -ne [IntPtr]::Zero) { break } }
    if ($btn -ne [IntPtr]::Zero) { [void][QwDead.W]::PostMessage($btn, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }   # BM_CLICK
    else { [void][QwDead.W]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) }                              # WM_CLOSE
  }
  $alive = { @($procs | Where-Object { Test-QwSameProc $_.pid $_.start }) }
  $deadline = (Get-Date).AddSeconds($WaitSec)
  while ((Get-Date) -lt $deadline) {
    if (@(& $alive).Count -eq 0) { return 'closed' }
    Start-Sleep -Milliseconds 500
  }
  foreach ($p in (& $alive)) { Stop-Process -Id $p.pid -Force -ErrorAction SilentlyContinue }
  $deadline = (Get-Date).AddSeconds(10)
  while ((Get-Date) -lt $deadline) {
    if (@(& $alive).Count -eq 0) { return 'killed' }
    Start-Sleep -Milliseconds 500
  }
  return 'kill_failed'
}
