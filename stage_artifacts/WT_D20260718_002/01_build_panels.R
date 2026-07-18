# WT-D20260718_002 — Data prep for insider-selling EXCLUSION filter
# Builds monthly panels from PINNED RAWDATA (vintage wt002_20260718_214215).
#   base_panel.parquet : Date(month-end t=formation), Ticker, mom_score, Ret_1m(month t+1),
#                        Size, adv, in_univ
#   bench_panel.parquet: Date, BM_Ret(month t+1 benchmark return)
# PIT: momentum uses months <= t-1 (skip month t). Ret_1m/BM_Ret = forward month t+1.
#      adv/Size/univ = end of month t (formation, t-1 lag for holding t+1). C1/C10 clean.
suppressWarnings(suppressMessages({library(arrow); library(data.table)}))
setDTthreads(1)
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT <- file.path(R, "stage_artifacts/WT_D20260718_002")
RAW <- file.path(R, ".cache/pins/wt002_20260718_214215/RAWDATA.parquet")  # PINNED

cat("[1] loading pinned RAWDATA (needed cols, Date>=2004)...\n")
ds <- arrow::open_dataset(RAW)
d <- as.data.table(ds |>
  dplyr::filter(Date >= as.Date("2004-01-01")) |>
  dplyr::select(Date, Ticker, Ret, Close, Vol, Size, K200, KQ150) |>
  dplyr::collect())
cat("   rows:", nrow(d), " tickers:", uniqueN(d$Ticker), "\n")

# keep only tickers ever in K200|KQ150 (universe candidates) to bound memory
d[, inuniv_day := (fifelse(is.na(K200),0,K200) > 0) | (fifelse(is.na(KQ150),0,KQ150) > 0)]
univ_tickers <- unique(d[inuniv_day == TRUE, Ticker])
cat("   ever-in-universe tickers:", length(univ_tickers), "\n")
d <- d[Ticker %in% univ_tickers]

d[, ym := format(Date, "%Y-%m")]
d[, trade_val := as.numeric(Vol) * as.numeric(Close)]
d[, lr := log1p(pmax(Ret, -0.99))]

# monthly aggregation per ticker
setorder(d, Ticker, Date)
mon <- d[, .(
  mdate = max(Date),                       # month-end trading date
  mret  = expm1(sum(lr, na.rm = TRUE)),    # asset monthly return (input data-prep, not strategy synth)
  ndays = .N,
  Size  = last(Size),
  adv   = mean(trade_val, na.rm = TRUE),   # avg daily trading value over month (t-1 PIT for t+1 hold)
  inuniv= as.integer(last(inuniv_day))
), by = .(Ticker, ym)]
setorder(mon, Ticker, ym)

# momentum 12-1 : cum return over months {t-11..t-1} (skip most recent month t)
mon[, lr_m := log1p(pmax(mret, -0.99))]
# rolling sum of lr over a window; build via shift within ticker
mon[, mom_score := {
  n <- .N
  out <- rep(NA_real_, n)
  # cumulative log-return helper
  cl <- cumsum(c(0, lr_m))  # length n+1; cl[i+1]-cl[j] = sum lr_m[j+1..i]
  for (i in seq_len(n)) {
    # window months i-11 .. i-1  (skip current month i)
    hi <- i - 1L; lo <- i - 11L
    if (lo >= 1L && hi >= lo) out[i] <- cl[hi + 1L] - cl[lo]   # sum lr_m[lo..hi]
  }
  out
}, by = Ticker]

# forward return: Ret_1m(t) = mret(month t+1)
mon[, Ret_1m := shift(mret, -1L, type = "shift"), by = Ticker]
# forward month must be consecutive (guard gaps): require next ym is +1 month
mon[, ym_idx := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))]
mon[, next_idx := shift(ym_idx, -1L), by = Ticker]
mon[is.na(next_idx) | next_idx != ym_idx + 1L, Ret_1m := NA_real_]

base <- mon[inuniv == 1L & !is.na(mom_score) & !is.na(Ret_1m),
            .(Date = mdate, ym, Ticker, mom_score, Ret_1m, Size, adv, in_univ = inuniv)]
cat("[2] base_panel rows:", nrow(base), " months:", uniqueN(base$ym),
    " range:", min(base$ym), "..", max(base$ym), "\n")
arrow::write_parquet(base, file.path(OUT, "base_panel.parquet"))

# benchmark: unique (Date, BM_Ret) daily -> monthly compound -> forward align
cat("[3] benchmark panel...\n")
bmd <- unique(as.data.table(arrow::open_dataset(RAW) |>
  dplyr::filter(Date >= as.Date("2004-01-01")) |>
  dplyr::select(Date, BM_Ret) |> dplyr::collect()))
bmd <- bmd[!is.na(BM_Ret)]
bmd[, ym := format(Date, "%Y-%m")]
bmd[, lr := log1p(pmax(BM_Ret, -0.99))]
setorder(bmd, Date)
bmon <- bmd[, .(mdate = max(Date), bm_mret = expm1(sum(lr, na.rm=TRUE))), by = ym]
setorder(bmon, ym)
bmon[, ym_idx := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))]
bmon[, BM_Ret_fwd := shift(bm_mret, -1L)]
bmon[, next_idx := shift(ym_idx, -1L)]
bmon[is.na(next_idx) | next_idx != ym_idx + 1L, BM_Ret_fwd := NA_real_]
bench <- bmon[!is.na(BM_Ret_fwd), .(Date = mdate, ym, BM_Ret = BM_Ret_fwd)]
cat("   bench months:", nrow(bench), " range:", min(bench$ym),"..",max(bench$ym), "\n")
arrow::write_parquet(bench, file.path(OUT, "bench_panel.parquet"))

# map ym -> month-end Date (for insider panel alignment)
ym_date <- unique(base[, .(ym, Date)])
arrow::write_parquet(ym_date, file.path(OUT, "ym_date_map.parquet"))
cat("[DONE] panels written.\n")
