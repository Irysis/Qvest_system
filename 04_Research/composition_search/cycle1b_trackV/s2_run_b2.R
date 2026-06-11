# =============================================================================
# s2_run_b2.R — B2_STR1715V2: base + 8 preregistered variants
#   Signal: inputs/b2_scores.parquet (fe_str1715v2.R verbatim, N_CAP=25)
#   Returns: me_panel forward 1M (driver_str1715v2_lo-identical source);
#            Track V interleaved construction (alignment fix documented).
# =============================================================================
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/composition_search/cycle1b_trackV/s2_common.R")

S2_raw <- as.data.table(read_parquet(file.path(INP, "b2_scores.parquet")))
S2_raw[, Date := as.Date(Date)]
S2_raw <- S2_raw[, .(Date, Ticker, score = Score, N)]
S2_raw <- merge(S2_raw, RETOK, by = c("Date", "Ticker"), all.x = TRUE)
S2_raw[is.na(ret_ok), ret_ok := FALSE]
S2_raw <- merge(S2_raw, ADV[, .(Date, Ticker, adv)], by = c("Date", "Ticker"), all.x = TRUE)
S2 <- S2_raw[Date >= START_DATE]
cat(sprintf("[B2] scores: %d rows, %d months (%s ~ %s)\n", nrow(S2), uniqueN(S2$Date), min(S2$Date), max(S2$Date)))

# ---- repro check (diagnostic, NOT in n_trials): driver-identical construction vs registry ----
rp <- tv_repro_driver(S2[, .(Date, Ticker, score, N)], RET_ME_K, n_cap = NULL)
repro <- list(
  target = list(source = "str1715v2_top25_longonly_result.json / module_performance.json",
                sharpe = 0.911, cagr_pct = 16.96, mdd_pct = 39.22, n_months = 256,
                cost_note = "driver cost = gross - oneway_TO x 15bps (NOT v2.4; half of v2.4 both-leg charge)"),
  measured_driver_replication = rp,
  note = "tv_repro_driver replicates the driver verbatim incl. its same-grid Return.portfolio construction (one-month weight/return mis-alignment, probe_env.R-proven). Gap vs target = signal/data-vintage drift only."
)
cat(sprintf("[B2] REPRO driver-mode: SR=%.4f CAGR=%.2f%% MDD=%.2f%% n=%d (target 0.911/16.96/39.22/256)\n",
            rp$sharpe, rp$cagr*100, rp$mdd*100, rp$n_months))

S_map <- list(default = S2)
runs <- list(
  B2_BASE              = list(),                       # native N col (=min(25, decile))
  B2_V1_topN15         = list(n_fixed = 15L),
  B2_V2_topN20         = list(n_fixed = 20L),
  B2_V3_rebal_quarterly= list(quarterly = TRUE),
  B2_V4_band_1p5N      = list(band = 38L),
  B2_V5_band_2N        = list(band = 50L),
  B2_V6_smooth3m       = list(smooth = TRUE),
  B2_V7_liq_4e8        = list(liq_floor = 4e8),
  B2_V8_combo_band2N_smooth3m = list(band = 50L, smooth = TRUE)
)
tv_execute("B2_STR1715V2", runs, S_map, RET_ME, repro = repro)
cat("[B2] DONE\n")
