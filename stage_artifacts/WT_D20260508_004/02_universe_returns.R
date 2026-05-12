#==============================================================================
# WT-D20260508_004 — Step 2: Universe + Monthly Returns Build (PIT-safe)
#
# Universe = KOSPI200 ∪ KOSDAQ150 (KR_top342) per request.json
# Liquidity floor: 20d avg traded value >= 5e7 KRW (request specifies min 5e7,
#                  Hard mandate KR Production Constraint = 2e8 KRW).
# We use 2e8 KRW (more conservative, project-wide LIQ_THRESHOLD).
#
# PIT contract:
#   - Universe membership at month t = K200=1 OR KQ150=1 at t-1 close
#   - Liquidity = 20d avg(Close*Vol) up to t-1
#   - Monthly forward return = simple total return month t+1 (Ret accumulated)
#
# Output:
#   - panel_monthly.parquet : (Ticker, ym, Date_eom, Universe, FwdRet_1M, FwdRet_3M,
#                              FwdRet_6M, FwdRet_12M, AdjClose, ADV20, MarketCap)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(zoo)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_004")

cat("[02] loading rawdata.parquet …\n")
rd <- as.data.table(read_parquet(file.path(PROJ, ".cache", "rawdata.parquet")))
rd[, Date := as.Date(Date)]

# Filter post-2003 (KOSDAQ150 inception 2010, but build ICIR window from 2008)
rd <- rd[Date >= "2003-01-01"]
cat("[02] after 2003+:", nrow(rd), "rows,", uniqueN(rd$Ticker), "tickers\n")

# 20d ADV (traded value, KRW)
setkey(rd, Ticker, Date)
rd[, TV_d := Close * Vol]
rd[, ADV20 := frollmean(TV_d, 20L, align="right"), by = Ticker]

# Universe flag at each date: K200=1 or KQ150=1
rd[, in_univ := ifelse(!is.na(K200) & K200 == 1, 1L,
                ifelse(!is.na(KQ150) & KQ150 == 1, 1L, 0L))]

# Month-end snapshot
rd[, ym := format(Date, "%Y-%m")]
rd[, eom_flag := Date == max(Date), by = .(Ticker, ym)]

month_dt <- rd[eom_flag == TRUE,
               .(Ticker, ym, Date_eom = Date,
                 in_univ_eom = in_univ,
                 Close_eom = Close,
                 Size_eom  = Size,
                 ADV20_eom = ADV20,
                 Sector)]

# PIT universe / liquidity at t = membership snapshot at t-1 month end (apply lag)
setorder(month_dt, Ticker, ym)
month_dt[, in_univ_lag1 := shift(in_univ_eom, 1L, type="lag"), by = Ticker]
month_dt[, ADV20_lag1   := shift(ADV20_eom, 1L, type="lag"), by = Ticker]

# Forward returns: from eom of month t close, hold to eom of month t+h close
# Use Close_eom adjusted via Ret? RAWDATA Ret is daily simple. Compound monthly.
# Easier: take Close_eom growth = Close_eom_{t+h} / Close_eom_t - 1
# This implicitly uses adjusted close (RAWDATA Close is adjusted per krx pipeline).
month_dt[, Close_fwd_1m  := shift(Close_eom, 1L, type="lead"), by = Ticker]
month_dt[, Close_fwd_3m  := shift(Close_eom, 3L, type="lead"), by = Ticker]
month_dt[, Close_fwd_6m  := shift(Close_eom, 6L, type="lead"), by = Ticker]
month_dt[, Close_fwd_12m := shift(Close_eom, 12L, type="lead"), by = Ticker]

month_dt[, FwdRet_1M  := Close_fwd_1m  / Close_eom - 1]
month_dt[, FwdRet_3M  := Close_fwd_3m  / Close_eom - 1]
month_dt[, FwdRet_6M  := Close_fwd_6m  / Close_eom - 1]
month_dt[, FwdRet_12M := Close_fwd_12m / Close_eom - 1]

# Past 1M return for AR(1) check etc
month_dt[, Close_lag1 := shift(Close_eom, 1L, type="lag"), by = Ticker]
month_dt[, Ret_1M := Close_eom / Close_lag1 - 1]

# PIT-safe universe: in_univ_lag1 == 1 AND ADV20_lag1 >= 2e8 KRW
LIQ_FLOOR <- 2e8
month_dt[, eligible := !is.na(in_univ_lag1) & in_univ_lag1 == 1 &
                       !is.na(ADV20_lag1) & ADV20_lag1 >= LIQ_FLOOR]

# Coverage check
cat("[02] eligible per month (post-2010):\n")
month_dt[ym >= "2010-01" & eligible == TRUE, .N, by = ym][order(-ym)] |> head(5) |> print()
month_dt[ym >= "2010-01" & eligible == TRUE, .N, by = ym][, summary(N)] |> print()

# Save
write_parquet(month_dt, file.path(OUT, "panel_monthly.parquet"))
cat("[02] saved panel_monthly.parquet:", nrow(month_dt), "rows\n")

# Tickers active 2010+
n_tickers_active <- uniqueN(month_dt[ym >= "2010-01" & eligible == TRUE, Ticker])
cat("[02] unique eligible tickers 2010+:", n_tickers_active, "\n")
