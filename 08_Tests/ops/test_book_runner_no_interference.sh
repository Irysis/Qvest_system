#!/usr/bin/env bash
#==============================================================================
# test_book_runner_no_interference.sh — BOOK 러너가 다른 작업의 R 을 끄지 않는가 (2026-11-06)
#
# 배경: 도훈 지시 "Book 리밸 돌릴 때 다른 작업에 간섭하는부분 다 없애주고 11월 리밸 진행해줘".
#   구 kill_stray(run_nolayer4_monthly.sh + 05_Production 전진 스크립트)는 'taskkill //F //IM Rscript.exe' 로 이 기계의
#   R 을 전부 끄던 것 → 지금은 러너 자기 R 만 끈다(ops/kill_own_r.ps1 · 05_Production 쪽은 PATH 가로채기 ops/shims/taskkill).
#
# 계약(양방향):
#   K1 [보호] 러너 밖 R — 살아 있는 부모 아래 R · 부모가 죽은 일반 스크립트 고아 — 는 '끌 대상'에 들지 않고 실제로도 산다
#   K2 [검거] 러너 bash 자손 R(bin + x64)은 끈다
#   K3 [검거] 부모가 죽은 BOOK 스크립트 고아(m4_append_only.R)는 자식 x64 까지 끈다
#   K4 [보호] '끌 대상'은 이 시험이 띄운 자기 R 뿐이다 — 기계의 다른 R(레인 · P2R05 · 다른 세션)이 한 개라도 들면 실패
#   S1 [가로채기] PATH 앞 shims/taskkill 이 '//F //IM Rscript.exe' 를 받으면 진짜 taskkill 로 넘기지 않는다
#   S2 [통과] R 실행기가 아닌 호출(//PID …)은 진짜 taskkill(주입 기록기)로 넘긴다
#   S3 [fail-safe] QV_KILL_ROOT_WINPID 없으면 아무것도 끄지 않는다(rc 0)
#   W1 [배선] run_nolayer4_monthly.sh 코드 줄에 이미지 이름 전체 종료 없음 · kill_own_r · shims PATH · BelowNormal ·
#      05_Production 전진 스크립트 무수정
#   M1 [뮤테이션] 늘 통과시키는 가로채기 사본 → 기록기가 //IM 호출을 받는다(S1 판정이 발화)
#   M2 [뮤테이션] 자손 제한을 잃은 kill_own_r 사본(-DryRun 으로만) → 러너 밖 R 이 '끌 대상'에 든다(K1 · K4 판정이 발화)
# 안전: 실제로 끄는 것은 이 시험이 띄운 R 뿐이다. 뮤테이션은 -DryRun(목록만) 또는 기록기로만 잰다 — 기계의 다른 R 은
#   어떤 경로로도 끄지 않는다. 끝나면 이 시험이 띄운 R 을 PID 로 정리한다.
# 출력: 마지막 줄 JSON {"test":"book_runner_no_interference","pass":N,"fail":N,"total":N,"mut_killed":k,"mut_total":2}
#==============================================================================
set -u
TN="book_runner_no_interference"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE="$(cd "$HERE/../.." && pwd)"                       # 코드 루트 = 이 시험 파일의 저장소(워크트리 포함)
KOR="$CODE/02_Infrastructure/ops/kill_own_r.ps1"
SHIMD="$CODE/02_Infrastructure/ops/shims"
NL4="$CODE/02_Infrastructure/monitoring/run_nolayer4_monthly.sh"
FWD_REL="05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/run_pg2_forward_noLayer4.sh"
RS="${QVEST_RSCRIPT:-/c/Program Files/R/R-4.5.2/bin/Rscript.exe}"
PASS=0; FAIL=0; MK=0; MT=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
preflight_fail(){ echo "XX 사전 점검 실패: $1"; echo "{\"test\":\"$TN\",\"pass\":0,\"fail\":1,\"total\":1,\"preflight\":\"$1\"}"; exit 1; }
ps1(){ powershell -NoProfile -ExecutionPolicy Bypass -Command "$1" 2>/dev/null | tr -d '\r'; }

