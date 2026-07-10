# Phase 2a — calibrate harness vs prior base_score_eff canonical PORT_t (2.749)
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA <- file.path(ROOT,"stage_artifacts","WT-D20260710_001")
source(file.path(ROOT,"02_Infrastructure","contracts","canonical_screen_bt.R"))
panel <- readRDS(file.path(SA,"panel.rds"))

# bench_dt: replicate run_forge_midcap.R lines 32-37 (forward-shifted cap-w KOSPI200, anchor-verified)
bm <- as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[, Dt := as.Date(Date)]; bm[, ym := format(Dt,"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_m <- bm[, .(bm_ret=expm1(sum(log1p(BM_Ret)))), by=ym][order(ym)]
bm_m[, Date := as.Date(paste0(ym,"-01"))]
bm_m[, bm_fwd := shift(bm_ret, type="lead", n=1L)]
benchdt <- bm_m[!is.na(bm_fwd), .(Date, BM_Ret=bm_fwd)]

returns_dt <- panel[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
liq_dt <- panel[, .(Date, Ticker, adv=tv20)]

# calibration: score_eff top-25 whole-universe
sc <- panel[!is.na(score_eff), .(Date, Ticker, score=score_eff)]
for(lm in c(0, 2e8)){
  r <- canonical_screen_bt(sc, returns_dt, benchdt, top_n=25L, cost_bps_oneway=15,
                           liq_dt=(if(lm>0) liq_dt else NULL), liq_min=lm,
                           run_id="calib", strategy_id="score_eff", diag_dual_basis=FALSE)
  cat(sprintf("[calib score_eff top25 liq=%.0e] n=%d PORT_t=%.4f IR=%.4f net_sr=%.4f TO=%.2f (prior base=2.749)\n",
              lm, r$n_months, r$portfolio_alpha_t_nw_lag3, r$information_ratio, r$net_sr, r$turnover_annual))
}
