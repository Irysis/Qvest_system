# FQ-143 CV_Vol EV Correlation Check v2 (long-format DB)
# Factor DB is LONG: columns = Date, Ticker, Factor_Name, Raw_Value, Z_Score, ...
# Must filter by Factor_Name

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
}))

qm_root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(qm_root)
cat("=== FQ-143 CV_Vol EV Correlation Check v2 ===\n")

# --- 1. Load RAWDATA (daily) ---
cat("[1] Loading RAWDATA...\n")
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
  col_select = c("Date","Ticker","Vol")))
RD[, Date := as.Date(Date)]
RD[, Vol := as.numeric(Vol)]
setorder(RD, Ticker, Date)

# Restrict to 2010+ for speed
RD <- RD[Date >= as.Date("2010-01-01")]
cat("RAWDATA rows (2010+):", nrow(RD), "\n")

# --- 2. Compute CV_Vol monthly ---
cat("[2] Computing CV_Vol 21d monthly...\n")
RD[, ym := format(Date, "%Y-%m")]
month_ends <- RD[, .(sig_date = max(Date)), by = ym]

cv_list <- list()
for (i in seq_len(nrow(month_ends))) {
  sig_d <- month_ends$sig_date[i]
  # Last 21 trading days ending on sig_d
  window_data <- RD[Date <= sig_d & Date >= sig_d - 35L]
  window_21 <- window_data[, {
    tmp <- tail(.SD, 21)
    if (nrow(tmp) >= 10) {
      list(CV_Vol = sd(tmp$Vol, na.rm=TRUE) / mean(tmp$Vol, na.rm=TRUE))
    } else {
      list(CV_Vol = NA_real_)
    }
  }, by = Ticker]
  window_21[, sig_date := sig_d]
  cv_list[[i]] <- window_21[!is.na(CV_Vol)]
}
CV_DT <- rbindlist(cv_list)
cat("CV_Vol obs:", nrow(CV_DT), "| months:", uniqueN(CV_DT$sig_date), "\n")

# --- 3. Load L13/L16 from long-format DB ---
cat("[3] Loading L13/L16 from Factor DB (long format)...\n")
db_dir <- ".cache/factor_db"
# Sample months quarterly 2010-2026
sample_yms <- do.call(c, lapply(2010:2026, function(y) {
  paste0(y, sprintf("%02d", c(3, 6, 9, 12)))
}))
sample_yms <- sample_yms[sample_yms <= "202606"]

fdb_list <- list()
for (ym in sample_yms) {
  fp <- file.path(db_dir, paste0("factor_db_", ym, ".parquet"))
  if (!file.exists(fp)) next
  tryCatch({
    dt <- as.data.table(read_parquet(fp,
      col_select = c("Date","Ticker","Factor_Name","Raw_Value")))
    dt <- dt[Factor_Name %in% c("L13_Vol_Variance_Ratio","L16_Turnover_Vol")]
    if (nrow(dt) > 0) {
      dt[, Date := as.Date(Date)]
      fdb_list[[ym]] <- dt
    }
  }, error = function(e) NULL)
}

if (length(fdb_list) == 0) {
  cat("ERROR: No L13/L16 found in DB. Checking available Factor_Names in 202506...\n")
  fp <- file.path(db_dir, "factor_db_202506.parquet")
  dt_check <- as.data.table(read_parquet(fp, col_select = c("Factor_Name")))
  liq_factors <- unique(dt_check$Factor_Name)[grepl("^L", unique(dt_check$Factor_Name))]
  cat("L-series factors in DB (202506):", paste(sort(liq_factors), collapse=", "), "\n")
  quit(save="no", status=1)
}

FDB <- rbindlist(fdb_list)
FDB_WIDE <- dcast(FDB, Date + Ticker ~ Factor_Name, value.var = "Raw_Value")
cat("Factor DB (wide) rows:", nrow(FDB_WIDE), "| months:", uniqueN(FDB_WIDE$Date), "\n")

# --- 4. Merge & correlate ---
cat("[4] Computing cross-sectional correlations...\n")
FDB_WIDE[, sig_date := Date]
MERGED <- merge(CV_DT, FDB_WIDE[, .(Ticker, sig_date, L13_Vol_Variance_Ratio, L16_Turnover_Vol)],
                by = c("Ticker","sig_date"), all = FALSE)
MERGED <- MERGED[!is.na(CV_Vol) & (!is.na(L13_Vol_Variance_Ratio) | !is.na(L16_Turnover_Vol))]
cat("Merged obs:", nrow(MERGED), "\n")

if (nrow(MERGED) < 50) {
  cat("WARN: Too few merged obs. L13/L16 might not be in DB.\n")
  quit(save="no", status=1)
}

cors <- MERGED[, .(
  cor_L13 = if(sum(!is.na(L13_Vol_Variance_Ratio)) > 10) {
    cor(CV_Vol, L13_Vol_Variance_Ratio, method="spearman", use="complete.obs")
  } else NA_real_,
  cor_L16 = if(sum(!is.na(L16_Turnover_Vol)) > 10) {
    cor(CV_Vol, L16_Turnover_Vol, method="spearman", use="complete.obs")
  } else NA_real_,
  n = .N
), by = sig_date]

mean_l13 <- mean(abs(cors$cor_L13), na.rm=TRUE)
mean_l16 <- mean(abs(cors$cor_L16), na.rm=TRUE)

cat("\n===== EV CORRELATION RESULTS =====\n")
cat("Mean |Spearman| cor(CV_Vol, L13_Vol_Variance_Ratio):", round(mean_l13, 3), "\n")
cat("Mean |Spearman| cor(CV_Vol, L16_Turnover_Vol):", round(mean_l16, 3), "\n")
cat("Months measured:", sum(!is.na(cors$cor_L13) | !is.na(cors$cor_L16)), "\n")
cat("\nEV Threshold: mean |cor| >= 0.90 = REDUNDANT\n")

max_cor <- max(mean_l13, mean_l16, na.rm=TRUE)
if (is.na(max_cor) || max_cor >= 0.90) {
  cat("VERDICT: EV_D1_GATED (redundant with existing DB factor)\n")
  if (!is.na(max_cor)) {
    partner <- ifelse(mean_l13 > mean_l16, "L13_Vol_Variance_Ratio", "L16_Turnover_Vol")
    cat("  Most similar to:", partner, "| cor=", round(max_cor, 3), "\n")
  }
} else if (max_cor >= 0.70) {
  cat("VERDICT: BORDERLINE — EV review needed. max |cor|=", round(max_cor, 3), "\n")
  cat("  → Suggest dcast comparison before full alpha-search\n")
} else {
  cat("VERDICT: NOVEL — CV_Vol is distinct from existing L13/L16. |cor|=", round(max_cor, 3), "\n")
  cat("  → FQ-143 is testable as alpha-search candidate\n")
}
