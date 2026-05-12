## ============================================================================
## WT-T20260508_003 — Phase 2b: STR_1715 base run_all.R rerun
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
cat("  WT-T20260508_003 Phase 2b — STR_1715 base rerun\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_003")
STR_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd")
OUT_DIR <- file.path(STR_DIR, "output")

setwd(STR_DIR)

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

# ─── Backup pre-rerun output files ───────────────────────────────────────────
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
files_to_backup <- c("02_nav.csv", "03_period_returns.csv", "06_metrics.csv",
                      "04_holdings.csv", "10_audit.csv", "bt_result.rds")
backup_md5_pre <- list()
for (f in files_to_backup) {
  src <- file.path(OUT_DIR, f)
  if (file.exists(src)) {
    bak <- file.path(OUT_DIR, sub("\\.([^.]+)$", paste0("_pre_factor_db_rebuild_", ts, ".\\1.bak"), f))
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
m_pre_path <- file.path(OUT_DIR, sub("\\.([^.]+)$", paste0("_pre_factor_db_rebuild_", ts, ".\\1.bak"), nm))
if (file.exists(m_post_path)) metrics_post <- fread(m_post_path)
if (file.exists(m_pre_path)) metrics_pre <- fread(m_pre_path)

diag <- list(
  task_id = "WT-T20260508_003",
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
