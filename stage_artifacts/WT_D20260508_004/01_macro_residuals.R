#==============================================================================
# WT-D20260508_004 — Step 1: Macro Residual Extraction
#
# Goal: 13 macro variables (KR ECOS 7 + FRED 6) → monthly innovations
#       (AR(1) + month-of-year FE residuals) → "unexpected shocks"
#
# PIT contract:
#   - Each shock at month t uses only data available at t (close-of-month publish)
#   - AR(1) coefficient estimated on EXPANDING window with 36-month burn-in
#     to avoid look-ahead in shock definition.
#
# Output: stage_artifacts/WT_D20260508_004/macro_shocks_monthly.parquet
#         columns: ym (yearmonth), macro_var, level, ar1_resid, ar1_resid_z
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(zoo)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_004")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

cat("[01] loading macro sources …\n")

# 1. FRED wide (US 거시)
fred <- as.data.table(read_parquet(file.path(PROJ, ".cache", "fred_macro_wide.parquet")))
setnames(fred, "Date", "Date")
fred <- fred[!is.na(Date)]
fred[, Date := as.Date(Date)]

# 2. ECOS bond (KR 채권/콜)
ecos_b <- as.data.table(read_parquet(file.path(PROJ, ".cache", "ecos_bond_rates.parquet")))
ecos_b[, Date := as.Date(Date)]
ecos_w <- dcast(ecos_b, Date ~ Series, value.var = "Value")

# 3. ECOS KRW/USD (already in fred_macro_wide as KRW_USD, but ECOS is more complete)
ecos_fx <- as.data.table(read_parquet(file.path(PROJ, ".cache", "ecos_krw_usd.parquet")))
ecos_fx[, Date := as.Date(Date)]
setnames(ecos_fx, "KRW_USD", "KRW_USD_ECOS")

# Merge daily series → align on Date
all_daily <- merge(ecos_w, ecos_fx, by = "Date", all = TRUE)
fred_keep <- fred[, .(Date, VIX, US_10Y_Yield, US_2Y_Yield, KRW_USD,
                      Term_Spread, Breakeven_5Y)]
all_daily <- merge(all_daily, fred_keep, by = "Date", all = TRUE)

# Construct daily KR-specific macro series + cross-spreads
all_daily[, KR_TermSpread := KR_Gov10Y - KR_Gov3Y]   # KR yield curve slope
all_daily[, KR_CreditSpread := KR_CorpBBB - KR_Gov3Y] # KR credit risk
all_daily[, KR_CallRate := KR_Call1D]                 # KR short rate
all_daily[, KR_FX := ifelse(!is.na(KRW_USD_ECOS), KRW_USD_ECOS, KRW_USD)]
all_daily[, US_TermSpread := US_10Y_Yield - US_2Y_Yield]

# Final daily wide → fill forward (calendar fill within 5 day gap, no future)
setorder(all_daily, Date)
keep_cols <- c(
  # KR macro (7)
  "KR_Gov3Y", "KR_Gov10Y", "KR_TermSpread", "KR_CreditSpread",
  "KR_CallRate", "KR_FX", "KR_CD91",
  # Global (6)
  "VIX", "US_10Y_Yield", "US_TermSpread", "Breakeven_5Y", "KRW_USD", "US_2Y_Yield"
)
keep_cols <- intersect(keep_cols, names(all_daily))

# Forward-fill (only past) within max-7d gap
for (cc in keep_cols) {
  set(all_daily, j = cc,
      value = na.locf(all_daily[[cc]], na.rm = FALSE, maxgap = 7L))
}

# Aggregate to month-end (last available date in month)
all_daily[, ym := format(Date, "%Y-%m")]
month_lvl <- all_daily[, lapply(.SD, function(x) tail(x[!is.na(x)], 1)),
                       by = ym, .SDcols = keep_cols]
# tail returns numeric(0) if all NA → keep NA
for (cc in keep_cols) {
  month_lvl[, (cc) := sapply(get(cc), function(v) if(length(v)==0) NA_real_ else v)]
}
month_lvl[, Date := as.Date(paste0(ym, "-01"))]
setorder(month_lvl, Date)
cat("[01] monthly panel:", nrow(month_lvl), "months,",
    length(keep_cols), "macro vars\n")

