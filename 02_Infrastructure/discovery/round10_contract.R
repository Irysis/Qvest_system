# Round 10 계약 — blend(book75/sleeve25) 총-SR vs 활성-IR 분리 측정 (거버넌스 surface)
#   총 SR = de-risking 효과(개선), 활성 IR = 알파추가(희석). 게이트는 활성IR, 목표는 총SR.
#   ※ blend는 self-synthesized(0.75book+0.25sleeve) = metric_type ESTIMATED, forge 아님.
suppressMessages(library(data.table))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
bl <- fread(file.path(ROOT,".cache/discovery/round10_blend_series.csv"))   # ym, ret_net(blend), benchmark_ret
L5 <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
L5[, ym := substr(as.character(realized_ym),1,7)]
d <- merge(bl, L5[, .(ym, book=ret_L5_V5)], by="ym")[!is.na(book)]
d[, date := as.Date(paste0(ym,"-01"))]; setorder(d, date)
tsr <- function(r){ r<-r[is.finite(r)]; if(sd(r)>0) mean(r)/sd(r)*sqrt(12) else NA_real_ }
act_t <- function(s, retcol){
  prt <- s[, .(date, ret_net=get(retcol), frequency="monthly")]
  bmt <- s[, .(date, benchmark_ret, benchmark_id="KOSPI200_total_return")]
  bc <- build_benchmark_compare(prt, bmt, run_id="r10", strategy_id="x", annualization_factor=12)
  g <- function(nm){ v<-bc[metric_name==nm, active_value]; if(length(v)==0) NA_real_ else as.numeric(v[1]) }
  c(PORT_t=g("Portfolio_Alpha_t_NW_lag3"), IR=g("Information_Ratio"))
}
cat("=== Round 10 거버넌스 surface — 총SR(목표지표) vs 활성IR(게이트지표) ===\n")
cat("blend = book75/sleeve25 (ESTIMATED self-synth, NOT forge-authoritative — 실제 admission은 forge+governor+도훈)\n\n")
for(tag in c("full","recent")){
  s <- if(tag=="recent") d[ym>="2021-01"] else d
  bk_tsr <- tsr(s$book); bl_tsr <- tsr(s$ret_net)
  bk_a <- act_t(s,"book"); bl_a <- act_t(s,"ret_net")
  cat(sprintf("[%-7s] n=%d\n", tag, nrow(s)))
  cat(sprintf("   총 SR(목표):   book %+.2f -> blend %+.2f  (Δ%+.2f)   <- de-risking 개선\n", bk_tsr, bl_tsr, bl_tsr-bk_tsr))
  cat(sprintf("   활성 IR(게이트): book %+.2f -> blend %+.2f  (Δ%+.3f)  <- 알파 희석(ΔIR≥0.05 게이트 FAIL)\n", bk_a["IR"], bl_a["IR"], bl_a["IR"]-bk_a["IR"]))
  cat(sprintf("   활성 PORT_t:    book %+.2f -> blend %+.2f\n\n", bk_a["PORT_t"], bl_a["PORT_t"]))
}
cat("거버넌스 질문(도훈 결정): 목표가 총SR 2.5라면 활성IR 게이트가 de-risking sleeve를 차단 — 의도된 보호인가, 목표-게이트 불일치인가?\n")
cat("=== done ===\n")
