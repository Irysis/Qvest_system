#==============================================================================
# 40_model_free_sanity.R — Cycle 10 Model-free sanity check
#
# Critical test: if naive alternatives match Hybrid performance, model is incidental.
#
# Variants (all on bear_trigger lag1):
#   N_A: 100%% KOSPI long
#   N_B: 100%% cash
#   N_C: 50/50 KOSPI/cash
#   N_D: 70/30 KOSPI/cash
#   N_E: -100%% inverse KOSPI (sanity)
#   M_PIT: V_S5 PIT regime (model-based)
#
# Verdict logic:
#   if max(naive_dSR) >= 0.95 × model_dSR → model INCIDENTAL
#   else → model has unique value
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

# ── (1) Load baseline ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

# ── (2) KOSPI200 ret ──
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(Date_eom = max(Date),
              close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

# ── (3) PIT-clean V_S5 model retval (from cycle 9) ──
feat <- as.data.table(read_parquet(
  file.path(WS, "outputs/01_data/feature_panel_v1_alt_enhanced.parquet")))
feat[, Date := as.Date(Date)]
feat <- feat[, .(Date, bbva_macro_composite)]
feat[, ym := format(Date, "%Y-%m")]
setorder(feat, Date)
me_macro <- feat[, .SD[which.max(Date)], by = ym]
setorder(me_macro, Date)

expanding_q <- function(x, dates, q = 0.5) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[dates < dates[i]]; past <- past[!is.na(past)]
    if (length(past) >= 12) out[i] <- as.numeric(quantile(past, q, na.rm = TRUE))
  }
  out
}
me_macro[, q33_past := expanding_q(bbva_macro_composite, Date, 0.33)]
me_macro[, q67_past := expanding_q(bbva_macro_composite, Date, 0.67)]
me_macro[, regime_PIT := fcase(
  is.na(bbva_macro_composite) | is.na(q33_past), NA_character_,
  bbva_macro_composite <= q33_past, "bull",
  bbva_macro_composite >= q67_past, "bear",
  default = "sideways"
)]

# ── (4) Build panel ──
m <- merge(eom, me_macro[, .(ym, regime_PIT)], by = "ym", all.x = TRUE)
setorder(m, ym)
m[, pos_M := fcase(regime_PIT == "bull", 1.0,
                    regime_PIT == "bear", 0.0,
                    default = 0.5)]
m[, turn_M := abs(pos_M - shift(pos_M, 1, fill = 0))]
m[, ret_M := pos_M * ret_kospi - turn_M * 0.0015]

# Naive variants
m[, pos_N_A := 1.0]; m[, pos_N_B := 0.0]; m[, pos_N_C := 0.5]
m[, pos_N_D := 0.7]; m[, pos_N_E := -1.0]
for (v in c("N_A", "N_B", "N_C", "N_D", "N_E")) {
  pcol <- paste0("pos_", v); tcol <- paste0("turn_", v); rcol <- paste0("ret_", v)
  m[, (tcol) := abs(get(pcol) - shift(get(pcol), 1, fill = 0))]
  m[, (rcol) := get(pcol) * ret_kospi - get(tcol) * 0.0015]
}

