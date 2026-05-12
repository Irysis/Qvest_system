## ============================================================================
## WT-T20260508_004 — Phase 1: SUE/ESBR/ESCR Incremental Factor Update
##
## 도훈 정정 mandate (2026-05-08, post-_003):
##   "모든 팩터들을 다 재구축해달라는게 아니라 SUE, ESBR, ESCR만 다시 계산해달라"
##
## 본 스크립트 = INCREMENTAL COLUMN-LEVEL UPDATE only.
##   ❌ build_factor_db(force=TRUE) 사용 X — 모든 14 module 재호출
##   ✅ 기존 parquet 로드 → compute_consensus만 호출 → 영향 받는 factor row만 교체
##
## SUE/ESBR/ESCR derivative 10 factors (직접 의존):
##   C01_SUE                         (sue 직접)
##   C04_ESBR                        (esbr 직접)
##   C05_ESCR                        (escr 직접)
##   C09_Earnings_Surprise_Sq        (sue 의존)
##   C10_SUE_Persistence             (sue history)
##   C11_Earnings_Streak             (sue history)
##   C13_Revision_Breadth_3m         (esbr history)
##   C15_Forecast_Error_Trend        (sue history)
##   C18_Earnings_CAR_3d             (sue 의존, RAWDATA 부수)
##   C19_Composite_Earnings          (sue + esbr + EPS_chg + TP_Gap composite)
##
## NOTE on C19: composite uses C01/C04 along with C02 (eps_chg_1m) & C06 (TP_Gap).
##   C02/C06 자체는 변경 X → C19도 SUE/ESBR 갱신만큼 영향. 재계산 의무.
##
## NOT recomputed (기존 row 보존):
##   C02_EPS_Chg_1m, C03_EPS_Chg_3m, C06_TP_Gap, C07_TP_Mom, C08_Coverage,
##   C12_Estimate_Dispersion_Proxy, C14_Revenue_Surprise, C16_EPS_Acceleration,
##   C17_OP_Revision  (eps_chg / target_price / coverage / revenue / op_profit
##                      모두 SUE/ESBR/ESCR 비-의존)
##   + 다른 13 family (size/momentum/quality/value/defense/liquidity/accrual/
##                     risk/regime/crowding/growth/investor) 전체 row 보존
##
## Cross-sectional Z_Score / Z_Sector / Rank_Pct 처리:
##   변경되는 10 factor의 그 sig_date 내 cross-section만 재계산.
##   다른 factor는 row 그대로 retain (Z_Score는 within-Factor_Name이므로 영향 X).
##
## Output:
##   .cache/factor_db/factor_db_YYYYMM.parquet (in-place overwrite)
##   audit: WT/incremental_update_audit.json
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260508_004 Phase 1 — Incremental SUE/ESBR/ESCR Update\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_004")

setwd(PROJECT_ROOT)
source("02_Infrastructure/config.R")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ─── 직접 module load (build_factor_db_monthly 우회) ───────────────────────────
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/compute_consensus.R"))

# ─── Constants ────────────────────────────────────────────────────────────────
FDB_DIR <- file.path(CACHE_DIR, "factor_db")

# SUE/ESBR/ESCR-derived factor list (재계산 대상)
SUE_DERIVED <- c("C01_SUE", "C09_Earnings_Surprise_Sq", "C10_SUE_Persistence",
                  "C11_Earnings_Streak", "C15_Forecast_Error_Trend",
                  "C18_Earnings_CAR_3d")
ESBR_DERIVED <- c("C04_ESBR", "C13_Revision_Breadth_3m")
ESCR_DERIVED <- c("C05_ESCR")
COMPOSITE_DERIVED <- c("C19_Composite_Earnings")  # uses C01 + C04

TARGET_FACTORS <- c(SUE_DERIVED, ESBR_DERIVED, ESCR_DERIVED, COMPOSITE_DERIVED)
cat(sprintf("[CONFIG] Target factors (recompute): %d\n", length(TARGET_FACTORS)))
cat(sprintf("  SUE-derived (6):   %s\n", paste(SUE_DERIVED, collapse=", ")))
cat(sprintf("  ESBR-derived (2):  %s\n", paste(ESBR_DERIVED, collapse=", ")))
cat(sprintf("  ESCR-derived (1):  %s\n", paste(ESCR_DERIVED, collapse=", ")))
cat(sprintf("  Composite (1):     %s\n", paste(COMPOSITE_DERIVED, collapse=", ")))

