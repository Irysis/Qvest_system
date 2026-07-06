suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"; OUT <- "stage_artifacts/WT-D20260706_008"
pl <- readRDS(file.path(TMP,"wt008_pl.rds")); setDT(pl)
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","BM_Ret")))
rd[, Date := as.Date(Date)]; rd[, ym := format(Date,"%Y-%m")]
bm_m <- rd[!is.na(BM_Ret), .(BM_Ret_m = prod(1+BM_Ret)-1), by=ym]; setorder(bm_m, ym)
bm_m[, fwd_bm := shift(BM_Ret_m,-1)]
pl <- merge(pl, bm_m[, .(ym, fwd_bm)], by="ym", all.x=TRUE)
pl <- pl[!is.na(fwd_bm) & !is.na(fwd_ret)]   # drop last month (no forward)
cat("Usable rows:", nrow(pl), " months:", uniqueN(pl$ym), "\n\n")

run_screen <- function(d, scorecol, label, top_n=25L){
  d <- d[!is.na(get(scorecol))]
  sc <- d[, .(Date=me_date, Ticker, score=get(scorecol))]
  rr <- d[, .(Date=me_date, Ticker, Ret_1m=fwd_ret)]
  bd <- unique(d[, .(Date=me_date, BM_Ret=fwd_bm)])
  res <- tryCatch(canonical_screen_bt(sc, rr, bd, top_n=top_n, cost_bps_oneway=15),
                  error=function(e){cat("ERR",label,":",e$message,"\n");NULL})
  if(is.null(res)) return(NULL)
  cat(sprintf("%-32s | PORT_t=%+.2f IR=%+.2f netSR=%+.2f alpha=%+.2f%% TO=%.0f%% n=%d\n",
    label,res$portfolio_alpha_t_nw_lag3,res$information_ratio,res$net_sr,
    res$alpha_annualized*100,res$turnover_annual*100,res$n_months)); invisible(res)
}
cat("=== CANONICAL top-25 EW long-only 15bps (PORT_t authoritative) ===\n")
run_screen(pl, "z_basis_pct", "A: pick richest basis")
pl[, negoi := -z_oi_chg]; pl[, comp := z_basis_pct + z_basis_mom - z_oi_chg]
run_screen(pl, "z_basis_mom", "B: pick basis momentum")
run_screen(pl, "negoi",       "C: pick -oi_change")
run_screen(pl, "comp",        "D: composite")

cat("\n=== LONG-SIDE HARVESTABILITY: exclude cheap-basis from a liquidity book ===\n")
run_screen(pl, "adv_m", "E: liq-only baseline (top25 liq)")
plx <- copy(pl); plx[, rk := frank(z_basis_pct)/.N, by=ym]
run_screen(plx[rk>0.20], "adv_m", "F: liq-book EXCL bottom-20% basis")
run_screen(plx[rk>0.40], "adv_m", "G: liq-book EXCL bottom-40% basis")

cat("\n=== post-2018 subperiod for winner (A) ===\n")
run_screen(pl[as.integer(substr(ym,1,4))>=2018], "z_basis_pct", "A-post2018: richest basis")
