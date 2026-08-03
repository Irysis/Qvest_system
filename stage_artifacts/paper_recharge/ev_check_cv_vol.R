# FQ-143 CV_Vol EV Correlation Check
# Checks if CV_Vol = std(daily_Vol_21d)/mean(daily_Vol_21d) is redundant with
# L13_Vol_Variance_Ratio or L16_Turnover_Vol in Factor DB
# If mean cross-sectional Spearman correlation >= 0.9 -> EV redundant

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
}))

qm_root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(qm_root)

cat("=== FQ-143 CV_Vol EV Correlation Check ===\n")

# --- 1. Load RAWDATA (daily) ---
rawdata_path <- file.path(qm_root, ".cache/RAWDATA.parquet")
cat("[1] Loading RAWDATA from:", rawdata_path, "\n")
RD <- as.data.table(read_parquet(rawdata_path,
  col_select = c("Date","Ticker","Vol")))
RD[, Date := as.Date(Date)]
setorder(RD, Ticker, Date)
cat("RAWDATA rows:", nrow(RD), "| date range:", as.character(min(RD$Date)), "~", as.character(max(RD$Date)), "\n")

# --- 2. Compute CV_Vol rolling 21d (month-end only) ---
cat("[2] Computing CV_Vol 21d rolling...\n")
RD[, Vol := as.numeric(Vol)]

# Rolling 21d CV_Vol using shift trick: at each date, std/mean of last 21 days
# We use a month-end filter after computing
RD[, ym := format(Date, "%Y-%m")]
month_ends <- RD[, .(sig_date = max(Date)), by = ym]

# For each month-end, compute CV_Vol from preceding 21 trading days
cv_list <- list()
for (i in seq_len(nrow(month_ends))) {
  sig_d <- month_ends$sig_date[i]
  # Use last 21 trading days ENDING at sig_d (inclusive, PIT-safe)
  window_data <- RD[Date <= sig_d & Date >= sig_d - 35L]  # 35 calendar days covers ~21 trading
  # Keep last 21 trading days per ticker
  window_21 <- window_data[, .SD[.N >= 10], by = Ticker]  # need at least 10 obs
  window_21 <- window_21[, tail(.SD, 21), by = Ticker]
  cv_month <- window_21[, .(
    CV_Vol = sd(Vol, na.rm=TRUE) / mean(Vol, na.rm=TRUE),
    sig_date = sig_d
  ), by = Ticker]
  cv_list[[i]] <- cv_month
}
CV_DT <- rbindlist(cv_list)
cat("CV_Vol computed:", nrow(CV_DT), "obs | months:", uniqueN(CV_DT$sig_date), "\n")

# --- 3. Load L13/L16 from monthly factor DB (sample months) ---
cat("[3] Loading L13/L16 from Factor DB...\n")
db_dir <- file.path(qm_root, ".cache/factor_db")
# Sample months 2015-2025 (quarterly)
sample_yms <- paste0(
  rep(2015:2025, each = 4),
  sprintf("%02d", c(3, 6, 9, 12))
)
sample_yms <- c(sample_yms, "202601", "202602", "202603", "202604", "202605", "202606")

fdb_list <- list()
for (ym in sample_yms) {
  fp <- file.path(db_dir, paste0("factor_db_", ym, ".parquet"))
  if (!file.exists(fp)) next
  tryCatch({
    dt <- as.data.table(read_parquet(fp,
      col_select = c("Ticker","Date","L13_Vol_Variance_Ratio","L16_Turnover_Vol")))
    dt[, Date := as.Date(Date)]
    fdb_list[[ym]] <- dt
  }, error = function(e) NULL)
}
FDB <- rbindlist(fdb_list, fill = TRUE)
cat("Factor DB loaded:", nrow(FDB), "obs | months:", uniqueN(FDB$Date), "\n")

# --- 4. Merge and compute cross-sectional correlation ---
cat("[4] Merging CV_Vol with DB factors...\n")
# Align on month-end dates
FDB[, sig_date := Date]
MERGED <- merge(CV_DT, FDB[, .(Ticker, sig_date, L13_Vol_Variance_Ratio, L16_Turnover_Vol)],
                by = c("Ticker", "sig_date"), all = FALSE)
cat("Merged rows:", nrow(MERGED), "\n")

if (nrow(MERGED) < 100) {
  cat("WARNING: Too few observations for reliable correlation\n")
  cat("Check if L13/L16 columns exist in DB parquet\n")
  # Check column names
  if (nrow(FDB) > 0) cat("FDB columns:", paste(names(FDB), collapse=", "), "\n")
  quit(save="no", status=1)
}

# Monthly cross-sectional Spearman correlation
MERGED <- MERGED[!is.na(CV_Vol) & !is.na(L13_Vol_Variance_Ratio) & !is.na(L16_Turnover_Vol)]
cors <- MERGED[, .(
  cor_L13 = cor(CV_Vol, L13_Vol_Variance_Ratio, method="spearman", use="complete.obs"),
  cor_L16 = cor(CV_Vol, L16_Turnover_Vol, method="spearman", use="complete.obs"),
  n = .N
), by = sig_date]

cat("\n=== RESULTS ===\n")
cat("Mean Spearman cor(CV_Vol, L13_Vol_Variance_Ratio):", round(mean(cors$cor_L13, na.rm=T), 3), "\n")
cat("Mean Spearman cor(CV_Vol, L16_Turnover_Vol):", round(mean(cors$cor_L16, na.rm=T), 3), "\n")
cat("Max cor_L13:", round(max(cors$cor_L13, na.rm=T), 3), "\n")
cat("Max cor_L16:", round(max(cors$cor_L16, na.rm=T), 3), "\n")
cat("\nEV Threshold: >= 0.90 = REDUNDANT (EV_D1_GATED)\n")

mean_l13 <- mean(abs(cors$cor_L13), na.rm=T)
mean_l16 <- mean(abs(cors$cor_L16), na.rm=T)

if (max(mean_l13, mean_l16) >= 0.90) {
  cat("\nVERDICT: REDUNDANT — FQ-143 CV_Vol is EV_D1_GATED\n")
  cat("  Most correlated with:", ifelse(mean_l13 > mean_l16, "L13_Vol_Variance_Ratio", "L16_Turnover_Vol"), "\n")
} else if (max(mean_l13, mean_l16) >= 0.70) {
  cat("\nVERDICT: BORDERLINE — EV review needed\n")
  cat("  Note: mean |cor| =", round(max(mean_l13, mean_l16), 3), "(< 0.90 threshold, > 0.70 concern)\n")
} else {
  cat("\nVERDICT: NOVEL — CV_Vol is distinct from existing DB factors\n")
  cat("  Mean |cor| =", round(max(mean_l13, mean_l16), 3), "(< 0.70)\n")
  cat("  FQ-143 is testable as alpha-search candidate\n")
}
