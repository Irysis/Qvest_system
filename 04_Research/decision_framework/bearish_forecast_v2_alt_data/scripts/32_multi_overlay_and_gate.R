#==============================================================================
# 32_multi_overlay_and_gate.R — Cycle 2.1 Multi-overlay AND gate audit
#
# Hypothesis: 4중 overlay (m4 + β_AR + β_R05 + β_FX) 동시 alert는 FP 극도 억제
# 따라서 inverse 베팅 시 monthly close ret이 더 신뢰성 있게 negative일 가능성.
#
# N-of-4 confirmation: 1/2/3/4 of 4 alerts → precision + monthly ret
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(ggplot2)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load overlay scalars + monthly KOSPI200 close ret ──
ov <- fread(file.path(EVAL_DIR, "overlay_scalars_monthly.csv"))
ov[, Date := as.Date(Date)]
setorder(ov, ym)

# Load BM close
bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_next_month := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, ym_next := shift(ym, n = 1L, type = "lead")]

# Merge
audit <- merge(ov[, .(ym, m4_scalar, beta_AR, beta_R05, beta_FX, p_bear)],
               eom[, .(ym, ret_next_month, ym_next)],
               by = "ym", all.x = TRUE)
setorder(audit, ym)

# ── (2) Define binary alerts (scalar < 1 = alert) ──
audit[, alert_m4   := m4_scalar < 1.0]
audit[, alert_AR   := beta_AR < 1.0]
audit[, alert_R05  := beta_R05 < 1.0]
audit[, alert_FX   := beta_FX < 1.0]
audit[, n_alerts   := alert_m4 + alert_AR + alert_R05 + alert_FX]

cat(sprintf("━━━ Alert counts ━━━\n"))
cat(sprintf("Total months: %d\n\n", nrow(audit)))
cat(sprintf("Per-overlay alert counts (active months):\n"))
cat(sprintf("  m4 (BOCPD)  : %d (%.1f%%)\n", sum(audit$alert_m4), 100 * mean(audit$alert_m4)))
cat(sprintf("  β_AR        : %d (%.1f%%)\n", sum(audit$alert_AR), 100 * mean(audit$alert_AR)))
cat(sprintf("  β_R05       : %d (%.1f%%)\n", sum(audit$alert_R05), 100 * mean(audit$alert_R05)))
cat(sprintf("  β_FX        : %d (%.1f%%)\n", sum(audit$alert_FX), 100 * mean(audit$alert_FX)))

# ── (3) N-of-4 confirmation distribution ──
cat(sprintf("\n━━━ N-of-4 alert distribution ━━━\n"))
print(table(audit$n_alerts))

# ── (4) Per N-of-4 level: monthly ret stats ──
cat(sprintf("\n━━━ Monthly close ret per confirmation level ━━━\n"))
cat(sprintf("%-10s %-8s %-15s %-15s %-15s %-15s\n",
            "N alerts", "N obs", "Neg ret%%", "Ret<-3%%%%", "Mean ret", "Inv cum"))
for (k in 0:4) {
  sub <- audit[n_alerts == k & !is.na(ret_next_month)]
  if (nrow(sub) == 0) next
  inv_cum <- prod(1 - sub$ret_next_month) - 1  # inverse 1x
  cat(sprintf("%-10d %-8d %-15.0f %-15.0f %+14.2f%% %+14.1f%%\n",
              k, nrow(sub),
              100 * mean(sub$ret_next_month < 0),
              100 * mean(sub$ret_next_month < -0.03),
              100 * mean(sub$ret_next_month),
              100 * inv_cum))
}

# ── (5) ≥ N alerts (cumulative) ──
cat(sprintf("\n━━━ ≥N alerts (cumulative trigger) ━━━\n"))
cat(sprintf("%-10s %-8s %-15s %-15s %-15s %-15s\n",
            "≥N alerts", "N obs", "Neg ret%%", "Ret<-3%%%%", "Mean ret", "Inv cum"))
