#!/usr/bin/env bash
#==============================================================================
# test_scn_data_selfheal_tick.sh — 낮 시간 데이터 자가 복구 틱(ops/data_selfheal_tick.sh) 시나리오 (2026-11-11)
#
# 임시 루트 · 가짜 배리어 판정기 · 가짜 ensure_data_current(호출 기록 · 종료 코드 주입). 운영 파일 · 로그 · 리프레시 무접촉.
#   T1 배리어 free → 자가 복구 스크립트를 한 번 부른다 · 틱 rc 0 · 로그 한 줄
#   T2 배리어 held → 부르지 않는다(밤 체인 · 다른 복구와 겹치지 않는다)
#   T3 배리어 판정 불가(출력 없음) → 부르지 않는다
#   T4 스위치 끔(QVEST_DATA_SELFHEAL_TICK=off) → 부르지 않고 로그도 없다
#   T5 자가 복구가 rc 3(낡음 잔존) · rc 1(오류)이어도 틱은 rc 0(뒤따르는 상설 판 틱을 막지 않는다) · 로그에 사유
#   T6 배리어 판정기 또는 스크립트가 없으면 부르지 않는다
#   M1 [돌연변이] 배리어 검사를 뗀 사본 → held 에서도 부른다(가드가 실제로 막고 있었다)
# 마지막 줄 = {"test":...,"pass":N,"fail":N,"total":N}
#==============================================================================
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"; ROOT="${ROOT//\\//}"
TICK="${QVEST_TEST_TICK_SRC:-$ROOT/02_Infrastructure/ops/data_selfheal_tick.sh}"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkroot(){ # $1 = 배리어 상태 문자열(빈 값 = 출력 없음) · $2 = 가짜 자가 복구의 종료 코드 · $3 = 가짜 출력
  rm -rf "$T/r"; mkdir -p "$T/r/02_Infrastructure/ops" "$T/r/.cache/scheduler_logs"
  if [ -n "$1" ]; then printf '#!/usr/bin/env bash\nprintf "RB\\tstate=%s\\tlock=\\n"\n' "$1" > "$T/r/rb.sh"; else printf '#!/usr/bin/env bash\nexit 0\n' > "$T/r/rb.sh"; fi
  printf '#!/usr/bin/env bash\necho called >> "%s/r/edc_calls"\necho "[edc 00:00:00] %s"\nexit %s\n' "$T" "${3:-✅ 이미 최신 (as_of=2026-11-10) — 리프레시 실행 안 함}" "${2:-0}" > "$T/r/edc.sh"
}
run(){ # $1 = 틱 스크립트 · 나머지 = env 대입들
  local tick="$1"; shift
  env RC_ROOT_POSIX="$T/r" RB_SH="$T/r/rb.sh" DST_EDC="$T/r/edc.sh" "$@" bash "$tick" > "$T/out" 2>&1; echo $?
}
calls(){ local n=0; [ -f "$T/r/edc_calls" ] && n=$(wc -l < "$T/r/edc_calls"); echo $((n+0)); }
LOGF="$T/r/.cache/scheduler_logs/data_selfheal_tick.log"

[ -f "$TICK" ] || { ng "S0 대상 없음" "$TICK"; printf '{"test":"scn_data_selfheal_tick","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"; exit 1; }
bash -n "$TICK" && ok "S0 문법" || ng "S0 문법"

mkroot free 0; rc=$(run "$TICK")
[ "$rc" = "0" ] && [ "$(calls)" = "1" ] && grep -q 'ok — 이미 최신' "$LOGF" && ok "T1 배리어 free → 자가 복구 1회 호출 · rc 0 · 로그 한 줄" || ng "T1" "rc=$rc calls=$(calls) log=$(tail -1 "$LOGF" 2>/dev/null)"
mkroot held 0; rc=$(run "$TICK")
[ "$rc" = "0" ] && [ "$(calls)" = "0" ] && grep -q 'skip — 리프레시 배리어 state=held' "$LOGF" && ok "T2 배리어 held → 부르지 않는다" || ng "T2" "rc=$rc calls=$(calls)"
mkroot "" 0; rc=$(run "$TICK")
[ "$rc" = "0" ] && [ "$(calls)" = "0" ] && grep -q 'state=unknown' "$LOGF" && ok "T3 배리어 판정 불가 → 부르지 않는다" || ng "T3" "rc=$rc calls=$(calls)"
mkroot free 0; rc=$(run "$TICK" QVEST_DATA_SELFHEAL_TICK=off)
[ "$rc" = "0" ] && [ "$(calls)" = "0" ] && [ ! -s "$LOGF" ] && ok "T4 스위치 끔 → 부르지 않고 로그도 없다" || ng "T4" "rc=$rc calls=$(calls)"
mkroot free 3 "⚠ as_of=2026-11-10 는 이미 리프레시했으나 stale=1 잔존 — **재시도하지 않음**"; rc=$(run "$TICK")
[ "$rc" = "0" ] && [ "$(calls)" = "1" ] && grep -q 'stale — 복구 생략 또는 복구 뒤에도 낡음(rc=3)' "$LOGF" && ok "T5a 자가 복구 rc 3 → 틱은 rc 0 · 로그에 사유" || ng "T5a" "rc=$rc calls=$(calls)"
mkroot free 1 "❌ 프로젝트 루트 해석 실패"; rc=$(run "$TICK")
[ "$rc" = "0" ] && [ "$(calls)" = "1" ] && grep -q 'error — ensure_data_current rc=1' "$LOGF" && ok "T5b 자가 복구 rc 1 → 틱은 rc 0 · 로그에 오류" || ng "T5b" "rc=$rc calls=$(calls)"
mkroot free 0; rm -f "$T/r/rb.sh"; rc=$(run "$TICK")
[ "$rc" = "0" ] && [ "$(calls)" = "0" ] && ok "T6 배리어 판정기 없음 → 부르지 않는다" || ng "T6" "rc=$rc calls=$(calls)"

MUT="$T/tick_mut.sh"
PYB="$ROOT/.venv_qvest_ml/Scripts/python.exe"; [ -x "$PYB" ] || PYB="${QVEST_PY:-python}"
"$PYB" - "$TICK" "$MUT" <<'PYM'
import io, sys
s = io.open(sys.argv[1], encoding="utf-8", newline="").read()
a = 'if [ "$ST" != "free" ]; then'
assert s.count(a) == 1, s.count(a)
io.open(sys.argv[2], "w", encoding="utf-8", newline="").write(s.replace(a, 'if false; then'))
PYM
mkroot held 0; rc=$(run "$MUT")
[ "$(calls)" = "1" ] && ok "M1 [돌연변이] 배리어 검사를 뗀 사본 → held 에서도 부른다(가드가 실제로 막고 있었다)" || ng "M1" "calls=$(calls)"

echo
printf '결과: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
printf '{"test":"scn_data_selfheal_tick","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" = "0" ]
