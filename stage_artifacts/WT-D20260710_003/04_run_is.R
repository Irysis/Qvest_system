# 04_run_is.R — Stage A: IS-ONLY metrics for all joint configs. Selection locked from IS.
# H1 (tier-stratified x tier-weighting) + H3 (regime-conditional active-share, overlay-coherent) + baselines.
# H2/H4/H5 PRE-DEMOTED (Q-Lead scope directive) — not run, not counted in n_trials.
# Discipline: this stage NEVER computes OOS. Winner selected by IS canonical PORT_t among IS-robust configs.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT, "stage_artifacts/WT-D20260710_003/02_harness.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260710_003")
bundle <- readRDS(file.path(OUT, "panel_bundle.rds"))
regime <- build_regime_signal(bundle)

CFG <- list()
add <- function(...) CFG[[length(CFG)+1]] <<- list(...)

# ---- Baselines (reference; measured => counted in n_trials) ----
add(id="BASE_flat25_allEW",  H="BASE", factor_design="all_ew",        exposure_ctrl="full", universe_strat="flat", weighting="EW",         regime_dyn="static", top_n=25L)
add(id="BASE_flat25_valqual",H="BASE", factor_design="value_quality", exposure_ctrl="full", universe_strat="flat", weighting="EW",         regime_dyn="static", top_n=25L)
add(id="BASE_flat25_aprop",  H="BASE", factor_design="all_ew",        exposure_ctrl="full", universe_strat="flat", weighting="alpha_prop", regime_dyn="static", top_n=25L)
add(id="BASE_flat20_allEW",  H="BASE", factor_design="all_ew",        exposure_ctrl="full", universe_strat="flat", weighting="EW",         regime_dyn="static", top_n=20L)

# ---- H1: tier-stratified selection x tier-weighting ----
add(id="H1a_q0_20_5_EW",     H="H1", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(0,20,5),  weighting="EW", regime_dyn="static")
add(id="H1b_q5_15_5_EW",     H="H1", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(5,15,5),  weighting="EW", regime_dyn="static")
add(id="H1c_q5_15_5_twMid",  H="H1", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(5,15,5),  weighting="tier_weight", tier_w=c(MEGA=.25,MID=.60,OTHER=.15), regime_dyn="static")
add(id="H1d_q5_15_5_twMega", H="H1", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(5,15,5),  weighting="tier_weight", tier_w=c(MEGA=.50,MID=.40,OTHER=.10), regime_dyn="static")
add(id="H1e_q3_17_5_twMid",  H="H1", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(3,17,5),  weighting="tier_weight", tier_w=c(MEGA=.30,MID=.55,OTHER=.15), regime_dyn="static")
add(id="H1f_q5_20_0_EW",     H="H1", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(5,20,0),  weighting="EW", regime_dyn="static")
add(id="H1g_q8_12_5_twMega", H="H1", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(8,12,5),  weighting="tier_weight", tier_w=c(MEGA=.45,MID=.45,OTHER=.10), regime_dyn="static")
add(id="H1h_q5_15_5_cap",    H="H1", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(5,15,5),  weighting="cap_within", regime_dyn="static")
add(id="H1i_q0_20_5_aprop",  H="H1", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(0,20,5),  weighting="alpha_prop", regime_dyn="static")
add(id="H1j_q5_15_5_valqual",H="H1", factor_design="value_quality", exposure_ctrl="full", universe_strat="tier", quota=c(5,15,5), weighting="EW", regime_dyn="static")
add(id="H1k_q5_15_5_momqual",H="H1", factor_design="mom_quality",   exposure_ctrl="full", universe_strat="tier", quota=c(5,15,5), weighting="EW", regime_dyn="static")
add(id="H1l_q3_17_5_sizeN",  H="H1", factor_design="all_ew", exposure_ctrl="size_neutral", universe_strat="tier", quota=c(3,17,5), weighting="tier_weight", tier_w=c(MEGA=.30,MID=.55,OTHER=.15), regime_dyn="static")

