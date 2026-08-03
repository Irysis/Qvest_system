# Quick EV check: single month correlation CV_Vol vs L13/L16
library(arrow); library(data.table)
qm_root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(qm_root)

# Load RAWDATA daily - last 2 months only
RD <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
  col_select = c("Date","Ticker","Vol")))
RD[, Date := as.Date(Date)]
RD[, Vol := as.numeric(Vol)]
RD <- RD[Date >= as.Date("2026-04-01")]  # 3 months for rolling
setorder(RD, Ticker, Date)
cat("RAWDATA rows (recent):", nrow(RD), "\n")

# Compute CV_Vol for June 2026 month-end
sig_date <- as.Date("2026-06-30")
# Get last trading day in June
june_dates <- RD[format(Date,"%Y-%m")=="2026-06", unique(Date)]
if (length(june_dates) == 0) {
  cat("No June 2026 data\n")
  quit()
}
sig_date <- max(june_dates)
cat("Signal date:", as.character(sig_date), "\n")

# Compute CV_Vol for each ticker
window_data <- RD[Date <= sig_date]
cv_june <- window_data[, {
  tmp <- tail(.SD[order(Date)], 21)
  if (nrow(tmp) >= 10 && mean(tmp$Vol, na.rm=T) > 0) {
    list(CV_Vol = sd(tmp$Vol, na.rm=T) / mean(tmp$Vol, na.rm=T))
  } else list(CV_Vol = NA_real_)
}, by = Ticker]
cv_june <- cv_june[!is.na(CV_Vol)]
cat("CV_Vol (June 2026):", nrow(cv_june), "tickers\n")

# Load L13/L16 from DB for June 2026
fp <- ".cache/factor_db/factor_db_202606.parquet"
db <- as.data.table(read_parquet(fp))
cat("DB columns:", paste(names(db)[1:5], collapse=", "), "\n")
cat("Unique Factor_Names in DB:", length(unique(db$Factor_Name)), "\n")
# Filter L13/L16
l13 <- db[Factor_Name == "L13_Vol_Variance_Ratio", .(Ticker, Raw_L13 = Raw_Value)]
l16 <- db[Factor_Name == "L16_Turnover_Vol", .(Ticker, Raw_L16 = Raw_Value)]
cat("L13 rows:", nrow(l13), "| L16 rows:", nrow(l16), "\n")

# Merge
merged <- merge(cv_june, l13, by="Ticker", all=FALSE)
merged <- merge(merged, l16, by="Ticker", all=FALSE)
merged <- merged[!is.na(CV_Vol) & !is.na(Raw_L13) & !is.na(Raw_L16)]
cat("Merged rows:", nrow(merged), "\n")

if (nrow(merged) < 20) {
  cat("ERROR: Too few merged obs\n")
  print(head(cv_june))
  print(head(l13))
  quit()
}

cor_l13 <- cor(merged$CV_Vol, merged$Raw_L13, method="spearman", use="complete.obs")
cor_l16 <- cor(merged$CV_Vol, merged$Raw_L16, method="spearman", use="complete.obs")

cat("\n===== QUICK EV RESULT (June 2026) =====\n")
cat("Spearman cor(CV_Vol, L13_Vol_Variance_Ratio):", round(cor_l13, 3), "\n")
cat("Spearman cor(CV_Vol, L16_Turnover_Vol):", round(cor_l16, 3), "\n")

max_cor <- max(abs(cor_l13), abs(cor_l16))
if (max_cor >= 0.90) {
  cat("VERDICT: REDUNDANT (EV_D1_GATED)\n")
} else if (max_cor >= 0.70) {
  cat("VERDICT: BORDERLINE — need multi-month check\n")
} else {
  cat("VERDICT: NOVEL — proceed to alpha-search\n")
}