# ─── Load base data (RAWDATA + CONSENSUS) ─────────────────────────────────────
cat("\n[LOAD] base data (RAWDATA + CONSENSUS)...\n")
RAWDATA <- as.data.table(read_parquet(RAWDATA_CACHE))
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
setkey(RAWDATA, Date, Ticker)
cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(RAWDATA), big.mark=","), min(RAWDATA$Date), max(RAWDATA$Date)))

CONSENSUS <- list()
cons_dir <- file.path(CACHE_DIR, "consensus")
cons_files <- list.files(cons_dir, pattern="\\.parquet$", full.names=TRUE)
for (cf in cons_files) {
  nm <- gsub("\\.parquet$", "", basename(cf))
  CONSENSUS[[nm]] <- as.data.table(read_parquet(cf))
  if ("Date" %in% names(CONSENSUS[[nm]]) && !inherits(CONSENSUS[[nm]]$Date, "Date")) {
    CONSENSUS[[nm]][, Date := as.Date(Date)]
  }
}
cat(sprintf("  CONSENSUS: %d tables (%s)\n",
            length(CONSENSUS), paste(names(CONSENSUS), collapse=", ")))

# Consensus cache md5 (audit)
cons_md5 <- list(
  sue  = as.character(tools::md5sum(file.path(cons_dir, "sue.parquet"))),
  esbr = as.character(tools::md5sum(file.path(cons_dir, "esbr.parquet"))),
  escr = as.character(tools::md5sum(file.path(cons_dir, "escr.parquet")))
)
cat("[INPUT MD5]\n")
for (nm in names(cons_md5)) cat(sprintf("  %s: %s\n", nm, cons_md5[[nm]]))

# ─── Pre-audit: list parquets + md5 ───────────────────────────────────────────
fdb_files <- sort(list.files(FDB_DIR, pattern="^factor_db_\\d{6}\\.parquet$",
                              full.names=TRUE))
cat(sprintf("\n[PRE-AUDIT] %d monthly parquets (%s ~ %s)\n",
            length(fdb_files),
            gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fdb_files[1])),
            gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fdb_files[length(fdb_files)]))))

pre_md5 <- vapply(fdb_files, function(f) as.character(tools::md5sum(f)), character(1))
names(pre_md5) <- basename(fdb_files)

# Hash of SUBSET-of-rows for "other factors" (invariance verification)
# 검증 대상: 각 parquet에서 NOT (Factor_Name %in% TARGET_FACTORS) row의 hash
# Phase 1 끝나고 post에서 동일 hash 확인 → "다른 factor 컬럼 invariance" 입증
cat(sprintf("\n[INVARIANCE PRE-HASH] computing 'other-factors' hash for invariance check (5 sample files)...\n"))
sample_idx <- round(seq(1, length(fdb_files), length.out=5))
invariance_pre <- list()
for (i in sample_idx) {
  fp <- fdb_files[i]
  ym <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", basename(fp))
  dt <- as.data.table(read_parquet(fp))
  other <- dt[!(Factor_Name %in% TARGET_FACTORS)]
  setorder(other, Date, Ticker, Factor_Name)
  invariance_pre[[ym]] <- digest::digest(other, algo="md5")
}
cat(sprintf("  Sample md5 (other-factors-only): %d files hashed\n", length(invariance_pre)))

