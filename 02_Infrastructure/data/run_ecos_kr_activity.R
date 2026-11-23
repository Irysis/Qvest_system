## run_ecos_kr_activity.R — 밤 갱신 [4ka] 가 부르는 실행 스크립트: 한국 경기 지표 수집(ECOS 9계열 + 관세청 수출 실적).
##   작업 폴더 = 02_Infrastructure (daily_refresh.sh 가 cd "$INFRA" 뒤에 부른다). 손으로 돌릴 때도 같다:
##     cd 02_Infrastructure && Rscript --no-save data/run_ecos_kr_activity.R
##   ① ECOS 9계열            data/data_collector_ecos_activity.R   (수집기 · 쓰는 파일 · 가용일 규칙은 그 파일 머리말)
##   ② 관세청 수출 실적       data/data_collector_customs_trade.R   (10일 단위 잠정치 + 월 확정치 총계 · 2026-11-23 추가 · 끄기 = QVEST_CUSTOMS_KR_TRADE=0)
##   둘은 서로 막지 않는다 — 하나가 실패해도 다른 하나는 돈다. 하나라도 실패하면 종료 코드 1(밤 갱신은 로그에만 남기고 단계 실패로 세지 않는다).
##   run_r 블록으로 두지 않은 이유: 스텝 번호(r<N>)가 밀려 뒤 단계의 실패 서명이 흔들리지 않게 하고, 연구용(3등급) 계열의 실패를 단계 실패로 세지 않기 위해서다.
##   파일 이름은 처음 만든 때(ECOS 만 받던 때)의 것이다 — 밤 갱신 스크립트가 이 이름으로 부르므로 그대로 둔다.
source("config.R")
ok <- c(ecos = TRUE, customs = TRUE)
ok["ecos"] <- tryCatch({ source("data/data_collector_ecos_activity.R"); ecos_fetch_kr_activity(); TRUE },
                       error = function(e) { cat("!! [4ka] ECOS 한국 경기 지표 수집 실패 —", conditionMessage(e), "\n"); FALSE })
if (identical(Sys.getenv("QVEST_CUSTOMS_KR_TRADE"), "0")) {
  cat("[4ka] 관세청 수출 실적 건너뜀(QVEST_CUSTOMS_KR_TRADE=0)\n")
} else {
  ok["customs"] <- tryCatch({ source("data/data_collector_customs_trade.R"); customs_fetch_kr_trade(); TRUE },
                            error = function(e) { cat("!! [4ka] 관세청 수출 실적 수집 실패 —", conditionMessage(e), "\n"); FALSE })
}
if (!all(ok)) quit(save = "no", status = 1L)
