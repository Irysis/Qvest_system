# build_panel.R — WT-D20260710_002 Alpha Research (EW-relative survivor screen)
# Builds PIT-safe monthly panel for dual-basis re-measurement of cap-w-rejected standard factors.
#
# Outputs (stage_artifacts/WT-D20260710_002/panel/):
#   returns_monthly.parquet   Date, Ticker, Ret_1m   (FORWARD 1M realized, aligned to signal month t)
#   benchmark_monthly.parquet Date, BM_Ret           (FORWARD 1M cap-w KOSPI200 benchmark, aligned to t)
#   universe_flags.parquet    Date, Ticker, in_univ, adv20 (K200 U KQ150 mask + 20d ADV at t)
#   size_monthly.parquet      Date, Ticker, Size      (month-end market cap for cap-tier diagnostic)
#   features_monthly.parquet  Date, Ticker, <8 factor Z cols>  (factor DB Z, PIT-safe, C15)
#
# PIT DESIGN (C1/C2/C4/C10/C14/C15): mirrors WT-D20260705_009/build_panel.R (validated).

suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)   # single-thread mandate (segfault avoidance). Do NOT set io_thread_count (parquet HANG bug).

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT)
PROJECT_ROOT <- ROOT
CACHE_DIR    <- file.path(ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

OUT <- file.path(ROOT, "stage_artifacts/WT-D20260710_002/panel")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ---- 1. RAWDATA (daily) -> monthly universe + forward returns + size ----
cat("[panel] loading RAWDATA...\n")
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
rd <- rd[, .(Date, Ticker, K200, KQ150, Close, Vol, Size, Ret, BM_Ret)]
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)
rd[, ym := as.Date(cut(Date, "month"))]
rd[, dvalue := Close * Vol]
rd[, adv20 := frollmean(dvalue, 20, align = "right"), by = Ticker]

# month-end record per ticker-month (last trading day)
rd[, .grp := .GRP, by = .(Ticker, ym)]
is_last <- rd[, .I[.N], by = .grp]$V1
me <- rd[is_last]
me[, adv20_me := adv20]
rd[, .grp := NULL]

# monthly simple return from close_{t-1} -> close_t
setorder(me, Ticker, ym)
me[, close_prev := shift(Close, 1), by = Ticker]
me[, mret := Close / close_prev - 1]
# FORWARD 1M return aligned to signal month t
me[, Ret_1m := shift(mret, -1), by = Ticker]
me[, in_univ := (K200 == TRUE | KQ150 == TRUE)]

# ---- 2. benchmark monthly forward return (cap-w KOSPI200 = RAWDATA BM_Ret) ----
bm <- rd[, .(Date, ym, BM_Ret)][!is.na(BM_Ret)]
bm <- unique(bm, by = c("Date"))
bm_m <- bm[, .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]   # panel-construction compound only (not a strategy return)
setorder(bm_m, ym)
bm_m[, BM_Ret_fwd := shift(bm_mret, -1)]

# ---- 3. write returns + benchmark + universe + size ----
returns_monthly   <- me[!is.na(Ret_1m) & in_univ == TRUE, .(Date = ym, Ticker, Ret_1m)]
universe_flags    <- me[in_univ == TRUE, .(Date = ym, Ticker, in_univ, adv20 = adv20_me)]
benchmark_monthly <- bm_m[!is.na(BM_Ret_fwd), .(Date = ym, BM_Ret = BM_Ret_fwd)]
size_monthly      <- me[in_univ == TRUE & !is.na(Size), .(Date = ym, Ticker, Size)]

write_parquet(returns_monthly,   file.path(OUT, "returns_monthly.parquet"))
write_parquet(universe_flags,    file.path(OUT, "universe_flags.parquet"))
write_parquet(benchmark_monthly, file.path(OUT, "benchmark_monthly.parquet"))
write_parquet(size_monthly,      file.path(OUT, "size_monthly.parquet"))
cat(sprintf("[panel] returns_monthly: %d rows / %d months (%s..%s)\n",
    nrow(returns_monthly), uniqueN(returns_monthly$Date),
    as.character(min(returns_monthly$Date)), as.character(max(returns_monthly$Date))))

# ---- 4. factor features per month (load_month_factors, PIT-safe C15) ----
# 8 CAP-W-REJECTED standard-factor families (clean sources only — NOT batch_434 residual pool):
#   Value: V02_EP (AX-003 EP_STANDALONE), V12_Composite_Value (KR value decay), V10_FCF_Yield
#   Quality: Q01_GPA (AX-004 quality-profitability), Q08_Composite_Quality
#   Momentum: M08_Residual_Mom, M09_Composite_Mom
#   Low-risk/defense: R12_Idiosyncratic_Risk (AX-005-adjacent)
FEATURES <- c(
  "V02_EP","V12_Composite_Value","V10_FCF_Yield",
  "Q01_GPA","Q08_Composite_Quality",
  "M08_Residual_Mom","M09_Composite_Mom",
  "R12_Idiosyncratic_Risk"
)

months <- sort(unique(returns_monthly$Date))
months <- months[months >= as.Date("2005-01-01")]
cat(sprintf("[panel] building features over %d months (%s..%s)...\n",
    length(months), as.character(min(months)), as.character(max(months))))

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
cat(sprintf("[panel] features_monthly: %d rows / %d months / cols present: %s\n",
    nrow(features_monthly), uniqueN(features_monthly$Date),
    paste(setdiff(names(features_monthly), c("Date","Ticker")), collapse=", ")))
cat("[panel] DONE\n")
