library(data.table); library(arrow)
source("02_Infrastructure/config.R")

cat("=== Cross-Market Lead/Lag + Behavioral Deep Dive ===\n\n")

# Load all available data
fred_wide <- as.data.table(read_parquet(".cache/macro_fred.parquet"))
fred_wide <- dcast(fred_wide, Date ~ Series, value.var = "Value")
fred_wide[, Date := as.Date(Date)]
setorder(fred_wide, Date)

bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]
setorder(bm, Date)

drv <- as.data.table(read_parquet("04_Research/regime_comparison/output/derivatives_indicators_daily.parquet"))
drv[, Date := as.Date(Date)]
setorder(drv, Date)

# Merge all
dt <- merge(bm, fred_wide, by="Date", all.x=TRUE)
dt <- merge(dt, drv[, .(Date, K200_Basis_Pct, PCR_OI, PCR_Vol, Put_OI, Call_OI,
                          IV_Put_ATM, IV_Skew, K200_Fut_OI, K200_Fut_Vol)],
            by="Date", all.x=TRUE)
setorder(dt, Date)

# Forward returns
dt[, Fwd_1M := shift(frollapply(1+BM_Ret, n=21, FUN=function(x) prod(x)-1, align="left"), -1, type="lead")]
dt[, Fwd_3M := shift(frollapply(1+BM_Ret, n=63, FUN=function(x) prod(x)-1, align="left"), -1, type="lead")]

# LOCF fill macro data (released monthly/weekly)
macro_cols <- c("VIX","HY_Spread","Term_Spread","KRW_USD","Fed_Funds_Rate")
for (col in macro_cols) {
  if (col %in% names(dt)) setnafill(dt, type="locf", cols=col)
}

# ===================================================================
# PART 1: US VIX → KOSPI lead/lag
# VIX 변화가 KOSPI 수익률을 선행하는가?
# ===================================================================
cat("=== Part 1: VIX Change → KOSPI Lead/Lag ===\n")

dt[, VIX_Chg5 := VIX - shift(VIX, 5)]
dt[, VIX_Chg20 := VIX - shift(VIX, 20)]
dt[, VIX_Pct20 := VIX / shift(VIX, 20) - 1]

# VIX level bins → forward KOSPI
dt[, VIX_Bin := cut(VIX, breaks=c(0, 15, 20, 25, 30, 40, Inf),
                     labels=c("<15","15-20","20-25","25-30","30-40",">40"))]
cat("\nVIX level → KOSPI Fwd 1M:\n")
print(dt[!is.na(Fwd_1M) & !is.na(VIX_Bin),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=VIX_Bin][order(VIX_Bin)])

# VIX 20d change → forward KOSPI (lead?)
dt[, VIXchg_Bin := cut(VIX_Chg20, breaks=c(-Inf,-5,-2,0,2,5,10,Inf),
                        labels=c("<-5","-5~-2","-2~0","0~2","2~5","5~10",">10"))]
cat("\nVIX 20d change → KOSPI Fwd 1M:\n")
print(dt[!is.na(Fwd_1M) & !is.na(VIXchg_Bin),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=VIXchg_Bin][order(VIXchg_Bin)])

# ===================================================================
# PART 2: HY Spread → KOSPI (신용 스트레스 선행?)
# ===================================================================
cat("\n=== Part 2: HY Spread → KOSPI ===\n")

dt[, HY_Chg20 := HY_Spread - shift(HY_Spread, 20)]
dt[, HY_Z := (HY_Spread - frollmean(HY_Spread, n=252, align="right")) /
              pmax(frollapply(HY_Spread, n=252, FUN=sd, align="right"), 0.01)]

dt[, HYchg_Bin := cut(HY_Chg20, breaks=c(-Inf,-0.5,-0.2,0,0.2,0.5,1,Inf),
                       labels=c("<-0.5","-0.5~-0.2","-0.2~0","0~0.2","0.2~0.5","0.5~1",">1"))]
cat("\nHY Spread 20d change → KOSPI Fwd 1M:\n")
print(dt[!is.na(Fwd_1M) & !is.na(HYchg_Bin),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=HYchg_Bin][order(HYchg_Bin)])

# ===================================================================
# PART 3: KRW/USD → KOSPI (환율 급등 선행?)
# ===================================================================
cat("\n=== Part 3: KRW/USD → KOSPI ===\n")

dt[, KRW_Chg20 := KRW_USD / shift(KRW_USD, 20) - 1]

dt[, KRWchg_Bin := cut(KRW_Chg20, breaks=c(-Inf,-0.03,-0.01,0,0.01,0.03,0.05,Inf),
                        labels=c("<-3%","-3~-1%","-1~0%","0~1%","1~3%","3~5%",">5%"))]
cat("\nKRW 20d change → KOSPI Fwd 1M:\n")
print(dt[!is.na(Fwd_1M) & !is.na(KRWchg_Bin),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=KRWchg_Bin][order(KRWchg_Bin)])

# ===================================================================
# PART 4: Term Spread (금리 역전) → KOSPI
# ===================================================================
cat("\n=== Part 4: Term Spread → KOSPI ===\n")

dt[, TS_Bin := cut(Term_Spread, breaks=c(-Inf,-0.5,0,0.5,1,2,Inf),
                    labels=c("<-0.5","-0.5~0","0~0.5","0.5~1","1~2",">2"))]
cat("\nTerm Spread level → KOSPI Fwd 3M:\n")
print(dt[!is.na(Fwd_3M) & !is.na(TS_Bin),
         .(Mean_3M=round(mean(Fwd_3M)*100,2), PctNeg=round(mean(Fwd_3M<0)*100,1), N=.N),
         by=TS_Bin][order(TS_Bin)])

