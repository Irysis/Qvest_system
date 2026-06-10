#==============================================================================
# rebuild_z_winsorized.R — Retroactive Z recompute (winsorized) for monthly DB
# P1 Track A (2026-06-10)
#
# For every .cache/factor_db/factor_db_YYYYMM.parquet:
#   - Re-derive Z_Score / Z_Sector from Raw_Value via the CURRENT builder
#     .standardize_factors() (cross-sectional 1/99 winsorize before z-scoring)
#   - Apply new Coverage definition: !is.na(Raw_Value) & !is.na(Z_Score)
#   - Raw_Value and Rank_Pct are NOT modified (reversibility guaranteed)
#   - Same 8-column schema saved in place (tmp file + rename, no partial write)
#
# Restart safety: explicit marker files under
#   .cache/factor_db/_rebuild_z_markers/<basename>.done
# Files with a marker are skipped. No Z-magnitude heuristics are used.
# Per-file before/after metrics (max|Z|, worst identical-Z share) appended to
#   .cache/factor_db/_rebuild_z_markers/rebuild_log.csv
#
# Usage (from project root):
#   Rscript -e 'source("02_Infrastructure/factor_db/rebuild_z_winsorized.R")'
#     -> all factor_db_*.parquet (437)
#   Rscript -e 'source("02_Infrastructure/factor_db/rebuild_z_winsorized.R")' 199006 202401
#     -> only the listed YYYYMM tags (sample / verification runs)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ─── Self-locate & source config + builder ──────────────────────────────────
.self_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    file.path(
      Sys.getenv("CLAUDE_PROJECT_DIR",
                 Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
      "02_Infrastructure", "factor_db"
    )
  }
)
if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(.self_dir), "config.R"))
}
# Reuse the builder's .standardize_factors so the retroactive recompute is
# bit-identical to what build_factor_db() will produce going forward.
source(file.path(.self_dir, "factor_db_builder.R"))

#==============================================================================
# Setup
#==============================================================================

MARKER_DIR <- file.path(FACTOR_DB_DIR, "_rebuild_z_markers")
LOG_PATH   <- file.path(MARKER_DIR, "rebuild_log.csv")
dir.create(MARKER_DIR, recursive = TRUE, showWarnings = FALSE)

# Optional YYYYMM tag subset from trailing command-line args
.args <- commandArgs(trailingOnly = TRUE)
.ym_subset <- grep("^\\d{6}$", .args, value = TRUE)

files <- sort(list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$",
                         full.names = TRUE))
if (length(.ym_subset) > 0L) {
  keep <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", basename(files)) %in% .ym_subset
  files <- files[keep]
  cat(sprintf("[rebuild_z] Subset mode: %d file(s) for tags %s\n",
              length(files), paste(.ym_subset, collapse = ", ")))
}
cat(sprintf("[rebuild_z] %d monthly file(s) targeted | marker dir: %s\n",
            length(files), MARKER_DIR))

# ─── Sector map source: RAWDATA (Date/Ticker/Sector only) ───────────────────
cat("[rebuild_z] Loading RAWDATA sector columns...\n")
RAW_SEC <- as.data.table(read_parquet(RAWDATA_CACHE,
                                      col_select = c("Date", "Ticker", "Sector")))
RAW_SEC[, Date := as.Date(Date)]
setkey(RAW_SEC, Date)
raw_dates <- sort(unique(RAW_SEC$Date))
cat(sprintf("  RAWDATA sector map: %s rows | %s ~ %s\n",
            format(nrow(RAW_SEC), big.mark = ","),
            min(raw_dates), max(raw_dates)))

#==============================================================================
# Helpers
#==============================================================================

#' Worst per-factor identical-Z share: max over factors of
#' (count of the most frequent Z value) / (non-NA Z count in that factor).
#' Captures the Q11_Net_Margin-type collapse (79.6% of tickers on one Z).
.worst_tie_share <- function(dt) {
  tie <- dt[!is.na(Z_Score),
            .(share = max(tabulate(frank(Z_Score, ties.method = "dense"))) / .N,
              n = .N),
            by = Factor_Name][n >= 20L]
  if (nrow(tie) == 0L) return(list(share = NA_real_, factor = NA_character_))
  w <- tie[which.max(share)]
  list(share = w$share, factor = w$Factor_Name)
}

.append_log <- function(row) {
  fwrite(row, LOG_PATH, append = file.exists(LOG_PATH))
}

#==============================================================================
# Main loop
#==============================================================================

EXPECTED_COLS <- c("Date", "Ticker", "Factor_Name", "Raw_Value",
                   "Z_Score", "Z_Sector", "Rank_Pct", "Coverage")

t0 <- Sys.time()
n_done <- 0L; n_skip <- 0L; n_fail <- 0L