# ── 사전 점검(카나리아) — 계측이 살아 있어야 결과를 낸다 ─────────────────────
[ -f "$KOR" ] || preflight_fail "kill_own_r.ps1 부재"
[ -f "$SHIMD/taskkill" ] || preflight_fail "shims/taskkill 부재"
[ -x "$RS" ] || [ -f "$RS" ] || preflight_fail "Rscript 부재($RS)"
_can="$(powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$KOR")" -RootPid 1 -DryRun 2>&1 | tr -d '\r' | tail -n 1)"
[[ "$_can" == "kill_own_r: root=1 would_kill="* ]] || preflight_fail "kill_own_r -DryRun 카나리아 무응답($_can)"

TD="$(mktemp -d)"; TDW="$(cygpath -w "$TD")"; RSW="$(cygpath -w "$RS")"
SPAWNED=()
cleanup(){ # 이 시험이 띄운 R 만 PID 로 정리
  local ids; ids="$(printf '%s,' "${SPAWNED[@]}" | sed 's/,$//')"
  [ -n "$ids" ] && ps1 "foreach (\$i in @($ids)) { try { Stop-Process -Id \$i -Force -ErrorAction Stop } catch {} }" >/dev/null
  [ -n "${FR:-}" ] && kill "$FR" 2>/dev/null; [ -n "${FL:-}" ] && kill "$FL" 2>/dev/null
  rm -rf "$TD"
}
trap cleanup EXIT
printf 'Sys.sleep(240)\n' > "$TD/m4_append_only.R"      # BOOK 스크립트 이름(고아 검거 대상)
printf 'Sys.sleep(240)\n' > "$TD/other_job.R"           # 대조 — 같은 고아지만 BOOK 조각 없음

spawn_orphan(){ ps1 "\$p = Start-Process -FilePath '$RSW' -ArgumentList '\"$TDW\\$1\"' -WindowStyle Hidden -PassThru; \$p.Id" | tail -n 1; }
# R 의 실제 트리(11-06 실측): bash → bash(fork 대리) → bin\Rscript.exe → cmd.exe → x64\Rscript.exe — 직계 자식만 보면 놓친다
cat > "$TD/desc_r.ps1" <<'PS1'
param([int[]]$Roots)
$all = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name)
$kids = @{}
foreach ($p in $all) { $pp = [int]$p.ParentProcessId; if (-not $kids.ContainsKey($pp)) { $kids[$pp] = New-Object System.Collections.Generic.List[int] }; if ($pp -ne [int]$p.ProcessId) { $kids[$pp].Add([int]$p.ProcessId) } }
$seen = @{}; $q = New-Object System.Collections.Generic.Queue[int]
foreach ($r in $Roots) { $seen[$r] = $true; $q.Enqueue($r) }
while ($q.Count -gt 0) { $c = $q.Dequeue(); if ($kids.ContainsKey($c)) { foreach ($k in $kids[$c]) { if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $q.Enqueue($k) } } } }
foreach ($p in $all) { if ($seen.ContainsKey([int]$p.ProcessId) -and ([string]$p.Name) -match '^(?i)(rscript|r|rterm)\.exe$') { [int]$p.ProcessId } }
PS1
desc_r(){ powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$TD/desc_r.ps1")" -Roots "$1" 2>/dev/null | tr -d '\r' | paste -sd' ' -; }
alive_set(){ ps1 "(Get-Process -Name Rscript,R,Rterm -ErrorAction SilentlyContinue).Id" | paste -sd' ' -; }
in_set(){ [[ " $2 " == *" $1 "* ]]; }

