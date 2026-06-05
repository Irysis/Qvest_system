#==============================================================================
# 27_monthend_prauc_revalidate.R — 월말 snapshot 한정 PR-AUC 재평가
#
# 검증 목표 (β_FX Layer 6 admit 사전 검증 #1):
#   Daily 전체 OOS PR-AUC = 0.608 (target = y_tail_q15)
#   월말 snapshot 한정 (~110건) subset에서도 0.6 수준 유지하는지?
#   유지 안 되면 분포 shift / 월말 효과 의심 → β_FX 사용 불가
#
# Output:
#   - outputs/04_evaluation/monthend_prauc_revalidation.json
#   - outputs/06_reports/charts/10_monthend_prauc.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DYN_DIR <- file.path(WS, "outputs/03_models/dynamic_ensemble")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load predictions ──
preds <- as.data.table(read_parquet(
  file.path(DYN_DIR, "predictions_dynamic_y_tail_q15.parquet")))
preds[, Date := as.Date(Date)]
preds[, p := p_M2_regime]
preds <- preds[!is.na(p) & !is.na(y)]
setorder(preds, Date)
cat(sprintf("Daily OOS: N=%d / events=%d (%.1f%%)\n",
            nrow(preds), sum(preds$y), 100 * mean(preds$y)))

# ── (2) Month-end filter ──
preds[, ym := format(Date, "%Y-%m")]
me <- preds[, .SD[which.max(Date)], by = ym]
setorder(me, Date)
cat(sprintf("Month-end snapshots: N=%d / events=%d (%.1f%%)\n\n",
            nrow(me), sum(me$y), 100 * mean(me$y)))

# ── (3) PR-AUC functions ──
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

# Bootstrap CI for PR-AUC
boot_prauc_ci <- function(p, y, B = 1000, seed = 42) {
  set.seed(seed); n <- length(p); bs <- numeric(B)
  for (b in seq_len(B)) {
    idx <- sample(n, n, replace = TRUE)
    bs[b] <- pr_auc(p[idx], y[idx])
  }
  c(lo = quantile(bs, 0.025, na.rm = TRUE),
    hi = quantile(bs, 0.975, na.rm = TRUE),
    se = sd(bs, na.rm = TRUE))
}

# ── (4) Core comparison ──
pa_daily <- pr_auc(preds$p, preds$y)
base_daily <- mean(preds$y)
ci_daily <- boot_prauc_ci(preds$p, preds$y, B = 500)

pa_me <- pr_auc(me$p, me$y)
base_me <- mean(me$y)
ci_me <- boot_prauc_ci(me$p, me$y, B = 2000)

cat("━━━ PR-AUC 비교 ━━━\n")
cat(sprintf("Daily   : %.4f (baseline %.4f, lift %.2fx) | 95%% CI [%.3f, %.3f]\n",
            pa_daily, base_daily, pa_daily / base_daily, ci_daily["lo.2.5%"], ci_daily["hi.97.5%"]))
cat(sprintf("Monthend: %.4f (baseline %.4f, lift %.2fx) | 95%% CI [%.3f, %.3f]\n",
            pa_me, base_me, pa_me / base_me, ci_me["lo.2.5%"], ci_me["hi.97.5%"]))
cat(sprintf("Delta   : %+.4f (monthend - daily)\n", pa_me - pa_daily))

# Statistical test: monthend within daily 95% CI?
in_ci <- (pa_me >= ci_daily["lo.2.5%"]) & (pa_me <= ci_daily["hi.97.5%"])
cat(sprintf("Monthend within daily 95%% CI? %s\n\n", ifelse(in_ci, "YES (분포 shift 없음)", "NO (분포 shift 의심)")))

# ── (5) Threshold analysis at month-end ──
cat("━━━ Month-end threshold 분석 ━━━\n")
cat(sprintf("%-10s %-12s %-10s %-10s %-10s %-10s\n",
            "Top %", "Threshold", "Alerts", "TP", "Precision", "Recall"))
n_me <- nrow(me); total_events_me <- sum(me$y)
for (pct in c(0.05, 0.10, 0.15, 0.20, 0.30, 0.50)) {
  k <- ceiling(n_me * pct)
  thr <- quantile(me$p, 1 - pct, na.rm = TRUE)
  alert <- as.integer(me$p >= thr)
  tp <- sum(alert == 1 & me$y == 1)
  fp <- sum(alert == 1 & me$y == 0)
  fn <- sum(alert == 0 & me$y == 1)
  precision <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
  recall <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
  cat(sprintf("%-10s %-12.4f %-10d %-10d %-10.3f %-10.3f\n",
              sprintf("%.0f%%", 100 * pct), thr, sum(alert), tp, precision, recall))
}

