# =============================================================================
# FQ-057 run_01: vintage pin (measurement-graduation section 7) + monthly panel build
# - Pin RAWDATA_CACHE + BM_CACHE BEFORE any measurement (daily_refresh may be running)
# - Build monthly return panel + month-end size/membership snapshot for K200|KQ150
#   ever-members, 2004-12 .. latest COMPLETE month.
# - Monthly compounding via PerformanceAnalytics apply.monthly + Return.cumulative
#   (contract-standard functions; no hand-rolled prod(1+r) synthesis).
# Output: stage_artifacts/method_frontier/fq057_monthly_returns.parquet
#         stage_artifacts/method_frontier/fq057_monthly_snapshot.parquet
#         stage_artifacts/method_frontier/fq057_pin_tag.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)
  library(jsonlite)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/data/pin_cache.R"))

OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# ---- 1) Vintage pin (HARD, before any read for measurement) -----------------
PIN_TAG_FILE <- file.path(OUT_DIR, "fq057_pin_tag.json")
if (file.exists(PIN_TAG_FILE)) {
  pin_tag <- fromJSON(PIN_TAG_FILE)$pin_tag
  cat("[pin] existing tag reused:", pin_tag, "\n")
} else {
  pin_tag <- format(Sys.time(), "fq057_%Y%m%d_%H%M%S")
  pin_cache(c(RAWDATA_CACHE, BM_CACHE), pin_tag)
  write_json(list(pin_tag = pin_tag,
                  pinned_files = c("RAWDATA.parquet", "benchmark.parquet"),
                  pinned_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
             PIN_TAG_FILE, auto_unbox = TRUE, pretty = TRUE)
  cat("[pin] new tag:", pin_tag, "\n")
}
RAW_PINNED <- read_pinned(RAWDATA_CACHE, pin_tag)

# ---- 2) Load daily data (pinned copy, col_select only) ----------------------
cat("[load] reading pinned RAWDATA (col_select 7 cols)...\n")
rd <- as.data.table(read_parquet(RAW_PINNED,
        col_select = c("Date", "Ticker", "Ret", "Size", "K200", "KQ150", "Close")))
rd[, Date := as.Date(Date)]
rd <- rd[Date >= as.Date("2004-11-01")]
cat("[load] rows after 2004-11 filter:", nrow(rd), "\n")

# Ever-member set (K200 or KQ150 at any point in sample)
ever <- rd[(K200 > 0 | KQ150 > 0) & !is.na(K200 + KQ150), unique(Ticker)]
cat("[universe] ever-member tickers:", length(ever), "\n")
rd <- rd[Ticker %in% ever]

# Latest COMPLETE month: drop the in-progress calendar month of max(Date)
max_d <- max(rd$Date)
last_complete_ym <- as.integer(format(max_d, "%Y")) * 100L + as.integer(format(max_d, "%m")) - 1L
if (last_complete_ym %% 100L == 0L) last_complete_ym <- last_complete_ym - 100L + 12L
rd[, ym := as.integer(format(Date, "%Y")) * 100L + as.integer(format(Date, "%m"))]
rd <- rd[ym <= last_complete_ym]
cat("[panel] last complete month:", last_complete_ym, "\n")

# ---- 3) Monthly returns via apply.monthly + Return.cumulative ---------------
# wide daily return matrix (xts) -> per-column monthly cumulative return
cat("[monthly] building wide xts...\n")
wide <- dcast(rd[, .(Date, Ticker, Ret)], Date ~ Ticker, value.var = "Ret")
dates <- wide$Date
mat <- as.matrix(wide[, -1, drop = FALSE])
# NA daily returns within a listed period are gaps; treat NA as 0 ONLY where the
# ticker has a Close on that date is unknown here -> keep NA and let
# Return.cumulative propagate NA; months with any NA day become NA (strict).
# That is too strict for sporadic holes; use na-tolerant rule: a month return is
# valid iff >= 15 non-NA daily obs in that month; compute on NA-zeroed copy.
x <- xts(mat, order.by = dates)
obs_cnt <- apply.monthly(xts(!is.na(mat) * 1, order.by = dates), colSums)
mat0 <- mat; mat0[is.na(mat0)] <- 0
x0 <- xts(mat0, order.by = dates)
mret <- apply.monthly(x0, Return.cumulative)   # PerformanceAnalytics standard
stopifnot(nrow(mret) == nrow(obs_cnt))
mret_m <- as.matrix(mret)
mret_m[as.matrix(obs_cnt) < 15] <- NA_real_
mym <- as.integer(format(index(mret), "%Y")) * 100L + as.integer(format(index(mret), "%m"))

mr_dt <- as.data.table(mret_m)
mr_dt[, ym := mym]
mr_long <- melt(mr_dt, id.vars = "ym", variable.name = "Ticker",
                value.name = "ret_m", variable.factor = FALSE)
mr_long <- mr_long[!is.na(ret_m)]
cat("[monthly] return rows:", nrow(mr_long), "\n")

# ---- 4) Month-end snapshot: size + membership (last obs in month) -----------
setorder(rd, Ticker, Date)
snap <- rd[, .SD[.N], by = .(Ticker, ym),
           .SDcols = c("Date", "Size", "K200", "KQ150")]
snap <- snap[, .(Ticker, ym, snap_date = Date, size = as.numeric(Size),
                 k200 = as.integer(K200 > 0), kq150 = as.integer(KQ150 > 0))]
snap[, member := as.integer(k200 == 1L | kq150 == 1L)]
cat("[snapshot] rows:", nrow(snap), " members latest month:",
    snap[ym == last_complete_ym & member == 1L, .N], "\n")

# ---- 5) Persist (write to stage_artifacts, different path from read) --------
write_parquet(mr_long, file.path(OUT_DIR, "fq057_monthly_returns.parquet"))
write_parquet(snap,   file.path(OUT_DIR, "fq057_monthly_snapshot.parquet"))
meta <- list(pin_tag = pin_tag,
             built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
             last_complete_ym = last_complete_ym,
             n_ever_members = length(ever),
             n_return_rows = nrow(mr_long),
             monthly_rule = "apply.monthly+Return.cumulative on NA-zeroed daily; month valid iff >=15 non-NA daily obs",
             pit_notes = "membership/size at month-end (last trading obs of month); no forward info")
write_json(meta, file.path(OUT_DIR, "fq057_panel_meta.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("[done] run_01 complete\n")
