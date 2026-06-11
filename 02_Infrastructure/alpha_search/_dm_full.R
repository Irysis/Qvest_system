# =============================================================================
# _dm_full.R — Daniel & Moskowitz (2016) 동적 모멘텀 풀런 wrapper
#   기간 2005-01-01~ 고정(alpha-search 표준). 텔레그램 실발송 + saveRDS.
#   기동(Q-Lead): full_run_command 참조 (직접 기동 금지 — wrapper만 작성).
# =============================================================================
source("02_Infrastructure/alpha_search/run_dm_momentum.R")
res <- run_dm_momentum(start_date = "2005-01-01", send_telegram = TRUE, tg_dry_run = FALSE)
saveRDS(res, "02_Infrastructure/alpha_search/_dm_full_result.rds")
cat("\n=== DM FULL DONE === grade:", res$grade, " score:", res$score,
    " out_dir:", res$out_dir, "\n")
