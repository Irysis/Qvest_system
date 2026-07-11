#==============================================================================
# WT-D20260711_002 Phase A — Step 10: pin rawdata + full candidate pool + panel
#   - PIN rawdata.parquet (concurrent April-gap repair session may be rewriting it;
#     read a byte-identical frozen snapshot for the whole WT).
#   - Full K200uKQ150 (ticker, fiscal_year) candidate pool 2010-2023.
#   - Monthly return panel (forward window 2010..2024, no 2026-04 gap exposure).
#   - RAWDATA CACHE WRITE FORBIDDEN — read-only + pinned copy only.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")
dir.create(file.path(OUT, "text_cache"), recursive = TRUE, showWarnings = FALSE)

# --- pin rawdata (byte copy; guards mid-session mutation) ---
source(file.path(ROOT, "02_Infrastructure/data/pin_cache.R"))
PIN_TAG <- "wt002_phaseA_20260711"
RAW <- file.path(ROOT, ".cache/rawdata.parquet")
if (inherits(try(read_pinned(RAW, PIN_TAG), silent = TRUE), "try-error")) {
  pin_cache(RAW, PIN_TAG)
}
RAW_PINNED <- read_pinned(RAW, PIN_TAG)
cat("[10] rawdata pinned:", RAW_PINNED, "\n")

cols <- c("Date","Ticker","K200","KQ150","Size","Ret","BM_Ret","Vol","Close")
raw <- as.data.table(read_parquet(RAW_PINNED, col_select = all_of(cols)))
raw[, Date := as.Date(Date)]
cat("[10] rawdata Date range:", as.character(min(raw$Date)), "..", as.character(max(raw$Date)),
    " rows:", nrow(raw), "\n")

# forward-return window we will use: 2010-01 .. 2024-12 (signal filed 2011..2024)
raw <- raw[Date >= as.Date("2009-06-01") & Date <= as.Date("2025-06-30")]
setorder(raw, Ticker, Date)

# daily price-limit clip (error hygiene only)
raw[, Ret_c := pmin(pmax(Ret, -0.35), 0.35)]
raw[, ym := as.integer(format(Date, "%Y%m"))]

# month-end panel (last trading day per Ticker,ym)
me <- raw[, .SD[.N], by = .(Ticker, ym), .SDcols = c("Date","K200","KQ150","Size","Close","Vol")]
setnames(me, "Date", "me_date")
mret <- raw[, .(mret = prod(1 + Ret_c) - 1, n_days = .N), by = .(Ticker, ym)]
me <- merge(me, mret, by = c("Ticker","ym"))
# 20d avg trading value (ADV) proxy for liquidity filter — trailing 20 trading days per ticker
raw[, tv := Vol * Close]
raw[, adv20 := frollmean(tv, 20, align = "right"), by = Ticker]
adv_me <- raw[, .SD[.N], by = .(Ticker, ym), .SDcols = "adv20"]
me <- merge(me, adv_me, by = c("Ticker","ym"), all.x = TRUE)

# monthly benchmark (KOSPI200 TR)
bench_d <- unique(raw[, .(Date, BM_Ret)])
bench_d[, BM_c := pmin(pmax(BM_Ret, -0.35), 0.35)]
bench_d[, ym := as.integer(format(Date, "%Y%m"))]
bench_m <- bench_d[, .(bench_mret = prod(1 + BM_c) - 1), by = ym]

saveRDS(list(me = me, bench_m = bench_m, pin_tag = PIN_TAG),
        file.path(OUT, "monthly_panel.rds"))
cat("[10] monthly panel saved. tickers:", uniqueN(me$Ticker), " months:", uniqueN(me$ym),
    " ym range:", min(me$ym), "..", max(me$ym), "\n")

# --- full candidate pool: every (Ticker, fiscal_year) in K200uKQ150 at (fy+1)-03 snapshot ---
fiscal_years <- 2010:2023
pool_list <- list()
for (Y in fiscal_years) {
  snap_ym <- (Y + 1L) * 100L + 3L
  snap <- me[ym == snap_ym & (K200 == 1 | KQ150 == 1) & !is.na(Size) & Size > 0]
  if (nrow(snap) == 0) next
  qs <- quantile(snap$Size, c(1/3, 2/3), na.rm = TRUE)
  snap[, cap_tier := fifelse(Size >= qs[2], "LARGE", fifelse(Size >= qs[1], "MID", "SMALL"))]
  snap[, `:=`(fiscal_year = Y, file_year = Y + 1L, snap_ym = snap_ym)]
  pool_list[[as.character(Y)]] <- snap[, .(Ticker, fiscal_year, file_year, snap_ym,
                                           me_date, Size, cap_tier, adv20)]
}
pool <- rbindlist(pool_list)
write_parquet(pool, file.path(OUT, "candidate_pool_full.parquet"))
cat("[10] FULL candidate pool:", nrow(pool), "(ticker,fy) rows. unique tickers:",
    uniqueN(pool$Ticker), "\n")
print(pool[, .N, by = fiscal_year][order(fiscal_year)])
cat("[10] DONE\n")
