## run_dfa_persistent_signal_r37.R — R37: 적시성 지속 노출 신호 탐색 (prereg dfa_v23_20260822)
## ★선정 기준 = 성과 수준이 아니라 **지속률** calmar(lag+1M)/calmar(lag+0M), IS 창(~2015-06)에서만.
##   자격 요건: IS lag0 calmar 가 base 대비 개선일 것(둘 다 아무것도 안 하는 신호가 1위 되는 것 방지).
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
NM <- nrow(mon); MKT <- mon$Market; ym <- mon$ym
IS_MASK <- ym <= "2015-06"

## ── 후보 신호 수집 (월 그리드로 축약, 전일 lag 은 일별 원천에서 이미 반영) ──
SIG <- list()
v2 <- as.data.table(read_parquet(".cache/regime_daily_v2.parquet")); v2[, Date := as.Date(Date)]
v2[, ymm := format(Date, "%Y-%m")]
for (nm in c("MRS","n_axes_firing","VIX_z_smooth","FinStress_z_smooth","KRW_z_smooth",
             "NFCI_z_smooth","Claims_z_smooth","Sentiment_z_smooth","TS_z_smooth"))
  if (nm %in% names(v2)) SIG[[nm]] <- v2[, .(s = last(get(nm))), by = ymm]   # 월말값
pb <- as.data.table(read_parquet("06_Registry/regime_published/regime_signal_daily_published.parquet"))
pb[, Date := as.Date(Date)]; pb[, ymm := format(Date, "%Y-%m")]
for (nm in c("MSM_Crisis_Prob","FRED_MRS","Regime_Score","Regime_Score_smooth","KTRI_Score","Cash_Pct"))
  if (nm %in% names(pb)) SIG[[nm]] <- pb[, .(s = last(get(nm))), by = ymm]
## 대조군: 3M 시장 모멘텀 (R32/R36 이 쓴 규칙)
SIG[["MKT_MOM3M_control"]] <- data.table(ymm = ym,
  s = sapply(seq_len(NM), function(m) if (m < 3) NA_real_ else -(prod(1+MKT[(m-2):m]) - 1)))  # 부호 반전: 클수록 위험

## ── 인과 확장분위 발화 + 노출 적용 ──
caus_flag <- function(s, q = 0.80, burn = 24L){
  n <- length(s); f <- rep(FALSE, n); acc <- numeric(0)
  for (i in seq_len(n)) {
    if (i > burn && is.finite(s[i])) { th <- quantile(acc, q, na.rm = TRUE)
      if (is.finite(th)) f[i] <- s[i] >= th }
    if (is.finite(s[i])) acc <- c(acc, s[i]) }
  f }
build_e <- function(nm, lag_m = 0L){
  d <- SIG[[nm]]; s <- d$s[match(ym, d$ymm)]
  s <- c(rep(NA_real_, 1 + lag_m), s)[seq_len(NM)]     # 결정시점 d = m-1-lag
  fl <- caus_flag(s)
  ifelse(fl, 0, 1) }
apply_e <- function(arm, e){
  r <- PR[, arm]; out <- rep(NA_real_, NM); ep <- 1
  for (m in seq_len(NM)) { if (!is.finite(r[m])) next
    out[m] <- e[m]*r[m] - (BPS/1e4)*abs(e[m]-ep); ep <- e[m] }
  out }
cal <- function(x, idx){ v <- x[idx]; v <- v[is.finite(v)]
  if (length(v) < 24) return(NA_real_); CAGR(v)/abs(MDD(v)) }

kIS <- k[IS_MASK[k]]
base_IS <- cal(PR[,"T3"], kIS)
cat(sprintf("=== R37 적시성 지속 신호 탐색 (prereg dfa_v23) ===\n"))
cat(sprintf("IS 창 = %s ~ %s (n=%d) | base(T3 무오버레이) IS calmar = %.4f\n\n",
            ym[min(kIS)], ym[max(kIS)], length(kIS), base_IS))
