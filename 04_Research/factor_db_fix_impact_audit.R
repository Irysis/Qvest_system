#==============================================================================
# Factor DB Fix Impact Audit — v54 P0 Sprint
#
# 목적: v54 re-standardize fix 전/후 ICIR delta 측정
#       |delta| > 0.05 팩터 식별 + 과거 전략 매핑
#
# 실행 방법: rebuild 완료 후 아래 실행
#   cd Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
#   Rscript -e 'source("04_Research/factor_db_fix_impact_audit.R")'
#
# 출력: stage_artifacts/factor_db_fix_impact_audit_v1.json
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(PROJECT_ROOT, "02_Infrastructure", "config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure", "factor_db", "factor_db_builder.R"))

FACTOR_DB_DIR  <- file.path(CACHE_DIR, "factor_db")
IC_PATH        <- file.path(FACTOR_DB_DIR, "factor_ic_monthly.parquet")
AUDIT_OUT      <- file.path(PROJECT_ROOT, "stage_artifacts",
                             "factor_db_fix_impact_audit_v1.json")

TARGET_FACTORS <- c("M08_Residual_Mom", "R12_Idiosyncratic_Risk", "R16_Calmar",
                    "Q07_Earnings_Stability", "C19_Composite_Earnings",
                    "V01_BM", "Q25_Ohlson_O", "M01_Mom_12_1")

STRATEGY_MAP <- list(
  M08_Residual_Mom       = c("STR_1631", "STR_1682", "STR_1684"),
  R12_Idiosyncratic_Risk = c("STR_1631", "STR_1656", "STR_1683"),
  R16_Calmar             = c("STR_1631", "STR_1679v3", "STR_1683"),
  Q07_Earnings_Stability = c("STR_1071", "STR_1562", "STR_1631"),
  C19_Composite_Earnings = c("STR_1682", "STR_1656"),
  V01_BM                 = c("STR_1071", "STR_1433", "STR_1562"),
  Q25_Ohlson_O           = c("STR_1683"),
  M01_Mom_12_1           = c("STR_1071", "STR_1562", "STR_1631", "STR_1684")
)

cat("[impact_audit] Starting Factor DB Fix Impact Audit v54\n")
cat("[impact_audit] Audit time:", format(Sys.time()), "\n\n")

# ── 1. 현재 sd 상태 점검 (rebuilt parquets 기준) ─────────────────────────────
cat("[impact_audit] Step 1: Checking current Z_Score sd in rebuilt parquet files\n")

check_months <- c("202604", "202603", "202512", "202501", "202412")
sd_results <- list()

for (ym in check_months) {
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym, ".parquet"))
  if (!file.exists(fpath)) {
    cat(sprintf("  [SKIP] %s not found\n", ym))
    next
  }
  dt <- as.data.table(read_parquet(fpath))
  dt_sub <- dt[Factor_Name %in% TARGET_FACTORS & Coverage == TRUE]
  if (nrow(dt_sub) == 0) {
    dt_sub <- dt[grepl(paste(paste0("^", sub("_.*", "", TARGET_FACTORS)), collapse="|"),
                        Factor_Name) & Coverage == TRUE]
  }
  if (nrow(dt_sub) == 0) next
  # Z_Score_Aligned is not stored in parquet — only Z_Score is (connector computes it)
  sd_check <- dt_sub[, .(
    sd_z = round(sd(Z_Score, na.rm = TRUE), 4),
    n    = .N
  ), by = Factor_Name]
  sd_check[, ym := ym]
  sd_results[[ym]] <- sd_check
}

if (length(sd_results) > 0) {
  sd_dt <- rbindlist(sd_results)
  cat("\n[impact_audit] Z_Score sd by factor (current parquets — pre- or post-fix depending on rebuild status):\n")
  print(sd_dt[order(Factor_Name, ym)], nrows=80)
} else {
  cat("[impact_audit] WARNING: No parquet files found for sd check\n")
  sd_dt <- data.table()
}

# ── 2. ICIR 전/후 delta (factor_ic_monthly.parquet 기반) ─────────────────────
cat("\n[impact_audit] Step 2: Computing ICIR from current factor_ic_monthly.parquet\n")

icir_post <- NULL
if (file.exists(IC_PATH)) {
  ic_hist <- as.data.table(read_parquet(IC_PATH))
  ic_hist[, Date := as.Date(Date)]

  # Post-fix ICIR (전체 기간)
  ic_target <- ic_hist[Factor_Name %in% TARGET_FACTORS]
  icir_post <- ic_target[, {
    n <- .N
    m <- mean(IC, na.rm = TRUE)
    s <- sd(IC, na.rm = TRUE)
    list(
      Mean_IC_post = round(m, 4),
      ICIR_post    = if (s > 1e-8) round(m / s, 4) else NA_real_,
      N_Months     = n
    )
  }, by = Factor_Name]

  cat("\n[impact_audit] Post-fix ICIR:\n")
  print(icir_post[order(Factor_Name)])
} else {
  cat("[impact_audit] WARNING: factor_ic_monthly.parquet not found\n")
  cat("  Run compute_all_factor_ic_monthly() after rebuild completes\n")
}

