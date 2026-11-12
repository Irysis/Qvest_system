#!/usr/bin/env bash
#==============================================================================
# test_scn_qw_session_ensure.sh — 퀀티 세션 확인 · 재로그인 도우미(ops/qw_session_ensure.sh) 시나리오 (2026-11-11)
#   결정 QW-SELFHEAL-SESSION-ENSURE-20261111 — 도훈 "자가 복구가 수급 전에 퀀티 세션을 먼저 확인하고, 죽어 있으면 한 번 재로그인하게 해줘"
#
# 임시 루트 · 가짜 드라이버(QSE_DRIVER_CMD — 호출 수를 세고 정해 준 끝 줄을 낸다). 퀀티 단말 · Excel · 운영 표식 무접촉.
#   T1 세션 살아 있음 → 아무것도 안 함 · rc 0 · state=alive
#   T2 죽어 있음 → 로그인 → 살아남 · rc 0 · state=logged_in
#   T3 로그인 시도 뒤에도 세션 없음 → rc 3 · state=login_failed · 날짜 표식
#   T4 같은 날 두 번째 호출 → 드라이버를 부르지 않는다(계정 잠금 방지) · rc 3 · state=skipped_failed_today
#   T5 다음 날 → 다시 시도한다
#   T6 드라이버가 끝 줄을 못 냄 → rc 3 · state=driver_error · 그날을 잠그지 않는다(다음 호출이 다시 부른다)
#   T7 스위치 끔 → 드라이버를 부르지 않는다 · rc 10
#   T8 두 번 밀려 드라이버가 멈춤(alive=False · 로그인 줄 없음) → 그날 잠금
#   T9 루트 표지 없음 → rc 3 · 드라이버를 부르지 않는다
#   C1 [계약] 운영 도우미가 드라이버를 부르는 줄은 -LoginOnly 뿐이다(책 수급 · 다른 인자를 붙이지 않는다)
#   M1 [돌연변이] '오늘 이미 실패' 가드를 뗀 사본 → 같은 날 다시 로그인을 누른다
# 마지막 줄 = {"test":...,"pass":N,"fail":N,"total":N}
#==============================================================================
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"; ROOT="${ROOT//\\//}"
SRC="${QVEST_TEST_QSE_SRC:-$ROOT/02_Infrastructure/ops/qw_session_ensure.sh}"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
emit(){ printf '\n결과: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"; printf '{"test":"scn_qw_session_ensure","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"; }
[ -f "$SRC" ] || { ng "S0 대상 없음" "$SRC"; emit; exit 1; }
bash -n "$SRC" && ok "S0 문법" || ng "S0 문법"

mkroot(){ # $1 = 도우미 원본 · 표지 포함 임시 루트
  rm -rf "$T/r"; mkdir -p "$T/r/02_Infrastructure/ops" "$T/r/02_Infrastructure/hooks" "$T/r/.cache"
  : > "$T/r/02_Infrastructure/hooks/qvest_hook_router.py"
  printf 'PROJECT="%s"\n' "$T/r" > "$T/r/02_Infrastructure/ops/resolve_project.sh"
  cp "${1:-$SRC}" "$T/r/02_Infrastructure/ops/qw_session_ensure.sh"
  rm -f "$T/drv_calls"
}
# 가짜 드라이버: 호출을 세고 DRV_LINES(줄바꿈 = '|')를 그대로 낸다
drv(){ printf 'echo x >> "%s/drv_calls"; printf "%%s\\n" "%s" | tr "|" "\\n"' "$T" "$1"; }
calls(){ local n=0; [ -f "$T/drv_calls" ] && n=$(wc -l < "$T/drv_calls"); echo $((n+0)); }
run(){ # $1 = 드라이버 출력(| 구분) · $2 = 오늘 · 나머지 = env 대입 → "rc|마지막 줄"
  local lines="$1" today="$2"; shift 2
  local out rc
  out=$(env -u QVEST_QW_SESSION_ENSURE QSE_DRIVER_CMD="$(drv "$lines")" QSE_TODAY="$today" QSE_LOG_DIR="$T/r/.cache/logs" "$@" bash "$T/r/02_Infrastructure/ops/qw_session_ensure.sh" 2>&1); rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tail -n 1 | tr '\t' ' ')"
}
END_ALIVE="===== LOGIN-ONLY END 13:43:25 / alive=True / kicks=0 ====="
END_DEAD="===== LOGIN-ONLY END 13:43:25 / alive=False / kicks=0 ====="
END_KICK2="===== LOGIN-ONLY END 13:43:25 / alive=False / kicks=2 ====="
END_KICK2_OK1="===== LOGIN-ONLY END 13:43:25 / alive=False / kicks=2 / logins_ok=1 ====="   # (11-13) 재로그인 살아남 뒤 다시 밀림
END_KICK1_OK0="===== LOGIN-ONLY END 13:43:25 / alive=False / kicks=1 / logins_ok=0 ====="   # (11-13) 종료 알림은 닫았지만 로그인 자체가 실패
LOGIN="[login] no session -> launching + login"
ST="$T/r/.cache/qw_session_ensure.json"

mkroot; r=$(run "[autologin] SAVEUSERPW=1|$END_ALIVE" 2026-11-11)
[ "$r" = "0|QSE state=alive alive=True kicks=0" ] && [ "$(calls)" = "1" ] && grep -q '"result":"alive"' "$ST" && ok "T1 세션 살아 있음 → 아무것도 안 함 · rc 0" || ng "T1" "$r calls=$(calls)"
mkroot; r=$(run "[autologin] SAVEUSERPW=1|$LOGIN|$END_ALIVE" 2026-11-11)
[ "$r" = "0|QSE state=logged_in alive=True kicks=0" ] && grep -q '"login_attempted":"1"' "$ST" && ok "T2 죽어 있음 → 로그인 → 살아남 · rc 0 · state=logged_in" || ng "T2" "$r"
mkroot; r=$(run "$LOGIN|$END_DEAD" 2026-11-11)
[ "$r" = "3|QSE state=login_failed alive=False kicks=0" ] && grep -q '"result":"login_failed"' "$ST" && grep -q '"date":"2026-11-11"' "$ST" && ok "T3 로그인 시도 뒤에도 세션 없음 → rc 3 · 날짜 표식" || ng "T3" "$r"
r=$(run "$LOGIN|$END_ALIVE" 2026-11-11)
[ "$r" = "3|QSE state=skipped_failed_today alive=False kicks=0" ] && [ "$(calls)" = "1" ] && ok "T4 같은 날 두 번째 호출 → 드라이버를 부르지 않는다(로그인 단추를 다시 누르지 않는다)" || ng "T4" "$r calls=$(calls)"
r=$(run "$LOGIN|$END_ALIVE" 2026-11-12)
[ "$r" = "0|QSE state=logged_in alive=True kicks=0" ] && [ "$(calls)" = "2" ] && ok "T5 다음 날 → 다시 시도한다" || ng "T5" "$r calls=$(calls)"
mkroot; r=$(run "[autologin] SAVEUSERPW=0 — 자격 미저장" 2026-11-11)
[ "$r" = "3|QSE state=driver_error alive=? kicks=0" ] && grep -q '"result":"driver_error"' "$ST" && ok "T6a 드라이버가 끝 줄을 못 냄 → rc 3 · state=driver_error" || ng "T6a" "$r"
r=$(run "$END_ALIVE" 2026-11-11)
[ "$r" = "0|QSE state=alive alive=True kicks=0" ] && [ "$(calls)" = "2" ] && ok "T6b 드라이버 오류는 그날을 잠그지 않는다(다음 호출이 다시 확인)" || ng "T6b" "$r calls=$(calls)"
mkroot; r=$(run "$END_ALIVE" 2026-11-11 QVEST_QW_SESSION_ENSURE=0)
[ "$r" = "10|QSE state=disabled alive=? kicks=0" ] && [ "$(calls)" = "0" ] && [ ! -f "$ST" ] && ok "T7 스위치 끔 → 드라이버를 부르지 않는다 · rc 10 · 표식 없음" || ng "T7" "$r calls=$(calls)"
## T8 (2026-11-13 도훈 결정 QW-NIGHT-SESSION-ENSURE-20261113 — 재로그인 횟수 제한 없음): 재로그인 뒤 다시 밀림은 그날을 잠그지 않는다 · 로그인 자체 실패만 잠근다
mkroot; r=$(run "$LOGIN|$END_KICK2_OK1" 2026-11-11)
[ "$r" = "3|QSE state=kicked_again alive=False kicks=2" ] && grep -q '"result":"kicked_again"' "$ST" && ok "T8a 재로그인 살아남 뒤 다시 밀림(logins_ok 1) → rc 3 · state=kicked_again(로그인 실패 아님)" || ng "T8a" "$r"
r=$(run "$LOGIN|$END_ALIVE" 2026-11-11)
[ "$r" = "0|QSE state=logged_in alive=True kicks=0" ] && [ "$(calls)" = "2" ] && ok "T8b 같은 날 다음 호출도 다시 재로그인한다(횟수 제한 없음)" || ng "T8b" "$r calls=$(calls)"
mkroot; r=$(run "$LOGIN|$END_KICK1_OK0" 2026-11-11)
[ "$r" = "3|QSE state=login_failed alive=False kicks=1" ] && ok "T8c 종료 알림을 닫았지만 로그인 자체가 실패(logins_ok 0) → login_failed · 그날 잠금(계정 잠금 방지 유지)" || ng "T8c" "$r"
r=$(run "$LOGIN|$END_ALIVE" 2026-11-11)
[ "${r%%|*}" = "3" ] && [ "$(calls)" = "1" ] && ok "T8d 로그인 실패한 날은 다시 누르지 않는다" || ng "T8d" "$r calls=$(calls)"
mkroot; r=$(run "$LOGIN|$END_KICK2" 2026-11-11)
[ "$r" = "3|QSE state=login_failed alive=False kicks=2" ] && ok "T8e logins_ok 없는 옛 드라이버 끝 줄 → 종전대로 login_failed(보수적)" || ng "T8e" "$r"
mkroot; rm -f "$T/r/02_Infrastructure/hooks/qvest_hook_router.py"; r=$(run "$END_ALIVE" 2026-11-11)
[ "${r%%|*}" = "3" ] && [ "$(calls)" = "0" ] && ok "T9 루트 표지 없음 → rc 3 · 드라이버를 부르지 않는다" || ng "T9" "$r calls=$(calls)"

n_drv=$(grep -c 'qw_refresh.ps1' "$SRC"); n_inv=$(grep -c 'powershell.exe .*-File .*-LoginOnly' "$SRC"); n_skip=$(grep -c -- '-Only\b\|-FromOverride\|-MaxRounds' "$SRC")
[ "$n_inv" = "1" ] && [ "$n_skip" = "0" ] && ok "C1 [계약] 드라이버 호출 줄은 -LoginOnly 하나뿐(책 수급 인자 없음)" || ng "C1" "invocations=$n_inv fetch_args=$n_skip refs=$n_drv"

MUT="$T/qse_mut.sh"; PYB="$ROOT/.venv_qvest_ml/Scripts/python.exe"; [ -x "$PYB" ] || PYB="${QVEST_PY:-python}"
"$PYB" - "$SRC" "$MUT" <<'PYM'
import io, sys
s = io.open(sys.argv[1], encoding="utf-8", newline="").read()
a = 'if [ "$(_field date)" = "$TODAY" ] && [ "$(_field result)" = "login_failed" ]; then'
assert s.count(a) == 1, s.count(a)
io.open(sys.argv[2], "w", encoding="utf-8", newline="").write(s.replace(a, 'if false; then'))
PYM
mkroot "$MUT"; run "$LOGIN|$END_DEAD" 2026-11-11 >/dev/null; r=$(run "$LOGIN|$END_DEAD" 2026-11-11)
[ -s "$MUT" ] && [ "$(calls)" = "2" ] && ok "M1 [돌연변이] 가드를 뗀 사본 → 같은 날 로그인을 다시 누른다(가드가 실제로 막고 있었다)" || ng "M1" "$r calls=$(calls)"

## M2 [돌연변이 · 11-13] '재로그인 뒤 다시 밀림' 분기를 뗀 사본 → T8a 꼴이 login_failed 로 접힌다(분기가 실제로 가르고 있었다)
MUT2="$T/qse_mut2.sh"
"$PYB" - "$SRC" "$MUT2" <<'PYM'
import io, sys
s = io.open(sys.argv[1], encoding="utf-8", newline="").read()
a = 'if [ -n "$LOK" ] && [ "$LOK" -gt 0 ]; then'
assert s.count(a) == 1, s.count(a)
io.open(sys.argv[2], "w", encoding="utf-8", newline="").write(s.replace(a, 'if false; then'))
PYM
mkroot "$MUT2"; r=$(run "$LOGIN|$END_KICK2_OK1" 2026-11-11)
[ -s "$MUT2" ] && [ "$r" = "3|QSE state=login_failed alive=False kicks=2" ] && ok "M2 [돌연변이] kicked_again 분기 삭제 → T8a 꼴이 login_failed(그날 잠금)로 접힌다 — T8a 는 그 분기의 발화다" || ng "M2" "$r"

emit
[ "$FAIL" = "0" ]