for (i in seq_along(files)) {
  f      <- files[i]
  bn     <- basename(f)
  marker <- file.path(MARKER_DIR, paste0(bn, ".done"))

  if (file.exists(marker)) {
    n_skip <- n_skip + 1L
    next
  }

  status <- "OK"; note <- ""
  res <- tryCatch({
    dt <- as.data.table(read_parquet(f))

    if (!all(EXPECTED_COLS %in% names(dt))) {
      stop("schema mismatch: missing ", paste(setdiff(EXPECTED_COLS, names(dt)), collapse = ","))
    }
    if (nrow(dt) == 0L) stop("empty file")
    if (anyDuplicated(dt, by = c("Ticker", "Factor_Name")) > 0L) {
      stop("duplicate (Ticker, Factor_Name) rows — manual review required")
    }

    sig_d <- as.Date(dt$Date[1])

    # PIT sector snapshot: most recent trading day <= sig_d
    idx <- findInterval(sig_d, raw_dates)
    if (idx == 0L) stop("no RAWDATA on or before ", sig_d)
    snap_d <- raw_dates[idx]
    sector_map <- unique(RAW_SEC[.(snap_d), .(Ticker, Sector)], by = "Ticker")
    if (nrow(sector_map) == 0L) stop("empty sector snapshot at ", snap_d)

    # ── Before metrics ──────────────────────────────────────────────────────
    max_z_before  <- suppressWarnings(dt[, max(abs(Z_Score), na.rm = TRUE)])
    tie_before    <- .worst_tie_share(dt)
    cov_before    <- dt[, sum(Coverage, na.rm = TRUE)]

    # ── Recompute via builder .standardize_factors (winsorized) ─────────────
    new_std <- .standardize_factors(dt[, .(Ticker, Factor_Name, Raw_Value)],
                                    sector_map)

    out <- merge(dt[, .(Date, Ticker, Factor_Name, Raw_Value, Rank_Pct)],
                 new_std[, .(Ticker, Factor_Name, Z_Score, Z_Sector, Coverage)],
                 by = c("Ticker", "Factor_Name"), all.x = TRUE, sort = FALSE)
    setcolorder(out, EXPECTED_COLS)
    stopifnot(nrow(out) == nrow(dt))

    # ── After metrics ───────────────────────────────────────────────────────
    max_z_after <- suppressWarnings(out[, max(abs(Z_Score), na.rm = TRUE)])
    tie_after   <- .worst_tie_share(out)
    cov_after   <- out[, sum(Coverage, na.rm = TRUE)]

    # ── Atomic-ish save: tmp write -> remove original -> rename ─────────────
    tmp <- paste0(f, ".tmp_rebuild")
    write_parquet(out, tmp)
    if (!file.remove(f)) stop("could not remove original for replace")
    if (!file.rename(tmp, f)) stop("rename failed — original removed, tmp at ", tmp)

    # ── Marker (written only after successful replace) ──────────────────────
    writeLines(c(
      sprintf("rebuilt_at=%s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
      sprintf("max_absZ_before=%.4f", max_z_before),
      sprintf("max_absZ_after=%.4f",  max_z_after),
      sprintf("worst_tie_before=%.4f (%s)", tie_before$share, tie_before$factor),
      sprintf("worst_tie_after=%.4f (%s)",  tie_after$share,  tie_after$factor)
    ), marker)

    .append_log(data.table(
      file = bn, ym = gsub("factor_db_(\\d{6})\\.parquet", "\\1", bn),
      n_rows = nrow(out), snap_date = as.character(snap_d),
      max_absZ_before = round(max_z_before, 4),
      max_absZ_after  = round(max_z_after, 4),
      worst_tie_before = round(tie_before$share, 4),
      worst_tie_factor_before = tie_before$factor,
      worst_tie_after = round(tie_after$share, 4),
      worst_tie_factor_after = tie_after$factor,
      n_coverage_before = cov_before, n_coverage_after = cov_after,
      status = "OK", ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    ))

    cat(sprintf("  [%d/%d] %s: max|Z| %.1f->%.1f | worst tie %.1f%%(%s)->%.1f%%(%s) | cov %s->%s\n",
                i, length(files), bn, max_z_before, max_z_after,
                100 * tie_before$share, tie_before$factor,
                100 * tie_after$share,  tie_after$factor,
                format(cov_before, big.mark = ","), format(cov_after, big.mark = ",")))
    TRUE
  }, error = function(e) {
    cat(sprintf("  [FAIL] %s: %s\n", bn, conditionMessage(e)))
    .append_log(data.table(
      file = bn, ym = gsub("factor_db_(\\d{6})\\.parquet", "\\1", bn),
      n_rows = NA_integer_, snap_date = NA_character_,
      max_absZ_before = NA_real_, max_absZ_after = NA_real_,
      worst_tie_before = NA_real_, worst_tie_factor_before = NA_character_,
      worst_tie_after = NA_real_, worst_tie_factor_after = NA_character_,
      n_coverage_before = NA_integer_, n_coverage_after = NA_integer_,
      status = paste0("FAIL: ", conditionMessage(e)),
      ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    ))
    FALSE
  })

  if (isTRUE(res)) n_done <- n_done + 1L else n_fail <- n_fail + 1L
}

elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
cat(sprintf("\n[rebuild_z] Done: %d rebuilt | %d skipped (marker) | %d failed | %.1f min\n",
            n_done, n_skip, n_fail, elapsed))
cat(sprintf("[rebuild_z] Log: %s\n", LOG_PATH))
