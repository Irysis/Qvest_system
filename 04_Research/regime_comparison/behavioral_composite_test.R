library(data.table); library(arrow)
source("02_Infrastructure/config.R")

cat("=== Behavioral Composite Score: Regime Integration Test ===\n\n")

# Load data
fred_wide <- dcast(as.data.table(read_parquet(".cache/macro_fred.parquet")),
                    Date ~ Series, value.var = "Value")
fred_wide[, Date := as.Date(Date)]
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]
drv <- as.data.table(read_parquet(
  "04_Research/regime_comparison/output/derivatives_indicators_daily.parquet"))
drv[, Date := as.Date(Date)]

dt <- merge(bm, fred_wide, by="Date", all.x=TRUE)
dt <- merge(dt, drv[, .(Date, PCR_OI, IV_Put_ATM, K200_Basis_Pct,
                          Put_OI, Call_OI, K200_Fut_OI)],
            by="Date", all.x=TRUE)
setorder(dt, Date)

# Forward returns
dt[, Fwd_1M := shift(frollapply(1+BM_Ret, n=21, FUN=function(x) prod(x)-1,
                                  align="left"), -1, type="lead")]
dt[, CumRet := cumprod(1+BM_Ret)]

# LOCF fill
for (col in c("VIX","HY_Spread","KRW_USD","Term_Spread",
               "PCR_OI","IV_Put_ATM","K200_Basis_Pct","Put_OI","Call_OI"))
  setnafill(dt, type="locf", cols=col)

# ================================================================
# Build Behavioral Composite Score (BCS)
# ================================================================

# Component 1: VIX Momentum (가장 강한 cross-market 시그널)
dt[, VIX_Chg5 := VIX - shift(VIX, 5)]
dt[, VIX_Chg20 := VIX - shift(VIX, 20)]

# Component 2: Complacency (유일한 선행 행태 시그널)
dt[, PCR_Z120 := (PCR_OI - frollmean(PCR_OI, n=120, align="right")) /
                  pmax(frollapply(PCR_OI, n=120, FUN=sd, align="right"), 0.01)]
dt[, IV_Z120 := (IV_Put_ATM - frollmean(IV_Put_ATM, n=120, align="right")) /
                 pmax(frollapply(IV_Put_ATM, n=120, FUN=sd, align="right"), 0.01)]
dt[, Complacency := -PCR_Z120 - IV_Z120]

# Component 3: Multi-Market Danger
dt[, d_VIX_rise := fifelse(!is.na(VIX_Chg20) & VIX_Chg20 > 5, 1L, 0L)]
dt[, d_HY_widen := fifelse(!is.na(HY_Spread) & !is.na(shift(HY_Spread, 20)) &
                            (HY_Spread - shift(HY_Spread, 20)) > 0.5, 1L, 0L)]
dt[, d_KRW_weak := fifelse(!is.na(KRW_USD) & !is.na(shift(KRW_USD, 20)) &
                            (KRW_USD/shift(KRW_USD, 20)-1) > 0.03, 1L, 0L)]
dt[, d_YC_invert := fifelse(!is.na(Term_Spread) & Term_Spread < 0, 1L, 0L)]
dt[, MultiDanger := d_VIX_rise + d_HY_widen + d_KRW_weak + d_YC_invert]

# Component 4: Hedging behavior change
dt[, Put_OI_Chg20 := Put_OI / shift(Put_OI, 20) - 1]

# ================================================================
# Composite: BCS = weighted sum, higher = more danger
# ================================================================
# Normalize each component to [0, 1] via rolling rank (percentile)
dt[, VIX_Chg5_pct := frank(VIX_Chg5, na.last="keep") / sum(!is.na(VIX_Chg5))]
dt[, Complacency_pct := frank(Complacency, na.last="keep") / sum(!is.na(Complacency))]
dt[, MultiDanger_pct := MultiDanger / 4]

# BCS: higher = more likely to decline
# VIX rising (50%) + Complacency (30%) + Multi-danger (20%)
dt[, BCS := fifelse(!is.na(VIX_Chg5_pct) & !is.na(Complacency_pct),
                    0.50 * VIX_Chg5_pct + 0.30 * Complacency_pct + 0.20 * MultiDanger_pct,
                    NA_real_)]

cat("=== BCS Correlation ===\n")
cat(sprintf("r(BCS, Fwd_1M) = %.4f (N=%d)\n",
            cor(dt$BCS, dt$Fwd_1M, use="pairwise.complete.obs"),
            sum(!is.na(dt$BCS) & !is.na(dt$Fwd_1M))))

# BCS Quintile analysis
cat("\n=== BCS Quintile → Fwd 1M ===\n")
dt[, BCS_Q := cut(BCS, breaks=quantile(BCS, seq(0,1,0.2), na.rm=T),
                   include.lowest=TRUE,
                   labels=c("Q1(safe)","Q2","Q3","Q4","Q5(danger)"))]
print(dt[!is.na(Fwd_1M) & !is.na(BCS_Q),
         .(Mean_1M=round(mean(Fwd_1M)*100,2),
           Med_1M=round(median(Fwd_1M)*100,2),
           PctNeg=round(mean(Fwd_1M<0)*100,1),
           Sharpe_1M=round(mean(Fwd_1M)/sd(Fwd_1M),3),
           N=.N),
         by=BCS_Q][order(BCS_Q)])

