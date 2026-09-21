#!/usr/bin/env bash
#==============================================================================
# test_morning_run_director_stage.sh — 아침 체인 [3/3] 리서치 디렉터 스테이지 배선 (2026-09-21 플랜 Part 3 · D0)
#
# 계약: rf_director.R 호출이 ① 주석 아닌 실행 줄로 존재 ② stage_result "rf_director" 로 감싸여 있다(fail-soft 위장 금지)
#   ③ mrs_daily 뒤·"morning_run done" 앞에 있다(데이터 refresh 완료 후) ④ timeout 으로 감싸여 있다(체인 정지 금지)
#   ⑤ 캐시 산출 경로가 부팅 6번째 줄이 읽는 경로와 같다(생산자·소비자 정합).
#==============================================================================
set -uo pipefail
QM="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$QM" || exit 9
MR="02_Infrastructure/ops/morning_run.sh"; BL="02_Infrastructure/ops/boot_lean.sh"; DR="02_Infrastructure/ops/rf_director.R"
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== morning_run [3/3] rf_director 배선 ==="
if grep -qE '^[^#]*Rscript[^#]*rf_director\.R' "$MR"; then ok "① rf_director.R 실행 줄 존재"; else ng "① rf_director.R 호출 없음"; fi
if grep -qE '^[^#]*stage_result "rf_director"' "$MR"; then ok "② stage_result 래핑"; else ng "② stage_result 없음 — 실패가 성공으로 읽힌다"; fi
ln_call=$(grep -nE '^[^#]*Rscript[^#]*rf_director\.R' "$MR" | head -1 | cut -d: -f1)
ln_mrs=$(grep -n 'mrs_daily_briefing.sh' "$MR" | grep -v '^[0-9]*:[[:space:]]*#' | head -1 | cut -d: -f1)
ln_done=$(grep -n 'morning_run done' "$MR" | head -1 | cut -d: -f1)
if [ -n "$ln_call" ] && [ -n "$ln_mrs" ] && [ -n "$ln_done" ] && [ "$ln_call" -gt "$ln_mrs" ] && [ "$ln_call" -lt "$ln_done" ]; then ok "③ 순서: mrs_daily($ln_mrs) < director($ln_call) < done($ln_done)"; else ng "③ 순서 위반: mrs=$ln_mrs director=$ln_call done=$ln_done"; fi
if grep -qE '^[^#]*timeout [0-9]+ Rscript[^#]*rf_director\.R' "$MR"; then ok "④ timeout 래핑"; else ng "④ timeout 없음"; fi
if grep -q 'rf_director_latest.json' "$BL" && grep -q 'rf_director_latest.json' "$DR"; then ok "⑤ 생산자(rf_director.R)·소비자(boot_lean.sh) 캐시 경로 일치"; else ng "⑤ 캐시 경로 불일치"; fi
if bash -n "$MR" 2>/dev/null; then ok "⑥ morning_run.sh 구문"; else ng "⑥ morning_run.sh 구문 오류"; fi
if [ -f "$DR" ] && grep -q 'QVEST_DIRECTOR_NO_MAIN' "$DR"; then ok "⑦ rf_director.R 검사용 NO_MAIN 진입점"; else ng "⑦ rf_director.R 부재/진입점 없음"; fi

echo "결과: PASS=$PASS FAIL=$FAIL"
printf '{"test":"morning_run_director_stage","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
