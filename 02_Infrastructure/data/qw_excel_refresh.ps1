<#
qw_excel_refresh.ps1 — QuantiWise 정본 xlsx 를 **우리 인프라 안에서** 갱신한다 (2026-09-18 신설)

★왜 (도훈 2026-09-18): "공표값 인터넷에서 받지말고 우리 인프라 내에서 벤치마크 캐시파일 만드는
  퀀티와이즈 파일 매일 업데이트해서 가져와. 퀀티 자동 로그인 가능하잖아"
  — 맞았다. 이 PC 안에 이미 다 있다. 찾아낸 배관을 그대로 쓴다(새로 만들지 않는다):

    (1) 단말       C:\WISEfn\Quantiwise\Quantiwise.exe   (FnGuide Quantiwise 7G)
    (2) 자동로그인 C:\WISEfn\Common\Data\maincfg.ini  [LOGIN] SAVEID=1 · SAVEUSERPW=1 · LOGINCOMPLETE=1
                   ★이 스크립트는 **플래그만** 읽는다. ID/PW 값은 읽지도 찍지도 않는다.
    (3) 엑셀 애드인 "Quantiwise For Excel" (VSTO · LoadBehavior=3)
                   HKCU\Software\Microsoft\Office\Excel\Addins\Quantiwise For Excel
    (4) 질의 시트  03_Universe/Benchmark_price.xlsx 자체가 **퀀티 질의서**다:
                   A1 = 하이퍼링크(tooltip "Quantiwise7G", 표시 "Refresh") — 따라가면 애드인이
                        SheetFollowHyperlink 를 받아 그 시트를 다시 받아온다(사람이 누르는 것과 같은 길).
                   A3 Time Series (Sector) · B4 Frequency=D · B5 Period(From)=19900103
                   B6 Period(To) = **CPD-1TD** = '직전 영업일' — 상대 토큰이라 날짜를 박을 필요가 없다.
                   B1 = "Last Update : ..." (갱신 완료의 지문)
                   지수 19계열 (코스피200 = IKS200).

  ⇒ "매일 업데이트" 는 새 크롤러가 아니라 **이 시트의 Refresh 를 누르는 일**이다.

폴백 순서(하나가 막히면 다음):
  1) A1 하이퍼링크 Follow           — 사람이 쓰는 길
  2) qwMain.QBroker.Run(8200, xl)   — 리본 'Refresh Book' 진입점(QW7menu.xml m_8200)
  3) qwMain.QBroker.Run(8100, xl)   — 'Refresh Sheet'

사용:
  powershell -NoProfile -ExecutionPolicy Bypass -File qw_excel_refresh.ps1
      -Source <원본 xlsx> -Out <결과 xlsx> [-TimeoutSec 1800] [-Visible] [-JsonOut <file>]
종료코드: 0=갱신됨 / 2=갱신 없음(이미 최신·무변화) / 3=전제 부재(단말·애드인·자동로그인 미설정) / 1=실패
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Source,
  [Parameter(Mandatory = $true)][string]$Out,
  [ValidateSet('Sheet','Book')][string]$Scope = 'Sheet',   # ★질의 시트가 여럿인 통합문서(Update_File 계열)는 Book
  [int]$TimeoutSec = 1800,
  [switch]$Visible,
  [string]$JsonOut = ''
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8; $OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$QW_EXE = 'C:\WISEfn\Quantiwise\Quantiwise.exe'
$QW_CFG = 'C:\WISEfn\Common\Data\maincfg.ini'
$ADDIN  = 'Quantiwise For Excel'
$result = [ordered]@{
  schema = 'qw_excel_refresh_v1'; at = (Get-Date).ToString('s')
  source = $Source; out = $Out; path = ''; method = ''; result = 'unknown'
  before = @{}; after = @{}; message = ''
}

function Say($m) { Write-Host "[qw_refresh] $m" }

