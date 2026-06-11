# _covd_full.R — 커버리지 변화 알파 풀런. start 2005(mandate), 텔레그램 실발송.
# Q-Lead가 RAM 직렬화 후 기동(백그라운드, 로그 리다이렉트). 스모크 PASS 후 실행.
source("02_Infrastructure/alpha_search/run_coverage_delta.R")
r <- run_coverage_delta(
  start_date    = "2005-01-01",   # mandate: coverage floor 2001-06 충족
  signal_var    = "dcov_abs",     # 스모크 IS 분포 보고 확정한 변형
  send_telegram = TRUE,
  tg_dry_run    = FALSE,          # 실발송(2차트 + 성과요약 + 팩터분석)
  factor_analysis = TRUE)
cat(sprintf("\n[FULL RESULT] id=%s grade=%s score=%.0f excess=%+.2f%%p signal=%s out=%s\n",
            r$strategy_id, r$grade, r$score %||% 0, r$excess_cagr %||% 0, r$signal_var, r$out_dir))
