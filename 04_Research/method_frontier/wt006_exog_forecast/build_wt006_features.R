# WT-D20260718_006 — Multi-economic-logic candidate feature matrix for DIRECT factor-return forecasting.
# Reuses WT-005 factor-timing panel (family_z, per-family forward returns, grids). Adds exogenous
# predictor groups under 6 independent economic logics (도훈 강화 지시). ML combo discovery downstream.
# PIT: all features known at t. macro = CONDITIONING-ONLY (current level at month-end t, observable;
#      forward-macro prediction is settled-null). trailing factor features shift(1) (realized < t).
# Vintage pin: RAWDATA_pin20260703 + benchmark_pin20260703 + exog_pin20260718wt006.
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
W5  <- "04_Research/method_frontier/wt005_factor_timing"
OUT <- "04_Research/method_frontier/wt006_exog_forecast"
fams <- c("value","quality","momentum","low_vol","size","dividend")

## ---- reuse WT-005 pieces ----
FEAT0 <- as.data.table(read_parquet(file.path(W5,"family_feature_panel.parquet"))); FEAT0[,date:=as.Date(date)]
so   <- readRDS(file.path(W5,"static_oracle.rds"))
per_fam_pr <- so$per_fam_pr

# per-family forward-return matrix (labeled at sig_date = realized over (t,t+1]; TARGET only)
FR <- Reduce(function(a,b) merge(a,b,by="date",all=TRUE), lapply(fams, function(fk){
  x <- copy(per_fam_pr[[fk]]); setnames(x, setdiff(names(x),"date"), fk); x }))
setorder(FR, date); dts <- FR$date; nT <- length(dts)
RM <- as.matrix(FR[, ..fams])   # T x 6 forward returns

## ---- rolling helpers (all use realized returns strictly BEFORE t via lo=i-k, hi=i-1) ----
roll_apply <- function(v, k, f){ out<-rep(NA_real_,length(v))
  for(i in seq_along(v)){ lo<-i-k; hi<-i-1; if(lo>=1 && hi>=1){ x<-v[lo:hi]; if(sum(is.finite(x))>=max(3,k%/%2)) out[i]<-f(x) } }; out }
kurt <- function(x){ x<-x[is.finite(x)]; m<-mean(x); s<-sd(x); if(!is.finite(s)||s<=0) return(NA); mean(((x-m)/s)^4) }
downdev <- function(x){ x<-x[is.finite(x)]; sqrt(mean(pmin(x,0)^2)) }

## ---- L4 crash-risk (per family): trailing kurtosis + downside deviation over 12m ----
## ---- L5 cross-factor dynamics: complex momentum (spillover), relative rank ----
feat_list <- list()
for(fk in fams){
  v <- FR[[fk]]
  others <- setdiff(fams, fk)
  # complex momentum = avg trailing 12m of OTHER families (rotation spillover)
  comp12 <- rep(NA_real_, nT)
  for(i in seq_along(v)){ lo<-i-12; hi<-i-1; if(lo>=1&&hi>=1){
    s <- sapply(others, function(o){ seg<-FR[[o]][lo:hi]; if(sum(is.finite(seg))>=6) sum(seg,na.rm=TRUE) else NA })
    comp12[i] <- mean(s, na.rm=TRUE) } }
  feat_list[[fk]] <- data.table(date=dts, family=fk,
    tr_kurt12 = roll_apply(v,12,kurt),
    tr_downdev12 = roll_apply(v,12,downdev),
    complex_mom12 = comp12)
}
CF <- rbindlist(feat_list)
# relative rank of tr_12m among families at each date (from FEAT0 tr_12m)
tmp <- FEAT0[, .(date,family,tr_12m)]
tmp[, rel_rank12 := frank(tr_12m, ties.method="average")/.N, by=date]
CF <- merge(CF, tmp[,.(date,family,rel_rank12)], by=c("date","family"), all.x=TRUE)

## ---- family-invariant per-date: dispersion + cross-factor correlation regime ----
# dispersion of trailing 12m returns across families (rotation opportunity breadth)
disp12 <- rep(NA_real_, nT)
avg_corr <- rep(NA_real_, nT)
for(i in seq_along(dts)){
  lo12<-i-12; hi<-i-1
  if(lo12>=1 && hi>=1){ tr <- sapply(fams, function(fk){ seg<-FR[[fk]][lo12:hi]; if(sum(is.finite(seg))>=6) sum(seg,na.rm=TRUE) else NA })
    disp12[i] <- sd(tr, na.rm=TRUE) }
  lo24<-i-24
  if(lo24>=1 && hi>=1 && (hi-lo24)>=11){ Wmat <- RM[lo24:hi,,drop=FALSE]
    cc <- suppressWarnings(cor(Wmat, use="pairwise.complete.obs"))
    avg_corr[i] <- mean(cc[upper.tri(cc)], na.rm=TRUE) } }
