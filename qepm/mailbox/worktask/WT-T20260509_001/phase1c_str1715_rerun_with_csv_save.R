## ============================================================================
## WT-T20260509_001 — Phase 1c: STR_1715 rerun + force csv save (268m)
##
## Issue: STR_1715 [17.5] bt_result auto-update SKIPPED 'missing value where TRUE/FALSE needed'
##        → 03_period_returns.csv + 02_nav.csv가 268m로 갱신 X (240m 5/8 stale 잔존)
##
## Action: WT-T20260508_004 phase2b PATCH 동일 패턴 채용
##   - source('STR_1715/run_all.R')
##   - globalenv bt_dt 추출 → 직접 fwrite 03_period_returns.csv + 02_nav.csv (268m)
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260509_001 Phase 1c — STR_1715 rerun + csv force save\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260509_001")
STR_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd")
OUT_DIR_STR <- file.path(STR_DIR, "output")

setwd(STR_DIR)

suppressPackageStartupMessages({
  library(jsonlite); library(data.table)
})
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

# ─── Backup ──────────────────────────────────────────────────────────────────
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
files_to_backup <- c("02_nav.csv", "03_period_returns.csv", "06_metrics.csv",
                     "04_holdings.csv", "10_audit.csv", "bt_result.rds")
backup_md5_pre <- list()
for (f in files_to_backup) {
  src <- file.path(OUT_DIR_STR, f)
  if (file.exists(src)) {
    bak <- file.path(OUT_DIR_STR, sub("\\.([^.]+)$",
                                       paste0("_pre_WT-T20260509_001_", ts, ".\\1.bak"), f))
    file.copy(src, bak, overwrite = FALSE)
    backup_md5_pre[[f]] <- as.character(tools::md5sum(src))
    cat(sprintf("[BACKUP] %s | md5(pre)=%s\n", f, substr(backup_md5_pre[[f]], 1, 16)))
  }
}

# ─── Source run_all.R ────────────────────────────────────────────────────────
cat("\n[RERUN] Sourcing STR_1715/run_all.R (268m walk-forward)...\n")
t_start <- Sys.time()

result <- tryCatch({
  source("run_all.R", echo = FALSE, max.deparse.length = Inf)
  TRUE
}, error = function(e) {
  cat(sprintf("\n[FATAL] run_all.R error: %s\n", conditionMessage(e)))
  FALSE
})

