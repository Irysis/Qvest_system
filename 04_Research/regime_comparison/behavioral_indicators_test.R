library(data.table); library(arrow)

drv <- as.data.table(read_parquet("04_Research/regime_comparison/output/derivatives_indicators_daily.parquet"))
drv[, Date := as.Date(Date)]
setorder(drv, Date)

bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]
setorder(bm, Date)
bm[, Fwd_1M := shift(frollapply(1+BM_Ret, n=21, FUN=function(x) prod(x)-1, align="left"), -1, type="lead")]

dt <- merge(drv, bm[, .(Date, BM_Ret, Fwd_1M)], by="Date")
setorder(dt, Date)
setnafill(dt, type="locf", cols=c("K200_Basis_Pct","K200_Fut_OI","K200_Fut_Vol",
                                    "PCR_OI","Put_OI","Call_OI",
                                    "IV_Put_ATM","IV_Skew","K200_Spot"))

cat("=== Behavioral Indicators ===\n\n")

# 1. Basis Momentum
dt[, Basis_Mom5  := K200_Basis_Pct - shift(K200_Basis_Pct, 5)]
dt[, Basis_Mom20 := K200_Basis_Pct - shift(K200_Basis_Pct, 20)]

# 2. Hedging Intensity
dt[, Put_OI_Chg5  := (Put_OI / shift(Put_OI, 5) - 1)]
dt[, Put_OI_Chg20 := (Put_OI / shift(Put_OI, 20) - 1)]
dt[, Call_OI_Chg5 := (Call_OI / shift(Call_OI, 5) - 1)]
dt[, Hedge_Accel := Put_OI_Chg5 - Call_OI_Chg5]

# 3. Smart Money Flow (OI+Basis interaction)
dt[, Fut_OI_Chg5 := (K200_Fut_OI / shift(K200_Fut_OI, 5) - 1)]
dt[, Smart_Flow := fifelse(Fut_OI_Chg5 > 0.02 & Basis_Mom5 < -0.05, -1,
                   fifelse(Fut_OI_Chg5 > 0.02 & Basis_Mom5 > 0.05, 1, 0))]

# 4. Complacency Index
dt[, PCR_Z120 := (PCR_OI - frollmean(PCR_OI, n=120, align="right")) /
                  pmax(frollapply(PCR_OI, n=120, FUN=sd, align="right"), 0.01)]
dt[, IV_Z120 := (IV_Put_ATM - frollmean(IV_Put_ATM, n=120, align="right")) /
                 pmax(frollapply(IV_Put_ATM, n=120, FUN=sd, align="right"), 0.01)]
dt[, Complacency := fifelse(!is.na(PCR_Z120) & !is.na(IV_Z120),
                            -PCR_Z120 - IV_Z120, NA_real_)]

# 5. VRP
dt[, RV_20 := frollapply(BM_Ret, n=20, FUN=function(x) sd(x)*sqrt(252)*100, align="right")]
dt[, VRP_raw := IV_Put_ATM - RV_20]

# 6. Vol/OI ratio
dt[, Vol_OI_Ratio := K200_Fut_Vol / pmax(K200_Fut_OI, 1)]
dt[, Vol_OI_Z := (Vol_OI_Ratio - frollmean(Vol_OI_Ratio, n=60, align="right")) /
                  pmax(frollapply(Vol_OI_Ratio, n=60, FUN=sd, align="right"), 0.001)]

# === Correlations ===
cat("=== Correlation with Fwd 1M ===\n")
indicators <- c("Basis_Mom5","Basis_Mom20","Put_OI_Chg5","Put_OI_Chg20",
                 "Hedge_Accel","Fut_OI_Chg5","Complacency","VRP_raw","Vol_OI_Z")
for (ind in indicators) {
  r <- cor(dt[[ind]], dt$Fwd_1M, use="pairwise.complete.obs")
  n <- sum(!is.na(dt[[ind]]) & !is.na(dt$Fwd_1M))
  if (!is.na(r) & n > 100) cat(sprintf("  %-18s: r=%+.4f (N=%d) %s\n", ind, r, n,
                                        ifelse(abs(r)>0.05, "*", "")))
}

# === Bin analyses ===
cat("\n=== Basis Momentum (5d) ===\n")
dt[, BM5_Bin := cut(Basis_Mom5, breaks=c(-Inf,-0.3,-0.1,0,0.1,0.3,Inf),
                     labels=c("<-0.3","-0.3~-0.1","-0.1~0","0~0.1","0.1~0.3",">0.3"))]
print(dt[!is.na(Fwd_1M) & !is.na(BM5_Bin),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=BM5_Bin][order(BM5_Bin)])

