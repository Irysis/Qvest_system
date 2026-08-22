## run_dfa_t1_gates_r35.R — R35: 게이트 0 준수팔(T1)의 계약 경유 전 게이트 측정 + 수리판 지수팔과 정면 비교
## ★회계 확인: R29 의 T0~T3 는 종목 수준 분기 포트폴리오이고 리밸 시 sum|Δw| 를 15bps 로 과금한다.
##   즉 지수 내부 월별 재구성 자체를 하지 않으므로 §34 결함(지수 내부 회전 무과금)의 대상이 아니다.
##   단 그 때문에 R29 의 T0 은 지수팔의 충실 재구성이 아니다 — 비교 시 이 점을 명시한다.
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(sandwich); library(lmtest)})
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
IRf  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA)
                     m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }
MDD  <- function(r){ n <- cumprod(1+r); min(n/cummax(n)-1) }
CAGR <- function(r) prod(1+r)^(12/length(r))-1

Z29 <- readRDS(".cache/_dfa_r29.rds")     # PR(월수익 T0~T3) · mon · CC(제약) · k
Z33 <- readRDS(".cache/_dfa_r33.rds")     # armC = 비용 수리판 지수팔 · monC
mon <- Z29$mon; PR <- Z29$PR; CC <- Z29$CC

cat("=== [1] 회계 무결성 확인 — T1 이 §34 결함 대상인가 ===\n")
cat("  R29 구성: 분기 리밸 종목 포트폴리오 · 리밸 시 sum|Δw| 를 15bps 과금 · 분기 내 드리프트 무과금\n")
cat("  ⇒ 지수 내부 월별 재구성을 수행하지 않으므로 §34(지수 내부 회전 무과금) 대상 아님. 회계 완결.\n")
cat("  ⚠단 그래서 R29 의 T0 은 지수팔(월별 재구성)의 충실 재구성이 아니다 — 아래 비교에서 별개 객체로 취급.\n")

cat("\n=== [2] 정면 비교 — 배포 가능성 × 성과 ===\n")
k <- Z29$k; mk <- mon$Market[k]
arms <- list("index_costfixed" = NULL, "T1_gate0_ok" = PR[k,"T1"], "T3_gate0_ok" = PR[k,"T3"],
             "T0_index_stocklevel" = PR[k,"T0"])
prC <- Z33$armC; kC <- which(is.finite(prC)); mkC <- Z33$monC$Market[kC]
cat(sprintf("  %-24s %-8s %8s %8s %9s %9s %8s\n","팔","제약준수","CAGR","MDD","calmar","PORT_t","IR"))
cat(sprintf("  %-24s %-8s %8.4f %8.4f %9.4f %+9.3f %8.3f\n","index_costfixed(수리판)","0%",
    CAGR(prC[kC]), MDD(prC[kC]), CAGR(prC[kC])/abs(MDD(prC[kC])), nwt(prC[kC]-mkC), IRf(prC[kC]-mkC)))
for (a in c("T0","T1","T2","T3")) {
  x <- PR[k,a]; comp <- 100*mean(CC[[paste0(a,"_n")]] <= 25 & CC[[paste0(a,"_maxw")]] <= 0.20+1e-9)
  cat(sprintf("  %-24s %-8s %8.4f %8.4f %9.4f %+9.3f %8.3f\n",
      paste0(a,"(종목수준)"), sprintf("%.0f%%",comp),
      CAGR(x), MDD(x), CAGR(x)/abs(MDD(x)), nwt(x-mk), IRf(x-mk)))
}

cat("\n=== [3] T1 계약 경유 졸업지표 (미측정이던 oos_retention 포함) ===\n")
ymk <- mon$ym[k]
md <- as.Date(paste0(ymk,"-01")) ; md <- as.Date(sapply(md, function(z) as.character(seq(z, by="month", length.out=2)[2]-1)))
for (a in c("T1","T3")) {
  p <- PR[k,a]; b <- mk
  sim <- list(DAILY_NAV_DT = data.table(Date=md, Strategy_Ret=p, NAV=cumprod(1+p)),
              strategy_xts = xts(p, order.by=md), bm_xts = xts(b, order.by=md),
              cost_model_version = "dfa_r29_15bps_stocklevel")
  spec <- list(strategy_name = paste0("DFA_R35_",a),
    description = "게이트 0 제약 내재화 변환(종목 수준 분기 포트폴리오)",
    universe = "K200 U KQ150 stocks (<=25)", rebalance = "quarterly",
    cost = "15bps one-way delta (종목 수준)", signal = "trailing 12M active, top-quintile k=5")
  bt <- build_bt_result(sim, spec, run_id=paste0("dfa_r35_",tolower(a)), strategy_id=paste0("DFA_R35_",a),
    benchmark_id="CAPW_PARENT", benchmark_name="parent", transaction_cost_bps=15, slippage_bps=0,
    frequency="monthly", universe_id="K200_KQ150", code_version="run_dfa_gate0_transform_r29.R",
    created_by_agent="Q-Lead")
  au <- audit_bt_result(bt); es <- essence_score(bt, n_trials_cumulative=2, selection_type="chain")
  cat(sprintf("\n[%s] audit=%s grade=%s\n", a, au$integrity, es$grade))
  cat(sprintf("  PORT_t %.3f (문턱 2.95) | oos_retention %.3f (문턱 0.70) | calmar %.3f (문턱 0.64)\n",
      es$essence$portfolio_alpha_t_nw_lag3, es$essence$oos_retention, es$essence$calmar))
  cat(sprintf("  net_sharpe %.3f | CAGR %.3f | MDD %.3f | 3분할 {%s}\n",
      es$essence$net_sharpe, es$essence$cagr, es$essence$mdd,
      paste(sprintf("%.3f", es$oos_retention_splits), collapse=", ")))
  cat(sprintf("  게이트 통과 수: %d/3 (PORT_t %s · oos %s · calmar %s)\n",
      sum(es$essence$portfolio_alpha_t_nw_lag3>=2.95, es$essence$oos_retention>=0.70, es$essence$calmar>=0.64),
      ifelse(es$essence$portfolio_alpha_t_nw_lag3>=2.95,"PASS","FAIL"),
      ifelse(es$essence$oos_retention>=0.70,"PASS","FAIL"),
      ifelse(es$essence$calmar>=0.64,"PASS","FAIL")))
}
cat("\n=== [4] clean 창 (2015-07~) ===\n")
kc <- k[ymk >= "2015-07"]; mkc <- mon$Market[kc]
for (a in c("T0","T1","T3")) { x <- PR[kc,a]
  cat(sprintf("  %-6s n=%3d | CAGR %+.4f MDD %.4f calmar %.4f | PORT_t %+.3f IR %+.3f\n",
      a, length(x), CAGR(x), MDD(x), CAGR(x)/abs(MDD(x)), nwt(x-mkc), IRf(x-mkc))) }
cat("\nR35_DONE\n")
