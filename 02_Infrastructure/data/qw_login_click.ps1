<#
qw_login_click.ps1 — 퀀티 단말 로그인 창의 **버튼만** 눌러 세션을 연다 (2026-09-18 신설)

★경계 (도훈 2026-09-18 "로그인 버튼 클릭까지 자동화" · "다른 컴퓨터에 로그인되어있으면 경고창까지 예 버튼을 눌러야해"):
  · 이 스크립트는 **자격증명을 입력하지 않는다.** ID/PW 는 단말이 스스로 채운다
    (maincfg.ini [LOGIN] SAVEID=1 · SAVEUSERPW=1). 여기서는 폼의 기본 버튼과
    중복로그인 경고창의 '예' 만 누른다.
  · 입력칸(ThunderRT6TextBox)의 내용은 읽지 않는다 — 로그·상태 파일 어디에도 남기지 않는다.
  · **2단계 인증(OTP·모바일 인증)이 뜨면 거기서 멈춘다**(qwMain 에 frmMobileCertification 경로가 있다).
    인증번호는 사람 몫이다.

★실측 구조 (2026-09-18 23:30, 이 PC):
  · 로그인 폼 = `[[Quantiwise7_Login]]` (VB6 ThunderRT6FormDC). 버튼은 **PictureBox 이미지**라
    누를 hwnd 가 사실상 없다 ⇒ 폼을 전면에 올리고 **기본 버튼(Enter)** 을 친다.
  · 중복 로그인 경고 = 표준 대화상자 `#32770` title='Quantiwise7G'
      "[HOST(IP)]에서 사용중이거나 정상적으로 종료되지 않았습니다. 로그인 하시겠습니까?
       주의! 로그인하시면 기존 사용중이던 곳에서는 로그아웃됩니다."
      버튼: id=6 '예(&Y)' · id=7 '아니오(&N)'  ⇒ **id=6 에 BM_CLICK**.
  · ★LOGINCOMPLETE 플래그는 성공 신호가 아니다(로그인 뒤에도 0이었다). 판정은
    **로그인 폼이 사라졌는가**로 한다.

★PowerShell 함정(이 파일에서 두 번 물렸다): EnumWindows 콜백(델리게이트) 안의 Write-Output 은
  파이프라인에 안 실린다. 그래서 콜백은 **수집만** 하고 출력은 밖에서 한다.

사용: powershell -NoProfile -ExecutionPolicy Bypass -File qw_login_click.ps1 [-WaitSec 120] [-Quiet]
종료코드: 0=세션 열림(또는 원래 로그인 창 없음) / 3=2단계 인증 대기(사람 몫) / 1=실패
#>
[CmdletBinding()]
param([int]$WaitSec = 120, [switch]$Quiet)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
function Say($m) { if (-not $Quiet) { Write-Host "[qw_login] $m" } }

Add-Type -Namespace QwL -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
'@

function WinText([IntPtr]$h) {
  $sb = New-Object System.Text.StringBuilder 1024
  [void][QwL.U]::GetWindowTextW($h, $sb, 1024); $sb.ToString()
}
function WinClass([IntPtr]$h) {
  $sb = New-Object System.Text.StringBuilder 256
  [void][QwL.U]::GetClassNameW($h, $sb, 256); $sb.ToString()
}
# 보이는 최상위 창 수집 — 콜백은 담기만 한다(출력 금지).
function TopWindows {
  $script:qwRows = New-Object System.Collections.ArrayList
  $cb = [QwL.U+EnumProc] {
    param($h, $l)
    if ([QwL.U]::IsWindowVisible($h)) {
      $p = 0; [void][QwL.U]::GetWindowThreadProcessId($h, [ref]$p)
      $pn = ''
      try { $pn = (Get-Process -Id $p -ErrorAction SilentlyContinue).ProcessName } catch {}
      if ($pn -eq 'qwMain' -or $pn -eq 'Quantiwise') {
        [void]$script:qwRows.Add([pscustomobject]@{ h = $h; cls = (WinClass $h); title = (WinText $h) })
      }
    }
    return $true
  }
  [void][QwL.U]::EnumWindows($cb, [IntPtr]::Zero)
  return $script:qwRows
}
function ChildButtons([IntPtr]$dlg) {
  $script:qwBtns = New-Object System.Collections.ArrayList
  $cb = [QwL.U+EnumProc] {
    param($c, $l)
    if ((WinClass $c) -match '(?i)^button$') {
      [void]$script:qwBtns.Add([pscustomobject]@{ h = $c; id = [QwL.U]::GetDlgCtrlID($c); text = (WinText $c) })
    }
    return $true
  }
  [void][QwL.U]::EnumChildWindows($dlg, $cb, [IntPtr]::Zero)
  return $script:qwBtns
}

