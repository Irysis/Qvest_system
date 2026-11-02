<#
2_main.ps1 — 메인 PC 에서 한 번(노트북 1_laptop.ps1 이 끝나고 OneDrive 가 '최신 상태'가 된 뒤): 노트북에서 내보낸 것을
  가져오고 메인 PC 를 main(우선)으로 세운다 (2026-11-01 두 대 운용 · 도훈 지시 "둘 다 켜져 있을 땐 메인 PC 우선")

  실행 — 보통 PowerShell(관리자 아님):
    powershell -NoProfile -ExecutionPolicy Bypass -File "$env:OneDrive\Quant_Module_Moltbot\02_Infrastructure\ops\machine\2_main.ps1"
  노트북 내보내기 · 공유 메모리(클라우드 전용)를 먼저 보통 권한으로 내려받고(항상 유지) 관리자 확인(UAC)을 스스로 띄운다 —
  관리자 프로세스는 클라우드 전용 파일을 그 자리에서 못 내려받을 수 있다.
  -SkipR  R 패키지 생략 · -SkipPin  항상 유지 생략 · -NoTasks  예약 작업 · 생존 신호 등록 생략

  [0] 점검 — main 인가 · OneDrive · 노트북 내보내기가 목록(DONE.txt)대로 다 내려왔나 · Python · Git Bash
  [1] 항상 이 장치에 유지 — OneDrive 가 뒤에서 내려받기 시작(충돌 정리 · 대조 [10] 가 읽을 파일)
  [2] OneDrive 충돌 사본 정리(노트북 판이 이긴다 · *.jsonl 은 줄 합집합 · 진 판은 Qvest_sync\conflicts\ 로)
  [3] 경로 연결 C:\Users\<노트북 사용자> → 이 PC 사용자 폴더(코드 · venv · 예약 작업이 박아 둔 경로가 그대로 맞는다)
  [4] 사용자 환경 변수 — 이름만 표시 · 기존 값 백업(%LOCALAPPDATA%\Qvest\env_backup_*.json) · 가져온 뒤 OneDrive 사본 삭제
  [5] 홈 설정 파일(.Renviron · .gitconfig …) — 다르면 기존 것을 <이름>.main_bak_<시각> 으로 두고 바꾼다
  [6] Claude 사용자 설정 — 없는 것만 더한다 · 다른 것은 메인 것 유지 + 곁에 *.laptop 사본
  [7] Claude 메모리 → OneDrive 공유 폴더 연결(실제 경로 · 연결 경로 두 프로젝트 키 모두)
  [8] 도구 — 노트북에 있고 여기 없는 것(uv 는 winget 설치 · 나머지는 목록)
  [9] R 패키지 — 노트북 판 그대로(묶음) · 묶음에 없으면 CRAN
  [10] 대조 — OneDrive 사본이 노트북 대조표와 바이트 단위로 같은가(어떤 git 명령보다 먼저: git 은 .git/index 를 다시 쓴다)
  [11] 일치: 보류 표식 해제 → 예약 작업 등록(게이트) → 생존 신호(메인 우선) / 불일치: 보류 유지 · 나중에 다시
  [12] 확인 — venv torch · CUDA · R 패키지 · 게이트 상태 · git
다시 돌려도 같은 결과(이미 가져온 묶음은 건너뛴다). 로그 = OneDrive\Qvest_sync\logs\.
#>
param([switch]$SkipR, [switch]$SkipPin, [switch]$NoTasks, [switch]$Elevated)
trap {
  Write-Host ''
  Write-Host "  ERROR $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "        $($_.InvocationInfo.PositionMessage)"
  Finish 1
}
. (Join-Path $PSScriptRoot 'qvest_setup_common.ps1')
$pass = @(); if ($SkipR) { $pass += '-SkipR' }; if ($SkipPin) { $pass += '-SkipPin' }; if ($NoTasks) { $pass += '-NoTasks' }
$preSync = Join-Path "$env:OneDrive".TrimEnd('\') 'Qvest_sync'                 # 노트북이 올린 것 — 관리자 창 전에 이 장치로([0] 이 다시 확인)
[void](Wait-Local @((Join-Path $preSync 'from_laptop'), (Join-Path $preSync 'claude_memory')) 30)
Assert-Admin $PSCommandPath $pass

function Send-SettingChange {
  if (-not ('Qvest.Native' -as [type])) {
    Add-Type -Namespace Qvest -Name Native -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
  }
  $res = [UIntPtr]::Zero
  [void][Qvest.Native]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 0x0002, 5000, [ref]$res)
}
function Add-Consumed([string]$part) { [IO.File]::AppendAllText($ConsumedFile, "$part`n", $Utf8); $script:Consumed += $part }

