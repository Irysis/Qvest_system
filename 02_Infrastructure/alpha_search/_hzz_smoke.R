# _hzz_smoke.R — HZZ(2016) 트렌드 팩터 스모크 (start 2015, 텔레그램 dry-run)
#   1프로세스 포그라운드. 실발송 금지(tg_dry_run=TRUE). 양식·경로·PIT·허들 작동 확인용.
source("02_Infrastructure/alpha_search/run_hzz_trend.R")
res <- run_hzz_trend(start_date = "2015-01-01", send_telegram = TRUE, tg_dry_run = TRUE)
saveRDS(res, "02_Infrastructure/alpha_search/_hzz_smoke_result.rds")
cat("\n=== HZZ SMOKE DONE === grade:", res$grade, " score:", res$score,
    " excess:", res$excess_cagr, " out_dir:", res$out_dir, "\n")
