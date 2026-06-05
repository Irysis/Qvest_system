#==============================================================================
# merge_xlsx_into_dart.R — Merge XF (xlsx-based) factors INTO DART-named factors
#
# Creates continuous long time series from 1990 onwards (DART coverage ~2005; pre-2005 uses XF) by:
#   - Before DART coverage: use XF (xlsx-computed) values under DART factor names
#   - After DART coverage:  keep existing DART-computed values (higher quality)
#
# The 19 mapped pairs (DART_name <- XF_name):
#   Q01_GPA <- XF_Q01_GPA,  Q02_ROE <- XF_Q02_ROE,  Q03_ROA <- XF_Q03_ROA,
#   Q05_Accrual <- XF_A01_Accrual,  Q10_Gross_Margin <- XF_Q05_Gross_Margin,
#   Q11_Net_Margin <- XF_Q07_Net_Margin,  Q12_Asset_Turnover <- XF_Q04_Asset_Turnover,
#   Q32_Interest_Coverage <- XF_Q08_Interest_Coverage,
#   Q15_Debt_to_Equity <- XF_L01_Debt_to_Equity,
#   Q14_Current_Ratio <- XF_L02_Current_Ratio,  Q04_Piotroski_F <- XF_P01_Piotroski_F,
#   V01_BM <- XF_V01_BM,  V02_EP <- XF_V02_EP,  V03_CFP <- XF_V03_CFP,
#   V08_PSR <- XF_V04_SP,
#   GR03_Asset_Growth <- XF_G01_Asset_Growth,
#   GR01_Revenue_Growth <- XF_G02_Revenue_Growth,
#   GR02_Earnings_Growth <- XF_G03_Earnings_Growth,
#   AC05_NOA <- XF_A02_NOA
#
# Logic per factor per month:
#   - DART has 0 rows  -> copy ALL XF rows, rename Factor_Name to DART name
#   - DART has >0 rows -> keep DART, discard XF (avoid duplicates)
# After merge: remove all standalone XF_ rows for the 19 mapped pairs.
# Unmapped XF_ factors (e.g., XF_DU01_NetMargin) are kept as-is.
#
# Usage:
#   source("02_Infrastructure/factor_db/merge_xlsx_into_dart.R")
#   merge_xlsx_into_dart()
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

