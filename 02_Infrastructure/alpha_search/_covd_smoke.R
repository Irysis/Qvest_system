# _covd_smoke.R — 커버리지 변화 알파 스모크(빠른 검증). start 2015, 텔레그램 dry-run.
source("02_Infrastructure/alpha_search/run_coverage_delta.R")
r <- run_coverage_delta(
  start_date    = "2015-01-01",   # 스모크: 빠른 검증(풀런은 2005)
  signal_var    = "dcov_abs",
  send_telegram = TRUE,
  tg_dry_run    = TRUE,           # 발송 없이 양식만 점검
  factor_analysis = TRUE)
cat(sprintf("\n[SMOKE RESULT] id=%s grade=%s score=%.0f excess=%+.2f%%p signal=%s\n",
            r$strategy_id, r$grade, r$score %||% 0, r$excess_cagr %||% 0, r$signal_var))
