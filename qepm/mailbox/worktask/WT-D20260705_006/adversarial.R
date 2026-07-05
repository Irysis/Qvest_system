# Self-Adversarial Challenge probes
Sys.setenv(LC_ALL = "English_United States.utf8")
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))
data.table::setDTthreads(1L)
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROJ)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
STA <- file.path(PROJ, "stage_artifacts/WT_D20260705_006")
bp  <- readRDS(file.path(STA,"base_panels.rds")); FAC <- readRDS(file.path(STA,"FAC.rds"))
returns_dt <- bp$returns_dt; bench_dt <- bp$bench_dt; liq_dt <- bp$liq_dt
CORE6 <- c("GR03_Asset_Growth","AC24_NOA_Growth","AC05_NOA","AC09_NNI",
           "IN04_Net_Equity_Issuance","IN06_Investment_to_Assets")
comp <- FAC[Factor_Name %in% CORE6][, .(score=mean(Z), n=.N), by=.(Date,Ticker)][n>=2,.(Date,Ticker,score)]

# CHALLENGE 1: is composite just IN04 repackaged? correlation of composite to each component
for (f in CORE6) {
  ff <- FAC[Factor_Name==f, .(Date,Ticker,z=Z)]
  m <- merge(comp, ff, by=c("Date","Ticker"))
  cat(sprintf("[C1] composite rank-rho vs %-28s = %.3f\n", f, cor(m$score,m$z,method="spearman")))
}

# CHALLENGE 2: top-25 illiquidity check — what fraction of selected names below 5e8? (RF-A5)
setorder(comp, Date, -score)
top25 <- comp[, .SD[seq_len(min(25,.N))], by=Date]
top25 <- merge(top25, liq_dt, by=c("Date","Ticker"), all.x=TRUE)
cat(sprintf("[C2] top-25 selections: %d | with adv<5e8: %.1f%% | median adv=%.2e KRW\n",
    nrow(top25), 100*mean(top25$adv < 5e8, na.rm=TRUE), median(top25$adv, na.rm=TRUE)))

# CHALLENGE 3: leave-IN04-out composite (does removing the only positive component kill it or not?)
CORE5 <- setdiff(CORE6, "IN04_Net_Equity_Issuance")
comp5 <- FAC[Factor_Name %in% CORE5][, .(score=mean(Z), n=.N), by=.(Date,Ticker)][n>=2,.(Date,Ticker,score)]
cs5 <- canonical_screen_bt(comp5, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
                           liq_dt=liq_dt, liq_min=2e8, run_id="core5_noIN04", strategy_id="core5_noIN04")
cat(sprintf("[C3] core5 (drop IN04) PORT_t=%.3f net_sr=%.3f\n",
    cs5$portfolio_alpha_t_nw_lag3, cs5$net_sr))

# CHALLENGE 4: lookahead sanity — recompute pre2017 with a HARD 2-yr embargo shift on scores
# (shift scores forward 1 extra month = strictly worse info; if pre2017 alpha survives with LESS
#  info, it's not lookahead-inflated; if it collapses, suspect timing). Use core6.
comp_lag <- copy(comp); setorder(comp_lag, Ticker, Date)
comp_lag[, score := shift(score, 1L), by=Ticker]   # use last month's score (strictly stale)
comp_lag <- comp_lag[!is.na(score)]
cs_lag_pre <- canonical_screen_bt(comp_lag[Date<as.Date("2017-01-01")], returns_dt, bench_dt,
    top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8, run_id="lag", strategy_id="lag")
cat(sprintf("[C4] pre2017 with 1M-STALE scores PORT_t=%.3f (vs live pre2017 +1.716; small drop=no lookahead)\n",
    cs_lag_pre$portfolio_alpha_t_nw_lag3))

# CHALLENGE 5: does the pre2017 alpha concentrate in a single crisis window (2008)? split pre2017
cs_0812 <- canonical_screen_bt(comp[Date>=as.Date("2005-01-01") & Date<as.Date("2012-01-01")],
    returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8, run_id="p1", strategy_id="p1")
cs_1216 <- canonical_screen_bt(comp[Date>=as.Date("2012-01-01") & Date<as.Date("2017-01-01")],
    returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8, run_id="p2", strategy_id="p2")
cat(sprintf("[C5] 2005-2011 PORT_t=%.3f | 2012-2016 PORT_t=%.3f (both>0 => pre2017 not single-window)\n",
    cs_0812$portfolio_alpha_t_nw_lag3, cs_1216$portfolio_alpha_t_nw_lag3))
cat("\nADVERSARIAL DONE\n")