# ── 띄우기 ── 출력은 버린다(물려받은 파이프가 끝까지 열려 있으면 호출자가 240초를 기다린다) ─────
bash -c "\"$RS\" -e 'Sys.sleep(240)' >/dev/null 2>&1; :" >/dev/null 2>&1 & FR=$!   # 가짜 러너(자손 R = 검거 대상)
"$RS" -e 'Sys.sleep(240)' >/dev/null 2>&1 & FL=$!                                    # 러너 밖 R(살아 있는 부모 = 이 시험 bash)
OB="$(spawn_orphan m4_append_only.R)"; OC="$(spawn_orphan other_job.R)"
sleep 5
FRW="$(tr -d '\r\n ' < /proc/$FR/winpid 2>/dev/null)"; FLW="$(tr -d '\r\n ' < /proc/$FL/winpid 2>/dev/null)"
OWN="$(echo $(desc_r "$FRW") $(desc_r "$OB"))"; FOREIGN="$(echo $(desc_r "$FLW") $(desc_r "$OC"))"
SPAWNED=($OWN $FOREIGN)
echo "  띄움: 자기(검거 대상)=[$OWN] · 러너 밖=[$FOREIGN] · 가짜 러너 winpid=$FRW"
[ "$(wc -w <<< "$OWN")" -ge 4 ] && [ "$(wc -w <<< "$FOREIGN")" -ge 4 ] \
  || preflight_fail "시험 R 띄우기 실패(자기=[$OWN] 러너 밖=[$FOREIGN] — 각 bin+x64 2개씩 기대)"

# ── K: 끌 대상 목록(DryRun) — 자기 R 만 정확히 ────────────────────────────────
dry(){ powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$1")" -RootPid "$2" -DryRun 2>&1 | tr -d '\r' | awk '/would kill/{print $4}' | paste -sd' ' -; }
judge_dry(){ # judge_dry <목록> → 0 이면 계약 충족(자기 전부 포함 · 러너 밖 0 · 낯선 R 0)
  local list="$1" p miss="" leak="" extra=""
  for p in $OWN; do in_set "$p" "$list" || miss="$miss $p"; done
  for p in $FOREIGN; do in_set "$p" "$list" && leak="$leak $p"; done
  for p in $list; do in_set "$p" "$OWN" || in_set "$p" "$FOREIGN" || extra="$extra $p"; done
  echo "miss=[${miss# }] leak=[${leak# }] extra=[${extra# }]"
  [ -z "$miss" ] && [ -z "$leak" ] && [ -z "$extra" ]
}
D="$(dry "$KOR" "$FRW")"
if _j="$(judge_dry "$D")"; then ok "K1·K2·K3·K4 끌 대상 = 자기 R 전부 · 러너 밖 0 · 기계의 다른 R 0 ($_j)"; else ng "K 끌 대상 오류: $_j"; fi

# ── M2: 자손 제한을 잃은 kill_own_r(-DryRun 전용) → 러너 밖 R 이 대상에 든다 ──────
#   ★S1(실제 종료) 앞에서 잰다 — 자기 R 이 죽은 뒤면 'miss' 만으로 판정이 갈려 검출이 공허해진다. 판정은 leak(러너 밖 포함)만 본다.
MT=$((MT+1))
sed "s/foreach (\$id in \$desc.Keys) { if (\$isR.ContainsKey(\$id)) { \$why\[\$id\] = 'descendant' } }/foreach (\$id in @(\$isR.Keys)) { \$why[\$id] = 'descendant' }/" "$KOR" > "$TD/kor_mut.ps1"
if grep -q 'foreach ($id in @($isR.Keys)) { $why\[$id\] = .descendant. }' "$TD/kor_mut.ps1"; then
  D2="$(dry "$TD/kor_mut.ps1" "$FRW")"; leak2=""
  for p in $FOREIGN; do in_set "$p" "$D2" && leak2="$leak2 $p"; done
  if [ -n "$leak2" ]; then MK=$((MK+1)); ok "M2 검거: 자손 제한 없는 사본은 러너 밖 R(${leak2# })을 대상에 넣는다 — K 판정이 그 누출을 잡는다(DryRun 만)"
  else ng "M2 생존: 제한을 지웠는데도 러너 밖 R 이 대상에 안 든다 — 검사 사망"; fi
else ng "M2 치환 실패 — 검사 불능"; fi

