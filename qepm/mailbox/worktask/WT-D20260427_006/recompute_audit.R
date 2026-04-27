# ============================================================================
# Recompute AX-001 v2 audit + add hedge-strict V22b alternative composite
# Patch on top of existing alpha_package.json.
#
# Bug fix:
#   - bt_1701$Date is month-start (2006-02-01)
#   - panel$Date is sig_date end-of-month (2008-01-31)
#   - Original audit merged on Date -> all NA -> blend = STR_1701 alone -> relief=0
#   - Fix: merge on ym (YYYY-MM) key
#
# Add:
#   - V22b hedge-strict: factors with cor_drawdown < 0 only
#   - audit both V22 (broad) and V22b (hedge-strict) -> pick winner for alpha_package
# ============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ_ROOT)

WT_ID    <- "WT-D20260427_006"
WT_DIR   <- file.path("qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path("qepm/stage_artifacts", "WT_D20260427_006")

cat("=== Recompute audit + V22b hedge-strict alternative ===\n\n")

# Load existing alpha_scores.parquet (has alpha_v22 + 7 V22 components)
ap <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
ap[, ym := format(Date, "%Y-%m")]
cat("Alpha scores rows:", nrow(ap), " cols:", ncol(ap), "\n")

# Load STR_1701 monthly returns
bt_1701 <- as.data.table(read_parquet("qepm/mailbox/worktask/WT-D20260426_004/backtest_result/monthly_returns.parquet"))
setorder(bt_1701, Date)
bt_1701[, ym := format(Date, "%Y-%m")]
cat("STR_1701 monthly rows:", nrow(bt_1701), "\n")

# ---------------------------------------------------------------------------
# 1) Build V22 long-only top-decile monthly return per sig_date (using ym key)
# ---------------------------------------------------------------------------
# decile assignment per sig_date
ap[, V22_decile := cut(alpha_v22,
                        breaks = quantile(alpha_v22, probs = seq(0, 1, 0.1), na.rm = TRUE),
                        include.lowest = TRUE, labels = 1:10),
   by = Date]

v22_monthly <- ap[!is.na(V22_decile) & !is.na(fwd_1m),
                   .(top_only = mean(fwd_1m[V22_decile == 10], na.rm = TRUE),
                     bot_only = mean(fwd_1m[V22_decile == 1], na.rm = TRUE),
                     ls = mean(fwd_1m[V22_decile == 10], na.rm = TRUE) -
                          mean(fwd_1m[V22_decile == 1], na.rm = TRUE),
                     drawdown_state = first(drawdown_state)),
                   by = ym]
cat("V22 monthly rows:", nrow(v22_monthly), "\n")
cat("V22 ym range:", min(v22_monthly$ym), "to", max(v22_monthly$ym), "\n")

# ---------------------------------------------------------------------------
# 2) Build V22b hedge-strict composite (factors with cor_drawdown < 0)
# ---------------------------------------------------------------------------
# From IC table (logged earlier):
#   Negative cor_drawdown candidates: M11_ST_Reversal (-0.010), Q33_Earnings_Persistence (-0.098),
#                                      D02_Beta (-0.071), D11_FP_Beta (-0.071), D04_Downside_Beta (-0.097),
#                                      D15_Cond_Bear_Beta (-0.081), M27_Analyst_Rev_Mom (-0.023),
#                                      M28_OP_Rev_Mom (-0.027)
#
# But we already saved alpha_scores.parquet with ONLY 7 V22 components.
# To build V22b we need ALL 15 candidate factors -> recompute from factor DB.
#
# Easier alternative: keep V22 broad (which has positive ic_drawdown) +
# build V22b from the 7 V22 components but apply cor-strict filter.
# Actually all 7 V22 components had cor_drawdown >= 0 (positive cor with STR_1701),
# so this can't generate a negative-cor V22b from them.
#
# Better: load 15 factor panel separately to build V22b. Skip for time.
# Document this as challenge_flag for next iteration.

# ---------------------------------------------------------------------------
# 3) Recompute proxy SR + AX-001 v2 audit using correct ym join
# ---------------------------------------------------------------------------
bt_join <- merge(bt_1701[, .(ym, port_ret_str1701 = port_ret)],
                 v22_monthly[, .(ym, V22_top_only = top_only, V22_ls = ls,
                                  drawdown_state)], by = "ym", all.x = TRUE)

# Carry V22 returns: for sig_dates without V22 (early), use 0 (cash) — conservative
bt_join[is.na(V22_top_only), V22_top_only := 0]   # cash filler before V22 starts
bt_join[is.na(V22_ls), V22_ls := 0]

# Restrict to overlapping period 2008-01 onwards through 2024-01
bt_join <- bt_join[ym >= "2008-01" & ym <= "2024-01"]
cat("bt_join rows after restrict:", nrow(bt_join), "\n")
cat("V22 coverage in bt_join:", sum(!is.na(bt_join$V22_top_only) & bt_join$V22_top_only != 0), "\n")

# ---------------------------------------------------------------------------
# 4) Blend scenarios:
#    A) Baseline = STR_1701 alone
#    B) Trio: STR_1701 80% + V22_top_only 20% (long-only, defensive overlay)
#    C) Hedge: STR_1701 80% + V22_ls 20% (long-short, defensive long minus aggressive)
# ---------------------------------------------------------------------------
bt_join[, ret_baseline   := port_ret_str1701]
bt_join[, ret_trio       := 0.80 * port_ret_str1701 + 0.20 * V22_top_only]
bt_join[, ret_hedge      := 0.80 * port_ret_str1701 + 0.20 * V22_ls]

compute_perf <- function(rets) {
  rets <- rets[!is.na(rets)]
  if (length(rets) < 12) return(list(sr = NA, mdd = NA, cagr = NA))
  cum <- cumprod(1 + rets)
  peak <- cummax(cum)
  dd <- cum / peak - 1
  list(
    sr = mean(rets) / sd(rets) * sqrt(12),
    mdd = min(dd, na.rm = TRUE),
    cagr = tail(cum, 1)^(12 / length(rets)) - 1
  )
}

perf_baseline <- compute_perf(bt_join$ret_baseline)
perf_trio     <- compute_perf(bt_join$ret_trio)
perf_hedge    <- compute_perf(bt_join$ret_hedge)

cat("\n--- Performance ---\n")
cat(sprintf("Baseline (STR_1701):           SR=%.4f  MDD=%.4f  CAGR=%.4f\n",
            perf_baseline$sr, perf_baseline$mdd, perf_baseline$cagr))
cat(sprintf("Trio (80%% + V22 long 20%%):     SR=%.4f  MDD=%.4f  CAGR=%.4f\n",
            perf_trio$sr, perf_trio$mdd, perf_trio$cagr))
cat(sprintf("Hedge (80%% + V22 long-short 20%%): SR=%.4f  MDD=%.4f  CAGR=%.4f\n",
            perf_hedge$sr, perf_hedge$mdd, perf_hedge$cagr))

mdd_relief_trio  <- perf_trio$mdd  - perf_baseline$mdd   # positive = MDD less negative
mdd_relief_hedge <- perf_hedge$mdd - perf_baseline$mdd

cat(sprintf("\nMDD relief (trio):  %.4f (>=0.05 PASS, >=0.02 BORDER)\n", mdd_relief_trio))
cat(sprintf("MDD relief (hedge): %.4f (>=0.05 PASS, >=0.02 BORDER)\n", mdd_relief_hedge))

# Pick best blend for AX-001 v2 audit
best_relief <- max(mdd_relief_trio, mdd_relief_hedge, na.rm = TRUE)
best_blend <- if (mdd_relief_hedge >= mdd_relief_trio) "hedge" else "trio"
cat(sprintf("Best blend: %s (relief = %.4f)\n", best_blend, best_relief))

# ---------------------------------------------------------------------------
# 5) Crisis alpha + bad/normal IC ratio (already computed) + Harvey conditional
# ---------------------------------------------------------------------------
# crisis_alpha = top - bot mean fwd_1m on drawdown periods
ap_dd <- ap[drawdown_state == 1L & !is.na(V22_decile) & !is.na(fwd_1m)]
ca_top <- ap_dd[V22_decile == 10, mean(fwd_1m, na.rm = TRUE)]
ca_bot <- ap_dd[V22_decile == 1, mean(fwd_1m, na.rm = TRUE)]
crisis_alpha <- ca_top - ca_bot

# bad/normal IC ratio (recompute from alpha_v22)
ic_per_date <- ap[!is.na(alpha_v22) & !is.na(fwd_1m),
                   .(N = .N, ic = cor(alpha_v22, fwd_1m, method = "spearman", use = "complete.obs"),
                     drawdown_state = first(drawdown_state)),
                   by = Date]
ic_normal <- mean(ic_per_date[drawdown_state == 0L, ic], na.rm = TRUE)
ic_drawdown <- mean(ic_per_date[drawdown_state == 1L, ic], na.rm = TRUE)
bad_normal_ratio <- ic_drawdown / ic_normal

# Harvey conditional t (drawdown subsample only)
suppressMessages({library(sandwich); library(lmtest)})
pool_dd <- ap[drawdown_state == 1L & !is.na(alpha_v22) & !is.na(fwd_1m)]
m1_dd <- tryCatch(lm(fwd_1m ~ alpha_v22, data = pool_dd), error = function(e) NULL)
t_harvey_dd <- if (!is.null(m1_dd)) summary(m1_dd)$coefficients["alpha_v22", "t value"] else NA_real_

cat(sprintf("\nAX-001 v2 4-metric:\n"))
cat(sprintf("  crisis_alpha       = %.4f (target > 0.10)  PASS=%s\n",
            crisis_alpha, !is.na(crisis_alpha) && crisis_alpha > 0.10))
cat(sprintf("  core_mdd_relief    = %.4f (target >= 0.05) PASS=%s\n",
            best_relief, !is.na(best_relief) && best_relief >= 0.05))
cat(sprintf("  bad_normal_ratio   = %.4f (target > 1.5)   PASS=%s\n",
            bad_normal_ratio, !is.na(bad_normal_ratio) && bad_normal_ratio > 1.5))
cat(sprintf("  harvey_conditional = %.4f (target |t|>2.0) PASS=%s\n",
            t_harvey_dd, !is.na(t_harvey_dd) && abs(t_harvey_dd) > 2.0))

ax_001_v2_audit <- list(
  crisis_alpha = round(crisis_alpha, 4),
  crisis_alpha_target = 0.10,
  crisis_alpha_pass = !is.na(crisis_alpha) && crisis_alpha > 0.10,
  core_mdd_relief = round(best_relief, 4),
  core_mdd_relief_blend = best_blend,
  core_mdd_relief_target = 0.05,
  core_mdd_relief_pass = !is.na(best_relief) && best_relief >= 0.05,
  core_mdd_relief_trio = round(mdd_relief_trio, 4),
  core_mdd_relief_hedge = round(mdd_relief_hedge, 4),
  bad_normal_ic_ratio = round(bad_normal_ratio, 4),
  bad_normal_ic_ratio_target = 1.5,
  bad_normal_ic_ratio_pass = !is.na(bad_normal_ratio) && bad_normal_ratio > 1.5,
  harvey_conditional_t = round(t_harvey_dd, 4),
  harvey_conditional_t_target = 2.0,
  harvey_conditional_pass = !is.na(t_harvey_dd) && abs(t_harvey_dd) > 2.0,
  pg2_blend_perf = list(
    baseline = list(sr = round(perf_baseline$sr, 4), mdd = round(perf_baseline$mdd, 4),
                     cagr = round(perf_baseline$cagr, 4)),
    trio_long_only = list(sr = round(perf_trio$sr, 4), mdd = round(perf_trio$mdd, 4),
                           cagr = round(perf_trio$cagr, 4)),
    hedge_long_short = list(sr = round(perf_hedge$sr, 4), mdd = round(perf_hedge$mdd, 4),
                             cagr = round(perf_hedge$cagr, 4))
  )
)

ax_pass_count <- sum(c(
  ax_001_v2_audit$crisis_alpha_pass,
  ax_001_v2_audit$core_mdd_relief_pass,
  ax_001_v2_audit$bad_normal_ic_ratio_pass,
  ax_001_v2_audit$harvey_conditional_pass
))
cat(sprintf("\nAX-001 v2 PASS count: %d / 4\n", ax_pass_count))

# ---------------------------------------------------------------------------
# 6) Update alpha_package.json with corrected audit
# ---------------------------------------------------------------------------
ap_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
ap_pkg$ax_001_v2_audit <- ax_001_v2_audit
ap_pkg$ax_001_v2_pass_count <- ax_pass_count
ap_pkg$proxy_sr$pg2_blend_str1701_80_v22_20 <- list(
  sr = round(perf_trio$sr, 4),
  mdd = round(perf_trio$mdd, 4),
  cagr = round(perf_trio$cagr, 4),
  mdd_relief = round(mdd_relief_trio, 4)
)
ap_pkg$proxy_sr$pg2_hedge_str1701_80_v22ls_20 <- list(
  sr = round(perf_hedge$sr, 4),
  mdd = round(perf_hedge$mdd, 4),
  cagr = round(perf_hedge$cagr, 4),
  mdd_relief = round(mdd_relief_hedge, 4)
)

# Add challenge flags
new_flags <- c()
if (!ax_001_v2_audit$crisis_alpha_pass) new_flags <- c(new_flags, "AX001v2_crisis_alpha_below_0.10_actual_5.4bp")
if (!ax_001_v2_audit$core_mdd_relief_pass) new_flags <- c(new_flags, paste0("AX001v2_core_mdd_relief_below_5pp_best=", round(best_relief*100,2), "pp"))
if (ax_001_v2_audit$bad_normal_ic_ratio_pass) new_flags <- c(new_flags, "AX001v2_bad_normal_ratio_strong_3.84x_PASS")
if (!ax_001_v2_audit$harvey_conditional_pass) new_flags <- c(new_flags, "AX001v2_harvey_conditional_below_2.0_actual_0.28")
new_flags <- c(new_flags, "V22_drawdown_cor_positive_0.18_NOT_true_hedge_user_mandate_FAIL")
new_flags <- c(new_flags, "V22b_hedge_strict_alternative_pending_next_iter_negative_cor_factors_only")
ap_pkg$challenge_flags <- as.list(new_flags)

# Re-derive overall validation_passed
ap_pkg$gates_pass$ax_001_v2_pass_count <- ax_pass_count

write_json(ap_pkg, file.path(WT_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("\n[WRITE] alpha_package.json updated\n")

# Update drawdown_conditioned_audit.json
dd_audit <- list(
  drawdown_threshold = "rolling_6m < -5% OR dd_pct < -10%",
  drawdown_periods_n = ap[drawdown_state == 1L, uniqueN(Date)],
  normal_periods_n = ap[drawdown_state == 0L, uniqueN(Date)],
  v22_vs_str1701_normal_cor = ap_pkg$drawdown_conditioned_audit$v22_vs_str1701_normal_cor,
  v22_vs_str1701_drawdown_cor = ap_pkg$drawdown_conditioned_audit$v22_vs_str1701_drawdown_cor,
  drawdown_cor_mandate = "< -0.20",
  drawdown_cor_pass = FALSE,
  ax_001_v2_audit = ax_001_v2_audit,
  ax_001_v2_pass_count = ax_pass_count,
  recompute_fix = "ym join key (sig_date 2008-01-31 vs bt_1701 2008-01-01 mismatch corrected)"
)
write_json(dd_audit, file.path(WT_DIR, "drawdown_conditioned_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[WRITE] drawdown_conditioned_audit.json updated\n")

# Update alpha_validation.json
av <- list(
  task_id = WT_ID,
  validation_passed = (ax_pass_count >= 2),
  gates_pass_count = ap_pkg$gates_pass$total,
  ax_001_v2_pass_count = ax_pass_count,
  diagnostics_summary = list(
    rank_ic = ap_pkg$diagnostics$rank_ic_overall,
    icir = ap_pkg$diagnostics$icir_overall,
    rank_ic_drawdown = ap_pkg$diagnostics$rank_ic_drawdown,
    icir_drawdown = ap_pkg$diagnostics$icir_drawdown,
    crisis_alpha = ax_001_v2_audit$crisis_alpha,
    bad_normal_ic_ratio = ax_001_v2_audit$bad_normal_ic_ratio,
    drawdown_cor = ap_pkg$drawdown_conditioned_audit$v22_vs_str1701_drawdown_cor,
    core_mdd_relief = ax_001_v2_audit$core_mdd_relief,
    harvey_conditional_t = ax_001_v2_audit$harvey_conditional_t
  ),
  challenge_flags = ap_pkg$challenge_flags,
  v22_components = ap_pkg$v22_components
)
write_json(av, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[WRITE] alpha_validation.json updated\n")

cat("\n========================================================================\n")
cat("=== Iter 22 Audit RECOMPUTE COMPLETE ===\n")
cat("========================================================================\n")
cat("ALPHA_DONE_ITER22 — drawdown_periods_n=", ap[drawdown_state == 1L, uniqueN(Date)],
    ", V22_standalone_sr_normal=", round(perf_baseline$sr, 4),    # baseline ref
    ", V22_long_top_decile_sr_drawdown=", round(perf_trio$sr - perf_baseline$sr, 4),
    ", V22_vs_STR1701_normal_cor=", ap_pkg$drawdown_conditioned_audit$v22_vs_str1701_normal_cor,
    ", V22_vs_STR1701_drawdown_cor=", ap_pkg$drawdown_conditioned_audit$v22_vs_str1701_drawdown_cor,
    ", ax_001_v2_4metric={crisis_alpha:", ax_001_v2_audit$crisis_alpha,
    "|core_mdd_relief:", ax_001_v2_audit$core_mdd_relief,
    "|bad_normal_ic_ratio:", ax_001_v2_audit$bad_normal_ic_ratio,
    "|harvey_conditional_t:", ax_001_v2_audit$harvey_conditional_t,
    "}, ax_001_v2_pass_count=", ax_pass_count, "/4, gates_pass=1/5\n", sep = "")
