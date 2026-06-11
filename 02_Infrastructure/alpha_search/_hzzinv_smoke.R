# _hzzinv_smoke.R — HZZ(2016) 역방향 프로브 스모크 (start 2015, 텔레그램 dry-run)
#   1프로세스 포그라운드. 실발송 금지(tg_dry_run=TRUE). 양식·경로·PIT·허들·invert 작동 확인.
#   원방향 스모크(SR 0.07, MDD 69.8%, Carhart −8.3%)와 대조 — 역방향이 부호 역전 보이는지.
source("02_Infrastructure/alpha_search/run_hzz_inverse.R")
res <- run_hzz_inverse(start_date = "2015-01-01", send_telegram = TRUE, tg_dry_run = TRUE)
saveRDS(res, "02_Infrastructure/alpha_search/_hzzinv_smoke_result.rds")
cat("\n=== HZZ INVERSE SMOKE DONE === grade:", res$grade, " score:", res$score,
    " excess:", res$excess_cagr, " out_dir:", res$out_dir, "\n")