# ── (6) Yearly stability ──
me[, year := format(Date, "%Y")]
yr_table <- me[, .(N = .N, events = sum(y),
                   event_pct = sprintf("%.0f%%", 100 * mean(y)),
                   pr_auc = round(pr_auc(p, y), 3),
                   baseline = round(mean(y), 3)), by = year]
cat("\n━━━ 연도별 month-end PR-AUC ━━━\n")
print(yr_table)

# ── (7) Recent 24m subset ──
recent24 <- tail(me, 24)
pa_r24 <- pr_auc(recent24$p, recent24$y)
base_r24 <- mean(recent24$y)
cat(sprintf("\n━━━ 최근 24개월 month-end ━━━\n"))
cat(sprintf("N=%d / events=%d (%.0f%%) / PR-AUC=%.4f / baseline=%.4f / lift %.2fx\n",
            nrow(recent24), sum(recent24$y), 100 * mean(recent24$y),
            pa_r24, base_r24, pa_r24 / base_r24))

# Recent 12m
recent12 <- tail(me, 12)
pa_r12 <- pr_auc(recent12$p, recent12$y)
base_r12 <- mean(recent12$y)
cat(sprintf("최근 12개월: N=%d / events=%d (%.0f%%) / PR-AUC=%.4f / baseline=%.4f\n",
            nrow(recent12), sum(recent12$y), 100 * mean(recent12$y),
            pa_r12, base_r12))

# ── (8) Calibration (reliability diagram) ──
me[, p_bin := cut(p, breaks = quantile(p, seq(0, 1, 0.1), na.rm = TRUE),
                  include.lowest = TRUE, labels = FALSE)]
cal <- me[, .(N = .N, mean_p = mean(p), obs_rate = mean(y)), by = p_bin][order(p_bin)]
cat("\n━━━ Calibration (decile) ━━━\n")
print(cal)

# Calibration slope (1.0 perfect, > 1 over-conf, < 1 under-conf)
cal_lm <- lm(obs_rate ~ mean_p, data = cal)
cal_slope <- coef(cal_lm)[2]
cal_int <- coef(cal_lm)[1]
cat(sprintf("Calibration slope = %.3f (1.0 perfect / >1 over-conf / <1 under-conf)\n", cal_slope))
cat(sprintf("Calibration intercept = %.3f\n", cal_int))

# Brier Skill Score
brier <- mean((me$p - me$y)^2)
brier_base <- mean((base_me - me$y)^2)
bss <- 1 - brier / brier_base
cat(sprintf("Brier Skill Score = %.4f\n", bss))

# ── (9) Decision rule: β_FX deployment ──
cat("\n━━━ β_FX deployment 판단 ━━━\n")
deploy_ok <- TRUE; reasons <- c()

# Criterion 1: PR-AUC monthend > 1.5x baseline
if (pa_me / base_me >= 1.5) {
  cat(sprintf("  ✅ Lift = %.2fx ≥ 1.5x (PASS)\n", pa_me / base_me))
} else {
  cat(sprintf("  ❌ Lift = %.2fx < 1.5x (FAIL)\n", pa_me / base_me))
  deploy_ok <- FALSE; reasons <- c(reasons, "lift_lt_1.5x")
}

# Criterion 2: Top 30% precision > baseline by 50%
top30_alert <- as.integer(me$p >= quantile(me$p, 0.7))
prec30 <- sum(top30_alert == 1 & me$y == 1) / max(sum(top30_alert), 1)
if (prec30 >= base_me * 1.5) {
  cat(sprintf("  ✅ Top 30%% precision = %.3f ≥ baseline*1.5 (%.3f) (PASS)\n",
              prec30, base_me * 1.5))
} else {
  cat(sprintf("  ❌ Top 30%% precision = %.3f < baseline*1.5 (%.3f) (FAIL)\n",
              prec30, base_me * 1.5))
  deploy_ok <- FALSE; reasons <- c(reasons, "top30_prec_lt_1.5x_baseline")
}

# Criterion 3: 95% CI overlap with daily
if (in_ci) {
  cat(sprintf("  ✅ Within daily 95%% CI (no distribution shift)\n"))
} else {
  cat(sprintf("  ⚠️ Outside daily 95%% CI (distribution shift)\n"))
  reasons <- c(reasons, "outside_daily_ci")
}

