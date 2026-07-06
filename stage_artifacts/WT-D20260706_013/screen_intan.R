# screen_intan.R — WT-D20260706_013 Alpha Research
# Canonical screening of intangible-adjusted value + CONTROL standard value + mega-cap dual-benchmark
# + large-cap decomposition + reclassification spread + quality-orthogonality.
# Real-computation via canonical_screen_bt (contract-grade, NW lag-3). metric_type=canonical_screen.

suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

PAN <- file.path(ROOT, "stage_artifacts/WT-D20260706_013/panel")
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260706_013")

sc    <- as.data.table(read_parquet(file.path(PAN, "intan_scores_monthly.parquet")))
rets  <- as.data.table(read_parquet(file.path(PAN, "returns_monthly.parquet")))
bm_cw <- as.data.table(read_parquet(file.path(PAN, "benchmark_capw.parquet")))
bm_ew <- as.data.table(read_parquet(file.path(PAN, "benchmark_ew.parquet")))
univ  <- as.data.table(read_parquet(file.path(PAN, "universe_flags.parquet")))

START <- as.Date("2005-01-01")
sc <- sc[Date >= START]; rets <- rets[Date >= START]
bm_cw <- bm_cw[Date >= START]; bm_ew <- bm_ew[Date >= START]; univ <- univ[Date >= START]
liq <- univ[, .(Date, Ticker, adv = adv20)]
rets <- rets[, .(Date, Ticker, Ret_1m)]

# ---- rank-IC diagnostic (Spearman score vs forward return) — NOT authoritative ----
rank_ic_diag <- function(scoredt, scol) {
  d <- merge(scoredt[is.finite(get(scol)), .(Date, Ticker, s = get(scol))], rets, by = c("Date","Ticker"))
  icm <- d[, .(ic = suppressWarnings(cor(s, Ret_1m, method="spearman"))), by = Date][is.finite(ic)]
  if (nrow(icm) < 6) return(list(rank_ic=NA,ic_t=NA,icir=NA,n=nrow(icm),icm=icm))
  list(rank_ic = mean(icm$ic), ic_t = mean(icm$ic)/(sd(icm$ic)/sqrt(nrow(icm))),
       icir = mean(icm$ic)/sd(icm$ic), n = nrow(icm), icm = icm)
}

# ---- canonical screen runner ----
run_screen <- function(scoredt, scol, months, bench, label, top_n = 25L) {
  s <- scoredt[Date %in% months & is.finite(get(scol)), .(Date, Ticker, score = get(scol))]
  r <- rets[Date %in% months]; b <- bench[Date %in% months]; l <- liq[Date %in% months]
  if (uniqueN(s$Date) < 6) return(data.table(label=label, n_months=uniqueN(s$Date), port_t=NA,ir=NA,net_sr=NA,alpha_ann=NA,turnover=NA))
  res <- canonical_screen_bt(s, r, b, top_n = top_n, cost_bps_oneway = 15,
                             liq_dt = l, liq_min = 2e8, periods_per_year = 12L,
                             run_id = paste0("intan_", label), strategy_id = paste0("intan_", label))
  data.table(label = label, n_months = res$n_months,
             port_t = round(res$portfolio_alpha_t_nw_lag3, 3), ir = round(res$information_ratio, 3),
             net_sr = round(res$net_sr, 3), alpha_ann = round(res$alpha_annualized, 4),
             turnover = round(res$turnover_annual, 3))
}

all_m    <- sort(unique(sc$Date))
pre17_m  <- all_m[all_m <  as.Date("2017-01-01")]
post17_m <- all_m[all_m >= as.Date("2017-01-01")]
valup_m  <- all_m[all_m >= as.Date("2024-01-01")]

# =========================================================================
# rank-IC for all signal variants
cat("=============================================================\n")
cat("RANK-IC (diagnostic) — all variants, full sample\n")
sigs <- c("stdBM","stdEP","iBM_full","iBM_orgc","iEP_full","iEP_orgc")
ic_tbl <- rbindlist(lapply(sigs, function(s){
  ic <- rank_ic_diag(sc, s)
  data.table(signal=s, rank_ic=round(ic$rank_ic,4), ic_t=round(ic$ic_t,2), icir=round(ic$icir,3), n=ic$n)
}))
print(ic_tbl)

