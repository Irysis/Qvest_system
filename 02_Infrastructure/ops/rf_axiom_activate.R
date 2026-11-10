#!/usr/bin/env Rscript
#==============================================================================
# rf_axiom_activate.R — 퇴역 대체 스크립트 (v10.2 · 2026-11-10 · 도훈 "Axiom 엔진: 기록 · 조회만 남긴다")
#
# 예약 작업 Qvest_AxiomActivate 의 진입점이었다(구 본문 = 승격 통과 공리 자동 활성화 + 사후 통보 · promote.R 적재).
# 승격 기계(promote.R · refine_statement.R)와 함께 원본을 보관소로 옮겼다:
#   99_Archive/axiom_engine_v10_2_20261110/02_Infrastructure/ops/rf_axiom_activate.R (원본)
# 예약 작업이 아직 켜져 있어도 실패 경보가 나지 않게 한 줄을 남기고 0 으로 끝난다(작업 끄기 = 도훈).
# 되살리기 = 보관소 MANIFEST.md §되살리는 법.
#==============================================================================
cat(sprintf("[ax_act] %s 퇴역(v10.2 · 보관 경로 99_Archive/axiom_engine_v10_2_20261110/) — 공리 활성화 실행 안 함\n",
            format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")))
quit(save = "no", status = 0L)
