# =============================================================================
# s1b_b3v.R — B3 valmom scores via fe_valmom.R VERBATIM (live load_month_factors)
#
# Fallback after s1b_b3.R spot-check FAIL: lo_screen _factor_cache.rds (built
# 2026-06-08) V01_BM differs from live load_month_factors (max|diff|=0.22 at
# 2005-06-30, same 179 tickers) -> cache shortcut REJECTED; prereg engine is
# fe_valmom.R (live connector), run verbatim (= s1_build_inputs.R step 6).
# Also logs a 3-date cache-vs-live diff summary for the honesty record.
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(arrow)
}))
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = PROJ)
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))
source(file.path(INFRA, "factor_db", "factor_db_connector.R"))
OUT <- file.path(PROJ, "04_Research/composition_search/cycle1b_trackV/inputs")
t0 <- Sys.time()

res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]

# ---- cache-vs-live diff diagnosis (record only; cache NOT used downstream) ----
FCC <- readRDS(file.path(PROJ, "stage_artifacts/alpha_search/lo_screen/_factor_cache.rds"))
VALC <- FCC[Factor_Name == "V01_BM", .(Date, Ticker, Val_cache = Z_Score_Aligned)]
rm(FCC); gc(FALSE)
for (ds in c("2005-06-30", "2015-06-30", "2024-12-30")) {
  dd <- max(VALC[Date <= as.Date(ds), Date])
  fdt <- load_month_factors(dd, coverage_min = 0.05)
  live <- fdt[Factor_Name == "V01_BM" & is.finite(Z_Score_Aligned), .(Ticker, Val_live = Z_Score_Aligned)]
  rm(fdt)
  cc <- merge(VALC[Date == dd, .(Ticker, Val_cache)], live, by = "Ticker")
  dv <- cc[, abs(Val_cache - Val_live)]
  cat(sprintf("[s1b_b3v] cache-vs-live %s: n=%d | n_diff(>1e-12)=%d | mean|d|=%.4f max|d|=%.4f cor=%.6f\n",
              as.character(dd), nrow(cc), sum(dv > 1e-12), mean(dv), max(dv),
              cc[, cor(Val_cache, Val_live)]))
}
rm(VALC); gc(FALSE)

# ---- fe_valmom.R verbatim (s1_build_inputs.R step 6) ----
cat("[s1b_b3v] sourcing fe_valmom.R (live monthly V01_BM loop + momentum)...\n")
source(file.path(INFRA, "alpha_search", "fe_valmom.R"))
stopifnot(exists("FACTORS"), all(c("Date", "Ticker", "Score", "N") %in% names(FACTORS)))
write_parquet(FACTORS, file.path(OUT, "b3_scores.parquet"))
cat(sprintf("[s1b_b3v] b3_scores saved: %d rows, %d months | %.1f min\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cat("[s1b_b3v] DONE\n")
