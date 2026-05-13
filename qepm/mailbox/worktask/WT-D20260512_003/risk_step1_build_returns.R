#==============================================================================
# Risk Step 1: Monthly Return Matrix + FF-Carhart-Quality Factor TS Construction
#
# Universe: alpha emission universe (846 tickers historical, 238 at 2026-04-01)
# Period: 2004-01 ~ 2026-04 (268 months, matches alpha emission span)
# PIT: t-1 monthly close, expanding rolling, returns at sig_date+1m.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(zoo)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

OUT_DIR <- "stage_artifacts/WT_D20260512_003"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ── 1. Alpha emission universe ──────────────────────────────────────────────
alpha_dt <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_scores_new.parquet")))
universe <- sort(unique(alpha_dt$Ticker))
cat("[Step1] Alpha emission universe:", length(universe), "tickers\n")

# Restrict to ticker active universe at last sig_date (238 tickers)
universe_eff <- sort(unique(alpha_dt[Date == max(Date) & !is.na(z_blend_composite), Ticker]))
cat("[Step1] Effective universe (2026-04-01):", length(universe_eff), "tickers\n")

# ── 2. Build monthly returns ────────────────────────────────────────────────
RAWDATA <- as.data.table(read_parquet(RAWDATA_CACHE))
setkey(RAWDATA, Date, Ticker)
RD <- RAWDATA[Ticker %in% universe & Date >= as.Date("2003-12-01") & Date <= as.Date("2026-04-30"),
              .(Date, Ticker, Close, Vol, Size, BM_Ret, K200, KQ150, AdminStock, TradingHalt)]
RD[, YM := as.Date(format(Date, "%Y-%m-01"))]
mret <- RD[order(Date), .SD[.N], by = .(Ticker, YM)]
mret[, Ret_m := (Close / shift(Close)) - 1, by = Ticker]
mret[, Date := YM]
mret <- mret[Date >= as.Date("2004-01-01") & Date <= as.Date("2026-04-01")]
cat("[Step1] Monthly return rows:", nrow(mret), "  unique sig_dates:", uniqueN(mret$Date), "\n")

# Wide return matrix: rows = sig_date, cols = ticker
ret_wide <- dcast(mret, Date ~ Ticker, value.var = "Ret_m")
setorder(ret_wide, Date)
cat("[Step1] Wide matrix:", nrow(ret_wide), "x", ncol(ret_wide), "\n")

write_parquet(ret_wide, file.path(OUT_DIR, "_risk_monthly_returns_wide.parquet"))
write_parquet(mret, file.path(OUT_DIR, "_risk_monthly_returns_long.parquet"))

# ── 3. KR Market portfolio (BM_Ret monthly) ─────────────────────────────────
bm_monthly <- RAWDATA[Date >= as.Date("2003-12-01") & !is.na(BM_Ret),
                      .(BM_Ret_d = mean(BM_Ret, na.rm=TRUE)), by = Date]
bm_monthly[, YM := as.Date(format(Date, "%Y-%m-01"))]
bm_m <- bm_monthly[order(Date), .(BM_m = prod(1 + BM_Ret_d, na.rm=TRUE) - 1), by = YM]
bm_m[, Date := YM]
bm_m <- bm_m[Date >= as.Date("2004-01-01") & Date <= as.Date("2026-04-01"), .(Date, RM = BM_m)]
write_parquet(bm_m, file.path(OUT_DIR, "_risk_market_monthly.parquet"))
cat("[Step1] Market monthly rows:", nrow(bm_m), "\n")

# ── 4. Factor TS via quintile spread on Z_Score_Aligned ─────────────────────
sig_dates <- sort(unique(mret$Date))
n_sig <- length(sig_dates)
cat("[Step1] Building factor TS over", n_sig, "sig_dates...\n")

cross_sec_qspread <- function(values, returns_next, q = 5) {
  ok <- !is.na(values) & !is.na(returns_next)
  if (sum(ok) < 30) return(NA_real_)
  v <- values[ok]; r <- returns_next[ok]
  brks <- quantile(v, probs = seq(0, 1, length.out = q+1), na.rm=TRUE, type=7)
  brks[1] <- brks[1] - 1e-9; brks[q+1] <- brks[q+1] + 1e-9
  qbin <- cut(v, breaks = brks, labels=FALSE)
  mean(r[qbin == q], na.rm=TRUE) - mean(r[qbin == 1], na.rm=TRUE)
}

