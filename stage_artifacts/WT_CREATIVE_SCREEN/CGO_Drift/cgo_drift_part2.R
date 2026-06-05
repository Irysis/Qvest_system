#==============================================================================
# CGO-Drift SCREEN — Part 2: forward rank-IC + ICIR + Harvey-t(NW) + orthogonality
#   + subperiod stability.  read-only.  NO backtest / portfolio / admission.
#
# Inputs:
#   cgo_signal.rds            (Part 1: Ticker, CGO, sig_date — PIT backward, lockbox-strict)
#   .cache/rawdata.parquet    (forward 1m return label)
#   .cache/factor_db/factor_db_YYYYMM.parquet  (M01/M06/M08/M17 Z_Score controls, PIT same sig_date)
#
# Orthogonality: residualize CGO_z on [M01_Mom_12_1, M06_High_52w, M08_Residual_Mom,
#   M17_Low_52w] cross-sectionally each month -> rank-IC(residual) = incremental IC.
#   Also partial Spearman (CGO vs fwd | controls) as cross-check.
#
# Lockbox 2023-12-22 strict.  Universe KOSPI200 U KOSDAQ150.  Window 2010-01+ (both legs).
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts/WT_CREATIVE_SCREEN/CGO_Drift")
LOCKBOX <- as.Date("2023-12-22")
WIN_START <- as.Date("2010-01-01")   # KQ150 leg present from 2010
CTRL <- c("M01_Mom_12_1","M06_High_52w","M08_Residual_Mom","M17_Low_52w")

#--- 0. CGO signal ------------------------------------------------------------
cgo <- as.data.table(readRDS(file.path(OUT,"cgo_signal.rds")))
cgo[, sig_date := as.Date(sig_date)]
cgo <- cgo[sig_date >= WIN_START & sig_date <= LOCKBOX]
# cross-sectional winsorize CGO at 1/99 pct per month (fat illiquid tail)
cgo[, CGO_w := {
  q <- quantile(CGO, c(.01,.99), na.rm=TRUE); pmin(pmax(CGO, q[1]), q[2])
}, by=sig_date]
cat("[0] CGO 2010+ rows:", nrow(cgo), " months:", uniqueN(cgo$sig_date), "\n")

#--- 1. Forward 1-month return label (PIT: future return only) ----------------
rd <- as.data.table(read_parquet(file.path(PROJ,".cache/rawdata.parquet"),
                                  col_select=c("Date","Ticker","Close")))
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)
sigs <- sort(unique(cgo$sig_date))
# month-end trading dates beyond lockbox allowed for the LABEL (forward realization)
all_me <- rd[, .(me=max(Date)), by=.(ym=as.integer(format(Date,"%Y%m")))][order(ym)]
me_dates <- sort(all_me$me)
# next month-end after each sig_date
nxt <- sapply(sigs, function(s){ z <- me_dates[me_dates>s]; if(length(z)) as.character(z[1]) else NA })
nxt <- as.Date(nxt)
map_nxt <- data.table(sig_date=sigs, nxt_date=nxt)

px_at <- function(dts){
  m <- rd[Date %in% dts, .(Ticker, Date, Close)]
  m
}
px_sig <- rd[Date %in% sigs, .(Ticker, sig_date=Date, P0=Close)]
px_nxt <- rd[Date %in% nxt,  .(Ticker, nxt_date=Date, P1=Close)]
cgo <- merge(cgo, map_nxt, by="sig_date", all.x=TRUE)
cgo <- merge(cgo, px_sig, by=c("Ticker","sig_date"), all.x=TRUE)
cgo <- merge(cgo, px_nxt, by=c("Ticker","nxt_date"), all.x=TRUE)
cgo[, fwd_ret := fifelse(!is.na(P0) & P0>0 & !is.na(P1), P1/P0 - 1, NA_real_)]
cgo <- cgo[!is.na(fwd_ret) & !is.na(nxt_date)]
# winsorize fwd_ret monthly 1/99 (avoid spurious IC from outliers)
cgo[, fwd_ret_w := { q<-quantile(fwd_ret,c(.01,.99),na.rm=TRUE); pmin(pmax(fwd_ret,q[1]),q[2]) }, by=sig_date]
cat("[1] with fwd label:", nrow(cgo), " months:", uniqueN(cgo$sig_date), "\n")

