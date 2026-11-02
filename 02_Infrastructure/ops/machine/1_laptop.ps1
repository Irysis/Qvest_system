<#
1_laptop.ps1 — 노트북(지금까지의 정본 기계)에서 한 번: 메인 PC 로 옮길 것을 내보내고 노트북을 보조(secondary)로 맞춘다
  (2026-11-01 두 대 운용 · 도훈 지시 "둘 다 켜져 있을 땐 메인 PC 우선")

  실행 — 보통 PowerShell(관리자 아님) · Claude 를 닫고 · OneDrive 가 '최신 상태'가 된 뒤:
    powershell -NoProfile -ExecutionPolicy Bypass -File "$env:OneDrive\Quant_Module_Moltbot\02_Infrastructure\ops\machine\1_laptop.ps1"
  메인 PC 가 올린 파일(클라우드 전용일 수 있음)을 먼저 보통 권한으로 내려받고(항상 유지) 관리자 확인(UAC)을 스스로 띄운다 —
  관리자 프로세스는 클라우드 전용 파일을 그 자리에서 못 내려받을 수 있다.
  -NoPush  커밋만 하고 GitHub 에 올리지 않는다 · -Force  Claude 가 켜져 있어도 진행

  [0] 점검 — 보조 기계인가 · OneDrive · 메인 PC 가 올린 이전 도구가 내려왔나 · Git Bash · Python · Claude 꺼짐
  [1] OneDrive 충돌 사본 정리 — 노트북 판이 이긴다(*.jsonl 은 줄 합집합) · 진 판은 Qvest_sync\conflicts\ 로 옮긴다(지우지 않음)
  [2] machines.conf 에 이 기계(secondary) · git 설정(core.checkStat minimal · core.trustctime false — 두 기계가 index 를 공유)
  [3] 자동 커밋 · 푸시 훅 가드(멱등) + 시험 4종(게이트 · 훅 회귀)
  [4] 커밋(이 작업 경로만 · 서술형 메시지) · 푸시
  [5] 내보내기 → OneDrive\Qvest_sync\from_laptop: 기계 정보 · 예약 작업 원본 · 홈 설정 파일 · 사용자 환경 변수(비밀 — 메인이
      가져간 뒤 지운다) · Claude 사용자 설정 · R 패키지 묶음(메인에 없거나 판이 다른 것만) · pip freeze · 도구 판
  [6] 이 기계 예약 작업을 게이트 실행기로 감싼다(메인이 살아 있으면 메인이 돈다)
  [7] Claude 메모리 → OneDrive\Qvest_sync\claude_memory 연결(두 기계 공유)
  [8] 항상 이 장치에 유지(핵심 폴더)
  [9] 대조표(manifest.tsv) — 메인이 OneDrive 사본을 바이트 단위로 맞춰 본다 · 마지막에 DONE.txt(내보낸 파일 목록)
다시 돌려도 같은 결과(끝난 단계는 그대로 지나간다). 로그 = OneDrive\Qvest_sync\logs\.
#>
param([switch]$NoPush, [switch]$Force, [switch]$Elevated)
trap {
  Write-Host ''
  Write-Host "  ERROR $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "        $($_.InvocationInfo.PositionMessage)"
  Finish 1
}
. (Join-Path $PSScriptRoot 'qvest_setup_common.ps1')
$pass = @(); if ($NoPush) { $pass += '-NoPush' }; if ($Force) { $pass += '-Force' }
$preRoot = Join-Path $PSScriptRoot '..\..\..'                                  # 메인 PC 가 올리거나 바꾼 파일 — 관리자 창 전에 이 장치로
$n = Wait-Local @($PSScriptRoot, (Join-Path $preRoot '08_Tests\ops\test_qvest_machine.sh'),
  (Join-Path $preRoot '02_Infrastructure\hooks\auto_commit_on_stop.sh'), (Join-Path $preRoot '02_Infrastructure\hooks\auto_push_on_stop.sh')) 20
if ($n) { Stop-Here "메인 PC 가 올린 파일 $n 개가 아직 이 장치에 없음(항상 유지로 표시함 — OneDrive 가 내려받는 중) — “최신 상태” 뒤 다시" }
Assert-Admin $PSCommandPath $pass