# rank-IC by sub-period for the two headline signals
cat("\n--- rank-IC by period (iBM_orgc vs stdBM) ---\n")
for (s in c("stdBM","iBM_orgc","iBM_full")) for (pm in list(pre=pre17_m, post=post17_m)) {
  ic <- rank_ic_diag(sc[Date %in% pm], s)
  cat(sprintf("  %-9s %-4s rank-IC=%.4f t=%.2f n=%d\n", s,
      if(identical(pm,pre17_m))"pre" else "post", ic$rank_ic, ic$ic_t, ic$n))
}

# =========================================================================
# CANONICAL SCREEN: each signal, both benchmarks, sub-periods
runset <- function(scol, tag) {
  cat(sprintf("\n=== CANONICAL SCREEN [%s] — cap-w (float) universe benchmark ===\n", tag))
  cw <- rbindlist(list(
    run_screen(sc, scol, all_m,    bm_cw, "FULL_capw"),
    run_screen(sc, scol, pre17_m,  bm_cw, "PRE2017_capw"),
    run_screen(sc, scol, post17_m, bm_cw, "POST2017_capw"),
    run_screen(sc, scol, valup_m,  bm_cw, "VALUEUP2024_capw")
  ), fill=TRUE); print(cw)
  cat(sprintf("=== CANONICAL SCREEN [%s] — EW universe benchmark (mega-cap artifact diagnostic) ===\n", tag))
  ew <- rbindlist(list(
    run_screen(sc, scol, all_m,    bm_ew, "FULL_ew"),
    run_screen(sc, scol, pre17_m,  bm_ew, "PRE2017_ew"),
    run_screen(sc, scol, post17_m, bm_ew, "POST2017_ew"),
    run_screen(sc, scol, valup_m,  bm_ew, "VALUEUP2024_ew")
  ), fill=TRUE); print(ew)
  list(cw=cw, ew=ew)
}
res_std   <- runset("stdBM",    "CONTROL_stdBM")
res_stdEP <- runset("stdEP",    "CONTROL_stdEP")
res_orgc  <- runset("iBM_orgc", "iBM_orgc")
res_full  <- runset("iBM_full", "iBM_full")
res_iEPo  <- runset("iEP_orgc", "iEP_orgc")

# =========================================================================
# DECILE realized-alpha profile (monotonicity) — headline iBM_orgc
cat("\n=== DECILE realized forward-return profile [iBM_orgc] (D10=cheapest) ===\n")
dd <- merge(sc[is.finite(iBM_orgc), .(Date, Ticker, s=iBM_orgc)], rets, by=c("Date","Ticker"))
dd[, dec := cut(frank(s)/.N, breaks=seq(0,1,0.1), labels=1:10, include.lowest=TRUE), by=Date]
decprof <- dd[, .(mean_fwd = mean(Ret_1m, na.rm=TRUE), n=.N), by=dec][order(dec)]
print(decprof)
mono <- suppressWarnings(cor(as.numeric(decprof$dec), decprof$mean_fwd, method="spearman"))
cat(sprintf("[decile] monotonicity (Spearman) = %.3f   EW-uni mean fwd = %.4f\n",
    mono, mean(bm_ew$BM_Ret, na.rm=TRUE)))

# =========================================================================
# ★ LARGE-CAP-CONDITIONAL decomposition (wall-escape판별)
cat("\n=== LARGE-CAP-CONDITIONAL decomposition ===\n")
sc[, size_grp := fifelse(size_pctile >= 0.60, "LARGE", "SMALL")]
run_within <- function(scol, grp, bench, blabel, months=all_m) {
  s <- sc[Date %in% months & is.finite(get(scol)) & size_grp==grp, .(Date, Ticker, score=get(scol))]
  r <- rets[Date %in% months]; b <- bench[Date %in% months]; l <- liq[Date %in% months]
  if (uniqueN(s$Date) < 6) return(data.table(signal=scol,group=grp,bench=blabel,n_months=uniqueN(s$Date),port_t=NA,ir=NA,net_sr=NA,alpha_ann=NA))
  res <- canonical_screen_bt(s, r, b, top_n=25L, cost_bps_oneway=15, liq_dt=l, liq_min=2e8,
                             periods_per_year=12L, run_id=paste0(scol,"_",grp), strategy_id=paste0(scol,"_",grp))
  data.table(signal=scol, group=grp, bench=blabel, n_months=res$n_months,
             port_t=round(res$portfolio_alpha_t_nw_lag3,3), ir=round(res$information_ratio,3),
             net_sr=round(res$net_sr,3), alpha_ann=round(res$alpha_annualized,4))
}
lc <- rbindlist(lapply(c("stdBM","iBM_orgc","iBM_full"), function(sg) rbindlist(list(
  run_within(sg,"LARGE", bm_cw, "capw"), run_within(sg,"LARGE", bm_ew, "ew"),
  run_within(sg,"SMALL", bm_cw, "capw"), run_within(sg,"SMALL", bm_ew, "ew")
), fill=TRUE)), fill=TRUE)
print(lc)