panel <- merge(baseline,
               m[, .(realized_ym, ret_M, ret_N_A, ret_N_B, ret_N_C, ret_N_D, ret_N_E,
                      ret_kospi)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)

# Bear trigger
panel[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel[, kospi_lvl := exp(kospi_log_cum)]
panel[, kospi_6m_max := frollapply(kospi_lvl, 6, max, align = "right")]
panel[, kospi_dd_6m := kospi_lvl / kospi_6m_max - 1]
panel[, bear_trigger := !is.na(kospi_dd_6m) & kospi_dd_6m <= -0.10]
panel[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]

# Pre-trigger fill (so substitute strategies have valid values)
for (v in c("M", "N_A", "N_B", "N_C", "N_D", "N_E")) {
  rcol <- paste0("ret_", v)
  panel[is.na(get(rcol)), (rcol) := 0]
}

# Build hybrid returns per variant
panel[, state := fifelse(bear_trigger_lag1, "BEAR", "BULL")]
panel[, state_change := state != shift(state, 1, fill = "BULL")]
for (v in c("M", "N_A", "N_B", "N_C", "N_D", "N_E")) {
  rcol_sub <- paste0("ret_", v); rcol_hyb <- paste0("hyb_", v)
  panel[, (rcol_hyb) := fifelse(bear_trigger_lag1, get(rcol_sub), ret_L5_V5)]
  panel[state_change == TRUE, (rcol_hyb) := get(rcol_hyb) - 0.0015]
}

# ── (5) Eval on 110m β_FX active ──
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

cat(sprintf("━━━ Baseline: STR_1715 admit (110m β_FX active) ━━━\n"))
cat(sprintf("  SR %.4f / MDD %+.4f / CAGR %.4f\n\n", m_base["SR"], m_base["MDD"], m_base["CAGR"]))

cat(sprintf("━━━ Hybrid variants (bear_trigger → substitute strategy) ━━━\n\n"))
labels <- c("M" = "Model (V_S5 PIT regime)",
            "N_A" = "Naive A: 100%% KOSPI long",
            "N_B" = "Naive B: 100%% cash",
            "N_C" = "Naive C: 50/50 KOSPI/cash",
            "N_D" = "Naive D: 70/30 KOSPI/cash",
            "N_E" = "Naive E: -100%% inverse KOSPI")
dt_res <- data.table()
for (v in c("M", "N_A", "N_B", "N_C", "N_D", "N_E")) {
  rcol <- paste0("hyb_", v)
  mm <- compute_m(pfx[[rcol]], pfx$anchor_date)
  diff_ret <- pfx[[rcol]] - pfx$ret_L5_V5
  ht <- nw_t(diff_ret, 4)
  dt_res <- rbind(dt_res, data.table(
    variant = labels[v],
    SR = round(mm["SR"], 4),
    MDD = round(mm["MDD"], 4),
    CAGR = round(mm["CAGR"], 4),
    dSR = round(mm["SR"] - m_base["SR"], 4),
    dMDD = round(mm["MDD"] - m_base["MDD"], 4),
    dCAGR = round(mm["CAGR"] - m_base["CAGR"], 4),
    harvey_t = round(ht, 3)
  ))
}
print(dt_res)

# ── (6) Model vs best naive ──
model_dSR <- dt_res[variant == labels["M"], dSR]
naive_dSR_max <- max(dt_res[variant != labels["M"], dSR], na.rm = TRUE)
best_naive <- dt_res[variant != labels["M"]][which.max(dSR)]
cat(sprintf("\n━━━ Model vs best naive ━━━\n"))
cat(sprintf("  Model (V_S5) dSR  : %+.4f\n", model_dSR))
cat(sprintf("  Best naive   dSR  : %+.4f (%s)\n", naive_dSR_max, best_naive$variant))
cat(sprintf("  Gap (model - naive): %+.4f\n", model_dSR - naive_dSR_max))

# Verdict
gap_pct <- (model_dSR - naive_dSR_max) / abs(model_dSR)
if (model_dSR <= naive_dSR_max * 1.05) {
  if (model_dSR <= naive_dSR_max * 0.95) {
    verdict <- "❌ MODEL INFERIOR — naive 만으로 충분, model 불필요"
  } else {
    verdict <- "⚠️ MODEL INCIDENTAL — naive와 동등 (±5%%), model 추가 가치 약함"
  }
} else if (model_dSR <= naive_dSR_max * 1.20) {
  verdict <- "△ MODEL MARGINAL — naive 대비 약간 우위 (5-20%%)"
} else {
  verdict <- "✅ MODEL ESSENTIAL — naive 대비 명확한 우위 (>20%%)"
}
cat(sprintf("\n[VERDICT] %s\n", verdict))

# ── (7) Save ──
out <- list(
  baseline = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                   CAGR = unname(m_base["CAGR"])),
  variant_metrics = dt_res,
  model_dSR = model_dSR,
  best_naive_variant = best_naive$variant,
  best_naive_dSR = naive_dSR_max,
  model_minus_naive = model_dSR - naive_dSR_max,
  verdict = verdict,
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "model_free_sanity.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/model_free_sanity.json\n", EVAL_DIR))

# Chart: NAV comparison
nav_dt <- pfx[, .(anchor_date, STR_1715 = cumprod(1 + ret_L5_V5),
                   M = cumprod(1 + hyb_M),
                   N_A = cumprod(1 + hyb_N_A),
                   N_B = cumprod(1 + hyb_N_B),
                   N_C = cumprod(1 + hyb_N_C),
                   N_D = cumprod(1 + hyb_N_D),
                   N_E = cumprod(1 + hyb_N_E))]
nav_long <- melt(nav_dt, id.vars = "anchor_date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = anchor_date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  labs(title = "Model-free sanity: bear_trigger substitute strategy NAV",
       subtitle = verdict, x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "20_model_free_sanity.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 20] %s/20_model_free_sanity.png\n", CHART_DIR))

cat("\n[DONE]\n")
