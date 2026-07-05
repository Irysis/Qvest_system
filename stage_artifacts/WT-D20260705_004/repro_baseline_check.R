# repro_baseline_check.R — validity gate before A/B.
# Reproduce alpha baseline A (point mu_hat top-25 EW, full_port_t=0.9698) via weighted_screen_bt.
# If EW-of-top25 != ~0.97, my pipeline is misaligned and A/B is invalid.
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA   <- file.path(ROOT,"stage_artifacts","WT-D20260705_004")
source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","weighted_screen_bt.R"))

pan <- as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet")))
yms <- sort(unique(pan$ym))
bm <- as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[, ym := format(as.Date(Date),"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_lr <- bm[, .(lr=sum(log1p(BM_Ret))), by=ym][order(ym)]
bm_lr[, bm_fwd := expm1(shift(lr, type="lead", n=1L))]
ym2date <- function(y) as.Date(paste0(y,"-01"))
benchdt <- bm_lr[!is.na(bm_fwd), .(Date=ym2date(ym), BM_Ret=bm_fwd)]
rets <- pan[, .(Date=ym2date(ym), Ticker, Ret_1m=F1)]

# top-25 by mu_hat, EW
setorder(pan, ym, -mu_hat)
top25 <- pan[, head(.SD, 25L), by=ym]
wd <- top25[, .(Date=ym2date(ym), Ticker, w=1/25)]
r <- weighted_screen_bt(wd, rets, benchdt, cost_bps_oneway=15,
                        run_id="repro_A", strategy_id="repro_A")
cat(sprintf("REPRO baseline A (top25 EW): full_port_t=%.4f  IR=%.4f  turnover=%.2f  n=%d  (alpha reported 0.9698)\n",
            r$portfolio_alpha_t_nw_lag3, r$information_ratio, r$turnover_annual, r$n_months))
wd_r <- wd[Date >= as.Date("2017-01-01")]
rr <- weighted_screen_bt(wd_r, rets, benchdt, cost_bps_oneway=15, run_id="repro_A_rec", strategy_id="repro_A_rec")
cat(sprintf("REPRO baseline A recent2017: port_t=%.4f  n=%d  (alpha reported -0.7248)\n",
            rr$portfolio_alpha_t_nw_lag3, rr$n_months))