# ★단말이 떠 있는 것과 **로그인된 것**은 다른 사실이다 (실측 2026-09-18: qwMain 은 살아 있는데
#   [[Quantiwise7_Login]] 창이 떠 있었고, 그 상태로 Refresh 를 누르면 애드인은 **캐시값을
#   그대로 되돌리며 스탬프만 갱신한다** — "성공" 처럼 보이는 무변화가 이렇게 만들어진다).
#   그래서 로그인 창의 존재를 직접 본다. 자격증명은 건드리지 않는다 — 창이 있으면 사람 몫이다.
Add-Type -Namespace QwWin -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
'@ -ErrorAction SilentlyContinue
function LoginWindowOpen {
  # ★쓰는 자리와 읽는 자리가 **같은 변수**여야 한다 — 델리게이트 안의 $script: 에 쓰고
  #   함수 지역 변수를 돌려주면 언제나 $false 다(초판의 실제 결함, 09-18 23:18 실측).
  $script:qwLoginSeen = $false
  $cb = [QwWin.U+EnumWindowsProc] {
    param($h, $l)
    if ([QwWin.U]::IsWindowVisible($h)) {
      $sb = New-Object System.Text.StringBuilder 512
      [void][QwWin.U]::GetWindowText($h, $sb, 512)
      if ($sb.ToString() -match 'Quantiwise\d*_Login') { $script:qwLoginSeen = $true }
    }
    return $true
  }
  [void][QwWin.U]::EnumWindows($cb, [IntPtr]::Zero)
  return $script:qwLoginSeen
}
function Finish([int]$code, [string]$res, [string]$msg) {
  $result.result = $res; $result.message = $msg
  if ($JsonOut) {
    try { ($result | ConvertTo-Json -Depth 6) | Out-File -FilePath $JsonOut -Encoding utf8 } catch {}
  }
  Say "결과=$res rc=$code $msg"
  exit $code
}

# --- (1) 전제 ----------------------------------------------------------------
if (-not (Test-Path $QW_EXE)) { Finish 3 'no_terminal' "단말 부재: $QW_EXE" }
if (-not (Test-Path $QW_CFG)) { Finish 3 'no_config'   "설정 부재: $QW_CFG" }

# 자동로그인 **플래그만** 본다 (값은 읽어도 어디에도 남기지 않는다)
$cfg = Get-Content $QW_CFG -Encoding Default
function CfgFlag([string]$key) {
  $line = $cfg | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -First 1
  if (-not $line) { return '' }
  return ($line -split '=', 2)[1].Trim()
}
$saveId = CfgFlag 'SAVEID'; $savePw = CfgFlag 'SAVEUSERPW'; $done = CfgFlag 'LOGINCOMPLETE'
$hasId = (CfgFlag 'ID').Length -gt 0; $hasPw = (CfgFlag 'USERPW').Length -gt 0
Say "자동로그인 플래그: SAVEID=$saveId SAVEUSERPW=$savePw LOGINCOMPLETE=$done (ID 저장=$hasId · PW 저장=$hasPw)"
if ($saveId -ne '1' -or $savePw -ne '1' -or -not $hasId -or -not $hasPw) {
  Finish 3 'no_autologin' '퀀티와이즈 자동로그인 미설정 — 단말에서 ID/PW 저장 체크 후 1회 로그인 필요(사람이 할 일)'
}

$addinKey = "HKCU:\Software\Microsoft\Office\Excel\Addins\$ADDIN"
if (-not (Test-Path $addinKey)) { Finish 3 'no_addin' "엑셀 애드인 미등록: $ADDIN" }
if (-not (Test-Path $Source))   { Finish 1 'no_source' "원본 부재: $Source" }

# --- (2) 단말 기동(자동 로그인) ----------------------------------------------
# ★단말의 실체는 qwMain.exe 다 — Quantiwise.exe 는 런처라 띄우고 **스스로 빠진다**.
#   (초판은 'Quantiwise' 만 기다리다 180초를 헛돌았다. 실측 2026-09-18: 런처 종료 · qwMain 상주)
function QwProc { Get-Process -Name 'qwMain', 'Quantiwise' -ErrorAction SilentlyContinue |
                  Sort-Object { $_.MainWindowHandle -ne 0 } -Descending | Select-Object -First 1 }