# Criterion 4: Calibration slope in [0.5, 2.0]
if (cal_slope >= 0.5 && cal_slope <= 2.0) {
  cat(sprintf("  ✅ Calibration slope = %.3f in [0.5, 2.0]\n", cal_slope))
} else {
  cat(sprintf("  ⚠️ Calibration slope = %.3f outside [0.5, 2.0]\n", cal_slope))
  reasons <- c(reasons, "cal_slope_out_of_range")
}

# Final
cat(sprintf("\n[VERDICT] β_FX deployment = %s\n",
            ifelse(deploy_ok, "PROCEED to next validation",
                   sprintf("BLOCK — reasons: %s", paste(reasons, collapse = ", ")))))

# ── (10) Save outputs ──
out <- list(
  daily_prauc = pa_daily, daily_baseline = base_daily,
  daily_ci_lo = ci_daily["lo.2.5%"], daily_ci_hi = ci_daily["hi.97.5%"],
  monthend_prauc = pa_me, monthend_baseline = base_me,
  monthend_ci_lo = ci_me["lo.2.5%"], monthend_ci_hi = ci_me["hi.97.5%"],
  monthend_in_daily_ci = in_ci,
  delta = pa_me - pa_daily,
  recent_24m_prauc = pa_r24, recent_24m_baseline = base_r24,
  recent_12m_prauc = pa_r12, recent_12m_baseline = base_r12,
  top30_precision = prec30,
  calibration_slope = unname(cal_slope),
  calibration_intercept = unname(cal_int),
  brier_skill_score = bss,
  deployment_verdict = ifelse(deploy_ok, "PROCEED", "BLOCK"),
  block_reasons = if (length(reasons) == 0) "none" else paste(reasons, collapse = ", "),
  n_months = nrow(me),
  total_events = sum(me$y),
  date_range_start = as.character(min(me$Date)),
  date_range_end = as.character(max(me$Date)),
  timestamp = as.character(Sys.time())
)
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
write_json(out, file.path(EVAL_DIR, "monthend_prauc_revalidation.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/monthend_prauc_revalidation.json\n", EVAL_DIR))

# ── (11) Chart: PR-AUC comparison + calibration ──
g1 <- ggplot(data.frame(
    type = c("Daily OOS", "Month-end", "Recent 24m", "Recent 12m"),
    pa = c(pa_daily, pa_me, pa_r24, pa_r12),
    base = c(base_daily, base_me, base_r24, base_r12)),
  aes(x = type)) +
  geom_col(aes(y = pa, fill = "PR-AUC"), alpha = 0.8, width = 0.5) +
  geom_col(aes(y = base, fill = "Baseline (prevalence)"), alpha = 0.5, width = 0.3) +
  scale_fill_manual(values = c("PR-AUC" = "#073B4C",
                                "Baseline (prevalence)" = "#FFD166"),
                    name = NULL) +
  geom_text(aes(y = pa + 0.02, label = sprintf("%.3f", pa)), size = 4) +
  labs(title = "PR-AUC: Daily vs Month-end subset",
       subtitle = sprintf("Daily %.3f / Monthend %.3f / Delta %+.3f / In CI: %s",
                          pa_daily, pa_me, pa_me - pa_daily,
                          ifelse(in_ci, "YES", "NO")),
       x = NULL, y = "PR-AUC") +
  theme_minimal(base_size = 11)

g2 <- ggplot(cal, aes(x = mean_p, y = obs_rate)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray50") +
  geom_point(size = 3, color = "#EF476F") +
  geom_smooth(method = "lm", se = FALSE, color = "#073B4C", linewidth = 0.5) +
  labs(title = "Calibration at month-end (decile bins)",
       subtitle = sprintf("Slope %.3f / Intercept %.3f / Brier Skill %.3f",
                          cal_slope, cal_int, bss),
       x = "Predicted probability (mean)", y = "Observed event rate") +
  theme_minimal(base_size = 11)

g_combined <- patchwork::wrap_plots(g1, g2, ncol = 1)
ggsave(file.path(CHART_DIR, "10_monthend_prauc.png"),
       plot = g_combined, width = 11, height = 8, dpi = 120)
cat(sprintf("[Chart 10] %s/10_monthend_prauc.png\n", CHART_DIR))

cat("\n[DONE]\n")
