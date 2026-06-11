# =============================================================================
# _pead_full.R — PEAD/SUE (Bernard-Thomas 1989) 풀런 wrapper (텔레그램 실발송 + saveRDS)
# =============================================================================
# 스모크(tg_dry_run=TRUE)와 동일 구간(데이터 floor ~2018 = 풀구간) — 차이는 텔레그램 실발송뿐.
# Q-Lead가 백그라운드 기동. 직접 기동 금지(에이전트는 wrapper만 작성).
# =============================================================================
source("02_Infrastructure/alpha_search/run_pead_paper.R")
res <- run_pead_paper(start_date = "2015-01-01", send_telegram = TRUE, tg_dry_run = FALSE)
saveRDS(res, "02_Infrastructure/alpha_search/_pead_full_result.rds")
cat("\n=== PEAD/SUE FULL DONE === grade:", res$grade, " score:", res$score,
    " excess:", res$excess_cagr, " out_dir:", res$out_dir, "\n")