$proc = QwProc
if (-not $proc) {
  Say '단말 미기동 — 시작(저장된 자격으로 자동 로그인)'
  Start-Process -FilePath $QW_EXE | Out-Null
  $deadline = (Get-Date).AddSeconds(180)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    $proc = QwProc
    if ($proc -and $proc.MainWindowHandle -ne 0) { break }
  }
  if (-not $proc) { Finish 1 'terminal_start_failed' '단말이 뜨지 않았다' }
  Say "단말 기동 확인 ($($proc.Name) pid=$($proc.Id))"
  Start-Sleep -Seconds 20   # 로그인·세션 수립 여유
} else {
  Say "단말 이미 기동 중 ($($proc.Name) pid=$($proc.Id))"
}

if (LoginWindowOpen) {
  # 도훈 2026-09-18: "로그인 버튼 클릭까지 자동화" + "다른 컴퓨터에 로그인되어있으면 경고창까지 예 버튼을 눌러야해"
  #   ⇒ 자격증명은 단말이 채운 그대로 두고, **기본 버튼 + 중복로그인 경고의 '예'** 만 누른다.
  #     2단계 인증이 뜨면 거기서 멈춘다(rc=3) — 인증번호는 사람 몫이다.
  $clicker = Join-Path (Split-Path -Parent $PSCommandPath) 'qw_login_click.ps1'
  if (Test-Path $clicker) {
    Say '로그인 창 감지 — qw_login_click.ps1 로 세션을 연다'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $clicker -WaitSec 120
    $lrc = $LASTEXITCODE
    if ($lrc -eq 3) { Finish 3 'otp_required' '2단계 인증 대기 — 인증번호는 사람 몫이다(이 배관은 거기서 멈춘다)' }
    if ($lrc -ne 0) { Finish 3 'login_failed' ('로그인 자동화 실패 rc=' + $lrc + ' — 자격 만료·인증 대기일 수 있다. 단말에서 한 번 수동 로그인해 볼 것') }
    Start-Sleep -Seconds 5
    if (LoginWindowOpen) { Finish 3 'login_required' '로그인 자동화 뒤에도 로그인 창이 남아 있다' }
    Say '세션 열림'
  } else {
    Finish 3 'login_required' ('퀀티 단말에 로그인 창이 떠 있고 클릭 도우미가 없다: ' + $clicker)
  }
}
Say ("로그인 창 없음 — 세션 있는 것으로 본다 (LOGINCOMPLETE=" + (CfgFlag 'LOGINCOMPLETE') + ")")

# --- (3) 작업본 (정본은 제자리에서 절대 건드리지 않는다) ---------------------
$work = [System.IO.Path]::GetFullPath($Out)
Copy-Item -LiteralPath $Source -Destination $work -Force
$result.path = $work
Say "작업본 = $work"