$LOGIN_RE = 'Quantiwise\d*_Login'
$CERT_RE = '(?i)certification|인증서|본인인증|OTP'
$BM_CLICK = 0x00F5

$rows = TopWindows
$login = $rows | Where-Object { $_.title -match $LOGIN_RE } | Select-Object -First 1
if (-not $login) { Say '로그인 창 없음 — 이미 세션이 있거나 단말이 안 떠 있다'; exit 0 }
Say ("로그인 창 발견 (hwnd={0}) — 기본 버튼을 누른다 (자격증명은 단말이 이미 채워 뒀다)" -f $login.h)

[void][QwL.U]::ShowWindow($login.h, 9)          # SW_RESTORE
[void][QwL.U]::SetForegroundWindow($login.h)
Start-Sleep -Milliseconds 700
if ([QwL.U]::GetForegroundWindow() -ne $login.h) {
  # ★전면에 못 올렸으면 키를 치지 않는다 — 남의 창에 Enter 를 보내는 일이 없어야 한다.
  Say '전면 전환 실패 — 키 입력을 보내지 않는다'
  exit 1
}
[QwL.U]::keybd_event(0x0D, 0, 0, [IntPtr]::Zero)      # VK_RETURN down
Start-Sleep -Milliseconds 80
[QwL.U]::keybd_event(0x0D, 0, 2, [IntPtr]::Zero)      # up
Say 'Enter 전송 — 경고창/세션 대기'

$deadline = (Get-Date).AddSeconds($WaitSec)
$clicked = 0
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 2
  $rows = TopWindows

  # (a) 2단계 인증 — 사람 몫이다. 건드리지 않고 멈춘다.
  $cert = $rows | Where-Object { $_.title -match $CERT_RE -and $_.title -notmatch $LOGIN_RE } | Select-Object -First 1
  if ($cert) { Say ("2단계 인증 창: '{0}' — 여기서 멈춘다(인증번호는 사람 몫)" -f $cert.title); exit 3 }

  # (b) 중복 로그인 경고 — 도훈 지시대로 '예' 를 누른다.
  $dlg = $rows | Where-Object { $_.cls -eq '#32770' } | Select-Object -First 1
  if ($dlg) {
    $btns = ChildButtons $dlg.h
    $yes = $btns | Where-Object { $_.id -eq 6 -or $_.text -match '^&?(예|Yes|확인|OK)' } | Select-Object -First 1
    if ($yes) {
      Say ("경고창 '{0}' — '{1}' 클릭 (기존 세션은 로그아웃된다)" -f $dlg.title, ($yes.text -replace '&', ''))
      [void][QwL.U]::SendMessage($yes.h, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
      $clicked++
      Start-Sleep -Seconds 2
      continue
    }
    Say ("경고창 '{0}' 에 누를 버튼을 못 찾았다 (버튼 {1}개)" -f $dlg.title, $btns.Count)
  }

  # (c) 판정 — 로그인 폼이 사라졌는가
  if (-not ($rows | Where-Object { $_.title -match $LOGIN_RE })) {
    Say ("세션 열림 (경고창 클릭 {0}회)" -f $clicked)
    exit 0
  }
}
Say ("대기 시간 안에 로그인 폼이 닫히지 않았다 (경고창 클릭 {0}회) — 자격 만료·인증 대기일 수 있다" -f $clicked)
exit 1
