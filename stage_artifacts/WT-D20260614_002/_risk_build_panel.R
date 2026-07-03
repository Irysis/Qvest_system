# ============================================================================
# WT-D20260614_002 RISK — Step A: build monthly FACTOR-RETURN panel (for Omega)
# Role: risk-research ONLY. Builds factor portfolio returns, NOT alpha signals.
# PIT: per-month factors via load_month_factors (C15), forward 1M return (t-1 close).
# Each factor return = EW(top-quintile aligned-z) - EW(universe) long-side spread.
# ============================================================================
suppressMessages({ library(data.table); library(arrow); library(future.apply) })
Sys.setenv(CLAUDE_PROJECT_DIR = getwd(), QM_ROOT = getwd())
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

FACTORS <- c("D01_IdioVol","D02_Beta","M07_IndMom","M01_Mom_12_1","M05_Trended_Mom",
             "Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability","V01_BM")
OUT <- "stage_artifacts/WT-D20260614_002"

# ---- monthly forward returns from RAWDATA (month-end close to next month-end) ----
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Ret","K200","KQ150","Vol")))
rd[, Date := as.Date(Date)]
rd <- rd[Date >= as.Date("2004-12-01") & !is.na(Close)]
rd[, ym := format(Date, "%Y%m")]
# month-end close per ticker
setorder(rd, Ticker, Date)
me <- rd[, .SD[.N], by = .(Ticker, ym)]   # last obs of each month
setorder(me, Ticker, ym)
me[, fwd_ret := shift(Close, -1L)/Close - 1, by = Ticker]   # NEXT month return (forward)
me[, in_univ := (K200 == TRUE | KQ150 == TRUE)]
me[, sig_date := as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))]
# month-end date label = the ym; forward return realized in ym+1
me <- me[!is.na(fwd_ret)]

# universe of months for which we have factor DB and forward returns
ym_all <- sort(unique(me$ym))
ym_all <- ym_all[ym_all >= "200501" & ym_all <= "202604"]
cat("[panel] candidate months:", length(ym_all), head(ym_all,1), "-", tail(ym_all,1), "\n")

# helper: signal date = month-end of ym
me_date <- function(ym) {
  d <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))
  seq(d, by = "month", length.out = 2)[2] - 1
}

build_one <- function(ym) {
  sig_d <- me_date(ym)
  fac <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05, factor_names = FACTORS),
                  error = function(e) NULL)
  if (is.null(fac) || !nrow(fac)) return(NULL)
  w <- dcast(fac, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  # forward returns for this ym
  rr <- me[me$ym == ym, .(Ticker, fwd_ret, in_univ, Vol)]
  m <- merge(w, rr, by = "Ticker")
  m <- m[in_univ == TRUE & is.finite(fwd_ret)]
  if (nrow(m) < 30) return(NULL)
  uni_ret <- mean(m$fwd_ret, na.rm = TRUE)
  out <- list(ym = ym, n = nrow(m), uni_ret = uni_ret)
  for (f in FACTORS) {
    if (!f %in% names(m)) { out[[f]] <- NA_real_; next }
    z <- m[[f]]; ok <- is.finite(z)
    if (sum(ok) < 20) { out[[f]] <- NA_real_; next }
    # top quintile by aligned z (higher=better) long-side EW spread vs universe
    thr <- quantile(z[ok], 0.80, na.rm = TRUE)
    topr <- mean(m$fwd_ret[ok & z >= thr], na.rm = TRUE)
    out[[f]] <- topr - uni_ret
  }
  as.data.table(out)
}

plan(multisession, workers = min(8L, parallel::detectCores() - 1L))
res <- future_lapply(ym_all, build_one, future.seed = TRUE)
plan(sequential)
panel <- rbindlist(Filter(Negate(is.null), res), fill = TRUE)
setorder(panel, ym)
cat("[panel] built months:", nrow(panel), "\n")
cat("[panel] per-factor non-NA months:\n")
print(sapply(FACTORS, function(f) sum(is.finite(panel[[f]]))))
write_parquet(panel, file.path(OUT, "_factor_return_panel.parquet"))
saveRDS(panel, file.path(OUT, "_factor_return_panel.rds"))
cat("[panel] saved.\n")
print(round(colMeans(panel[, ..FACTORS], na.rm = TRUE) * 12, 4))  # annualized mean
