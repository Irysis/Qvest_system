#!/usr/bin/env Rscript
#==============================================================================
# backfill_sparse_factors_v8.R
#   Surgical backfill of build-gap factors into the monthly Factor DB.
#
#   Targets (root cause confirmed 2026-05-29):
#     CR07_Momentum_Crowding     build-gap (365d window vs .N>252 per-ticker)
#     MA06_Risk_Sentiment_1Y     build-gap (bm_daily>=252 vs 365d window)
#     SE01_Volatility_Uncertainty build-gap (consensus lacks dispersion col;
#                                            fallback only fired pre-consensus)
#     RE13_Credit_Spread_Pctile  data-limit (HY OAS only 2023-05+; fills where data exists)
#     RE16_Canary_Signal         data-limit (SP500 absent; will stay 0, honest)
#
#   Method (per month):
#     1. backup month file -> .cache/factor_db_backup_v8/ (once)
#     2. compute the 5 target factors via compute_regime + compute_crowding
#        (fixed scripts), passing a wide RAWDATA slice (PIT: Date <= sig_d)
#     3. standardize EXACTLY as factor_db_builder.R::.standardize_factors
#        using the month's sector_map (per-factor self-contained z-score)
#     4. drop existing rows of the 5 factor names, append fresh rows
#     5. atomic write (.tmp -> rename). Other factors' rows untouched.
#
#   SAFETY: only the 5 target Factor_Name rows are ever modified. All other
#   factor rows are passed through byte-for-byte (filtered out, re-bound).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

ROOT      <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
CACHE_DIR <- file.path(ROOT, ".cache")
FDB_DIR   <- file.path(CACHE_DIR, "factor_db")
BACKUP    <- file.path(CACHE_DIR, "factor_db_backup_v8")
setwd(ROOT)
dir.create(BACKUP, showWarnings = FALSE, recursive = TRUE)

TARGET_FACTORS <- c(
  "CR07_Momentum_Crowding",
  "MA06_Risk_Sentiment_1Y",
  "SE01_Volatility_Uncertainty",
  "RE13_Credit_Spread_Pctile",
  "RE16_Canary_Signal"
)

DRY_RUN <- "--dry-run" %in% commandArgs(TRUE)
LIMIT_N <- {
  a <- grep("^--limit=", commandArgs(TRUE), value = TRUE)
  if (length(a)) as.integer(sub("^--limit=", "", a[1])) else NA_integer_
}
# Resume support: --from=YYYYMM processes only files with ym >= YYYYMM
FROM_YM <- {
  a <- grep("^--from=", commandArgs(TRUE), value = TRUE)
  if (length(a)) sub("^--from=", "", a[1]) else NA_character_
}