# Spread: Q1 vs Q5
q1 <- dt[BCS_Q == "Q1(safe)" & !is.na(Fwd_1M)]$Fwd_1M
q5 <- dt[BCS_Q == "Q5(danger)" & !is.na(Fwd_1M)]$Fwd_1M
cat(sprintf("\nQ1-Q5 spread: %.2f%% per month\n", (mean(q1)-mean(q5))*100))

# ================================================================
# BCS top decile: strongest danger signal
# ================================================================
cat("\n=== BCS Decile Analysis ===\n")
dt[, BCS_D := cut(BCS, breaks=quantile(BCS, seq(0,1,0.1), na.rm=T),
                   include.lowest=TRUE,
                   labels=paste0("D",1:10))]
print(dt[!is.na(Fwd_1M) & !is.na(BCS_D),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=BCS_D][order(BCS_D)])

# ================================================================
# Monthly aggregation: strategy-relevant
# ================================================================
cat("\n=== Monthly BCS → Next Month Return ===\n")
dt[, YM := format(Date, "%Y-%m")]
monthly <- dt[, .(BCS_last = tail(BCS[!is.na(BCS)], 1),
                   BM_Ret_M = prod(1+BM_Ret) - 1), by=YM]
setorder(monthly, YM)
monthly[, Fwd_Ret_M := shift(BM_Ret_M, -1, type="lead")]

monthly[, BCS_MQ := cut(BCS_last, breaks=quantile(BCS_last, seq(0,1,0.2), na.rm=T),
                         include.lowest=TRUE,
                         labels=c("Q1(safe)","Q2","Q3","Q4","Q5(danger)"))]
cat("\nMonthly BCS Q → Next Month Return:\n")
print(monthly[!is.na(Fwd_Ret_M) & !is.na(BCS_MQ),
              .(Mean_M=round(mean(Fwd_Ret_M)*100,2),
                PctNeg=round(mean(Fwd_Ret_M<0)*100,1),
                N=.N), by=BCS_MQ][order(BCS_MQ)])

cat(sprintf("\nMonthly r(BCS, Fwd_Ret) = %.4f\n",
            cor(monthly$BCS_last, monthly$Fwd_Ret_M, use="pairwise.complete.obs")))

# ================================================================
# BCS in crisis periods
# ================================================================
cat("\n=== BCS During Crises ===\n")
for (period in list(
  list(name="GFC pre-crash", start="2007-09-01", end="2008-01-31"),
  list(name="GFC crash", start="2008-01-01", end="2008-10-31"),
  list(name="COVID pre-crash", start="2020-01-01", end="2020-02-19"),
  list(name="COVID crash", start="2020-02-20", end="2020-03-23"),
  list(name="Rate pre-crash", start="2021-11-01", end="2022-01-05"),
  list(name="Rate crash", start="2022-01-05", end="2022-06-30"),
  list(name="Normal 2024", start="2024-01-01", end="2024-06-30")
)) {
  rows <- dt[Date >= period$start & Date <= period$end & !is.na(BCS)]
  if (nrow(rows) == 0) next
  cat(sprintf("  %-22s: BCS avg=%.3f | Q5%%=%.0f%% | VIX_Chg5 avg=%+.1f | Compl avg=%.1f\n",
              period$name, mean(rows$BCS), mean(rows$BCS_Q == "Q5(danger)", na.rm=T)*100,
              mean(rows$VIX_Chg5, na.rm=T), mean(rows$Complacency, na.rm=T)))
}

# ================================================================
# Backtest: BCS-based cash-out strategy
# ================================================================
cat("\n=== BCS Cash-Out Backtest ===\n")

# Monthly strategy: cash out when BCS_Q5 at month-end
monthly[, Cashout := (!is.na(BCS_MQ) & BCS_MQ == "Q5(danger)")]
monthly[, Strat_Ret := fifelse(Cashout, 0, BM_Ret_M)]
monthly <- monthly[!is.na(Strat_Ret) & !is.na(BM_Ret_M)]

bm_cum <- cumprod(1 + monthly$BM_Ret_M)
str_cum <- cumprod(1 + monthly$Strat_Ret)

n_years <- as.numeric(difftime(max(as.Date(paste0(monthly$YM,"-01"))),
                                min(as.Date(paste0(monthly$YM,"-01"))),
                                units="days")) / 365.25
bm_cagr <- (tail(bm_cum,1))^(1/n_years) - 1
str_cagr <- (tail(str_cum,1))^(1/n_years) - 1

# MDD
bm_mdd <- min(bm_cum / cummax(bm_cum) - 1)
str_mdd <- min(str_cum / cummax(str_cum) - 1)

bm_sharpe <- mean(monthly$BM_Ret_M) / sd(monthly$BM_Ret_M) * sqrt(12)
str_sharpe <- mean(monthly$Strat_Ret) / sd(monthly$Strat_Ret) * sqrt(12)

cash_pct <- sum(monthly$Cashout) / nrow(monthly) * 100

cat(sprintf("  Benchmark:  CAGR=%.1f%% | MDD=%.1f%% | Sharpe=%.3f\n",
            bm_cagr*100, bm_mdd*100, bm_sharpe))
cat(sprintf("  BCS Q5 Out: CAGR=%.1f%% | MDD=%.1f%% | Sharpe=%.3f | Cash=%.0f%%\n",
            str_cagr*100, str_mdd*100, str_sharpe, cash_pct))
cat(sprintf("  CAGR diff: %+.2f%%p\n", (str_cagr - bm_cagr)*100))
