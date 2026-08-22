## run_dfa_costfix_r33.R — R33: §34 측정 결함 수리 — 지수 내부 회전 비용을 부과한 판본으로 전 게이트 재측정
## 결함: 지수 빌더가 매 월말 top-tercile 을 재구성하는데 비용이 없다. 15bps 는 배분층에만 붙었다.
## 수리: R31 이 실측한 팩터별·월별 지수 내부 회전율(sum|Δw|, 드리프트 반영)에 동일 규약(15bps delta-based)으로 과금.
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(sandwich); library(lmtest)})
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
IRf  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt  <- function(x){ x <- x[is.finite(x)]; if (length(x) < 12) return(NA)
                     m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }
MDD  <- function(r){ n <- cumprod(1+r); min(n/cummax(n)-1) }
CAGR <- function(r) prod(1+r)^(12/length(r))-1
BPS  <- 15

R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]; R[, ym := format(Date,"%Y-%m")]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x),x,0))-1), .(medate = max(Date))),
         by = ym, .SDcols = c("Market", fac)]
setorder(mon, medate); mon <- mon[ym <= "2026-07"]; NM <- nrow(mon); NF <- length(fac)

TV <- fread("outputs/ramp/dfa_index_turnover_r31_20260822.csv", encoding = "UTF-8")
## 비용 차감판 월 지수수익: r_net(f,m) = r_gross(f,m) - 15bps * turnover(f,m)
monC <- copy(mon)
applied <- 0L; miss <- 0L
for (f in fac) {
  tv <- TV[factor == f]
  idx <- match(monC$ym, tv$ym)
  cst <- ifelse(is.na(idx), NA_real_, tv$turnover[idx]) * BPS/1e4
  miss <- miss + sum(is.na(cst)); applied <- applied + sum(!is.na(cst))
  cst[is.na(cst)] <- 0
  monC[[f]] <- monC[[f]] - cst
}
cat(sprintf("비용 부과: 팩터-월 셀 %d 적용 / %d 결측(0 처리)\n", applied, miss))
cat(sprintf("Market 은 유니버스 전체 cap-w 라 리밸 없음 -> 비용 미부과(정합)\n\n"))

mk_S <- function(M){
  s <- matrix(NA_real_, NM, NF)
  for (fi in 1:NF) for (m in 12:NM)
    s[m, fi] <- prod(1 + M[[fac[fi]]][(m-11):m]) / prod(1 + M$Market[(m-11):m]) - 1
  s }
run_ens <- function(M, Suse, K = 5, freq = 3, ncoh = 3, bps = BPS, dec_lag = 1, start0 = 13){
  RET <- as.matrix(M[, c("Market", fac), with = FALSE]); RET[!is.finite(RET)] <- 0
  NAx <- 1 + NF; pr_c <- matrix(NA_real_, ncoh, NM)
  for (cc in 0:(ncoh-1)) {
    st <- start0 + cc; wprev <- rep(1/NAx, NAx); wcur <- NULL
    for (m in st:NM) {
      d <- m - dec_lag; if (d < 1) next
      if (is.null(wcur) || ((m-st) %% freq == 0)) {
        s <- Suse[d, ]; pos <- which(is.finite(s) & s > 0)
        if (!is.na(K) && length(pos) > K) pos <- pos[order(s[pos], decreasing = TRUE)][1:K]
        w <- rep(0, NAx); if (length(pos) == 0) w[1] <- 1 else w[1+pos] <- s[pos]/sum(s[pos])
        wcur <- w }
      ri <- RET[m, ]; dlt <- sum(abs(wcur - wprev))
      pr_c[cc+1, m] <- sum(wcur*ri) - (bps/1e4)*dlt
      wd <- wcur*(1+ri); wprev <- wd/sum(wd); wcur <- wprev } }
  pr <- rep(NA_real_, NM)
  for (m in (start0+ncoh-1):NM) if (all(is.finite(pr_c[,m]))) pr[m] <- mean(pr_c[,m])
  pr }

S_g <- mk_S(mon); S_c <- mk_S(monC)
armG <- run_ens(mon,  S_g)      # 현행(결함 상태)
armC <- run_ens(monC, S_c)      # 수리판 — 신호도 비용 차감 지수에서 재산출

cat("=== [1] 게이트 재측정 — 현행(결함) vs 수리판 ===\n")
for (win in c("full","clean")) {
  cat(sprintf("\n[%s]\n", win))
  for (nm in c("현행(비용 결함)","수리판(지수내부 비용 부과)")) {
    pr <- if (grepl("현행", nm)) armG else armC
    M  <- if (grepl("현행", nm)) mon  else monC
    k <- which(is.finite(pr)); if (win == "clean") k <- k[mon$ym[k] >= "2015-07"]
    x <- pr[k]; a <- x - M$Market[k]
    cat(sprintf("  %-28s n=%3d | CAGR %+.4f MDD %.4f calmar %.4f | PORT_t %+.3f IR %+.3f\n",
                nm, length(x), CAGR(x), MDD(x), CAGR(x)/abs(MDD(x)), nwt(a), IRf(a)))
  }
}
k <- which(is.finite(armG) & is.finite(armC))
cat(sprintf("\n[대응표본] 수리판 - 현행 : mean %+.4f%%/월 · NW-t %+.3f (음수 기대 — 비용은 한 방향)\n",
            100*mean(armC[k]-armG[k]), nwt(armC[k]-armG[k])))

cat("\n=== [2] 계약 경유 졸업지표 (수리판) ===\n")
k <- which(is.finite(armC)); d <- as.Date(monC$medate[k]); p <- armC[k]; b <- monC$Market[k]
sim <- list(DAILY_NAV_DT = data.table(Date=d, Strategy_Ret=p, NAV=cumprod(1+p)),
            strategy_xts = xts(p, order.by=d), bm_xts = xts(b, order.by=d),
            cost_model_version = "dfa_r33_15bps_both_layers")
spec <- list(strategy_name="DFA_R33_costfix", description="R20 채택팔 + 지수 내부 회전 비용 부과(§34 수리)",
             universe="broad-21 KR 팩터지수", rebalance="quarterly(배분) / monthly(지수 재구성)",
             cost="15bps 양 층(배분 sum|dw| + 지수내부 sum|dw|)", signal="trailing 12M active, top-quintile k=5")
bt <- build_bt_result(sim, spec, run_id="dfa_r33_costfix", strategy_id="DFA_R33_COSTFIX",
  benchmark_id="CAPW_PARENT", benchmark_name="parent", transaction_cost_bps=15, slippage_bps=0,
  frequency="monthly", universe_id="K200_KQ150", code_version="run_dfa_costfix_r33.R", created_by_agent="Q-Lead")
au <- audit_bt_result(bt); es <- essence_score(bt, n_trials_cumulative=2, selection_type="chain")
cat(sprintf("audit=%s grade=%s\n", au$integrity, es$grade))
print(es$essence[c("net_sharpe","net_ir","portfolio_alpha_t_nw_lag3","oos_retention","calmar","mdd","cagr")])
cat("\n[게이트 대조 — 현행 기록 -> 수리판]\n")
cat(sprintf("  PORT_t   2.882 -> %.3f (문턱 2.95)\n", es$essence$portfolio_alpha_t_nw_lag3))
cat(sprintf("  oos      0.852 -> %.3f (문턱 0.70)\n", es$essence$oos_retention))
cat(sprintf("  calmar   0.298 -> %.3f (문턱 0.64)\n", es$essence$calmar))
saveRDS(list(armG=armG, armC=armC, monC=monC, es=es), ".cache/_dfa_r33.rds")
cat("\nR33_DONE\n")