$xl = $null; $wb = $null; $ws = $null
$preExcel = @(Get-Process -Name 'EXCEL' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
try {
  $xl = New-Object -ComObject Excel.Application
  $xl.Visible = [bool]$Visible
  $xl.DisplayAlerts = $false
  $xl.AskToUpdateLinks = $false
  $xl.EnableEvents = $true        # ★애드인 이벤트 핸들러가 살아야 한다
  $xl.ScreenUpdating = [bool]$Visible

  $connected = $false
  foreach ($a in $xl.COMAddIns) {
    if ($a.Description -eq $ADDIN -or $a.ProgId -like '*Quantiwise*') {
      if (-not $a.Connect) { $a.Connect = $true }
      $connected = $a.Connect
      Say "애드인 '$($a.Description)' Connect=$connected"
    }
  }
  if (-not $connected) { Finish 3 'addin_not_connected' '엑셀이 Quantiwise 애드인을 올리지 못했다' }

  Say "통합문서 여는 중 (큰 파일은 수 분) — $work"
  $wb = $xl.Workbooks.Open($work, 0, $false)   # UpdateLinks=0 · ReadOnly=false
  Say ("열림 — 시트 {0}개" -f $wb.Worksheets.Count)

  # --- 시트 단위 상태·판정 (Sheet/Book 공용) ----------------------------------
  #   ★Book 범위를 초판처럼 '첫 시트 스탬프 + 20초 안정' 으로 재면, 첫 시트가 끝나는 순간
  #     나머지 11개 시트가 도는 중인데 완료로 읽는다. 그래서 **시트마다** 발화·완료를 잰다.
  function SheetStateOf($sh) {
    $lr = [int]$sh.Cells($sh.Rows.Count, 1).End(-4162).Row   # xlUp
    @{ name      = [string]$sh.Name
       stamp     = [string]$sh.Range('B1').Text
       period_to = [string]$sh.Range('B6').Text
       last_row  = $lr
       last_date = [string]$sh.Cells($lr, 1).Text }          # ★지평선 = A열 마지막 날짜
  }
  function IsQuerySheet($sh) {
    try {
      if ($sh.Hyperlinks.Count -lt 1) { return $false }
      $h = $sh.Hyperlinks.Item(1)
      return ((([string]$h.ScreenTip) -match 'Quantiwise') -or (([string]$h.TextToDisplay) -match 'Refresh'))
    } catch { return $false }
  }
  function RefreshSheet($sh, [int]$tmo) {
    $b = SheetStateOf $sh
    Say ("[{0}] 갱신 전: {1} · Period(To)={2} · 마지막일={3}" -f $b.name, $b.stamp, $b.period_to, $b.last_date)
    $sh.Activate() | Out-Null
    $sh.Hyperlinks.Item(1).Follow()
    $dl = (Get-Date).AddSeconds($tmo); $chg = $null; $sig0 = "$($b.stamp)|$($b.last_row)"; $st = 0
    while ((Get-Date) -lt $dl) {
      Start-Sleep -Seconds 5
      $c = SheetStateOf $sh
      $sig = "$($c.stamp)|$($c.last_row)"
      if ($sig -ne $sig0) { $chg = Get-Date; $sig0 = $sig; $st = 0 } elseif ($chg) { $st += 5 }
      if ($chg -and $st -ge 20) { break }
    }
    $a = SheetStateOf $sh
    # ★판정은 **지평선**으로 한다. B1 스탬프는 '응답이 왔다' 는 뜻이지 '새 값이 왔다' 가 아니다
    #   (세션이 없으면 애드인은 캐시를 되돌리며 스탬프만 새로 찍는다 — 실측 09-18 23:13).
    $adv = -not ($a.last_date -eq $b.last_date -and $a.last_row -le $b.last_row)
    $note = ''; if (-not $chg) { $note = ' (응답 없음)' }
    Say ("[{0}] 갱신 후: {1} · Period(To)={2} · 마지막일={3} · 전진={4}{5}" -f $a.name, $a.stamp, $a.period_to, $a.last_date, $adv, $note)
    return @{ name = $a.name; before = $b; after = $a; responded = [bool]$chg; advanced = [bool]$adv }
  }

  # --- (4) 대상 시트 ------------------------------------------------------------
  $targets = @()
  foreach ($sh in $wb.Worksheets) { if (IsQuerySheet $sh) { $targets += $sh } }
  if ($Scope -ne 'Book' -and $targets.Count -gt 1) { $targets = @($targets[0]) }
  Say ("범위={0} · 질의 시트 {1}개 / 전체 {2}" -f $Scope, $targets.Count, $wb.Worksheets.Count)

  if ($targets.Count -eq 0) {
    # 하이퍼링크가 없는 질의서 — 리본이 부르는 진입점(QW7menu m_8200 Book / m_8100 Sheet)으로 폴백.
    $ws = $wb.Worksheets.Item(1)
    $b0 = SheetStateOf $ws
    $fired = $false
    foreach ($mid in 8200, 8100) {
      try {
        $broker = New-Object -ComObject qwMain.QBroker
        $miss = [System.Reflection.Missing]::Value
        $broker.Run([int16]$mid, $xl, $miss, $miss, $miss, $miss)
        $fired = $true; $result.method = "qbroker_run_$mid"; Say "Refresh 발화 = qwMain.QBroker.Run($mid)"
        break
      } catch { Say "QBroker.Run($mid) 실패: $($_.Exception.Message)" }
    }
    if (-not $fired) { Finish 1 'refresh_not_fired' 'Refresh 를 발화시키지 못했다(하이퍼링크 없음 · QBroker 실패)' }
    Start-Sleep -Seconds ([Math]::Min($TimeoutSec, 120))
    $a0 = SheetStateOf $ws
    $result.before = $b0; $result.after = $a0
    if ($a0.last_date -eq $b0.last_date -and $a0.last_row -le $b0.last_row) {
      $wb.Close($false) | Out-Null; $wb = $null
      Finish 2 'no_change' "지평선 불변($($a0.last_date)) — 폴백 경로"
    }
    $wb.Save(); $wb.Close($false) | Out-Null; $wb = $null
    Finish 0 'updated' "갱신 완료(폴백) ($($b0.last_date) -> $($a0.last_date))"
  }

  # --- (5) 시트마다 발화 → 완료 → 판정 ------------------------------------------
  $result.method = 'hyperlink_follow'
  $res = @(); $k = 0
  foreach ($sh in $targets) {
    $k++
    Say ("--- 시트 {0}/{1}" -f $k, $targets.Count)
    $res += ,(RefreshSheet $sh $TimeoutSec)
  }
  $result.before = $res[0].before; $result.after = $res[0].after
  $result.sheets = @($res | ForEach-Object { @{ name = $_.name; before = $_.before.last_date; after = $_.after.last_date;
                                               responded = $_.responded; advanced = $_.advanced } })
  $adv = @($res | Where-Object { $_.advanced })
  $lag = @($res | Where-Object { -not $_.advanced } | ForEach-Object { $_.name })

  if ($adv.Count -eq 0) {
    $wb.Close($false) | Out-Null; $wb = $null
    Finish 2 'no_change' ("지평선 불변 — 시트 {0}개 전부 그대로다. 세션이 없거나(로그인 창·인증 만료) 원격에 새 값이 없다." -f $res.Count)
  }
  Say ("저장 중 — 전진 시트 {0}/{1}" -f $adv.Count, $res.Count)
  $wb.Save()
  $wb.Close($false) | Out-Null; $wb = $null
  $span = "$($res[0].before.last_date) -> $($res[0].after.last_date)"
  if ($lag.Count -gt 0) {
    Finish 0 'partial' ("부분 갱신 — 전진 {0}/{1} ({2}) · 미전진: {3}" -f $adv.Count, $res.Count, $span, ($lag -join ', '))
  }
  Finish 0 'updated' ("갱신 완료 — 시트 {0}/{1} 전진 ({2})" -f $adv.Count, $res.Count, $span)
}
catch {
  $msg = $_.Exception.Message
  try { if ($wb) { $wb.Close($false) | Out-Null } } catch {}
  Finish 1 'error' $msg
}
finally {
  try { if ($xl) { $xl.Quit() } } catch {}
  foreach ($v in @($ws, $wb, $xl)) {
    try { if ($v) { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($v) } } catch {}
  }
  [GC]::Collect(); [GC]::WaitForPendingFinalizers()
  Start-Sleep -Seconds 2
  # 우리가 띄운 EXCEL 만 정리한다(사람이 쓰던 창은 건드리지 않는다)
  foreach ($p in (Get-Process -Name 'EXCEL' -ErrorAction SilentlyContinue)) {
    if ($preExcel -notcontains $p.Id) { try { $p.CloseMainWindow() | Out-Null } catch {} }
  }
}
