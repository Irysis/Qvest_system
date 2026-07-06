suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"; OUT <- "stage_artifacts/WT-D20260706_008"
pl <- readRDS(file.path(TMP,"wt008_pl.rds")); setDT(pl)

# Clean monthly benchmark from BM_Close (month-end to month-end)
b <- as.data.table(read_parquet(".cache/benchmark.parquet"))
b[, Date := as.Date(Date)]; b[, ym := format(Date,"%Y-%m")]
setorder(b, Date)
bm_me <- b[, .(bmclose=last(BM_Close), me=last(Date)), by=ym]; setorder(bm_me, me)
bm_me[, bm_ret_m := bmclose/shift(bmclose)-1]       # this-month return
bm_me[, fwd_bm := shift(bm_ret_m, -1)]              # forward month return (t->t+1)
cat("bm monthly range:", range(bm_me$bm_ret_m,na.rm=T)," fwd_bm range:",range(bm_me$fwd_bm,na.rm=T),"\n")

pl <- merge(pl, bm_me[,.(ym,fwd_bm)], by="ym", all.x=TRUE)
pl <- pl[!is.na(fwd_bm) & !is.na(fwd_ret) & is.finite(fwd_bm) & is.finite(fwd_ret)]
cat("Usable rows:", nrow(pl)," months:", uniqueN(pl$ym),"\n\n")

run_screen <- function(d, scorecol, label, top_n=25L){
  d <- d[!is.na(get(scorecol)) & is.finite(get(scorecol))]
  sc <- d[, .(Date=me_date, Ticker, score=get(scorecol))]
  rr <- d[, .(Date=me_date, Ticker, Ret_1m=fwd_ret)]
  bd <- unique(d[, .(Date=me_date, BM_Ret=fwd_bm)])
  res <- tryCatch(canonical_screen_bt(sc, rr, bd, top_n=top_n, cost_bps_oneway=15),
                  error=function(e){cat("ERR",label,":",e$message,"\n");NULL})
  if(is.null(res)||is.null(res$portfolio_alpha_t_nw_lag3)) return(invisible(NULL))
  cat(sprintf("%-34s | PORT_t=%+.2f IR=%+.2f netSR=%+.2f alpha=%+.2f%% TO=%.0f%% n=%d\n",
    label,res$portfolio_alpha_t_nw_lag3,res$information_ratio,res$net_sr,
    res$alpha_annualized*100,res$turnover_annual*100,res$n_months)); invisible(res)
}
cat("=== CANONICAL top-25 EW long-only 15bps (PORT_t authoritative, clean bench) ===\n")
rA <- run_screen(pl, "z_basis_pct", "A: pick richest basis")
pl[, negoi := -z_oi_chg]; pl[, comp := z_basis_pct + z_basis_mom - z_oi_chg]
rB <- run_screen(pl, "z_basis_mom", "B: pick basis momentum")
rC <- run_screen(pl, "negoi",       "C: pick -oi_change")
rD <- run_screen(pl, "comp",        "D: composite basis+mom-oi")

cat("\n=== LONG-SIDE HARVESTABILITY (exclude cheap-basis from liquidity book) ===\n")
rE <- run_screen(pl, "adv_m", "E: liq-only baseline")
plx <- copy(pl); plx[, rk := frank(z_basis_pct)/.N, by=ym]
rF <- run_screen(plx[rk>0.20], "adv_m", "F: liq-book EXCL bottom-20% basis")
rG <- run_screen(plx[rk>0.40], "adv_m", "G: liq-book EXCL bottom-40% basis")

cat("\n=== post-2018 for A + composite ===\n")
run_screen(pl[as.integer(substr(ym,1,4))>=2018], "z_basis_pct", "A-post2018")
run_screen(pl[as.integer(substr(ym,1,4))>=2018], "comp",        "D-post2018")

# save winner series for oos_retention
if(!is.null(rA)) saveRDS(rA, file.path(TMP,"wt008_rA.rds"))
if(!is.null(rD)) saveRDS(rD, file.path(TMP,"wt008_rD.rds"))
