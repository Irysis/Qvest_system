suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"; OUT <- "stage_artifacts/WT-D20260706_008"
pl <- readRDS(file.path(TMP,"wt008_pl.rds")); setDT(pl)

# canonical inputs. Date = signal date (me_date). Ret_1m = forward realized (fwd_ret).
# bench: BM_Ret from RAWDATA (KOSPI200 TR) aligned to forward month.
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","BM_Ret")))
rd[, Date := as.Date(Date)]; rd[, ym := format(Date,"%Y-%m")]
bm_m <- rd[, .(BM_Ret_m = prod(1+BM_Ret,na.rm=TRUE)-1), by=ym]  # monthly bench return
setorder(bm_m, ym)
bm_m[, fwd_bm := shift(BM_Ret_m, -1)]   # forward month bench

pl <- merge(pl, bm_m[, .(ym, fwd_bm)], by="ym", all.x=TRUE)
pl[, sig_date := me_date]

run_screen <- function(scoreexpr, label, exclude_bottom=FALSE, botpct=0.2){
  d <- copy(pl)
  d[, score := eval(scoreexpr, d)]
  d <- d[!is.na(score) & !is.na(fwd_ret)]
  if (exclude_bottom) {
    d[, rk := frank(score)/.N, by=ym]
    d <- d[rk > botpct]  # drop cheapest-basis bottom
  }
  scores_dt  <- d[, .(Date=sig_date, Ticker, score)]
  returns_dt <- d[, .(Date=sig_date, Ticker, Ret_1m=fwd_ret)]
  bench_dt   <- unique(d[, .(Date=sig_date, BM_Ret=fwd_bm)])
  res <- tryCatch(canonical_screen_bt(scores_dt, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15),
                  error=function(e){cat("ERR",label,":",e$message,"\n");NULL})
  if (is.null(res)) return(NULL)
  cat(sprintf("%-30s | PORT_t=%+.2f  IR=%+.2f  netSR=%+.2f  alpha_ann=%+.2f%%  TO=%.0f%%  n_mo=%d\n",
    label, res$portfolio_alpha_t_nw_lag3, res$information_ratio, res$net_sr,
    res$alpha_annualized*100, res$turnover_annual*100, res$n_months))
  invisible(res)
}
cat("=== CANONICAL top-25 EW long-only (15bps), PORT_t authoritative ===\n\n")
cat("-- A. basis_pct as score (pick richest basis) --\n")
rA <- run_screen(quote(z_basis_pct), "A: top25 by basis_pct")
cat("\n-- B. basis_mom as score --\n")
rB <- run_screen(quote(z_basis_mom), "B: top25 by basis_mom")
cat("\n-- C. -oi_chg as score (contrarian OI) --\n")
rC <- run_screen(quote(-z_oi_chg), "C: top25 by -oi_change")
cat("\n-- D. composite (basis_pct + basis_mom - oi_chg) --\n")
rD <- run_screen(quote(z_basis_pct + z_basis_mom - z_oi_chg), "D: composite top25")

cat("\n=== HARVESTABILITY: does EXCLUDING cheap-basis help a NEUTRAL book? ===\n")
cat("(score=random-ish liquidity anchor, then exclude bottom basis quintile)\n")
set.seed(42); pl[, rnd := runif(.N)]
cat("\n-- E. baseline: top25 by liquidity (adv_m), NO basis --\n")
rE <- run_screen(quote(adv_m), "E: top25 by liquidity")
cat("\n-- F. same liquidity pick but EXCLUDE bottom-20% basis first --\n")
# manual: filter bottom basis then pick top adv
d <- copy(pl)[!is.na(z_basis_pct) & !is.na(fwd_ret)]
d[, rk := frank(z_basis_pct)/.N, by=ym]; d <- d[rk>0.2]
sc <- d[, .(Date=me_date, Ticker, score=adv_m)]; rr <- d[, .(Date=me_date, Ticker, Ret_1m=fwd_ret)]
bd <- unique(d[, .(Date=me_date, BM_Ret=fwd_bm)])
rF <- canonical_screen_bt(sc, rr, bd, top_n=25L, cost_bps_oneway=15)
cat(sprintf("%-30s | PORT_t=%+.2f  IR=%+.2f  netSR=%+.2f  alpha_ann=%+.2f%%\n",
  "F: liq-pick excl cheap basis", rF$portfolio_alpha_t_nw_lag3, rF$information_ratio, rF$net_sr, rF$alpha_annualized*100))
