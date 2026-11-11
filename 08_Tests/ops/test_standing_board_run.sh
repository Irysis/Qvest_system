#!/usr/bin/env bash
#==============================================================================
# test_standing_board_run.sh — 상설 판 정기 실행(02_Infrastructure/ops/standing_board_run.sh · 2026-11-10) 격리 검사
#   임시 루트(RC_ROOT_POSIX · RC_SA_ROOT)에 가짜 round.sh(호출만 적는다 · R 미호출)와 정본 배리어 판정기 사본을 두고 돌린다.
#   실제 판 · 원장 · 측정 · 발송은 없다. 배리어 잠금 경로는 판정기의 검사 주입 변수(QM_REFRESH_LOCKDIR · QM_RAWDATA_WRITER_LOCKDIR)로만 바꾼다.
#   재는 것: 판 없음 = 조용히 0 · 등록 전 · 비상설 · 이름 불일치 판 무시 · 드라이런 = 측정 · round.sh 미호출 · 잠금(살아 있는 보유자 = 건너뜀 ·
#     죽은 pid = 인계 · 끝나면 해제) · 대기 있음 + 배리어 열림 = scan → pending → standing-measure → standing-report · 배리어 잠김(정본 판정기 —
#     갓 만든 빈 pid 잠금) = 측정 건너뜀 · 대기 없음 = 측정 없음 · --send 전달 · 로그 파일 · 단계 실패 = rc 1 · 판정기 없음 = 측정 막음(fail-closed)
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
RUNNER="${QVEST_TEST_SBR_SRC:-$ROOT/02_Infrastructure/ops/standing_board_run.sh}"     # 검사 주입 = 교체 전 후보판을 같은 검사로 잰다
P=0; F=0
ok(){ P=$((P+1)); printf '  OK    %s\n' "$1"; }
ng(){ F=$((F+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export RC_ROOT_POSIX="$T" RC_SA_ROOT="$T"
export QM_REFRESH_LOCKDIR="$T/no_refresh_lock" QM_RAWDATA_WRITER_LOCKDIR="$T/no_writer_lock"
CALLS="$T/calls.log"
go(){ "$BASH" "$RUNNER" "$@" 2>&1; }

# ── 1. 판 없음 ────────────────────────────────────────────────────────────────
o=$(go); rc=$?
{ [ "$rc" = "0" ] && [ -z "$o" ] && [ ! -d "$T/.cache/scheduler_logs" ]; } && ok "1 판 없음 = 조용히 0 종료(출력 · 로그 없음)" || ng "1 판 없음" "rc=$rc out=$o"

# ── 임시 루트 꾸미기: 판 4개(등록 상설 · 등록 전 상설 · 비상설 · 이름 불일치) · 가짜 round.sh · 정본 배리어 사본 ──────────
mkspec(){ mkdir -p "$T/04_Research/programs/$1/$2"; printf '{\n  "schema": "x",\n  "program": "%s",\n  "round_id": "%s",\n  "standing": %s,\n  "standing_cfg": {\n    "program": "P9_OTHER"\n  }\n}\n' "$1" "$3" "$4" > "$T/04_Research/programs/$1/$2/round_spec.json"; }
mkpre(){ mkdir -p "$T/stage_artifacts/programs/$1/$2"; echo '{}' > "$T/stage_artifacts/programs/$1/$2/prereg.json"; }
mkspec P1_RETURN P1S99_t P1S99_t true;  mkpre P1_RETURN P1S99_t
mkspec P1_RETURN P1S98_u P1S98_u true                                   # 등록 전
mkspec P1_RETURN P1R97_v P1R97_v false; mkpre P1_RETURN P1R97_v         # 비상설
mkspec P1_RETURN P1S96_w P1S96_other true; mkpre P1_RETURN P1S96_w      # 사양 round_id ≠ 디렉터리
mkdir -p "$T/04_Research/programs/_lib/round_core" "$T/02_Infrastructure/ops"
cat > "$T/04_Research/programs/_lib/round_core/round.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$RC_ROOT_POSIX/calls.log"
st="$2"; v="STUB_RC_${st//-/_}"
[ "$st" = "pending" ] && printf '%s' "${STUB_PENDING:-}"
[ "$st" = "standing-measure" ] && [ -n "${STUB_SENT:-}" ] && { mkdir -p "$RC_ROOT_POSIX/.cache/round_core/state"; echo "status=$STUB_SENT rc=0" > "$RC_ROOT_POSIX/.cache/round_core/state/$(basename "$1").standing"; }
exit "${!v:-0}"
EOF
cp "$ROOT/02_Infrastructure/ops/refresh_barrier.sh" "$T/02_Infrastructure/ops/refresh_barrier.sh"

# ── 2. 드라이런 ────────────────────────────────────────────────────────────────
rm -f "$CALLS"; o=$(STUB_PENDING=$'P1S99_x\n' go --dry-run); rc=$?
{ [ "$rc" = "0" ] && [ ! -f "$CALLS" ] && printf '%s' "$o" | grep -q "P1S99_t: scan" && ! printf '%s' "$o" | grep -qE "P1S98_u|P1R97_v|P1S96_w" \
  && printf '%s' "$o" | grep -q "판 1" && [ ! -d "$T/.cache/scheduler_logs" ] && [ ! -d "$T/.cache/standing_board_run.lock" ]; } \
  && ok "2 드라이런 = 할 일만 출력 · round.sh(측정 포함) 미호출 · 잠금 · 로그 없음 · 등록 전 · 비상설 · 이름 불일치 판 무시" || ng "2 드라이런" "rc=$rc calls=$(cat "$CALLS" 2>/dev/null) out=$o"

# ── 3. 잠금 — 살아 있는 보유자(이 셸) = 건너뜀 ─────────────────────────────────────
mkdir -p "$T/.cache/standing_board_run.lock"; echo "$$" > "$T/.cache/standing_board_run.lock/pid"
rm -f "$CALLS"; o=$(STUB_PENDING=$'P1S99_x\n' go); rc=$?
{ [ "$rc" = "0" ] && [ ! -f "$CALLS" ] && printf '%s' "$o" | grep -q "건너뜀" && [ -d "$T/.cache/standing_board_run.lock" ]; } \
  && ok "3 동시 실행 방지 — 살아 있는 보유자 잠금 = 0 종료 · round.sh 미호출 · 남의 잠금 유지" || ng "3 잠금" "rc=$rc out=$o"
o=$(go --dry-run); printf '%s' "$o" | grep -q "잠금 $$" && ok "3b 드라이런은 잠금 보유자를 보여준다" || ng "3b 드라이런 잠금 표시" "$o"

# ── 4. 죽은 pid 잠금 = 인계 · 대기 있음 + 배리어 열림 = 전 단계 ───────────────────────
"$BASH" -c 'exit 0' & dpid=$!; wait "$dpid"; echo "$dpid" > "$T/.cache/standing_board_run.lock/pid"
rm -f "$CALLS"; o=$(STUB_PENDING=$'P1S99_x\nP1S99_y\n' go); rc=$?
exp=$'04_Research/programs/P1_RETURN/P1S99_t scan\n04_Research/programs/P1_RETURN/P1S99_t pending\n04_Research/programs/P1_RETURN/P1S99_t standing-measure\n04_Research/programs/P1_RETURN/P1S99_t standing-report'
got=$(cat "$CALLS" 2>/dev/null)
{ [ "$rc" = "0" ] && [ "$got" = "$exp" ] && [ ! -d "$T/.cache/standing_board_run.lock" ]; } \
  && ok "4 죽은 pid 잠금 인계 · scan → pending → standing-measure → standing-report(드라이런 · --send 없음) · 끝나면 잠금 해제" || ng "4 전 단계" "rc=$rc got=[$got] out=$o"
LOGF=$(ls "$T/.cache/scheduler_logs"/standing_board_*.log 2>/dev/null | head -n 1)
{ [ -n "$LOGF" ] && grep -q "standing-measure(대기 2" "$LOGF"; } && ok "4b 로그 = .cache/scheduler_logs/standing_board_<시각>.log(대기 수 · 단계)" || ng "4b 로그" "$LOGF"

# ── 5. 배리어 잠김(정본 판정기 — 갓 만든 빈 pid 잠금 = held) = 측정 건너뜀 · 보고는 한다 ──────────
mkdir -p "$T/held_lock"; : > "$T/held_lock/pid"
rm -f "$CALLS"; o=$(QM_REFRESH_LOCKDIR="$T/held_lock" STUB_PENDING=$'P1S99_x\n' go); rc=$?
got=$(cat "$CALLS" 2>/dev/null)
{ [ "$rc" = "0" ] && ! printf '%s' "$got" | grep -q standing-measure && printf '%s' "$got" | grep -q standing-report && printf '%s' "$o" | grep -q "배리어 held"; } \
  && ok "5 배리어 잠김 = 이번 틱 측정 건너뜀(기다리지 않음) · 보고는 그대로" || ng "5 배리어 잠김" "rc=$rc got=[$got] out=$o"
o=$(QM_REFRESH_LOCKDIR="$T/held_lock" go --dry-run); printf '%s' "$o" | grep -q "standing-measure 건너뜀" && ok "5b 드라이런이 배리어 잠김을 보여준다" || ng "5b" "$o"

# ── 6. 대기 없음 = 측정 없음 ───────────────────────────────────────────────────
rm -f "$CALLS"; o=$(STUB_PENDING="" go); rc=$?; got=$(cat "$CALLS" 2>/dev/null)
{ [ "$rc" = "0" ] && ! printf '%s' "$got" | grep -q standing-measure && printf '%s' "$o" | grep -q "측정 대기 0"; } && ok "6 대기 없음 = standing-measure 미호출" || ng "6 대기 없음" "got=[$got]"

# ── 7. --send 전달 ────────────────────────────────────────────────────────────
rm -f "$CALLS"; o=$(STUB_PENDING="" go --send); got=$(cat "$CALLS" 2>/dev/null)
printf '%s' "$got" | grep -qx "04_Research/programs/P1_RETURN/P1S99_t standing-report --send" && ok "7 --send 일 때만 보고 발송 인자" || ng "7 --send" "$got"

# ── 8. 단계 실패 = rc 1(다른 단계는 계속) · 판정기 없음 = 측정 막음 ────────────────────
rm -f "$CALLS"; o=$(STUB_RC_scan=3 STUB_PENDING=$'P1S99_x\n' go); rc=$?; got=$(cat "$CALLS" 2>/dev/null)
{ [ "$rc" = "1" ] && printf '%s' "$got" | grep -q standing-measure && printf '%s' "$got" | grep -q standing-report; } && ok "8 scan 실패 = rc 1 · 대기 측정 · 보고는 계속" || ng "8 실패 rc" "rc=$rc got=[$got]"
rm -f "$CALLS"; o=$(RB_SH="$T/no_such_barrier.sh" STUB_PENDING=$'P1S99_x\n' go); got=$(cat "$CALLS" 2>/dev/null)
! printf '%s' "$got" | grep -q standing-measure && ok "8b 배리어 판정기 없음 = 측정 막음(fail-closed)" || ng "8b fail-closed" "got=[$got]"
rm -f "$CALLS"; o=$(STUB_RC_pending=1 STUB_PENDING=$'P1S99_x\n' go); rc=$?; got=$(cat "$CALLS" 2>/dev/null)
{ [ "$rc" = "1" ] && ! printf '%s' "$got" | grep -q standing-measure; } && ok "8c pending 판독 실패 = 측정 건너뜀 · rc 1" || ng "8c" "rc=$rc got=[$got]"

# ── 9. 뮤테이션 — 드라이런 분기 · 잠금 검사 · 배리어 검사를 지운 사본은 위 검사에 걸린다 ──────────────
mut(){ local name="$1" from="$2" to="$3" m="$T/mut_$1.sh"
  python -c "import sys;s=open(sys.argv[1],encoding='utf-8').read();f,t=sys.argv[3],sys.argv[4];assert f in s,'no target';open(sys.argv[2],'w',encoding='utf-8',newline='').write(s.replace(f,t,1))" "$RUNNER" "$m" "$from" "$to" || { ng "9 $name 치환 실패" ""; return 1; }
  echo "$m"; }
m=$(mut dry 'if [ "$DRY" = "1" ]; then' 'if false; then') && { rm -f "$CALLS"; STUB_PENDING=$'P1S99_x\n' "$BASH" "$m" --dry-run >/dev/null 2>&1; [ -f "$CALLS" ] && ok "9a 뮤턴트(드라이런 분기 제거) 검출 — round.sh 가 불렸다" || ng "9a 뮤턴트 미검출" ""; }
m=$(mut lock 'if [ -n "$h" ]; then echo' 'if false; then echo') && { mkdir -p "$T/.cache/standing_board_run.lock"; echo "$$" > "$T/.cache/standing_board_run.lock/pid"; rm -f "$CALLS"
  STUB_PENDING="" "$BASH" "$m" >/dev/null 2>&1; [ -f "$CALLS" ] && ok "9b 뮤턴트(잠금 보유자 검사 제거) 검출 — 잠긴 채 실행" || ng "9b 뮤턴트 미검출" ""; rm -rf "$T/.cache/standing_board_run.lock"; }
m=$(mut barrier 'if [ "$brc" != "0" ]; then log' 'if false; then log') && { rm -f "$CALLS"
  QM_REFRESH_LOCKDIR="$T/held_lock" STUB_PENDING=$'P1S99_x\n' "$BASH" "$m" >/dev/null 2>&1; grep -q standing-measure "$CALLS" 2>/dev/null && ok "9c 뮤턴트(배리어 검사 제거) 검출 — 잠김에도 측정" || ng "9c 뮤턴트 미검출" ""; }

# ── 10. 데이터 신선도 차단(11-10) — 실행기가 대기 측정을 건너뛰면(센티널 judged_data_stale) 로그 · 출력에 한 줄 · rc 0 · 돌연변이 = 침묵 ─────
rm -f "$CALLS"; o=$(STUB_SENT=judged_data_stale STUB_PENDING=$'P1S99_x
' go); rc=$?
{ [ "$rc" = "0" ] && printf '%s' "$o" | grep -q "데이터 신선도 미달 — 측정 대기 1 건너뜀"; } && ok "10 신선도 미달 = 건너뜀 표시 · rc 0(판정은 진행)" || ng "10 신선도 표시" "rc=$rc out=$o"
rm -f "$T/.cache/round_core/state/P1S99_t.standing"
m=$(mut fresh 'grep -q "status=judged_data_stale" "$sent"' 'false') && { o=$(STUB_SENT=judged_data_stale STUB_PENDING=$'P1S99_x
' "$BASH" "$m" 2>&1)
  ! printf '%s' "$o" | grep -q "데이터 신선도 미달" && ok "10b 뮤턴트(센티널 판독 제거) 검출 — 표시 사라짐" || ng "10b 뮤턴트 미검출" ""; }
rm -f "$T/.cache/round_core/state/P1S99_t.standing"

# ── 11. 세션 보류(tick_hold · 2026-11-11 도훈 "파일럿부터") — 판 폴더에 tick_hold 가 있으면 그 판은 scan · 측정 · 보고를 하지 않는다 ─────
HOLD="$T/04_Research/programs/P1_RETURN/P1S99_t/tick_hold"
printf '파일럿 통과 뒤 해제(시험)\n둘째 줄은 출력하지 않는다\n' > "$HOLD"
NLOG0=$(ls "$T/.cache/scheduler_logs"/standing_board_*.log 2>/dev/null | wc -l)
rm -f "$CALLS"; o=$(STUB_PENDING=$'P1S99_x\n' go); rc=$?
NLOG1=$(ls "$T/.cache/scheduler_logs"/standing_board_*.log 2>/dev/null | wc -l)
{ [ "$rc" = "0" ] && [ ! -f "$CALLS" ] && printf '%s' "$o" | grep -q "P1S99_t: 보류(tick_hold — 파일럿 통과 뒤 해제(시험)) — 이번 틱 건너뜀" \
  && ! printf '%s' "$o" | grep -q "둘째 줄" && [ "$NLOG0" = "$NLOG1" ] && [ ! -d "$T/.cache/standing_board_run.lock" ]; } \
  && ok "11 보류 = round.sh 미호출(scan · 측정 · 보고 없음) · 사유 첫 줄만 한 줄로 알림 · rc 0 · 잠금 · 로그 없음" || ng "11 보류" "rc=$rc calls=$(cat "$CALLS" 2>/dev/null) out=$o"
o=$(go --dry-run)
{ printf '%s' "$o" | grep -q "등록된 판 0 · 보류 1" && printf '%s' "$o" | grep -q "P1S99_t: 보류(tick_hold" && ! printf '%s' "$o" | grep -q "P1S99_t: scan"; } \
  && ok "11b 드라이런이 보류 판을 보여준다(등록된 판 0 · 보류 1)" || ng "11b 드라이런 보류" "$o"
: > "$HOLD"; o=$(go); printf '%s' "$o" | grep -q "P1S99_t: 보류(tick_hold) — 이번 틱 건너뜀" && ok "11c 빈 보류 파일 = 사유 없이 알림" || ng "11c 빈 보류 파일" "$o"
mkspec P1_RETURN P1S95_z P1S95_z true; mkpre P1_RETURN P1S95_z          # 판 둘 — 하나만 보류
rm -f "$CALLS"; o=$(STUB_PENDING="" go); got=$(cat "$CALLS" 2>/dev/null)
{ printf '%s' "$got" | grep -q "P1S95_z scan" && printf '%s' "$got" | grep -q "P1S95_z standing-report" && ! printf '%s' "$got" | grep -q "P1S99_t" \
  && printf '%s' "$o" | grep -q "P1S99_t: 보류(tick_hold)"; } && ok "11d 보류는 그 판만 — 다른 판은 그대로 돈다" || ng "11d 판 둘" "got=[$got] out=$o"
m=$(mut hold 'if [ -e "$d/tick_hold" ]; then' 'if false; then') && { rm -f "$CALLS"; STUB_PENDING="" "$BASH" "$m" >/dev/null 2>&1
  grep -q "P1S99_t scan" "$CALLS" 2>/dev/null && ok "11e 뮤턴트(보류 검사 제거) 검출 — 보류한 판이 돌았다" || ng "11e 뮤턴트 미검출" "$(cat "$CALLS" 2>/dev/null)"; }
rm -f "$HOLD"; rm -f "$CALLS"; o=$(STUB_PENDING="" go); got=$(cat "$CALLS" 2>/dev/null)
{ printf '%s' "$got" | grep -q "P1S99_t scan" && ! printf '%s' "$o" | grep -q "보류"; } && ok "11f 보류 파일을 지우면 다음 틱부터 다시 돈다" || ng "11f 해제" "got=[$got] out=$o"

echo
echo "합계: 통과 $P · 실패 $F"
echo "{\"test\":\"standing_board_run\",\"pass\":$P,\"fail\":$F,\"total\":$((P+F))}"
[ "$F" -eq 0 ]
