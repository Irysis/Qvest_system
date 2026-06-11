# =============================================================================
# s2_run_b1.R — B1_STR1715_VANILLA: base + 9 preregistered variants
#   Signal: factor_panel_7f.parquet score_eff (b1-verified reconstruction path)
#   Returns: panel Ret_1m (forward calendar month), w_idx=month_end(t),
#            r_idx=month_end(t+1) — b1_step3-identical interleaved construction.
#   Universe: production panel rows (NO liquidity filter in base; liq = variation axis)
# =============================================================================
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/composition_search/cycle1b_trackV/s2_common.R")

pan <- as.data.table(read_parquet(file.path(PROJ, "04_Research/pg2_forensics/intermediate/factor_panel_7f.parquet")))
pan[, Date := as.Date(Date)]
last_d <- max(pan$Date)

# sig grid = calendar month-end of score label month; returns realized at month_end(t+1)
udates <- sort(unique(pan$Date))
umap <- data.table(Date = udates,
                   w_idx = as.Date(vapply(udates, function(d) as.character(month_end_cal(as.Date(d))), character(1))),
                   r_idx = as.Date(vapply(udates, function(d) as.character(month_end_cal(seq(as.Date(d), by = "1 month", length.out = 2)[2])), character(1))))
pan <- merge(pan, umap, by = "Date")

# adv by calendar month (trading month-end AvgTV20 of same month) — for liq variants
ADV[, ym := format(Date, "%Y-%m")]
adv_ym <- ADV[, .(ym, Ticker, adv)]

S1_all <- pan[!is.na(score_eff) & Date < last_d,
              .(Date = w_idx, Ticker, score = score_eff, ret_ok = is.finite(Ret_1m))]
S1_all[, ym := format(Date, "%Y-%m")]
S1_all <- merge(S1_all, adv_ym, by = c("ym", "Ticker"), all.x = TRUE)
S1_all[, ym := NULL]
cat(sprintf("[B1] ticker-adv match share: %.3f\n", S1_all[, mean(!is.na(adv))]))

RET_B1 <- pan[, .(Date = w_idx, Ticker, ret_fwd = Ret_1m, r_idx)]

S1 <- S1_all[Date >= START_DATE]
S_map <- list(default = S1)

# ---- repro check (diagnostic, NOT in n_trials): full-from-2004 gross top-20 vs b1 1.044 ----
rfull <- tv_run_variant("B1_REPRO_2004_GROSS", S1_all, RET_B1, BMM, list(n_fixed = 20L))
repro <- list(
  target = list(source = "b1_family_attribution blend_65_35 gross", sharpe_gross = 1.044, mdd = 0.374, n_months = 267),
  measured = list(sharpe_gross_full = rfull$windows$FULL$sr_gross,
                  mdd_net = rfull$windows$FULL$mdd_net, n_months = rfull$windows$FULL$n_months),
  note = "b1 gross had no cost; compare sr_gross. Window 2004+ both. MDD here is net-of-v2.4-cost (not directly comparable)."
)
cat(sprintf("[B1] REPRO gross SR (2004+): %.4f vs b1 1.044\n", rfull$windows$FULL$sr_gross))

runs <- list(
  B1_BASE              = list(n_fixed = 20L),
  B1_V1_topN15         = list(n_fixed = 15L),
  B1_V2_topN25         = list(n_fixed = 25L),
  B1_V3_rebal_quarterly= list(n_fixed = 20L, quarterly = TRUE),
  B1_V4_band_1p5N      = list(n_fixed = 20L, band = 30L),
  B1_V5_band_2N        = list(n_fixed = 20L, band = 40L),
  B1_V6_smooth3m       = list(n_fixed = 20L, smooth = TRUE),
  B1_V7_liq_2e8        = list(n_fixed = 20L, liq_floor = 2e8),
  B1_V8_liq_4e8        = list(n_fixed = 20L, liq_floor = 4e8),
  B1_V9_combo_band2N_smooth3m = list(n_fixed = 20L, band = 40L, smooth = TRUE)
)
tv_execute("B1_STR1715_VANILLA", runs, S_map, RET_B1, repro = repro)
cat("[B1] DONE\n")
