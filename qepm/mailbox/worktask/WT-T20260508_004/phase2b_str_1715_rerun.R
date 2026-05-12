## ============================================================================
## WT-T20260508_004 — Phase 2b: STR_1715 base run_all.R rerun
##
## Pre-condition: Phase 2a alpha_scores.parquet regen complete
##
## Action:
##   - Backup STR_1715/output/02_nav.csv + 03_period_returns.csv (timestamp suffix)
##   - source('04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/run_all.R')
##   - run_all.R reads alpha_scores.parquet → walks 240+ monthly → writes 02_nav / 03_period_returns
##
## 추정 시간: ~10-20분 (walk-forward 240+ monthly)
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260508_004 Phase 2b — STR_1715 base rerun\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_004")
STR_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd")
OUT_DIR <- file.path(STR_DIR, "output")

setwd(STR_DIR)

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

# ─── Backup pre-rerun output files ───────────────────────────────────────────
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
files_to_backup <- c("02_nav.csv", "03_period_returns.csv", "06_metrics.csv",
                      "04_holdings.csv", "10_audit.csv", "bt_result.rds")
backup_md5_pre <- list()
for (f in files_to_backup) {
  src <- file.path(OUT_DIR, f)
  if (file.exists(src)) {
    bak <- file.path(OUT_DIR, sub("\\.([^.]+)$", paste0("_pre_WT004_incremental_", ts, ".\\1.bak"), f))
    file.copy(src, bak, overwrite = FALSE)
    backup_md5_pre[[f]] <- as.character(tools::md5sum(src))
    cat(sprintf("[BACKUP] %s | md5(pre): %s\n", f, substr(backup_md5_pre[[f]], 1, 16)))
  }
}

# ─── Execute run_all.R (STR_1715 base walk-forward) ─────────────────────────
cat(sprintf("\n[RERUN] Sourcing STR_1715/run_all.R...\n"))
t_start <- Sys.time()

result <- tryCatch({
  source("run_all.R", echo = FALSE, max.deparse.length = Inf)
  TRUE
}, error = function(e) {
  cat(sprintf("\n[FATAL] run_all.R error: %s\n", conditionMessage(e)))
  FALSE
})

# WT-T20260508_004 patch — STR_1715 [17.5] auto-update가 conditional bug로 SKIPPED 시
# bt_dt 변수가 globalenv에 살아있다면 직접 03_period_returns.csv + 02_nav.csv 갱신.
# (incremental SUE/ESBR/ESCR update 효과를 four_layer_comparison.R 다운스트림에 propagate)
if (isTRUE(result) && exists("bt_dt", envir = globalenv())) {
  cat("\n[WT004 PATCH] STR_1715 [17.5] SKIPPED 보완 — direct fwrite 03_period_returns.csv\n")
  bt_dt_g <- get("bt_dt", envir = globalenv())
  if (is.data.table(bt_dt_g) && nrow(bt_dt_g) > 0 && "period_end" %in% names(bt_dt_g)) {
    bt_dates_g <- as.Date(bt_dt_g$period_end)
    monthly_ret_g <- bt_dt_g$port_ret
    monthly_ret_gross_g <- if ("port_ret_gross" %in% names(bt_dt_g)) bt_dt_g$port_ret_gross else (monthly_ret_g + (bt_dt_g$cost %||% 0))
    weights_risk_g <- 1 - (bt_dt_g$cash_pct %||% 0)

    pr_dt <- data.table::data.table(
      run_id = sprintf("STR_1715_WT016_Iter31_WT004_%s", format(Sys.time(), "%Y%m%d_%H%M%S")),
      strategy_id = "STR_1715_WT016_Iter31_GridBestProd",
      date = bt_dates_g, frequency = "monthly",
      ret_gross = monthly_ret_gross_g, ret_net = monthly_ret_g,
      risk_free_ret = 0, excess_ret_net = monthly_ret_g,
      turnover = bt_dt_g$turnover %||% 0, cost_ret = bt_dt_g$cost %||% 0,
      cash_weight = bt_dt_g$cash_pct %||% 0, leverage = weights_risk_g,
      n_holdings = bt_dt_g$n_held %||% 20L
    )
    out_dir_g <- get("OUT_DIR", envir = globalenv())
    pr_path_g <- file.path(out_dir_g, "03_period_returns.csv")
    data.table::fwrite(pr_dt, pr_path_g)
    cat(sprintf("  [PATCH] 03_period_returns.csv fwrite OK: %d rows | %s ~ %s\n",
                nrow(pr_dt), min(bt_dates_g), max(bt_dates_g)))

    # 02_nav.csv도 함께 갱신
    nav_net_g <- 100 * cumprod(1 + monthly_ret_g)
    nav_gross_g <- 100 * cumprod(1 + monthly_ret_gross_g)
    nav_dt_g <- data.table::data.table(
      Date = bt_dates_g, NAV = nav_net_g, NAV_gross = nav_gross_g,
      cash_weight = bt_dt_g$cash_pct %||% 0, gross_exposure = weights_risk_g,
      net_exposure = weights_risk_g, leverage = weights_risk_g
    )
    nav_path_g <- file.path(out_dir_g, "02_nav.csv")
    data.table::fwrite(nav_dt_g, nav_path_g)
    cat(sprintf("  [PATCH] 02_nav.csv fwrite OK: %d rows\n", nrow(nav_dt_g)))
  } else {
    cat("  [PATCH] bt_dt 변수 형태 비정상 — fwrite skip\n")
    cat(sprintf("  bt_dt class=%s nrow=%s\n",
                class(bt_dt_g)[1], if(is.data.frame(bt_dt_g)) nrow(bt_dt_g) else "NA"))
  }
} else {
  cat("\n[WT004 PATCH] bt_dt 변수 globalenv 부재 — direct fwrite skip\n")
  cat(sprintf("  exists bt_dt: %s\n", exists("bt_dt", envir = globalenv())))
}

