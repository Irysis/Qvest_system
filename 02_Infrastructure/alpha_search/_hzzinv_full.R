# _hzzinv_full.R — HZZ(2016) 역방향 프로브 풀런 wrapper (anti-trend Q1 long)
#   기간 2005-01-01~ 고정(alpha-search 표준). 텔레그램 실발송 + saveRDS.
#   기동(Q-Lead): full_run_command 참조 (직접 기동 금지 — wrapper만 작성).
source("02_Infrastructure/alpha_search/run_hzz_inverse.R")
res <- run_hzz_inverse(start_date = "2005-01-01", send_telegram = TRUE, tg_dry_run = FALSE,
                       factor_analysis = TRUE)
saveRDS(res, "02_Infrastructure/alpha_search/_hzzinv_full_result.rds")
cat("\n=== HZZ INVERSE FULL DONE === grade:", res$grade, " score:", res$score,
    " excess:", res$excess_cagr, " out_dir:", res$out_dir, "\n")
