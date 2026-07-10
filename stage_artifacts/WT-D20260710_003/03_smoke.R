# 03_smoke.R — verify harness + parity vs canonical_screen_bt (sanctioned helper) on flat EW baseline
suppressPackageStartupMessages({ library(data.table) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "stage_artifacts/WT-D20260710_003/02_harness.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
bundle <- readRDS(file.path(ROOT, "stage_artifacts/WT-D20260710_003/panel_bundle.rds"))

regime <- build_regime_signal(bundle)
cat("[smoke] regime signal rows:", nrow(regime), " non-NA:", sum(!is.na(regime$regime_spread)), "\n")

# baseline: flat top-25, cross_family all_ew, EW, static
cfg0 <- list(id="BASE_flat25_allEW", H="BASE", factor_design="all_ew",
             exposure_ctrl="full", universe_strat="flat", weighting="EW",
             regime_dyn="static", top_n=25L)
r0 <- screen_config(cfg0, bundle, regime=regime, window="full")
cat(sprintf("[smoke] BASE full: n=%d port_t=%.3f ir=%.3f net_sr=%.3f calmar=%.3f oos_ret=%.3f TO=%.0f%% bm_cor=%.3f bm_dIR=%.4f maxN=%d\n",
    r0$n_months, r0$port_t, r0$ir, r0$net_sr, r0$calmar, r0$oos_retention, 100*r0$turnover_annual, r0$bm_cor, r0$bm_dIR_sleeve, r0$max_names))

# parity: same selection via canonical_screen_bt (top-25 EW) using my composite score
S <- build_score(bundle$features, bundle$size, cfg0)
scores_dt <- S[, .(Date, Ticker, score)]
liq_dt <- bundle$univ[, .(Date, Ticker, adv=adv20)]
cs <- canonical_screen_bt(scores_dt, bundle$returns, bundle$bench, top_n=25L,
                          cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8,
                          diag_dual_basis=FALSE)
cat(sprintf("[smoke] canonical_screen_bt parity: port_t=%.3f ir=%.3f net_sr=%.3f TO=%.0f%% n=%d\n",
    cs$portfolio_alpha_t_nw_lag3, cs$information_ratio, cs$net_sr, 100*cs$turnover_annual, cs$n_months))
cat(sprintf("[smoke] PARITY DELTA port_t=%.4f net_sr=%.4f\n",
    r0$port_t - cs$portfolio_alpha_t_nw_lag3, r0$net_sr - cs$net_sr))

# IS / OOS split check
ris <- screen_config(cfg0, bundle, regime=regime, window="IS")
roos<- screen_config(cfg0, bundle, regime=regime, window="OOS")
cat(sprintf("[smoke] BASE IS : n=%d port_t=%.3f net_sr=%.3f\n", ris$n_months, ris$port_t, ris$net_sr))
cat(sprintf("[smoke] BASE OOS: n=%d port_t=%.3f net_sr=%.3f\n", roos$n_months, roos$port_t, roos$net_sr))
cat("[smoke] DONE\n")
