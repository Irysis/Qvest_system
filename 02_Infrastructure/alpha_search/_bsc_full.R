source("02_Infrastructure/alpha_search/run_bsc_momentum.R")
res <- run_bsc_momentum(start_date = "2005-01-01", send_telegram = TRUE, tg_dry_run = FALSE)
saveRDS(res, "02_Infrastructure/alpha_search/_bsc_full_result.rds")
cat("\n=== BSC FULL DONE === grade:", res$grade, " score:", res$score,
    " out_dir:", res$out_dir, "\n")
