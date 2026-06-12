# =============================================================================
# _aband_smoke.R — COVD 역신호 프로브(abandonment long) 스모크. start 2015, dry-run.
# =============================================================================
#   "애널리스트 커버리지 *철수*(abandonment) 종목 long" — 커버리지 3개월 감소폭 상위 decile EW.
#   근거: 원검증 STR_AS_COVD_20260612_083700_45840(F)의 P2 진단에서 aband IC +0.0220(t=3.39,
#   hit 61.3%) — 가설(P1 커버리지증가 long)과 반대 부호. 메커니즘 후보: 커버리지 철수 →
#   과매도/방치 → 가치 반등(neglected-firm premium 변형). chain 3번째 trial(변경사유=P2 역부호 관찰).
#   롱숏 불허(도훈 06-11): 전면 long-only. aband 정의는 fe 원정의(dcov_abs<0) 그대로(새 정의 없음).
#   1프로세스 포그라운드. 실발송 금지(tg_dry_run=TRUE). 양식·경로·PIT·허들·invert·잔존폭 확인.
# =============================================================================
source("02_Infrastructure/alpha_search/run_coverage_delta.R")
r <- run_coverage_delta(
  strategy_name = "Coverage Abandonment Inverse Probe (KR-native)",
  strategy_idea = paste0(
    "애널리스트 커버리지 head-count 3개월 *철수*(abandonment, Δ 하위=감소폭 큰) 횡단면 상위 ",
    "decile EW long-only — 커버리지 철수=과매도/방치 → 가치 반등(neglected-firm premium 변형). ",
    "원검증 P2 진단 aband IC +0.0220(t=3.39)의 portfolio 집행. coverage 가족 3번째 trial(chain)."),
  signal_var    = "dcov_abs",         # 철수폭 정의 = 원 P2 dcov_abs<0 그대로 (invert가 랭크만 뒤집음)
  invert        = TRUE,               # ★ Score=frank(-dcov_abs): 철수(감소폭 큰) 종목 상위 decile long
  track         = "COVD_abandonment_inverse",
  start_date    = "2015-01-01",       # 스모크: 빠른 검증(풀런은 2005). 원 P2 IC(t=3.39)도 2015~ 산출
  send_telegram = TRUE,
  tg_dry_run    = TRUE,               # 발송 없이 양식만 점검
  factor_analysis = TRUE)
saveRDS(r, "02_Infrastructure/alpha_search/_aband_smoke_result.rds")
cat(sprintf(paste0("\n[ABAND SMOKE RESULT] id=%s grade=%s score=%.0f excess=%+.2f%%p\n",
                   "  track=%s invert=%s | decile N med=%d (철수 med=%d, 비율 %.1f%%, thin=%s)\n",
                   "  P1(-dcov_abs) IC=%.4f (t=%.2f) | P2 aband IC=%.4f (t=%.2f) [원 t=3.39 정합 확인]\n",
                   "  out=%s\n"),
            r$strategy_id, r$grade, r$score %||% 0, r$excess_cagr %||% 0,
            r$track, r$invert, r$decile_n_med, r$aband_in_decile_med,
            100 * (r$aband_frac_in_decile_med %||% 0), r$decile_thin,
            r$ic_p1$mean_ic %||% NA, r$ic_p1$t_ic %||% NA,
            r$ic_p2$mean_ic %||% NA, r$ic_p2$t_ic %||% NA, r$out_dir))
