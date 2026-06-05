#==============================================================================
# 55_kill_switch_inverse.R — Cycle 30 Kill switch + 재진입 + 인버스 비중 검증
#
# 도훈 mandate (2026-05-20):
#   "약세예측모델이 데일리로 +21d 약세 확률값 제시 → 포트폴리오 운용의
#    킬스위치(전액매도) + 재진입시점 + 인버스 매수 비중 추천 모델 활용 가능?"
#
# 3 applications to validate:
#   1. KILL SWITCH: p_bear > q95 (top 5%%) → STR_1715 → 100%% cash
#   2. RE-ENTRY: p_bear < q70 sustained N days → cash → STR_1715 복귀
#   3. INVERSE BET: p_bear > q95 sustained M days → KODEX 인버스 X%% bet
#
# Approach:
#   - Monthly snapshot of daily p_bear (latest day of each month-end)
#   - Apply switching rules
#   - Compare with STR_1715 only baseline + V1aV3 Hybrid
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

# ── (1) Load data ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_str := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

# Daily predictions
preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]
preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]
setorder(preds, Date)
preds[, ym := format(Date, "%Y-%m")]

# Monthly snapshot of daily p_bear (latest day of each month)
preds_me <- preds[, .(p_eom = p[which.max(Date)],
                       p_avg_5d = mean(tail(p, 5)),
                       p_max_5d = max(tail(p, 5)),
                       count_q95_5d = sum(tail(p, 5) >= quantile(p[Date < Date[which.max(Date)]], 0.95, na.rm = TRUE)),
                       count_q70_5d = sum(tail(p, 5) >= quantile(p[Date < Date[which.max(Date)]], 0.70, na.rm = TRUE))),
                   by = ym]
setorder(preds_me, ym)

# PIT expanding past quantiles per month
preds_me[, q70 := NA_real_]
preds_me[, q90 := NA_real_]
preds_me[, q95 := NA_real_]
for (i in seq_len(nrow(preds_me))) {
  past_p <- preds$p[preds$ym < preds_me$ym[i]]
  past_p <- past_p[!is.na(past_p)]
  if (length(past_p) >= 30) {
    preds_me[i, q70 := quantile(past_p, 0.70)]
    preds_me[i, q90 := quantile(past_p, 0.90)]
    preds_me[i, q95 := quantile(past_p, 0.95)]
  }
}

# Merge to baseline panel
preds_me[, realized_ym := shift(ym, -1, type = "lead")]  # decision at t-1 applied to t
panel <- merge(baseline,
               preds_me[, .(realized_ym,
                             p_eom_lag1 = p_eom,
                             p_avg_5d_lag1 = p_avg_5d,
                             p_max_5d_lag1 = p_max_5d,
                             count_q95_5d_lag1 = count_q95_5d,
                             count_q70_5d_lag1 = count_q70_5d,
                             q70_lag1 = q70, q90_lag1 = q90, q95_lag1 = q95)],
               by = "realized_ym", all.x = TRUE)
panel <- merge(panel, eom[, .(realized_ym, ret_kospi)],
               by = "realized_ym", all.x = TRUE)
setorder(panel, anchor_date)
cat(sprintf("[Panel] %d months / model data: %d months / overlap: %d\n",
            nrow(panel), sum(!is.na(panel$p_eom_lag1)),
            sum(!is.na(panel$p_eom_lag1) & !is.na(panel$ret_kospi))))

# Restrict to model-available period (2016+)
pfx <- panel[!is.na(p_eom_lag1) & !is.na(q95_lag1)]

# ── (2) Build 4 variants ──
# A: Baseline STR_1715
# B: KILL_SWITCH — p_eom_lag1 > q95 → cash, else STR_1715
# C: KILL_SWITCH + RE-ENTRY (sustained 5d count_q95 <= 0 → re-entry)
# D: KILL + INVERSE 30%% (sustained count_q95_5d >= 3 → 30%% inverse KOSPI200)
# E: KILL + INVERSE 50%%

cost <- 0.003  # 30bps

