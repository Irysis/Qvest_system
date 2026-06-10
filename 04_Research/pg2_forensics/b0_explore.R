# b0_explore.R — PG2 forensics: data reconnaissance (diagnostic only)
# Verifies: alpha_scores parquet structure, PIT structure of Ret_1m,
# factor name availability in Factor DB cache, IC history availability.
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")

# 1. alpha scores parquet
as_path <- file.path(PROD_DIR, "02_holdings_universe/alpha_scores_str1715_268m.parquet")
sc <- as.data.table(read_parquet(as_path))
cat("=== alpha_scores ===\n")
cat("rows:", nrow(sc), " cols:", paste(names(sc), collapse=", "), "\n")
cat("class(Date):", class(sc$Date), "\n")
sc[, Date := as.Date(Date)]
dates <- sort(unique(sc$Date))
cat("n_dates:", length(dates), " range:", format(min(dates)), "to", format(max(dates)), "\n")
cat("day-of-month table (head):\n"); print(head(table(format(dates, "%d")), 10))
cat("stocks per date summary:\n"); print(summary(sc[, .N, by=Date]$N))
cat("NA counts:\n"); print(sapply(sc, function(x) sum(is.na(x))))
cat("theta_core summary:\n"); print(summary(sc$theta_core))
cat("theta_defense summary:\n"); print(summary(sc$theta_defense))
cat("regime_state table:\n"); print(table(sc[, .(r=regime_state[1]), by=Date]$r, useNA="ifany"))
cat("sample rows:\n"); print(head(sc, 3))
cat("last date sample:\n"); print(head(sc[Date == max(Date)], 3))

# 2. PIT check of Ret_1m: is Ret_1m the forward return t -> t+1?
# Compare with RAWDATA-free approach: take a ticker, check Ret_1m at date t vs
# score-date spacing. We can't load RAWDATA here cheaply; instead verify internal
# consistency: Ret_1m at last available date should be mostly NA if forward.
last_d <- max(dates)
cat("\n=== PIT structure check ===\n")
cat("NA share of Ret_1m at LAST date:", sc[Date==last_d, mean(is.na(Ret_1m))], "\n")
cat("NA share of Ret_1m overall:", sc[, mean(is.na(Ret_1m))], "\n")
# Cross-check vs period_returns ret_orig: portfolio top-20 by score_eff at t,
# EW mean Ret_1m should roughly track realized ret of month t+1 (gross, no cost)
pr <- fread(file.path(PROD_DIR, "04_backtest_results/period_returns_layer5.csv"))
cat("period_returns rows:", nrow(pr), " realized_ym range:", pr[1, realized_ym], "to", pr[.N, realized_ym], "\n")

# top-20 EW forward return per score date
top20 <- sc[!is.na(score_eff), .SD[order(-score_eff)][1:20], by=Date]
ew <- top20[, .(ew_ret = mean(Ret_1m, na.rm=TRUE)), by=Date]
ew[, ym_t  := format(Date, "%Y-%m")]
# hypothesis A: Ret_1m is return of month t+1 (forward) -> matches realized_ym of t+1
ew[, ym_tp1 := format(seq(Date, by="1 month", length.out=2)[2], "%Y-%m"), by=Date]
mA <- merge(ew[, .(ym = ym_tp1, ew_ret)], pr[, .(ym = realized_ym, ret_orig)], by="ym")
mB <- merge(ew[, .(ym = ym_t,   ew_ret)], pr[, .(ym = realized_ym, ret_orig)], by="ym")
cat("corr(EW top20 Ret_1m @t, ret_orig @t+1) [forward hypothesis]:", mA[, cor(ew_ret, ret_orig, use="complete.obs")], "n=", nrow(mA), "\n")
cat("corr(EW top20 Ret_1m @t, ret_orig @t)   [same-month hypothesis]:", mB[, cor(ew_ret, ret_orig, use="complete.obs")], "n=", nrow(mB), "\n")

# 3. Factor DB: check 7 factor names exist
cat("\n=== Factor DB factor-name check ===\n")
targets <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap",
             "Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
fdb_dir <- file.path(PROJECT_ROOT, ".cache/factor_db")
for (ym in c("201001","201801","202403","202602")) {
  fp <- file.path(fdb_dir, paste0("factor_db_", ym, ".parquet"))
  if (!file.exists(fp)) { cat(ym, ": MISSING\n"); next }
  fn <- unique(as.data.table(read_parquet(fp, col_select=c("Factor_Name")))$Factor_Name)
  hit <- targets %in% fn
  cat(ym, ": present", sum(hit), "/7 | missing:", paste(targets[!hit], collapse=", "), "\n")
  # fuzzy candidates for missing
  for (t in targets[!hit]) {
    stem <- strsplit(t, "_")[[1]][1]
    cand <- grep(paste0("^", stem), fn, value=TRUE)
    cat("   candidates for ", t, ": ", paste(head(cand,8), collapse=", "), "\n", sep="")
  }
}

# 4. IC history parquet availability
icp <- file.path(fdb_dir, "factor_ic_monthly.parquet")
cat("\nIC history exists:", file.exists(icp), "\n")
if (file.exists(icp)) {
  ic <- as.data.table(read_parquet(icp))
  cat("IC history cols:", paste(names(ic), collapse=", "), " rows:", nrow(ic), "\n")
  cat("IC rows for 7 targets:\n")
  print(ic[Factor_Name %in% targets, .N, by=Factor_Name])
  cat("IC Date range:", format(min(as.Date(ic$Date))), "to", format(max(as.Date(ic$Date))), "\n")
}
cat("\n[b0_explore] DONE\n")
