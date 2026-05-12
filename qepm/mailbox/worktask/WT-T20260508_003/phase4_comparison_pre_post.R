## ============================================================================
## WT-T20260508_003 — Phase 4: 직전(WT_001) vs 신규(WT_003) 정량 비교
##
## Pre-condition: Phase 3 5family backtest 완료 (post Factor DB rebuild)
##
## Output:
##   - comparison_table_pre_post.csv (5 family × 11 metrics × pre/post/delta)
##   - phase4_comparison_summary.json (4/30 lift 정량 + 진단)
##   - output/equity_curves_pre_post.png (overlay equity curves)
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260508_003 Phase 4 — 직전 vs 신규 정량 비교\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_003")
PRE_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_001")
PRE_5F  <- file.path(PRE_DIR, "output/5family_fresh_rebacktest")
POST_5F <- file.path(WT_DIR, "output/5family_post_factor_db_rebuild")

setwd(PROJECT_ROOT)

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(ggplot2)
  library(scales)
})

# ─── Load pre comparison table (WT_001) ──────────────────────────────────────
pre_path <- file.path(PRE_DIR, "comparison_table.csv")
post_path <- file.path(WT_DIR, "comparison_table.csv")

pre <- fread(pre_path)
post <- fread(post_path)

setnames(pre, names(pre)[-1], paste0(names(pre)[-1], "_pre"))
setnames(post, names(post)[-1], paste0(names(post)[-1], "_post"))

cmp <- merge(pre, post, by = "strategy")

# Compute delta (post - pre)
metric_cols <- gsub("_pre$", "", grep("_pre$", names(cmp), value = TRUE))
for (m in metric_cols) {
  cmp[[paste0("delta_", m)]] <- cmp[[paste0(m, "_post")]] - cmp[[paste0(m, "_pre")]]
}

# Reorder: strategy + per-metric (pre, post, delta)
out_cols <- c("strategy")
for (m in metric_cols) {
  out_cols <- c(out_cols, paste0(m, "_pre"), paste0(m, "_post"), paste0("delta_", m))
}
cmp <- cmp[, ..out_cols]

fwrite(cmp, file.path(WT_DIR, "comparison_table_pre_post.csv"))
cat("[OUTPUT] comparison_table_pre_post.csv\n")
print(cmp[, .(strategy, Sharpe_pre, Sharpe_post, delta_Sharpe,
                 CAGR_pre, CAGR_post, delta_CAGR,
                 MDD_pre, MDD_post, delta_MDD)])

# ─── Equity curves overlay ──────────────────────────────────────────────────
load_nav <- function(base, family, label_prefix) {
  pr_path <- file.path(base, family, "03_period_returns.csv")
  if (!file.exists(pr_path)) return(NULL)
  dt <- fread(pr_path)
  if ("date" %in% names(dt) && "ret_net" %in% names(dt)) {
    setorder(dt, date)
    dt[, nav := cumprod(1 + ret_net)]
    dt[, run := label_prefix]
    dt[, strategy := family]
    return(dt[, .(date, nav, run, strategy)])
  }
  NULL
}

eq_data <- rbindlist(c(
  lapply(c("S0_baseline","S1_KR10y_only","S2_TSMOM_only","S3_Hybrid_70_15_15","S4_Hybrid_50_25_25"),
         function(f) load_nav(PRE_5F, f, "pre_WT_001")),
  lapply(c("S0_baseline","S1_KR10y_only","S2_TSMOM_only","S3_Hybrid_70_15_15","S4_Hybrid_50_25_25"),
         function(f) load_nav(POST_5F, f, "post_WT_003"))
), fill = TRUE)

if (nrow(eq_data) > 0) {
  eq_data[, date := as.Date(date)]
  ggplot(eq_data, aes(x = date, y = nav, color = strategy, linetype = run)) +
    geom_line(linewidth = 0.6, alpha = 0.85) +
    scale_y_log10() +
    labs(title = "Equity Curves — pre (WT_001) vs post (WT_003 Factor DB rebuild)",
         subtitle = "Log scale | 256m walk-forward | 4월 30일 자료 lift 시각화",
         x = NULL, y = "NAV (log10)") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom",
          legend.box = "vertical")
  ggsave(file.path(WT_DIR, "output/equity_curves_pre_post.png"),
         width = 11, height = 7, dpi = 110)
  cat("[OUTPUT] equity_curves_pre_post.png\n")
}

# ─── Lift summary 진단 ──────────────────────────────────────────────────────
diag <- list(
  task_id = "WT-T20260508_003",
  phase = "PHASE_4_COMPARISON_PRE_POST",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  pre_source = list(
    wt = "WT-T20260508_001",
    description = "5family fresh re-backtest (직전 cycle, pre-Factor DB rebuild — Apr 30 자료 미반영 alpha_scores)"),
  post_source = list(
    wt = "WT-T20260508_003",
    description = "5family re-backtest (신규 cycle, post Factor DB rebuild — Apr 30 자료 propagate alpha_scores)"),
  per_family_lift = lapply(seq_len(nrow(cmp)), function(i) {
    list(
      strategy = cmp$strategy[i],
      Sharpe_pre = round(cmp$Sharpe_pre[i], 4),
      Sharpe_post = round(cmp$Sharpe_post[i], 4),
      delta_Sharpe = round(cmp$delta_Sharpe[i], 4),
      CAGR_pre = round(cmp$CAGR_pre[i], 4),
      CAGR_post = round(cmp$CAGR_post[i], 4),
      delta_CAGR = round(cmp$delta_CAGR[i], 4),
      MDD_pre = round(cmp$MDD_pre[i], 4),
      MDD_post = round(cmp$MDD_post[i], 4),
      delta_MDD = round(cmp$delta_MDD[i], 4)
    )
  }),
  s3_admit_retain_check = {
    s3_row <- cmp[strategy == "S3_Hybrid_70_15_15"]
    if (nrow(s3_row) == 1) {
      delta_sr <- s3_row$delta_Sharpe
      delta_mdd <- s3_row$delta_MDD
      pareto_dominated <- (delta_sr < -0.05) || (delta_mdd > 0.02)
      list(
        delta_Sharpe = delta_sr,
        delta_MDD = delta_mdd,
        pareto_dominated_post_rebuild = pareto_dominated,
        admit_retain_recommendation = if (!pareto_dominated) "RETAIN — 4/30 자료 lift 정합 (S3 admit 6/1 effective 변경 X)" else "REVIEW — Pareto 악화 확인, 도훈 escalate"
      )
    } else NA
  }
)

write_json(diag, file.path(WT_DIR, "phase4_comparison_summary.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[OUTPUT] phase4_comparison_summary.json\n")

cat("\n========================================================\n")
cat("  Phase 4 비교 — DONE\n")
cat("========================================================\n")
