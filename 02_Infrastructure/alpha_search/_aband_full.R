# =============================================================================
# _aband_full.R — COVD 역신호 프로브(abandonment long) 풀런. start 2005(mandate), 실발송.
# =============================================================================
#   Q-Lead가 RAM 직렬화 후 기동(백그라운드, 로그 리다이렉트). 스모크 PASS/타당 후 실행.
#   "커버리지 철수(abandonment) 종목 long" — Δcoverage_3m 하위 decile EW long-only.
#   chain 3번째 trial(변경사유=원검증 P2 진단 aband IC +0.0220 t=3.39 역부호 관찰). 롱숏 불허.
# =============================================================================
source("02_Infrastructure/alpha_search/run_coverage_delta.R")
r <- run_coverage_delta(
  strategy_name = "Coverage Abandonment Inverse Probe (KR-native)",
  strategy_idea = paste0(
    "애널리스트 커버리지 head-count 3개월 *철수*(abandonment, Δ 하위=감소폭 큰) 횡단면 상위 ",
    "decile EW long-only — 커버리지 철수=과매도/방치 → 가치 반등(neglected-firm premium 변형). ",
    "원검증 P2 진단 aband IC +0.0220(t=3.39)의 portfolio 집행. coverage 가족 3번째 trial(chain)."),
  signal_var    = "dcov_abs",
  invert        = TRUE,               # ★ Score=frank(-dcov_abs): 철수 종목 상위 decile long
  track         = "COVD_abandonment_inverse",
  start_date    = "2005-01-01",       # mandate: coverage floor 2001-06 충족
  send_telegram = TRUE,
  tg_dry_run    = FALSE,              # 실발송(2차트 + 성과요약 + 팩터분석)
  factor_analysis = TRUE)
saveRDS(r, "02_Infrastructure/alpha_search/_aband_full_result.rds")
cat(sprintf("\n[ABAND FULL RESULT] id=%s grade=%s score=%.0f excess=%+.2f%%p track=%s out=%s\n",
            r$strategy_id, r$grade, r$score %||% 0, r$excess_cagr %||% 0, r$track, r$out_dir))
