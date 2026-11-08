<#
qvest_setup_common.ps1 — 1_laptop.ps1 · 2_main.ps1 공통 도우미 (점 찍어 불러 쓴다 · 단독 실행 안 함 · 2026-11-01 두 대 운용)
  출력 · 멈춤 · 관리자 다시 띄우기 · 외부 명령 실행(종료 코드 + 줄) · 도구 찾기 · Claude 메모리 합치기 · 연결(junction) · 항상 유지 ·
  OneDrive 내려받기 기다림(Wait-Local — 관리자 프로세스의 그 자리 내려받기에 기대지 않는다).
  PowerShell 5.1: 외부 명령 인자에 큰따옴표를 넣지 않는다(5.1 은 이스케이프하지 않아 인자가 갈라진다 — 2026-11-01 실측).
#>
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }
$OutputEncoding = New-Object Text.UTF8Encoding($false)
$env:PYTHONUTF8 = '1'
$Utf8 = New-Object Text.UTF8Encoding($false)
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Tar = Join-Path $env:SystemRoot 'System32\tar.exe'
$script:Warns = New-Object Collections.Generic.List[string]

# 그 기계에 꼭 남길 것 · 남기지 않을 것(항상 이 장치에 유지 — qvest_sync.py pin) = 데이터 · 실행 필수.
# 결과물 폴더(04_Research · stage_artifacts — 메인 11-03 실측 14.2 · 34.1 GB)는 핵심이 아니다: 메인은 그 안의 대조표 파일만
# 남기고(-Files) 나머지는 열 때 내려받는다(도훈 11-03 '전체 유지는 원치 않음 — 용량')
$PinExclude = @('01_Literature', '99_Archive', '_deleted_FreshIdea', '.claude/worktrees', '.pip_cache', 'catboost_info')
$PinEssential = @('.git', '.venv_qvest_ml', '.cache', '.claude', '.github', '00_Lawbook', '02_Infrastructure', '03_Universe',
  '05_Production', '06_Registry', '08_Tests', 'qepm')

function Assert-Admin([string]$scriptPath, [string[]]$passArgs) {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $scriptPath + '"'), '-Elevated') + $passArgs
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $a
  Write-Host '관리자 권한 창(UAC 확인)에서 이어 갑니다 — 이 창은 닫아도 됩니다.'
  exit 0
}

function Step([string]$n, [string]$t) { Write-Host ''; Write-Host ('[{0}] {1}' -f $n, $t) -ForegroundColor Cyan }
function Ok([string]$t) { Write-Host "  OK    $t" -ForegroundColor Green }
function Info([string]$t) { Write-Host "  ..    $t" }
function Warn([string]$t) { Write-Host "  WARN  $t" -ForegroundColor Yellow; $script:Warns.Add($t) }

function Finish([int]$rc) {
  if ($script:Warns.Count -gt 0) {
    Write-Host ''
    Write-Host "확인할 것 $($script:Warns.Count)개:" -ForegroundColor Yellow
    foreach ($w in $script:Warns) { Write-Host "  - $w" -ForegroundColor Yellow }
  }
  try { Stop-Transcript | Out-Null } catch { }
  if ($script:Elevated) { Write-Host ''; [void](Read-Host '창을 닫으려면 Enter') }
  exit $rc
}

function Stop-Here([string]$t) {
  Write-Host "  STOP  $t" -ForegroundColor Red
  Write-Host ''
  Write-Host '멈췄습니다 — 위 사유를 해결한 뒤 같은 명령으로 다시 실행하세요(끝난 단계는 그대로 지나갑니다).' -ForegroundColor Red
  Finish 1
}

# 외부 명령: 표준 출력 + 오류를 줄로 모으고(-Show 면 바로 찍음) 종료 코드를 돌려준다. 창이 따로 뜨는 대화형 명령은 쓰지 않는다.
function Run([string]$Exe, [string[]]$Argv = @(), [switch]$Show) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $lines = New-Object Collections.Generic.List[string]
  $rc = 0
  try {
    & $Exe @Argv 2>&1 | ForEach-Object {
      $l = "$_"
      $lines.Add($l)
      if ($Show) { Write-Host "        $l" }
    }
    $rc = $LASTEXITCODE
  } catch {
    $lines.Add($_.Exception.Message); $rc = 255
    if ($Show) { Write-Host "        $($_.Exception.Message)" }
  } finally { $ErrorActionPreference = $old }
  if ($null -eq $rc) { $rc = 0 }
  return [pscustomobject]@{ Rc = [int]$rc; Out = $lines.ToArray(); Text = ($lines -join "`n") }
}