merge_xlsx_into_dart <- function(cache_dir = NULL, dry_run = FALSE, verbose = TRUE) {

  # ── Path resolution ──────────────────────────────────────────────────────────
  if (is.null(cache_dir)) {
    proj_root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
    cache_dir <- file.path(proj_root, ".cache", "factor_db")
  }

  stopifnot(dir.exists(cache_dir))

  # ── 19 Mapped pairs: DART_name -> XF_name ─────────────────────────────────
  MAPPING <- list(
    list(dart = "Q01_GPA",              xf = "XF_Q01_GPA"),
    list(dart = "Q02_ROE",              xf = "XF_Q02_ROE"),
    list(dart = "Q03_ROA",              xf = "XF_Q03_ROA"),
    list(dart = "Q05_Accrual",          xf = "XF_A01_Accrual"),
    list(dart = "Q10_Gross_Margin",     xf = "XF_Q05_Gross_Margin"),
    list(dart = "Q11_Net_Margin",       xf = "XF_Q07_Net_Margin"),
    list(dart = "Q12_Asset_Turnover",   xf = "XF_Q04_Asset_Turnover"),
    list(dart = "Q32_Interest_Coverage",xf = "XF_Q08_Interest_Coverage"),
    list(dart = "Q15_Debt_to_Equity",   xf = "XF_L01_Debt_to_Equity"),
    list(dart = "Q14_Current_Ratio",    xf = "XF_L02_Current_Ratio"),
    list(dart = "Q04_Piotroski_F",      xf = "XF_P01_Piotroski_F"),
    list(dart = "V01_BM",               xf = "XF_V01_BM"),
    list(dart = "V02_EP",               xf = "XF_V02_EP"),
    list(dart = "V03_CFP",              xf = "XF_V03_CFP"),
    list(dart = "V08_PSR",              xf = "XF_V04_SP"),
    list(dart = "GR03_Asset_Growth",    xf = "XF_G01_Asset_Growth"),
    list(dart = "GR01_Revenue_Growth",  xf = "XF_G02_Revenue_Growth"),
    list(dart = "GR02_Earnings_Growth", xf = "XF_G03_Earnings_Growth"),
    list(dart = "AC05_NOA",             xf = "XF_A02_NOA")
  )

  # Build quick lookup vectors
  mapped_xf_names  <- vapply(MAPPING, function(m) m$xf,   character(1))
  mapped_dart_names <- vapply(MAPPING, function(m) m$dart, character(1))
  xf_to_dart <- setNames(mapped_dart_names, mapped_xf_names)

  # ── Discover parquet files ─────────────────────────────────────────────────
  files <- sort(list.files(cache_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                           full.names = TRUE))
  if (length(files) == 0) stop("No parquet files found in: ", cache_dir)

  if (verbose) cat(sprintf("=== merge_xlsx_into_dart ===\nCache: %s\nFiles: %d\nMapped pairs: %d\nDry run: %s\n\n",
                           cache_dir, length(files), length(MAPPING), dry_run))

  # ── Counters for summary ───────────────────────────────────────────────────
  total_copied    <- 0L   # XF rows copied into DART names
  total_removed   <- 0L   # mapped XF_ rows removed (duplicates)
  total_kept      <- 0L   # unmapped XF_ rows kept
  files_modified  <- 0L
  copy_log <- list()      # detailed log: list of (ym, dart_name, rows_copied)

  # ── Process each parquet ───────────────────────────────────────────────────
  for (f in files) {
    ym <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", f)
    dt <- as.data.table(read_parquet(f))

    # Quick check: does this file have ANY XF_ factors?
    all_factors <- unique(dt$Factor_Name)
    xf_present  <- grep("^XF_", all_factors, value = TRUE)

    if (length(xf_present) == 0L) next   # No XF_ in this month -> skip

    modified <- FALSE

    # ── Step 1: For each mapped pair, decide copy vs remove ────────────────
    for (m in MAPPING) {
      dart_name <- m$dart
      xf_name   <- m$xf

      xf_rows  <- dt[Factor_Name == xf_name]
      dart_rows <- dt[Factor_Name == dart_name]

      n_xf   <- nrow(xf_rows)
      n_dart <- nrow(dart_rows)

      if (n_xf == 0L) next  # This XF factor not present in this month

      if (n_dart == 0L) {
        # ── DART has no data -> copy XF rows under DART name ────────────────
        new_rows <- copy(xf_rows)
        new_rows[, Factor_Name := dart_name]
        dt <- rbindlist(list(dt, new_rows), use.names = TRUE)

        total_copied <- total_copied + n_xf
        copy_log[[length(copy_log) + 1L]] <- list(ym = ym, dart = dart_name, rows = n_xf)
        if (verbose) cat(sprintf("  [%s] COPY  %s -> %s (%d rows)\n", ym, xf_name, dart_name, n_xf))
      } else {
        # ── DART already has data -> keep DART, will remove XF below ────────
        total_removed <- total_removed + n_xf
      }

      modified <- TRUE
    }

    # ── Step 2: Remove all mapped XF_ rows ─────────────────────────────────
    # (both the duplicates and the ones we just copied into DART names)
    mapped_present <- intersect(mapped_xf_names, xf_present)
    if (length(mapped_present) > 0L) {
      dt <- dt[!Factor_Name %in% mapped_present]
    }

    # ── Step 3: Remove ALL remaining XF_ rows (unmapped included) ───────
    unmapped_xf <- grep("^XF_", unique(dt$Factor_Name), value = TRUE)
    if (length(unmapped_xf) > 0L) {
      n_removed_xf <- sum(dt$Factor_Name %in% unmapped_xf)
      dt <- dt[!grepl("^XF_", Factor_Name)]
      total_kept <- total_kept + n_removed_xf
      modified <- TRUE
    }

    # ── Step 4: Save back ──────────────────────────────────────────────────
    if (modified) {
      files_modified <- files_modified + 1L
      if (!dry_run) {
        write_parquet(dt, f)
      }
      if (verbose) cat(sprintf("  [%s] Saved (%d rows, %d factors)\n", ym, nrow(dt), length(unique(dt$Factor_Name))))
    }
  }

  # ── Summary ──────────────────────────────────────────────────────────────
  summary <- list(
    files_processed = length(files),
    files_modified  = files_modified,
    rows_copied     = total_copied,
    rows_removed    = total_removed,
    unmapped_kept   = total_kept,
    copy_details    = copy_log
  )

  if (verbose) {
    cat("\n=== SUMMARY ===\n")
    cat(sprintf("Files processed:        %d\n", summary$files_processed))
    cat(sprintf("Files modified:         %d\n", summary$files_modified))
    cat(sprintf("XF rows -> DART name:   %d (factors that had 0 DART coverage)\n", summary$rows_copied))
    cat(sprintf("XF rows removed:        %d (DART already existed)\n", summary$rows_removed))
    cat(sprintf("Unmapped XF rows kept:  %d (no DART equivalent)\n", summary$unmapped_kept))

    if (length(copy_log) > 0L) {
      cat("\n--- Copy details (XF filled gaps in DART) ---\n")
      for (cl in copy_log) {
        cat(sprintf("  %s: %s <- %d rows\n", cl$ym, cl$dart, cl$rows))
      }
    }

    if (dry_run) {
      cat("\n*** DRY RUN — no files were modified ***\n")
    } else {
      cat("\nDone. All parquets updated in-place.\n")
    }
  }

  invisible(summary)
}