# ─── Helper: cross-section z-score (per-factor within sig_date) ───────────────
.standardize_target <- function(dt_target, sector_map) {
  # dt_target: rows with Ticker, Factor_Name, Raw_Value (multiple Factor_Name OK)
  # sector_map: data.table(Ticker, Sector) at sig_date
  if (nrow(dt_target) == 0) return(dt_target)
  dt <- merge(dt_target, sector_map[, .(Ticker, Sector)], by="Ticker", all.x=TRUE)
  dt[, Coverage := !is.na(Raw_Value)]
  dt[, Z_Score := {
    vals <- Raw_Value
    mu <- mean(vals, na.rm=TRUE); s <- sd(vals, na.rm=TRUE)
    if (is.na(s) || s < 1e-12) rep(NA_real_, .N) else (vals-mu)/s
  }, by=Factor_Name]
  dt[, Z_Sector := {
    vals <- Raw_Value
    mu <- mean(vals, na.rm=TRUE); s <- sd(vals, na.rm=TRUE)
    if (is.na(s) || s < 1e-12) rep(NA_real_, .N) else (vals-mu)/s
  }, by=.(Factor_Name, Sector)]
  dt[, Rank_Pct := {
    vals <- Raw_Value
    r <- frank(vals, ties.method="average", na.last="keep")
    n_v <- sum(!is.na(vals))
    if (n_v > 1) (r-1)/(n_v-1) else rep(NA_real_, .N)
  }, by=Factor_Name]
  # Winsorize +/- 3 then re-standardize (factor_db_builder convention)
  dt[!is.na(Z_Score), Z_Score := pmin(pmax(Z_Score, -3), 3)]
  dt[!is.na(Z_Sector), Z_Sector := pmin(pmax(Z_Sector, -3), 3)]
  dt[!is.na(Z_Score), Z_Score := {
    s <- sd(Z_Score, na.rm=TRUE)
    if (!is.na(s) && s > 1e-12) Z_Score / s else Z_Score
  }, by=Factor_Name]
  dt[!is.na(Z_Sector), Z_Sector := {
    s <- sd(Z_Sector, na.rm=TRUE)
    if (!is.na(s) && s > 1e-12) Z_Sector / s else Z_Sector
  }, by=.(Factor_Name, Sector)]
  dt[, Sector := NULL]
  dt
}

# ─── Per-month incremental update function ────────────────────────────────────
update_one_parquet <- function(fp) {
  ym <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", basename(fp))
  ym_year  <- as.integer(substr(ym, 1, 4))
  ym_month <- as.integer(substr(ym, 5, 6))

  # Existing parquet 로드
  dt_old <- as.data.table(read_parquet(fp))
  if (nrow(dt_old) == 0) {
    return(list(ym=ym, status="EMPTY_SKIP", n_old_rows=0, n_new_rows=0))
  }
  if (!inherits(dt_old$Date, "Date")) dt_old[, Date := as.Date(Date)]

  # sig_date = max date in existing parquet (그 month-end 거래일)
  sig_d <- max(dt_old$Date)

  # Compute fresh consensus factors at sig_date
  fresh <- tryCatch(
    compute_consensus(RAWDATA = RAWDATA[Date <= sig_d & Date >= (sig_d - 400L)],
                      sig_date = sig_d,
                      FUND = NULL,
                      CONSENSUS = CONSENSUS),
    error = function(e) {
      cat(sprintf("    [ERROR] compute_consensus %s: %s\n", ym, conditionMessage(e)))
      data.table(Ticker=character(), Factor_Name=character(), Raw_Value=numeric())
    }
  )

  # Filter to TARGET_FACTORS only (도훈 mandate: 다른 consensus factor 변경 X)
  fresh_target <- fresh[Factor_Name %in% TARGET_FACTORS]
  if (nrow(fresh_target) == 0) {
    return(list(ym=ym, status="NO_TARGET_FRESH", n_old_rows=nrow(dt_old),
                n_old_target=sum(dt_old$Factor_Name %in% TARGET_FACTORS),
                n_new_rows=0))
  }

  # Sector map from RAWDATA snapshot at sig_date
  rd_snap <- RAWDATA[Date == sig_d]
  if (nrow(rd_snap) == 0) {
    avail <- sort(unique(RAWDATA$Date[RAWDATA$Date <= sig_d]))
    if (length(avail) > 0) rd_snap <- RAWDATA[Date == avail[length(avail)]]
  }
  if (nrow(rd_snap) == 0 || !"Sector" %in% names(rd_snap)) {
    return(list(ym=ym, status="NO_RAWDATA_SNAP", n_old_rows=nrow(dt_old), n_new_rows=0))
  }
  sector_map <- rd_snap[, .(Ticker, Sector)]

  # Standardize target rows
  fresh_std <- .standardize_target(fresh_target, sector_map)
  if (nrow(fresh_std) == 0) {
    return(list(ym=ym, status="STANDARDIZE_EMPTY", n_old_rows=nrow(dt_old), n_new_rows=0))
  }
  fresh_std[, Date := sig_d]
  setcolorder(fresh_std, c("Date", "Ticker", "Factor_Name", "Raw_Value",
                            "Z_Score", "Z_Sector", "Rank_Pct", "Coverage"))

  # Existing rows: keep all NOT in TARGET_FACTORS (다른 factor 보존)
  dt_keep <- dt_old[!(Factor_Name %in% TARGET_FACTORS)]
  n_old_target <- nrow(dt_old) - nrow(dt_keep)

  # Rebind: keep + fresh_std
  dt_new <- rbindlist(list(dt_keep, fresh_std), use.names=TRUE, fill=TRUE)

  # 정렬 + write
  setorder(dt_new, Date, Ticker, Factor_Name)
  write_parquet(dt_new, fp)

  list(
    ym = ym,
    sig_date = format(sig_d, "%Y-%m-%d"),
    status = "UPDATED",
    n_old_rows = nrow(dt_old),
    n_old_target = n_old_target,
    n_new_target = nrow(fresh_std),
    n_new_total = nrow(dt_new),
    n_other_kept = nrow(dt_keep),
    coverage_C01 = if ("C01_SUE" %in% fresh_std$Factor_Name)
                     round(100*mean(fresh_std[Factor_Name=="C01_SUE", Coverage]), 1) else NA,
    coverage_C04 = if ("C04_ESBR" %in% fresh_std$Factor_Name)
                     round(100*mean(fresh_std[Factor_Name=="C04_ESBR", Coverage]), 1) else NA,
    coverage_C05 = if ("C05_ESCR" %in% fresh_std$Factor_Name)
                     round(100*mean(fresh_std[Factor_Name=="C05_ESCR", Coverage]), 1) else NA
  )
}

