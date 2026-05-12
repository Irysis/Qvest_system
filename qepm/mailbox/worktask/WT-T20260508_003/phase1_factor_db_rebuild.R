## ============================================================================
## WT-T20260508_003 — Phase 1: Factor DB Full-Period Rebuild (force=TRUE)
##
## 도훈 mandate (2026-05-08 19:50 KST):
##   - Consensus cache (SUE/ESBR/ESCR) 4월 30일 자료까지 갱신 완료 (선행)
##   - Factor DB 전기간 재계산 → SUE/ESBR/ESCR 갱신 자동 propagate (consensus 모듈)
##   - 다른 factor (size/momentum/quality/...) 변경 X (compute_consensus.R만 영향)
##
## 효율성:
##   - 317 monthly cache (200001 ~ 202605) 재빌드 force=TRUE
##   - sequential build_factor_db_monthly() 호출
##   - 추정 시간: ~80-100분 (Apr 10 build 기준 확인)
##
## 출력:
##   - .cache/factor_db/factor_db_YYYYMM.parquet × 317 모두 갱신
##   - .cache/factor_db/build_hash.txt (timestamp + git hash)
##   - WT/factor_db_rebuild_log.txt (실행 로그)
##   - WT/factor_db_rebuild_audit.json (pre/post md5 + 효과 측정)
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260508_003 Phase 1 — Factor DB Full-Period Rebuild\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_003")

setwd(PROJECT_ROOT)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_builder.R")

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

# ─── Pre-rebuild audit (baseline md5) ────────────────────────────────────────
fdb_dir <- file.path(CACHE_DIR, "factor_db")
fdb_files_pre <- sort(list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                                  full.names = TRUE))
cat(sprintf("[PRE-AUDIT] Found %d existing monthly cache files (%s ~ %s)\n",
            length(fdb_files_pre),
            gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fdb_files_pre[1])),
            gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fdb_files_pre[length(fdb_files_pre)]))))

pre_md5 <- vapply(fdb_files_pre, function(f) as.character(tools::md5sum(f)), character(1))
names(pre_md5) <- basename(fdb_files_pre)

