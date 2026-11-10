#!/usr/bin/env bash
# axiom_quarterly.sh — 퇴역 대체 스크립트 (v10.2 · 2026-11-10 · 도훈 "Axiom 엔진: 기록 · 조회만 남긴다")
#
# 예약 작업 Qvest_AxiomReview 의 진입점이었다(구 본문 = review.R --all · 활성 공리 열화/반증 재검토).
# 공리 리뷰 · 승격 기계는 보관소로 옮겼다:
#   99_Archive/axiom_engine_v10_2_20261110/02_Infrastructure/ops/axiom_quarterly.sh (원본)
#   99_Archive/axiom_engine_v10_2_20261110/02_Infrastructure/axiom/review.R
# 예약 작업이 아직 켜져 있어도 실패 경보가 나지 않게 한 줄을 남기고 0 으로 끝난다(작업 끄기 = 도훈).
# 되살리기 = 보관소 MANIFEST.md §되살리는 법.
LOG="${QVEST_AXIOM_LOG:-/tmp/axiom_quarterly.log}"
MSG="[axiom_quarterly] $(date '+%Y-%m-%dT%H:%M:%S%z') 퇴역(v10.2 · 보관 경로 99_Archive/axiom_engine_v10_2_20261110/) — 공리 리뷰 실행 안 함"
echo "$MSG"
echo "$MSG" >> "$LOG" 2>/dev/null || true
exit 0