# ─── Execute incremental update for ALL monthly parquets ──────────────────────
cat(sprintf("\n[UPDATE] %d monthly parquets — incremental SUE/ESBR/ESCR update\n",
            length(fdb_files)))
cat(sprintf("  Strategy: in-place column overwrite | other-factor rows preserved\n"))

t_start <- Sys.time()
update_log <- list()

for (i in seq_along(fdb_files)) {
  fp <- fdb_files[i]
  ym <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", basename(fp))
  if (i %% 25 == 1 || i == length(fdb_files)) {
    elapsed <- as.numeric(difftime(Sys.time(), t_start, units="secs"))
    eta <- if (i > 1) elapsed / (i-1) * (length(fdb_files) - i + 1) else NA
    cat(sprintf("  [%d/%d] %s | elapsed %.0fs | ETA %.0fs\n",
                i, length(fdb_files), ym, elapsed,
                ifelse(is.finite(eta), eta, 0)))
  }
  res <- update_one_parquet(fp)
  update_log[[ym]] <- res
}

t_end <- Sys.time()
elapsed_min <- as.numeric(difftime(t_end, t_start, units="mins"))
cat(sprintf("\n[UPDATE COMPLETE] Elapsed: %.1f min | %d files\n",
            elapsed_min, length(fdb_files)))

# ─── Post-audit: md5 + invariance verification ────────────────────────────────
cat("\n[POST-AUDIT] computing post-md5 + invariance check...\n")
post_md5 <- vapply(fdb_files, function(f) as.character(tools::md5sum(f)), character(1))
names(post_md5) <- basename(fdb_files)
n_changed <- sum(pre_md5 != post_md5)
n_unchanged <- sum(pre_md5 == post_md5)
cat(sprintf("  md5 changed: %d / %d files\n", n_changed, length(fdb_files)))

# Invariance verification on same sample files
invariance_post <- list()
invariance_match <- list()
for (i in sample_idx) {
  fp <- fdb_files[i]
  ym <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", basename(fp))
  dt <- as.data.table(read_parquet(fp))
  other <- dt[!(Factor_Name %in% TARGET_FACTORS)]
  setorder(other, Date, Ticker, Factor_Name)
  h_post <- digest::digest(other, algo="md5")
  invariance_post[[ym]] <- h_post
  invariance_match[[ym]] <- (h_post == invariance_pre[[ym]])
}
n_invariance_pass <- sum(unlist(invariance_match))
cat(sprintf("  Invariance check (other-factor rows): %d / %d files match\n",
            n_invariance_pass, length(invariance_match)))

