# =============================================================================
# s2_run_b3.R — B3_VALMOM_AMP: base + 9 preregistered variants
#   Signal: inputs/b3_scores.parquet (fe_valmom.R verbatim — AMP2013 z(BM)+z(12-1mom),
#           native decile N(t)). Highest-turnover base — H1 prime testbed.
#   Returns: me_panel forward 1M; Track V interleaved construction.
#   NOTE: original registry measurement = run_monthly_simulation DAILY NAV engine
#   (flat-cost era). No exact monthly replication possible — ballpark check vs
#   hurdle proxy (0.825) + registry (0.887) documented.
# =============================================================================
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/composition_search/cycle1b_trackV/s2_common.R")

S3_raw <- as.data.table(read_parquet(file.path(INP, "b3_scores.parquet")))
S3_raw[, Date := as.Date(Date)]
S3_raw <- S3_raw[, .(Date, Ticker, score = Score, N)]
S3_raw <- merge(S3_raw, RETOK, by = c("Date", "Ticker"), all.x = TRUE)
S3_raw[is.na(ret_ok), ret_ok := FALSE]
S3_raw <- merge(S3_raw, ADV[, .(Date, Ticker, adv)], by = c("Date", "Ticker"), all.x = TRUE)
S3 <- S3_raw[Date >= START_DATE]
cat(sprintf("[B3] scores: %d rows, %d months | native N range %d~%d\n",
            nrow(S3), uniqueN(S3$Date), min(S3$N), max(S3$N)))

# ---- repro check (diagnostic, NOT in n_trials): driver-style monthly decile EW ----
rp <- tv_repro_driver(S3[, .(Date, Ticker, score, N)], RET_ME_K, n_cap = NULL)
repro <- list(
  target = list(source = "hurdle_result.json (proxy) / module_performance.json (daily sim, flat-era)",
                hurdle_sharpe_proxy = 0.825, registry_full_sharpe = 0.887,
                hurdle_mdd_pct = 60.4, hurdle_to_oneway_pct = 213.7),
  measured_driver_replication = rp,
  note = "Original engine = run_monthly_simulation DAILY NAV (flat cost). This check is a monthly Return.portfolio approximation - ballpark only, engine difference documented."
)
cat(sprintf("[B3] REPRO driver-mode: SR=%.4f CAGR=%.2f%% MDD=%.2f%% n=%d (ballpark vs 0.825/0.887)\n",
            rp$sharpe, rp$cagr*100, rp$mdd*100, rp$n_months))

S_map <- list(default = S3)
runs <- list(
  B3_BASE              = list(),                       # native decile N(t)
  B3_V1_topN15         = list(n_fixed = 15L),
  B3_V2_topN20         = list(n_fixed = 20L),
  B3_V3_topN25         = list(n_fixed = 25L),          # production-compliance spec
  B3_V4_rebal_quarterly= list(quarterly = TRUE),       # H3: preregistered expected-negative
  B3_V5_band_1p5N      = list(band = "mult:1.5"),
  B3_V6_band_2N        = list(band = "mult:2"),
  B3_V7_smooth3m       = list(smooth = TRUE),
  B3_V8_liq_4e8        = list(liq_floor = 4e8),
  B3_V9_combo_band2N_smooth3m = list(band = "mult:2", smooth = TRUE)
)
tv_execute("B3_VALMOM_AMP", runs, S_map, RET_ME, repro = repro)
cat("[B3] DONE\n")
