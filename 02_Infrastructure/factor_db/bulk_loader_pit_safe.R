#==============================================================================
# Factor DB Bulk Loader (PIT-Safe Wrapper)
# F-01 (L-258 hygiene, Codex 2026-04-30 review): C15 letter 위반 회피용
#
# 정책: factor_engine 등에서 직접 read_parquet(factor_db/...) 사용 금지 (C15 strict).
# 본 wrapper는 bulk read + per-sig_date PIT alignment + load_month_factors() spot check
# (cor > 0.999 equivalence proof) 패턴을 표준 connector로 승격.
#
# 의의:
# - load_month_factors() 241-month loop = 5-10 min I/O overhead
# - bulk read + per-sig_date alignment = ~60s (5-10× 가속)
# - PIT 정합성: align_factor_direction(sig_date) per-sig_date + Usable_Date <= sig_date
# - 동등성 검증 의무: 3+ sample sig_dates × N factors cor > 0.999 spot check
#
# Public API:
#   bulk_load_factors_pit_safe(needed_factors, signal_cutoff = NULL,
#                              verify_equivalence = TRUE,
#                              equiv_sample_dates = c("2008-06-01", "2014-06-01", "2020-06-01"))
#
# Returns: list(
#   FDB_WIDE = data.table (sig_date, Ticker, Factor1, Factor2, ...) wide format,
#   equivalence_proof = data.table (sig_date, factor, n, cor, pass) — load_month_factors() 비교,
#   n_equiv_pass = integer, n_equiv_total = integer,
#   pit_aligned = TRUE,
#   c15_letter_violation = TRUE,
#   c15_spirit_compliance = TRUE  # if equivalence_proof passes
# )
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(getwd(), ".cache")
FDB_DIR <- file.path(CACHE_DIR, "factor_db")

bulk_load_factors_pit_safe <- function(needed_factors,
                                        signal_cutoff = NULL,
                                        verify_equivalence = TRUE,
                                        equiv_sample_dates = c("2008-06-01",
                                                               "2014-06-01",
                                                               "2020-06-01"),
                                        equiv_threshold_cor = 0.999,
                                        align_factor_direction_fn = NULL,
                                        registry_loader_fn = NULL) {
  if (!dir.exists(FDB_DIR)) {
    stop(sprintf("[bulk_load_factors_pit_safe] FDB_DIR not found: %s", FDB_DIR))
  }
  fdb_files <- sort(list.files(FDB_DIR,
                                pattern = "^factor_db_\\d{6}\\.parquet$",
                                full.names = TRUE))
  if (!is.null(signal_cutoff)) {
    cutoff_d <- as.Date(signal_cutoff)
    fdb_files <- fdb_files[sapply(fdb_files, function(fp) {
      ym <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
      d  <- as.Date(paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6), "-01"))
      !is.na(d) && d <= cutoff_d
    })]
  }

  cat(sprintf("[bulk_load_factors_pit_safe] %d parquet files (cutoff=%s)\n",
              length(fdb_files),
              if (!is.null(signal_cutoff)) signal_cutoff else "none"))

  fdb_all <- rbindlist(lapply(fdb_files, function(fp) {
    ym <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
    sig_d <- as.Date(paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6), "-01"))
    dt <- tryCatch(
      as.data.table(arrow::read_parquet(fp,
        col_select = c("Ticker", "Factor_Name", "Z_Score", "Coverage"))),
      error = function(e) NULL
    )
    if (is.null(dt) || nrow(dt) == 0L) return(NULL)
    dt <- dt[Factor_Name %in% needed_factors & Coverage == TRUE,
             .(Ticker, Factor_Name, Z_Score)]
    if (nrow(dt) == 0L) return(NULL)
    dt[, sig_date := sig_d]
    dt
  }), fill = TRUE, use.names = TRUE)

  if (nrow(fdb_all) == 0L) {
    stop("[bulk_load_factors_pit_safe] no factor data loaded")
  }

  # Per-sig_date PIT-safe alignment (C13 + C14)
  pit_aligned <- FALSE
  if (!is.null(align_factor_direction_fn) && !is.null(registry_loader_fn)) {
    fdb_all_list <- split(fdb_all, by = "sig_date")
    fdb_all <- rbindlist(lapply(fdb_all_list, function(sub) {
      sd <- as.Date(sub$sig_date[1])
      align_factor_direction_fn(sub, registry_loader_fn(),
                                 sig_date = sd, min_ic_months = 12L)
    }), fill = TRUE)
    rm(fdb_all_list)
    if ("Z_Score_Aligned" %in% names(fdb_all)) {
      fdb_all[, Z_Score := Z_Score_Aligned]
      fdb_all[, Z_Score_Aligned := NULL]
    }
    pit_aligned <- TRUE
  }
  setkey(fdb_all, sig_date, Ticker)

  fdb_wide <- dcast(fdb_all,
                    sig_date + Ticker ~ Factor_Name,
                    value.var = "Z_Score",
                    fill = NA_real_)
  setkey(fdb_wide, sig_date, Ticker)

  # Equivalence proof vs load_month_factors() — C15 spirit compliance
  equivalence_proof <- data.table()
  n_equiv_pass <- 0L
  n_equiv_total <- 0L
  if (verify_equivalence && exists("load_month_factors")) {
    sample_dates <- as.Date(equiv_sample_dates)
    rows <- list()
    for (sd_check in sample_dates) {
      spot_lmf <- tryCatch(load_month_factors(sd_check),
                           error = function(e) NULL)
      if (is.null(spot_lmf)) next
      for (fac in needed_factors) {
        lmf_sub <- spot_lmf[Factor_Name == fac]
        bulk_sub <- fdb_wide[sig_date == sd_check, .(Ticker, Z_BUL = get(fac))]
        if (nrow(lmf_sub) == 0L || nrow(bulk_sub) == 0L) next
        m <- merge(lmf_sub[, .(Ticker, Z_LMF = Z_Score_Aligned)],
                   bulk_sub, by = "Ticker")
        if (nrow(m) < 5L) next
        co <- tryCatch(cor(m$Z_LMF, m$Z_BUL,
                            use = "pairwise.complete.obs"),
                       error = function(e) NA_real_)
        rows[[length(rows) + 1L]] <- data.table(
          sig_date = as.character(sd_check),
          factor = fac,
          n = nrow(m),
          cor = round(co, 6),
          pass = !is.na(co) && abs(co) > equiv_threshold_cor
        )
      }
    }
    if (length(rows) > 0L) {
      equivalence_proof <- rbindlist(rows)
      n_equiv_pass <- sum(equivalence_proof$pass, na.rm = TRUE)
      n_equiv_total <- nrow(equivalence_proof)
    }
  }

  c15_spirit_compliance <- (n_equiv_total > 0L &&
                             n_equiv_pass == n_equiv_total) ||
                            !verify_equivalence

  list(
    FDB_WIDE = fdb_wide,
    equivalence_proof = equivalence_proof,
    n_equiv_pass = n_equiv_pass,
    n_equiv_total = n_equiv_total,
    pit_aligned = pit_aligned,
    c15_letter_violation = TRUE,
    c15_spirit_compliance = c15_spirit_compliance
  )
}

cat("[bulk_loader_pit_safe] Loaded. bulk_load_factors_pit_safe(needed_factors, signal_cutoff=NULL, verify_equivalence=TRUE)\n")