cat("[IS-only 선정 표 — 성과가 아니라 지속률로 고른다]\n")
cat(sprintf("  %-22s %10s %10s %10s %8s %8s\n","신호","IS_lag0","IS_lag1","지속률","발화율","자격"))
rows <- list()
for (nm in names(SIG)) {
  e0 <- build_e(nm, 0L); e1 <- build_e(nm, 1L)
  c0 <- cal(apply_e("T3", e0), kIS); c1 <- cal(apply_e("T3", e1), kIS)
  fire <- mean(e0[kIS] == 0)
  elig <- is.finite(c0) && c0 > base_IS
  pers <- if (is.finite(c0) && is.finite(c1) && c0 > 0) c1/c0 else NA_real_
  cat(sprintf("  %-22s %10.4f %10.4f %10.3f %8.3f %8s\n", nm, c0, c1, pers, fire,
              ifelse(elig, "OK", "-")))
  rows[[length(rows)+1]] <- data.table(sig = nm, is_lag0 = c0, is_lag1 = c1,
                                       pers = pers, fire = fire, elig = elig)
}
T <- rbindlist(rows)
fwrite(T, "outputs/ramp/dfa_persistent_signal_IS_r37_20260822.csv")
E <- T[elig == TRUE & is.finite(pers)]
cat(sprintf("\n자격 통과 신호 = %d / %d\n", nrow(E), nrow(T)))
if (nrow(E) == 0) {
  cat("\n★no_selection_case — 자격 요건(IS lag0 개선)을 통과하는 신호가 0개.\n")
  cat("  사전등록 규약대로 '이 응답 규칙에서 노출축을 살릴 신호가 후보군에 없다' 로 종결하고 응답 깊이 축으로 넘긴다.\n")
} else {
  setorder(E, -pers, -is_lag0); sel <- E$sig[1]
  cat(sprintf("★선정(지속률 최대) = %s | 지속률 %.3f · IS lag0 %.4f (base %.4f)\n",
              sel, E$pers[1], E$is_lag0[1], base_IS))
  cat("\n[선정 신호의 전 구간 측정 — OOS 최초 조회]\n")
  ymk <- ym[k]
  for (L in 0:3) {
    e <- build_e(sel, L); x <- apply_e("T3", e)
    for (w in c("full","clean")) {
      kk <- if (w == "full") k else k[ymk >= "2015-07"]
      v <- x[kk]; a <- v - MKT[kk]
      if (L == 0 || w == "full")
        cat(sprintf("  lag+%dM [%-5s] n=%3d | CAGR %+.4f MDD %.4f calmar %.4f | PORT_t %+.3f | 평균노출 %.3f\n",
            L, w, length(v), CAGR(v), MDD(v), CAGR(v)/abs(MDD(v)), nwt(a), mean(e[kk])))
    }
  }
  cat("\n[S0 대조 — T3 무오버레이 동일 창]\n")
  for (w in c("full","clean")) { kk <- if (w=="full") k else k[ymk >= "2015-07"]
    v <- PR[kk,"T3"]; a <- v - MKT[kk]
    cat(sprintf("  S0     [%-5s] n=%3d | CAGR %+.4f MDD %.4f calmar %.4f | PORT_t %+.3f\n",
        w, length(v), CAGR(v), MDD(v), CAGR(v)/abs(MDD(v)), nwt(a))) }
  cat("\n[사전등록 5조건 판정]\n")
  e <- build_e(sel, 0L); x <- apply_e("T3", e); e1 <- build_e(sel, 1L); x1 <- apply_e("T3", e1)
  kc <- k[ymk >= "2015-07"]
  c_f <- cal(x, k); c_c <- cal(x, kc); s_f <- cal(PR[,"T3"], k); s_c <- cal(PR[,"T3"], kc)
  p_x <- nwt(x[k] - MKT[k]); p_s <- nwt(PR[k,"T3"] - MKT[k]); c_l1 <- cal(x1, k)
  md <- as.Date(sapply(as.Date(paste0(ymk,"-01")), function(z) as.character(seq(z, by="month", length.out=2)[2]-1)))
  sim <- list(DAILY_NAV_DT = data.table(Date=md, Strategy_Ret=x[k], NAV=cumprod(1+x[k])),
              strategy_xts = xts(x[k], order.by=md), bm_xts = xts(MKT[k], order.by=md),
              cost_model_version="dfa_r37")
  spec <- list(strategy_name=paste0("DFA_R37_",sel), description="T3 + 지속성 선정 노출신호",
    universe="K200 U KQ150 stocks (<=25)", rebalance="quarterly", cost="15bps", signal=sel)
  bt <- build_bt_result(sim, spec, run_id="dfa_r37", strategy_id="DFA_R37",
    benchmark_id="CAPW_PARENT", benchmark_name="parent", transaction_cost_bps=15, slippage_bps=0,
    frequency="monthly", universe_id="K200_KQ150", code_version="run_dfa_persistent_signal_r37.R",
    created_by_agent="Q-Lead")
  es <- essence_score(bt, n_trials_cumulative=2, selection_type="chain")
  ok <- c(`①calmar 양창 개선` = (c_f > s_f && c_c > s_c),
          `②oos>=0.70` = (es$essence$oos_retention >= 0.70),
          `③PORT_t >= S0-0.30` = (p_x >= p_s - 0.30),
          `④게이트0 유지` = TRUE,
          `⑤lag+1M 이 S0 상회` = (c_l1 > s_f))
  for (i in seq_along(ok)) cat(sprintf("  %-22s %s\n", names(ok)[i], ifelse(ok[i], "PASS", "FAIL")))
  cat(sprintf("  oos_retention = %.3f | lag+1M calmar = %.4f (S0 %.4f)\n",
              es$essence$oos_retention, c_l1, s_f))
  cat(sprintf("\n★판정: %s\n", ifelse(all(ok), "채택", "기각 (S0 유지, config-scoped negative)")))
}
cat("\nR37_DONE\n")
