#!/usr/bin/env bash
# run_priority_backfill.sh — DART decay-window(2015-01..2024-02) 우선 백필 런처.
# ============================================================================
# 목적: 연대순 백필(bw9c1hhv0, 현재 ~2009)이 감쇠벽(2015-2024)에 닿기까지 ~10일 걸림 →
#       감쇠구간을 먼저 수집해 DART sleeve book-marginal 판정을 앞당긴다.
# 규율:
#   - 동일 checkpoint dir, 다른 월 범위 => 파일 무충돌 (2015+ vs 연대순 2009).
#   - API budget은 연대순 run 과 공유 (DART 10k/day). BUDGET 을 잔여 헤드룸 내로 설정.
#   - resumable: 완료 월 skip. 020(rate-limit) 감지 시 파이프라인이 즉시 halt(무손상).
#   - PIT: rcept_dt 기준 signal date. consolidate 가 usable_month=+1 lag 적용.
# 사용: BUDGET=<n> bash run_priority_backfill.sh   (기본 1500 = 보수적 잔여 헤드룸)
# ============================================================================
set -u
cd "C:/Users/99922/OneDrive/Quant_Module_Moltbot" || exit 1
source .venv_qvest_ml/Scripts/activate 2>/dev/null || true

BUDGET="${BUDGET:-1500}"
# 감쇠구간: officer 분류 신뢰(2010+) + cohort decay 벽(2017+) 포함. 2015-01 시작(decay 진입 전 anchor).
export MODE=backfill
export BF_START="${BF_START:-2015-01}"
export BF_END="${BF_END:-2024-02}"
export DART_DAILY_BUDGET="$BUDGET"

echo "[priority] launching DART backfill $BF_START..$BF_END budget=$BUDGET (shared cap 10k/day)"
python -u stage_artifacts/dart_parser_build/code/dart_backfill_pipeline.py \
  > stage_artifacts/dart_sleeve_test/reports/priority_backfill_$(date +%Y%m%d_%H%M%S).log 2>&1
echo "[priority] run ended (exit=$?)"
