# build_panel.R — DISCOVERY PROBE: long-side harvest battery (screening-tier, NOT a WT)
# Question: does a long-side-harvestable alpha exist in KR large-cap deployment universe
#           (K200 U KQ150, top-N EW long-only, 15bps, monthly)?
#
# Builds PIT-safe monthly panel + candidate signals:
#   A1. target-price implied upside  = TP_{asof<=t} / Close_t - 1        (long-side: analyst expected upside)
#   A2. dividend growth / initiation = DPS_1y growth vs 12m-prior + init flag  (long-side positive)
#   B.  factor matrix (load_month_factors Z) for long-side-weighted composite
#
# PIT DESIGN (C1/C2/C4/C6/C10/C14/C15):
#   - signal date t = month-end. Close_t = month-end close (known at t). C2-safe: no same-day return use.
#   - consensus (target_price / dps_1y) are DAILY forecasts -> take LAST value on-or-before t (as-of, no peek). C14.
#   - Ret_1m = shift(mret, -1) forward realized (t -> t+1). C2-safe.
#   - universe = K200|KQ150 membership as-of t; exclude AdminStock/TradingHalt/UnfaithfulDisc as-of t. C6.
#   - adv20 = 20d trailing ADV ending t (Close*Vol). C10 liquidity.
#   - factors via load_month_factors (Z_Score_Aligned, C13/C15).
#   - NO full-sample stats; all cross-sectional per month.
#
# Outputs -> panel/:
#   returns_monthly.parquet     Date, Ticker, Ret_1m
#   benchmark_monthly.parquet   Date, BM_Ret          (forward 1M)
#   universe_flags.parquet      Date, Ticker, in_univ, adv20, Close, Size
#   signals_consensus.parquet   Date, Ticker, tp_upside, dps_growth, dps_init, dps_yield
#   features_monthly.parquet    Date, Ticker, <factor Z cols>

suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); arrow::set_cpu_count(1)

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT)
PROJECT_ROOT <- ROOT
CACHE_DIR    <- file.path(ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

OUT <- file.path(ROOT, "stage_artifacts/probe_longside_harvest_20260705/panel")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ---- 1. RAWDATA daily -> monthly month-end panel ----
cat("[panel] loading RAWDATA...\n")
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
rd <- rd[, .(Date, Ticker, K200, KQ150, Close, Vol, Ret, BM_Ret,
             Size, AdminStock, TradingHalt, UnfaithfulDisc)]
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)
rd[, ym := as.Date(cut(Date, "month"))]

# 20d trailing ADV ending each day
rd[, dvalue := Close * Vol]
rd[, adv20 := frollmean(dvalue, 20, align = "right"), by = Ticker]

# month-end row per ticker-month (last obs), vectorized
rd[, .grp := .GRP, by = .(Ticker, ym)]
is_last <- rd[, .I[.N], by = .grp]$V1
me <- rd[is_last]
rd[, .grp := NULL]

# monthly return from month-end close_{t-1} to close_t
setorder(me, Ticker, ym)
me[, close_prev := shift(Close, 1), by = Ticker]
me[, mret := Close / close_prev - 1]
# forward 1M realized aligned to signal month t
me[, Ret_1m := shift(mret, -1), by = Ticker]

# universe flag + exclusions as-of month-end t (C6: no survivorship, membership as-of t)
me[, in_univ := (K200 == 1 | KQ150 == 1) &
                (is.na(AdminStock) | AdminStock == 0) &
                (is.na(TradingHalt) | TradingHalt == 0) &
                (is.na(UnfaithfulDisc) | UnfaithfulDisc == 0)]

# ---- 2. benchmark monthly forward return (compound daily BM_Ret, then forward-shift) ----
bm <- unique(rd[, .(Date, ym, BM_Ret)][!is.na(BM_Ret)], by = "Date")
bm_m <- bm[, .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]   # panel construction only
setorder(bm_m, ym)
bm_m[, BM_Ret_fwd := shift(bm_mret, -1)]

returns_monthly   <- me[!is.na(Ret_1m) & in_univ == TRUE, .(Date = ym, Ticker, Ret_1m)]
universe_flags    <- me[in_univ == TRUE, .(Date = ym, Ticker, in_univ, adv20, Close, Size)]
benchmark_monthly <- bm_m[!is.na(BM_Ret_fwd), .(Date = ym, BM_Ret = BM_Ret_fwd)]

write_parquet(returns_monthly,   file.path(OUT, "returns_monthly.parquet"))
write_parquet(universe_flags,    file.path(OUT, "universe_flags.parquet"))
write_parquet(benchmark_monthly, file.path(OUT, "benchmark_monthly.parquet"))
cat(sprintf("[panel] returns: %d rows / %d months (%s..%s) | univ names/mo median=%d\n",
    nrow(returns_monthly), uniqueN(returns_monthly$Date),
    as.character(min(returns_monthly$Date)), as.character(max(returns_monthly$Date)),
    as.integer(median(universe_flags[, .N, by=Date]$N))))

# month-end grid (signal dates), 2005+ mandate
months <- sort(unique(returns_monthly$Date))
months <- months[months >= as.Date("2005-01-01")]