INV <- data.table(date=dts, disp_ret12=disp12, avg_corr24=avg_corr)
INV[, corr_shift := avg_corr24 - frollmean(avg_corr24, 12, align="right", na.rm=TRUE)]  # correlation regime shift (L5 (a))

## ---- L3 liquidity/funding + L6 macro conditioning (month-end level, PIT observable) ----
ecos <- as.data.table(read_parquet(".cache/ecos_bond_rates_pin20260718wt006.parquet")); ecos[,Date:=as.Date(Date)]
EW <- dcast(ecos, Date ~ Series, value.var="Value")
setnames(EW, old=names(EW), new=make.names(names(EW)))
setorder(EW, Date)
# forward-fill daily then take month-end value at each sig_date (last obs <= date)
num_ec <- setdiff(names(EW),"Date")
for(c in num_ec) EW[, (c):=nafill(get(c), type="locf")]
# credit / funding spreads
EW[, cs_bbb := KR_CorpBBB - KR_Gov3Y]     # HY-proxy credit spread
EW[, cs_aa  := KR_CorpAA  - KR_Gov3Y]     # IG credit spread
EW[, term   := KR_Gov10Y  - KR_Gov3Y]     # term spread
EW[, cd_call:= KR_CD91    - KR_Call1D]    # funding/money-market spread

fred <- as.data.table(read_parquet(".cache/fred_macro_wide_pin20260718wt006.parquet")); fred[,Date:=as.Date(Date)]
setorder(fred, Date)
fcols <- c("BBB_Spread","HY_Spread","Term_Spread","StL_Fin_Stress","VIX","KRW_USD","Chi_Fin_Cond")
fcols <- intersect(fcols, names(fred))
for(c in fcols) fred[, (c):=nafill(get(c), type="locf")]

# rolling-join macro to sig_dates (last observation <= sig_date = strictly PIT)
sig <- data.table(date=dts); setkey(sig,date)
ecJ <- EW[, c("Date","cs_bbb","cs_aa","term","cd_call"), with=FALSE]; setnames(ecJ,"Date","date"); setkey(ecJ,date)
frJ <- fred[, c("Date",fcols), with=FALSE]; setnames(frJ,"Date","date"); setkey(frJ,date)
MAC <- ecJ[sig, roll=TRUE]
MAC <- frJ[MAC, roll=TRUE]
setorder(MAC, date)
# 3-month changes (momentum of conditions) — still PIT (uses only <= t levels)
for(c in c("cs_bbb","cs_aa","term","VIX","HY_Spread","StL_Fin_Stress")) if(c %in% names(MAC))
  MAC[, (paste0(c,"_chg3")) := get(c) - shift(get(c),3)]

## ---- assemble full candidate matrix ----
X <- merge(FEAT0, CF, by=c("date","family"), all.x=TRUE)
X <- merge(X, INV, by="date", all.x=TRUE)
X <- merge(X, MAC, by="date", all.x=TRUE)
setorder(X, family, date)
write_parquet(X, file.path(OUT,"wt006_candidate_features.parquet"))

# feature -> economic-logic map (for per-logic decomposition)
logic_map <- list(
  L1_crowding   = c("val_spread","vs_z"),
  L2_dispersion = c("disp_ret12","tr_vol12","VIX","VIX_chg3"),
  L3_funding    = c("cs_bbb","cs_aa","cs_bbb_chg3","cs_aa_chg3","term","cd_call","term_chg3"),
  L4_crashrisk  = c("tr_kurt12","tr_downdev12","avg_corr24"),
  L5_crossfactor= c("tr_1m","tr_3m","tr_6m","tr_12m","complex_mom12","rel_rank12","corr_shift"),
  L6_macro      = c("BBB_Spread","HY_Spread","Term_Spread","StL_Fin_Stress","KRW_USD","Chi_Fin_Cond",
                    "HY_Spread_chg3","StL_Fin_Stress_chg3")
)
logic_map <- lapply(logic_map, function(v) intersect(v, names(X)))
jsonlite::write_json(logic_map, file.path(OUT,"logic_map.json"), pretty=TRUE, auto_unbox=TRUE)

cat("[WT006 features]\n")
cat("  rows", nrow(X), " dates", uniqueN(X$date), " range", as.character(min(X$date)),"..",as.character(max(X$date)),"\n")
allf <- unlist(logic_map, use.names=FALSE)
na_rate <- sapply(allf, function(c) round(mean(is.na(X[[c]])),3))
cat("  candidate features (", length(allf), "):\n"); print(na_rate)
cat("  target fwd_ret NA:", round(mean(is.na(X$fwd_ret)),3), "\n")