# ===================================================================
# PART 5: Correlation Summary
# ===================================================================
cat("\n=== Correlation Summary (vs Fwd_1M) ===\n")
test_vars <- c("VIX","VIX_Chg5","VIX_Chg20","VIX_Pct20",
                "HY_Spread","HY_Chg20","HY_Z",
                "KRW_USD","KRW_Chg20",
                "Term_Spread")
for (v in test_vars) {
  if (v %in% names(dt)) {
    r <- cor(dt[[v]], dt$Fwd_1M, use="pairwise.complete.obs")
    n <- sum(!is.na(dt[[v]]) & !is.na(dt$Fwd_1M))
    if (!is.na(r) & n > 100) cat(sprintf("  %-18s: r=%+.4f (N=%d) %s\n", v, r, n,
                                          ifelse(abs(r)>0.06, "**", ifelse(abs(r)>0.03, "*", ""))))
  }
}

# ===================================================================
# PART 6: Cross-market composite danger signal
# 동시에 여러 시장에서 위험 신호가 뜨면?
# ===================================================================
cat("\n=== Part 6: Multi-Market Danger Score ===\n")

# Compute danger signals (using 20d changes)
dt[, d_VIX_rise := fifelse(!is.na(VIX_Chg20) & VIX_Chg20 > 5, 1L, 0L)]
dt[, d_HY_widen := fifelse(!is.na(HY_Chg20) & HY_Chg20 > 0.5, 1L, 0L)]
dt[, d_KRW_weak := fifelse(!is.na(KRW_Chg20) & KRW_Chg20 > 0.03, 1L, 0L)]
dt[, d_YC_invert := fifelse(!is.na(Term_Spread) & Term_Spread < 0, 1L, 0L)]

dt[, MultiDanger := d_VIX_rise + d_HY_widen + d_KRW_weak + d_YC_invert]

cat("\nMulti-Market Danger Score (0-4) → KOSPI Fwd 1M:\n")
print(dt[!is.na(Fwd_1M),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=MultiDanger][order(MultiDanger)])

# Threshold tests
cat("\n=== Multi-Danger Thresholds ===\n")
valid <- !is.na(dt$Fwd_1M)
for (th in 1:4) {
  sig <- (dt$MultiDanger >= th) & valid
  n <- sum(sig, na.rm=TRUE)
  if (n < 10) next
  fwd <- dt$Fwd_1M[sig]
  nosig <- dt$Fwd_1M[!sig & valid]
  va <- (mean(nosig) - mean(fwd)) * 10000
  cat(sprintf("  Danger >= %d: %4d days (%4.1f%%) | Fwd1M=%+5.2f%% | P(neg)=%4.1f%% | VA=%+.0fbps\n",
              th, n, n/sum(valid)*100, mean(fwd)*100, mean(fwd<0)*100, va))
}

# ===================================================================
# PART 7: Combined Behavioral + Cross-Market
# ===================================================================
cat("\n=== Part 7: Behavioral + Cross-Market Combo ===\n")

# Complacency (from derivatives)
setnafill(dt, type="locf", cols=c("PCR_OI","IV_Put_ATM"))
dt[, PCR_Z120 := (PCR_OI - frollmean(PCR_OI, n=120, align="right")) /
                  pmax(frollapply(PCR_OI, n=120, FUN=sd, align="right"), 0.01)]
dt[, IV_Z120 := (IV_Put_ATM - frollmean(IV_Put_ATM, n=120, align="right")) /
                 pmax(frollapply(IV_Put_ATM, n=120, FUN=sd, align="right"), 0.01)]
dt[, Complacency := fifelse(!is.na(PCR_Z120) & !is.na(IV_Z120), -PCR_Z120 - IV_Z120, NA_real_)]

# High Complacency + some cross-market warning
dt[, Complacent_Q := frank(Complacency, na.last="keep") / sum(!is.na(Complacency))]

gates2 <- list(
  "Complacent(top20%) + YC_Invert" = (!is.na(dt$Complacent_Q) & dt$Complacent_Q > 0.8 & dt$d_YC_invert == 1),
  "Complacent(top20%) + VIX_rise" = (!is.na(dt$Complacent_Q) & dt$Complacent_Q > 0.8 & dt$d_VIX_rise == 1),
  "Complacent(top20%) + HY_widen" = (!is.na(dt$Complacent_Q) & dt$Complacent_Q > 0.8 & dt$d_HY_widen == 1),
  "Complacent(top30%) + Danger>=2" = (!is.na(dt$Complacent_Q) & dt$Complacent_Q > 0.7 & dt$MultiDanger >= 2),
  "VIX>25 + HY_widen + KRW_weak" = (!is.na(dt$VIX) & dt$VIX > 25 & dt$d_HY_widen == 1 & dt$d_KRW_weak == 1),
  "Danger>=2 only" = (dt$MultiDanger >= 2),
  "Danger>=3 only" = (dt$MultiDanger >= 3)
)

for (gname in names(gates2)) {
  sig <- gates2[[gname]]
  n_sig <- sum(sig & valid, na.rm=TRUE)
  if (n_sig < 10) { cat(sprintf("  %-45s: %3d days (too few)\n", gname, n_sig)); next }
  fwd <- dt$Fwd_1M[sig & valid]
  nosig <- dt$Fwd_1M[!sig & valid]
  va <- (mean(nosig) - mean(fwd)) * 10000
  cat(sprintf("  %-45s: %4d days (%4.1f%%) | Fwd1M=%+5.2f%% | P(neg)=%4.1f%% | VA=%+.0fbps\n",
              gname, n_sig, n_sig/sum(valid)*100, mean(fwd)*100, mean(fwd<0)*100, va))
}
