source("02_Infrastructure/alpha_search/run_bsc_momentum.R")
res <- run_bsc_momentum(start_date = "2015-01-01", send_telegram = TRUE, tg_dry_run = TRUE)
cat("\n=== SMOKE DONE === grade:", res$grade, " score:", res$score, "\n")
