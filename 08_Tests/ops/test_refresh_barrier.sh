#!/usr/bin/env bash
#==============================================================================
# test_refresh_barrier.sh — 리프레시 배리어 **양방향** 검사 (도훈 결정 OPS-RUNNER-REFRESH-BARRIER · 2026-09-24)
#
# 대상: 02_Infrastructure/ops/refresh_barrier.sh(판정 정본) · refresh_barrier.R(래퍼) 와 그 소비자
#   틱(reinforce_auto_tick.sh) · 러너(reinforce_auto_parallel.R 진입 + 수집 절) · 워커(rf_cell_worker.R) ·
#   엔진 재판정(rf_cell_engine.R) · 충실구현 레인(rf_replication_auto.sh 진입 + rp_verify) · 2계층 드라이버(rf_l2_auto.R) ·
#   적대검증(rf_overlay_adversary.R) · 아침 writer 잠금(morning_briefing.sh).
#
# ★부작용 없음 — 잠금 경로는 전부 주입(QM_REFRESH_LOCKDIR · QM_RAWDATA_WRITER_LOCKDIR)이고 임시 디렉터리 안이다.
#   운영 잠금(/tmp/qm_daily_refresh.lock)·원장·.cache/reinforce_auto_log.jsonl 을 만들거나 지우지 않는다.
#   러너·틱·레인 실행은 샌드박스 ROOT(임시) 또는 격리 env(QVEST_RF_CONFIG·QVEST_RP_*·QVEST_RF_CLAIM)로만 돈다.
#   자식 Rscript 는 R_ENVIRON_USER=<빈 파일> — ~/.Renviron 의 QM_ROOT 가 샌드박스를 덮지 않게(system2(env=) 는 Windows 에서 무시).
# ★각 가드마다 ①양성 대조(정상 경로가 지나간다) ②위반 주입(막아야 할 것을 막는다) ③돌연변이(가드를 지우면 빨개진다)를 건다.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"; [ -x "$PY" ] || PY=python
OPS="$ROOT/02_Infrastructure/ops"; SH="$OPS/refresh_barrier.sh"; RW="$OPS/refresh_barrier.R"
T=$(mktemp -d); TM=$(cygpath -m "$T")
: > "$T/empty.Renviron"; export R_ENVIRON_USER="$TM/empty.Renviron"
export QM_REFRESH_LOCKDIR="$TM/refresh.lock" QM_RAWDATA_WRITER_LOCKDIR="$TM/writer.lock" RB_EMPTY_GRACE_S=1
unset QVEST_RB_SH QVEST_RB_BASH QVEST_RB_ENGINE_RECHECK
PASS=0; FAIL=0; SKIP=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
sk(){ printf '  SKIP %s — %s\n' "$1" "${2:-}"; SKIP=$((SKIP+1)); }
BG=()
cleanup(){ local p; for p in "${BG[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT

# 판정 요약 "state:reason:lock" — $1 = 판정기(기본 정본)
st(){ bash "${1:-$SH}" status 2>/dev/null | awk -F'\t' '/^RB\t/{s="";r="";l=""; for(i=2;i<=NF;i++){k=$i; sub(/=.*/,"",k); v=$i; sub(/^[^=]*=/,"",v); if(k=="state")s=v; if(k=="reason")r=v; if(k=="lock")l=v} print s":"r":"l}'; }
# 보유자 픽스처 — 살아 있는 MSYS 프로세스가 잠금 pid 를 쓴다(daily_refresh.sh:25 와 같은 모양: mkdir → echo $$)
hold(){ mkdir -p "$QM_REFRESH_LOCKDIR"; bash -c 'echo $$ > "$1/pid"; exec sleep 300' _ "$QM_REFRESH_LOCKDIR" & BG+=("$!")
        local i; for i in $(seq 1 50); do [ -s "$QM_REFRESH_LOCKDIR/pid" ] && return 0; sleep 0.1; done; return 1; }
unhold(){ local p; p=$(cat "$QM_REFRESH_LOCKDIR/pid" 2>/dev/null); [ -n "$p" ] && kill "$p" 2>/dev/null; rm -rf "$QM_REFRESH_LOCKDIR"; sleep 0.3; }
BOOT=$(awk '$1=="btime"{print $2; exit}' /proc/stat 2>/dev/null); BOOT=${BOOT:-0}
last_event(){ tail -n 1 "$1" 2>/dev/null | "$PY" -c "import sys,json; print(json.loads(sys.stdin.read()).get('event',''))" 2>/dev/null; }

echo "=== A. 판정기(bash) — 상태 판정 양방향 ==="
bash -n "$SH" 2>/dev/null && ok "A0 구문" || ng "A0 구문"
# A0b 잠금 경로 = daily_refresh.sh:24 와 같은 문자열 (재도출: 두 파일에서 각각 뽑아 대조 · ensure_data_current 도)
L_DR=$(sed -n 's/^LOCKDIR="\(.*\)"[[:space:]]*$/\1/p' 02_Infrastructure/data/daily_refresh.sh | head -1)
L_ED=$(sed -n 's/^LOCKDIR="\(.*\)"[[:space:]]*$/\1/p' 02_Infrastructure/ops/ensure_data_current.sh | head -1)
L_RB=$(sed -n 's/.*QM_REFRESH_LOCKDIR:-\([^}]*\)}.*/\1/p' "$SH" | sort -u)
if [ -n "$L_DR" ] && [ "$L_DR" = "$L_RB" ] && [ "$L_DR" = "$L_ED" ]; then ok "A0b 기본 잠금 경로 일치 — daily_refresh.sh=$L_DR · 판정기 · ensure_data_current"
else ng "A0b 잠금 경로 불일치" "daily_refresh=$L_DR helper=$(echo $L_RB) edc=$L_ED"; fi
[ "$(st)" = "free::" ] && ok "A1 [양성] 잠금 없음 → free" || ng "A1 free" "$(st)"
bash "$SH" status >/dev/null 2>&1; [ $? -eq 0 ] && ok "A1b free rc=0" || ng "A1b free rc"
hold; r=$(st); bash "$SH" status >/dev/null 2>&1; rc=$?
[ "$r" = "held:alive:refresh" ] && [ "$rc" = 10 ] && ok "A2 [주입] 살아 있는 보유자(비조상) → held rc=10" || ng "A2 held" "$r rc=$rc"
unhold
mkdir -p "$QM_REFRESH_LOCKDIR"; bash -c 'echo $$ > "$1/pid"' _ "$QM_REFRESH_LOCKDIR"
[ "$(st)" = "stale:dead:refresh" ] && ok "A3 [주입] 보유자 사망 → stale(dead) · 대기 안 함" || ng "A3 dead" "$(st)"
rm -rf "$QM_REFRESH_LOCKDIR"
# A4 재부팅 전 기록 — 살아 있는 pid 라도 pid 파일이 부팅 전이면 재사용
hold; touch -d "@$((BOOT - 3600))" "$QM_REFRESH_LOCKDIR/pid"
[ "$(st)" = "stale:pre_boot:refresh" ] && ok "A4 [주입] pid 파일 mtime < 부팅 → stale(pre_boot)" || ng "A4 pre_boot" "$(st)"
# A5 같은 부팅 안 재사용 — 프로세스 시작이 pid 기록보다 늦다
HP=$(cat "$QM_REFRESH_LOCKDIR/pid"); PST=$(stat -c %Y "/proc/$HP" 2>/dev/null || echo 0); M5=$((PST - 30)); [ "$M5" -le "$BOOT" ] && M5=$((BOOT + 1))
if [ "$M5" -lt $((PST - 2)) ]; then touch -d "@$M5" "$QM_REFRESH_LOCKDIR/pid"
  [ "$(st)" = "stale:pid_reused:refresh" ] && ok "A5 [주입] 프로세스 시작 > pid 기록 → stale(pid_reused)" || ng "A5 pid_reused" "$(st)"
else sk "A5 pid_reused" "부팅 직후라 시작시각 앞 여유 없음"; fi
# A9 인계 모양 — 디렉터리는 부팅 전(옛 인스턴스 mkdir)이지만 pid 파일은 살아 있는 새 보유자가 방금 썼다 → held
touch "$QM_REFRESH_LOCKDIR/pid"; touch -d "@$((BOOT - 7200))" "$QM_REFRESH_LOCKDIR"
[ "$(st)" = "held:alive:refresh" ] && ok "A9 [양성] stale 인계 모양(디렉터리 부팅 전 · pid 파일 신선) → held — 디렉터리 mtime 을 쓰지 않는다" || ng "A9 인계" "$(st)"
unhold
# A6~A8 빈 pid — mkdir 과 echo $$ 사이 창
mkdir -p "$QM_REFRESH_LOCKDIR"; : > "$QM_REFRESH_LOCKDIR/pid"
r=$(st); [ "$r" = "held:empty_pid:refresh" ] && ok "A6 [양성] 빈 pid(신선) → held(유예 후 재판정)" || ng "A6 빈 pid" "$r"
T7=$(( $(date +%s) - 1200 )); [ "$T7" -le "$BOOT" ] && T7=$((BOOT + 1))
if [ $(( $(date +%s) - T7 )) -gt 600 ]; then touch -d "@$T7" "$QM_REFRESH_LOCKDIR/pid"
  [ "$(st)" = "stale:empty_pid_expired:refresh" ] && ok "A7 [주입] 빈 pid 가 10분 넘게 비어 있음 → stale(파손)" || ng "A7 빈 pid 만료" "$(st)"
else sk "A7 빈 pid 만료" "부팅 후 10분 미만"; fi
touch -d "@$((BOOT - 60))" "$QM_REFRESH_LOCKDIR/pid"
[ "$(st)" = "stale:empty_pid_pre_boot:refresh" ] && ok "A7b [주입] 빈 pid + 부팅 전 → stale" || ng "A7b" "$(st)"
rm -f "$QM_REFRESH_LOCKDIR/pid"; touch "$QM_REFRESH_LOCKDIR"
[ "$(st)" = "held:empty_pid:refresh" ] && ok "A8 [양성] pid 파일 자체가 아직 없음(mkdir 직후) → held" || ng "A8" "$(st)"
# A8b 유예 중 기록이 도착하면 그 pid 로 판정한다
rm -rf "$QM_REFRESH_LOCKDIR"; mkdir -p "$QM_REFRESH_LOCKDIR"
bash -c 'sleep 0.4; echo $$ > "$1/pid"; exec sleep 300' _ "$QM_REFRESH_LOCKDIR" & BG+=("$!")
[ "$(RB_EMPTY_GRACE_S=3 st)" = "held:alive:refresh" ] && ok "A8b [양성] 유예 중 pid 도착 → 그 보유자로 재판정(held:alive)" || ng "A8b 유예 재판정" "$(st)"
unhold
# A10/A11 보유자 자손 = self (daily_refresh 가 잠금을 쥔 채 도는 배터리·백필이 자기 잠금에 막히지 않는다)
mkdir -p "$QM_REFRESH_LOCKDIR"
r=$(bash -c 'echo $$ > "$1/pid"; bash "$2" status | cut -f2,6' _ "$QM_REFRESH_LOCKDIR" "$SH")
[ "$r" = "$(printf 'state=self\treason=own_descendant')" ] && ok "A10 [양성] 보유자 자손(MSYS 사슬) → self · 진행" || ng "A10 self MSYS" "$r"
rm -rf "$QM_REFRESH_LOCKDIR"; mkdir -p "$QM_REFRESH_LOCKDIR"
SHM=$(cygpath -m "$SH")
r=$(bash -c 'echo $$ > "$1/pid"; Rscript -e "o <- system2(\"C:/Program Files/Git/usr/bin/bash.exe\", c(\"--noprofile\",\"--norc\",\"$2\",\"status\"), stdout=TRUE); cat(grep(\"^RB\", o, value=TRUE))"' _ "$QM_REFRESH_LOCKDIR" "$SHM" 2>/dev/null | cut -f2)
[ "$r" = "state=self" ] && ok "A11 [양성] 보유자 → Rscript → bash (MSYS 사슬 끊김) → 윈도 조상 사슬로 self" || ng "A11 self 윈도 사슬" "$r"
rm -rf "$QM_REFRESH_LOCKDIR"; mkdir -p "$QM_REFRESH_LOCKDIR"
# A11b 배터리 모양 — 보유자 → $( ) 서브셸이 exec 한 env → timeout → Rscript → bash. 윈도 사슬은 Cygwin exec 지점에서 끊기고
#   (새 프로세스의 부모 winpid = 사라진 원래 프로세스) MSYS 사슬은 네이티브 경계에서 끊긴다 → 두 사슬을 번갈아 타야 닿는다(실측 재현)
cat > "$T/a11b.sh" <<'EOS'
echo $$ > "$1/pid"
for i in 1; do o=$(env -u RB_NOPE timeout 120 Rscript -e "cat(grep('^RB', system2('C:/Program Files/Git/usr/bin/bash.exe', c('--noprofile','--norc','$2','status'), stdout=TRUE), value=TRUE))" 2>/dev/null); done
printf '%s
' "$o" | cut -f2
EOS
r=$(bash "$T/a11b.sh" "$QM_REFRESH_LOCKDIR" "$SHM"); [ "$r" = "state=self" ] && ok "A11b [양성] 보유자 → \$(exec env → timeout) → Rscript → bash (두 사슬 모두 끊기는 배터리 모양) → self" || ng "A11b self 혼합 사슬" "$r"
rm -rf "$QM_REFRESH_LOCKDIR"
# A12 writer 잠금 — 아침 체인 writer(다른 셸)가 쥐면 held · 풀면 free · 동시 보유 · 사망 보유자 stale
bash -c '. "$1"; rb_writer_acquire krx_update+naver_supplement; exec sleep 300' _ "$SH" & WP1=$!; BG+=("$WP1"); sleep 0.5
r=$(st); [ "$r" = "held:alive:writer" ] && ok "A12 [주입] writer 잠금 보유(타 셸) → held(lock=writer)" || ng "A12 writer held" "$r"
bash -c '. "$1"; rb_writer_acquire self_heal; rb_writer_release' _ "$SH"
[ "$(st)" = "held:alive:writer" ] && ok "A12b 다른 보유자가 풀어도 남은 보유자가 있으면 held" || ng "A12b 동시 보유" "$(st)"
kill "$WP1" 2>/dev/null; sleep 0.3
[ "$(st)" = "stale:dead:writer" ] && ok "A12c [주입] writer 가 해제 없이 죽음 → stale(dead) · 영구 차단 없음" || ng "A12c writer 사망" "$(st)"
rm -rf "$QM_RAWDATA_WRITER_LOCKDIR"
bash -c '. "$1"; rb_writer_acquire t; rb_writer_release; [ -d "$QM_RAWDATA_WRITER_LOCKDIR" ] && echo left || echo gone' _ "$SH" > "$T/wrel"
[ "$(cat "$T/wrel")" = "gone" ] && [ "$(st)" = "free::" ] && ok "A12d [양성] 획득→해제 → 잠금 디렉터리 제거 · free" || ng "A12d 해제" "$(cat "$T/wrel") $(st)"
# A13 대기 — 벽시계 상한
hold; ( sleep 3; unhold ) & BG+=("$!")
t0=$(date +%s); bash "$SH" wait 30 1 >/dev/null 2>&1; rc=$?; el=$(( $(date +%s) - t0 ))
[ "$rc" = 0 ] && [ "$el" -ge 2 ] && [ "$el" -lt 25 ] && ok "A13 [양성] 대기 중 해제 → rc 0 (${el}s)" || ng "A13 대기 해제" "rc=$rc el=$el"
hold; t0=$(date +%s); bash "$SH" wait 4 1 >/dev/null 2>&1; rc=$?; el=$(( $(date +%s) - t0 ))
[ "$rc" = 10 ] && [ "$el" -ge 4 ] && [ "$el" -lt 15 ] && ok "A13b [주입] 상한 뒤에도 held → rc 10 · 벽시계 상한(${el}s)" || ng "A13b 대기 상한" "rc=$rc el=$el"
unhold

echo "=== A-M. 판정기 돌연변이 (가드를 지우면 빨개져야 한다) ==="
mut(){ # $1 이름 $2 python 치환(old) $3 new → $T/mut_$1.sh
  "$PY" - "$SH" "$T/mut_$1.sh" "$2" "$3" <<'PYM'
import io,sys
s=io.open(sys.argv[1],encoding='utf-8').read(); o,n=sys.argv[3],sys.argv[4]
if s.count(o)!=1: sys.exit(3)
io.open(sys.argv[2],'w',encoding='utf-8',newline='').write(s.replace(o,n))
PYM
}
if mut dead 'if ! kill -0 "$pid" 2>/dev/null || [ ! -d "/proc/$pid" ]; then' 'if false; then'; then
  mkdir -p "$QM_REFRESH_LOCKDIR"; bash -c 'echo $$ > "$1/pid"' _ "$QM_REFRESH_LOCKDIR"
  r=$(st "$T/mut_dead.sh"); [ "$r" != "stale:dead:refresh" ] && ok "A-M1 생존 검사 제거 → 사망 보유자 판정이 바뀐다($r)" || ng "A-M1 생존 검사 돌연변이 미검출" "$r"
  rm -rf "$QM_REFRESH_LOCKDIR"; else ng "A-M1 앵커 없음" ""; fi
if mut dirm 'm=$(_rb_mtime "$F"); [ -n "$m" ] || m=$(_rb_mtime "$L")' 'm=$(_rb_mtime "$L")'; then
  hold; touch -d "@$((BOOT - 7200))" "$QM_REFRESH_LOCKDIR"
  r=$(st "$T/mut_dirm.sh"); [ "$r" != "held:alive:refresh" ] && ok "A-M2 디렉터리 mtime 판정 → 인계 모양에서 살아 있는 리프레시를 놓친다($r)" || ng "A-M2 미검출" "$r"
  unhold; else ng "A-M2 앵커 없음" ""; fi
if mut self 'if _rb_is_ancestor "$pid" "$wp"; then' 'if false; then'; then
  mkdir -p "$QM_REFRESH_LOCKDIR"
  r=$(bash -c 'echo $$ > "$1/pid"; bash "$2" status | cut -f2' _ "$QM_REFRESH_LOCKDIR" "$T/mut_self.sh")
  [ "$r" = "state=held" ] && ok "A-M3 자손 검사 제거 → 보유자 자손이 자기 잠금에 막힌다(held)" || ng "A-M3 미검출" "$r"
  rm -rf "$QM_REFRESH_LOCKDIR"; else ng "A-M3 앵커 없음" ""; fi
if mut hyb 'if [ -n "$m" ] && [ "$m" != "$cur" ]; then cur="$m"; break; fi' ':'; then
  mkdir -p "$QM_REFRESH_LOCKDIR"; r=$(bash "$T/a11b.sh" "$QM_REFRESH_LOCKDIR" "$(cygpath -m "$T/mut_hyb.sh")")
  [ "$r" = "state=held" ] && ok "A-M6 윈도→MSYS 복귀 제거 → 배터리 모양에서 보유자 자손이 held 로 막힌다" || ng "A-M6 미검출" "$r"
  rm -rf "$QM_REFRESH_LOCKDIR"; else ng "A-M6 앵커 없음" ""; fi
if mut reuse 'if [ -n "$s" ] && [ "$s" -gt $((m + 2)) ]; then' 'if false; then'; then
  hold; HP=$(cat "$QM_REFRESH_LOCKDIR/pid"); PST=$(stat -c %Y "/proc/$HP"); M5=$((PST - 30)); [ "$M5" -le "$BOOT" ] && M5=$((BOOT + 1))
  if [ "$M5" -lt $((PST - 2)) ]; then touch -d "@$M5" "$QM_REFRESH_LOCKDIR/pid"
    r=$(st "$T/mut_reuse.sh"); [ "$r" = "held:alive:refresh" ] && ok "A-M4 시작시각 대조 제거 → 재사용 pid 를 held 로 오판" || ng "A-M4 미검출" "$r"
  else sk "A-M4" "부팅 직후"; fi; unhold; else ng "A-M4 앵커 없음" ""; fi
if mut empty 'elif [ "$RB_J_AGE" -le "${RB_EMPTY_HELD_MAX_S:-600}" ]; then RB_J_STATE=held; RB_J_REASON=empty_pid' 'elif false; then RB_J_STATE=held; RB_J_REASON=empty_pid'; then
  mkdir -p "$QM_REFRESH_LOCKDIR"; : > "$QM_REFRESH_LOCKDIR/pid"
  r=$(st "$T/mut_empty.sh"); [ "$r" != "held:empty_pid:refresh" ] && ok "A-M5 빈 pid 보유 판정 제거 → mkdir 직후 창을 놓친다($r)" || ng "A-M5 미검출" "$r"
  rm -rf "$QM_REFRESH_LOCKDIR"; else ng "A-M5 앵커 없음" ""; fi

echo "=== B. R 래퍼 — 패리티 · fail-closed ==="
RWM=$(cygpath -m "$RW")
cat > "$T/b.R" <<EOF
\`%||%\` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
source("$RWM")
a <- commandArgs(trailingOnly = TRUE)
if (a[1] == "status") { s <- rb_status(); cat(sprintf("%s:%s:%s:%s\n", s\$state, s\$reason %||% "", s\$lock %||% "", s\$blocking)) }
if (a[1] == "paths")  { p <- rb_paths(); cat(p\$refresh, "\n") }
if (a[1] == "rexists") { p <- readLines(a[2], warn = FALSE)[1]; cat(file.exists(file.path(p, "pid")), "\n") }
if (a[1] == "rstatus") { p <- readLines(a[2], warn = FALSE)[1]; Sys.setenv(QM_REFRESH_LOCKDIR = p); s <- rb_status(); cat(sprintf("%s:%s:%s:%s\n", s\$state, s\$reason %||% "", s\$lock %||% "", s\$blocking)) }
if (a[1] == "wait")   { w <- rb_wait(as.numeric(a[2]), 1); cat(sprintf("%s:%s:%s\n", w\$proceed, w\$status\$state, w\$waited_s)) }
EOF
BM=$(cygpath -m /tmp/qm_daily_refresh.lock)
r=$(env -u QM_REFRESH_LOCKDIR Rscript "$T/b.R" paths 2>/dev/null | tr -d ' \r')
[ "$r" = "$BM" ] && ok "B1 [양성] 기본 경로 패리티 — R 래퍼가 쓰는 잠금 = bash 의 /tmp/qm_daily_refresh.lock ($r)" || ng "B1 경로 패리티" "R=$r bash=$BM"
# B1b R 이 MSYS 경로 문자열을 **직접** 풀면 없는 잠금을 본다(위임 이유) — 같은 문자열로 래퍼는 잠금을 본다
MS=$(cygpath -u "$T")/msys.lock; hold_ms(){ mkdir -p "$MS"; bash -c 'echo $$ > "$1/pid"; exec sleep 300' _ "$MS" & BG+=("$!"); sleep 0.5; }
hold_ms
printf '%s\n' "$MS" > "$T/mspath.txt"   # ★R 코드가 파일에서 읽는다 — 인자/env 로 넘기면 MSYS 가 C:/... 로 바꿔 검사가 무효가 된다(실측)
r1=$(Rscript "$T/b.R" rexists "$TM/mspath.txt" 2>/dev/null | tr -d ' \r'); r2=$(Rscript "$T/b.R" rstatus "$TM/mspath.txt" 2>/dev/null | tr -d '\r')
[ "$r1" = "FALSE" ] && [ "$r2" = "held:alive:refresh:TRUE" ] && ok "B1b [주입] R 코드 안의 MSYS 경로 '$MS' — R 직접 file.exists=FALSE(C:\\tmp 로 해석) · 래퍼 위임=held (\"/tmp\" 층 차이)" || ng "B1b" "r1=$r1 r2=$r2"
kill "$(cat "$MS/pid")" 2>/dev/null; rm -rf "$MS"
# B2 상태 패리티 (bash CLI 와 같은 결론)
r=$(Rscript "$T/b.R" status 2>/dev/null | tr -d '\r'); [ "$r" = "free:::FALSE" ] && ok "B2 [양성] free 패리티" || ng "B2 free" "$r"
hold; r=$(Rscript "$T/b.R" status 2>/dev/null | tr -d '\r'); [ "$r" = "held:alive:refresh:TRUE" ] && ok "B2b [주입] held 패리티 · blocking=TRUE" || ng "B2b held" "$r"
r=$(Rscript "$T/b.R" wait 3 2>/dev/null | tr -d '\r'); case "$r" in FALSE:held:[3-9]|FALSE:held:1[0-9]) ok "B3 [주입] rb_wait 상한 뒤 held → proceed=FALSE ($r)";; *) ng "B3 rb_wait held" "$r";; esac
unhold
mkdir -p "$QM_REFRESH_LOCKDIR"; bash -c 'echo $$ > "$1/pid"' _ "$QM_REFRESH_LOCKDIR"
r=$(Rscript "$T/b.R" status 2>/dev/null | tr -d '\r'); [ "$r" = "stale:dead:refresh:FALSE" ] && ok "B2c stale 패리티 · 진행(blocking=FALSE)" || ng "B2c stale" "$r"
rm -rf "$QM_REFRESH_LOCKDIR"
r=$(Rscript "$T/b.R" wait 3 2>/dev/null | tr -d '\r'); case "$r" in TRUE:free:[0-2]) ok "B3b [양성] 잠금 없음 → 즉시 진행 ($r)";; *) ng "B3b" "$r";; esac
printf '#!/usr/bin/env bash\necho garbage\n' > "$T/stub_rb.sh"
r=$(QVEST_RB_SH="$TM/stub_rb.sh" Rscript "$T/b.R" status 2>/dev/null | tr -d '\r')
[ "$r" = "error:no_status_line::TRUE" ] && ok "B4 [주입] 판정기가 판정 줄을 못 내면 error · blocking(fail-closed)" || ng "B4 fail-closed" "$r"

echo "=== C. 워커 · 엔진 재판정 · 러너 (샌드박스 실행 + 블록 추출) ==="
SBX="$T/sbx"; SBXM="$TM/sbx"; mkdir -p "$SBX/06_Registry" "$SBX/02_Infrastructure/ops" "$SBX/02_Infrastructure/alpha_search" "$SBX/.cache"
cp 06_Registry/reinforce_program.json "$SBX/06_Registry/"; cp "$RW" "$SBX/02_Infrastructure/ops/"
printf '{"code":"B1_1","block":"B1","label":"t","idea":"t","universe":{"kind":"k200_kq150"},"weighting":{"kind":"ew"}}\n' > "$SBX/spec.json"
wrun(){ rm -f "$SBX/out.json"; QM_ROOT="$SBXM" QVEST_RB_CELL_WAIT_S="${1:-3}" Rscript "$OPS/rf_cell_worker.R" "$SBXM/spec.json" 1 T_RB "$SBXM/out.json" >/dev/null 2>&1; echo $?; }
jget(){ "$PY" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); v=d
for k in sys.argv[2].split('.'): v=(v or {}).get(k) if isinstance(v,dict) else None
print('' if v is None else v)" "$1" "$2" 2>/dev/null; }
hold; t0=$(date +%s); rc=$(wrun 3); el=$(( $(date +%s) - t0 ))
if [ "$(jget "$SBX/out.json" deferred)" = "refresh_lock" ] && [ "$(jget "$SBX/out.json" ok)" = "False" ] && [ "$(jget "$SBX/out.json" barrier.state)" = "held" ] && [ "$rc" = 3 ] && [ ! -d "$SBX/stage_artifacts" ]; then
  ok "C1 [주입] 셀 시작 held → 대기 ${el}s 후 미측정 종료(deferred=refresh_lock · rc 3 · 러너 미적재)"
else ng "C1 워커 held" "rc=$rc deferred=$(jget "$SBX/out.json" deferred) err=$(jget "$SBX/out.json" err | head -c 120)"; fi
unhold
t0=$(date +%s); rc=$(wrun 3); el=$(( $(date +%s) - t0 )); e=$(jget "$SBX/out.json" err)
if [ -z "$(jget "$SBX/out.json" deferred)" ] && [ "$(jget "$SBX/out.json" ok)" = "False" ] && [ "$rc" = 1 ] && [ -n "$e" ] && ! printf '%s' "$e" | grep -qF "[refresh_barrier]" && [ "$el" -lt 30 ]; then
  ok "C2 [양성] 잠금 없음 → 배리어 통과 · 러너 적재 단계까지 진행(샌드박스엔 러너가 없어 거기서 실패 — deferred 아님)"
else ng "C2 워커 free" "rc=$rc deferred=$(jget "$SBX/out.json" deferred) err=$(printf '%s' "$e" | head -c 120)"; fi
cat > "$SBX/02_Infrastructure/alpha_search/run_paper_replication.R" <<EOF
run_paper_replication <- function(...) { writeLines(Sys.getenv("QVEST_RB_ENGINE_RECHECK"), "$SBXM/recheck_flag.txt"); stop(Sys.getenv("RB_STUB_MSG")) }
EOF
rc=$(RB_STUB_MSG="[refresh_barrier] RAWDATA 적재 직후 재판정 held(lock=refresh) — stub" wrun 3)
[ "$(jget "$SBX/out.json" deferred)" = "refresh_lock" ] && [ "$(jget "$SBX/out.json" barrier.reason)" = "engine_recheck" ] && [ "$(tr -d '\r\n' < "$SBX/recheck_flag.txt" 2>/dev/null)" = "1" ] \
  && ok "C3 [주입] 엔진 재판정 오류 → 워커가 미측정 종료로 접는다(deferred · reason=engine_recheck) · 러너 호출 시 재판정 스위치=1" \
  || ng "C3 엔진 재판정 접기" "deferred=$(jget "$SBX/out.json" deferred) flag=$(cat "$SBX/recheck_flag.txt" 2>/dev/null)"
rc=$(RB_STUB_MSG="boom" wrun 3)
[ -z "$(jget "$SBX/out.json" deferred)" ] && [ "$(jget "$SBX/out.json" err)" = "boom" ] && [ "$rc" = 1 ] && ok "C4 [대조] 일반 오류는 그대로 실패(deferred 아님 · rc 1)" || ng "C4 일반 오류" "deferred=$(jget "$SBX/out.json" deferred) rc=$rc"
# C5 엔진 재판정 블록 추출 실행
cat > "$T/c5.R" <<'EOF'
a <- commandArgs(trailingOnly = TRUE); src <- readLines(a[1], warn = FALSE, encoding = "UTF-8")
i0 <- grep('^if \\(identical\\(Sys.getenv\\("QVEST_RB_ENGINE_RECHECK"', src)[1]; i1 <- i0 + which(grepl("^\\}", src[(i0 + 1):length(src)]))[1]
if (is.na(i0) || is.na(i1)) { cat("NOBLOCK\n"); quit(status = 0) }
blk <- src[i0:i1]; if (identical(a[3], "mut")) blk <- c("{", blk[-1])       # 돌연변이: 스위치 조건 제거(무조건 재판정)
pat <- sub('^.*grepl\\("([^"]+)", \\.err\\).*$', "\\1", grep("\\.structural <- grepl\\(", readLines(a[2], warn = FALSE, encoding = "UTF-8"), value = TRUE)[1])
e <- new.env(); e$`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x; e$.RF_ROOT <- a[4]
r <- tryCatch({ eval(parse(text = paste(blk, collapse = "\n")), envir = e); "NOSTOP" }, error = function(z) conditionMessage(z))
cat(if (identical(r, "NOSTOP")) "NOSTOP" else if (startsWith(r, "[refresh_barrier]") && !grepl(pat, r)) "STOP_BARRIER" else paste("STOP_OTHER", r), "\n")
EOF
c5(){ Rscript "$T/c5.R" "$ROOT/02_Infrastructure/reinforcement/rf_cell_engine.R" "$OPS/reinforce_auto_parallel.R" "${1:-}" "$SBXM" 2>/dev/null | tr -d '\r' | sed 's/ *$//'; }
hold
r1=$(QVEST_RB_ENGINE_RECHECK= c5); r2=$(QVEST_RB_ENGINE_RECHECK=1 c5); r3=$(QVEST_RB_ENGINE_RECHECK= c5 mut)
[ "$r1" = "NOSTOP" ] && ok "C5a [양성] 스위치 없음(엔진 단독 검사·세션) → held 라도 비트 동일(재판정 안 함)" || ng "C5a" "$r1"
[ "$r2" = "STOP_BARRIER" ] && ok "C5b [주입] 스위치=1 + held → [refresh_barrier] 로 멈춘다 · 러너 구조적 판정 정규식에 안 걸린다(terminal 방지)" || ng "C5b" "$r2"
[ "$r3" = "STOP_BARRIER" ] && ok "C5c 돌연변이(스위치 조건 제거) → 단독 경로도 멈춘다 = 스위치가 실제로 가른다" || ng "C5c" "$r3"
unhold
r4=$(QVEST_RB_ENGINE_RECHECK=1 c5); [ "$r4" = "NOSTOP" ] && ok "C5d [양성] 스위치=1 + 잠금 없음 → 통과" || ng "C5d" "$r4"
# C6 러너 수집 절 추출 실행 — 미측정 종료는 원장에 아무것도 안 쓴다
cat > "$T/c6.R" <<'EOF'
a <- commandArgs(trailingOnly = TRUE); src <- readLines(a[1], warn = FALSE, encoding = "UTF-8")
i0 <- grep("^  R <- fromJSON\\(j\\$out, simplifyVector = FALSE\\)$", src)[1]
ic <- grep('^    jlog\\("cell_error"', src); ic <- ic[ic > i0][1]; i1 <- ic + which(grepl("^  \\}$", src[(ic + 1):length(src)]))[1]
if (is.na(i0) || is.na(i1)) { cat("NOBLOCK\n"); quit(status = 0) }
blk <- src[i0:i1]
if (identical(a[2], "mut")) { d0 <- grep('^  if \\(identical\\(as.character\\(R\\$deferred', blk)[1]; d1 <- d0 + which(grepl("^  \\}$", blk[(d0 + 1):length(blk)]))[1]
  if (is.na(d0)) { cat("NOMUT\n"); quit(status = 0) }; blk <- blk[-(d0:d1)] }
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
REC <- list(); LOG <- character(0); REACHED <- FALSE
rf_record_result <- function(...) REC[[length(REC) + 1L]] <<- list(...)
jlog <- function(ev, ...) LOG <<- c(LOG, ev)
.fail_count_of <- function(n) 0L; MAX_RETRY <- 2L; ROOT <- tempdir(); WDIR <- tempdir(); BID <- "T"
out <- file.path(tempdir(), "res.json")
writeLines(if (identical(a[3], "deferred")) '{"n":1,"code":"B1_1","ok":false,"deferred":"refresh_lock","waited_s":600,"barrier":{"state":"held","lock":"refresh","pid":"1","reason":"alive"},"err":"[refresh_barrier] x"}'
           else '{"n":1,"code":"B1_1","ok":false,"err":"boom"}', out)
library(jsonlite); jobs <- list(list(n = 1L, code = "B1_1", spec = "", out = out))
eval(parse(text = paste(c("for (j in jobs) {", blk, "REACHED <- TRUE", "}"), collapse = "\n")))
cat(sprintf("rec=%d log=%s", length(REC), paste(LOG, collapse = ",")), "\n")
EOF
c6(){ Rscript "$T/c6.R" "$OPS/reinforce_auto_parallel.R" "$1" "$2" 2>/dev/null | tr -d '\r' | sed 's/ *$//'; }
r=$(c6 cur deferred); [ "$r" = "rec=0 log=cell_deferred_refresh_lock" ] && ok "C6a [주입] 미측정 결과 → rf_record_result 0회 · cell_deferred_refresh_lock (pending 유지 · fail_count 무증가)" || ng "C6a" "$r"
r=$(c6 cur fail); [ "$r" = "rec=1 log=cell_error" ] && ok "C6b [대조] 일반 실패 → 기존대로 NA 기록 1회 + cell_error (계기가 기록을 본다)" || ng "C6b" "$r"
r=$(c6 mut deferred); [ "$r" = "rec=1 log=cell_error" ] && ok "C6c 돌연변이(미측정 분기 삭제) → 원장에 NA·fail_count 가 쓰인다 = 분기가 막고 있다" || ng "C6c" "$r"
# C7 러너 진입 배리어 — claim 전. 살아 있는 claim 으로 '배리어 통과'를 관측한다(통과하면 halt_claimed)
mkdir -p "$SBX/02_Infrastructure/ops"; cp "$OPS/rf_claim.R" "$SBX/02_Infrastructure/ops/"
printf '{"enabled":true,"daily_cap":999,"parallel_cells":1,"claim_stale_hours":6}\n' > "$T/rcfg.json"
sleep 300 & CLP=$!; BG+=("$CLP"); CLW=$(cat /proc/$CLP/winpid)
mkclaim(){ rm -rf "$T/claim"; mkdir -p "$T/claim"; printf '{"pid":%s,"started_at":"x","host":"t"}\n' "$CLW" > "$T/claim/owner.json"; }
prun(){ rm -f "$SBX/.cache/reinforce_auto_log.jsonl"; mkclaim; env -u QVEST_RF_CLAIM_HELD QM_ROOT="$SBXM" CLAUDE_PROJECT_DIR="$SBXM" QVEST_RF_CONFIG="$TM/rcfg.json" QVEST_RF_CLAIM="$TM/claim" \
        timeout 120 Rscript "$OPS/reinforce_auto_parallel.R" >/dev/null 2>&1; last_event "$SBX/.cache/reinforce_auto_log.jsonl"; }
hold; r=$(prun); o=$(cat "$T/claim/owner.json" 2>/dev/null)
[ "$r" = "halt_refresh_lock" ] && printf '%s' "$o" | grep -q "\"pid\":$CLW" && ok "C7a [주입] 러너 진입 held → halt_refresh_lock · claim 무접촉(사전 등록 전)" || ng "C7a" "event=$r"
unhold; r=$(prun); [ "$r" = "halt_claimed" ] && ok "C7b [양성] 잠금 없음 → 배리어 통과(다음 가드 halt_claimed 도달)" || ng "C7b" "event=$r"
mkdir -p "$QM_REFRESH_LOCKDIR"; bash -c 'echo $$ > "$1/pid"' _ "$QM_REFRESH_LOCKDIR"
r=$(prun); g=$(grep -c '"event":"refresh_lock_stale"' "$SBX/.cache/reinforce_auto_log.jsonl" 2>/dev/null)
[ "$r" = "halt_claimed" ] && [ "${g:-0}" -ge 1 ] && ok "C7c [주입] stale → 대기 없이 진행 + refresh_lock_stale 로그" || ng "C7c" "event=$r stale_lines=$g"
rm -rf "$QM_REFRESH_LOCKDIR"

echo "=== D. 틱 (샌드박스 ROOT 실행) ==="
TK="$OPS/reinforce_auto_tick.sh"; ST="$T/tick"; mkdir -p "$ST/.cache/scheduler_logs"; STM="$TM/tick"
trun(){ rm -f "$ST/.cache/reinforce_auto_log.jsonl" "$ST"/.cache/scheduler_logs/*.log; QM_ROOT="$STM" timeout 300 bash "${1:-$TK}" >/dev/null 2>&1; cat "$ST"/.cache/scheduler_logs/reinforce_auto_*.log 2>/dev/null; }
lanes_ran(){ grep -q "rf_replication_auto.sh" <<<"$1"; }   # 샌드박스엔 레인 파일이 없어 호출되면 'No such file' 에 경로가 찍힌다
hold; L=$(trun); J=$(last_event "$ST/.cache/reinforce_auto_log.jsonl")
[ "$J" = "halt_refresh_lock" ] && grep -q "halt_refresh_lock" <<<"$L" && ! lanes_ran "$L" && ok "D1 [주입] 틱 held → halt_refresh_lock 1줄 · 레인 0개 호출(틱 전체 건너뜀)" || ng "D1" "jl=$J lanes=$(lanes_ran "$L" && echo yes || echo no)"
grep -q '"src":"tick"' "$ST/.cache/reinforce_auto_log.jsonl" 2>/dev/null && "$PY" -c "import json,sys; [json.loads(l) for l in open(sys.argv[1],encoding='utf-8')]" "$ST/.cache/reinforce_auto_log.jsonl" 2>/dev/null \
  && ok "D1b halt 줄이 기존 jsonl 형식(ts·event·src) — 파싱 가능" || ng "D1b jsonl 형식"
unhold; L=$(trun)
[ ! -s "$ST/.cache/reinforce_auto_log.jsonl" ] && lanes_ran "$L" && ! grep -q "refresh_lock" <<<"$L" && ok "D2 [양성] 잠금 없음 → 레인 호출 · 배리어 흔적 0(비트 동일)" || ng "D2" "jsonl=$(wc -c < "$ST/.cache/reinforce_auto_log.jsonl" 2>/dev/null)"
mkdir -p "$QM_REFRESH_LOCKDIR"; bash -c 'echo $$ > "$1/pid"' _ "$QM_REFRESH_LOCKDIR"; L=$(trun)
grep -q '"event":"refresh_lock_stale"' "$ST/.cache/reinforce_auto_log.jsonl" 2>/dev/null && lanes_ran "$L" && ok "D3 [주입] stale → 대기 없이 레인 진행 + refresh_lock_stale 로그" || ng "D3" ""
rm -rf "$QM_REFRESH_LOCKDIR"
"$PY" - "$TK" "$T/tick_mut.sh" <<'PYM'
import io,re,sys
s=io.open(sys.argv[1],encoding='utf-8').read()
a=s.index('  RB_SH="$(dirname'); b=s.index('  # ★충실구현 대기가 있으면 먼저 처리한다')
io.open(sys.argv[2],'w',encoding='utf-8',newline='').write(s[:a]+s[b:])
PYM
cp "$T/tick_mut.sh" "$T/tick_mut_run.sh"; hold; L=$(trun "$T/tick_mut_run.sh")
lanes_ran "$L" && ok "D4 돌연변이(틱 배리어 삭제) → held 에서도 레인이 돈다 = 배리어가 막고 있다" || ng "D4 미검출" ""
unhold
nc=$(sed 's/#.*$//' "$TK"); lb=$(printf '%s\n' "$nc" | grep -n 'rb_status' | head -1 | cut -d: -f1); ll=$(printf '%s\n' "$nc" | grep -n 'rf_replication_auto.sh' | head -1 | cut -d: -f1)
[ -n "$lb" ] && [ -n "$ll" ] && [ "$lb" -lt "$ll" ] && ok "D5 틱 배리어($lb) < 첫 레인 호출($ll)" || ng "D5 순서" "$lb $ll"

echo "=== E. 충실구현 레인 (격리 요청·claim·jlog·config) ==="
RPA="$OPS/rf_replication_auto.sh"; E="$T/rp"; mkdir -p "$E"; EM="$TM/rp"
"$PY" -c "import io,json,os;d=json.loads(io.open(os.path.join(r'$ROOT','06_Registry','reinforce_auto_config.json'),'rb').read().decode('utf-8'));d['enabled']=True;io.open(r'$EM/cfg.json','w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))"
mkreq(){ printf '{"requested_at":"2026-01-01T00:00:00+0900","source":"test","paper":{"title":"t","paper_title":"t","url":"http://x","paper_key":"TEST_RB","source":"arxiv"},"status":"%s"}\n' "$1" > "$E/req.json"; }
mkdir -p "$E/.cache/scheduler_logs"
rprun(){ rm -f "$E/jlog.jsonl"; QM_ROOT="$EM" QVEST_PY="$PY" QVEST_RP_REQUEST="$EM/req.json" QVEST_RP_CLAIM="$EM/claim" QVEST_RP_JLOG="$EM/jlog.jsonl" QVEST_RF_CONFIG="$EM/cfg.json" QVEST_RP_ALLOW_CONCURRENT=1 \
         timeout 120 bash "$RPA" >/dev/null 2>&1; last_event "$E/jlog.jsonl"; }
mkreq pending; h0=$(md5sum < "$E/req.json"); hold; r=$(rprun)
[ "$r" = "halt_refresh_lock" ] && [ "$(md5sum < "$E/req.json")" = "$h0" ] && [ ! -d "$E/claim" ] && ok "E1 [주입] 레인 진입 held → halt_refresh_lock · 요청 바이트 불변 · claim 미생성(auto_retries 무소모)" || ng "E1" "event=$r"
unhold; mkreq done; r=$(rprun); [ "$r" = "no_pending_request" ] && ok "E2 [양성] 잠금 없음 → 배리어 통과(다음 게이트 no_pending_request 도달)" || ng "E2" "event=$r"
# E3 rp_verify 추출 실행 — 검증기(RAWDATA 첫 읽기) 직전 대기·연기
awk '/^rp_verify\(\)\{/{f=1} f{print} f&&/^\}/{exit}' "$RPA" > "$E/rpv.sh"
cat > "$E/run_rpv.sh" <<'EOF'
. "$1"; PY="$2"; REQ="$3"; ROOT=x; WDIR=x; P_URL=x; P_TITLE=x; P_KEY=x; JLOG="$4"; LOG="$5"; CALLS="$6"; RPV="$7"
jl(){ printf '%s\n' "$1" >> "$JLOG"; }
Rscript(){ echo called >> "$CALLS"; return 0; }
. "$RPV"; RB_VERIFY_WAIT_S=2 rp_verify; echo "rc=$?"
EOF
mkreq in_progress; rm -f "$E/calls" "$E/j2"; hold
r=$(bash "$E/run_rpv.sh" "$SH" "$PY" "$EM/req.json" "$E/j2" "$E/log" "$E/calls" "$E/rpv.sh" 2>/dev/null | tail -1)
sreq=$("$PY" -c "import json;d=json.load(open(r'$EM/req.json',encoding='utf-8'));print(d.get('status'),d.get('failure'))")
[ "$r" = "rc=75" ] && [ ! -e "$E/calls" ] && [ "$sreq" = "pending refresh_lock_deferred" ] && grep -q verify_deferred_refresh_lock "$E/j2" && ok "E3 [주입] 검증기 직전 held → 측정 0회 · pending+refresh_lock_deferred(재시도 예산 무소모) · rc 75" || ng "E3" "$r calls=$(cat "$E/calls" 2>/dev/null) req=$sreq"
unhold; mkreq in_progress; rm -f "$E/calls" "$E/j2"
r=$(bash "$E/run_rpv.sh" "$SH" "$PY" "$EM/req.json" "$E/j2" "$E/log" "$E/calls" "$E/rpv.sh" 2>/dev/null | tail -1)
[ "$(cat "$E/calls" 2>/dev/null)" = "called" ] && [ "$r" = "rc=0" ] && ok "E3b [양성] 잠금 없음 → 검증기 1회 호출(비트 동일 경로)" || ng "E3b" "$r"
nc=$(sed 's/#.*$//' "$RPA"); iv=$(printf '%s\n' "$nc" | grep -n '"$PREV_FAIL" = "refresh_lock_deferred"' | grep -- '-s "$WDIR/engine.R"' | head -1 | cut -d: -f1); ic=$(printf '%s\n' "$nc" | grep -n '^rf_llm_agent_run ' | head -1 | cut -d: -f1)
[ -n "$iv" ] && [ -n "$ic" ] && [ "$iv" -lt "$ic" ] && ok "E4 연기분 재시도 = verify-only 분기(엔진 보존 · 에이전트 앞 $iv < $ic)" || ng "E4" "$iv $ic"

echo "=== F. 2계층 드라이버 (블록 추출 실행) ==="
cat > "$T/f.R" <<'EOF'
a <- commandArgs(trailingOnly = TRUE); src <- readLines(a[1], warn = FALSE, encoding = "UTF-8")
i0 <- grep("^\\.rb_l2 <- tryCatch\\(\\{", src)[1]; i1 <- grep('^if \\(identical\\(\\.rb_l2\\$state, "stale"\\)\\)', src)[1]
ic <- grep("rf_claim_acquire\\(OWN", src)[1]; ia <- grep("rf_append_attempt\\(2L", src)[1]
if (is.na(i0) || is.na(i1)) { cat("NOBLOCK\n"); quit(status = 0) }
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
EV <- character(0); jl <- function(ev, ...) EV <<- c(EV, ev); quit <- function(...) stop("__QUIT__")
CODE_ROOT <- a[2]; ROOT <- a[3]
r <- tryCatch({ eval(parse(text = paste(src[i0:i1], collapse = "\n"))); "GO" }, error = function(e) conditionMessage(e))
cat(sprintf("%s|%s|order=%s", r, paste(EV, collapse = ","), isTRUE(i1 < ic && i1 < ia)), "\n")
EOF
fr(){ Rscript "$T/f.R" "$OPS/rf_l2_auto.R" "$ROOT" "$SBXM" 2>/dev/null | tr -d '\r' | sed 's/ *$//'; }
hold; r=$(fr); [ "$r" = "__QUIT__|halt_refresh_lock|order=TRUE" ] && ok "F1 [주입] held → halt_refresh_lock 후 종료 · 블록이 claim·원장 append 앞" || ng "F1" "$r"
unhold; r=$(fr); [ "$r" = "GO||order=TRUE" ] && ok "F2 [양성] 잠금 없음 → 로그 0 · 진행" || ng "F2" "$r"

echo "=== G. 적대검증 (착수 대기 · 재실행 미측정 · 연기 표식 · 러너 재실행) ==="
# ★2026-09-24 수리: 초판 G1/G5 는 "판정 미기록(rec=0)"을 정답으로 단정했다 — 그런데 표식 없음 = rf_adversary_ok TRUE(구 attempt 호환)라
#   검증 안 된 B5 칸이 승자·B4 바닥·승격 carry 로 소비됐다(적대검증 3인 BLOCKING · fail-open). 이제 정답 = 블록 칸 전부에
#   verdict "deferred_refresh_lock"(소비 보류) + 러너가 다음 tick 에 재실행. 구판 동작은 돌연변이(G1m·G5o)로 빨개짐을 보인다.
SA="$T/adv"; SAM="$TM/adv"; mkdir -p "$SA/06_Registry" "$SA/02_Infrastructure/ops" "$SA/.cache"
cat > "$T/g.R" <<'EOF'
a <- commandArgs(trailingOnly = TRUE); mode <- a[1]; ROOTC <- a[2]; SA <- a[3]; mut <- if (length(a) >= 4L) a[4] else ""
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
CALLS <- list(load = 0L, rec = 0L); VERD <- character(0); NRUN <- 0L
rf_load <- function(layer, root) { CALLS$load <<- CALLS$load + 1L
  mk <- function(n) list(n = n, cell_code = sprintf("B5_%d", n), grade = "B", essence = list(port_t = 1, calmar = 0.5, spec = ""))
  list(entries = list(list(base_id = "B", attempts = lapply(2:4, mk)))) }
rf_record_adversary <- function(layer, base_id, n, adversary, root) { CALLS$rec <<- CALLS$rec + 1L
  v <- as.character(adversary$verdict %||% ""); if (identical(v, "deferred_refresh_lock")) v <- "D"
  VERD <<- c(VERD, sprintf("%s:%s", n, v)) }
.rf_find <- function(led, bid) if (identical(bid, "B")) 1L else NA_integer_
.rf_attempt_code <- function(a) a$cell_code; .spec_sig <- function(...) ""; .ov_layers <- function(...) list()
src <- readLines(file.path(ROOTC, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"), warn = FALSE, encoding = "UTF-8")
mline <- function(pat) { k <- grep(pat, src, fixed = TRUE); if (length(k) != 1L) { cat("NOMUT\n"); quit(status = 0) }; k }
if (identical(mut, "m_entry")) src <- src[-mline(".adv_mark_deferred(layer, base_id, block, blk, .rb_block, root)")]
if (identical(mut, "m_rest"))  src <- src[-mline(".adv_mark_deferred(layer, base_id, block, .rest, .rb_mid, root)")]
if (identical(mut, "m_old")) { k <- mline('if (grepl("[refresh_barrier]", conditionMessage(e), fixed = TRUE)) {')
  src[k] <- sub("fixed = TRUE)) {", "fixed = TRUE)) { stop(e)", src[k], fixed = TRUE) }   # 구판 = 표식 없이 재상승
E <- new.env(parent = globalenv()); suppressMessages(eval(parse(text = paste(src, collapse = "\n")), envir = E))
E$.adv_load_spec <- function(...) list(code = "B5_2"); E$.adv_own_layers <- function(...) list(list(kind = "k"))
E$.adv_floor_of <- function(...) list(attempt = list(n = 1L, cell_code = "B5_0", essence = list(calmar = 0.1)), match = "t")
E$.adv_arm_meta <- function(...) list(); E$.adv_art_dir <- function(...) ""
# G_SEQ: 후보 순서대로 pass | 그 밖(= G_MSG 로 실패) — 마지막 값이 뒤를 채운다
E$.adv_run_tests <- function(rec, ...) { NRUN <<- NRUN + 1L; s <- strsplit(Sys.getenv("G_SEQ", "err"), ",")[[1]]
  if (identical(s[min(NRUN, length(s))], "pass")) { rec$verdict <- "pass"; return(rec) }; stop(Sys.getenv("G_MSG")) }
r <- tryCatch(if (mode == "rerun") E$.adv_rerun(list(code = "B5_2"), "T1", "B5_2", "B", 2L, SA, file.path(SA, "rr"), 60) else {
  if (mode == "entry")      E$rf_overlay_adversary_run("B", "B5", 1L, root = SA, dry_run = FALSE, cfg = list(enabled = TRUE))
  else if (mode == "dry")   E$rf_overlay_adversary_run("B", "B5", 1L, root = SA, dry_run = TRUE, cfg = list(enabled = TRUE))
  else if (mode == "loader") E$rf_overlay_adversary_run("B", "B5", 1L, root = SA, dry_run = FALSE, cfg = list(enabled = TRUE), rawdata_loader = function(...) NULL)
  else if (mode == "dryloader") E$rf_overlay_adversary_run("B", "B5", 1L, root = SA, dry_run = TRUE, cfg = list(enabled = TRUE), rawdata_loader = function(...) NULL)
  "RETURNED" }, error = function(e) paste("ERR", substr(conditionMessage(e), 1, 60)))
if (is.list(r)) r <- paste("STATUS", r$status)
cat(sprintf("%s|load=%d|rec=%d|v=%s", if (grepl("[refresh_barrier]", r, fixed = TRUE)) "ERR_BARRIER" else if (startsWith(r, "ERR")) "ERR_OTHER" else r,
            CALLS$load, CALLS$rec, paste(VERD, collapse = ",")), "\n")
EOF
gr(){ Rscript "$T/g.R" "$1" "$ROOT" "$SAM" "${2:-}" 2>/dev/null | tr -d '\r' | sed 's/ *$//' | tail -n 1; }
GB="[refresh_barrier] T1 재실행 워커가 미측정 종료"
hold
r=$(QVEST_RB_CELL_WAIT_S=2 G_MSG=boom gr entry); [ "$r" = "ERR_BARRIER|load=1|rec=3|v=2:D,3:D,4:D" ] && ok "G1 [주입] 착수 held(상한 뒤) → 블록 칸 전부 deferred_refresh_lock 표식 후 [refresh_barrier] 로 멈춤(검정 0)" || ng "G1" "$r"
r=$(QVEST_RB_CELL_WAIT_S=2 G_MSG=boom gr entry m_entry); [ "$r" = "ERR_BARRIER|load=1|rec=0|v=" ] && ok "G1m 돌연변이(착수 표식 줄 삭제 = 초판) → 표식 0 = 소비 가능으로 샌다 · 그 줄이 막고 있다" || ng "G1m" "$r"
r=$(QVEST_RB_CELL_WAIT_S=2 G_MSG=boom gr dry); [ "$r" = "RETURNED|load=1|rec=0|v=" ] && ok "G2 [대조] dry_run 은 배리어 대상 아님 · 원장 기록 0" || ng "G2" "$r"
r=$(QVEST_RB_CELL_WAIT_S=2 G_MSG=boom gr loader); [ "$r" = "RETURNED|load=1|rec=3|v=2:error,3:error,4:error" ] && ok "G3 [대조] 주입 로더(합성 RAWDATA) → 배리어 대상 아님 · 일반 오류는 기존대로 verdict error" || ng "G3" "$r"
unhold
r=$(G_MSG=boom gr entry); [ "$r" = "RETURNED|load=1|rec=3|v=2:error,3:error,4:error" ] && ok "G4 [양성] 잠금 없음 → 배리어 통과 · 기존 흐름(표식 0 · 판정 기록)" || ng "G4" "$r"
r=$(G_SEQ=barrier G_MSG="$GB" gr loader); [ "$r" = "ERR_BARRIER|load=1|rec=3|v=2:D,3:D,4:D" ] && ok "G5 [주입] 첫 칸 검정 중 배리어 미측정 → 그 칸·남은 칸 전부 표식(error 아님) 후 호출자로 올린다" || ng "G5" "$r"
r=$(G_SEQ=pass,barrier G_MSG="$GB" gr loader); [ "$r" = "ERR_BARRIER|load=1|rec=3|v=2:pass,3:D,4:D" ] && ok "G5b [주입] 둘째 칸 미측정 → 앞 칸 판정(pass) 유지 · 그 칸과 뒤 칸 표식" || ng "G5b" "$r"
r=$(G_SEQ=pass,barrier G_MSG="$GB" gr loader m_rest); [ "$r" = "ERR_BARRIER|load=1|rec=2|v=2:pass,3:D" ] && ok "G5m 돌연변이(남은 칸 표식 줄 삭제) → 뒤 칸(4) 판정 없음 = 소비 가능 · 그 줄이 막고 있다" || ng "G5m" "$r"
r=$(G_SEQ=barrier G_MSG="$GB" gr loader m_old); [ "$r" = "ERR_BARRIER|load=1|rec=0|v=" ] && ok "G5o 돌연변이(초판 = 표식 없이 재상승) → 기록 0 = fail-open 재현" || ng "G5o" "$r"
r=$(G_SEQ=barrier G_MSG="$GB" gr dryloader); [ "$r" = "ERR_BARRIER|load=1|rec=0|v=" ] && ok "G5d [대조] dry_run 중 미측정 → 원장 기록 0(표식도 안 쓴다) · 올리기만" || ng "G5d" "$r"
r=$(G_SEQ=err G_MSG=boom gr loader); [ "$r" = "RETURNED|load=1|rec=3|v=2:error,3:error,4:error" ] && ok "G5e [대조] 배리어 밖 검정 실패 → 기존대로 칸마다 verdict error · 멈추지 않음" || ng "G5e" "$r"
mkdir -p "$SA/02_Infrastructure/ops"; cat > "$SA/02_Infrastructure/ops/rf_cell_worker.R" <<'EOF'
a <- commandArgs(trailingOnly = TRUE)
writeLines(if (nzchar(Sys.getenv("G_DEFER"))) '{"ok":false,"deferred":"refresh_lock","err":"[refresh_barrier] stub"}' else '{"ok":false,"err":"stub boom"}', a[4])
EOF
r=$(G_DEFER=1 gr rerun); [ "$r" = "ERR_BARRIER|load=0|rec=0|v=" ] && ok "G6 [주입] 재실행 워커 deferred → .adv_rerun 이 [refresh_barrier] 로 올린다(status error 아님)" || ng "G6" "$r"
r=$(G_DEFER= gr rerun); [ "$r" = "STATUS error|load=0|rec=0|v=" ] && ok "G6b [대조] 재실행 워커 일반 실패 → 기존대로 status error" || ng "G6b" "$r"

# G7 — 실물 원장 writer(reinforce_ledger.R) + 실물 소비 술어(rf_runner_gates.R) 위에서 끝까지: 표식이 소비를 실제로 막는가
SB7="$T/adv7"; SB7M="$TM/adv7"; mkdir -p "$SB7/06_Registry"
cat > "$T/g7.R" <<'EOF'
a <- commandArgs(trailingOnly = TRUE); ROOTC <- a[1]; SB <- a[2]
suppressMessages({ library(data.table); library(jsonlite) })
invisible(capture.output(suppressMessages({
  source(file.path(ROOTC, "02_Infrastructure/reinforcement/reinforce_ledger.R"))
  source(file.path(ROOTC, "02_Infrastructure/reinforcement/rf_spec_sig.R"))
  source(file.path(ROOTC, "02_Infrastructure/reinforcement/rf_runner_gates.R"))
  source(file.path(ROOTC, "02_Infrastructure/reinforcement/rf_overlay_adversary.R")) })))
att <- function(n, code, adv = NULL) { x <- list(n = n, cell_code = code, grade = "B",
  essence = list(port_t = 1 + n / 10, calmar = 0.5, cell_code = code, spec = "")); if (!is.null(adv)) x$adversary <- adv; x }
obj <- .rf_skeleton(1L)
obj$entries <- list(list(base_id = "B", status = "active", attempts_used = 3L,
  attempts = list(att(1L, "B4_1"), att(2L, "B5_2"), att(3L, "B5_3", list(verdict = "pass", at = "old")))))
.rf_write(obj, 1L, SB)
ok_of <- function() { e <- rf_load(1L, SB)$entries[[1]]; paste(vapply(e$attempts, function(z) if (rf_adversary_ok(z)) "T" else "F", ""), collapse = ",") }
pre <- ok_of()
err <- tryCatch({ invisible(capture.output(rf_overlay_adversary_run("B", "B5", 1L, root = SB, cfg = list(enabled = TRUE)))); "NONE" },
                error = function(e) if (grepl("[refresh_barrier]", conditionMessage(e), fixed = TRUE)) "BARRIER" else paste("OTHER", conditionMessage(e)))
e <- rf_load(1L, SB)$entries[[1]]
vv <- vapply(e$attempts, function(z) { v <- as.character((z$adversary %||% list())$verdict %||% ""); if (identical(v, "deferred_refresh_lock")) "D" else v }, "")
b5 <- Filter(function(z) startsWith(z$cell_code, "B5_"), e$attempts)
n_cons <- length(Filter(rf_adversary_ok, b5))                               # 러너 .winner_of(gate = rf_adversary_ok) 와 같은 거르기
floor_n <- paste(vapply(Filter(rf_adversary_ok, e$attempts), function(z) as.character(z$n), ""), collapse = ",")   # 누적 바닥 후보
hold <- rf_grade_a_hold("B5_2", list(overlay_cell = list(kind = "vt", arm_id = "vt1")), NULL, e$attempts[[2]])
h3 <- paste(vapply(e$attempts[[3]]$adversary$history %||% list(), function(h) as.character(h$verdict %||% ""), ""), collapse = ",")
cat(sprintf("E2E|err=%s|pre=%s|post=%s|v=%s|b5_consumable=%d|floor=%s|hold=%s|hist3=%s\n", err, pre, ok_of(),
            paste(vv, collapse = ","), n_cons, floor_n, hold, h3))
EOF
g7(){ Rscript "$T/g7.R" "$ROOT" "$SB7M" 2>/dev/null | tr -d '\r' | grep '^E2E|' | tail -n 1; }
hold
# ★2026-09-24(P0-11 · 러너 관문 G_runner_gates): 적재 직후 B5_2(verdict 없음 · spec 판독 불가 = 자기 층 유무 모름)는
#   이제 소비 불가(unverified)다 — 구판은 verdict 부재를 통과로 읽어 pre=T,T,T 였다. B4_1·B5_3(pass) 은 그대로 T.
#   이 절이 재는 것(표식이 소비를 막는다 · post · 이력 보존)은 불변이다.
r=$(QVEST_RB_CELL_WAIT_S=2 g7); [ "$r" = "E2E|err=BARRIER|pre=T,F,T|post=T,F,F|v=,D,D|b5_consumable=0|floor=1|hold=TRUE|hist3=pass" ] && ok "G7 [주입·실물 원장] held → B5 칸 표식 · 소비 술어 F(승자·바닥 후보 0) · A 보류 · 이전 pass 는 이력 보존(B4 칸 무접촉)" || ng "G7" "$r"
unhold
r=$(g7); [ "$r" = "E2E|err=NONE|pre=T,F,T|post=T,F,F|v=,not_candidate,not_candidate|b5_consumable=0|floor=1|hold=TRUE|hist3=pass" ] && ok "G7b [양성·실물 원장] 잠금 없음 → 표식 0 · 기존 판정 경로(spec 부재 = not_candidate)" || ng "G7b" "$r"

# G8 — 러너 연기분 재실행(설치본 블록 추출 실행) · 순서(entry 선택 뒤 · 예산/소진·승자 해석 앞) · 표식 문자열 패리티
RP="$OPS/reinforce_auto_parallel.R"
SB8="$T/adv8"; SB8M="$TM/adv8"; mkdir -p "$SB8/02_Infrastructure/reinforcement"
cat > "$SB8/02_Infrastructure/reinforcement/rf_overlay_adversary.R" <<'EOF'
rf_overlay_adversary_run <- function(base_id, block = "B5", layer = 1L, root = NULL, ...) {
  G8$calls <<- c(G8$calls, paste0(base_id, ":", block))
  if (nzchar(Sys.getenv("G8_FAIL"))) stop("[refresh_barrier] stub held again")
  G8$verdict <<- "pass"
  data.table::data.table(code = "B5_2", verdict = "pass") }
EOF
cat > "$T/g8.R" <<'EOF'
a <- commandArgs(trailingOnly = TRUE); RP <- a[1]; ROOTC <- a[2]; ROOT <- a[3]; mode <- a[4]; mut <- identical(a[5], "mut")
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x
src <- readLines(RP, warn = FALSE, encoding = "UTF-8")
# 2026-09-24(통합 검증 I2): 블록이 rebase 뒤 규약 거부 재검정 술어(rf_runner_gates.R::rf_adversary_rerun_blocks)를 부른다 — 실물 적재
Sys.setenv(QM_ROOT = ROOTC)
invisible(capture.output(suppressMessages({ library(data.table); library(jsonlite)
  source(file.path(ROOTC, "02_Infrastructure/reinforcement/reinforce_ledger.R"))
  source(file.path(ROOTC, "02_Infrastructure/reinforcement/rf_spec_sig.R"))
  source(file.path(ROOTC, "02_Infrastructure/reinforcement/rf_runner_gates.R")) })))
av <- readLines(file.path(ROOTC, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"), warn = FALSE, encoding = "UTF-8")
DV <- local({ e <- new.env(); eval(parse(text = grep("^ADV_DEFERRED_VERDICT <- ", av, value = TRUE)), envir = e); e$ADV_DEFERRED_VERDICT })
i0 <- grep("^\\.adv_def_blk <- unique\\(", src)[1]
i1 <- if (is.na(i0)) NA else i0 - 1L + which(src[i0:length(src)] == "}")[1]
ie <- grep("^E <- act\\[\\[1\\]\\]; BID <- E\\$base_id", src)[1]; iu <- grep("^used <- as.integer\\(E\\$attempts_used", src)[1]
iw <- grep('^w5 <- \\.winner_of\\("B5"', src)[1]; ix <- grep('\\.exhaust_and_delegate\\("budget"\\)', src)[1]
if (is.na(i0) || is.na(i1)) { cat("G8|NOBLOCK\n"); quit(status = 0) }
blk <- src[i0:i1]
if (mut) blk <- gsub('"deferred_refresh_lock"', '"deferred_X"', blk, fixed = TRUE)
G8 <- list(calls = character(0), verdict = if (mode == "none") "pass" else DV)
EV <- character(0); jlog <- function(ev, ...) EV <<- c(EV, ev)
mkE <- function(v) list(base_id = "B", status = "active", attempts = list(
  list(n = 1L, cell_code = "B4_1", essence = list(port_t = 1)),
  list(n = 2L, cell_code = "B5_2", essence = list(port_t = 1), adversary = list(verdict = v, block = "B5"))))
rf_load <- function(layer, root) list(entries = list(mkE(G8$verdict)))
BID <- "B"; E <- mkE(G8$verdict); E0 <- E
eval(parse(text = paste(blk, collapse = "\n")))
cat(sprintf("G8|ev=%s|calls=%s|E_v=%s|same=%s|order=%s\n", paste(EV, collapse = ","), paste(G8$calls, collapse = ","),
            E$attempts[[2]]$adversary$verdict, identical(E, E0),
            isTRUE(ie < i0 && i1 < iu && i1 < iw && i1 < ix)))
EOF
g8(){ Rscript "$T/g8.R" "$RP" "$ROOT" "$SB8M" "$@" 2>/dev/null | tr -d '\r' | grep '^G8|' | tail -n 1; }
r=$(g8 marker); [ "$r" = "G8|ev=adversary_rerun_deferred,adversary_rerun_done|calls=B:B5|E_v=pass|same=FALSE|order=TRUE" ] && ok "G8 [주입] 표식 있는 entry → 승자 해석·예산 판정 앞에서 적대검증 재실행 · E 재적재(판정 반영)" || ng "G8" "$r"
r=$(g8 none); [ "$r" = "G8|ev=|calls=|E_v=pass|same=TRUE|order=TRUE" ] && ok "G8b [양성] 표식 없음 → 호출 0 · 로그 0 · E 불변(잠금 없음 경로 비트 동일)" || ng "G8b" "$r"
r=$(G8_FAIL=1 g8 marker); [ "$r" = "G8|ev=adversary_rerun_deferred,adversary_rerun_failed|calls=B:B5|E_v=deferred_refresh_lock|same=TRUE|order=TRUE" ] && ok "G8c [주입] 재실행도 막힘 → 로그 · 표식 유지(소비 보류 지속 · 다음 tick 재시도)" || ng "G8c" "$r"
r=$(g8 marker mut); [ "$r" = "G8|ev=|calls=|E_v=deferred_refresh_lock|same=TRUE|order=TRUE" ] && ok "G8m 돌연변이(러너 표식 문자열 불일치) → 재실행 0 = 영구 보류 · 문자열 패리티가 막고 있다" || ng "G8m" "$r"

echo "=== H. 아침 writer 잠금 · daily_refresh 무변경 ==="
MB="$OPS/morning_briefing.sh"; nc=$(sed 's/#.*$//' "$MB")
ln(){ printf '%s\n' "$nc" | grep -nF -- "$1" | head -1 | cut -d: -f1; }
a1=$(ln 'rb_writer_acquire "krx_update+naver_supplement"'); k=$(ln 'morning_steps/krx_update.R'); nv=$(ln 'morning_steps/naver_supplement.R'); ar=$(ln 'morning_steps/arrow_extend.R')
r1=$(printf '%s\n' "$nc" | grep -n '^rb_writer_release$' | cut -d: -f1 | head -1); r2=$(printf '%s\n' "$nc" | grep -n '^rb_writer_release$' | cut -d: -f1 | sed -n 2p)
a2=$(ln 'rb_writer_acquire "self_heal"'); sh=$(ln 'morning_steps/self_heal.R')
if [ -n "$a1" ] && [ -n "$k" ] && [ -n "$nv" ] && [ -n "$r1" ] && [ -n "$ar" ] && [ "$a1" -lt "$k" ] && [ "$k" -lt "$nv" ] && [ "$nv" -lt "$r1" ] && [ "$r1" -lt "$ar" ]; then
  ok "H1 krx_update·naver_supplement 가 writer 잠금 안($a1<$k<$nv<$r1) · arrow 전에 해제"; else ng "H1 writer 잠금 범위" "$a1 $k $nv $r1 $ar"; fi
[ -n "$a2" ] && [ -n "$sh" ] && [ -n "$r2" ] && [ "$a2" -lt "$sh" ] && [ "$sh" -lt "$r2" ] && ok "H2 self_heal 이 writer 잠금 안($a2<$sh<$r2)" || ng "H2 self_heal 범위" "$a2 $sh $r2"
grep -q "trap 'rb_writer_release' EXIT" <<<"$nc" && ok "H3 비정상 종료에도 해제(EXIT trap)" || ng "H3 EXIT trap"
! grep -q "qm_daily_refresh.lock" <<<"$nc" && ok "H4 writer 는 리프레시 잠금을 쥐지 않는다(쥐면 그 사이 뜬 daily_refresh 가 '이미 실행 중' 으로 종료)" || ng "H4 리프레시 잠금 공유"
[ "$(grep -c 'refresh_barrier\|qm_rawdata_writer' 02_Infrastructure/data/daily_refresh.sh)" = 0 ] && ok "H5 daily_refresh.sh 무변경(배리어 배선 0)" || ng "H5 daily_refresh.sh 에 배리어 흔적"
bash -n "$MB" && ok "H6 morning_briefing.sh 구문" || ng "H6 구문"

echo ""
echo "결과: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
printf '{"test":"refresh_barrier","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
