source("02_Infrastructure/alpha_search/run_dm_momentum.R")
res <- run_dm_momentum(start_date = "2015-01-01", send_telegram = TRUE, tg_dry_run = TRUE)
cat("\n=== DM SMOKE DONE === grade:", res$grade, " score:", res$score,
    " out_dir:", res$out_dir, "\n")
