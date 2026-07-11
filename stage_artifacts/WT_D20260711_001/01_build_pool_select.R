#==============================================================================
# WT-D20260711_001 — Step 1: candidate pool + seeded stratified selection
# Executes the FROZEN sampling_protocol (preregistration.json, sha256 beba7a3c...).
# NO returns are inspected for selection. Monthly panel is built + saved for the
# POST-scoring merge only (not read during scoring).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_001")

cat("[1] loading rawdata (cols) ...\n")
cols <- c("Date","Ticker","K200","KQ150","Size","Ret","BM_Ret","Vol","Close")
raw <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet"), col_select = all_of(cols)))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2014-06-01") & Date <= as.Date("2025-06-30")]
setorder(raw, Ticker, Date)
cat("   rows:", nrow(raw), "\n")

# --- daily return hygiene: KR price-limit clip (errors only; +-30% since 2015, +-15% before) ---
raw[, Ret_c := pmin(pmax(Ret, -0.35), 0.35)]
raw[, ym := as.integer(format(Date, "%Y%m"))]

# --- month-end panel: last trading day per (Ticker, ym) ---
me <- raw[, .SD[.N], by = .(Ticker, ym),
          .SDcols = c("Date","K200","KQ150","Size","Close","Vol")]
setnames(me, "Date", "me_date")
# monthly compounded return per ticker
mret <- raw[, .(mret = prod(1 + Ret_c) - 1, n_days = .N), by = .(Ticker, ym)]
me <- merge(me, mret, by = c("Ticker","ym"))
# 20d-avg trading value proxy at month end (Vol*Close of last day; simple liquidity presence flag)
me[, tv_proxy := Vol * Close]

# monthly benchmark (KOSPI200 TR) — BM_Ret is market-wide; dedupe by Date
bench_d <- unique(raw[, .(Date, BM_Ret)])
bench_d[, BM_c := pmin(pmax(BM_Ret, -0.35), 0.35)]
bench_d[, ym := as.integer(format(Date, "%Y%m"))]
bench_m <- bench_d[, .(bench_mret = prod(1 + BM_c) - 1), by = ym]

saveRDS(list(me = me, bench_m = bench_m), file.path(OUT, "monthly_panel.rds"))
cat("[1] monthly panel saved. tickers:", uniqueN(me$Ticker), " months:", uniqueN(me$ym), "\n")

#--- eligibility snapshots + strata (fiscal_year Y=2014..2022; snap = (Y+1)-03 ME) ---
fiscal_years <- 2014:2022
pool_list <- list()
for (Y in fiscal_years) {
  snap_ym <- (Y + 1L) * 100L + 3L                     # (Y+1)-03
  snap <- me[ym == snap_ym & (K200 == 1 | KQ150 == 1) & !is.na(Size) & Size > 0]
  if (nrow(snap) == 0) next
  # within-universe Size terciles -> cap_tier
  qs <- quantile(snap$Size, c(1/3, 2/3), na.rm = TRUE)
  snap[, cap_tier := fifelse(Size >= qs[2], "LARGE",
                      fifelse(Size >= qs[1], "MID", "SMALL"))]
  fy_file <- Y + 1L
  ybin <- if (fy_file <= 2017) "FILE_2015_2017" else if (fy_file <= 2020) "FILE_2018_2020" else "FILE_2021_2023"
  snap[, `:=`(fiscal_year = Y, file_year = fy_file, snap_ym = snap_ym,
              year_bin = ybin)]
  pool_list[[as.character(Y)]] <- snap[, .(Ticker, fiscal_year, file_year, snap_ym,
                                           me_date, Size, cap_tier, year_bin, tv_proxy)]
}
pool <- rbindlist(pool_list)
write_parquet(pool, file.path(OUT, "candidate_pool.parquet"))
cat("[1] candidate pool:", nrow(pool), "eligible (ticker,fy). unique tickers:", uniqueN(pool$Ticker), "\n")
cat("    by cell:\n"); print(pool[, .N, by = .(cap_tier, year_bin)][order(cap_tier, year_bin)])

#--- FROZEN seeded selection: 9 cells x 5, one-doc-per-ticker, buffered ---
set.seed(20260711)
cap_order  <- c("LARGE","MID","SMALL")
ybin_order <- c("FILE_2015_2017","FILE_2018_2020","FILE_2021_2023")
CELL_TARGET <- 5L
BUFFER <- 4L      # extra seeded candidates per cell for fetch-failure replacement
used_tickers <- character(0)
sel_list <- list()
for (ct in cap_order) for (yb in ybin_order) {
  cell <- pool[cap_tier == ct & year_bin == yb & !(Ticker %in% used_tickers)]
  if (nrow(cell) == 0) next
  # order deterministically by Ticker,fy then shuffle by seed
  setorder(cell, Ticker, fiscal_year)
  # one doc per ticker inside cell: keep the ticker's earliest eligible fy in this cell
  cell <- cell[, .SD[1], by = Ticker]
  k <- min(nrow(cell), CELL_TARGET + BUFFER)
  idx <- sample(seq_len(nrow(cell)), k)      # seeded draw
  pick <- cell[idx]
  pick[, `:=`(cell = paste(ct, yb, sep="|"), seeded_rank = seq_len(.N))]
  used_tickers <- c(used_tickers, pick$Ticker)
  sel_list[[paste(ct, yb)]] <- pick
}
sel <- rbindlist(sel_list)
setorder(sel, cell, seeded_rank)
sel[, doc_id := sprintf("D%03d", .I)]
write_parquet(sel, file.path(OUT, "selection.parquet"))
cat("\n[1] SELECTION (buffered) rows:", nrow(sel), " target-primary per cell:", CELL_TARGET, "\n")
print(sel[seeded_rank <= CELL_TARGET, .N, by = cell][order(cell)])
cat("    primary target total:", nrow(sel[seeded_rank <= CELL_TARGET]), "\n")
cat("[1] DONE\n")