#==============================================================================
# verify_merge() — Post-merge verification
#==============================================================================
verify_merge <- function(cache_dir = NULL, verbose = TRUE) {

  if (is.null(cache_dir)) {
    proj_root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
    cache_dir <- file.path(proj_root, ".cache", "factor_db")
  }

  files <- sort(list.files(cache_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                           full.names = TRUE))

  # Mapped XF names that should no longer exist
  mapped_xf <- c("XF_Q01_GPA", "XF_Q02_ROE", "XF_Q03_ROA",
                  "XF_A01_Accrual", "XF_Q05_Gross_Margin", "XF_Q07_Net_Margin",
                  "XF_Q04_Asset_Turnover", "XF_Q08_Interest_Coverage",
                  "XF_L01_Debt_to_Equity", "XF_L02_Current_Ratio",
                  "XF_P01_Piotroski_F", "XF_V01_BM", "XF_V02_EP",
                  "XF_V03_CFP", "XF_V04_SP",
                  "XF_G01_Asset_Growth", "XF_G02_Revenue_Growth",
                  "XF_G03_Earnings_Growth", "XF_A02_NOA")

  # Key checks
  checks <- list(pass = 0L, fail = 0L, details = character())
  add_check <- function(ok, msg) {
    if (ok) { checks$pass <<- checks$pass + 1L }
    else    { checks$fail <<- checks$fail + 1L }
    status <- if (ok) "PASS" else "FAIL"
    checks$details <<- c(checks$details, sprintf("[%s] %s", status, msg))
  }

  # ── Check 1: No mapped XF_ factors remain in ANY file ─────────────────────
  if (verbose) cat("Check 1: No mapped XF_ factors remain...\n")
  stray_xf <- character()
  for (f in files) {
    dt <- read_parquet(f)
    found <- intersect(mapped_xf, unique(dt$Factor_Name))
    if (length(found) > 0) {
      ym <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", f)
      stray_xf <- c(stray_xf, paste0(ym, ": ", paste(found, collapse = ", ")))
    }
  }
  add_check(length(stray_xf) == 0,
            sprintf("Mapped XF_ cleanup (%d stray found)", length(stray_xf)))
  if (length(stray_xf) > 0 && verbose) {
    cat("  Stray XF_ factors:\n")
    for (s in head(stray_xf, 10)) cat("    ", s, "\n")
  }

  # ── Check 2: Unmapped XF_ factors still exist (e.g., XF_DU01_NetMargin) ──
  if (verbose) cat("Check 2: Unmapped XF_ factors preserved...\n")
  # Check a few months that had 44 XF factors (200602-200608)
  f_200602 <- file.path(cache_dir, "factor_db_200602.parquet")
  if (file.exists(f_200602)) {
    dt_602 <- read_parquet(f_200602)
    unmapped <- grep("^XF_", unique(dt_602$Factor_Name), value = TRUE)
    add_check(length(unmapped) > 0,
              sprintf("Unmapped XF_ preserved in 200602 (%d factors: %s)",
                      length(unmapped), paste(head(unmapped, 3), collapse = ", ")))
  }

  # ── Check 3: Q01_GPA has data from 2005 onwards ──────────────────────────
  if (verbose) cat("Check 3: Q01_GPA coverage from 2005...\n")
  spot_months <- c("200501", "200801", "201001", "201301", "201601", "202001")
  gpa_ok <- TRUE
  for (ym in spot_months) {
    f_check <- file.path(cache_dir, sprintf("factor_db_%s.parquet", ym))
    if (!file.exists(f_check)) next
    dt_check <- read_parquet(f_check)
    n <- sum(dt_check$Factor_Name == "Q01_GPA")
    if (n == 0) { gpa_ok <- FALSE; if (verbose) cat(sprintf("  MISSING Q01_GPA in %s\n", ym)) }
    else if (verbose) cat(sprintf("  %s: Q01_GPA = %d rows\n", ym, n))
  }
  add_check(gpa_ok, "Q01_GPA continuous from 2005")

  # ── Check 4: AC05_NOA and GR02_Earnings_Growth filled in early months ─────
  if (verbose) cat("Check 4: AC05_NOA / GR02_Earnings_Growth backfilled...\n")
  f_200501 <- file.path(cache_dir, "factor_db_200501.parquet")
  if (file.exists(f_200501)) {
    dt_501 <- read_parquet(f_200501)
    n_noa <- sum(dt_501$Factor_Name == "AC05_NOA")
    n_eg  <- sum(dt_501$Factor_Name == "GR02_Earnings_Growth")
    add_check(n_noa > 0, sprintf("AC05_NOA in 200501: %d rows", n_noa))
    add_check(n_eg > 0,  sprintf("GR02_Earnings_Growth in 200501: %d rows", n_eg))
  }

  # ── Check 5: In 2020, DART-quality data preserved (no XF overwrite) ───────
  if (verbose) cat("Check 5: Post-2016 DART data untouched...\n")
  f_202001 <- file.path(cache_dir, "factor_db_202001.parquet")
  if (file.exists(f_202001)) {
    dt_2020 <- read_parquet(f_202001)
    xf_2020 <- grep("^XF_", unique(dt_2020$Factor_Name), value = TRUE)
    add_check(length(xf_2020) == 0, sprintf("No XF_ factors in 202001 (%d found)", length(xf_2020)))
    n_gpa <- sum(dt_2020$Factor_Name == "Q01_GPA")
    add_check(n_gpa > 0, sprintf("Q01_GPA in 202001: %d rows (DART quality)", n_gpa))
  }

  # ── Report ───────────────────────────────────────────────────────────────
  if (verbose) {
    cat("\n=== VERIFICATION RESULTS ===\n")
    for (d in checks$details) cat(d, "\n")
    cat(sprintf("\nTotal: %d PASS, %d FAIL\n", checks$pass, checks$fail))
  }

  invisible(checks)
}