# ---- H3: regime-conditional active-share (blend alpha-tilt <-> cap-weight, ALWAYS fully invested,
#          NO cash/beta layer => TE modulation coherent with R05xm4 overlay, not double de-risking) ----
add(id="H3a_flat_l35_100",   H="H3", factor_design="all_ew", exposure_ctrl="full", universe_strat="flat", top_n=25L, weighting="EW", regime_dyn="regime_exposure", lambda_lo=0.35, lambda_hi=1.0, regime_thr=0.0, regime_scale=0.02)
add(id="H3b_flat_l25_100",   H="H3", factor_design="all_ew", exposure_ctrl="full", universe_strat="flat", top_n=25L, weighting="EW", regime_dyn="regime_exposure", lambda_lo=0.25, lambda_hi=1.0, regime_thr=0.0, regime_scale=0.02)
add(id="H3c_flat_l50_100",   H="H3", factor_design="all_ew", exposure_ctrl="full", universe_strat="flat", top_n=25L, weighting="EW", regime_dyn="regime_exposure", lambda_lo=0.50, lambda_hi=1.0, regime_thr=0.0, regime_scale=0.02)
add(id="H3d_flat_l35_085",   H="H3", factor_design="all_ew", exposure_ctrl="full", universe_strat="flat", top_n=25L, weighting="EW", regime_dyn="regime_exposure", lambda_lo=0.35, lambda_hi=0.85, regime_thr=0.0, regime_scale=0.02)
add(id="H3e_tier_l35_100",   H="H3", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(5,15,5), weighting="EW", regime_dyn="regime_exposure", lambda_lo=0.35, lambda_hi=1.0, regime_thr=0.0, regime_scale=0.02)  # H1xH3
add(id="H3f_tier_tw_l35",    H="H3", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(5,15,5), weighting="tier_weight", tier_w=c(MEGA=.30,MID=.55,OTHER=.15), regime_dyn="regime_exposure", lambda_lo=0.35, lambda_hi=1.0, regime_thr=0.0, regime_scale=0.02)
add(id="H3g_flat_thrMed",    H="H3", factor_design="all_ew", exposure_ctrl="full", universe_strat="flat", top_n=25L, weighting="EW", regime_dyn="regime_exposure", lambda_lo=0.35, lambda_hi=1.0, regime_thr=0.005, regime_scale=0.03)
add(id="H3h_flat_INVERT",    H="H3", factor_design="all_ew", exposure_ctrl="full", universe_strat="flat", top_n=25L, weighting="EW", regime_dyn="regime_exposure", lambda_lo=1.0, lambda_hi=0.35, regime_thr=0.0, regime_scale=0.02)  # falsification control (inverted)
add(id="H3i_tier_l30_090",   H="H3", factor_design="all_ew", exposure_ctrl="full", universe_strat="tier", quota=c(3,17,5), weighting="EW", regime_dyn="regime_exposure", lambda_lo=0.30, lambda_hi=0.90, regime_thr=0.0, regime_scale=0.02)
add(id="H3j_flat_aprop_l35", H="H3", factor_design="all_ew", exposure_ctrl="full", universe_strat="flat", top_n=25L, weighting="alpha_prop", regime_dyn="regime_exposure", lambda_lo=0.35, lambda_hi=1.0, regime_thr=0.0, regime_scale=0.02)

cat(sprintf("[run_is] %d configs (n_trials). IS window <= %s\n", length(CFG), as.character(IS_END)))

.nwt <- function(v){ if(length(v)<6) return(NA_real_); .nw_t_mean(v, lag=3) }
rows <- list()
for (i in seq_along(CFG)) {
  cfg <- CFG[[i]]
  r <- tryCatch(screen_config(cfg, bundle, regime=regime, window="IS"), error=function(e){cat("  ERR",cfg$id,conditionMessage(e),"\n");NULL})
  if (is.null(r)) next
  # IS-internal two-half stability (continuous blocks) — legitimate IS-only robustness
  n <- length(r$active); h <- floor(n/2)
  is_h1 <- .nwt(r$active[1:h]); is_h2 <- .nwt(r$active[(h+1):n])
  rows[[length(rows)+1]] <- data.table(
    id=cfg$id, H=cfg$H, n=r$n_months, maxN=r$max_names,
    is_port_t=r$port_t, is_net_sr=r$net_sr, is_ir=r$ir, is_calmar=r$calmar,
    is_oos_ret=r$oos_retention, is_TO=r$turnover_annual,
    is_h1_t=is_h1, is_h2_t=is_h2, is_both_half_pos=(is_h1>0 & is_h2>0),
    bm_cor=r$bm_cor, bm_dIR=r$bm_dIR_sleeve)
  cat(sprintf("  %-22s IS port_t=%6.3f net_sr=%5.2f h1t=%5.2f h2t=%5.2f both+=%s bm_cor=%5.2f bm_dIR=%+.4f TO=%.0f%%\n",
      cfg$id, r$port_t, r$net_sr, is_h1, is_h2, is_h1>0&is_h2>0, r$bm_cor, r$bm_dIR_sleeve, 100*r$turnover_annual))
}
res <- rbindlist(rows)
setorder(res, -is_port_t)
fwrite(res, file.path(OUT, "is_results.csv"))
saveRDS(CFG, file.path(OUT, "all_configs.rds"))

# ---- Winner selection rule (IS-ONLY, documented): among IS-robust configs
#      (both IS halves NW-t > 0), pick max IS canonical PORT_t. Robustness gate reduces
#      overfit-spike selection without any OOS peek. ----
robust <- res[is_both_half_pos == TRUE]
winner <- if (nrow(robust)) robust[which.max(is_port_t)] else res[which.max(is_port_t)]
cat("\n[run_is] IS-robust configs (both halves NW-t>0):", nrow(robust), "of", nrow(res), "\n")
cat(sprintf("[run_is] WINNER (IS-locked) = %s  IS port_t=%.3f  net_sr=%.3f  h1t=%.2f h2t=%.2f  bm_cor=%.2f bm_dIR=%+.4f\n",
    winner$id, winner$is_port_t, winner$is_net_sr, winner$is_h1_t, winner$is_h2_t, winner$bm_cor, winner$bm_dIR))
wcfg <- CFG[[which(sapply(CFG, function(c) c$id) == winner$id)]]
write_json(list(winner_id=winner$id, winner_config=wcfg, n_trials=length(CFG),
                selection_rule="IS-only: max canonical PORT_t among configs with both IS-half NW-t>0",
                is_locked_at=as.character(Sys.time())),
           file.path(OUT, "winner_config.json"), pretty=TRUE, auto_unbox=TRUE)
cat("[run_is] winner_config.json written. Stage B (finalize) computes OOS on winner (1 look).\n")
