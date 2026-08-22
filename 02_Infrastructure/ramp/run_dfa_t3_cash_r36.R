## run_dfa_t3_cash_r36.R — R36: 게이트 0 준수팔(T3) 위에서 노출축 단독 시험 (prereg dfa_v22_20260822)
## 단일 자유도 = 3M 시장 현금규칙 적용 여부. 종목 선택·비중·리밸·비용 전부 T3 고정.
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
BPS <- 15

Z <- readRDS(".cache/_dfa_r29.rds"); mon <- Z$mon; PR <- Z$PR; k <- Z$k
NM <- nrow(mon); MKT <- mon$Market
ymk <- mon$ym[k]

## PIT-청정 현금 규칙 (R32 와 동일 · 무파라미터)
expo <- function(cash_lag = 0L){
  e <- rep(1, NM)
  for (m in 1:NM) { d <- m - 1 - cash_lag; if (d - 2 < 1) next
    c3 <- prod(1 + MKT[(d-2):d]) - 1
    e[m] <- if (is.finite(c3) && c3 < 0) 0 else 1 }
  e }
apply_cash <- function(arm, cash_lag = 0L){
  e <- expo(cash_lag); r <- PR[, arm]
  out <- rep(NA_real_, NM); ep <- 1
  for (m in 1:NM) { if (!is.finite(r[m])) { next }
    out[m] <- e[m]*r[m] - (BPS/1e4)*abs(e[m] - ep); ep <- e[m] }
  list(r = out, e = e) }

rep1 <- function(x, e, lab){
  for (w in c("full","clean")) {
    kk <- if (w == "full") k else k[ymk >= "2015-07"]
    v <- x[kk]; a <- v - MKT[kk]
    cat(sprintf("  %-22s [%-5s] n=%3d | CAGR %+.4f MDD %.4f calmar %.4f | PORT_t %+.3f IR %+.3f | 평균노출 %.3f\n",
      lab, w, length(v), CAGR(v), MDD(v), CAGR(v)/abs(MDD(v)), nwt(a), IRf(a), mean(e[kk]))) } }

cat("=== R36 T3 + 노출축 (prereg dfa_v22) ===\n[헤드라인 사전지정: H1 = T3 + 3M현금규칙]\n\n")
cat("[H0 대조 — T3 그대로]\n"); rep1(PR[,"T3"], rep(1,NM), "H0_T3")
cash3 <- apply_cash("T3")
cat("\n[H1 헤드라인 — T3 + 3M현금규칙]\n"); rep1(cash3$r, cash3$e, "H1_T3_cash")
cat("\n[진단 전용 — 헤드라인 승격 금지]\n")
for (a in c("T1","T0")) { z <- apply_cash(a); rep1(z$r, z$e, paste0("diag_",a,"_cash")) }

cat("\n=== [필수 반증 ①] lag 사다리 — 적시성 의존 ===\n")
for (L in 0:3) { z <- apply_cash("T3", L); kk <- k; v <- z$r[kk]
  cat(sprintf("  cash_lag=+%dM: full calmar %.4f | MDD %.4f | PORT_t %+.3f\n",
      L, CAGR(v)/abs(MDD(v)), MDD(v), nwt(v - MKT[kk]))) }
cat("  ★기각조건: +1M 에서 개선 소멸 시 기각\n")

cat("\n=== [필수 반증 ②] 평균노출 매칭 상수-e 대조 ===\n")
em <- mean(cash3$e[k]); xb <- PR[k,"T3"] * em
cat(sprintf("  상수노출 e=%.3f : full calmar %.4f | MDD %.4f | PORT_t %+.3f\n",
    em, CAGR(xb)/abs(MDD(xb)), MDD(xb), nwt(xb - MKT[k])))
cat(sprintf("  타이밍 순증분 = %.4f calmar\n", CAGR(cash3$r[k])/abs(MDD(cash3$r[k])) - CAGR(xb)/abs(MDD(xb))))
cat("  ★기각조건: 상수 축소를 유의하게 넘지 못하면 기각\n")

cat("\n=== [필수 반증 ③] 게이트 0 준수 유지 ===\n")
CC <- Z$CC
cat(sprintf("  T3 제약 완전준수 %.0f%% (노출 규칙은 보유 종목을 바꾸지 않고 현금 비중만 조정 -> 종목수·비중 상한 불변)\n",
    100*mean(CC$T3_n <= 25 & CC$T3_maxw <= 0.20 + 1e-9)))
cat(sprintf("  현금 상태(e=0) 분기 비율 = %.1f%% — 그 구간은 보유 0종목이므로 제약 자명 충족\n", 100*(1-em)))

cat("\n=== [계약 경유 졸업지표] ===\n")
md <- as.Date(sapply(as.Date(paste0(ymk,"-01")), function(z) as.character(seq(z, by="month", length.out=2)[2]-1)))
for (nm in c("H0_T3","H1_T3_cash")) {
  p <- if (nm == "H0_T3") PR[k,"T3"] else cash3$r[k]
  sim <- list(DAILY_NAV_DT = data.table(Date=md, Strategy_Ret=p, NAV=cumprod(1+p)),
              strategy_xts = xts(p, order.by=md), bm_xts = xts(MKT[k], order.by=md),
              cost_model_version = "dfa_r36_15bps")
  spec <- list(strategy_name = nm, description = "게이트 0 준수 종목 포트폴리오 + 노출축",
    universe = "K200 U KQ150 stocks (<=25)", rebalance = "quarterly", cost = "15bps",
    signal = "trailing 12M active top-quintile k=5 -> 목표비중 상위25 + 상한0.20")
  bt <- build_bt_result(sim, spec, run_id=tolower(nm), strategy_id=toupper(nm),
    benchmark_id="CAPW_PARENT", benchmark_name="parent", transaction_cost_bps=15, slippage_bps=0,
    frequency="monthly", universe_id="K200_KQ150", code_version="run_dfa_t3_cash_r36.R", created_by_agent="Q-Lead")
  es <- essence_score(bt, n_trials_cumulative=2, selection_type="chain")
  cat(sprintf("  %-12s PORT_t %.3f | oos %.3f {%s} | calmar %.3f | 통과 %d/3\n", nm,
    es$essence$portfolio_alpha_t_nw_lag3, es$essence$oos_retention,
    paste(sprintf("%.2f", es$oos_retention_splits), collapse=","), es$essence$calmar,
    sum(es$essence$portfolio_alpha_t_nw_lag3>=2.95, es$essence$oos_retention>=0.70, es$essence$calmar>=0.64)))
}
cat("\nR36_DONE\n")