$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..')).TrimEnd('\')
$MDirW = Join-Path $Root '02_Infrastructure\ops\machine'
$Conf = Join-Path $MDirW 'machines.conf'
$Tool = Join-Path $MDirW 'qvest_sync.py'
$TasksPs1 = Join-Path $MDirW 'qvest_tasks.ps1'
$McU = ConvertTo-Fwd (Join-Path $MDirW 'qvest_machine.sh')
$RPkgs = ConvertTo-Fwd (Join-Path $MDirW 'r_packages.R')
$Venv = Join-Path $Root '.venv_qvest_ml\Scripts\python.exe'

Write-Host "Qvest 두 대 운용 — 1단계(노트북) · $env:COMPUTERNAME · $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$OD = "$env:OneDrive".TrimEnd('\')
if (-not $OD -or -not $Root.StartsWith($OD + '\', [StringComparison]::OrdinalIgnoreCase)) {
  Stop-Here "프로젝트($Root)가 이 계정의 OneDrive($OD) 안에 있지 않음 — 노트북 사용자 계정으로 실행(관리자 권한 확인에 '예')"
}
$Sync = Join-Path $OD 'Qvest_sync'
$Out = Join-Path $Sync 'from_laptop'
$Logs = Join-Path $Sync 'logs'
[void](New-Item -ItemType Directory -Force -Path $Logs)
try { Start-Transcript -Path (Join-Path $Logs "1_laptop_$($env:COMPUTERNAME)_$Stamp.log") | Out-Null } catch { }

# ---------------------------------------------------------------- [0]
Step '0' '점검'
if (-not (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)) { Stop-Here 'OneDrive 가 꺼져 있음 — 켜고 “최신 상태”가 된 뒤 다시' }
$miss = @(@('qvest_machine.sh', 'qvest_tasks.ps1', 'qvest_sync.py', 'r_packages.R', 'install_hook_guard.sh', 'machines.conf', '2_main.ps1',
    'README.md') | Where-Object { -not (Test-Path -LiteralPath (Join-Path $MDirW $_)) })
if (-not (Test-Path -LiteralPath (Join-Path $Root '08_Tests\ops\test_qvest_machine.sh'))) { $miss += '08_Tests\ops\test_qvest_machine.sh' }
if ($miss.Count) { Stop-Here "메인 PC 가 올린 이전 도구가 아직 안 내려옴: $($miss -join ', ') — OneDrive “최신 상태” 뒤 다시" }
Ok '메인 PC 가 올린 이전 도구 도착'
$Bash = Find-GitBash
if (-not $Bash) { Stop-Here 'Git Bash 없음(C:\Program Files\Git\bin\bash.exe)' }
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { Stop-Here 'git 없음' }
$role = "$((Run $Bash @($McU, 'role')).Out | Select-Object -Last 1)".Trim()
if ($role -eq 'main') { Stop-Here "이 기계($env:COMPUTERNAME)는 machines.conf 에서 main — 이 스크립트는 노트북용(메인은 2_main.ps1)" }
Ok "기계 $env:COMPUTERNAME · 역할 $role · 프로젝트 $Root"
$Py = $null
foreach ($c in @($env:QVEST_PY, $Venv, (Find-BasePython))) { if ($c -and (Test-Py $c)) { $Py = $c; break } }
if (-not $Py) { Stop-Here 'Python 없음(QVEST_PY · venv · 기본 설치 모두 실패)' }
Ok "Python $Py"
$cl = @(Get-Process -Name claude -ErrorAction SilentlyContinue)
if ($cl.Count -and -not $Force) {
  Stop-Here 'Claude 가 켜져 있음 — 닫고 다시(세션 기록 · 자동 커밋이 이전과 겹친다). 그대로 하려면 -Force'
}
$mainNames = @(Get-ConfMachines $Conf 'main')
$me = @(Get-HostNames)
Ok "메인 = $($mainNames -join ', ') · 이 기계 이름 = $($me -join ', ')"

# ---------------------------------------------------------------- [1]
Step '1' 'OneDrive 충돌 사본 정리(노트북 판이 이긴다)'
$a = @($Tool, 'conflicts', $Root)
foreach ($d in @($mainNames + $me)) { $a += @('--device', $d) }
foreach ($w in $me) { $a += @('--winner', $w) }
$a += @('--stash', (Join-Path $Sync "conflicts\laptop_$Stamp"), '--apply')
$r = Run $Py $a -Show
if ($r.Rc -eq 3) { Stop-Here '.git 안 충돌 사본(또는 정리 오류)이 있음 — 위 GIT · ERROR 줄을 Claude 에 보여 주세요(사람이 판단)' }
if ($r.Rc -ne 0) { Stop-Here "충돌 사본 정리 실패(rc=$($r.Rc))" }
Info ('동기화 상태: ' + "$((Run $Bash @($McU, 'settled')).Out | Select-Object -Last 1)")

# ---------------------------------------------------------------- [2]
Step '2' 'machines.conf · git 설정'
$lines = @([IO.File]::ReadAllLines($Conf, $Utf8))
$mine = @($lines | Where-Object { $_ -match "^\s*machine\s+$([regex]::Escape($env:COMPUTERNAME))\s" })
if ($mine.Count) { Ok "machines.conf 에 이미 있음: $($mine[0].Trim())" }
else {
  $nl = $(if ([IO.File]::ReadAllText($Conf, $Utf8) -match "`r`n") { "`r`n" } else { "`n" })
  $last = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*machine\s') { $last = $i } }
  $new = New-Object Collections.Generic.List[string]
  $new.AddRange([string[]]$lines)
  $entry = "machine $($env:COMPUTERNAME) secondary"
  if ($last -ge 0) { $new.Insert($last + 1, $entry) } else { $new.Add($entry) }
  Write-Utf8 $Conf (($new -join $nl) + $nl)
  Ok "machines.conf += $entry"
}
foreach ($kv in @(@('core.checkStat', 'minimal'), @('core.trustctime', 'false'))) {
  $g = Run 'git' @('-C', $Root, 'config', $kv[0], $kv[1])
  if ($g.Rc -eq 0) { Ok "git config $($kv[0]) $($kv[1])" } else { Warn "git config $($kv[0]) 실패: $($g.Text)" }
}

# ---------------------------------------------------------------- [3]
Step '3' '자동 커밋 · 푸시 훅 가드 + 시험'
$gi = Run $Bash @((ConvertTo-Fwd (Join-Path $MDirW 'install_hook_guard.sh'))) -Show
if ($gi.Rc -ne 0) { Warn "가드 끼우기 문제(rc=$($gi.Rc)) — 위 줄 확인" }
if (-not $env:QVEST_PY) { $env:QVEST_PY = $Py }
$results = @()
foreach ($t in @('08_Tests/ops/test_qvest_machine.sh', '08_Tests/hooks/test_auto_commit_valve.sh',
    '08_Tests/hooks/test_auto_commit_session_scope.sh', '08_Tests/hooks/test_auto_commit_worktree_target.sh')) {
  Info "시험 $t …"
  $tr = Invoke-BashTest $Bash $Root $t
  $results += $tr
  if ($tr.Ok) { Ok ('{0} pass={1} fail={2}' -f $t, $tr.Pass, $tr.Fail) }
  else { Warn ('{0} 실패 rc={1} pass={2} fail={3}' -f $t, $tr.Rc, $tr.Pass, $tr.Fail); Write-Host $tr.Tail }
}
$testsOk = (@($results | Where-Object { -not $_.Ok }).Count -eq 0)

# ---------------------------------------------------------------- [4]
Step '4' '커밋 · 푸시(이 작업 경로만)'
$paths = @('02_Infrastructure/ops/machine', '08_Tests/ops/test_qvest_machine.sh')
$hooksIn = 0
foreach ($h in @('02_Infrastructure/hooks/auto_commit_on_stop.sh', '02_Infrastructure/hooks/auto_push_on_stop.sh')) {
  $ns = Run 'git' @('-C', $Root, 'diff', '--numstat', 'HEAD', '--', $h)
  $row = @($ns.Out | Where-Object { $_ -match '^\d+\s+\d+\s' } | Select-Object -First 1)
  if ($row.Count -eq 0) { continue }                                  # HEAD 와 같음(가드가 이미 커밋돼 있음)
  $nAdd, $nDel = @($row[0] -split '\s+')[0, 1]
  $blk = 0; $in = $false
  foreach ($l in [IO.File]::ReadAllLines((Join-Path $Root $h))) {
    if ($l.StartsWith('# >>> QVEST_MACHINE_SETTLE >>>')) { $in = $true }
    if ($in) { $blk++ }
    if ($l.StartsWith('# <<< QVEST_MACHINE_SETTLE <<<')) { break }
  }
  if ([int]$nDel -eq 0 -and [int]$nAdd -eq $blk) { $paths += $h; $hooksIn++ }
  else { Warn "$h — 가드 말고 다른 미커밋 변경(+$nAdd/-$nDel)도 있어 이번 커밋에서 뺐다(노트북 작업 보존 · 따로 정리)" }
}
if (-not $testsOk) { Warn '시험 실패가 있어 커밋 · 푸시를 건너뜀 — 위 결과를 Claude 에 보여 주세요(가드는 메인과 같은 판으로 남겨 둠)' }
else {
  [void](Run 'git' (@('-C', $Root, 'add', '--') + $paths))
  $st = Run 'git' (@('-C', $Root, 'status', '--porcelain', '--') + $paths)
  if (-not @($st.Out | Where-Object { "$_".Trim() }).Count) { Ok '커밋할 변경 없음(이미 커밋됨)' }
  else {
    $verify = ($results | ForEach-Object { '{0} {1}/{2}' -f ($_.Name -replace '^.*/', ''), $_.Pass, ($_.Pass + $_.Fail) }) -join ' · '
    $hookLine = $(if ($hooksIn -gt 0) { "- SessionEnd 자동 커밋 · 푸시 훅 $hooksIn 종에 '동기화 안정' 가드 블록(QVEST_MACHINE_SETTLE — 안정 아니면 SKIP_UNSETTLED)" }
      else { '- (훅 가드는 이미 커밋됐거나 노트북 미커밋 변경과 섞여 이번 커밋에서 뺐다)' })
    $msg = @"
두 대 운용(메인 PC 우선) — 기계 역할 · 예약 작업 게이트 · 동기화 안정 가드 · 노트북→메인 이전 도구

무엇
- 02_Infrastructure/ops/machine/ 신설: machines.conf(기계 → 역할) · qvest_machine.sh(역할 · 생존 신호 · 게이트 · settled)
  · qvest_tasks.ps1(예약 작업을 게이트 실행기로 감싸 등록 · 되돌림 · 내보내기 · 생존 신호) · install_hook_guard.sh
  · qvest_sync.py(대조표 · OneDrive 충돌 사본 정리 · 항상 유지) · r_packages.R(R 패키지 판 맞추기)
  · 1_laptop.ps1 · 2_main.ps1 · qvest_setup_common.ps1(이전 1회분) · README.md
- 08_Tests/ops/test_qvest_machine.sh(게이트 · 생존 신호 · settled)
$hookLine

왜
- 2026-11-01 도훈 지시: "메인 PC 나 노트북 둘 중 하나를 켜더라도 Qvest 문제없이 작업 가능하게 · 둘 다 켜져 있을 땐
  메인 PC 우선". 작업 트리(.git 포함)를 OneDrive 로 공유하므로 ① 같은 예약 작업이 두 기계에서 겹쳐 돌지 않게(메인 우선
  게이트) ② 반쯤 내려온 트리를 커밋 · 푸시하지 않게(가드) ③ 이전 결과를 바이트 대조로 확인한다(대조표).

검증
- 노트북 $($env:COMPUTERNAME) 실측(1_laptop.ps1): $verify
- 메인 PC 실측(게이트 34 · 훅 회귀 19/51/28 · qvest_sync compare 14 · conflicts 19 · 작업 스케줄러 실물 18/18) = README.md 검사 절

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
"@
    $mf = Join-Path $env:TEMP "qvest_commit_$Stamp.txt"
    Write-Utf8 $mf ($msg -replace "`r`n", "`n")
    $c = Run 'git' (@('-C', $Root, 'commit', '-F', $mf, '--') + $paths) -Show
    Remove-Item -LiteralPath $mf -Force -ErrorAction SilentlyContinue
    if ($c.Rc -eq 0) { Ok '커밋' } else { Warn "커밋 실패(rc=$($c.Rc)) — 위 줄 확인" }
  }
  $up = Run 'git' @('-C', $Root, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
  if ($up.Rc -ne 0) { Warn '추적하는 원격 브랜치 없음 — 푸시 생략' }
  elseif ($NoPush) { Info '-NoPush — 푸시 생략' }
  else {
    [void](Run 'git' @('-C', $Root, 'fetch', '--quiet'))
    $lr = Run 'git' @('-C', $Root, 'rev-list', '--left-right', '--count', 'HEAD...@{u}')
    $ab = @("$($lr.Out | Select-Object -Last 1)".Trim() -split '\s+')
    if ($lr.Rc -ne 0 -or $ab.Count -lt 2) { Warn '원격과 비교 실패 — 푸시 생략(나중에 git push)' }
    elseif ([int]$ab[1] -gt 0) { Warn "원격이 $($ab[1]) 커밋 앞서 있음 — 푸시 생략(git pull 뒤 git push)" }
    elseif ([int]$ab[0] -eq 0) { Ok '원격과 같음 — 올릴 것 없음' }
    else {
      $p = Run 'git' @('-C', $Root, 'push') -Show
      if ($p.Rc -eq 0) { Ok "푸시 $($ab[0]) 커밋" } else { Warn "푸시 실패(rc=$($p.Rc)) — 나중에 git push" }
    }
  }
}

# ---------------------------------------------------------------- [5]
Step '5' "내보내기 → $Out"
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
[void](New-Item -ItemType Directory -Force -Path $Out)
$Rs = Find-Rscript
$RHome = Get-RHomeDir $Rs
$rh = ''; $rlib = ''; $rver = ''
if ($Rs) {
  $ri = Run $Rs @('--no-init-file', '-e', 'cat(R.home(), Sys.getenv(''R_LIBS_USER''), as.character(getRversion()), sep=''\n'')')
  $o = @($ri.Out | Where-Object { "$_".Trim() })
  if ($o.Count -ge 3) { $rh, $rlib, $rver = $o[-3], $o[-2], $o[-1] }
}
$head = "$((Run 'git' @('-C', $Root, 'rev-parse', 'HEAD')).Out | Select-Object -Last 1)".Trim()
$info = [ordered]@{
  computername = $env:COMPUTERNAME; dnshost = [Net.Dns]::GetHostName(); user = $env:USERNAME
  sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value; userprofile = $env:USERPROFILE.TrimEnd('\')
  onedrive = $OD; root = $Root; time = (Get-Date -Format s); stamp = $Stamp; head = $head; python = $Py
  rscript = $Rs; r_home = $rh; r_libs_user = $rlib; r_version = $rver; r_home_dir = $RHome
}
Write-Utf8 (Join-Path $Out 'machine.txt') ((($info.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n") + "`n")
Ok "기계 정보 · HEAD $head · R $rver"

$tc = Invoke-QvestTasks $TasksPs1 @{ Mode = 'Export'; Out = (Join-Path $Out 'tasks'); Root = $Root }
$nTasks = @(Get-ChildItem -LiteralPath (Join-Path $Out 'tasks') -Filter *.xml -ErrorAction SilentlyContinue).Count
if ($tc -eq 0) { Ok "예약 작업 $nTasks 개 원본 XML" } else { Warn "예약 작업 내보내기 일부 실패(rc=$tc)" }

$homeList = New-Object Collections.Generic.List[string]
foreach ($c in @(@('profile', $env:USERPROFILE, @('.gitconfig', '.bash_profile', '.bashrc', '.profile', '.inputrc', '.minttyrc')),
    @('r', $RHome, @('.Renviron', '.Rprofile', '.R\Makevars.win', '.R\Makevars')))) {
  foreach ($rel in $c[2]) {
    $src = Join-Path $c[1] $rel
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }
    $dst = Join-Path $Out "home\$($c[0])\$rel"
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent))
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $homeList.Add("$($c[0])`t$($rel -replace '\\', '/')")
  }
}
if ($homeList.Count) { Write-Utf8 (Join-Path $Out 'home\_list.txt') (($homeList -join "`n") + "`n") }
Ok "홈 설정 파일 $($homeList.Count)개: $(($homeList | ForEach-Object { ($_ -split "`t")[1] }) -join ' ')"

$opt = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
$envList = @()
foreach ($n in $k.GetValueNames()) {
  if (@('Path', 'TEMP', 'TMP', 'QVEST_MACHINE_ROLE') -contains $n -or $n -like 'OneDrive*') { continue }
  $envList += [pscustomobject]@{ name = $n; kind = $k.GetValueKind($n).ToString(); value = [string]$k.GetValue($n, $null, $opt) }
}
Write-Utf8 (Join-Path $Out 'secrets\user_env.json') (ConvertTo-Json -InputObject @($envList) -Depth 3)
Write-Utf8 (Join-Path $Out 'user_path.txt') ([string]$k.GetValue('Path', '', $opt))
$k.Close()
Ok "사용자 환경 변수 $($envList.Count)개(이름만): $(($envList | ForEach-Object { $_.name }) -join ' ')"

$cd = Join-Path $env:USERPROFILE '.claude'
$cOut = Join-Path $Out 'claude'
$copied = @()
foreach ($f in @('settings.json', 'CLAUDE.md', 'keybindings.json')) {
  $s = Join-Path $cd $f
  if (Test-Path -LiteralPath $s -PathType Leaf) {
    [void](New-Item -ItemType Directory -Force -Path $cOut); Copy-Item -LiteralPath $s -Destination (Join-Path $cOut $f); $copied += $f
  }
}
foreach ($d in @('agents', 'commands', 'skills', 'output-styles', 'hooks')) {
  $s = Join-Path $cd $d
  if (Test-Path -LiteralPath $s -PathType Container) {
    [void](New-Item -ItemType Directory -Force -Path $cOut); Copy-Item -LiteralPath $s -Destination (Join-Path $cOut $d) -Recurse -Force; $copied += "$d\"
  }
}
Ok "Claude 사용자 설정: $(if ($copied.Count) { $copied -join ' ' } else { '없음' })"

if (-not $Rs) { Warn 'R 없음 — R 패키지 묶음 생략' }
else {
  $rl = Join-Path $Out 'r_lib'
  [void](New-Item -ItemType Directory -Force -Path $rl)
  [void](Run $Rs @('--no-init-file', $RPkgs, 'inventory', (ConvertTo-Fwd (Join-Path $rl 'r_packages.csv'))) -Show)
  $other = ''
  foreach ($m in $mainNames) { $p = Join-Path $Root ".cache\machine\r_packages_$m.csv"; if (Test-Path -LiteralPath $p) { $other = $p; break } }
  $ba = @('--no-init-file', $RPkgs, 'bundle', (ConvertTo-Fwd $rl))
  if ($other) { $ba += (ConvertTo-Fwd $other) } else { Warn '메인 R 목록(.cache\machine\r_packages_<메인>.csv) 없음 — 전부 묶는다' }
  $b = Run $Rs $ba -Show
  if ($b.Rc -ne 0) { Warn "R 묶음 목록 실패(rc=$($b.Rc))" }
  else {
    foreach ($row in @([IO.File]::ReadAllLines((Join-Path $rl 'libs.tsv')) | Select-Object -Skip 1)) {
      $col = $row -split "`t"
      if ($col.Count -lt 3 -or [int]$col[2] -eq 0) { continue }
      $tgz = Join-Path $rl "lib$($col[0]).tgz"
      $t = Run $Tar @('-czf', $tgz, '-C', $col[1], '-T', (Join-Path $rl "lib$($col[0]).txt"))
      if ($t.Rc -eq 0) { Ok ('R 묶음 lib{0}: {1}개 · {2:N1} MB ← {3}' -f $col[0], $col[2], ((Get-Item -LiteralPath $tgz).Length / 1MB), $col[1]) }
      else { Warn "tar 실패 lib$($col[0]): $($t.Text)" }
    }
  }
}