function Write-Utf8([string]$path, [string]$text) {
  [void](New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent))
  [IO.File]::WriteAllText($path, $text, $Utf8)
}

function Find-GitBash {
  $c = @()
  if ($env:ProgramFiles) { $c += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') }
  $g = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($null -ne $g) { $c += (Join-Path (Split-Path (Split-Path $g.Source -Parent) -Parent) 'bin\bash.exe') }
  foreach ($p in $c) { if (Test-Path -LiteralPath $p) { return $p } }   # System32\bash.exe(WSL)는 쓰지 않는다
  return $null
}

function Test-Py([string]$p) {
  if (-not $p -or -not (Test-Path -LiteralPath $p)) { return $false }
  return ((Run $p @('-c', 'import hashlib, json, re, shutil')).Rc -eq 0)        # 기능 프로브 — WindowsApps 스텁은 실패
}

# 기본 설치 Python(OneDrive 밖 · venv 아님) — 연결 · 내려받기 전에도 돈다
function Find-BasePython {
  $c = @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python3*\python.exe') -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending | ForEach-Object { $_.FullName })
  foreach ($p in $c) { if (Test-Py $p) { return $p } }
  return $null
}

function Find-Rscript {
  $c = @()
  if ($env:ProgramFiles) {
    $c += (Join-Path $env:ProgramFiles 'R\R-4.6.2\bin\Rscript.exe')
    $c += @(Get-ChildItem -Path (Join-Path $env:ProgramFiles 'R\R-*\bin\Rscript.exe') -ErrorAction SilentlyContinue |
        Sort-Object { $v = [version]'0.0'; [void][version]::TryParse(($_.FullName -replace '^.*\\R-([0-9.]+)\\bin\\.*$', '$1'), [ref]$v); $v } -Descending |
        ForEach-Object { $_.FullName })
  }
  foreach ($p in $c) { if (Test-Path -LiteralPath $p) { return $p } }
  return $null
}

function Get-RHomeDir([string]$rs) {
  if (-not $rs) { return $env:USERPROFILE }
  $r = Run $rs @('--no-init-file', '-e', 'cat(path.expand(''~''))')
  $h = @($r.Out | Where-Object { $_ -match '^[A-Za-z]:' } | Select-Object -First 1)
  if ($r.Rc -eq 0 -and $h.Count -gt 0) { return ($h[0].Trim() -replace '/', '\') }
  return $env:USERPROFILE
}

function Read-KeyValue([string]$path) {
  $h = @{}
  if (Test-Path -LiteralPath $path) {
    foreach ($l in [IO.File]::ReadAllLines($path, $Utf8)) { $i = $l.IndexOf('='); if ($i -gt 0) { $h[$l.Substring(0, $i).Trim()] = $l.Substring($i + 1).Trim() } }
  }
  return $h
}

function Get-ProjectKey([string]$path) { return ($path.TrimEnd('\') -replace '[^A-Za-z0-9]', '-') }   # ~/.claude/projects/<키>

function Get-JunctionTarget([string]$p) {
  $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  if ($null -eq $i -or "$($i.LinkType)" -ne 'Junction') { return $null }
  return ([string](@($i.Target)[0])).TrimEnd('\')
}

# 이 계정의 OneDrive 폴더 — 사용자 환경 변수(레지스트리)에서 읽는다: OneDrive 위치를 옮긴(다시 연결한) 뒤에도 그 전에 연 창의
# $env:OneDrive 는 옛 값이다(11-03 메인 G: 이전)
function Get-OneDriveRoot {
  $v = [Environment]::GetEnvironmentVariable('OneDrive', 'User')
  if (-not $v) { $v = $env:OneDrive }
  return "$v".TrimEnd('\')
}

# 노트북 공통 경로(machine.txt 의 userprofile · onedrive · root) → 이 PC 실제 경로. 사용자 폴더 연결(C:\Users\<노트북 사용자> → 이 PC
# 사용자 폴더)로 잇고, OneDrive 를 사용자 폴더 밖(예 G:\OneDrive)으로 옮겼으면 사용자 폴더의 OneDrive 자리 → 그 위치를 하나 더
# 잇는다(OdMoved). Err 가 있으면 이을 수 없다.
function Get-PathPlan([hashtable]$L, [string]$myProfile, [string]$od, [string]$realRoot) {
  $ci = [StringComparison]::OrdinalIgnoreCase
  $lp = "$($L.userprofile)".TrimEnd('\'); $canon = "$($L.root)".TrimEnd('\'); $lod = "$($L.onedrive)".TrimEnd('\')
  $myProfile = $myProfile.TrimEnd('\'); $od = $od.TrimEnd('\'); $realRoot = $realRoot.TrimEnd('\')
  $p = [pscustomobject]@{ Err = ''; LapProfile = $lp; CanonRoot = $canon; ProfOD = ''; ProfRoot = ''; OdMoved = $false }
  if (-not $lp -or -not $canon.StartsWith($lp + '\', $ci)) { $p.Err = "machine.txt 의 root($canon)가 userprofile($lp) 아래가 아님"; return $p }
  if (-not $lod) { $lod = Split-Path $canon -Parent }                  # 옛 내보내기(onedrive 키 없음) — 작업 트리 바로 위
  if (-not $lod.StartsWith($lp + '\', $ci) -or -not $canon.StartsWith($lod + '\', $ci) -or -not $realRoot.StartsWith($od + '\', $ci) -or
    $canon.Substring($lod.Length) -ine $realRoot.Substring($od.Length)) {
    $p.Err = "노트북 경로($canon)를 이 PC 의 $realRoot 로 이을 수 없음(사용자 폴더 · OneDrive 아래 상대 경로가 다름)"; return $p
  }
  $p.ProfOD = $myProfile + $lod.Substring($lp.Length)
  $p.ProfRoot = $myProfile + $canon.Substring($lp.Length)
  $p.OdMoved = ($p.ProfOD -ine $od)
  return $p
}

# 폴더를 아직 가리키는 것 — [pscustomobject]{ What; Block }. Block = OneDrive 계정 폴더 · 사용자 환경 변수 OneDrive* · 바탕 화면 · 문서
# (탐색기 · 프로그램이 늘 열어 두는 곳 — 이름 바꾸기가 막히고 폴더 백업이 옛 자리에 남는다). 나머지 셸 폴더(사진 · 스크린샷 …)는
# 알림만 — 연결 뒤에는 옛 경로가 새 OneDrive 의 같은 자리로 이어진다(11-03 메인 실측: OneDrive 안을 가리키는 셸 폴더 7개).
function Get-FolderUsers([string]$dir) {
  $d = $dir.TrimEnd('\')
  $under = { param($v) $x = [Environment]::ExpandEnvironmentVariables("$v").TrimEnd('\'); $x -and ($x -ieq $d -or $x.StartsWith($d + '\', [StringComparison]::OrdinalIgnoreCase)) }
  foreach ($a in @(Get-ChildItem -Path 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue)) {
    if (& $under (Get-ItemProperty -LiteralPath $a.PSPath -ErrorAction SilentlyContinue).UserFolder) { [pscustomobject]@{ What = "OneDrive 계정 $($a.PSChildName)"; Block = $true } }
  }
  $hard = @{ 'Desktop' = '바탕 화면'; 'Personal' = '문서'; '{F42EE2D3-909F-4907-8871-4C22FC0BF756}' = '문서'; '{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}' = '바탕 화면' }
  $sf = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
  if ($sf) {
    foreach ($q in @($sf.PSObject.Properties | Where-Object { $_.Name -notin 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider' })) {
      if (& $under $q.Value) { [pscustomobject]@{ What = "셸 폴더 $(if ($hard.ContainsKey($q.Name)) { $hard[$q.Name] } else { $q.Name })"; Block = $hard.ContainsKey($q.Name) } }
    }
  }
  foreach ($n in 'OneDrive', 'OneDriveConsumer', 'OneDriveCommercial') {
    if (& $under ([Environment]::GetEnvironmentVariable($n, 'User'))) { [pscustomobject]@{ What = "환경 변수 $n"; Block = $true } }
  }
}

# 사용자 폴더의 옛 OneDrive 자리 → 새 OneDrive 위치(예 C:\Users\User\OneDrive → G:\OneDrive). 실제 폴더(연결 해제 뒤 남은 옛
# OneDrive)는 지우지 않고 <이름>.old_<시각> 으로 이름만 바꾼다 — 계정 · 셸 폴더 · 환경 변수가 아직 가리키면 손대지 않는다.
# -CheckOnly = 점검만. 돌려주는 값 = 멈출 사유(빈 문자열 = 됨).
function Set-OneDriveJunction([string]$profOD, [string]$od, [switch]$CheckOnly) {
  $profOD = $profOD.TrimEnd('\'); $od = $od.TrimEnd('\')
  $t = Get-JunctionTarget $profOD
  if ($t) {
    if ($t -ine $od) { return "$profOD 가 다른 곳($t)에 연결돼 있음 — 확인 뒤 다시" }
    if (-not $CheckOnly) { Ok "이미 연결: $profOD -> $od" }
    return ''
  }
  if (Test-Path -LiteralPath $profOD) {
    $users = @(Get-FolderUsers $profOD)
    $block = @($users | Where-Object { $_.Block } | ForEach-Object { $_.What })
    if ($block.Count) { return "옛 OneDrive 폴더($profOD)를 아직 가리킴: $($block -join ' · ') — OneDrive 를 새 위치로 다시 연결하고 폴더 백업(바탕 화면 · 문서)도 다시 켠 뒤 다시" }
    if ($CheckOnly) { return '' }
    $soft = @($users | Where-Object { -not $_.Block } | ForEach-Object { $_.What })
    if ($soft.Count) { Info "옛 OneDrive 안을 가리키는 셸 폴더 $($soft.Count)개 — 연결 뒤 새 OneDrive 의 같은 자리로 이어짐: $($soft -join ' · ')" }
    $old = "$(Split-Path $profOD -Leaf).old_$Stamp"
    try { Rename-Item -LiteralPath $profOD -NewName $old -ErrorAction Stop }
    catch { return "옛 OneDrive 폴더 이름을 못 바꿈($($_.Exception.Message)) — 그 안을 연 프로그램(탐색기 창 · Claude · 터미널 · R)을 닫고 다시(그래도 안 되면 PC 를 다시 시작한 뒤 바로)" }
    Ok "옛 OneDrive 폴더 → $(Join-Path (Split-Path $profOD -Parent) $old) (지우지 않음 — 확인 뒤 사람이 지운다)"
  }
  if ($CheckOnly) { return '' }
  [void](New-Item -ItemType Junction -Path $profOD -Value $od)
  Ok "연결: $profOD -> $od"
  return ''
}

function Test-SameFile([string]$a, [string]$b) {
  return ((Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $b -Algorithm SHA256).Hash)
}

# Claude 메모리 합치기: 없는 파일 = 복사 · MEMORY.md = 줄 합집합(있는 줄 뒤에 새 줄) · 같은 이름 다른 내용 = <이름>.<tag>.md 로 곁에
function Merge-Memory([string]$src, [string]$dst, [string]$tag) {
  [void](New-Item -ItemType Directory -Force -Path $dst)
  $n = 0; $u = 0; $k = 0
  $base = $src.TrimEnd('\')
  foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($base.Length + 1)
    $d = Join-Path $dst $rel
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $d -Parent))
    if (-not (Test-Path -LiteralPath $d)) { Copy-Item -LiteralPath $f.FullName -Destination $d; $n++; continue }
    if (Test-SameFile $d $f.FullName) { continue }
    if ($f.Name -eq 'MEMORY.md') {
      $haveText = [IO.File]::ReadAllText($d, $Utf8)
      $set = New-Object 'System.Collections.Generic.HashSet[string]'
      foreach ($l in ($haveText -split "`r?`n")) { [void]$set.Add($l.TrimEnd()) }
      $add = @([IO.File]::ReadAllLines($f.FullName, $Utf8) | Where-Object { $_.Trim() -and -not $set.Contains($_.TrimEnd()) })
      if ($add.Count -gt 0) {
        $pre = $(if ($haveText.Length -gt 0 -and -not $haveText.EndsWith("`n")) { "`n" } else { '' })
        [IO.File]::AppendAllText($d, $pre + (($add -join "`n") + "`n"), $Utf8); $u += $add.Count
      }
      continue
    }
    $alt = Join-Path (Split-Path $d -Parent) ('{0}.{1}{2}' -f [IO.Path]::GetFileNameWithoutExtension($d), $tag, [IO.Path]::GetExtension($d))
    Copy-Item -LiteralPath $f.FullName -Destination $alt -Force; $k++
  }
  return "새 파일 $n · MEMORY.md 줄 +$u · 같은 이름 다른 내용 $k(→ 이름.$tag.md)"
}

# ~/.claude/projects/<키>/memory → OneDrive\Qvest_sync\claude_memory (있던 폴더는 합친 뒤 memory.bak_<시각> 으로 남긴다)
function Set-MemoryJunction([string]$memDir, [string]$shared, [string]$tag) {
  $t = Get-JunctionTarget $memDir
  if ($t) {
    if ($t -ieq $shared.TrimEnd('\')) { Ok "이미 연결: $memDir"; return }
    Warn "$memDir 가 다른 곳($t)에 연결돼 있음 — 그대로 둠"; return
  }
  [void](New-Item -ItemType Directory -Force -Path $shared)
  if (Test-Path -LiteralPath $memDir) {
    $msg = Merge-Memory $memDir $shared $tag
    Rename-Item -LiteralPath $memDir -NewName "memory.bak_$Stamp"
    Info "합침: $msg · 원래 폴더 = memory.bak_$Stamp"
  } else {
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $memDir -Parent))
  }
  [void](New-Item -ItemType Junction -Path $memDir -Value $shared)
  Ok "연결: $memDir -> $shared"
}

# -Files <대조표>: 고른 폴더 밖의 대조표 파일(T · U)을 파일 단위로 더한다 · -NoAll: '전부' 계획 없이 핵심 폴더부터(메인)
function Invoke-Pin([string]$py, [string]$tool, [string]$root, [int]$marginGb, [string]$files = '', [switch]$noAll) {
  $a = @($tool, 'pin', $root, '--margin-gb', "$marginGb", '--apply')
  foreach ($e in $PinExclude) { $a += @('--exclude', $e) }
  foreach ($e in $PinEssential) { $a += @('--essential', $e) }
  if ($files) { $a += @('--files', $files) }
  if ($noAll) { $a += '--no-all' }
  return (Run $py $a -Show)
}

function Set-PinnedFolder([string]$dir) {
  [void](Run 'attrib' @('+P', '-U', $dir))
  [void](Run 'attrib' @('+P', '-U', (Join-Path $dir '*'), '/S', '/D'))
}

# OneDrive 클라우드 전용(아직 안 내려받은) 파일 — RECALL_ON_DATA_ACCESS · RECALL_ON_OPEN · OFFLINE (qvest_machine.sh settled 와 같은 마스크)
function Get-CloudOnly([string[]]$files) {
  foreach ($f in $files) {
    $i = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    if ($i -and (([int]$i.Attributes -band 0x441000) -ne 0)) { $f }
  }
}

# 파일 · 폴더를 이 장치에 내려 둔다: 항상 유지(+P) → 한 번씩 읽어 그 자리에서 내려받기 → 남은 클라우드 전용이 0 이 될 때까지 기다림.
# 관리자 프로세스는 그 자리 내려받기가 안 될 수 있어(OneDrive 는 사용자 세션에서 돈다) 그때는 고정을 보고 OneDrive 가 내려받는다.
# 돌려주는 값 = 시간 안에 못 내려온 파일 수(0 = 모두 이 장치에 있음).
function Wait-Local([string[]]$paths, [int]$timeoutMin = 30) {
  $files = New-Object Collections.Generic.List[string]
  foreach ($p in $paths) {
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
    if ((Get-Item -LiteralPath $p -Force).PSIsContainer) {
      Set-PinnedFolder $p
      foreach ($f in @(Get-ChildItem -LiteralPath $p -Recurse -File -Force)) { $files.Add($f.FullName) }
    } else { [void](Run 'attrib' @('+P', '-U', $p)); $files.Add($p) }
  }
  $buf = New-Object byte[] 1MB
  foreach ($f in @(Get-CloudOnly $files.ToArray())) {
    try { $s = [IO.File]::OpenRead($f); try { while ($s.Read($buf, 0, $buf.Length) -gt 0) { } } finally { $s.Dispose() } } catch { }
  }
  $until = (Get-Date).AddMinutes($timeoutMin); $shown = Get-Date
  while ($true) {
    $left = @(Get-CloudOnly $files.ToArray())
    if (-not $left.Count) { return 0 }
    if ((Get-Date) -ge $until) { return $left.Count }
    if (((Get-Date) - $shown).TotalSeconds -ge 30) { Info "OneDrive 내려받기 기다림 — 남은 파일 $($left.Count)개(예 $(Split-Path $left[0] -Leaf))"; $shown = Get-Date }
    Start-Sleep -Seconds 10
  }
}

# 대조표(manifest.tsv)의 파일(D = 지운 것 제외)이 이 장치에 다 내려올 때까지 기다린다 — [10] 대조가 읽을 파일(도훈 11-04 "기다리게
# 바꿔줘" · UAC 한 번으로 끝까지). 관리자 프로세스는 그 자리 내려받기가 안 될 수 있어 읽지 않고, 항상 유지로 표시해 둔 것을 OneDrive 가
# 뒤에서 받는 것을 지켜본다. 기다리는 동안 이 PC 가 절전에 들지 않게 한다(전원 설정은 그대로 · 이 함수가 끝나면 풀림).
# 그만 기다리는 때 = 첫 파일이 오기 전 $startMin 분 · 온 뒤 줄지 않은 채 $stallMin 분 · 모두 $timeoutMin 분. 돌려주는 값 = 남은 파일 수.
function Wait-ManifestLocal([string]$root, [string]$manifest, [double]$timeoutMin = 1440, [double]$startMin = 180, [double]$stallMin = 60, [int]$pollSec = 60) {
  $files = New-Object Collections.Generic.List[string]; $sizes = New-Object Collections.Generic.List[long]
  foreach ($l in [IO.File]::ReadLines($manifest, $Utf8)) {
    if ($l.StartsWith('#')) { continue }
    $c = $l -split "`t", 4
    if ($c.Count -lt 4 -or $c[0] -eq 'D') { continue }
    $files.Add((Join-Path $root ($c[3] -replace '/', '\'))); $sizes.Add([long]$c[1])
  }
  if (-not ('Qvest.Power' -as [type])) {
    Add-Type -Namespace Qvest -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
  }
  [void][Qvest.Power]::SetThreadExecutionState([uint32]2147483649)              # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
  try {
    $t0 = Get-Date; $first = -1; $best = [int]::MaxValue; $bestAt = $t0; $shown = $t0
    while ($true) {
      $left = 0; $bytes = [long]0; $eg = ''
      for ($i = 0; $i -lt $files.Count; $i++) {
        try { $a = [int][IO.File]::GetAttributes($files[$i]) } catch { continue }   # 없는 파일은 [10] 이 '빠짐'으로 센다
        if (($a -band 0x441000) -ne 0) { $left++; $bytes += $sizes[$i]; if (-not $eg) { $eg = Split-Path $files[$i] -Leaf } }
      }
      if ($left -eq 0) { return 0 }
      $now = Get-Date; $gb = [math]::Round($bytes / 1GB, 2)
      if ($first -lt 0) { $first = $left; Info "대조할 파일 중 아직 클라우드에만 있는 것 $left 개($gb GB) — OneDrive 가 받기를 기다린다" }
      if ($left -lt $best) { $best = $left; $bestAt = $now }
      $quiet = ($now - $bestAt).TotalMinutes
      if (($now - $t0).TotalMinutes -ge $timeoutMin) { Info "기다림 끝($timeoutMin 분) — 남은 $left 개"; return $left }
      if ($best -eq $first -and $quiet -ge $startMin) { Info "$startMin 분 동안 한 개도 안 내려옴 — 그만 기다린다(OneDrive 가 멈췄거나 고정이 안 됐을 수 있다)"; return $left }
      if ($best -lt $first -and $quiet -ge $stallMin) { Info "$stallMin 분 동안 줄지 않음 — 그만 기다린다(남은 $left 개 · 예 $eg)"; return $left }
      if (($now - $shown).TotalMinutes -ge 5) { Info "내려받기 기다림 — 남은 $left 개($gb GB · 예 $eg) · $([int]($now - $t0).TotalMinutes) 분"; $shown = $now }
      Start-Sleep -Seconds $pollSec
    }
  } finally { [void][Qvest.Power]::SetThreadExecutionState([uint32]2147483648) }   # ES_CONTINUOUS — 절전 막기 풀기
}

function ConvertTo-Fwd([string]$p) { return ($p -replace '\\', '/') }

function Get-HostNames { return @(@($env:COMPUTERNAME, [Net.Dns]::GetHostName()) | Where-Object { $_ } | Select-Object -Unique) }

# machines.conf 의 기계 이름(역할 지정 시 그 역할만)
function Get-ConfMachines([string]$conf, [string]$role = '') {
  $n = @()
  if (Test-Path -LiteralPath $conf) {
    foreach ($l in [IO.File]::ReadAllLines($conf, $Utf8)) {
      $t = @($l.Trim() -split '\s+')
      if ($t.Count -ge 3 -and $t[0] -eq 'machine' -and (-not $role -or $t[2] -eq $role)) { $n += $t[1] }
    }
  }
  return $n
}

# bash 시험 1개 — 마지막 {"pass":N,"fail":M} 줄 + 종료 코드로 판정(0/N 은 통과가 아니다)
function Invoke-BashTest([string]$bash, [string]$root, [string]$rel) {
  $r = Run $bash @('-c', "cd '$(ConvertTo-Fwd $root)' && bash $rel")
  $p = -1; $f = -1
  foreach ($l in $r.Out) { if ($l -match '"pass":\s*(\d+),\s*"fail":\s*(\d+)') { $p = [int]$Matches[1]; $f = [int]$Matches[2] } }
  return [pscustomobject]@{ Name = $rel; Ok = ($r.Rc -eq 0 -and $f -eq 0 -and $p -gt 0); Pass = $p; Fail = $f; Rc = $r.Rc
    Tail = (@($r.Out | Select-Object -Last 8) -join "`n") }
}

# qvest_tasks.ps1 를 이 프로세스에서 부른다(출력 그대로 · 종료 코드 돌려줌)
function Invoke-QvestTasks([string]$ps1, [hashtable]$prm) {
  try { $global:LASTEXITCODE = 0; & $ps1 @prm; return [int]$LASTEXITCODE }
  catch { Warn "qvest_tasks.ps1 -Mode $($prm.Mode): $($_.Exception.Message)"; return 1 }
}

# 내보낸 폴더의 파일 목록(크기 · sha256) — 받는 쪽은 이것으로 OneDrive 가 다 내려왔는지 본다
function Write-FileList([string]$dir, [string]$listFile, [string[]]$head) {
  $base = $dir.TrimEnd('\')
  $rows = New-Object Collections.Generic.List[string]
  foreach ($h in $head) { $rows.Add("# $h") }
  foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force | Sort-Object FullName)) {
    if ($f.FullName -ieq $listFile) { continue }
    $rows.Add(('{0}{1}{2}{1}{3}' -f $f.Length, "`t", (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower(),
        ($f.FullName.Substring($base.Length + 1) -replace '\\', '/')))
  }
  Write-Utf8 $listFile (($rows -join "`n") + "`n")
  return ($rows.Count - $head.Count)
}

# 목록대로 다 있나 — 빠짐 · 크기 · 해시가 다른 파일(이미 가져와 지운 묶음 = $skipTop 은 건너뜀)
function Test-FileList([string]$dir, [string]$listFile, [string[]]$skipTop = @()) {
  $bad = New-Object Collections.Generic.List[string]
  foreach ($l in [IO.File]::ReadAllLines($listFile, $Utf8)) {
    if ($l -notmatch '^(\d+)\t([0-9a-f]{64})\t(.+)$') { continue }
    $rel = $Matches[3]; $size = [long]$Matches[1]; $sha = $Matches[2]
    if ($skipTop -contains ($rel -split '/')[0]) { continue }
    $p = Join-Path $dir ($rel -replace '/', '\')
    $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if ($null -eq $i) { $bad.Add("없음 $rel"); continue }
    if ($i.Length -ne $size) { $bad.Add("크기 $rel"); continue }
    if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() -ne $sha) { $bad.Add("내용 $rel") }
  }
  return , $bad.ToArray()
}
