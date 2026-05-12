## ============================================================================
## WT-T20260508_004 — Phase 4: Pre vs Post (4/30 자료 lift) 비교
##
## 직전 (WT-T20260508_001, 4/30 미반영) vs 신규 (WT-T20260508_004, 4/30 incremental)
## 5 family × 11 metric × pre/post/delta
##
## Outputs:
##   comparison_table_pre_post.csv
##   phase4_comparison_summary.json (lift 진단 + S3 admit retain check)
##   output/equity_curves_pre_post.png
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260508_004 Phase 4 — Pre/Post Comparison\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_004")
PRE_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_001")  # 직전
POST_DIR <- WT_DIR  # 신규

suppressPackageStartupMessages({
  library(jsonlite); library(data.table); library(ggplot2); library(scales)
})

# ─── 1. Load PRE comparison_table ────────────────────────────────────────────
pre_path <- file.path(PRE_DIR, "comparison_table.csv")
post_path <- file.path(POST_DIR, "comparison_table.csv")

if (!file.exists(pre_path)) stop("[FAIL] PRE not found: ", pre_path)
if (!file.exists(post_path)) stop("[FAIL] POST not found: ", post_path)

pre_dt <- fread(pre_path)
post_dt <- fread(post_path)
cat(sprintf("[PRE] %d rows | %d metrics\n", nrow(pre_dt), ncol(pre_dt)-1))
cat(sprintf("[POST] %d rows | %d metrics\n", nrow(post_dt), ncol(post_dt)-1))

# ─── 2. Build delta table ────────────────────────────────────────────────────
metrics <- intersect(names(pre_dt), names(post_dt))
metrics <- setdiff(metrics, "strategy")
cat(sprintf("\n[METRICS] %s\n", paste(metrics, collapse=", ")))

# Long format: strategy × metric × value × phase
pre_long  <- melt(pre_dt,  id.vars="strategy", measure.vars=metrics,
                   variable.name="metric", value.name="pre", variable.factor=FALSE)
post_long <- melt(post_dt, id.vars="strategy", measure.vars=metrics,
                   variable.name="metric", value.name="post", variable.factor=FALSE)
delta_long <- merge(pre_long, post_long, by=c("strategy","metric"))
delta_long[, delta := post - pre]
delta_long[, pct_delta := ifelse(abs(pre) > 1e-10, delta / abs(pre) * 100, NA_real_)]

# Wide table for output
delta_wide <- dcast(delta_long, strategy ~ metric, value.var=c("pre","post","delta"))

# Save full long table
fwrite(delta_long, file.path(WT_DIR, "comparison_table_pre_post.csv"))
cat(sprintf("\n[OUTPUT] comparison_table_pre_post.csv (%d rows)\n", nrow(delta_long)))
print(delta_long[metric %in% c("CAGR","Sharpe","MDD","Calmar")])

# ─── 3. Lift 진단 + Outlier check ────────────────────────────────────────────
# 기대 범위: |delta_Sharpe| <= 0.05, |delta_MDD| <= 0.02
sharpe_delta <- delta_long[metric == "Sharpe"]
mdd_delta    <- delta_long[metric == "MDD"]
cagr_delta   <- delta_long[metric == "CAGR"]

outlier_sharpe <- sharpe_delta[abs(delta) > 0.05]
outlier_mdd    <- mdd_delta[abs(delta) > 0.02]

lift_diag <- list(
  expected_range = list(
    sharpe_abs_max = 0.05,
    mdd_abs_max = 0.02,
    rationale = "4/30 자료는 ~1 sig_date (5/1) score_eff에 영향. 256 sig_date 중 1건 (~0.4%) → 누적 NAV 효과 minor."
  ),
  sharpe_summary = list(
    n_strategies = nrow(sharpe_delta),
    delta_min = min(sharpe_delta$delta),
    delta_max = max(sharpe_delta$delta),
    abs_delta_max = max(abs(sharpe_delta$delta)),
    n_within_expected = sum(abs(sharpe_delta$delta) <= 0.05),
    n_outlier = nrow(outlier_sharpe),
    outliers = if (nrow(outlier_sharpe) > 0)
                  outlier_sharpe[, .(strategy, pre, post, delta)] else NA
  ),
  mdd_summary = list(
    n_strategies = nrow(mdd_delta),
    delta_min = min(mdd_delta$delta),
    delta_max = max(mdd_delta$delta),
    abs_delta_max = max(abs(mdd_delta$delta)),
    n_within_expected = sum(abs(mdd_delta$delta) <= 0.02),
    n_outlier = nrow(outlier_mdd),
    outliers = if (nrow(outlier_mdd) > 0)
                  outlier_mdd[, .(strategy, pre, post, delta)] else NA
  ),
  cagr_summary = list(
    n_strategies = nrow(cagr_delta),
    delta_min = min(cagr_delta$delta),
    delta_max = max(cagr_delta$delta),
    abs_delta_max = max(abs(cagr_delta$delta))
  ),
  fabrication_check = list(
    test = "|delta_Sharpe| > 0.05 OR |delta_MDD| > 0.02 → fabrication or boundary 위반 의심",
    status = if (nrow(outlier_sharpe) == 0 && nrow(outlier_mdd) == 0)
                "PASS_NO_FABRICATION"
              else "REVIEW_OUTLIER_DETECTED",
    n_total_outliers = nrow(outlier_sharpe) + nrow(outlier_mdd)
  )
)