if (Test-Path -LiteralPath $Venv) {
  $pf = Run $Venv @('-m', 'pip', 'freeze')
  Write-Utf8 (Join-Path $Out 'pip_freeze.txt') ((@($pf.Out) -join "`n") + "`n")
  Ok "pip freeze $(@($pf.Out).Count)줄(venv 는 OneDrive 로 함께 간다 — 기록용)"
}

$tools = New-Object Collections.Generic.List[string]
$probe = [ordered]@{ git = @('--version'); Rscript = @('--version'); python = @('--version'); node = @('--version'); npm = @('--version')
  uv = @('--version'); java = @('-version'); quarto = @('--version'); pandoc = @('--version'); claude = @('--version')
  codex = @('--version'); gh = @('--version'); 'nvidia-smi' = @('--query-gpu=name,driver_version', '--format=csv,noheader') }
$tools.Add("bash`t$Bash`t$("$((Run $Bash @('--version')).Out | Select-Object -First 1)".Trim())")
foreach ($e in $probe.GetEnumerator()) {
  $g = Get-Command $e.Key -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch '\\WindowsApps\\' } | Select-Object -First 1
  if ($null -eq $g) { $tools.Add("$($e.Key)`t-`t-"); continue }
  $v = @((Run $g.Source $e.Value).Out | Where-Object { "$_".Trim() } | Select-Object -First 1)
  $tools.Add("$($e.Key)`t$($g.Source)`t$(if ($v.Count) { "$($v[0])".Trim() } else { '?' })")
}
foreach ($rt in @('C:\rtools45', 'C:\rtools44', 'C:\rtools43')) { if (Test-Path -LiteralPath $rt) { $tools.Add("rtools`t$rt`tpresent") } }
Write-Utf8 (Join-Path $Out 'tools.txt') (($tools -join "`n") + "`n")
$npm = Get-Command npm -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $npm) { Write-Utf8 (Join-Path $Out 'npm_global.txt') (((Run $npm.Source @('ls', '-g', '--depth=0')).Out -join "`n") + "`n") }
Ok "도구 판: $(($tools | Where-Object { ($_ -split "`t")[1] -ne '-' } | ForEach-Object { ($_ -split "`t")[0] }) -join ' ')"