# Variant B: simple kill switch
pfx[, action_B := fifelse(p_eom_lag1 > q95_lag1, "CASH", "STR")]
pfx[, action_B_prev := shift(action_B, 1, fill = "STR")]
pfx[, change_B := action_B != action_B_prev]
pfx[, ret_B := fifelse(action_B == "STR", ret_str, 0)]
pfx[change_B == TRUE, ret_B := ret_B - cost]

# Variant C: kill switch + re-entry (cleaner — same as B since we re-eval each month)
# Same as B in monthly evaluation (re-entry is automatic next month when p falls)
# Make C stricter: re-entry only when count_q70_5d == 0 (sustained low)
pfx[, action_C := fifelse(p_eom_lag1 > q95_lag1, "CASH",
                           fifelse(shift(action_B, 1, fill = "STR") == "CASH" &
                                     count_q70_5d_lag1 > 0,
                                   "CASH", "STR"))]
pfx[, action_C_prev := shift(action_C, 1, fill = "STR")]
pfx[, change_C := action_C != action_C_prev]
pfx[, ret_C := fifelse(action_C == "STR", ret_str, 0)]
pfx[change_C == TRUE, ret_C := ret_C - cost]

# Variant D: kill + inverse 30%% if sustained
pfx[, action_D := fcase(
  count_q95_5d_lag1 >= 3, "INVERSE30",
  p_eom_lag1 > q95_lag1, "CASH",
  default = "STR")]
pfx[, action_D_prev := shift(action_D, 1, fill = "STR")]
pfx[, change_D := action_D != action_D_prev]
pfx[, ret_D := fcase(
  action_D == "STR", ret_str,
  action_D == "CASH", 0,
  action_D == "INVERSE30", 0.7 * ret_str + 0.3 * (-ret_kospi),
  default = ret_str)]
pfx[change_D == TRUE, ret_D := ret_D - cost]

# Variant E: kill + inverse 50%% if sustained
pfx[, action_E := fcase(
  count_q95_5d_lag1 >= 3, "INVERSE50",
  p_eom_lag1 > q95_lag1, "CASH",
  default = "STR")]
pfx[, action_E_prev := shift(action_E, 1, fill = "STR")]
pfx[, change_E := action_E != action_E_prev]
pfx[, ret_E := fcase(
  action_E == "STR", ret_str,
  action_E == "CASH", 0,
  action_E == "INVERSE50", 0.5 * ret_str + 0.5 * (-ret_kospi),
  default = ret_str)]
pfx[change_E == TRUE, ret_E := ret_E - cost]

# Variant F: full inverse 100%% if sustained (most aggressive)
pfx[, action_F := fcase(
  count_q95_5d_lag1 >= 3, "INVERSE100",
  p_eom_lag1 > q95_lag1, "CASH",
  default = "STR")]
pfx[, action_F_prev := shift(action_F, 1, fill = "STR")]
pfx[, change_F := action_F != action_F_prev]
pfx[, ret_F := fcase(
  action_F == "STR", ret_str,
  action_F == "CASH", 0,
  action_F == "INVERSE100", -ret_kospi,
  default = ret_str)]
pfx[change_F == TRUE, ret_F := ret_F - cost]

# ── (3) Action counts ──
cat(sprintf("\n━━━ Action distribution (110m eval) ━━━\n"))
for (v in LETTERS[2:6]) {
  acol <- paste0("action_", v)
  cat(sprintf("  Variant %s: %s\n", v,
              paste(sprintf("%s=%d", names(table(pfx[[acol]])),
                            as.integer(table(pfx[[acol]]))),
                    collapse = " / ")))
}

# ── (4) Metrics ──
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

m_base <- compute_m(pfx$ret_str, pfx$anchor_date)
cat(sprintf("\n━━━ 5 variants vs STR_1715 baseline ━━━\n"))
cat(sprintf("  A (Baseline STR_1715): SR %.4f / MDD %+.4f / CAGR %.4f\n",
            m_base["SR"], m_base["MDD"], m_base["CAGR"]))