#--- 2. Load control factors (PIT same sig_date, Z_Score) ---------------------
load_ctrl <- function(sd){
  ym <- format(sd,"%Y%m")
  f <- file.path(PROJ, sprintf(".cache/factor_db/factor_db_%s.parquet", ym))
  if(!file.exists(f)) return(NULL)
  d <- as.data.table(read_parquet(f, col_select=c("Date","Ticker","Factor_Name","Z_Score")))
  d <- d[Factor_Name %in% CTRL]
  if(!nrow(d)) return(NULL)
  w <- dcast(d, Ticker ~ Factor_Name, value.var="Z_Score", fun.aggregate=function(x) x[1])
  w[, sig_date := sd]
  w
}
ctrl_list <- lapply(sigs, load_ctrl)
ctrl_list <- ctrl_list[!sapply(ctrl_list, is.null)]
ctrl <- rbindlist(ctrl_list, fill=TRUE)
cat("[2] control months loaded:", uniqueN(ctrl$sig_date), " cols:", paste(setdiff(names(ctrl),c("Ticker","sig_date")),collapse=","),"\n")
cgo <- merge(cgo, ctrl, by=c("Ticker","sig_date"), all.x=TRUE)

#--- 3. Per-month rank-IC (raw CGO) + residual (orthogonal) IC -----------------
present_ctrl <- intersect(CTRL, names(cgo))
ic_rows <- list()
for(sd in sort(unique(cgo$sig_date))){
  d <- cgo[sig_date==sd]
  if(nrow(d) < 30L) next
  # raw rank-IC: CGO_w vs fwd_ret_w (Spearman)
  ric <- suppressWarnings(cor(d$CGO_w, d$fwd_ret_w, method="spearman", use="complete.obs"))
  # residual/orthogonal IC: rank-transform everything, regress rank(CGO) on rank(controls),
  # take residual, then Spearman(residual, fwd_ret) == partial rank-IC controlling factors.
  dd <- d[complete.cases(d[, c("CGO_w","fwd_ret_w", present_ctrl), with=FALSE])]
  res_ic <- NA_real_; part_ic <- NA_real_; n_ctrl <- nrow(dd)
  if(n_ctrl >= 30L && length(present_ctrl)>=1){
    rk <- function(x) rank(x, ties.method="average")
    R_cgo <- rk(dd$CGO_w); R_fwd <- rk(dd$fwd_ret_w)
    X <- sapply(present_ctrl, function(c) rk(dd[[c]]))
    X <- as.data.frame(X)
    # residualize rank(CGO) on rank(controls) -> orthogonal component
    e_cgo <- resid(lm(R_cgo ~ ., data=data.frame(R_cgo=R_cgo, X)))
    res_ic <- cor(e_cgo, R_fwd, method="pearson")  # pearson on residual-rank == orthogonalized IC
    # partial Spearman: also residualize fwd on controls
    e_fwd <- resid(lm(R_fwd ~ ., data=data.frame(R_fwd=R_fwd, X)))
    part_ic <- cor(e_cgo, e_fwd, method="pearson")
  }
  ic_rows[[as.character(sd)]] <- data.table(sig_date=as.Date(sd), n=nrow(d), n_ctrl=n_ctrl,
                                            rank_ic=ric, res_ic=res_ic, part_ic=part_ic)
}
ic <- rbindlist(ic_rows)
cat("[3] IC months:", nrow(ic), "\n")

#--- 4. Aggregate stats + Harvey-t (NW) on the rank-IC time series ------------
nw_t <- function(x){
  x <- x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m <- lm(x ~ 1)
  se <- sqrt(NeweyWest(m, lag=NULL, prewhite=FALSE, adjust=TRUE)[1,1])
  unname(coef(m)[1]/se)
}
mean_ic   <- mean(ic$rank_ic, na.rm=TRUE)
sd_ic     <- sd(ic$rank_ic, na.rm=TRUE)
icir      <- mean_ic/sd_ic
t_nw      <- nw_t(ic$rank_ic)
mean_res  <- mean(ic$res_ic, na.rm=TRUE)
t_res_nw  <- nw_t(ic$res_ic)
icir_res  <- mean_res / sd(ic$res_ic, na.rm=TRUE)
mean_part <- mean(ic$part_ic, na.rm=TRUE)
t_part_nw <- nw_t(ic$part_ic)
hit       <- mean(sign(ic$rank_ic)==sign(mean_ic), na.rm=TRUE)