$gitInfo = @('## log') + (Run 'git' @('-C', $Root, 'log', '-5', '--format=%h %ad %s', '--date=iso')).Out +
  @('## status') + (Run 'git' @('-C', $Root, 'status', '-sb')).Out + @('## remote') + (Run 'git' @('-C', $Root, 'remote', '-v')).Out
Write-Utf8 (Join-Path $Out 'git.txt') (($gitInfo -join "`n") + "`n")

# ---------------------------------------------------------------- [6]
Step '6' '이 기계 예약 작업 → 게이트 실행기로 감싸기(보조 — 메인이 살아 있으면 메인이 돈다)'
if ($nTasks -eq 0) { Info '감쌀 예약 작업 없음' }
else {
  $ac = Invoke-QvestTasks $TasksPs1 @{ Mode = 'Apply'; From = (Join-Path $Out 'tasks'); Root = $Root }
  if ($ac -eq 0) { Ok '감싸기 끝 — 로그온 방식 InteractiveToken(로그인해 있을 때만 돈다 · 암호를 저장하지 않음)' }
  else { Warn "감싸기 일부 실패(rc=$ac) — 위 FAIL 줄 확인" }
}

# ---------------------------------------------------------------- [7]
Step '7' 'Claude 메모리 → OneDrive 공유 폴더'
$shared = Join-Path $Sync 'claude_memory'
Set-MemoryJunction (Join-Path $env:USERPROFILE (".claude\projects\" + (Get-ProjectKey $Root) + '\memory')) $shared $env:COMPUTERNAME
Set-PinnedFolder $shared

# ---------------------------------------------------------------- [8]
Step '8' '항상 이 장치에 유지'
$pr = Invoke-Pin $Py $Tool $Root 25
if ($pr.Rc -ne 0) { Warn "항상 유지 일부 실패(rc=$($pr.Rc)) — 위 attrib 줄 확인" }

# ---------------------------------------------------------------- [9]
Step '9' '대조표(메인이 OneDrive 사본을 바이트 단위로 맞춰 본다)'
$mw = Run $Py @($Tool, 'write', $Root, (Join-Path $Out 'manifest.tsv')) -Show
if ($mw.Rc -ne 0) { Stop-Here "대조표 쓰기 실패(rc=$($mw.Rc))" }
$nf = Write-FileList $Out (Join-Path $Out 'DONE.txt') @("qvest_export v1 host=$($env:COMPUTERNAME) stamp=$Stamp time=$(Get-Date -Format s) head=$head")
Ok "DONE.txt — 내보낸 파일 $nf 개(크기 · 해시)"

Write-Host ''
Write-Host '노트북 1단계 끝.' -ForegroundColor Green
Write-Host '  1. 작업 표시줄 OneDrive 아이콘이 “최신 상태”가 될 때까지 노트북을 켜 두세요(10-20 이후 작업 · 대조표 · R 묶음을 올린다).'
Write-Host '  2. 그동안 이 노트북에서 Claude · R · 다른 작업을 하지 마세요. “최신 상태”가 되면 꺼도(절전) 됩니다.'
Write-Host '  3. 그다음 메인 PC 에서 2_main.ps1(관리자 PowerShell).'
Finish 0
