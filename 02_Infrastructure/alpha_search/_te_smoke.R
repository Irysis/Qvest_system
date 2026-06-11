# _te_smoke.R — Transfer-Entropy 정보-sink 알파 스모크 (start 2015, 텔레그램 dry-run)
#   1프로세스 포그라운드. 실발송 금지(tg_dry_run=TRUE). 양식·경로·PIT·허들·TE엔진 작동 확인용.
#   스모크가 10분 한도 초과 우려 시: 환경변수 TE_FREQ=quarterly 로 시그널 빈도 강등 가능
#   (엔진이 자동 인식 — 무엇을 타협했는지 진단 JSON·로그에 기록).
source("02_Infrastructure/alpha_search/run_te_sink.R")
res <- run_te_sink(start_date = "2015-01-01", send_telegram = TRUE, tg_dry_run = TRUE,
                   factor_analysis = TRUE)
saveRDS(res, "02_Infrastructure/alpha_search/_te_smoke_result.rds")
cat("\n=== TE SMOKE DONE === grade:", res$grade, " score:", res$score,
    " excess:", res$excess_cagr, " out_dir:", res$out_dir, "\n")
