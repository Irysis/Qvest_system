#==============================================================================
# 39_pit_audit_controls.R — Cycle 9 PIT audit + Control tests
#
# CRITICAL CONCERN:
#   regime label in preds_dynamic uses `train_macro` = first 2000 OOS rows
#   → q33/q67 quantile calibration uses data from 2016-2024
#   → Applied to dates 2016-2024 = partial LOOK-AHEAD
#   → 2024+ strictly PIT, 2017-2024 look-ahead
#
# Test plan:
#   (A) PIT-clean regime reconstruction (expanding past quantile)
#   (B) Hybrid_PIT vs baseline (key test)
#   (C) Random Bernoulli trigger control (1000 perms)
#   (D) Shuffled regime control
#   (E) Pre/post 2022 split (drift)
#
# If Hybrid_PIT loses, look-ahead artifact. If retains, robust.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load baseline + KOSPI200 + features ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(Date_eom = max(Date),
              close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

# Load bbva_macro_composite from feature panel
feat <- as.data.table(read_parquet(
  file.path(WS, "outputs/01_data/feature_panel_v1_alt_enhanced.parquet")))
feat[, Date := as.Date(Date)]
feat <- feat[, .(Date, bbva_macro_composite)]
setorder(feat, Date)
feat[, ym := format(Date, "%Y-%m")]
me_macro <- feat[, .SD[which.max(Date)], by = ym]

# ── (2) PIT-clean expanding quantile regime ──
# At each month-end t, compute q33/q67 of past bbva_macro_composite (strictly < t)
expanding_q <- function(x, dates, q = 0.5) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[dates < dates[i]]; past <- past[!is.na(past)]
    if (length(past) >= 12) out[i] <- as.numeric(quantile(past, q, na.rm = TRUE))
  }
  out
}
setorder(me_macro, Date)
me_macro[, q33_past := expanding_q(bbva_macro_composite, Date, 0.33)]
me_macro[, q67_past := expanding_q(bbva_macro_composite, Date, 0.67)]
me_macro[, regime_PIT := fcase(
  is.na(bbva_macro_composite) | is.na(q33_past), NA_character_,
  bbva_macro_composite <= q33_past, "bull",
  bbva_macro_composite >= q67_past, "bear",
  default = "sideways"
)]

# Load original regime from preds (look-ahead calibrated)
preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]
preds[, p := p_M2_regime]; preds <- preds[!is.na(p)]
preds[, ym := format(Date, "%Y-%m")]
me_preds <- preds[, .SD[which.max(Date)], by = ym]
setorder(me_preds, Date)

# Compare regime_orig vs regime_PIT
me_compare <- merge(me_preds[, .(ym, regime_orig = regime)],
                    me_macro[, .(ym, regime_PIT)], by = "ym", all = TRUE)
me_compare[, agree := regime_orig == regime_PIT]
cat(sprintf("━━━ Regime classification: orig (look-ahead) vs PIT (expanding) ━━━\n"))
cat(sprintf("  Total months: %d\n", nrow(me_compare)))
cat(sprintf("  Both non-NA: %d\n",
            sum(!is.na(me_compare$regime_orig) & !is.na(me_compare$regime_PIT))))
cat(sprintf("  Agreement rate: %.0f%%%%\n",
            100 * mean(me_compare$agree, na.rm = TRUE)))
cat(sprintf("  Confusion table (orig × PIT):\n"))
print(table(orig = me_compare$regime_orig, PIT = me_compare$regime_PIT, useNA = "ifany"))

# ── (3) Build hybrid variants: orig vs PIT regime ──
# Common: bear_trigger (KOSPI 6m rolling DD ≤ -10%%)
s5 <- merge(eom, me_preds[, .(ym, regime_orig = regime)], by = "ym", all.x = TRUE)
s5 <- merge(s5, me_macro[, .(ym, regime_PIT)], by = "ym", all.x = TRUE)
setorder(s5, ym)
s5[, pos_S5_orig := fcase(regime_orig == "bull", 1.0,
                           regime_orig == "bear", 0.0,
                           default = 0.5)]