# size x signal interaction: rank-IC within large vs small
cat("\n--- size-conditional rank-IC ---\n")
for (sg in c("stdBM","iBM_orgc")) {
  icL <- rank_ic_diag(sc[size_grp=="LARGE"], sg); icS <- rank_ic_diag(sc[size_grp=="SMALL"], sg)
  cat(sprintf("  %-9s LARGE rank-IC=%.4f t=%.2f | SMALL rank-IC=%.4f t=%.2f\n",
      sg, icL$rank_ic, icL$ic_t, icS$rank_ic, icS$ic_t))
}

# mega-cap composition of top-25 (are picks mega-cap?)
comp <- function(scol) {
  tmp <- sc[is.finite(get(scol))]
  tmp[, .s := get(scol)]
  setorder(tmp, Date, -.s)
  t25 <- tmp[, .SD[seq_len(min(25L,.N))], by=Date]
  cat(sprintf("[megacap %-9s] top-25 median size-rank=%.0f  median size-pctile=%.1f%%  frac size-top40=%.3f\n",
      scol, median(t25$size_rank), 100*median(t25$size_pctile), mean(t25$size_pctile>=0.60)))
}
cat("\n--- top-25 mega-cap composition ---\n")
comp("stdBM"); comp("iBM_orgc"); comp("iBM_full")

# =========================================================================
# ★ RECLASSIFICATION spread: how much does iBM_orgc re-rank vs stdBM? (per-month rank correlation
#   + which firms move up most = reclassified-cheap). Lower cor / larger tail moves = more reclassification.
cat("\n=== RECLASSIFICATION (iBM_orgc vs stdBM) ===\n")
rr <- sc[is.finite(stdBM) & is.finite(iBM_orgc)]
rr[, rk_std  := frank(stdBM)/.N, by=Date]
rr[, rk_intan:= frank(iBM_orgc)/.N, by=Date]
rr[, rk_shift := rk_intan - rk_std]           # >0 = became cheaper under intangible adj
xrank_cor <- rr[, .(rho = suppressWarnings(cor(rk_std, rk_intan, method="spearman"))), by=Date]
cat(sprintf("[reclass] median monthly cross-rank Spearman(stdBM,iBM_orgc)=%.3f  (1=no reclass)\n",
    median(xrank_cor$rho, na.rm=TRUE)))
# among LARGE caps, do they move UP (become cheaper) under intangible adj? (wall-escape mechanism)
lc_shift <- rr[size_pctile>=0.60, .(mean_shift = mean(rk_shift, na.rm=TRUE), med_shift=median(rk_shift,na.rm=TRUE), n=.N)]
sm_shift <- rr[size_pctile< 0.60, .(mean_shift = mean(rk_shift, na.rm=TRUE), med_shift=median(rk_shift,na.rm=TRUE), n=.N)]
cat(sprintf("[reclass] LARGE-cap mean rank-shift (intan-std)=%.4f (n=%d)  |  SMALL-cap=%.4f (n=%d)\n",
    lc_shift$mean_shift, lc_shift$n, sm_shift$mean_shift, sm_shift$n))
cat("   (LARGE >0 = intangible adj reclassifies big firms cheaper = wall-escape mechanism intact)\n")
# top reclassified-cheaper names (recent month) — sanity check vs thesis (Samsung/NAVER/etc)
recent_m <- max(rr$Date)
topmove <- rr[Date==recent_m][order(-rk_shift)][1:12, .(Ticker, size_rank, rk_std=round(rk_std,2), rk_intan=round(rk_intan,2), rk_shift=round(rk_shift,2), intan_intensity=round(intan_intensity,2))]
cat(sprintf("[reclass] top-12 reclassified-cheaper names @ %s:\n", as.character(recent_m))); print(topmove)

saveRDS(list(ic_tbl=ic_tbl, res_std=res_std, res_stdEP=res_stdEP, res_orgc=res_orgc,
             res_full=res_full, res_iEPo=res_iEPo, decprof=decprof, mono=mono, lc=lc,
             xrank_cor_med=median(xrank_cor$rho,na.rm=TRUE), lc_shift=lc_shift, sm_shift=sm_shift,
             topmove=topmove),
        file.path(OUT, "screen_results.rds"))
cat("\n[screen] DONE — saved screen_results.rds\n")