labels <- c("B" = "Kill Switch (p>q95 → cash)",
            "C" = "Kill + Strict Re-entry (q70 sustained)",
            "D" = "Kill + Inverse 30%% (sustained q95)",
            "E" = "Kill + Inverse 50%% (sustained q95)",
            "F" = "Kill + Inverse 100%% (sustained q95)")
results <- list()
for (v in LETTERS[2:6]) {
  rcol <- paste0("ret_", v)
  mm <- compute_m(pfx[[rcol]], pfx$anchor_date)
  ht <- nw_t(pfx[[rcol]] - pfx$ret_str, 4)
  dSR <- mm["SR"] - m_base["SR"]
  dMDD <- mm["MDD"] - m_base["MDD"]
  dCAGR <- mm["CAGR"] - m_base["CAGR"]
  verdict <- fcase(
    dSR >= 0.05 & dMDD >= 0 & abs(ht) > 2.0, "✅ ADMIT",
    dSR >= 0 & dMDD >= 0, "△ NEUTRAL",
    default = "❌ REJECT"
  )
  results[[v]] <- list(label = labels[v], SR = mm["SR"], MDD = mm["MDD"],
                        CAGR = mm["CAGR"], dSR = dSR, dMDD = dMDD,
                        dCAGR = dCAGR, harvey_t = ht, verdict = verdict)
  cat(sprintf("  %-50s SR %.4f / MDD %+.4f / dSR %+.4f / dMDD %+.4f / t %+.2f / %s\n",
              labels[v], mm["SR"], mm["MDD"], dSR, dMDD, ht, verdict))
}

# ── (5) Per-active episode (kill switch events) ──
cat(sprintf("\n━━━ Kill switch episodes detail (Variant B) ━━━\n"))
ep_dt <- pfx[action_B == "CASH",
              .(ym = realized_ym,
                p_lag1 = round(p_eom_lag1, 3),
                q95_lag1 = round(q95_lag1, 3),
                str_ret = sprintf("%+.2f%%%%", 100 * ret_str),
                kospi_ret = sprintf("%+.2f%%%%", 100 * ret_kospi))]
cat(sprintf("Total CASH episodes: %d / %d months\n",
            nrow(ep_dt), nrow(pfx)))
print(ep_dt)

# ── (6) Save ──
out <- list(
  n_months = nrow(pfx),
  baseline = list(SR = unname(m_base["SR"]), MDD = unname(m_base["MDD"]),
                   CAGR = unname(m_base["CAGR"])),
  variants = lapply(results, function(r) list(
    label = unname(r$label),
    SR = unname(r$SR), MDD = unname(r$MDD), CAGR = unname(r$CAGR),
    dSR = unname(r$dSR), dMDD = unname(r$dMDD), dCAGR = unname(r$dCAGR),
    harvey_t = r$harvey_t, verdict = r$verdict)),
  kill_switch_episodes_n = nrow(ep_dt),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "kill_switch_inverse.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/kill_switch_inverse.json\n", EVAL_DIR))

# Chart NAV
nav_dt <- pfx[, .(anchor_date,
                   A_Baseline = cumprod(1 + ret_str),
                   B_Kill = cumprod(1 + ret_B),
                   C_Kill_RE = cumprod(1 + ret_C),
                   D_Inv30 = cumprod(1 + ret_D),
                   E_Inv50 = cumprod(1 + ret_E),
                   F_Inv100 = cumprod(1 + ret_F))]
nav_long <- melt(nav_dt, id.vars = "anchor_date", variable.name = "Variant", value.name = "NAV")
g <- ggplot(nav_long, aes(x = anchor_date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.7) + scale_y_log10() +
  labs(title = sprintf("Kill switch + Inverse variants (%d months)", nrow(pfx)),
       subtitle = sprintf("Best by SR: %s",
                          names(which.max(sapply(results, function(r) r$SR)))),
       x = NULL, y = "NAV (log)") +
  theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "33_kill_switch_inverse.png"),
       plot = g, width = 13, height = 6, dpi = 120)
cat(sprintf("[Chart 33] %s/33_kill_switch_inverse.png\n", CHART_DIR))

cat("\n[DONE]\n")
