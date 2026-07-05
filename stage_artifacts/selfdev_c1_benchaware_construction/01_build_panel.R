# 01_build_panel.R — Self-Developing Cycle 1: benchmark-aware construction
# Builds a self-contained, PIT-safe monthly panel from RAWDATA (daily).
#
# Outputs (stage_artifacts/selfdev_c1_benchaware_construction/panel/):
#   panel_monthly.parquet    Date, Ticker, in_univ, mcap_t, adv20_t, mom_12_1, Ret_1m
#   benchmark_monthly.parquet Date, BM_Ret   (forward 1M cap-weighted KOSPI200 total return)
#
# PIT DESIGN (C1/C2/C4/C10/C14):
#   - Signal date t = month-end.
#   - mcap_t   = market cap AT month-end t (Size). Used to pick the mega-cap ANCHOR by LAGGED cap.
#                (we do NOT pick the winners; anchor = largest by cap known at t, held into t->t+1.)
#   - mom_12_1 = 12-1 skip-1 momentum = cumret from t-12 to t-1 (skip most recent month). Known at t.
#   - adv20_t  = 20d trailing avg daily traded value (Close*Vol) ending at t. Liquidity filter (C10).
#   - Ret_1m   = FORWARD 1M realized return over (t -> t+1). No same-day (C2).
#   - BM_Ret   = FORWARD 1M cap-weighted KOSPI200 total return aligned to t (the active denominator).
#   - Universe: K200 OR KQ150 membership as of month-end t.
#   - No full-sample stats; all per-month cross-sectional.

suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/selfdev_c1_benchaware_construction/panel")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
cat("[panel] loading RAWDATA (full, then subset — col_select hangs)...\n")
rd <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet")))
rd <- rd[, .(Date, Ticker, K200, KQ150, Close, Vol, Size, Ret, BM_Ret)]
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)
rd[, ym := as.Date(cut(Date, "month"))]

# daily traded value (KRW notional) & 20d trailing ADV ending each day
rd[, dvalue := Close * Vol]
rd[, adv20 := frollmean(dvalue, 20, align = "right"), by = Ticker]

# month-end record per ticker-month (last trading day of month) — vectorized
rd[, .grp := .GRP, by = .(Ticker, ym)]
is_last <- rd[, .I[.N], by = .grp]$V1
me <- rd[is_last]
rd[, .grp := NULL]
setorder(me, Ticker, ym)

# monthly simple return from month-end close_{t-1} to close_t
me[, close_prev := shift(Close, 1), by = Ticker]
me[, mret := Close / close_prev - 1]

# 12-1 momentum: cumulative return from t-12 to t-1 (skip most recent month), known at t.
# = prod over lags 2..12 of (1+mret) - 1 ; using shifted monthly returns.
# Build via rolling product of (1+mret) over a window ending at t-1 (skip t).
me[, lr := log1p(mret)]
# sum of log returns over months t-12..t-1  = (cumsum trick per ticker)
me[, cs := cumsum(fifelse(is.na(lr), 0, lr)), by = Ticker]
me[, cnt := cumsum(as.integer(!is.na(lr))), by = Ticker]
# value at t-1 minus value at t-12 : shift the cumsum
me[, cs_lag1  := shift(cs, 1),  by = Ticker]   # cumsum through t-1
me[, cs_lag12 := shift(cs, 12), by = Ticker]   # cumsum through t-12
me[, cnt_lag1 := shift(cnt,1),  by = Ticker]
me[, cnt_lag12:= shift(cnt,12), by = Ticker]
me[, mom_12_1 := exp(cs_lag1 - cs_lag12) - 1]
# require full 11-month window present (t-12..t-1 => 11 monthly returns)
me[(cnt_lag1 - cnt_lag12) < 11, mom_12_1 := NA_real_]

# forward 1M return aligned to signal month t
me[, Ret_1m := shift(mret, -1), by = Ticker]

# universe flag at month-end t
me[, in_univ := (K200 == TRUE | KQ150 == TRUE)]

# ---- benchmark monthly forward (cap-weighted KOSPI200 total return) ----
bm <- rd[, .(Date, ym, BM_Ret)][!is.na(BM_Ret)]
bm <- unique(bm, by = "Date")
bm_m <- bm[, .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]
setorder(bm_m, ym)
bm_m[, BM_Ret_fwd := shift(bm_mret, -1)]

panel <- me[in_univ == TRUE, .(Date = ym, Ticker, in_univ,
                               mcap_t = Size, adv20_t = adv20, mom_12_1, Ret_1m)]
benchmark_monthly <- bm_m[!is.na(BM_Ret_fwd), .(Date = ym, BM_Ret = BM_Ret_fwd)]

write_parquet(panel, file.path(OUT, "panel_monthly.parquet"))
write_parquet(benchmark_monthly, file.path(OUT, "benchmark_monthly.parquet"))

cat(sprintf("[panel] panel: %d rows / %d months (%s..%s)\n",
    nrow(panel), uniqueN(panel$Date), as.character(min(panel$Date)), as.character(max(panel$Date))))
cat(sprintf("[panel] benchmark: %d months (%s..%s)\n",
    nrow(benchmark_monthly), as.character(min(benchmark_monthly$Date)), as.character(max(benchmark_monthly$Date))))
# sanity: mega-cap dominance at a recent month
d <- panel[Date == max(panel[Date <= as.Date("2024-06-01")]$Date)]
setorder(d, -mcap_t)
cat(sprintf("[panel] sanity @%s: top2 mcap share of univ = %.3f, top5 = %.3f\n",
    as.character(d$Date[1]), sum(d$mcap_t[1:2])/sum(d$mcap_t, na.rm=TRUE),
    sum(d$mcap_t[1:5])/sum(d$mcap_t, na.rm=TRUE)))
cat("[panel] DONE\n")
