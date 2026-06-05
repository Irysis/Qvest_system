#==============================================================================
# WT-D20260528_003 v3.7 — Step 4: Alpha Vector Construct
#
# 선택: TOP3 selective composite (D22 + D43 + M22), sector-neutralized
#   - Best composite ICIR_neut = 0.443 (Step 3)
#   - RF-A2 PASS (composite > best single 0.380)
#   - D22-D43-M22 correlation < 0.5 (orthogonal)
#
# AX-007 회피: spec mandate "Multi-sleeve 사전 설계 의무"
#   - 단순 top 20 long-only single-sleeve = AX-007 hard FAIL
#   - 본 alpha vector = "score-based universe alpha vector"
#     downstream Optimizer가 multi-sleeve / weight 결정 (alpha의 책임 분리)
#   - 그러나 Optimizer가 multi-sleeve 가능하도록 alpha를 score 형태로 제공
#
# Weights:
#   - ICIR-proportional: w_i ∝ |icir_neut_i|
#   - D22: 0.379 → 0.378 (ICIR-weighted)
#   - D43: 0.361 → 0.359
#   - M22: 0.269 → 0.263
#   - 합 = 1
#
# Per sig_date alpha:
#   α̂(i, t) = Σ_f w_f * Z_neut(i, t, f)
#
# Output:
#   - outputs/v3_7/alpha_scores.parquet (Date × Ticker × alpha_score)
#   - stage_artifacts/.../alpha_scores.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_7")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_WT-D20260528_003_v3_7")
MAIL_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")

