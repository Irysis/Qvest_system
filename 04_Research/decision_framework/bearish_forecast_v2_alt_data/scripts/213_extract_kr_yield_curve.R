#==============================================================================
# 213_extract_kr_yield_curve.R — Cycle 58L
#
# KR_Macro.xlsx Interest sheet → KR 진정 yield curve PIT features.
#
# 8 series 일별 (1990~2026.02):
#   CD_91 (91d), 국고1y, 3y, 5y, 10y, 20y, 30y, 회사채 AA- 3y
#
# PIT features (lag1 + dynamics):
#   1. Levels: cd91, ktb1y, ktb3y, ktb5y, ktb10y, ktb20y, ktb30y, cb3y (8개)
#   2. Slopes: ktb10y-ktb1y (term premium), ktb10y-cd91 (steepness),
#              ktb5y-ktb1y (short), ktb20y-ktb10y (long)
#   3. Curvature: (ktb5y - ktb1y) - (ktb10y - ktb5y) (mid-belly)
#   4. Credit spread: cb3y - ktb3y (corp risk premium)
#   5. Changes (5d, 21d) for key slopes
#==============================================================================

suppressPackageStartupMessages({
  library(readxl); library(data.table); library(arrow)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data")
OUT_PATH <- file.path(WS, "outputs/01_data/kr_yield_curve_features.parquet")
SRC <- file.path(PROJECT_ROOT, "03_Universe/KR_Macro.xlsx")

cat(sprintf("[%s] Reading KR_Macro Interest sheet...\n",
            format(Sys.time(), "%H:%M:%S")))
d <- as.data.table(read_excel(SRC, sheet = "Interest", skip = 14,
                              col_names = FALSE, col_types = "text"))
old_names <- names(d)
setnames(d, old_names[1], "Date")
yc_cols <- c("cd91", "ktb1y", "ktb3y", "ktb5y", "ktb10y", "ktb20y",
             "ktb30y", "cb3y_aa")
setnames(d, old_names[2:9], yc_cols)

# Date parsing (Excel serial)
d[, Date := as.Date(as.numeric(Date), origin = "1899-12-30")]
setorder(d, Date)
cat(sprintf("  Rows: %d, Date range: %s ~ %s\n",
            nrow(d), as.character(min(d$Date, na.rm=T)),
            as.character(max(d$Date, na.rm=T))))

# Convert to numeric
for (c in yc_cols) {
  d[[c]] <- as.numeric(d[[c]])
}

# === PIT features (all lag1) ===
# 1. Slopes
d[, kr_term_premium := ktb10y - ktb1y]
d[, kr_steepness := ktb10y - cd91]
d[, kr_short_slope := ktb5y - ktb1y]
d[, kr_long_slope := ktb20y - ktb10y]
# 2. Curvature (negative = mid-belly cheap)
d[, kr_curvature := (ktb5y - ktb1y) - (ktb10y - ktb5y)]
# 3. Credit spread
d[, kr_credit_spread := cb3y_aa - ktb3y]
# 4. Changes (5d) for key slopes
d[, kr_term_chg5 := kr_term_premium - shift(kr_term_premium, 5)]
d[, kr_credit_chg5 := kr_credit_spread - shift(kr_credit_spread, 5)]
# 5. Long rate changes (5d)
d[, kr_10y_chg5 := ktb10y - shift(ktb10y, 5)]
d[, kr_3y_chg5 := ktb3y - shift(ktb3y, 5)]

# 6. EBP (Excess Bond Premium analog) deeper features
#    Gilchrist-Zakrajsek 2012 (AER) — credit spread historical extreme + dynamics
# Rolling z-score (5y window, PIT — expanding using past only)
roll_z_5y <- function(x, min_obs = 1260L) {
  n <- length(x); z <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i < min_obs) next
    hist <- x[1:(i - 1)]
    mu <- mean(hist, na.rm = TRUE); s <- sd(hist, na.rm = TRUE)
    if (is.na(s) || s < 1e-9) next
    z[i] <- (x[i] - mu) / s
  }
  z
}
d[, kr_ebp_rolling_z_5y := roll_z_5y(kr_credit_spread)]
d[, kr_ebp_rm21 := frollmean(kr_credit_spread, 21)]
d[, kr_ebp_chg21 := kr_credit_spread - shift(kr_credit_spread, 21)]

# Lag1 all features (PIT)
features <- c("ktb10y", "ktb3y", "kr_term_premium", "kr_steepness",
              "kr_curvature", "kr_credit_spread",
              "kr_term_chg5", "kr_credit_chg5",
              "kr_10y_chg5", "kr_3y_chg5",
              "kr_ebp_rolling_z_5y", "kr_ebp_rm21", "kr_ebp_chg21")
for (f in features) {
  d[[paste0(f, "_lag1")]] <- shift(d[[f]], 1, type = "lag")
}

# Keep Date + lag1 features
keep <- c("Date", paste0(features, "_lag1"))
out <- d[, ..keep]

# Validation
cat(sprintf("\n[%s] %d PIT features\n", format(Sys.time(), "%H:%M:%S"),
            length(features)))
for (col in paste0(features, "_lag1")) {
  v <- out[[col]]
  cat(sprintf("  %-26s n_non_na=%d  range=[%.3f, %.3f]\n",
              col, sum(!is.na(v)),
              min(v, na.rm=T), max(v, na.rm=T)))
}

write_parquet(out, OUT_PATH)
cat(sprintf("\n[%s] Saved: %s (%d rows × %d cols)\n",
            format(Sys.time(), "%H:%M:%S"), OUT_PATH,
            nrow(out), ncol(out)))
