## ============================================================================
## WT-T20260508_003 — Phase 2c: Layer A (ret_AR_on_M4) Regeneration
##
## Pre-condition: Phase 2b STR_1715 base rerun complete
##                (02_nav.csv + 03_period_returns.csv 갱신 완료)
##
## Action:
##   - Backup WT-P20260504_001/four_layer_returns_path.csv
##   - source('qepm/mailbox/worktask/WT-P20260504_001/four_layer_comparison.R')
##   - Generates fresh four_layer_returns_path.csv with new ret_AR_on_M4
##
## 추정 시간: ~3-5분
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260508_003 Phase 2c — Layer A (ret_AR_on_M4) Regen\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_003")
LAYER_A_WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260504_001")

setwd(LAYER_A_WT_DIR)

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

# ─── Backup pre-rerun returns path ───────────────────────────────────────────
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
src <- file.path(LAYER_A_WT_DIR, "four_layer_returns_path.csv")
bak <- file.path(LAYER_A_WT_DIR, paste0("four_layer_returns_path_pre_factor_db_rebuild_", ts, ".csv.bak"))
pre_md5 <- NA_character_
if (file.exists(src)) {
  file.copy(src, bak, overwrite = FALSE)
  pre_md5 <- as.character(tools::md5sum(src))
  cat(sprintf("[BACKUP] %s | md5(pre): %s\n", basename(src), substr(pre_md5, 1, 16)))
}

# ─── Source four_layer_comparison.R ──────────────────────────────────────────
cat(sprintf("\n[REGEN] Sourcing four_layer_comparison.R...\n"))
t_start <- Sys.time()

result <- tryCatch({
  source("four_layer_comparison.R", echo = FALSE, max.deparse.length = Inf)
  TRUE
}, error = function(e) {
  cat(sprintf("\n[FATAL] four_layer_comparison.R error: %s\n", conditionMessage(e)))
  FALSE
})

t_end <- Sys.time()
elapsed_min <- as.numeric(difftime(t_end, t_start, units = "mins"))
cat(sprintf("\n[REGEN] Complete | elapsed %.1f min\n", elapsed_min))

# ─── Verify ──────────────────────────────────────────────────────────────────
post_md5 <- if (file.exists(src)) as.character(tools::md5sum(src)) else NA_character_
changed <- !is.na(pre_md5) && !is.na(post_md5) && (pre_md5 != post_md5)

dt_post <- if (file.exists(src)) fread(src) else data.table()

diag <- list(
  task_id = "WT-T20260508_003",
  phase = "PHASE_2C_LAYER_A_REGEN",
  timestamp_start = format(t_start, "%Y-%m-%dT%H:%M:%S%z"),
  timestamp_end = format(t_end, "%Y-%m-%dT%H:%M:%S%z"),
  elapsed_min = round(elapsed_min, 2),
  status = if (isTRUE(result)) "PASS" else "FAIL",
  pre_md5 = pre_md5,
  post_md5 = post_md5,
  changed = changed,
  n_rows = nrow(dt_post),
  date_range = if (nrow(dt_post) > 0) list(min = as.character(min(dt_post$date)),
                                            max = as.character(max(dt_post$date))) else NA,
  ret_AR_on_M4_summary = if ("ret_AR_on_M4" %in% names(dt_post)) list(
    mean = round(mean(dt_post$ret_AR_on_M4, na.rm=TRUE), 6),
    sd = round(sd(dt_post$ret_AR_on_M4, na.rm=TRUE), 6),
    sum_finite = sum(is.finite(dt_post$ret_AR_on_M4))
  ) else NA
)

# Compare to backup if exists
if (file.exists(bak)) {
  dt_pre <- fread(bak)
  setkey(dt_pre, date)
  setkey(dt_post, date)
  common <- merge(dt_pre[, .(date, pre = ret_AR_on_M4)],
                  dt_post[, .(date, post = ret_AR_on_M4)],
                  by = "date")
  if (nrow(common) > 0 && all(c("pre", "post") %in% names(common))) {
    common[, delta := post - pre]
    cf <- common[is.finite(delta)]
    diag$ret_AR_on_M4_delta <- list(
      n_compared = nrow(cf),
      mean_delta = round(mean(cf$delta), 6),
      mean_abs_delta = round(mean(abs(cf$delta)), 6),
      max_abs_delta = round(max(abs(cf$delta)), 6),
      cor_pre_post = round(cor(cf$pre, cf$post, use="complete.obs"), 6),
      pct_unchanged_lt_1e6 = round(100*mean(abs(cf$delta) < 1e-6), 2)
    )
  }
}

write_json(diag, file.path(WT_DIR, "phase2c_layer_a_regen_audit.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[AUDIT] Saved: %s\n", file.path(WT_DIR, "phase2c_layer_a_regen_audit.json")))

cat(sprintf("\n========================================================\n"))
cat(sprintf("  Phase 2c Layer A Regen — DONE\n"))
cat(sprintf("  status: %s | %.1f min\n", diag$status, elapsed_min))
cat(sprintf("========================================================\n"))