# Save pre-rebuild md5 as baseline
pre_audit <- list(
  phase = "PRE_REBUILD_BASELINE",
  timestamp_start = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  n_files_pre = length(fdb_files_pre),
  consensus_cache_md5 = list(
    sue = as.character(tools::md5sum(file.path(CACHE_DIR, "consensus/sue.parquet"))),
    esbr = as.character(tools::md5sum(file.path(CACHE_DIR, "consensus/esbr.parquet"))),
    escr = as.character(tools::md5sum(file.path(CACHE_DIR, "consensus/escr.parquet")))
  ),
  factor_db_md5_pre = as.list(pre_md5),
  alpha_scores_md5_pre = as.character(tools::md5sum(
    file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
)
write_json(pre_audit, file.path(WT_DIR, "factor_db_rebuild_pre_audit.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[PRE-AUDIT] Saved: %s\n", file.path(WT_DIR, "factor_db_rebuild_pre_audit.json")))

# ─── Determine date range ────────────────────────────────────────────────────
# Earliest cache: 200001 (2000-01-31)
# Latest cache: 202605 (2026-05-30+)
# build_factor_db_monthly은 month-end 거래일을 sig_date로 사용

START_D <- as.Date("2000-01-01")
END_D   <- Sys.Date()  # 2026-05-08

cat(sprintf("\n[REBUILD] Range: %s ~ %s (force=TRUE)\n", START_D, END_D))
cat(sprintf("  Estimated time: ~80-100 min (317 month-ends)\n"))
cat(sprintf("  WARNING: This OVERWRITES all existing monthly cache.\n"))
cat(sprintf("  Reason: SUE/ESBR/ESCR consensus cache regen (Apr 30 data) propagates ONLY via re-computation.\n\n"))

# ─── Execute rebuild ─────────────────────────────────────────────────────────
t_rebuild_start <- Sys.time()

result <- tryCatch(
  build_factor_db_monthly(
    start_date = format(START_D, "%Y-%m-%d"),
    end_date   = format(END_D, "%Y-%m-%d"),
    force      = TRUE
  ),
  error = function(e) {
    cat(sprintf("\n[FATAL] build_factor_db_monthly error: %s\n", conditionMessage(e)))
    NULL
  }
)

t_rebuild_end <- Sys.time()
elapsed_min <- as.numeric(difftime(t_rebuild_end, t_rebuild_start, units = "mins"))

cat(sprintf("\n[REBUILD COMPLETE] Elapsed: %.1f min\n", elapsed_min))

# ─── Post-rebuild audit ──────────────────────────────────────────────────────
fdb_files_post <- sort(list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                                   full.names = TRUE))
post_md5 <- vapply(fdb_files_post, function(f) as.character(tools::md5sum(f)), character(1))
names(post_md5) <- basename(fdb_files_post)

# Compare pre vs post — count changed files
common_names <- intersect(names(pre_md5), names(post_md5))
n_changed <- sum(pre_md5[common_names] != post_md5[common_names])
n_unchanged <- length(common_names) - n_changed
n_new <- length(setdiff(names(post_md5), names(pre_md5)))
n_dropped <- length(setdiff(names(pre_md5), names(post_md5)))

cat(sprintf("\n[POST-AUDIT] %d common | %d changed | %d unchanged | %d new | %d dropped\n",
            length(common_names), n_changed, n_unchanged, n_new, n_dropped))

# ─── Spot-check: SUE coverage on a recent month ─────────────────────────────
# Verify that consensus update propagated correctly
spot_check <- list()
for (ym_check in c("202604", "202605")) {
  fp <- file.path(fdb_dir, paste0("factor_db_", ym_check, ".parquet"))
  if (file.exists(fp)) {
    dt <- as.data.table(arrow::read_parquet(fp))
    sue_rows <- dt[Factor_Name == "C01_SUE"]
    esbr_rows <- dt[Factor_Name == "C04_ESBR"]
    escr_rows <- dt[Factor_Name == "C05_ESCR"]
    spot_check[[ym_check]] <- list(
      n_total = nrow(dt),
      sue_n = nrow(sue_rows),
      sue_coverage_pct = if (nrow(sue_rows) > 0) round(100*mean(sue_rows$Coverage), 1) else NA,
      sue_mean_raw = if (nrow(sue_rows) > 0) round(mean(sue_rows$Raw_Value, na.rm=TRUE), 4) else NA,
      esbr_n = nrow(esbr_rows),
      esbr_coverage_pct = if (nrow(esbr_rows) > 0) round(100*mean(esbr_rows$Coverage), 1) else NA,
      esbr_mean_raw = if (nrow(esbr_rows) > 0) round(mean(esbr_rows$Raw_Value, na.rm=TRUE), 4) else NA,
      escr_n = nrow(escr_rows),
      escr_coverage_pct = if (nrow(escr_rows) > 0) round(100*mean(escr_rows$Coverage), 1) else NA
    )
  }
}

# ─── Save full audit ─────────────────────────────────────────────────────────
audit <- list(
  phase = "PHASE_1_FACTOR_DB_REBUILD",
  task_id = "WT-T20260508_003",
  timestamp_start = format(t_rebuild_start, "%Y-%m-%dT%H:%M:%S%z"),
  timestamp_end = format(t_rebuild_end, "%Y-%m-%dT%H:%M:%S%z"),
  elapsed_min = round(elapsed_min, 2),
  date_range = list(start = format(START_D, "%Y-%m-%d"),
                    end = format(END_D, "%Y-%m-%d")),
  n_month_ends_processed = if (!is.null(result)) length(result) else NA,
  n_files_pre = length(fdb_files_pre),
  n_files_post = length(fdb_files_post),
  n_changed = n_changed,
  n_unchanged = n_unchanged,
  n_new = n_new,
  consensus_cache_md5_input = pre_audit$consensus_cache_md5,
  spot_check_recent_months = spot_check,
  status = if (!is.null(result) && length(result) > 0) "PASS" else "FAIL"
)

write_json(audit, file.path(WT_DIR, "factor_db_rebuild_audit.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[AUDIT] Saved: %s\n", file.path(WT_DIR, "factor_db_rebuild_audit.json")))

# Save delta summary CSV
delta_dt <- data.table(
  ym = gsub("factor_db_(\\d{6})\\.parquet", "\\1", common_names),
  pre_md5 = pre_md5[common_names],
  post_md5 = post_md5[common_names],
  changed = pre_md5[common_names] != post_md5[common_names]
)
fwrite(delta_dt, file.path(WT_DIR, "factor_db_rebuild_md5_delta.csv"))
cat(sprintf("[AUDIT] md5 delta CSV: %s\n",
            file.path(WT_DIR, "factor_db_rebuild_md5_delta.csv")))

cat(sprintf("\n========================================================\n"))
cat(sprintf("  Phase 1 Factor DB Rebuild — DONE\n"))
cat(sprintf("  status: %s | %.1f min\n", audit$status, elapsed_min))
cat(sprintf("========================================================\n"))
