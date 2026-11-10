# axiom_approval_queue.R — 퇴역 대체 스텝 (v10.2 · 2026-11-10 · 도훈 "Axiom 엔진: 기록 · 조회만 남긴다")
#
# morning_briefing.sh 의 스텝이었다(구 본문 = DIST 승인 대기 · 공리 활성/보류 통지 · 재도전(부활) 신호 노출 —
#   distilled.R · promote.R · failure_revival_monitor.R 적재). DIST 수명주기 · 승격 기계와 함께 원본을 보관소로 옮겼다:
#   99_Archive/axiom_engine_v10_2_20261110/02_Infrastructure/ops/morning_steps/axiom_approval_queue.R (원본)
# 호출부(morning_briefing.sh)를 고치지 않아도 되게 같은 경로에 한 줄만 남긴다. 과거 교훈 조회 = hypothesis_index.R lookup.
cat("[Axiom 승인 대기] 퇴역(v10.2 · 보관 경로 99_Archive/axiom_engine_v10_2_20261110/) — 교훈 조회: Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <키워드>\n")