# subperiod stability: split into 3 equal time thirds
ic <- ic[order(sig_date)]
ic[, third := cut(seq_len(.N), 3, labels=c("P1","P2","P3"))]
sub <- ic[, .(mean_ic=mean(rank_ic,na.rm=TRUE), mean_res=mean(res_ic,na.rm=TRUE), n=.N), by=third]
# stability score: fraction of subperiods with same-sign mean rank-IC as overall, weighted by consistency
sub_signs <- sign(sub$mean_ic)
stab <- mean(sub_signs == sign(mean_ic))
# annualize ICIR (monthly -> *sqrt(12))
icir_ann <- icir * sqrt(12)

cat(sprintf("\n=== CGO-Drift SCREEN (2010-01 .. 2023-12, lockbox-strict) ===\n"))
cat(sprintf("N months           : %d\n", nrow(ic)))
cat(sprintf("avg names/month    : %.0f\n", mean(ic$n)))
cat(sprintf("RAW  rank-IC mean  : %+.4f  (sd %.4f)\n", mean_ic, sd_ic))
cat(sprintf("RAW  ICIR (monthly): %+.3f   ICIR_ann: %+.3f\n", icir, icir_ann))
cat(sprintf("RAW  Harvey-t (NW) : %+.3f\n", t_nw))
cat(sprintf("RAW  hit rate      : %.3f\n", hit))
cat(sprintf("ORTH res-IC mean   : %+.4f   ICIR(res): %+.3f   t_NW(res): %+.3f\n", mean_res, icir_res, t_res_nw))
cat(sprintf("ORTH partial-IC    : %+.4f   t_NW(part): %+.3f\n", mean_part, t_part_nw))
cat(sprintf("subperiod sign-stab: %.2f\n", stab))
print(sub)

#--- 5. SCREEN JSON -----------------------------------------------------------
res <- list(
  idea = "CGO-Drift (Grinblatt-Han 2005 capital-gains-overhang): CGO=(P_t-RP_t)/P_t from turnover-reconstructed reference price; (+)CGO winner-underreaction drift, residualized vs momentum/52w controls.",
  scope = "SCREEN only (read-only). NO backtest / portfolio / admission. rank-IC is advisory SCREEN metric, NOT tradeable alpha.",
  data_feasible = TRUE,
  universe = "KOSPI200 U KOSDAQ150 (both legs present 2010+)",
  window = "2010-01-31 .. 2023-12-22 (lockbox-strict regular research)",
  pit = list(features="t-1 backward (daily history strictly <= sig_date)", label="forward 1m return only",
             lockbox="2023-12-22 strict", C14="control Z_Score at same sig_date, Usable_Date<=sig_date via factor_db",
             shift_convention="forward label = next month-end / sig month-end - 1 (explicit forward, no neg-lead)"),
  controls = present_ctrl,
  n_obs = nrow(ic),
  avg_names_per_month = round(mean(ic$n)),
  raw = list(rank_ic=round(mean_ic,5), rank_ic_sd=round(sd_ic,5), icir_monthly=round(icir,4),
             icir_annualized=round(icir_ann,4), harvey_t_nw=round(t_nw,4), hit_rate=round(hit,4)),
  orthogonal = list(residual_ic=round(mean_res,5), icir_res=round(icir_res,4), t_nw_res=round(t_res_nw,4),
                    partial_ic=round(mean_part,5), t_nw_partial=round(t_part_nw,4)),
  subperiod = lapply(seq_len(nrow(sub)), function(i) list(period=as.character(sub$third[i]),
                     n=sub$n[i], mean_rank_ic=round(sub$mean_ic[i],5), mean_res_ic=round(sub$mean_res[i],5))),
  subperiod_sign_stability = round(stab,3),
  caveat = "Cycle2 lesson: rank-IC t >> portfolio-alpha t. SCREEN advisory only.",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
writeLines(toJSON(res, auto_unbox=TRUE, pretty=TRUE, digits=6), file.path(OUT,"cgo_drift_screen_result.json"))
fwrite(ic, file.path(OUT,"cgo_ic_timeseries.csv"))
cat("\n[5] wrote cgo_drift_screen_result.json + cgo_ic_timeseries.csv\n")