for (k in 1:4) {
  sub <- audit[n_alerts >= k & !is.na(ret_next_month)]
  if (nrow(sub) == 0) next
  inv_cum <- prod(1 - sub$ret_next_month) - 1
  cat(sprintf("≥%-9d %-8d %-15.0f %-15.0f %+14.2f%% %+14.1f%%\n",
              k, nrow(sub),
              100 * mean(sub$ret_next_month < 0),
              100 * mean(sub$ret_next_month < -0.03),
              100 * mean(sub$ret_next_month),
              100 * inv_cum))
}

# ── (6) 4-of-4 AND gate detail ──
cat(sprintf("\n━━━ 4-of-4 ALL alerts (strictest) ━━━\n"))
strict <- audit[n_alerts == 4]
if (nrow(strict) > 0) {
  print(strict[, .(ym, ym_next, m4 = round(m4_scalar, 2),
                   AR = beta_AR, R05 = beta_R05, FX = beta_FX,
                   p = round(p_bear, 3),
                   ret = sprintf("%+.2f%%", 100 * ret_next_month),
                   monthly_neg = ret_next_month < 0)])
} else {
  cat("  (no 4-of-4 alerts found)\n")
}

# ── (7) 3-of-4 detail ──
cat(sprintf("\n━━━ 3-of-4 alerts ━━━\n"))
three <- audit[n_alerts == 3]
if (nrow(three) > 0) {
  three_view <- three[, .(ym, ym_next, m4 = round(m4_scalar, 2),
                          AR = beta_AR, R05 = beta_R05, FX = beta_FX,
                          p = round(p_bear, 3),
                          ret = sprintf("%+.2f%%", 100 * ret_next_month),
                          neg = ret_next_month < 0)]
  print(three_view)
  cat(sprintf("\n  3-of-4 neg rate: %.0f%% / mean ret: %+.2f%%\n",
              100 * mean(three$ret_next_month < 0, na.rm = TRUE),
              100 * mean(three$ret_next_month, na.rm = TRUE)))
}

# ── (8) ≥3 confirmation rule → inverse PnL ──
cat(sprintf("\n━━━ ≥3 of 4 inverse bet (best so far) ━━━\n"))
trigger3 <- audit[n_alerts >= 3 & !is.na(ret_next_month)]
if (nrow(trigger3) > 0) {
  inv_ret <- -trigger3$ret_next_month
  cum_inv <- prod(1 + inv_ret) - 1
  win_rate <- mean(inv_ret > 0)
  cat(sprintf("  n=%d trigger / cum_inverse=%+.2f%% / win_rate=%.0f%% / per_trigger_avg=%+.2f%%\n",
              nrow(trigger3), 100 * cum_inv, 100 * win_rate, 100 * mean(inv_ret)))

  # Bootstrap CI
  set.seed(42)
  bs <- replicate(2000, {
    s <- sample(inv_ret, length(inv_ret), replace = TRUE)
    mean(s)
  })
  cat(sprintf("  Bootstrap mean CI [%+.2f%%, %+.2f%%] (95%%, B=2000)\n",
              100 * quantile(bs, 0.025), 100 * quantile(bs, 0.975)))

  if (mean(inv_ret) > 0) {
    cat(sprintf("  ✅ POSITIVE expected — ≥3 of 4 AND gate inverse 베팅 가치 있음\n"))
  } else {
    cat(sprintf("  ❌ NEGATIVE expected — AND gate도 inverse 베팅 부적합\n"))
  }
}

# ── (9) Save ──
fwrite(audit, file.path(EVAL_DIR, "multi_overlay_alert_audit.csv"))
cat(sprintf("\n[CSV] outputs/04_evaluation/multi_overlay_alert_audit.csv\n"))
cat(sprintf("\n[DONE]\n"))