t_end <- Sys.time()
elapsed_min <- as.numeric(difftime(t_end, t_start, units = "mins"))
cat(sprintf("\n[RERUN] Complete | elapsed %.1f min\n", elapsed_min))

# ─── Post-rerun: collect new md5 + key metrics ──────────────────────────────
backup_md5_post <- list()
for (f in files_to_backup) {
  src <- file.path(OUT_DIR, f)
  if (file.exists(src)) {
    backup_md5_post[[f]] <- as.character(tools::md5sum(src))
  }
}

# Compare metrics if available
metrics_pre <- NULL
metrics_post <- NULL
nm <- "06_metrics.csv"
m_post_path <- file.path(OUT_DIR, nm)
m_pre_path <- file.path(OUT_DIR, sub("\\.([^.]+)$", paste0("_pre_WT004_incremental_", ts, ".\\1.bak"), nm))
if (file.exists(m_post_path)) metrics_post <- fread(m_post_path)
if (file.exists(m_pre_path)) metrics_pre <- fread(m_pre_path)

diag <- list(
  task_id = "WT-T20260508_004",
  phase = "PHASE_2B_STR_1715_RERUN",
  timestamp_start = format(t_start, "%Y-%m-%dT%H:%M:%S%z"),
  timestamp_end = format(t_end, "%Y-%m-%dT%H:%M:%S%z"),
  elapsed_min = round(elapsed_min, 2),
  status = if (isTRUE(result)) "PASS" else "FAIL",
  files_md5_pre = backup_md5_pre,
  files_md5_post = backup_md5_post,
  metrics_pre = if (!is.null(metrics_pre)) as.list(metrics_pre) else NA,
  metrics_post = if (!is.null(metrics_post)) as.list(metrics_post) else NA
)

write_json(diag, file.path(WT_DIR, "phase2b_str_1715_rerun_audit.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[AUDIT] Saved: %s\n", file.path(WT_DIR, "phase2b_str_1715_rerun_audit.json")))

cat(sprintf("\n========================================================\n"))
cat(sprintf("  Phase 2b STR_1715 rerun — DONE\n"))
cat(sprintf("  status: %s | %.1f min\n", diag$status, elapsed_min))
cat(sprintf("========================================================\n"))
