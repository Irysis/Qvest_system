#==============================================================================
# 28_overlay_correlation_matrix.R — 4-overlay correlation matrix
#
# 검증 #2: m4 / β_AR / β_R05 / β_FX 4-overlay 상관성 진단
#
# Admit 차단 기준 (Sequential Admission v6.1 Charter §10):
#   - Pearson |ρ| > 0.7 = redundancy 위험
#   - TDC (Tail Dependence Coefficient at bear tail q20) > 0.5 = admit BLOCK
#
# β_FX 정의 (PIT, expanding past-only quantile):
#   p_bear ≤ q70_past  → β_FX = 1.0   (NORMAL)
#   p_bear in (q70,q90] → β_FX = 0.7  (CAUTION)
#   p_bear > q90_past  → β_FX = 0.5   (ALERT)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load m4 scalar (weight_str1715 = m4_scalar from M4 BOCPD overlay) ──
m4_path <- file.path(PROJECT_ROOT,
  "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv")
m4 <- fread(m4_path)
m4[, Date := as.Date(Date)]
m4[, ym := format(Date, "%Y-%m")]
setorder(m4, Date)
m4[, m4_scalar := weight_str1715]
cat(sprintf("[m4] n=%d / range %s ~ %s\n",
            nrow(m4), as.character(min(m4$Date)), as.character(max(m4$Date))))
cat(sprintf("[m4] scalar distribution:\n"))
print(round(table(round(m4$m4_scalar, 2)) / nrow(m4) * 100, 1))

# ── (2) Load β_AR (beta_threshold from AR overlay) ──
beta_path <- file.path(PROJECT_ROOT,
  "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv")
ar <- fread(beta_path)
ar[, Date := as.Date(Date)]
ar[, ym := format(Date, "%Y-%m")]
setorder(ar, Date)
ar[, beta_AR := beta_threshold]
cat(sprintf("\n[β_AR] n=%d / range %s ~ %s\n",
            nrow(ar), as.character(min(ar$Date)), as.character(max(ar$Date))))
cat(sprintf("[β_AR] distribution:\n"))
print(round(table(round(ar$beta_AR, 2)) / nrow(ar) * 100, 1))

# ── (3) Compute β_R05 (V5 regime × R05 interaction — current admit variant) ──
# Use production-frozen panel (alpha_scores_r05_panel.parquet has score_eff + R05_Z + regime)
panel_prod <- as.data.table(read_parquet(
  file.path(PROD_DIR, "02_holdings_universe/alpha_scores_r05_panel.parquet")))
m_valid <- panel_prod[!is.na(score_eff)]
setorder(m_valid, Date, -score_eff)
top20 <- m_valid[, head(.SD, 20), by = Date]

p_r05 <- top20[, .(R05_z_avg = mean(R05_Tail_Risk_Z, na.rm = TRUE),
                    regime = regime_state[1]), by = Date]
setorder(p_r05, Date)

expanding_q <- function(x, dates, q = 0.2) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[dates < dates[i]]; past <- past[!is.na(past)]
    if (length(past) >= 12) out[i] <- as.numeric(quantile(past, q, na.rm = TRUE))
  }
  out
}
p_r05[, q20 := expanding_q(R05_z_avg, Date, q = 0.20)]

# V5 admit
p_r05[, beta_R05 := fcase(
  is.na(q20), 1.0,
  regime == "CRISIS" & R05_z_avg < q20, 0.3,
  regime == "CRISIS", 0.5,
  regime == "CAUTION" & R05_z_avg < q20, 0.5,
  regime == "CAUTION", 0.7,
  regime %in% c("BULL", "NORMAL") & R05_z_avg < q20, 0.85,
  default = 1.0
)]
p_r05[, ym := format(Date, "%Y-%m")]
cat(sprintf("\n[β_R05 V5] n=%d / range %s ~ %s\n",
            nrow(p_r05), as.character(min(p_r05$Date)), as.character(max(p_r05$Date))))
cat(sprintf("[β_R05] distribution:\n"))
print(round(table(round(p_r05$beta_R05, 2)) / nrow(p_r05) * 100, 1))