s5[, pos_S5_PIT := fcase(regime_PIT == "bull", 1.0,
                          regime_PIT == "bear", 0.0,
                          default = 0.5)]
s5[, turn_orig := abs(pos_S5_orig - shift(pos_S5_orig, 1, fill = 0))]
s5[, turn_PIT := abs(pos_S5_PIT - shift(pos_S5_PIT, 1, fill = 0))]
s5[, ret_S5_orig := pos_S5_orig * ret_kospi - turn_orig * 0.0015]
s5[, ret_S5_PIT := pos_S5_PIT * ret_kospi - turn_PIT * 0.0015]

panel <- merge(baseline,
               s5[, .(realized_ym, ret_S5_orig, ret_S5_PIT, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)

# Bear trigger
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_6m_max := frollapply(kospi_lvl, 6, max, align = "right")]
panel[, kospi_dd_6m := kospi_lvl / kospi_6m_max - 1]
panel[, bear_trigger := !is.na(kospi_dd_6m) & kospi_dd_6m <= -0.10]
panel[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]

panel[is.na(ret_S5_orig), ret_S5_orig := 0]
panel[is.na(ret_S5_PIT), ret_S5_PIT := 0]

panel[, state := fifelse(bear_trigger_lag1, "BEAR", "BULL")]
panel[, state_change := state != shift(state, 1, fill = "BULL")]
panel[, ret_hybrid_orig := fifelse(bear_trigger_lag1, ret_S5_orig, ret_L5_V5)]
panel[, ret_hybrid_PIT := fifelse(bear_trigger_lag1, ret_S5_PIT, ret_L5_V5)]
panel[state_change == TRUE, ret_hybrid_orig := ret_hybrid_orig - 0.0015]
panel[state_change == TRUE, ret_hybrid_PIT := ret_hybrid_PIT - 0.0015]

# ── (4) Key test: Hybrid_PIT vs baseline ──
pfx <- panel[anchor_date >= as.Date("2017-03-01")]
compute_m <- function(ret_vec, dates) {
  ok <- !is.na(ret_vec) & is.finite(ret_vec)
  r <- ret_vec[ok]; d <- dates[ok]
  if (length(r) < 12) return(c(SR = NA, MDD = NA, CAGR = NA))
  xret <- xts::xts(r, order.by = d)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  c(SR = as.numeric(ann[3, 1]),
    MDD = -as.numeric(maxDrawdown(xret)),
    CAGR = as.numeric(ann[1, 1]))
}
nw_t <- function(x, lag = 4) {
  n <- length(x); xbar <- mean(x); resid <- x - xbar
  if (n < 10) return(NA)
  S <- sum(resid^2) / n
  for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    S <- S + 2 * w * sum(resid[(l + 1):n] * resid[1:(n - l)]) / n
  }
  xbar / sqrt(S / n)
}

m_base <- compute_m(pfx$ret_L5_V5, pfx$anchor_date)
m_orig <- compute_m(pfx$ret_hybrid_orig, pfx$anchor_date)
m_pit <- compute_m(pfx$ret_hybrid_PIT, pfx$anchor_date)