# helper: as-of last consensus value on-or-before each month-end signal date, per ticker
# consensus dt: (Date, Ticker, val). me_close: (ym, Ticker, Close) month-end.
asof_monthly <- function(cons_path, valname) {
  cons <- as.data.table(read_parquet(cons_path))
  setnames(cons, names(cons)[3], "val")
  cons <- cons[!is.na(val)]
  cons[, Date := as.Date(Date)]
  setkey(cons, Ticker, Date)
  # build (Ticker, ym-end signal date) grid = actual month-end trading date for join precision
  # use me month-end DATE (not ym-first) so as-of respects true trading-day t
  grid <- me[in_univ == TRUE & ym %in% months, .(Ticker, ym, tdate = Date)]
  setkey(grid, Ticker, tdate)
  # rolling join: for each grid (Ticker,tdate) find last cons Date <= tdate
  j <- cons[grid, on = .(Ticker, Date = tdate), roll = TRUE, .(Ticker, ym = i.ym, val)]
  setnames(j, "val", valname)
  j
}

# ---- 3. consensus long-side signals ----
cat("[panel] building consensus signals (as-of PIT)...\n")
me_close <- me[in_univ == TRUE & ym %in% months, .(Ticker, ym, Close, Size)]

# A1: target-price implied upside = TP_asof / Close_t - 1
tp <- asof_monthly(".cache/consensus/target_price.parquet", "tp")
tp <- merge(tp, me_close[, .(Ticker, ym, Close)], by = c("Ticker","ym"))
tp[, tp_upside := tp / Close - 1]
tp <- tp[is.finite(tp_upside) & tp > 0]   # need a valid positive TP

# A2: dividend growth / initiation from dps_1y (forward 1y DPS estimate, as-of)
dps <- asof_monthly(".cache/consensus/dps_1y.parquet", "dps")
setorder(dps, Ticker, ym)
# 12-month-prior DPS estimate (same ticker, 12 months back in the monthly grid)
dps[, dps_lag12 := shift(dps, 12), by = Ticker]
dps[, dps_growth := fifelse(!is.na(dps_lag12) & dps_lag12 > 0, dps / dps_lag12 - 1, NA_real_)]
# initiation: dps now > 0 but was 0/NA 12m ago
dps[, dps_init := as.integer((dps > 0) & (is.na(dps_lag12) | dps_lag12 == 0))]
# dividend yield (level) — for the *tested-dead value* control, NOT a candidate
dps <- merge(dps, me_close[, .(Ticker, ym, Close)], by = c("Ticker","ym"), all.x = TRUE)
dps[, dps_yield := fifelse(Close > 0, dps / Close, NA_real_)]

sig <- merge(tp[, .(Ticker, ym, tp_upside)],
             dps[, .(Ticker, ym, dps_growth, dps_init, dps_yield)],
             by = c("Ticker","ym"), all = TRUE)
signals_consensus <- sig[, .(Date = ym, Ticker, tp_upside, dps_growth, dps_init, dps_yield)]
write_parquet(signals_consensus, file.path(OUT, "signals_consensus.parquet"))
cat(sprintf("[panel] consensus signals: tp_upside n=%d | dps_growth n=%d | dps_init(sum)=%d | months=%d\n",
    sum(!is.na(signals_consensus$tp_upside)), sum(!is.na(signals_consensus$dps_growth)),
    sum(signals_consensus$dps_init, na.rm=TRUE), uniqueN(signals_consensus$Date)))

# ---- 4. factor matrix (for long-side-weighted composite, Battery B) ----
FEATURES <- c(
  "Q08_Composite_Quality","Q07_Earnings_Stability","Q01_GPA","Q02_ROE",
  "M09_Composite_Mom","M08_Residual_Mom","M14_RiskAdj_Mom","M12_LR_Reversal",
  "V12_Composite_Value","V02_EP","V10_FCF_Yield",
  "R11_Systematic_Risk","R12_Idiosyncratic_Risk","L01_Amihud","M11_ST_Reversal"
)
cat(sprintf("[panel] building factor features over %d months...\n", length(months)))
feat_list <- vector("list", length(months))
for (i in seq_along(months)) {
  sd <- months[i]
  fm <- tryCatch(load_month_factors(sd, coverage_min = 0.05, factor_names = FEATURES),
                 error = function(e) NULL)
  if (is.null(fm) || nrow(fm) == 0) next
  w <- dcast(fm, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  w[, Date := sd]
  feat_list[[i]] <- w
  if (i %% 36 == 0) cat("  ", as.character(sd), "\n")
}
features_monthly <- rbindlist(feat_list, fill = TRUE)
setcolorder(features_monthly, c("Date","Ticker"))
write_parquet(features_monthly, file.path(OUT, "features_monthly.parquet"))
cat(sprintf("[panel] features: %d rows / %d months / %d cols: %s\n",
    nrow(features_monthly), uniqueN(features_monthly$Date), ncol(features_monthly)-2L,
    paste(setdiff(names(features_monthly), c("Date","Ticker")), collapse=",")))
cat("[panel] DONE\n")
