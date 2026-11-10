#!/usr/bin/env bash
# test_scn_data_chain_failure.sh — 일일 체인 중간 실패 전파 · 자가 복구(ensure_data_current) 판정 시나리오 (감사 레인 A · 2026-11-10)
#
# 11-10 실측: 00:03 리프레시가 [1pre] 벤치 writer(pandas 3 문자열 dtype)에서 죽어 캘린더 · 퀀티 목표일이 11-06 에 멈췄고,
#   07:14 자가 복구 리프레시(ensure_data_current → daily_refresh, QVEST_REFRESH_TG=0)는 퀀티 세션 kicked 2회로 done=0/4 · rc=1 로 끝났다.
#   그런데 사후 감사가 RAWDATA(11-06 · as_of 11-09)를 달력 lag 3d ≤ 3 으로 FRESH 판정 → 스탬프 'refreshed_current' · exit 0 · 텔레그램 0.
# 이 시험은 실제 코드 조각을 모래상자에서 돌린다(외부 호출 없음):
#   C1~C4  daily_refresh.sh 의 run_r · dr_fail_summary 를 원본에서 떼어 가짜 Rscript 로: 실패 누적 · 체인 계속 · 이름표 · 요약
#   E1     ensure_data_current.sh 원본 + 스텁 감사기: 리프레시 rc=1 · 사후 감사 FRESH → refreshed_current(종전 침묵 경로 — 감사기가 판정의 전부)
#   E2     같은 상황에서 사후 감사가 rawdata 를 STALE 로 내면(세션 축 수리 뒤 11-10 의 실제 판정) → stale_after_refresh · exit 3
#   E3     같은 영업일 재실행 → 재시도하지 않고 exit 3(리프레시 재실행 0 · 47분 반복 방지 가드 유지)
# 요약: 마지막 줄 {"test":"scn_data_chain_failure","pass":N,"fail":N,"total":N}
set -uo pipefail
T=scn_data_chain_failure
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
fin() { echo "{\"test\":\"$T\",\"pass\":$1,\"fail\":$2,\"total\":$(( $1 + $2 ))}"; [ "$2" -eq 0 ]; exit $?; }
DR="$PROJ/02_Infrastructure/data/daily_refresh.sh"; EDC="$PROJ/02_Infrastructure/ops/ensure_data_current.sh"
[ -f "$DR" ] && [ -f "$EDC" ] || { echo "대상 없음"; fin 0 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
echo "== $T =="

# ── C: run_r 실패 누적 ──
awk '/^DR_FAILED=\(\)$/{f=1} f{print} f && /^dr_fail_summary\(\)/{g=1} g && /^}$/{exit}' "$DR" > "$TMP/runr.sh"
chk "C0 run_r 블록 추출" YES "$(grep -q 'run_r()' "$TMP/runr.sh" && grep -q 'dr_fail_summary()' "$TMP/runr.sh" && echo YES || echo NO)"
cat > "$TMP/fakeR" <<'SH'
#!/usr/bin/env bash
f="${@: -1}"; grep -q 'FAILME' "$f" && exit 7; echo ran >> "$(dirname "$0")/ran.txt"; exit 0
SH
chmod +x "$TMP/fakeR"
OUT=$(RSCRIPT="$TMP/fakeR" bash -c "set -uo pipefail; source '$TMP/runr.sh'; run_r 'ok1'; run_r 'FAILME' msm_asof; run_r 'ok3'; echo \"N=\${#DR_FAILED[@]} S=\$(dr_fail_summary)\"" 2>&1 | tail -1)
chk "C1 실패 1건 누적" "N=1" "$(printf '%s' "$OUT" | grep -o 'N=[0-9]*')"
chk "C2 이름표로 요약(msm_asof(rc=7))" "S=msm_asof(rc=7)" "$(printf '%s' "$OUT" | grep -o 'S=.*')"
chk "C3 실패 뒤 다음 스텝도 실행(체인 계속)" 2 "$(wc -l < "$TMP/ran.txt" | tr -d ' ')"
chk "C4 종료부: 실패 있으면 exit 1" YES "$(grep -A3 'if \[ "\${#DR_FAILED\[@\]}" -gt 0 \]; then' "$DR" | grep -q 'exit 1' && echo YES || echo NO)"

# ── E: ensure_data_current 판정 ──
B="$TMP/box"; mkdir -p "$B/02_Infrastructure/hooks" "$B/02_Infrastructure/ops/morning_steps" "$B/02_Infrastructure/data" "$B/.cache" "$B/qepm/observability"
: > "$B/02_Infrastructure/hooks/qvest_hook_router.py"
cp "$EDC" "$PROJ/02_Infrastructure/ops/resolve_project.sh" "$B/02_Infrastructure/ops/"
: > "$B/02_Infrastructure/ops/morning_steps/freshness_audit.R"                   # 존재 검사용 — 실제 판정은 가짜 Rscript 가 낸다
cat > "$B/fakeR" <<'SH'
#!/usr/bin/env bash
# 가짜 감사기: 리프레시 전 = rawdata · 벤치 stale, 리프레시 뒤 = $POST_MODE(fresh|stale)
d="$(dirname "$0")"
if [ -f "$d/refreshed" ]; then
  if [ "${POST_MODE:-fresh}" = "fresh" ]; then echo "EDC_RESULT stale=0 as_of=2026-11-09 items=-"; else echo "EDC_RESULT stale=1 as_of=2026-11-09 items=rawdata"; fi
else echo "EDC_RESULT stale=2 as_of=2026-11-09 items=benchmark,rawdata"; fi
SH
cat > "$B/02_Infrastructure/data/daily_refresh.sh" <<'SH'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")/../.." && pwd)"; : > "$d/refreshed"; echo x >> "$d/refresh_calls"; exit 1
SH
cat > "$B/fakepy" <<'SH'
#!/usr/bin/env bash
echo "0|2026-11-09|2026-11-09"
SH
chmod +x "$B/fakeR" "$B/fakepy" "$B/02_Infrastructure/data/daily_refresh.sh"
edc() { ( cd "$B" && QM_ROOT="$B" RSCRIPT="$B/fakeR" QVEST_PY="$B/fakepy" QVEST_EDC_MAX_WAIT=1 POST_MODE="$1" \
          bash "$B/02_Infrastructure/ops/ensure_data_current.sh" > "$TMP/edc.log" 2>&1; echo $? ); }
verdict() { sed -n 's/.*"verdict":"\([^"]*\)".*/\1/p' "$B/.cache/data_currency_stamp.json"; }
rm -f "$B/refreshed" "$B/.cache/data_currency_stamp.json"
chk "E1 rc=1 리프레시 · 사후 FRESH → exit 0" 0 "$(edc fresh)"
chk "E1b 스탬프 refreshed_current(rc=1 은 note 에만 — 감사 판정이 전부)" refreshed_current "$(verdict)"
rm -f "$B/refreshed" "$B/.cache/data_currency_stamp.json" "$B/refresh_calls"
chk "E2 사후 rawdata STALE → exit 3" 3 "$(edc stale)"
chk "E2b 스탬프 stale_after_refresh" stale_after_refresh "$(verdict)"
rm -f "$B/refreshed"
chk "E3 같은 영업일 재실행 → exit 3 · 재시도 없음" 3 "$(edc stale)"
chk "E3b 리프레시 호출 누계 1(재시도 0)" 1 "$(wc -l < "$B/refresh_calls" | tr -d ' ')"
fin "$PASS" "$FAIL"