cat(sprintf("\n━━━ (A) PIT-clean Hybrid vs original Hybrid vs baseline ━━━\n"))
cat(sprintf("  STR_1715 baseline : SR %.4f / MDD %+.4f / CAGR %.4f\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))
cat(sprintf("  Hybrid (orig)     : SR %.4f / MDD %+.4f / CAGR %.4f  (ΔSR %+.4f / ΔMDD %+.4f)\n",
            m_orig["SR"], m_orig["MDD"], m_orig["CAGR"],
            m_orig["SR"] - m_base["SR"], m_orig["MDD"] - m_base["MDD"]))
cat(sprintf("  Hybrid (PIT)      : SR %.4f / MDD %+.4f / CAGR %.4f  (ΔSR %+.4f / ΔMDD %+.4f)\n",
            m_pit["SR"], m_pit["MDD"], m_pit["CAGR"],
            m_pit["SR"] - m_base["SR"], m_pit["MDD"] - m_base["MDD"]))

pit_dSR <- m_pit["SR"] - m_base["SR"]
pit_dMDD <- m_pit["MDD"] - m_base["MDD"]
diff_pit <- pfx$ret_hybrid_PIT - pfx$ret_L5_V5
ht_pit <- nw_t(diff_pit, 4)
cat(sprintf("  Harvey-t (PIT): %+.3f\n", ht_pit))

pit_verdict <- fcase(
  pit_dSR >= 0.05 & pit_dMDD >= 0 & abs(ht_pit) > 2.0, "✅ ADMIT_STRICT (PIT robust)",
  pit_dSR >= 0.05 & pit_dMDD >= 0, "⚠️ ADMIT_WEAK (PIT robust but t low)",
  pit_dSR >= 0, "△ NEUTRAL (PIT reduced)",
  default = "❌ REJECT (look-ahead artifact)"
)
cat(sprintf("\n  PIT VERDICT: %s\n", pit_verdict))

# ── (5) Random Bernoulli trigger control (1000 perms) ──
cat(sprintf("\n━━━ (C) Random Bernoulli trigger control (1000 perms) ━━━\n"))
p_trigger <- mean(pfx$bear_trigger_lag1)
cat(sprintf("  Actual trigger ratio: %.3f (%d / %d)\n",
            p_trigger, sum(pfx$bear_trigger_lag1), nrow(pfx)))
set.seed(42)
B <- 1000
random_dSR <- numeric(B)
for (b in seq_len(B)) {
  rand_trigger <- as.logical(rbinom(nrow(pfx), 1, p_trigger))
  rand_state <- fifelse(rand_trigger, "BEAR", "BULL")
  rand_state_change <- rand_state != shift(rand_state, 1, fill = "BULL")
  ret_rand <- fifelse(rand_trigger, pfx$ret_S5_PIT, pfx$ret_L5_V5)
  ret_rand[rand_state_change] <- ret_rand[rand_state_change] - 0.0015
  random_dSR[b] <- compute_m(ret_rand, pfx$anchor_date)["SR"] - m_base["SR"]
}
random_dSR <- random_dSR[!is.na(random_dSR)]
cat(sprintf("  Random dSR: median %+.4f / mean %+.4f / 95%% CI [%+.4f, %+.4f]\n",
            median(random_dSR), mean(random_dSR),
            quantile(random_dSR, 0.025), quantile(random_dSR, 0.975)))
cat(sprintf("  Actual (PIT) dSR: %+.4f\n", pit_dSR))
pctile <- mean(random_dSR < pit_dSR)
cat(sprintf("  Percentile of actual vs random: %.1f%%%% (>95%% → trigger signal real)\n",
            100 * pctile))

# ── (6) Shuffled regime control ──
cat(sprintf("\n━━━ (D) Shuffled regime control (1000 perms) ━━━\n"))
set.seed(43)
shuffle_dSR <- numeric(B)
for (b in seq_len(B)) {
  reg_perm <- sample(s5$regime_PIT, nrow(s5))
  pos_perm <- fcase(reg_perm == "bull", 1.0,
                    reg_perm == "bear", 0.0,
                    default = 0.5)
  turn_perm <- abs(pos_perm - shift(pos_perm, 1, fill = 0))
  ret_S5_perm <- pos_perm * s5$ret_kospi - turn_perm * 0.0015

  s5_perm <- s5[, .(realized_ym, ret_S5_perm)]
  panel_perm <- merge(panel[, .(realized_ym, anchor_date, ret_L5_V5, bear_trigger_lag1, state_change)],
                       s5_perm, by = "realized_ym", all.x = TRUE)
  setorder(panel_perm, anchor_date)
  panel_perm[is.na(ret_S5_perm), ret_S5_perm := 0]
  panel_perm[, ret_hyb_perm := fifelse(bear_trigger_lag1, ret_S5_perm, ret_L5_V5)]
  panel_perm[state_change == TRUE, ret_hyb_perm := ret_hyb_perm - 0.0015]
  pfx_perm <- panel_perm[anchor_date >= as.Date("2017-03-01")]
  shuffle_dSR[b] <- compute_m(pfx_perm$ret_hyb_perm, pfx_perm$anchor_date)["SR"] - m_base["SR"]
}
shuffle_dSR <- shuffle_dSR[!is.na(shuffle_dSR)]
cat(sprintf("  Shuffled dSR: median %+.4f / 95%% CI [%+.4f, %+.4f]\n",
            median(shuffle_dSR),
            quantile(shuffle_dSR, 0.025), quantile(shuffle_dSR, 0.975)))
cat(sprintf("  Actual (PIT) dSR: %+.4f\n", pit_dSR))
pctile_s <- mean(shuffle_dSR < pit_dSR)
cat(sprintf("  Percentile of actual vs shuffled: %.1f%%%% (>95%% → regime info real)\n",
            100 * pctile_s))

# ── (7) Pre/post 2022 split ──
cat(sprintf("\n━━━ (E) Pre/post 2022 split ━━━\n"))
pre <- pfx[anchor_date < as.Date("2022-01-01")]
post <- pfx[anchor_date >= as.Date("2022-01-01")]
m_pre_base <- compute_m(pre$ret_L5_V5, pre$anchor_date)
m_pre_hyb <- compute_m(pre$ret_hybrid_PIT, pre$anchor_date)
m_post_base <- compute_m(post$ret_L5_V5, post$anchor_date)
m_post_hyb <- compute_m(post$ret_hybrid_PIT, post$anchor_date)
cat(sprintf("  Pre 2022 (%d m):  Baseline SR %.3f / Hybrid_PIT SR %.3f / ΔSR %+.3f\n",
            nrow(pre), m_pre_base["SR"], m_pre_hyb["SR"], m_pre_hyb["SR"] - m_pre_base["SR"]))
cat(sprintf("  Post 2022 (%d m): Baseline SR %.3f / Hybrid_PIT SR %.3f / ΔSR %+.3f\n",
            nrow(post), m_post_base["SR"], m_post_hyb["SR"], m_post_hyb["SR"] - m_post_base["SR"]))

# ── (8) Final verdict ──
cat(sprintf("\n━━━ Cycle 9 Final Verdict ━━━\n"))
verdict_ok <- (pit_dSR >= 0.05 && pit_dMDD >= 0 && abs(ht_pit) > 2.0 &&
                pctile > 0.95 && pctile_s > 0.95)
cat(sprintf("  PIT robust: %s\n", ifelse(pit_dSR >= 0.05 && pit_dMDD >= 0, "✅", "❌")))
cat(sprintf("  Harvey-t > 2.0: %s\n", ifelse(abs(ht_pit) > 2.0, "✅", "⚠️")))
cat(sprintf("  Trigger signal real (>95%%ile): %s\n", ifelse(pctile > 0.95, "✅", "❌")))
cat(sprintf("  Regime info real (>95%%ile): %s\n", ifelse(pctile_s > 0.95, "✅", "❌")))
cat(sprintf("\n[VERDICT] %s\n",
            ifelse(verdict_ok, "✅ ALL PASS → proceed to Codex Critic Round + AX-008 admit cycle",
                   "⚠️ PARTIAL — investigate before admit")))

# ── (9) Save ──
out <- list(
  pit_verdict = pit_verdict,
  pit_dSR = unname(pit_dSR),
  pit_dMDD = unname(pit_dMDD),
  pit_harvey_t = ht_pit,
  random_trigger_pctile = pctile,
  shuffled_regime_pctile = pctile_s,
  pre_2022 = list(n = nrow(pre), dSR = unname(m_pre_hyb["SR"] - m_pre_base["SR"])),
  post_2022 = list(n = nrow(post), dSR = unname(m_post_hyb["SR"] - m_post_base["SR"])),
  regime_agreement_rate = mean(me_compare$agree, na.rm = TRUE),
  final_verdict = ifelse(verdict_ok, "PASS", "PARTIAL"),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "pit_audit_controls.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/pit_audit_controls.json\n", EVAL_DIR))

cat("\n[DONE]\n")