# ── S1: 가로채기 경유 실제 종료 ───────────────────────────────────────────────
REC="$TD/rec_taskkill"; printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n' "$TD/rec.log" > "$REC"; chmod +x "$REC"
( export PATH="$SHIMD:$PATH" QV_KILL_ROOT_WINPID="$FRW" QV_REAL_TASKKILL="$REC"; hash -r; taskkill //F //IM Rscript.exe ) > "$TD/s1.out" 2>&1
sleep 2; A="$(alive_set)"; dead_own=""; alive_for=""
for p in $OWN; do in_set "$p" "$A" && dead_own="$dead_own $p"; done
for p in $FOREIGN; do in_set "$p" "$A" || alive_for="$alive_for $p"; done
if [ -z "$dead_own" ] && [ -z "$alive_for" ] && [ ! -e "$TD/rec.log" ]; then
  ok "S1 'taskkill //F //IM Rscript.exe' → 자기 R 만 종료 · 러너 밖 R 생존 · 진짜 taskkill 미호출"
else ng "S1 가로채기 오류: 남은 자기=[${dead_own# }] 죽은 러너 밖=[${alive_for# }] 기록기=$( [ -e "$TD/rec.log" ] && cat "$TD/rec.log")"; fi

# ── S2 · S3 ──────────────────────────────────────────────────────────────────
( export PATH="$SHIMD:$PATH" QV_REAL_TASKKILL="$REC"; hash -r; taskkill //PID 99999999 ) >/dev/null 2>&1
grep -q -- "//PID 99999999" "$TD/rec.log" 2>/dev/null && ok "S2 R 실행기가 아닌 호출은 진짜 taskkill 로 그대로 넘긴다" || ng "S2 통과 호출 미전달"
rm -f "$TD/rec.log"
( export PATH="$SHIMD:$PATH" QV_KILL_ROOT_WINPID="" QV_REAL_TASKKILL="$REC"; hash -r; taskkill //F //IM Rscript.exe ) > "$TD/s3.out" 2>&1; s3=$?
A="$(alive_set)"; gone=""; for p in $FOREIGN; do in_set "$p" "$A" || gone="$gone $p"; done
if [ "$s3" -eq 0 ] && [ -z "$gone" ] && [ ! -e "$TD/rec.log" ]; then ok "S3 러너 pid 없으면 아무것도 끄지 않는다(rc 0 · 진짜 taskkill 미호출)"
else ng "S3 fail-safe 오류: rc=$s3 죽음=[${gone# }]"; fi

# ── W1: 배선(코드 줄) ─────────────────────────────────────────────────────────
cl(){ grep -vE '^[[:space:]]*#' "$1"; }
if ! cl "$NL4" | grep -qiE '/IM[[:space:]]+Rscript' && cl "$NL4" | grep -q 'kill_own_r.ps1' && cl "$NL4" | grep -q 'ops/shims' \
   && cl "$NL4" | grep -q 'BelowNormal' && git -C "$CODE" diff --quiet HEAD -- "$FWD_REL" 2>/dev/null; then
  ok "W1 예약 러너: 이미지 이름 전체 종료 없음 · kill_own_r · shims PATH · BelowNormal · 05_Production 전진 스크립트 무수정"
else ng "W1 배선 이상(run_nolayer4_monthly.sh 또는 05_Production 수정)"; fi

# ── M1: 늘 통과시키는 가로채기 사본 → 기록기가 //IM 을 받는다 ──────────────────
MT=$((MT+1)); mkdir -p "$TD/mshim"
sed 's/rscript.exe|rscript|r.exe|r|rterm.exe|rterm)/__never__)/' "$SHIMD/taskkill" > "$TD/mshim/taskkill"; chmod +x "$TD/mshim/taskkill"
if grep -q '__never__)' "$TD/mshim/taskkill"; then
  rm -f "$TD/rec.log"
  ( export PATH="$TD/mshim:$PATH" QV_KILL_ROOT_WINPID="$FRW" QV_REAL_TASKKILL="$REC"; hash -r; taskkill //F //IM Rscript.exe ) >/dev/null 2>&1
  if grep -q -- "//IM Rscript.exe" "$TD/rec.log" 2>/dev/null; then MK=$((MK+1)); ok "M1 검거: 라우팅 없는 가로채기는 전체 종료 호출을 진짜 taskkill 로 흘린다(S1 판정 발화)"
  else ng "M1 생존: 뮤턴트에서도 기록기 미호출 — S1 판정이 배선을 못 본다"; fi
else ng "M1 치환 실패 — 검사 불능"; fi

echo "결과: PASS=$PASS FAIL=$FAIL · 뮤테이션 검거 $MK/$MT"
echo "{\"test\":\"$TN\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL)),\"mut_killed\":$MK,\"mut_total\":$MT}"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
