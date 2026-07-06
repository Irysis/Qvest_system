# extract_scores.R — pull V02_EP + WT_012 9-factor composite (PIT-aligned) per month.
# Uses load_month_factors() (C15-safe connector, Z_Score_Aligned higher=better).
# Writes small parquet: stage_artifacts/largecap_value_escape/factor_scores.parquet
# Single-threaded to avoid arrow/data.table segfaults on OneDrive.

suppressMessages({
  library(data.table); library(arrow)
})
try(setDTthreads(1L), silent = TRUE)
try(arrow::set_cpu_count(1L), silent = TRUE)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/largecap_value_escape")
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

# WT_012 composite factor set (EW of 9 aligned factors) + V02_EP standalone
COMP_FACTORS <- c("M01_Mom_12_1","M08_Residual_Mom","Q01_GPA","Q35_CashBased_OpProf",
                  "Q07_Earnings_Stability","V02_EP","V12_Composite_Value","D01_IdioVol","L01_Amihud")
VAL_FACTORS  <- c("V02_EP","V12_Composite_Value")

# months: month-end sig_dates 2009-06 .. 2026-06 (align to panel's sig_date)
panel <- as.data.table(arrow::read_parquet(file.path(OUT, "panel_returns.parquet")))
sig_dates <- sort(unique(as.Date(panel$sig_date)))
cat(sprintf("[extract] %d sig_dates %s .. %s\n", length(sig_dates),
            as.character(min(sig_dates)), as.character(max(sig_dates))))

want <- unique(c(COMP_FACTORS, VAL_FACTORS))
res <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  fm <- tryCatch(load_month_factors(sd, coverage_min = 0.05, factor_names = want),
                 error = function(e) NULL)
  if (is.null(fm) || nrow(fm) == 0) next
  fm <- fm[Factor_Name %in% want]
  # wide: Ticker x factor
  w <- dcast(fm, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
             fun.aggregate = function(x) mean(x, na.rm = TRUE))
  # composite = EW mean of available COMP_FACTORS (cross-sectional Z already standardized)
  comp_cols <- intersect(COMP_FACTORS, names(w))
  val_cols  <- intersect(VAL_FACTORS,  names(w))
  w[, comp_score := rowMeans(as.matrix(.SD), na.rm = TRUE), .SDcols = comp_cols]
  if (length(val_cols) >= 1) {
    w[, val_score := rowMeans(as.matrix(.SD), na.rm = TRUE), .SDcols = val_cols]
  } else w[, val_score := NA_real_]
  keep_cols <- c("Ticker","comp_score","val_score", intersect(c("V02_EP","V12_Composite_Value"), names(w)))
  ws <- w[, ..keep_cols]
  ws[, sig_date := as.character(sd)]
  res[[i]] <- ws
  if (i %% 24 == 0) cat(sprintf("  ..%d/%d (%s) n=%d\n", i, length(sig_dates), as.character(sd), nrow(ws)))
}
out <- rbindlist(res, use.names = TRUE, fill = TRUE)
cat(sprintf("[extract] total rows=%d, months=%d\n", nrow(out), uniqueN(out$sig_date)))
cat("[extract] non-NA: V02_EP=%d comp=%d val=%d\n")
cat(sprintf("  V02_EP non-NA: %d | comp_score non-NA: %d | val_score non-NA: %d\n",
            sum(!is.na(out$V02_EP)), sum(!is.na(out$comp_score)), sum(!is.na(out$val_score))))
arrow::write_parquet(out, file.path(OUT, "factor_scores.parquet"))
cat("[extract] wrote factor_scores.parquet\n")