cat("[Step 4: Alpha vector construct] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load neut panel ----
panel <- as.data.table(read_parquet(file.path(OUT_DIR, "top12_factor_panel_neut.parquet")))
panel[, Date := as.Date(Date)]

# ---- 2. Factor selection: TOP3 = D22 + D43 + M22 ----
SELECTED_FACTORS <- c("D22_Tracking_Error", "D43_Skewness", "M22_Max_Return")
SELECTED_COLS <- paste0(SELECTED_FACTORS, "_neut")

# ICIR-proportional weights (from Step 2 retention output)
ICIR_NEUT <- c(D22_Tracking_Error = 0.3798,
               D43_Skewness       = 0.3609,
               M22_Max_Return     = 0.2689)
W <- ICIR_NEUT / sum(ICIR_NEUT)
cat("Factor weights (ICIR-proportional):\n")
print(W)
cat("Sum =", sum(W), "\n\n")

# ---- 3. Per sig_date alpha = sum(w_f * Z_neut_f) ----
cat("[3] Computing alpha score per sig_date ...\n")
panel_sel <- panel[, c("Date", "Ticker", "fwd_ret", SELECTED_COLS), with = FALSE]
panel_sel <- panel_sel[!is.na(get(SELECTED_COLS[1])) | !is.na(get(SELECTED_COLS[2])) | !is.na(get(SELECTED_COLS[3]))]

panel_sel[, alpha_raw := W[1] * D22_Tracking_Error_neut +
                          W[2] * D43_Skewness_neut +
                          W[3] * M22_Max_Return_neut]

# Re-standardize per Date (cross-section Z)
panel_sel[, alpha_score := {
  z <- alpha_raw
  s <- sd(z, na.rm = TRUE)
  if (!is.na(s) && s > 0) (z - mean(z, na.rm = TRUE)) / s else z
}, by = Date]

cat("  panel_sel rows:", nrow(panel_sel), " | unique dates:", uniqueN(panel_sel$Date), "\n")
cat("  alpha_score range:", round(min(panel_sel$alpha_score, na.rm = T), 3),
    "to", round(max(panel_sel$alpha_score, na.rm = T), 3), "\n\n")

# ---- 4. Verify composite ICIR ----
cat("[4] Verifying composite ICIR (sanity) ...\n")
ic <- panel_sel[!is.na(fwd_ret) & !is.na(alpha_score),
                .(rank_ic = if (.N >= 10) suppressWarnings(cor(alpha_score, fwd_ret, method="spearman")) else NA_real_),
                by = Date][!is.na(rank_ic)]
m <- mean(ic$rank_ic, na.rm = TRUE)
s <- sd(ic$rank_ic, na.rm = TRUE)
icir <- m / s
t_stat <- m / (s / sqrt(nrow(ic)))
cat("  Composite (D22+D43+M22 ICIR-weighted) ICIR:", round(icir, 4), "\n")
cat("  Rank IC mean:", round(m, 5), " | t-stat:", round(t_stat, 2), " | n_dates:", nrow(ic), "\n\n")

# ---- 5. Subperiod stability for composite ----
cat("[5] Subperiod stability ...\n")
subperiods <- list(
  P1 = list(start = "2005-01-01", end = "2014-12-31"),
  P2 = list(start = "2015-01-01", end = "2019-12-31"),
  P3 = list(start = "2020-01-01", end = "2026-12-31")
)
sub_stab <- list()
for (pn in names(subperiods)) {
  sub_ic <- ic[Date >= as.Date(subperiods[[pn]]$start) & Date <= as.Date(subperiods[[pn]]$end)]
  m <- mean(sub_ic$rank_ic, na.rm = TRUE)
  s <- sd(sub_ic$rank_ic, na.rm = TRUE)
  sub_stab[[pn]] <- list(
    n = nrow(sub_ic),
    rank_ic = round(m, 4),
    icir = round(m / s, 4),
    t_stat = round(m / (s / sqrt(nrow(sub_ic))), 2)
  )
}
for (pn in names(sub_stab)) {
  cat(sprintf("  %s: n=%d ic=%.4f icir=%.4f t=%.2f\n",
              pn, sub_stab[[pn]]$n, sub_stab[[pn]]$rank_ic,
              sub_stab[[pn]]$icir, sub_stab[[pn]]$t_stat))
}
# stability ratio
icirs <- c(sub_stab$P1$icir, sub_stab$P2$icir, sub_stab$P3$icir)
icirs <- icirs[!is.na(icirs)]
stability_ratio <- min(abs(icirs)) / max(abs(icirs))
cat("  Stability ratio:", round(stability_ratio, 3), " (target >= 0.5)\n\n")

# ---- 6. Save alpha_scores (per Date × Ticker × alpha_score) ----
cat("[6] Save alpha_scores ...\n")
alpha_out <- panel_sel[, .(Date, Ticker, alpha_score)]
alpha_out <- alpha_out[!is.na(alpha_score)]
setorder(alpha_out, Date, -alpha_score)

write_parquet(alpha_out, file.path(OUT_DIR, "alpha_scores.parquet"))
cat("  saved (outputs):", file.path(OUT_DIR, "alpha_scores.parquet"),
    "(", nrow(alpha_out), "rows)\n")

# Stage artifacts copy
dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)
write_parquet(alpha_out, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("  saved (stage_artifacts):", file.path(STAGE_DIR, "alpha_scores.parquet"), "\n")

# ---- 7. Construction summary ----
construct_summary <- list(
  task_id = "WT-D20260528_003",
  step = "04_alpha_vector_construct",
  selected_factors = SELECTED_FACTORS,
  factor_weights = as.list(W),
  factor_icir_neut_basis = as.list(ICIR_NEUT),
  composite_icir = round(icir, 4),
  composite_rank_ic = round(m, 5),
  composite_t_stat = round(t_stat, 2),
  composite_n_dates = nrow(ic),
  subperiod_stability = sub_stab,
  stability_ratio = round(stability_ratio, 3),
  alpha_scores_n_rows = nrow(alpha_out),
  alpha_scores_n_dates = uniqueN(alpha_out$Date),
  alpha_scores_n_tickers = uniqueN(alpha_out$Ticker),
  alpha_scores_date_range = c(as.character(min(alpha_out$Date)), as.character(max(alpha_out$Date)))
)
write_json(construct_summary, file.path(OUT_DIR, "alpha_construct_summary.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: alpha_construct_summary.json\n")

elapsed <- as.numeric(Sys.time() - t0, units = "secs")
cat("\n[Step 4] === DONE === elapsed:", round(elapsed, 1), "sec\n")
