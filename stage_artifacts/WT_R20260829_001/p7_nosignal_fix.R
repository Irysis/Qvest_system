## p7_nosignal_fix.R — 무신호 대조 월 정렬 수리
## 결함: canonical_screen_bt 의 period_returns$date = **신호월 t** 이고 ret_net 은 t+1 실현이다.
##   p3 은 그 라벨을 그대로 build_no_signal_control(months=) 에 넘겼고, 그 함수는
##   months[mm] 을 **실현 캘린더월**로 해석한다 → 대조군이 1개월 앞선 수익을 쓴다.
##   증상 = 대조군 beta 0.041 (시총상위25 cap-w 포트가 벤치와 무상관일 수 없다).
## 수리: 홀딩월(= 신호월 + 1M) 라벨로 넘긴다. 대조군 선택은 months[m0-1] = 신호월 → PIT 정합.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source(file.path(QM,"02_Infrastructure/contracts/no_signal_control.R"))
OUT <- "stage_artifacts/WT_R20260829_001"
CS <- readRDS(file.path(OUT,"canonical_arms.rds"))

J <- as.data.table(CS$joint2way$period_returns); J[, date := as.Date(date)]
hold <- seq(1, nrow(J))
hold_ym <- format(as.Date(format(J$date, "%Y-%m-01")) + 32L, "%Y-%m")   # 신호월 + 1M = 홀딩월
cat(sprintf("[fix] 신호월 첫/끝 = %s / %s → 홀딩월 %s / %s\n",
    format(J$date[1],"%Y-%m"), format(J$date[nrow(J)],"%Y-%m"), hold_ym[1], hold_ym[length(hold_ym)]))

ctl <- build_no_signal_control(hold_ym, n_stocks=25L, cap=0.20, freq=1L, bps=15)
cat(sprintf("[fix] 대조군: 리밸 %d회 · 보유 중앙 %d종목 · max_w %.3f · NA월 %d\n",
    ctl$n_rebal, ctl$holdings_n, ctl$max_w, sum(!is.finite(ctl$ret))))

out <- list()
for (nm in names(CS)) {
  P <- as.data.table(CS[[nm]]$period_returns); P[, date := as.Date(date)]
  g <- tryCatch(no_signal_gate(P$ret_net, ctl$ret, P$benchmark_ret), error=function(e) NULL)
  if (is.null(g)) next
  out[[nm]] <- g
  cat(sprintf("[%s] verdict=%-34s diff %+.3f%%/yr NW-t %+.3f | strat beta %.3f t(a) %+.3f · ctl beta %.3f t(a) %+.3f PORT_t %+.3f\n",
    nm, g$verdict, 100*g$diff_ann, g$diff_nw_t,
    g$strategy[["beta"]], g$strategy[["t_alpha"]],
    g$control[["beta"]], g$control[["t_alpha"]], g$control[["port_t"]]))
}
write_json(out, file.path(OUT,"no_signal_gate_fixed.json"), auto_unbox=TRUE, na="null", digits=6)
cat("[p7] DONE\n")
