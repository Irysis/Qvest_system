# =============================================================================
# s2_run_b4.R — B4_C19_LO25: base + 8 preregistered variants
#   Signal: inputs/b4_scores.parquet (C19_Composite_Earnings Z_Score_Aligned,
#           K200uKQ150 + ADV>=2e8 universe — driver_lo_screen-identical).
#   Returns: me_panel forward 1M; Track V interleaved construction.
#   Honesty: base PORT_t ~ 0 (no alpha vs K200) — defensive-profile base only.
# =============================================================================
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/composition_search/cycle1b_trackV/s2_common.R")

S4_raw <- as.data.table(read_parquet(file.path(INP, "b4_scores.parquet")))
S4_raw[, Date := as.Date(Date)]
S4_raw <- S4_raw[, .(Date, Ticker, score = Score)]
S4_raw <- merge(S4_raw, RETOK, by = c("Date", "Ticker"), all.x = TRUE)
S4_raw[is.na(ret_ok), ret_ok := FALSE]
S4_raw <- merge(S4_raw, ADV[, .(Date, Ticker, adv)], by = c("Date", "Ticker"), all.x = TRUE)
S4 <- S4_raw[Date >= START_DATE]
cat(sprintf("[B4] scores: %d rows, %d months\n", nrow(S4), uniqueN(S4$Date)))

# ---- repro check (diagnostic, NOT in n_trials): driver-identical construction ----
rp <- tv_repro_driver(S4[, .(Date, Ticker, score)], RET_ME_K, n_cap = 25L)
repro <- list(
  target = list(source = "lo_screen/C19_Composite_Earnings.json / module_performance.json",
                sharpe = 0.865, cagr_pct = 12.28, mdd_pct = 20.97, n_months = 256,
                cost_note = "driver cost = gross - oneway_TO x 15bps (NOT v2.4)"),
  measured_driver_replication = rp,
  note = "tv_repro_driver replicates driver_lo_screen verbatim incl. same-grid construction quirk. Gap vs target = signal/data-vintage drift only."
)
cat(sprintf("[B4] REPRO driver-mode: SR=%.4f CAGR=%.2f%% MDD=%.2f%% n=%d (target 0.865/12.28/20.97/256)\n",
            rp$sharpe, rp$cagr*100, rp$mdd*100, rp$n_months))

S_map <- list(default = S4)
runs <- list(
  B4_BASE              = list(n_fixed = 25L),
  B4_V1_topN15         = list(n_fixed = 15L),
  B4_V2_topN20         = list(n_fixed = 20L),
  B4_V3_rebal_quarterly= list(n_fixed = 25L, quarterly = TRUE),
  B4_V4_band_1p5N      = list(n_fixed = 25L, band = 38L),
  B4_V5_band_2N        = list(n_fixed = 25L, band = 50L),
  B4_V6_smooth3m       = list(n_fixed = 25L, smooth = TRUE),
  B4_V7_liq_4e8        = list(n_fixed = 25L, liq_floor = 4e8),
  B4_V8_combo_band2N_smooth3m = list(n_fixed = 25L, band = 50L, smooth = TRUE)
)
tv_execute("B4_C19_LO25", runs, S_map, RET_ME, repro = repro)
cat("[B4] DONE\n")