# next-month return lookup
mret_lookup <- copy(mret)[, .(Date, Ticker, Ret_m)]
setkey(mret_lookup, Date, Ticker)

# Factors of interest. After align_factor_direction, Z_Score_Aligned = "higher = expected better return"
# So quintile spread Q5-Q1 should be POSITIVE for well-aligned factors.
factor_codes_needed <- c(
  "S01_Size",
  "V01_BM", "V03_EP",
  "M01_Mom_12_1",
  "Q07_Earnings_Stability",
  "MK01_CAPM_Beta",   # BAB proxy (low - high beta)
  "L05_Dollar_Volume",
  "R05_Tail_Risk"
)

factor_panels <- vector("list", n_sig)
for (i in seq_len(n_sig)) {
  sd <- sig_dates[i]
  panel <- tryCatch(load_month_factors(sd), error = function(e) NULL)
  if (!is.null(panel) && nrow(panel) > 0) {
    # Filter to factors we care about
    panel <- panel[Factor_Name %in% factor_codes_needed]
    # Long → Wide
    panel_w <- dcast(panel, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    factor_panels[[i]] <- panel_w
  }
  if (i %% 50 == 0) cat("  loaded", i, "/", n_sig, "\n")
}

factor_ts <- data.table(Date = sig_dates)
factor_names <- c("RM_KR", "F_SIZE", "F_VAL", "F_MOM", "F_QMJ", "F_BAB", "F_LIQ", "F_TAIL")
for (fn in factor_names) factor_ts[, (fn) := NA_real_]

for (i in seq_len(n_sig - 1)) {
  sd <- sig_dates[i]; sd_next <- sig_dates[i+1]
  panel <- factor_panels[[i]]
  if (is.null(panel)) next
  fwd_ret <- mret_lookup[Date == sd_next, .(Ticker, R = Ret_m)]
  if (nrow(fwd_ret) == 0) next
  m <- merge(panel, fwd_ret, by = "Ticker")
  if (nrow(m) < 30) next

  factor_ts[i, RM_KR := mean(m$R, na.rm = TRUE)]
  if ("S01_Size" %in% names(m)) factor_ts[i, F_SIZE := cross_sec_qspread(m$S01_Size, m$R)]
  if ("V01_BM" %in% names(m)) factor_ts[i, F_VAL := cross_sec_qspread(m$V01_BM, m$R)]
  if ("M01_Mom_12_1" %in% names(m)) factor_ts[i, F_MOM := cross_sec_qspread(m$M01_Mom_12_1, m$R)]
  if ("Q07_Earnings_Stability" %in% names(m)) factor_ts[i, F_QMJ := cross_sec_qspread(m$Q07_Earnings_Stability, m$R)]
  if ("MK01_CAPM_Beta" %in% names(m)) factor_ts[i, F_BAB := cross_sec_qspread(m$MK01_CAPM_Beta, m$R)]
  if ("L05_Dollar_Volume" %in% names(m)) factor_ts[i, F_LIQ := cross_sec_qspread(m$L05_Dollar_Volume, m$R)]
  if ("R05_Tail_Risk" %in% names(m)) factor_ts[i, F_TAIL := cross_sec_qspread(m$R05_Tail_Risk, m$R)]
}

cat("[Step1] Non-NA counts per factor:\n")
print(sapply(factor_ts[, -1], function(x) sum(!is.na(x))))

cat("\n[Step1] Factor TS summary:\n")
print(round(sapply(factor_ts[, -1], function(x) c(
  mean = mean(x, na.rm=TRUE),
  sd = sd(x, na.rm=TRUE),
  ann_vol = sd(x, na.rm=TRUE) * sqrt(12),
  ann_ret = mean(x, na.rm=TRUE) * 12,
  SR = (mean(x, na.rm=TRUE) * 12) / (sd(x, na.rm=TRUE) * sqrt(12))
)), 4))

write_parquet(factor_ts, file.path(OUT_DIR, "_risk_factor_ts.parquet"))
cat("[Step1] DONE.\n")