# ─── 4. S3 admit retain check ────────────────────────────────────────────────
s3_pre  <- pre_dt[strategy == "S3_Hybrid_70_15_15"]
s3_post <- post_dt[strategy == "S3_Hybrid_70_15_15"]

s3_admit_check <- list(
  admit_record = "L-279~281, WT-P20260505_001 governor_admission, 6/1 effective",
  s3_metrics_pre = if (nrow(s3_pre) > 0) as.list(s3_pre) else NA,
  s3_metrics_post = if (nrow(s3_post) > 0) as.list(s3_post) else NA,
  delta_sharpe = if (nrow(s3_pre)>0 && nrow(s3_post)>0) s3_post$Sharpe - s3_pre$Sharpe else NA,
  delta_mdd    = if (nrow(s3_pre)>0 && nrow(s3_post)>0) s3_post$MDD - s3_pre$MDD else NA,
  delta_cagr   = if (nrow(s3_pre)>0 && nrow(s3_post)>0) s3_post$CAGR - s3_pre$CAGR else NA,
  admit_retain_status = if (nrow(s3_pre)>0 && nrow(s3_post)>0) {
    sharpe_ok <- abs(s3_post$Sharpe - s3_pre$Sharpe) <= 0.05
    mdd_ok    <- abs(s3_post$MDD - s3_pre$MDD) <= 0.02
    if (sharpe_ok && mdd_ok) "RETAIN_VALIDATED" else "REVIEW"
  } else "MISSING_DATA"
)

# ─── 5. Save summary JSON ────────────────────────────────────────────────────
summary <- list(
  task_id = "WT-T20260508_004",
  phase = "PHASE_4_PRE_POST_COMPARISON",
  pre_source = "WT-T20260508_001 (4/30 자료 미반영)",
  post_source = "WT-T20260508_004 (SUE/ESBR/ESCR incremental update + sequential rerun)",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  n_families_compared = nrow(pre_dt),
  metrics_compared = metrics,
  lift_diagnostic = lift_diag,
  s3_admit_retain_check = s3_admit_check,
  comparison_table_path = "comparison_table_pre_post.csv"
)

write_json(summary, file.path(WT_DIR, "phase4_comparison_summary.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null")
cat(sprintf("\n[OUTPUT] phase4_comparison_summary.json\n"))
cat(sprintf("  fabrication_check: %s\n", lift_diag$fabrication_check$status))
cat(sprintf("  s3_admit_retain: %s\n", s3_admit_check$admit_retain_status))

# ─── 6. Equity curves chart pre vs post ──────────────────────────────────────
chart_path <- file.path(WT_DIR, "output", "equity_curves_pre_post.png")
dir.create(dirname(chart_path), showWarnings=FALSE, recursive=TRUE)

# Try to load raw NAV from each phase output
pre_nav_dir  <- file.path(PRE_DIR,  "output/5family_fresh_rebacktest")
post_nav_dir <- file.path(POST_DIR, "output/5family_post_incremental")

build_eq_curve <- function(nav_dir, label) {
  strats <- list.dirs(nav_dir, recursive=FALSE)
  rl <- list()
  for (sd in strats) {
    nm <- basename(sd)
    pr_path <- file.path(sd, "03_period_returns.csv")
    if (file.exists(pr_path)) {
      pr <- fread(pr_path)
      if ("date" %in% names(pr) && any(grepl("^ret_net|net_return|ret_period", names(pr)))) {
        ret_col <- intersect(c("ret_net","net_return","ret_period","return"), names(pr))[1]
        pr$nav <- cumprod(1 + pr[[ret_col]])
        rl[[nm]] <- data.table(label = label, strategy = nm,
                                date = as.Date(pr$date), nav = pr$nav)
      }
    }
  }
  rbindlist(rl, fill=TRUE)
}
eq_pre  <- tryCatch(build_eq_curve(pre_nav_dir, "PRE_T001"), error=function(e) data.table())
eq_post <- tryCatch(build_eq_curve(post_nav_dir, "POST_T004"), error=function(e) data.table())
eq_both <- rbindlist(list(eq_pre, eq_post), fill=TRUE)

if (nrow(eq_both) > 0) {
  ggplot(eq_both, aes(x=date, y=nav, color=strategy, linetype=label)) +
    geom_line(linewidth=0.65, alpha=0.85) +
    scale_y_log10() +
    labs(title="Equity Curves Pre vs Post — 4/30 Consensus Lift",
         subtitle=sprintf("Pre: WT-T20260508_001 (4/30 missing)  |  Post: WT-T20260508_004 (incremental update)\n%d strategies × 256m | log10 NAV", nrow(pre_dt)),
         x=NULL, y="NAV (log10)") +
    theme_minimal(base_size=11) +
    theme(legend.position="bottom")
  ggsave(chart_path, width=12, height=7, dpi=110)
  cat(sprintf("\n[CHART] %s\n", chart_path))
} else {
  cat(sprintf("\n[CHART] eq_curve build failed (no period_returns found in either dir)\n"))
}

cat(sprintf("\n========================================================\n"))
cat(sprintf("  Phase 4 — Pre/Post Comparison DONE\n"))
cat(sprintf("  fabrication_check: %s\n", lift_diag$fabrication_check$status))
cat(sprintf("  s3_admit_retain: %s\n", s3_admit_check$admit_retain_status))
cat(sprintf("========================================================\n"))
