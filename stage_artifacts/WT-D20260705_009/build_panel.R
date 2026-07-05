# build_panel.R — WT-D20260705_009 Alpha Research
# Builds PIT-safe monthly panel for uncertainty-conditioned selection A/B.
#
# Outputs (stage_artifacts/WT-D20260705_009/panel/):
#   features_monthly.parquet   Date, Ticker, <factor Z cols...>   (signal at month-end t)
#   returns_monthly.parquet    Date, Ticker, Ret_1m               (FORWARD 1M realized, aligned to signal month t)
#   benchmark_monthly.parquet  Date, BM_Ret                       (FORWARD 1M benchmark, aligned to t)
#   universe_flags.parquet     Date, Ticker, in_univ, adv20       (K200 U KQ150 mask + 20d ADV at t-1)
#
# PIT DESIGN (C1/C2/C4/C10/C14/C15):
#   - Signal date t = month-end. Features = factor DB Z (load_month_factors, PIT-safe connector, C15).
#   - Forward return Ret_1m = realized return from t (month-end) to t+1 (next month-end). No same-day (C2).
#   - Universe flag + liquidity use data AT t (K200/KQ150 membership as of t, ADV over trailing 20d ending t) -> C10.
#   - Benchmark BM_Ret = forward 1M benchmark return aligned to t.
#   - NO full-sample stats; all cross-sectional per-month. NGBoost training (separate) uses expanding window only.

suppressPackageStartupMessages({
  library(data.table); library(arrow)
})

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT)
# pre-define paths so connector doesn't rely on sys.frame(1)$ofile (fails when nested-sourced)
PROJECT_ROOT <- ROOT
CACHE_DIR    <- file.path(ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

OUT <- file.path(ROOT, "stage_artifacts/WT-D20260705_009/panel")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

LIQ_MIN <- 5e7   # request.json universe_definition.liquidity_min_won_20d_avg = 5e7 (WT-scoped)

# ---- 1. RAWDATA (daily) -> monthly universe + forward returns ----
cat("[panel] loading RAWDATA...\n")
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
      col_select = c("Date","Ticker","K200","KQ150","Close","Vol","Ret","BM_Ret")))
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)

# month key (month-first) for grouping
rd[, ym := as.Date(cut(Date, "month"))]

# per (Ticker, month): month-end close, universe membership at month-end, 20d ADV ending month-end
# daily traded value = Close * Vol (KRW notional proxy)
rd[, dvalue := Close * Vol]
# 20d trailing ADV ending each day (rolling mean of dvalue, 20 obs) — vectorized per ticker
rd[, adv20 := frollmean(dvalue, 20, align = "right"), by = Ticker]

# month-end record per ticker-month = last trading day of month (VECTORIZED, no .SD[.N])
# rd already sorted by (Ticker, Date). Mark last row within each (Ticker, ym) group.
rd[, .grp := .GRP, by = .(Ticker, ym)]
is_last <- rd[, .I[.N], by = .grp]$V1        # row indices of last obs per ticker-month
me <- rd[is_last]                             # month-end rows (carries adv20 at month-end)
me[, adv20_me := adv20]
rd[, .grp := NULL]

# monthly simple return from month-end close_{t-1} to close_t (per ticker)
setorder(me, Ticker, ym)
me[, close_prev := shift(Close, 1), by = Ticker]
me[, mret := Close / close_prev - 1]

# FORWARD 1M return aligned to signal month t: ret realized over (t -> t+1) = mret at month t+1
me[, Ret_1m := shift(mret, -1), by = Ticker]   # forward: next month's realized return (C2-safe: shift -1 of realized)

# universe flag at signal month t (K200 or KQ150 membership as of month-end t)
me[, in_univ := (K200 == TRUE | KQ150 == TRUE)]

# ---- 2. benchmark monthly forward return ----
# BM_Ret in RAWDATA is daily benchmark return; compound to monthly, then forward-shift
bm <- rd[, .(Date, ym, BM_Ret)][!is.na(BM_Ret)]
bm <- unique(bm, by = c("Date"))     # BM_Ret same across tickers per date
bm_m <- bm[, .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]   # monthly benchmark realized (compound of daily) -- panel construction only, not a strategy return
setorder(bm_m, ym)
bm_m[, BM_Ret_fwd := shift(bm_mret, -1)]   # forward 1M benchmark aligned to signal month t

# ---- 3. write returns + benchmark + universe ----
returns_monthly <- me[!is.na(Ret_1m) & in_univ == TRUE, .(Date = ym, Ticker, Ret_1m)]
universe_flags  <- me[in_univ == TRUE, .(Date = ym, Ticker, in_univ, adv20 = adv20_me)]
benchmark_monthly <- bm_m[!is.na(BM_Ret_fwd), .(Date = ym, BM_Ret = BM_Ret_fwd)]

write_parquet(returns_monthly,   file.path(OUT, "returns_monthly.parquet"))
write_parquet(universe_flags,    file.path(OUT, "universe_flags.parquet"))
write_parquet(benchmark_monthly, file.path(OUT, "benchmark_monthly.parquet"))
cat(sprintf("[panel] returns_monthly: %d rows / %d months  (%s..%s)\n",
    nrow(returns_monthly), uniqueN(returns_monthly$Date),
    as.character(min(returns_monthly$Date)), as.character(max(returns_monthly$Date))))

# ---- 4. factor features per month (load_month_factors, PIT-safe C15) ----
# Feature set: validated KR families for a KNOWN-GOOD composite base learner.
FEATURES <- c(
  "Q08_Composite_Quality","Q07_Earnings_Stability","Q01_GPA","Q02_ROE",
  "M09_Composite_Mom","M08_Residual_Mom","M14_RiskAdj_Mom","M12_LR_Reversal",
  "V12_Composite_Value","V02_EP","V10_FCF_Yield",
  "R11_Systematic_Risk","R12_Idiosyncratic_Risk","L01_Amihud","M11_ST_Reversal"
)

months <- sort(unique(returns_monthly$Date))
# start at 2005-01 (mandate: 2005~) and require factor DB availability
months <- months[months >= as.Date("2005-01-01")]

cat(sprintf("[panel] building features over %d months (%s..%s)...\n",
    length(months), as.character(min(months)), as.character(max(months))))

feat_list <- vector("list", length(months))
for (i in seq_along(months)) {
  sd <- months[i]
  fm <- tryCatch(load_month_factors(sd, coverage_min = 0.05, factor_names = FEATURES),
                 error = function(e) NULL)
  if (is.null(fm) || nrow(fm) == 0) next
  # wide: Ticker x Factor_Name (Z_Score_Aligned, higher=better)
  w <- dcast(fm, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  w[, Date := sd]
  feat_list[[i]] <- w
  if (i %% 24 == 0) cat("  ", as.character(sd), "\n")
}
features_monthly <- rbindlist(feat_list, fill = TRUE)
# reorder cols
setcolorder(features_monthly, c("Date","Ticker"))
write_parquet(features_monthly, file.path(OUT, "features_monthly.parquet"))
cat(sprintf("[panel] features_monthly: %d rows / %d months / %d feature cols\n",
    nrow(features_monthly), uniqueN(features_monthly$Date),
    ncol(features_monthly) - 2L))
cat("[panel] feature cols present:", paste(setdiff(names(features_monthly), c("Date","Ticker")), collapse=", "), "\n")
cat("[panel] DONE\n")