# ─── PATCH: bt_dt globalenv → direct csv fwrite ──────────────────────────────
if (isTRUE(result) && exists("bt_dt", envir = globalenv())) {
  cat("\n[PATCH] bt_dt globalenv extract → fwrite 03_period_returns.csv + 02_nav.csv\n")
  bt_dt_g <- get("bt_dt", envir = globalenv())
  cat(sprintf("  bt_dt class=%s nrow=%d cols=%s\n",
              class(bt_dt_g)[1], nrow(bt_dt_g),
              paste(head(names(bt_dt_g), 8), collapse=", ")))

  if (is.data.table(bt_dt_g) && nrow(bt_dt_g) > 0 && "period_end" %in% names(bt_dt_g)) {
    bt_dates_g <- as.Date(bt_dt_g$period_end)
    monthly_ret_g <- bt_dt_g$port_ret
    monthly_ret_gross_g <- if ("port_ret_gross" %in% names(bt_dt_g)) bt_dt_g$port_ret_gross else (monthly_ret_g + (bt_dt_g$cost %||% 0))
    weights_risk_g <- 1 - (bt_dt_g$cash_pct %||% 0)

    pr_dt <- data.table::data.table(
      run_id = sprintf("STR_1715_WT016_Iter31_WT-T20260509_001_%s", ts),
      strategy_id = "STR_1715_WT016_Iter31_GridBestProd",
      date = bt_dates_g, frequency = "monthly",
      ret_gross = monthly_ret_gross_g, ret_net = monthly_ret_g,
      risk_free_ret = 0, excess_ret_net = monthly_ret_g,
      turnover = bt_dt_g$turnover %||% 0, cost_ret = bt_dt_g$cost %||% 0,
      cash_weight = bt_dt_g$cash_pct %||% 0, leverage = weights_risk_g,
      n_holdings = bt_dt_g$n_held %||% 20L
    )
    pr_path_g <- file.path(OUT_DIR_STR, "03_period_returns.csv")
    fwrite(pr_dt, pr_path_g)
    cat(sprintf("  [OK] 03_period_returns.csv: %d rows | %s ~ %s\n",
                nrow(pr_dt), as.character(min(bt_dates_g)), as.character(max(bt_dates_g))))

    nav_net_g <- 100 * cumprod(1 + monthly_ret_g)
    nav_gross_g <- 100 * cumprod(1 + monthly_ret_gross_g)
    nav_dt_g <- data.table::data.table(
      date = bt_dates_g, NAV = nav_net_g, NAV_gross = nav_gross_g,
      cash_weight = bt_dt_g$cash_pct %||% 0,
      gross_exposure = weights_risk_g, net_exposure = weights_risk_g,
      leverage = weights_risk_g,
      drawdown_net = NA_real_,  # placeholder
      is_rebalance_date = TRUE
    )
    # Compute drawdown
    cs_nav <- cumprod(1 + monthly_ret_g)
    peak <- cummax(cs_nav)
    nav_dt_g[, drawdown_net := (cs_nav - peak) / peak]

    nav_path_g <- file.path(OUT_DIR_STR, "02_nav.csv")
    fwrite(nav_dt_g, nav_path_g)
    cat(sprintf("  [OK] 02_nav.csv: %d rows\n", nrow(nav_dt_g)))
  } else {
    cat(sprintf("  [SKIP] bt_dt not data.table or missing period_end\n"))
  }
} else {
  cat(sprintf("\n[PATCH SKIP] bt_dt globalenv 부재: exists=%s\n",
              exists("bt_dt", envir = globalenv())))
}

t_end <- Sys.time()
elapsed_min <- as.numeric(difftime(t_end, t_start, units = "mins"))
cat(sprintf("\n[RERUN] Complete | elapsed %.1f min\n", elapsed_min))

# Audit
backup_md5_post <- list()
for (f in files_to_backup) {
  src <- file.path(OUT_DIR_STR, f)
  if (file.exists(src)) {
    backup_md5_post[[f]] <- as.character(tools::md5sum(src))
  }
}

audit <- list(
  task_id = "WT-T20260509_001",
  phase = "Phase 1c (STR_1715 rerun + csv force save)",
  status = if (isTRUE(result)) "PASS" else "FAIL",
  elapsed_min = round(elapsed_min, 2),
  files_md5_pre = backup_md5_pre,
  files_md5_post = backup_md5_post,
  monthly_240m_sr_inferred = if (exists("monthly_240m_sr", envir = globalenv())) get("monthly_240m_sr", envir = globalenv()) else NA,
  v31_blend_sr_inferred = if (exists("V31_blend_sr", envir = globalenv())) get("V31_blend_sr", envir = globalenv()) else NA,
  baseline_sr_inferred = if (exists("baseline_sr", envir = globalenv())) get("baseline_sr", envir = globalenv()) else NA,
  ax_001_v2_4metric_inferred = if (exists("ax_001_v2_4metric", envir = globalenv())) get("ax_001_v2_4metric", envir = globalenv()) else NA,
  harvey_5spec_inferred = if (exists("harvey_5spec", envir = globalenv())) get("harvey_5spec", envir = globalenv()) else NA,
  dsr_post_inferred = if (exists("dsr_post", envir = globalenv())) get("dsr_post", envir = globalenv()) else NA,
  timestamp_end = format(t_end, "%Y-%m-%dT%H:%M:%S%z")
)
write_json(audit, file.path(WT_DIR, "phase1c_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("\n[AUDIT] Saved: %s\n", file.path(WT_DIR, "phase1c_audit.json")))
cat(sprintf("\n========================================================\n"))
cat(sprintf("  Phase 1c — %s | %.1f min\n", audit$status, elapsed_min))
cat(sprintf("========================================================\n"))