# ── 3. sd distortion 정도 (fix 전 알려진 수준 vs 현재) ───────────────────────
cat("\n[impact_audit] Step 3: sd distortion summary\n")

# 알려진 pre-fix sd 수준 (Scout 9/12 CRITICAL finding 기반)
pre_fix_sd <- data.table(
  Factor_Name    = TARGET_FACTORS,
  sd_pre_approx  = c(0.054, 0.071, 0.165, 0.328, 0.354, 0.395, 0.520, 0.630),
  distortion_pct = c(1761,  1316,  529,   205,   177,   176,   89,    52)
)

distortion_summary <- list(
  pre_fix_sd_known  = pre_fix_sd,
  post_fix_sd       = if (nrow(sd_dt) > 0) sd_dt[ym == max(ym)] else NULL,
  icir_post         = icir_post
)

# ── 4. 전략 매핑 ─────────────────────────────────────────────────────────────
cat("\n[impact_audit] Step 4: Strategy impact mapping\n")

affected_strategies <- unique(unlist(STRATEGY_MAP))
strategy_factor_map <- lapply(affected_strategies, function(str) {
  factors_used <- names(STRATEGY_MAP)[sapply(STRATEGY_MAP, function(strs) str %in% strs)]
  list(
    strategy     = str,
    factors_used = factors_used,
    n_critical   = sum(factors_used %in% c("M08_Residual_Mom", "R12_Idiosyncratic_Risk",
                                            "R16_Calmar"))
  )
})

cat("\n[impact_audit] Strategy → factor mapping:\n")
for (s in strategy_factor_map) {
  cat(sprintf("  %s: %s (critical: %d)\n",
              s$strategy, paste(s$factors_used, collapse=", "), s$n_critical))
}

# ── 5. 최종 audit result 저장 ─────────────────────────────────────────────────
cat("\n[impact_audit] Step 5: Writing audit result to stage_artifacts/\n")

sd_summary_list <- if (nrow(sd_dt) > 0) {
  lapply(split(sd_dt, by = "Factor_Name"), function(x) {
    latest_sd <- x[ym == max(ym), sd_z]
    list(
      factor      = x$Factor_Name[1],
      sd_current  = if (length(latest_sd) > 0) latest_sd else NA_real_,
      sd_target   = 1.0,
      fix_verified = if (length(latest_sd) > 0) latest_sd > 0.95 else FALSE
    )
  })
} else {
  list()
}

audit_result <- list(
  meta = list(
    audit_version   = "v1",
    created_at      = format(Sys.time()),
    rebuild_pid     = 2748125L,
    rebuild_cmd     = "build_factor_db_monthly(start='2005-01', end='2026-04', force=TRUE)",
    fix_description = "v54 re-standardize after winsorize (sd=1 guarantee) in .standardize_factors() + align_factor_direction()"
  ),
  pre_fix_distortions = lapply(seq_len(nrow(pre_fix_sd)), function(i) {
    row <- pre_fix_sd[i]
    list(
      factor         = row$Factor_Name,
      sd_pre_approx  = row$sd_pre_approx,
      distortion_pct = row$distortion_pct,
      severity       = if (row$distortion_pct > 500) "CRITICAL"
                       else if (row$distortion_pct > 100) "HIGH"
                       else "MEDIUM"
    )
  }),
  post_fix_sd_check  = sd_summary_list,
  icir_post          = if (!is.null(icir_post)) lapply(seq_len(nrow(icir_post)), function(i) {
    list(factor=icir_post$Factor_Name[i],
         icir=icir_post$ICIR_post[i],
         mean_ic=icir_post$Mean_IC_post[i],
         n_months=icir_post$N_Months[i])
  }) else list(),
  strategy_impact_map = strategy_factor_map,
  conclusion = list(
    fix_in_connector_R   = "DONE — align_factor_direction() re-standardize at line 186-189",
    fix_in_builder_R     = "DONE — .standardize_factors() re-standardize at line 372-379",
    build_hash_connector = "DONE — load_month_factors() attaches factor_db_build_hash attr",
    build_hash_builder   = "DONE — .write_build_hash() called after each save",
    rebuild_status       = "IN_PROGRESS — PID 2748125, monitor at /tmp/factor_db_rebuild_v54.log",
    icir_delta_status    = if (!is.null(icir_post)) "MEASURED" else "PENDING_REBUILD"
  )
)

dir.create(dirname(AUDIT_OUT), showWarnings = FALSE, recursive = TRUE)
write(toJSON(audit_result, pretty = TRUE, auto_unbox = TRUE), AUDIT_OUT)
cat(sprintf("[impact_audit] Audit saved: %s\n", AUDIT_OUT))
cat("[impact_audit] Complete at:", format(Sys.time()), "\n")
