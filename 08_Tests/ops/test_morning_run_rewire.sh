#!/usr/bin/env bash
#==============================================================================
# test_morning_run_rewire.sh — v10 무인 재배선(수집까지만)의 배선 검증
#
# 계약 (v10 2026-08-29 도훈): 무인 morning 체인 = 수집(recharge) + 트리아지(router)
#   + 데이터 환류(factor_evidence)까지. 자동 리서치 4종(recheck/alpha_queue/mode_queue/
#   dispatch)은 **호출 자체가 걷혀야** 한다 — mode_queue 는 내부 기본 ENABLE:-1 이라
#   env 정리만으로는 되살아난다(호출 부재가 유일한 확실한 차단).
#==============================================================================
set -uo pipefail
QM="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$QM" || exit 9
MR="02_Infrastructure/ops/morning_run.sh"
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "=== morning_run v10 재배선 검증 ==="

# ① 퇴역 러너 4종 — **호출**(bash/Rscript 실행줄)이 없어야 한다 (주석·echo 는 무관)
for r in "bash .*alpha_search_queue_run.sh" "bash .*mode_queue_research_run.sh" \
         "bash .*factor_deep_recheck_run.sh" "Rscript .*paper_research_dispatch.R" \
         "bash .*paper_dispatch_backfill.sh"; do
  if grep -qE "^[^#]*$r" "$MR"; then ng "① 퇴역 러너 호출 잔존: $r"; else ok "① 호출 부재: ${r##* }"; fi
done

# ② 유지 스테이지 — 호출이 살아 있어야 한다
for r in "paper_recharge_daily.sh" "paper_router_run.sh" "build_factor_evidence.py"; do
  if grep -qE "^[^#]*(bash|\"\\\$QVEST_PY\").*$r" "$MR"; then ok "② 유지 스테이지 생존: $r"; else ng "② 유지 스테이지 호출 소실: $r"; fi
done

# ③ 퇴역 선언 echo (침묵 금지 — '안 돌렸다'를 로그가 말해야 한다)
n_retired=$(grep -c "퇴역 (v10" "$MR" || true)
if [ "${n_retired:-0}" -ge 4 ]; then ok "③ 퇴역 선언 echo ${n_retired}건 (침묵 아님)"; else ng "③ 퇴역 선언 echo 부족: $n_retired"; fi

# ④ .bat — 리서치 env 잔존 금지 (라우터 ENABLE 은 유지)
for b in 02_Infrastructure/ops/scheduler/Qvest_MorningReboot.bat 02_Infrastructure/ops/scheduler/Qvest_MorningBrief.bat; do
  if grep -qE "QVEST_ALPHA_QUEUE_ENABLE|QVEST_PAPER_DISPATCH_ENABLE|QVEST_FACTOR_RECHECK_ENABLE|QVEST_PAPER_ROUTER_AUTORUN" "$b"; then
    ng "④ $(basename "$b") 에 리서치 env 잔존"
  else ok "④ $(basename "$b") 리서치 env 청소됨"; fi
  if grep -q "QVEST_PAPER_ROUTER_ENABLE=1" "$b"; then ok "④ $(basename "$b") 라우터(트리아지) 유지"; else ng "④ $(basename "$b") 라우터 env 소실 — 수집 체인 파손"; fi
done

echo "결과: PASS=$PASS FAIL=$FAIL"
# ★러너 요약 계약 (v10 2026-09-03): 이 줄이 없으면 run_all_hooks.sh 가 UNMEASURED 로 계상해
#   이 스위트의 단언이 배터리 총계에 **0** 으로 들어간다(조용한 커버리지 구멍).
printf '{"test":"morning_run_rewire","pass":%d,"fail":%d,"total":%d,"skipped":0}
' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