# ---- Compute monthly changes (level → first difference for I(1) suspects) ----
# For yields/spreads: first diff.  For VIX/FX: log change.
log_diff <- function(x) c(NA, diff(log(pmax(x, 1e-6))))
first_diff <- function(x) c(NA, diff(x))

month_lvl[, KR_Gov3Y_d        := first_diff(KR_Gov3Y)]
month_lvl[, KR_Gov10Y_d       := first_diff(KR_Gov10Y)]
month_lvl[, KR_TermSpread_d   := first_diff(KR_TermSpread)]
month_lvl[, KR_CreditSpread_d := first_diff(KR_CreditSpread)]
month_lvl[, KR_CallRate_d     := first_diff(KR_CallRate)]
month_lvl[, KR_CD91_d         := first_diff(KR_CD91)]
month_lvl[, KR_FX_lr          := log_diff(KR_FX)]
month_lvl[, VIX_lr            := log_diff(VIX)]
month_lvl[, US_10Y_Yield_d    := first_diff(US_10Y_Yield)]
month_lvl[, US_TermSpread_d   := first_diff(US_TermSpread)]
month_lvl[, Breakeven_5Y_d    := first_diff(Breakeven_5Y)]
month_lvl[, KRW_USD_lr        := log_diff(KRW_USD)]

shock_vars <- c(
  "KR_Gov3Y_d", "KR_Gov10Y_d", "KR_TermSpread_d", "KR_CreditSpread_d",
  "KR_CallRate_d", "KR_CD91_d", "KR_FX_lr",
  "VIX_lr", "US_10Y_Yield_d", "US_TermSpread_d", "Breakeven_5Y_d", "KRW_USD_lr"
)

# ---- AR(1) residual extraction with EXPANDING window (PIT-safe) ----
# At month t: estimate AR(1) on data 1..t-1, residual_t = x_t - phi_hat * x_{t-1}
# Burn-in: 36 months minimum
extract_ar_resid <- function(x, burn = 36L) {
  n <- length(x)
  res <- rep(NA_real_, n)
  for (t in (burn+2):n) {
    y <- x[2:(t-1)]; lagy <- x[1:(t-2)]
    ok <- !is.na(y) & !is.na(lagy)
    if (sum(ok) < burn) next
    fit <- tryCatch(lm(y ~ lagy, subset = ok), error=function(e) NULL)
    if (is.null(fit) || !is.finite(coef(fit)[1])) next
    if (is.na(x[t]) || is.na(x[t-1])) next
    pred <- coef(fit)[1] + coef(fit)[2] * x[t-1]
    res[t] <- x[t] - pred
  }
  res
}

cat("[01] computing AR(1) expanding residuals (PIT-safe, 36m burn-in) …\n")
shock_dt <- copy(month_lvl[, .(Date, ym)])
for (sv in shock_vars) {
  if (!sv %in% names(month_lvl)) next
  x <- month_lvl[[sv]]
  res <- extract_ar_resid(x, burn = 36L)
  # cross-section z-score (vs expanding own history)
  z <- rep(NA_real_, length(res))
  for (t in seq_along(res)) {
    if (is.na(res[t])) next
    hist <- res[1:(t-1)]
    hist <- hist[!is.na(hist)]
    if (length(hist) < 24L) next
    sigma <- sd(hist); mu <- mean(hist)
    z[t] <- (res[t] - mu) / max(sigma, 1e-8)
  }
  shock_dt[, (paste0(sv, "_resid")) := res]
  shock_dt[, (paste0(sv, "_z")) := z]
}

cat("[01] residuals ready. saving …\n")
write_parquet(shock_dt, file.path(OUT, "macro_shocks_monthly.parquet"))
cat("[01] done. rows:", nrow(shock_dt), " cols:", ncol(shock_dt), "\n")

# ---- Sanity: post-2010 coverage ----
sub <- shock_dt[Date >= "2010-01-01"]
cat("\n[01] coverage 2010+ (% non-NA):\n")
sapply(sub[, .SD, .SDcols = patterns("_resid$")], function(x) round(mean(!is.na(x)),3)) |>
  print()