# ── (4) β_FX historical (from p_bear month-end + expanding quantiles) ──
preds <- as.data.table(read_parquet(
  file.path(WS, "outputs/03_models/dynamic_ensemble/predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]
preds[, p := p_M2_regime]
preds <- preds[!is.na(p)]
preds[, ym := format(Date, "%Y-%m")]
me <- preds[, .SD[which.max(Date)], by = ym]
setorder(me, Date)
me[, q70_past := expanding_q(p, Date, q = 0.70)]
me[, q90_past := expanding_q(p, Date, q = 0.90)]
me[, beta_FX := fcase(
  is.na(q70_past) | is.na(q90_past), 1.0,
  p > q90_past, 0.5,
  p > q70_past, 0.7,
  default = 1.0
)]
cat(sprintf("\n[β_FX] n=%d / range %s ~ %s\n",
            nrow(me), as.character(min(me$Date)), as.character(max(me$Date))))
cat(sprintf("[β_FX] distribution:\n"))
print(round(table(round(me$beta_FX, 2)) / nrow(me) * 100, 1))

# ── (5) Merge on monthly ym ──
ov <- merge(m4[, .(ym, Date, m4_scalar)], ar[, .(ym, beta_AR)], by = "ym", all = FALSE)
ov <- merge(ov, p_r05[, .(ym, beta_R05)], by = "ym", all = FALSE)
ov <- merge(ov, me[, .(ym, beta_FX, p_bear = p)], by = "ym", all = FALSE)
setorder(ov, ym)
cat(sprintf("\n[Merged] n=%d months / range %s ~ %s\n",
            nrow(ov), ov$ym[1], ov$ym[nrow(ov)]))

# ── (6) Correlation matrix ──
cor_cols <- c("m4_scalar", "beta_AR", "beta_R05", "beta_FX")
cm_pearson <- cor(ov[, ..cor_cols], use = "complete.obs", method = "pearson")
cm_spearman <- cor(ov[, ..cor_cols], use = "complete.obs", method = "spearman")

cat("\n━━━ Pearson correlation ━━━\n")
print(round(cm_pearson, 3))
cat("\n━━━ Spearman correlation ━━━\n")
print(round(cm_spearman, 3))

# ── (7) Tail Dependence Coefficient (lower-tail q20: 동시에 bear 신호 강한 비율) ──
tdc_lower <- function(x, y, q = 0.20) {
  qx <- quantile(x, q, na.rm = TRUE); qy <- quantile(y, q, na.rm = TRUE)
  both <- sum(x <= qx & y <= qy, na.rm = TRUE)
  margin <- sum(x <= qx, na.rm = TRUE)
  if (margin == 0) return(NA_real_)
  both / margin
}
tdc_matrix <- matrix(NA_real_, 4, 4,
                     dimnames = list(cor_cols, cor_cols))
for (i in 1:4) for (j in 1:4) {
  if (i == j) tdc_matrix[i, j] <- 1.0
  else tdc_matrix[i, j] <- tdc_lower(ov[[cor_cols[i]]], ov[[cor_cols[j]]], q = 0.20)
}
cat("\n━━━ Lower Tail Dependence (q20) — 동시 bear-signal 비율 ━━━\n")
print(round(tdc_matrix, 3))

# ── (8) Admit block check ──
cat("\n━━━ Admit Block Check ━━━\n")
worst_pearson <- 0; worst_pair_p <- ""
worst_tdc <- 0; worst_pair_t <- ""
for (i in 1:4) for (j in 1:4) {
  if (i >= j) next
  pp <- abs(cm_pearson[i, j])
  tt <- tdc_matrix[i, j]
  if (pp > worst_pearson) { worst_pearson <- pp; worst_pair_p <- sprintf("%s ~ %s", cor_cols[i], cor_cols[j]) }
  if (tt > worst_tdc) { worst_tdc <- tt; worst_pair_t <- sprintf("%s ~ %s", cor_cols[i], cor_cols[j]) }
}
cat(sprintf("  Worst Pearson |ρ| = %.3f (%s)\n", worst_pearson, worst_pair_p))
cat(sprintf("  Worst TDC (q20)   = %.3f (%s)\n", worst_tdc, worst_pair_t))

reasons <- c(); deploy_ok <- TRUE
if (worst_pearson > 0.7) {
  cat(sprintf("  ❌ Pearson |ρ| > 0.7 (redundancy)\n"))
  reasons <- c(reasons, "pearson_gt_0.7"); deploy_ok <- FALSE
} else cat(sprintf("  ✅ Pearson |ρ| ≤ 0.7\n"))
if (worst_tdc > 0.5) {
  cat(sprintf("  ❌ TDC > 0.5 (Sequential Admission BLOCK)\n"))
  reasons <- c(reasons, "tdc_gt_0.5"); deploy_ok <- FALSE
} else cat(sprintf("  ✅ TDC ≤ 0.5\n"))
cat(sprintf("\n[VERDICT] β_FX overlay add = %s\n",
            ifelse(deploy_ok, "PROCEED to walk-forward backtest",
                   sprintf("BLOCK — %s", paste(reasons, collapse = ", ")))))

# ── (9) Save outputs ──
out <- list(
  pearson = cm_pearson, spearman = cm_spearman, tdc_lower_q20 = tdc_matrix,
  worst_pearson_abs = worst_pearson, worst_pearson_pair = worst_pair_p,
  worst_tdc = worst_tdc, worst_tdc_pair = worst_pair_t,
  deployment_verdict = ifelse(deploy_ok, "PROCEED", "BLOCK"),
  block_reasons = if (length(reasons) == 0) "none" else paste(reasons, collapse = ", "),
  n_months = nrow(ov),
  date_range = c(ov$ym[1], ov$ym[nrow(ov)]),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "overlay_correlation_matrix.json"),
           auto_unbox = TRUE, pretty = TRUE, matrix = "columnmajor")
cat(sprintf("\n[JSON] %s/overlay_correlation_matrix.json\n", EVAL_DIR))

fwrite(ov, file.path(EVAL_DIR, "overlay_scalars_monthly.csv"))
cat(sprintf("[CSV] %s/overlay_scalars_monthly.csv\n", EVAL_DIR))

# ── (10) Chart: heatmap ──
hm_dt <- as.data.table(reshape2::melt(cm_pearson))
hm_dt[, value_lab := sprintf("%.2f", value)]
g1 <- ggplot(hm_dt, aes(x = Var1, y = Var2, fill = value)) +
  geom_tile(color = "white") + geom_text(aes(label = value_lab), size = 4) +
  scale_fill_gradient2(low = "#073B4C", mid = "white", high = "#EF476F",
                       midpoint = 0, limits = c(-1, 1)) +
  labs(title = "4-overlay Pearson correlation", x = NULL, y = NULL, fill = "ρ") +
  theme_minimal(base_size = 11)

tdc_dt <- as.data.table(reshape2::melt(tdc_matrix))
tdc_dt[, value_lab := sprintf("%.2f", value)]
g2 <- ggplot(tdc_dt, aes(x = Var1, y = Var2, fill = value)) +
  geom_tile(color = "white") + geom_text(aes(label = value_lab), size = 4) +
  scale_fill_gradient2(low = "white", mid = "#FFD166", high = "#EF476F",
                       midpoint = 0.3, limits = c(0, 1)) +
  geom_hline(yintercept = 0.5, linetype = "dashed", color = "red") +
  labs(title = "Lower Tail Dependence (q20) — admit block at > 0.5",
       x = NULL, y = NULL, fill = "TDC") +
  theme_minimal(base_size = 11)

g_combined <- patchwork::wrap_plots(g1, g2, ncol = 2)
ggsave(file.path(CHART_DIR, "11_overlay_correlation.png"),
       plot = g_combined, width = 13, height = 5.5, dpi = 120)
cat(sprintf("[Chart 11] %s/11_overlay_correlation.png\n", CHART_DIR))

cat("\n[DONE]\n")