cat("\n=== Hedge Accel (Put-Call OI gap) ===\n")
dt[, HA_Bin := cut(Hedge_Accel, breaks=c(-Inf,-0.05,-0.02,0,0.02,0.05,Inf),
                    labels=c("<-5%","-5~-2%","-2~0%","0~2%","2~5%",">5%"))]
print(dt[!is.na(Fwd_1M) & !is.na(HA_Bin),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=HA_Bin][order(HA_Bin)])

cat("\n=== Complacency Index Q1~Q5 ===\n")
dt[, CMP_Bin := cut(Complacency, breaks=quantile(Complacency, c(0,.2,.4,.6,.8,1), na.rm=T),
                     include.lowest=TRUE,
                     labels=c("Q1(fear)","Q2","Q3","Q4","Q5(complacent)"))]
print(dt[!is.na(Fwd_1M) & !is.na(CMP_Bin),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=CMP_Bin][order(CMP_Bin)])

cat("\n=== Smart Money Flow ===\n")
print(dt[!is.na(Fwd_1M),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=Smart_Flow][order(Smart_Flow)])

cat("\n=== VRP_raw bins ===\n")
dt[, VRP_Bin := cut(VRP_raw, breaks=c(-Inf,-5,-2,0,2,5,10,Inf),
                     labels=c("<-5","-5~-2","-2~0","0~2","2~5","5~10",">10"))]
print(dt[!is.na(Fwd_1M) & !is.na(VRP_Bin),
         .(Mean_1M=round(mean(Fwd_1M)*100,2), PctNeg=round(mean(Fwd_1M<0)*100,1), N=.N),
         by=VRP_Bin][order(VRP_Bin)])

# === Composite AND-gates ===
cat("\n=== Composite Behavioral Signals ===\n")
valid <- !is.na(dt$Fwd_1M)

gates <- list(
  "Complacency Q5 (top 20%)" = (!is.na(dt$CMP_Bin) & dt$CMP_Bin == "Q5(complacent)"),
  "SmartFlow=-1 (short build)" = (dt$Smart_Flow == -1),
  "Hedge_Accel>5%" = (!is.na(dt$Hedge_Accel) & dt$Hedge_Accel > 0.05),
  "Hedge_Accel>5% & Basis_Mom5<-0.1" = (!is.na(dt$Hedge_Accel) & dt$Hedge_Accel > 0.05 &
                                          !is.na(dt$Basis_Mom5) & dt$Basis_Mom5 < -0.1),
  "VRP_raw<-2 (VRP collapse)" = (!is.na(dt$VRP_raw) & dt$VRP_raw < -2),
  "Vol_OI_Z>2 (high turnover)" = (!is.na(dt$Vol_OI_Z) & dt$Vol_OI_Z > 2),
  "SmartFlow=-1 & Hedge>5%" = (dt$Smart_Flow == -1 & !is.na(dt$Hedge_Accel) & dt$Hedge_Accel > 0.05)
)

for (gname in names(gates)) {
  sig <- gates[[gname]]
  n_sig <- sum(sig & valid, na.rm=TRUE)
  if (n_sig < 10) { cat(sprintf("  %-40s: %3d days (too few)\n", gname, n_sig)); next }
  fwd <- dt$Fwd_1M[sig & valid]
  nosig <- dt$Fwd_1M[!sig & valid]
  va <- (mean(nosig)-mean(fwd))*10000
  cat(sprintf("  %-40s: %4d days (%4.1f%%) | Fwd1M=%+5.2f%% | P(neg)=%4.1f%% | VA=%+.0fbps\n",
              gname, n_sig, n_sig/sum(valid)*100,
              mean(fwd)*100, mean(fwd<0)*100, va))
}

# === Crisis period spot-check ===
cat("\n=== COVID Behavioral Indicators Timeline ===\n")
covid <- dt[Date >= "2020-01-01" & Date <= "2020-04-30",
            .(Date, Basis_Mom5=round(Basis_Mom5,3), Hedge_Accel=round(Hedge_Accel,3),
              Smart_Flow, Complacency=round(Complacency,1), VRP_raw=round(VRP_raw,1))]
covid[, YM := format(Date, "%Y-%m")]
print(covid[, .(Basis_Mom5=round(mean(Basis_Mom5,na.rm=T),3),
                Hedge_Accel=round(mean(Hedge_Accel,na.rm=T),3),
                Short_Days=sum(Smart_Flow==-1, na.rm=T),
                Complacency=round(mean(Complacency,na.rm=T),1),
                VRP=round(mean(VRP_raw,na.rm=T),1)), by=YM])
