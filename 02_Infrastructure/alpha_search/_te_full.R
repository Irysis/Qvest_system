# _te_full.R — Transfer-Entropy 정보-sink 알파 풀런 wrapper
#   기간 2005-01-01~ 고정(alpha-search 표준). 월간 빈도. 텔레그램 실발송 + saveRDS.
#   기동(Q-Lead): full_run_command 참조 (직접 기동 금지 — wrapper만 작성).
source("02_Infrastructure/alpha_search/run_te_sink.R")
res <- run_te_sink(start_date = "2005-01-01", send_telegram = TRUE, tg_dry_run = FALSE,
                   factor_analysis = TRUE)
saveRDS(res, "02_Infrastructure/alpha_search/_te_full_result.rds")
cat("\n=== TE FULL DONE === grade:", res$grade, " score:", res$score,
    " excess:", res$excess_cagr, " out_dir:", res$out_dir, "\n")