# ---- standardize (byte-identical to factor_db_builder.R::.standardize_factors) ----
.standardize_factors <- function(dt, sector_map) {
  if (nrow(dt) == 0) return(dt[, .(Ticker, Factor_Name, Raw_Value,
                                    Z_Score = numeric(0), Z_Sector = numeric(0),
                                    Rank_Pct = numeric(0), Coverage = logical(0))])
  dt <- merge(dt, sector_map[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
  dt[, Coverage := !is.na(Raw_Value)]
  dt[, Z_Score := {
    vals <- Raw_Value; mu <- mean(vals, na.rm = TRUE); s <- sd(vals, na.rm = TRUE)
    if (is.na(s) || s < 1e-12) rep(NA_real_, .N) else (vals - mu) / s
  }, by = Factor_Name]
  dt[, Z_Sector := {
    vals <- Raw_Value; mu <- mean(vals, na.rm = TRUE); s <- sd(vals, na.rm = TRUE)
    if (is.na(s) || s < 1e-12) rep(NA_real_, .N) else (vals - mu) / s
  }, by = .(Factor_Name, Sector)]
  dt[, Rank_Pct := {
    vals <- Raw_Value; r <- frank(vals, ties.method = "average", na.last = "keep")
    n_valid <- sum(!is.na(vals)); if (n_valid > 1) (r - 1) / (n_valid - 1) else rep(NA_real_, .N)
  }, by = Factor_Name]
  dt[!is.na(Z_Score), Z_Score := pmin(pmax(Z_Score, -3), 3)]
  dt[!is.na(Z_Sector), Z_Sector := pmin(pmax(Z_Sector, -3), 3)]
  dt[!is.na(Z_Score), Z_Score := { s <- sd(Z_Score, na.rm = TRUE)
    if (!is.na(s) && s > 1e-12) Z_Score / s else Z_Score }, by = Factor_Name]
  dt[!is.na(Z_Sector), Z_Sector := { s <- sd(Z_Sector, na.rm = TRUE)
    if (!is.na(s) && s > 1e-12) Z_Sector / s else Z_Sector }, by = .(Factor_Name, Sector)]
  dt[, Sector := NULL]
  dt
}

# ---- load base data ----
cat("[backfill] loading RAWDATA...\n")
RAWDATA <- as.data.table(read_parquet(file.path(CACHE_DIR, "rawdata.parquet")))
RAWDATA[, Date := as.Date(Date)]
setkey(RAWDATA, Date, Ticker)
trading_dates <- sort(unique(RAWDATA$Date))
cat(sprintf("  RAWDATA %s rows %s~%s\n", format(nrow(RAWDATA), big.mark=","),
            min(RAWDATA$Date), max(RAWDATA$Date)))

CONSENSUS <- list()
cdir <- file.path(CACHE_DIR, "consensus")
if (dir.exists(cdir)) for (cf in list.files(cdir, pattern="\\.parquet$", full.names=TRUE))
  CONSENSUS[[sub("\\.parquet$","",basename(cf))]] <- as.data.table(read_parquet(cf))
cat(sprintf("  CONSENSUS %d tables\n", length(CONSENSUS)))

source(file.path(ROOT, "02_Infrastructure/factor_db/compute_regime.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/compute_crowding.R"))

pit_sector_map <- function(sig_d) {
  idx <- findInterval(sig_d, trading_dates)
  if (idx == 0L) return(NULL)
  snap <- RAWDATA[.(trading_dates[idx]), nomatch = 0L]
  if (nrow(snap) == 0L) return(NULL)
  unique(snap[, .(Ticker, Sector)], by = "Ticker")
}

files <- sort(list.files(FDB_DIR, pattern="^factor_db_[0-9]{6}\\.parquet$", full.names=TRUE))
if (!is.na(FROM_YM)) {
  fyms <- sub("^factor_db_([0-9]{6})\\.parquet$", "\\1", basename(files))
  files <- files[fyms >= FROM_YM]
  cat(sprintf("[backfill] resume from %s -> %d files\n", FROM_YM, length(files)))
}
if (!is.na(LIMIT_N)) files <- head(files, LIMIT_N)
cat(sprintf("[backfill] %d monthly files. DRY_RUN=%s\n", length(files), DRY_RUN))

audit <- data.table(ym=character(), before_rows=integer(), after_rows=integer(),
                    CR07=integer(), MA06=integer(), SE01=integer(),
                    RE13=integer(), RE16=integer(), other_unchanged=logical())

for (fp in files) {
  ym  <- sub("^factor_db_([0-9]{6})\\.parquet$", "\\1", basename(fp))
  existing <- as.data.table(read_parquet(fp))
  sig_d <- as.Date(existing$Date[1])
  before_rows <- nrow(existing)

  # other factors (everything except targets) — must be preserved exactly
  other <- existing[!Factor_Name %in% TARGET_FACTORS]

  sector_map <- pit_sector_map(sig_d)
  if (is.null(sector_map)) { cat(sprintf("  %s: no sector_map, skip\n", ym)); next }

  # wide slice for compute (CR07 needs ~410d; others 365d; pass 1400d to be safe)
  rd_slice <- RAWDATA[Date <= sig_d & Date >= (sig_d - 1400L)]

  rr <- tryCatch(compute_regime(RAWDATA=rd_slice, sig_date=sig_d, FUND=NULL, CONSENSUS=CONSENSUS),
                 error=function(e){cat(sprintf("  %s regime ERR %s\n",ym,conditionMessage(e)));data.table()})
  cc <- tryCatch(compute_crowding(RAWDATA=rd_slice, sig_date=sig_d, FUND=NULL, CONSENSUS=CONSENSUS),
                 error=function(e){cat(sprintf("  %s crowd ERR %s\n",ym,conditionMessage(e)));data.table()})

  raw_new <- rbindlist(list(
    if (nrow(rr)) rr[Factor_Name %in% TARGET_FACTORS] else NULL,
    if (nrow(cc)) cc[Factor_Name %in% TARGET_FACTORS] else NULL
  ), use.names=TRUE, fill=TRUE)

  if (nrow(raw_new) == 0L) {
    # nothing computable this month (e.g. earliest months) — leave file unchanged
    audit <- rbind(audit, data.table(ym=ym, before_rows=before_rows, after_rows=before_rows,
      CR07=0L, MA06=0L, SE01=0L, RE13=0L, RE16=0L, other_unchanged=TRUE))
    next
  }

  std_new <- .standardize_factors(raw_new[, .(Ticker, Factor_Name, Raw_Value)], sector_map)
  std_new[, Date := sig_d]
  setcolorder(std_new, c("Date","Ticker","Factor_Name","Raw_Value","Z_Score","Z_Sector","Rank_Pct","Coverage"))

  combined <- rbindlist(list(other, std_new), use.names=TRUE, fill=TRUE)
  setcolorder(combined, names(existing))

  # SAFETY assertion: other-factor rows preserved exactly
  other_unchanged <- nrow(combined[!Factor_Name %in% TARGET_FACTORS]) == nrow(other)

  cnt <- function(f) nrow(std_new[Factor_Name==f])
  audit <- rbind(audit, data.table(ym=ym, before_rows=before_rows, after_rows=nrow(combined),
    CR07=cnt("CR07_Momentum_Crowding"), MA06=cnt("MA06_Risk_Sentiment_1Y"),
    SE01=cnt("SE01_Volatility_Uncertainty"), RE13=cnt("RE13_Credit_Spread_Pctile"),
    RE16=cnt("RE16_Canary_Signal"), other_unchanged=other_unchanged))

  if (!DRY_RUN) {
    if (!other_unchanged) stop(sprintf("SAFETY ABORT %s: other-factor row count changed (%d != %d)",
                                       ym, nrow(combined[!Factor_Name %in% TARGET_FACTORS]), nrow(other)))
    bkp <- file.path(BACKUP, basename(fp))
    if (!file.exists(bkp)) file.copy(fp, bkp)  # backup once
    tmp <- paste0(fp, ".tmp")
    # write with retry — WSL/OneDrive mount occasionally throws transient
    # errno 5 (I/O error) under sustained write load. Atomic .tmp->rename
    # keeps the original intact on failure; retry up to 4x with backoff.
    ok <- FALSE
    for (attempt in 1:4) {
      res <- tryCatch({ write_parquet(combined, tmp); file.rename(tmp, fp); TRUE },
                      error = function(e) { cat(sprintf("  %s write attempt %d failed: %s\n", ym, attempt, conditionMessage(e))); FALSE })
      if (isTRUE(res)) { ok <- TRUE; break }
      if (file.exists(tmp)) try(file.remove(tmp), silent = TRUE)
      Sys.sleep(3 * attempt)
    }
    if (!ok) stop(sprintf("IO_PERSISTENT %s: write failed after 4 attempts (original intact)", ym))
  }
  if (as.integer(substr(ym,5,6)) %% 12 == 1 || ym == tail(audit$ym,1))
    cat(sprintf("  %s done (CR07=%d MA06=%d SE01=%d RE13=%d RE16=%d) safe=%s\n",
        ym, cnt("CR07_Momentum_Crowding"), cnt("MA06_Risk_Sentiment_1Y"),
        cnt("SE01_Volatility_Uncertainty"), cnt("RE13_Credit_Spread_Pctile"),
        cnt("RE16_Canary_Signal"), other_unchanged))
}

out_audit <- if (!is.na(FROM_YM)) file.path(CACHE_DIR, sprintf("backfill_v8_audit_from%s.csv", FROM_YM)) else file.path(CACHE_DIR, "backfill_v8_audit.csv")
fwrite(audit, out_audit)
cat(sprintf("\n[backfill] audit -> %s\n", out_audit))
cat(sprintf("[backfill] months with CR07>0: %d | MA06>0: %d | SE01>0: %d | RE13>0: %d | RE16>0: %d\n",
    sum(audit$CR07>0), sum(audit$MA06>0), sum(audit$SE01>0), sum(audit$RE13>0), sum(audit$RE16>0)))
cat(sprintf("[backfill] other_unchanged all TRUE: %s\n", all(audit$other_unchanged)))
cat("[backfill] DONE\n")