# ─── Spot-check: 2026-04 + 2026-05 SUE/ESBR/ESCR ─────────────────────────────
spot_check <- list()
for (ym_check in c("202604", "202605")) {
  fp <- file.path(FDB_DIR, paste0("factor_db_", ym_check, ".parquet"))
  if (file.exists(fp)) {
    dt <- as.data.table(read_parquet(fp))
    spot_check[[ym_check]] <- list(
      n_total_rows = nrow(dt),
      n_C01_SUE = nrow(dt[Factor_Name == "C01_SUE"]),
      n_C04_ESBR = nrow(dt[Factor_Name == "C04_ESBR"]),
      n_C05_ESCR = nrow(dt[Factor_Name == "C05_ESCR"]),
      n_C19_Composite = nrow(dt[Factor_Name == "C19_Composite_Earnings"]),
      n_other_factors_unchanged = nrow(dt[!(Factor_Name %in% TARGET_FACTORS)]),
      sue_mean_raw = round(mean(dt[Factor_Name=="C01_SUE", Raw_Value], na.rm=TRUE), 4),
      esbr_mean_raw = round(mean(dt[Factor_Name=="C04_ESBR", Raw_Value], na.rm=TRUE), 4),
      escr_mean_raw = round(mean(dt[Factor_Name=="C05_ESCR", Raw_Value], na.rm=TRUE), 4)
    )
  }
}

# ─── Save full audit ──────────────────────────────────────────────────────────
audit <- list(
  phase = "PHASE_1_INCREMENTAL_SUE_ESBR_ESCR_UPDATE",
  task_id = "WT-T20260508_004",
  mandate = "도훈 정정 mandate 2026-05-08: SUE/ESBR/ESCR만 재계산. 다른 factor 건드리지 X.",
  approach = "incremental column-level update (NOT force=TRUE rebuild)",
  target_factors = list(
    sue_derived = SUE_DERIVED,
    esbr_derived = ESBR_DERIVED,
    escr_derived = ESCR_DERIVED,
    composite = COMPOSITE_DERIVED,
    total_count = length(TARGET_FACTORS)
  ),
  consensus_cache_md5_input = cons_md5,
  timestamp_start = format(t_start, "%Y-%m-%dT%H:%M:%S%z"),
  timestamp_end = format(t_end, "%Y-%m-%dT%H:%M:%S%z"),
  elapsed_min = round(elapsed_min, 2),
  n_files = length(fdb_files),
  n_md5_changed = n_changed,
  n_md5_unchanged = n_unchanged,
  invariance_check = list(
    n_sampled = length(invariance_pre),
    n_pass = n_invariance_pass,
    pre_hashes = invariance_pre,
    post_hashes = invariance_post,
    match = invariance_match
  ),
  spot_check_recent_months = spot_check,
  per_month_log = update_log,
  status = if (n_changed > 0 && n_invariance_pass == length(invariance_pre)) "PASS" else "REVIEW"
)
write_json(audit, file.path(WT_DIR, "incremental_update_audit.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null")
cat(sprintf("\n[AUDIT] Saved: %s\n", file.path(WT_DIR, "incremental_update_audit.json")))

# md5 delta CSV
delta_dt <- data.table(
  ym = gsub("factor_db_(\\d{6})\\.parquet", "\\1", names(pre_md5)),
  pre_md5 = pre_md5,
  post_md5 = post_md5,
  changed = pre_md5 != post_md5
)
fwrite(delta_dt, file.path(WT_DIR, "incremental_md5_delta.csv"))

cat(sprintf("\n========================================================\n"))
cat(sprintf("  Phase 1 Incremental Update — %s\n", audit$status))
cat(sprintf("  files=%d | changed=%d | invariance pass=%d/%d | %.1f min\n",
            length(fdb_files), n_changed, n_invariance_pass, length(invariance_pre), elapsed_min))
cat(sprintf("========================================================\n"))