Write-Host "Qvest 두 대 운용 — 2단계(메인 PC) · $env:COMPUTERNAME · $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$OD = "$env:OneDrive".TrimEnd('\')
$RealRoot = Join-Path $OD 'Quant_Module_Moltbot'
if (-not $OD -or -not (Test-Path -LiteralPath (Join-Path $RealRoot '02_Infrastructure\ops\machine\2_main.ps1'))) {
  Stop-Here "이 계정의 OneDrive($OD)에 Quant_Module_Moltbot 이 없음 — 메인 PC 사용자 계정으로 실행(관리자 권한 확인에 '예')"
}
$MDirW = Join-Path $RealRoot '02_Infrastructure\ops\machine'
$Conf = Join-Path $MDirW 'machines.conf'
$Tool = Join-Path $MDirW 'qvest_sync.py'
$TasksPs1 = Join-Path $MDirW 'qvest_tasks.ps1'
$McU = ConvertTo-Fwd (Join-Path $MDirW 'qvest_machine.sh')
$RPkgs = ConvertTo-Fwd (Join-Path $MDirW 'r_packages.R')
$Sync = Join-Path $OD 'Qvest_sync'
$Out = Join-Path $Sync 'from_laptop'
$Logs = Join-Path $Sync 'logs'
$MyProfile = $env:USERPROFILE.TrimEnd('\')
$ConsumedFile = Join-Path $Out '_consumed.txt'
[void](New-Item -ItemType Directory -Force -Path $Logs)
try { Start-Transcript -Path (Join-Path $Logs "2_main_$($env:COMPUTERNAME)_$Stamp.log") | Out-Null } catch { }

# ---------------------------------------------------------------- [0]
Step '0' '점검'
if (-not (Get-Process -Name OneDrive -ErrorAction SilentlyContinue)) { Stop-Here 'OneDrive 가 꺼져 있음 — 켜고 “최신 상태”가 된 뒤 다시' }
$Bash = Find-GitBash
if (-not $Bash) { Stop-Here 'Git Bash 없음(C:\Program Files\Git\bin\bash.exe)' }
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { Stop-Here 'git 없음' }
$role = "$((Run $Bash @($McU, 'role')).Out | Select-Object -Last 1)".Trim()
if ($role -ne 'main') { Stop-Here "이 기계($env:COMPUTERNAME)가 machines.conf 에서 main 이 아님(역할 $role)" }
$Py = Find-BasePython
if (-not $Py) { Stop-Here 'Python 3 기본 설치 없음(%LOCALAPPDATA%\Programs\Python) — python.org 3.12 설치 뒤 다시' }
Ok "기계 $env:COMPUTERNAME · 역할 main · Python $Py"
$done = Join-Path $Out 'DONE.txt'
if (-not (Test-Path -LiteralPath $done)) {
  Stop-Here "노트북 내보내기 표식 없음($done) — 노트북 1_laptop.ps1 이 끝나고 OneDrive “최신 상태”가 된 뒤 다시"
}
$n = Wait-Local @($Out, (Join-Path $Sync 'claude_memory')) 30
if ($n) { Stop-Here "노트북 내보내기 · 공유 메모리 중 $n 개가 아직 이 장치에 없음(항상 유지로 표시함 — OneDrive 가 내려받는 중) — “최신 상태” 뒤 다시" }
$Consumed = @()
if (Test-Path -LiteralPath $ConsumedFile) { $Consumed = @([IO.File]::ReadAllLines($ConsumedFile, $Utf8) | Where-Object { $_.Trim() }) }
Info '노트북 내보내기 확인(크기 · 해시) …'
$bad = Test-FileList $Out $done $Consumed
if ($bad.Count) {
  $bad | Select-Object -First 10 | ForEach-Object { Info $_ }
  Stop-Here "노트북 내보내기가 아직 다 안 내려옴($($bad.Count)개) — OneDrive “최신 상태” 뒤 다시"
}
$L = Read-KeyValue (Join-Path $Out 'machine.txt')
$LapProfile = "$($L.userprofile)".TrimEnd('\')
$CanonRoot = "$($L.root)".TrimEnd('\')
if (-not $LapProfile -or -not $CanonRoot.StartsWith($LapProfile + '\', [StringComparison]::OrdinalIgnoreCase)) {
  Stop-Here "machine.txt 의 root($CanonRoot)가 userprofile($LapProfile) 아래가 아님"
}
if (($MyProfile + $CanonRoot.Substring($LapProfile.Length)) -ine $RealRoot) {
  Stop-Here "노트북 경로($CanonRoot)를 이 PC 의 $RealRoot 로 이을 수 없음(사용자 폴더 아래 상대 경로가 다름)"
}
Ok "노트북 $($L.computername) · 내보낸 시각 $($L.time) · HEAD $($L.head) · 공통 경로 $CanonRoot"
if (@(Get-Process -Name Rterm, Rgui, rsession, rstudio -ErrorAction SilentlyContinue).Count) { Warn 'R · RStudio 가 켜져 있음 — R 패키지 교체가 막힐 수 있다(닫고 다시 돌리면 그 단계만 다시 한다)' }
if (@(Get-Process -Name claude -ErrorAction SilentlyContinue).Count) { Info 'Claude 가 켜져 있음 — 이 스크립트가 끝나면 Claude 를 완전히 닫았다 다시 여세요' }

# ---------------------------------------------------------------- [1]
Step '1' '항상 이 장치에 유지(OneDrive 가 뒤에서 내려받기 시작)'
if ($SkipPin) { Info '-SkipPin — 건너뜀' }
else {
  $pr = Invoke-Pin $Py $Tool $RealRoot 25
  if ($pr.Rc -ne 0) { Warn "항상 유지 일부 실패(rc=$($pr.Rc)) — 위 줄 확인" }
}

# ---------------------------------------------------------------- [2]
Step '2' 'OneDrive 충돌 사본 정리(노트북 판이 이긴다)'
$lapNames = @(@($L.computername, $L.dnshost) | Where-Object { $_ } | Select-Object -Unique)
$devs = @(@(Get-HostNames) + @(Get-ConfMachines $Conf) + $lapNames | Where-Object { $_ } | Select-Object -Unique)
$a = @($Tool, 'conflicts', $RealRoot)
foreach ($d in $devs) { $a += @('--device', $d) }
foreach ($w in $lapNames) { $a += @('--winner', $w) }
$a += @('--stash', (Join-Path $Sync "conflicts\main_$Stamp"), '--apply')
$r = Run $Py $a -Show
if ($r.Rc -eq 3) {
  if ($r.Text -match '(?m)^GIT ') { Stop-Here '.git 안 충돌 사본이 있음 — 위 GIT 줄을 Claude 에 보여 주세요(사람이 판단)' }
  Stop-Here '충돌 사본 일부를 못 읽음(아직 클라우드 전용일 수 있음 — [1] 이 항상 유지로 표시함) — OneDrive “최신 상태” 뒤 다시(되풀이되면 위 ERROR 줄을 Claude 에)'
}
if ($r.Rc -ne 0) { Stop-Here "충돌 사본 정리 실패(rc=$($r.Rc))" }

# ---------------------------------------------------------------- [3]
Step '3' "경로 연결 $LapProfile → $MyProfile"
if ($LapProfile -ieq $MyProfile) { Ok '노트북과 사용자 폴더 경로가 같음 — 연결 불필요' }
else {
  $jt = Get-JunctionTarget $LapProfile
  if ($jt) {
    if ($jt -ieq $MyProfile) { Ok "이미 연결: $LapProfile -> $MyProfile" }
    else { Stop-Here "$LapProfile 가 다른 곳($jt)에 연결돼 있음 — 확인 뒤 다시" }
  } elseif (Test-Path -LiteralPath $LapProfile) {
    Stop-Here "$LapProfile 가 실제 폴더로 있음(다른 사용자 계정?) — 비우거나 이름을 바꾼 뒤 다시"
  } else {
    [void](New-Item -ItemType Junction -Path $LapProfile -Value $MyProfile)
    Ok "연결: $LapProfile -> $MyProfile"
  }
  $probe = ".cache\machine\junction_probe_$Stamp.txt"
  Write-Utf8 (Join-Path $RealRoot $probe) $Stamp
  $seen = (Test-Path -LiteralPath (Join-Path $CanonRoot $probe)) -and ([IO.File]::ReadAllText((Join-Path $CanonRoot $probe)) -eq $Stamp)
  Remove-Item -LiteralPath (Join-Path $RealRoot $probe) -Force
  if (-not $seen) { Stop-Here "연결 확인 실패 — $CanonRoot 로 같은 폴더가 보이지 않음" }
  Ok "확인: $CanonRoot = $RealRoot"
}

# ---------------------------------------------------------------- [4]
Step '4' '사용자 환경 변수(이름만 표시)'
$envFile = Join-Path $Out 'secrets\user_env.json'
if ($Consumed -contains 'secrets') { Ok '이미 가져옴 — 건너뜀' }
elseif (-not (Test-Path -LiteralPath $envFile)) { Warn 'user_env.json 없음 — 건너뜀' }
else {
  $opt = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
  $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
  $bk = Join-Path $env:LOCALAPPDATA "Qvest\env_backup_$Stamp.json"
  $old = @(foreach ($n in $k.GetValueNames()) { [pscustomobject]@{ name = $n; kind = $k.GetValueKind($n).ToString(); value = [string]$k.GetValue($n, $null, $opt) } })
  Write-Utf8 $bk (ConvertTo-Json -InputObject $old -Depth 3)
  $items = Get-Content -LiteralPath $envFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $set = @(); $same = 0; $noPath = @()
  foreach ($it in $items) {
    if (@('String', 'ExpandString') -notcontains $it.kind) { Warn "환경 변수 $($it.name): 종류 $($it.kind) — 건너뜀"; continue }
    $cur = $k.GetValue($it.name, $null, $opt)
    if ($null -ne $cur -and [string]$cur -ceq [string]$it.value) { $same++ }
    else { $k.SetValue($it.name, [string]$it.value, [Microsoft.Win32.RegistryValueKind]$it.kind); $set += $it.name }
    $exp = [Environment]::ExpandEnvironmentVariables([string]$it.value)
    [Environment]::SetEnvironmentVariable($it.name, $exp, 'Process')
    if ($exp -match '^[A-Za-z]:[\\/]' -and $exp -notmatch '[;|*?]' -and -not (Test-Path -LiteralPath $exp)) { $noPath += $it.name }
  }
  $norm = {
    param($e)
    $x = [Environment]::ExpandEnvironmentVariables($e).TrimEnd('\')
    if ($x.StartsWith($LapProfile + '\', [StringComparison]::OrdinalIgnoreCase)) { $x = $MyProfile + $x.Substring($LapProfile.Length) }
    $x.ToLowerInvariant()
  }
  $mainPath = [string]$k.GetValue('Path', '', $opt)
  $keep = @($mainPath -split ';' | Where-Object { $_.Trim() })
  $have = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($e in $keep) { [void]$have.Add((& $norm $e.Trim())) }
  $add = @(); $nope = @()
  $pf = Join-Path $Out 'user_path.txt'
  if (Test-Path -LiteralPath $pf) {
    foreach ($e in ([IO.File]::ReadAllText($pf, $Utf8).Trim() -split ';')) {
      $e = $e.Trim(); if (-not $e) { continue }
      $n = & $norm $e
      if ($have.Contains($n)) { continue }
      if (-not (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($e)))) { $nope += $e; continue }
      $add += $e; [void]$have.Add($n)
    }
  }
  if ($add.Count) {
    $k.SetValue('Path', (@($keep) + $add) -join ';', [Microsoft.Win32.RegistryValueKind]::ExpandString)
    Ok "Path += $($add.Count)개: $($add -join ' ; ')"
  }
  if ($nope.Count) { Info "노트북 Path 중 이 PC 에 없는 경로 $($nope.Count)개(건너뜀): $($nope -join ' ; ')" }
  $ensure = [ordered]@{ QM_ROOT = $CanonRoot; QVEST_PY = (Join-Path $CanonRoot '.venv_qvest_ml\Scripts\python.exe'); PYTHONUTF8 = '1' }
  foreach ($n in $ensure.Keys) {
    if ($null -eq $k.GetValue($n, $null)) { $k.SetValue($n, $ensure[$n], [Microsoft.Win32.RegistryValueKind]::String); $set += $n }
    [Environment]::SetEnvironmentVariable($n, [Environment]::ExpandEnvironmentVariables([string]$k.GetValue($n, '')), 'Process')
  }
  $k.Close()
  Send-SettingChange
  Remove-Item -LiteralPath (Join-Path $Out 'secrets') -Recurse -Force
  Add-Consumed 'secrets'
  Ok "환경 변수 바꿈 $($set.Count)개 · 같음 $same 개 — $($set -join ' ')"
  Info "기존 값 백업: $bk · OneDrive 사본(secrets) 삭제함"
  if ($noPath.Count) { Warn "이 PC 에 없는 경로를 가리키는 환경 변수: $($noPath -join ' ')" }
}

# ---------------------------------------------------------------- [5]
Step '5' '홈 설정 파일'
$Rs = Find-Rscript
$hl = Join-Path $Out 'home\_list.txt'
if ($Consumed -contains 'home') { Ok '이미 가져옴 — 건너뜀' }
elseif (-not (Test-Path -LiteralPath $hl)) { Info '노트북 홈 설정 파일 없음' }
else {
  $RHomeMain = Get-RHomeDir $Rs
  foreach ($l in [IO.File]::ReadAllLines($hl, $Utf8)) {
    $c = $l -split "`t"
    if ($c.Count -lt 2) { continue }
    $src = Join-Path $Out ("home\$($c[0])\" + ($c[1] -replace '/', '\'))
    $base = $(if ($c[0] -eq 'r') { $RHomeMain } else { $MyProfile })
    $dst = Join-Path $base ($c[1] -replace '/', '\')
    if (Test-Path -LiteralPath $dst) {
      if (Test-SameFile $src $dst) { Ok "같음 $($c[1])"; continue }
      Copy-Item -LiteralPath $dst -Destination "$dst.main_bak_$Stamp"
      Copy-Item -LiteralPath $src -Destination $dst -Force
      Ok "바꿈 $($c[1]) → $base (기존 = $([IO.Path]::GetFileName($dst)).main_bak_$Stamp)"
    } else {
      [void](New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent))
      Copy-Item -LiteralPath $src -Destination $dst
      Ok "새로 $($c[1]) → $base"
    }
  }
  Remove-Item -LiteralPath (Join-Path $Out 'home') -Recurse -Force
  Add-Consumed 'home'
  Info 'OneDrive 사본(home) 삭제함'
}

# ---------------------------------------------------------------- [6]
Step '6' 'Claude 사용자 설정(없는 것만 더한다)'
$cIn = Join-Path $Out 'claude'
$cd = Join-Path $MyProfile '.claude'
if ($Consumed -contains 'claude') { Ok '이미 가져옴 — 건너뜀' }
elseif (-not (Test-Path -LiteralPath $cIn)) { Info '노트북 Claude 사용자 설정 없음' }
else {
  [void](New-Item -ItemType Directory -Force -Path $cd)
  $ls = Join-Path $cIn 'settings.json'
  if (Test-Path -LiteralPath $ls) {
    $ms = Join-Path $cd 'settings.json'
    if (-not (Test-Path -LiteralPath $ms)) { Copy-Item -LiteralPath $ls -Destination $ms; Ok 'settings.json 새로' }
    else {
      $lj = Get-Content -LiteralPath $ls -Raw -Encoding UTF8 | ConvertFrom-Json
      $mj = Get-Content -LiteralPath $ms -Raw -Encoding UTF8 | ConvertFrom-Json
      $added = @(); $differ = @()
      foreach ($p in $lj.PSObject.Properties) {
        $mp = $mj.PSObject.Properties[$p.Name]
        if ($null -eq $mp) { $mj | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value; $added += $p.Name }
        elseif ((ConvertTo-Json -InputObject $mp.Value -Depth 30 -Compress) -ne (ConvertTo-Json -InputObject $p.Value -Depth 30 -Compress)) { $differ += $p.Name }
      }
      if ($added.Count) { Copy-Item -LiteralPath $ms -Destination "$ms.main_bak_$Stamp"; Write-Utf8 $ms ($mj | ConvertTo-Json -Depth 30) }
      Copy-Item -LiteralPath $ls -Destination (Join-Path $cd 'settings.laptop.json') -Force
      Ok "settings.json — 더한 키: $(if ($added.Count) { $added -join ' ' } else { '없음' }) · 노트북 원본 = settings.laptop.json"
      if ($differ.Count) { Warn "Claude settings.json 키 $($differ -join ', ') 가 노트북과 다름 — 메인 값 유지(노트북 값 = ~\.claude\settings.laptop.json)" }
    }
  }
  $new = 0; $diff = @()
  foreach ($f in @(Get-ChildItem -LiteralPath $cIn -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($cIn.Length + 1)
    if ($rel -ieq 'settings.json') { continue }
    $dst = Join-Path $cd $rel
    if (-not (Test-Path -LiteralPath $dst)) {
      [void](New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent)); Copy-Item -LiteralPath $f.FullName -Destination $dst; $new++
    } elseif (-not (Test-SameFile $f.FullName $dst)) {
      $alt = Join-Path (Split-Path $dst -Parent) ('{0}.laptop{1}' -f [IO.Path]::GetFileNameWithoutExtension($dst), [IO.Path]::GetExtension($dst))
      Copy-Item -LiteralPath $f.FullName -Destination $alt -Force; $diff += $rel
    }
  }
  Ok "Claude 설정 파일 새로 $new 개 · 다름 $($diff.Count)개"
  if ($diff.Count) { Warn "Claude 사용자 설정 중 노트북과 다른 파일(메인 것 유지 · 곁에 *.laptop 사본): $($diff -join ', ')" }
  Remove-Item -LiteralPath $cIn -Recurse -Force
  Add-Consumed 'claude'
}

# ---------------------------------------------------------------- [7]
Step '7' 'Claude 메모리 → OneDrive 공유 폴더'
$shared = Join-Path $Sync 'claude_memory'
if (-not (Test-Path -LiteralPath $shared)) { Warn "노트북 공유 메모리($shared) 없음 — 이 PC 메모리로 새로 만든다" }
foreach ($key in @(@((Get-ProjectKey $RealRoot), (Get-ProjectKey $CanonRoot)) | Select-Object -Unique)) {
  Set-MemoryJunction (Join-Path $cd "projects\$key\memory") $shared $env:COMPUTERNAME
}
Set-PinnedFolder $shared

# ---------------------------------------------------------------- [8]
Step '8' '도구(노트북에 있고 여기 없는 것)'
$tf = Join-Path $Out 'tools.txt'
if (-not (Test-Path -LiteralPath $tf)) { Info 'tools.txt 없음' }
else {
  $missing = @()
  foreach ($l in [IO.File]::ReadAllLines($tf, $Utf8)) {
    $c = $l -split "`t"
    if ($c.Count -lt 3 -or $c[1] -eq '-') { continue }
    $here = $(switch ($c[0]) {
        'bash' { $Bash }
        'rtools' { if (Test-Path -LiteralPath $c[1]) { $c[1] } }
        default { Get-Command $c[0] -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch '\\WindowsApps\\' } | Select-Object -First 1 }
      })
    if (-not $here) { $missing += [pscustomobject]@{ Name = $c[0]; Ver = $c[2]; Path = $c[1] } }
  }
  if (-not $missing.Count) { Ok '노트북 도구가 모두 있음' }
  foreach ($m in $missing) {
    if ($m.Name -eq 'uv' -and (Get-Command winget -ErrorAction SilentlyContinue)) {
      Info 'uv 설치(winget — 약관 동의를 물으면 직접 답하세요)'
      & winget install --id astral-sh.uv -e
      if ($LASTEXITCODE -eq 0) { Ok 'uv 설치' } else { Warn "uv 설치 실패(rc=$LASTEXITCODE) — 나중에 winget install --id astral-sh.uv -e" }
    } else { Warn "노트북에 있고 이 PC 에 없는 도구: $($m.Name) ($($m.Ver) · 노트북 $($m.Path))" }
  }
}

# ---------------------------------------------------------------- [9]
Step '9' 'R 패키지(노트북 판 그대로)'
$rl = Join-Path $Out 'r_lib'
if ($SkipR) { Info '-SkipR — 건너뜀' }
elseif ($Consumed -contains 'r_lib') { Ok '이미 맞춤 — 건너뜀' }
elseif (-not (Test-Path -LiteralPath (Join-Path $rl 'r_packages.csv'))) { Info '노트북 R 목록 없음 — 건너뜀' }
elseif (-not $Rs) { Warn 'R 없음 — R 4.5 설치(cran.r-project.org) 뒤 2_main.ps1 다시' }
else {
  $mv = "$((Run $Rs @('--no-init-file', '-e', 'cat(as.character(getRversion()))')).Out | Select-Object -Last 1)".Trim()
  if ("$($L.r_version)" -and ($mv -replace '\.\d+$', '') -ne ("$($L.r_version)" -replace '\.\d+$', '')) {
    Warn "R 판이 다름(노트북 $($L.r_version) · 메인 $mv) — 묶음 바이너리가 맞지 않을 수 있다(같은 4.x 판으로 맞추기 권장)"
  }
  $ex = Join-Path $env:LOCALAPPDATA 'Qvest\r_lib_extract'
  if (Test-Path -LiteralPath $ex) { Remove-Item -LiteralPath $ex -Recurse -Force }
  [void](New-Item -ItemType Directory -Force -Path $ex)
  foreach ($t in @(Get-ChildItem -LiteralPath $rl -Filter 'lib*.tgz' -ErrorAction SilentlyContinue)) {
    $x = Run $Tar @('-xzf', $t.FullName, '-C', $ex)
    if ($x.Rc -eq 0) { Ok "풀기 $($t.Name)" } else { Warn "풀기 실패 $($t.Name): $($x.Text)" }
  }
  $rr = Run $Rs @('--no-init-file', $RPkgs, 'restore', (ConvertTo-Fwd (Join-Path $rl 'r_packages.csv')), (ConvertTo-Fwd $ex)) -Show
  if ($rr.Rc -eq 0) {
    Remove-Item -LiteralPath $ex -Recurse -Force
    Get-ChildItem -LiteralPath $rl -Filter 'lib*.tgz' -ErrorAction SilentlyContinue | Remove-Item -Force
    Add-Consumed 'r_lib'
    Ok 'R 패키지 맞춤 끝(묶음 삭제)'
  } else { Warn "R 패키지 일부를 못 맞춤(rc=$($rr.Rc)) — 위 MISSING · COPY_FAIL 줄 확인(R 을 닫고 다시 돌리면 이 단계만 다시)" }
}

# ---------------------------------------------------------------- [10]
Step '10' '대조 — OneDrive 사본 = 노트북 대조표?(어떤 git 명령보다 먼저)'
Info '추적 파일 · .git 을 전부 읽는다 — OneDrive 가 아직 내려받는 중이면 그만큼 기다린다'
$report = Join-Path $Sync "main_compare_$Stamp.txt"
$cr = Run $Py @($Tool, 'compare', $RealRoot, (Join-Path $Out 'manifest.tsv'), '--allow', 'qepm/observability/events.jsonl', '--report', $report) -Show
$match = ($cr.Rc -eq 0)

# ---------------------------------------------------------------- [11]
Step '11' $(if ($match) { '일치 — 보류 해제 · 예약 작업 · 생존 신호' } else { '불일치 — 보류 유지' })
$hold = Join-Path $RealRoot ".cache\machine\hold_$($env:COMPUTERNAME)"
if (-not $match) {
  Warn "아직 노트북 작업이 다 안 내려옴(목록: $report) — 보류 표식 유지 · 예약 작업 등록 안 함. OneDrive “최신 상태” 뒤 2_main.ps1 다시"
} else {
  Ok '노트북 작업이 모두 도착(바이트 일치)'
  $gd = Run 'git' @('-C', $CanonRoot, 'rev-parse', '--git-dir')
  if ($gd.Rc -ne 0 -and $gd.Text -match 'dubious ownership') {            # 연결 경로로 열 때 소유자 확인에 걸리면
    foreach ($sd in @((ConvertTo-Fwd $CanonRoot), (ConvertTo-Fwd $RealRoot))) { [void](Run 'git' @('config', '--global', '--add', 'safe.directory', $sd)) }
    Info 'git safe.directory 등록(연결 경로 · 실제 경로)'
  }
  $hv = $null
  if (Test-Path -LiteralPath $hold) { $hv = [IO.File]::ReadAllText($hold); Remove-Item -LiteralPath $hold -Force }
  $s = Run $Bash @($McU, 'settled', (ConvertTo-Fwd $CanonRoot))
  $sl = "$($s.Out | Select-Object -Last 1)".Trim()
  if ($s.Rc -ne 0) {
    if ($null -ne $hv) { Write-Utf8 $hold $hv }
    Warn "아직 안정 아님($sl) — 보류 표식을 되살림(자동 커밋 · 푸시 계속 멈춤). 잠시 뒤 2_main.ps1 다시"
  } else { Ok "보류 해제 — 자동 커밋 · 푸시 재개 · $sl" }
  if ($NoTasks) { Info '-NoTasks — 예약 작업 · 생존 신호 등록 건너뜀' }
  else {
    $ac = Invoke-QvestTasks $TasksPs1 @{ Mode = 'Apply'; From = (Join-Path $Out 'tasks'); Root = $CanonRoot }
    if ($ac -eq 0) { Ok '예약 작업 등록(게이트 · InteractiveToken)' } else { Warn "예약 작업 등록 일부 실패(rc=$ac) — 위 FAIL 줄 확인" }
    $hc = Invoke-QvestTasks $TasksPs1 @{ Mode = 'Heartbeat'; Root = $CanonRoot }
    if ($hc -eq 0) { Ok '생존 신호 등록(5분 + 로그온) — 이제 메인이 우선' } else { Warn "생존 신호 등록 실패(rc=$hc)" }
    $gTasks = @(Get-ScheduledTask | Where-Object { ((@($_.Actions) | ForEach-Object { "$($_.Execute) $($_.Arguments) $($_.WorkingDirectory)" }) -join ' ') -match 'G:\\Quant_Module_Moltbot' })
    if ($gTasks.Count) { Info "옛 G: 경로 예약 작업 $($gTasks.Count)개는 꺼 둔 채 남김: $(($gTasks | ForEach-Object { $_.TaskName }) -join ', ')" }
  }
}

# ---------------------------------------------------------------- [12]
Step '12' '확인'
$vpy = Join-Path $CanonRoot '.venv_qvest_ml\Scripts\python.exe'
if (Test-Path -LiteralPath $vpy) {
  $tv = Run $vpy @('-c', 'import sys, torch; print(sys.version.split()[0], torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else chr(45))')
  if ($tv.Rc -eq 0) { Ok "venv(python · torch · CUDA · GPU): $("$($tv.Out | Select-Object -Last 1)".Trim())" } else { Warn "venv 실행 실패: $(@($tv.Out | Select-Object -Last 2) -join ' / ')" }
} else { Warn "venv 없음: $vpy" }
if ($Rs) {
  $rp = Run $Rs @('--no-init-file', '-e', 'x <- c(''data.table'', ''arrow'', ''PerformanceAnalytics'', ''jsonlite''); cat(paste0(x, ''='', vapply(x, requireNamespace, logical(1), quietly = TRUE)), sep = '' '')')
  Info "R 패키지: $("$($rp.Out | Select-Object -Last 1)".Trim())"
}
$ms = Run $Bash @($McU, 'status')
$ms.Out | ForEach-Object { Info $_ }
if ($match) {
  $gs = Run 'git' @('--no-optional-locks', '-C', $CanonRoot, 'status', '-sb')
  Info "git: $(@($gs.Out | Select-Object -First 1) -join '') · 바뀐 파일 $(@($gs.Out).Count - 1)개"
  Info 'GitHub 연결 확인 — 로그인 창이 뜨면 로그인하세요'
  $lr = Run 'git' @('-C', $CanonRoot, 'ls-remote', '--heads', 'origin')
  if ($lr.Rc -eq 0) { Ok "GitHub 연결: 브랜치 $(@($lr.Out | Where-Object { $_ -match 'refs/heads/' }).Count)개" } else { Warn 'GitHub 연결 실패 — 첫 git push 때 로그인 필요' }
}

Write-Host ''
if ($match) {
  Write-Host '메인 PC 2단계 끝.' -ForegroundColor Green
  Write-Host '  1. Claude 앱을 완전히 닫았다 다시 여세요(환경 변수 · 메모리 연결 반영).'
  Write-Host "  2. 세션 폴더 = $CanonRoot (노트북과 같은 경로 — 연결) → /qvest"
  Write-Host '  3. 앞으로: 두 기계에서 Claude 를 동시에 쓰지 않기 · 기계를 바꿀 땐 OneDrive “최신 상태”를 본 뒤 시작.'
} else {
  Write-Host '메인 PC 2단계 — 대조가 아직 불일치라 보류 상태로 멈춤.' -ForegroundColor Yellow
  Write-Host '  OneDrive 아이콘이 “최신 상태”가 되면 2_main.ps1 을 다시 돌리세요(끝난 단계는 건너뛴다).'
}
Finish $(if ($match) { 0 } else { 2 })
