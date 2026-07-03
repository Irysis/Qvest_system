# ============================================================================
# C21_Flow_Confirmed_Revision — alpha build (WT-D20260621_003)
# Interaction (product of x-sectional z) of analyst EPS up-revision CONFIRMED
# by smart-money (Foreign+Inst) 20d net-buy/Size. Two NON-return info sets.
# Real-computation ONLY: canonical_screen_bt(). PIT C1-C15 per spec.
# Single-thread segfault guard.
# ============================================================================
suppressMessages({
  library(arrow); library(data.table); library(dplyr)
})
setDTthreads(1L)
options(warn = 1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source("02_Infrastructure/factor_db/factor_z_standard.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260621_003"

cat("=== STEP 1: load data (single-thread) ===\n")
# rawdata: only needed columns to avoid 2.5GB full load
raw <- open_dataset(".cache/rawdata.parquet") %>%
  select(Date, Ticker, Close, Vol, Size, Ret, K200, KQ150) %>%
  filter(Date >= as.Date("2004-06-01")) %>%   # need 20d lookback before 2005-01
  collect() %>% as.data.table()
setkey(raw, Ticker, Date)
cat("raw rows:", nrow(raw), " date:", as.character(min(raw$Date)), "->", as.character(max(raw$Date)), "\n")

eps <- as.data.table(read_parquet(".cache/consensus/eps_chg_1m.parquet"))
esbr <- as.data.table(read_parquet(".cache/consensus/esbr.parquet"))
sue  <- as.data.table(read_parquet(".cache/consensus/sue.parquet"))
tp   <- as.data.table(read_parquet(".cache/consensus/target_price.parquet"))
inv <- open_dataset(".cache/investor_stock/investor_wide.parquet") %>%
  select(Date, Ticker, Foreign, Institutional, Individual) %>%
  filter(Date >= as.Date("2004-06-01")) %>%
  collect() %>% as.data.table()
setkey(inv, Ticker, Date)
cat("inv rows:", nrow(inv), " eps rows:", nrow(eps), "\n")

cat("=== STEP 2: benchmark (BM_Ret from .cache/benchmark.parquet, real KOSPI200 TR) ===\n")
bench <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bench[, Date := as.Date(Date)]   # POSIXct -> Date
bench <- bench[!is.na(BM_Ret), .(Date, BM_Ret)]
stopifnot(nrow(bench) > 100, all(!is.na(bench$BM_Ret)))
cat("bench daily rows:", nrow(bench), " BM_Ret non-NA OK\n")

cat("=== STEP 3: universe + monthly sig_dates (2005~) ===\n")
# trading days
all_days <- sort(unique(raw$Date))
# month-end sig dates = last trading day of each month, 2005-01 onward
raw[, ym := format(Date, "%Y-%m")]
me <- raw[, .(Date = max(Date)), by = ym][order(Date)]
sig_dates <- me[Date >= as.Date("2005-01-01") & Date <= as.Date("2026-04-30"), Date]
cat("n sig_dates:", length(sig_dates), " (", as.character(min(sig_dates)), "->", as.character(max(sig_dates)), ")\n")

# universe membership + Size + ADV per sig_date (t-1 ADV via 20d mean(Close*Vol))
raw[, dv := Close * Vol]   # daily traded value (KRW)
raw[, adv20 := frollmean(dv, 20L, align = "right"), by = Ticker]   # includes t; we shift for t-1 below

# helper: most-recent value on/before a date for a Ticker
# We build per-sig_date snapshots.

cat("=== STEP 4: Leg-B flow (Foreign+Inst 20d & 60d frollsum, /Size) ===\n")
inv[, roll_F20 := frollsum(Foreign, 20L, na.rm = TRUE, align = "right"), by = Ticker]
inv[, roll_I20 := frollsum(Institutional, 20L, na.rm = TRUE, align = "right"), by = Ticker]
inv[, roll_F60 := frollsum(Foreign, 60L, na.rm = TRUE, align = "right"), by = Ticker]
inv[, roll_I60 := frollsum(Institutional, 60L, na.rm = TRUE, align = "right"), by = Ticker]
inv[, roll_Ind20 := frollsum(Individual, 20L, na.rm = TRUE, align = "right"), by = Ticker]
inv[, smart20 := roll_F20 + roll_I20]   # smart_flow_raw 20d
inv[, smart60 := roll_F60 + roll_I60]   # smart_flow_raw 60d
# INV10 (Smart_Money_Flow) components for orthogonality
inv[, abs_all20 := frollsum(abs(Foreign) + abs(Institutional) + abs(Individual), 20L, na.rm = TRUE, align = "right"), by = Ticker]

# ============================================================================
# Build per-sig_date cross-section snapshot
# ============================================================================
# We must, for each sig_date t and each universe ticker, get the LAST Date<=t value of:
#   raw: Size (t value at sig_date row), adv20 at t-1 (C10), K200/KQ150 membership at t
#   inv: smart20/smart60/abs_all20 at last Date<=t
#   consensus: eps_chg_1m, esbr, sue, target_price at last Date<=t
# Forward return: Ret_1m = compound raw$Ret over (t, t+1M] up to next sig_date.
# ============================================================================

cat("=== STEP 5+6+7: per-sig_date z + interaction scores ===\n")
# Pre-index investor by Ticker for rolling joins
setkey(inv, Ticker, Date)
setkey(eps, Ticker, Date); setkey(esbr, Ticker, Date); setkey(sue, Ticker, Date); setkey(tp, Ticker, Date)

# universe snapshot per sig_date (membership + Size at t; adv at t-1)
# adv at t-1: shift adv20 by 1 within ticker
raw[, adv20_lag1 := shift(adv20, 1L, type = "lag"), by = Ticker]

# function: last value on/before date d from a keyed dt (Ticker,Date,value)
roll_asof <- function(dt, valcol, sig_d, univ_tickers) {
  empty <- data.table(Ticker = character(0), v = numeric(0))
  setnames(empty, "v", valcol)
  sub <- dt[Date <= sig_d & Ticker %in% univ_tickers]
  if (nrow(sub) == 0) return(empty)
  sub <- sub[order(Ticker, Date)]
  out <- sub[, .(v = get(valcol)[.N]), by = Ticker]   # last value <= sig_d
  setnames(out, "v", valcol)
  out
}

# Build a long table of scores across all sig_dates
score_list <- vector("list", length(sig_dates))
ret_list   <- vector("list", length(sig_dates))
liq_list   <- vector("list", length(sig_dates))

# precompute per-month raw snapshot map for membership/Size/adv (rows where Date==sig_d)
for (k in seq_along(sig_dates)) {
 tryCatch({
  t <- sig_dates[k]
  # universe = K200 or KQ150 == 1 at sig_date t, Close not NA
  usnap <- raw[Date == t & !is.na(Close) & ((K200 == 1) | (KQ150 == 1)),
               .(Ticker, Size, adv = adv20_lag1)]
  usnap <- usnap[!is.na(Size) & Size > 0]
  if (nrow(usnap) < 20) next
  uts <- usnap$Ticker

  # Leg-B flow: last value <= t
  fl <- roll_asof(inv, "smart20", t, uts)
  fl60 <- roll_asof(inv, "smart60", t, uts)
  sm_num <- roll_asof(inv, "smart20", t, uts); setnames(sm_num, "smart20", "sm_num")
  sm_den <- roll_asof(inv, "abs_all20", t, uts); setnames(sm_den, "abs_all20", "sm_den")
  # consensus legs
  e1 <- roll_asof(eps, "eps_chg_1m", t, uts)
  e2 <- roll_asof(esbr, "esbr", t, uts)
  su <- roll_asof(sue, "sue", t, uts)
  tpv <- roll_asof(tp, "target_price", t, uts)

  d <- merge(usnap, fl, by = "Ticker", all.x = TRUE)
  d <- merge(d, fl60, by = "Ticker", all.x = TRUE)
  d <- merge(d, e1, by = "Ticker", all.x = TRUE)
  d <- merge(d, e2, by = "Ticker", all.x = TRUE)
  d <- merge(d, su, by = "Ticker", all.x = TRUE)
  d <- merge(d, tpv, by = "Ticker", all.x = TRUE)
  d <- merge(d, sm_num, by = "Ticker", all.x = TRUE)
  d <- merge(d, sm_den, by = "Ticker", all.x = TRUE)
  # Close at t for TP gap
  close_t <- raw[Date == t & Ticker %in% uts, .(Ticker, Close)]
  d <- merge(d, close_t, by = "Ticker", all.x = TRUE)

  d[, Date := t]

  # flow_norm = smart20 / Size  (20d window) ; 60d variant
  d[, flow_norm20 := smart20 / Size]
  d[, flow_norm60 := smart60 / Size]
  # INV10 smart money flow ratio
  d[, INV10 := fifelse(!is.na(sm_den) & sm_den > 0, sm_num / sm_den, NA_real_)]
  # INV08 agreement: sign(F20)*sign(I20)*min(|F20|,|I20|)/Size -- need F20,I20 separately
  # (reconstruct via roll_asof on roll_F20/roll_I20)
  fF <- roll_asof(inv, "roll_F20", t, uts)
  fI <- roll_asof(inv, "roll_I20", t, uts)
  d <- merge(d, fF, by = "Ticker", all.x = TRUE)
  d <- merge(d, fI, by = "Ticker", all.x = TRUE)
  d[, INV08 := fifelse(!is.na(roll_F20) & !is.na(roll_I20),
                       sign(roll_F20) * sign(roll_I20) * pmin(abs(roll_F20), abs(roll_I20)) / Size, NA_real_)]
  # TP gap (C06) = target_price/Close - 1
  d[, tp_gap := fifelse(!is.na(target_price) & !is.na(Close) & Close > 0, target_price / Close - 1, NA_real_)]

  # revision legs
  d[, rev_blend := 0.5 * eps_chg_1m + 0.5 * esbr]   # may be NA if either missing -> handle via z below over available
  # For eps_only / esbr_only we keep separate columns

  # cross-sectional z (per sig_date, winsorize 1/99) — C1 no full-sample
  zw <- function(x) z_safe_winsorize(x)
  d[, z_rev_blend := zw(rev_blend)]
  d[, z_rev_eps   := zw(eps_chg_1m)]
  d[, z_rev_esbr  := zw(esbr)]
  d[, z_flow20    := zw(flow_norm20)]
  d[, z_flow60    := zw(flow_norm60)]
  # orthogonality factor z's
  d[, z_INV08 := zw(INV08)]
  d[, z_INV10 := zw(INV10)]
  d[, z_C02   := zw(eps_chg_1m)]
  d[, z_C04   := zw(esbr)]
  # C19 composite = rowMeans z(SUE,ESBR,EPS_chg1m,TP_gap)
  d[, z_sue := zw(sue)]; d[, z_tpgap := zw(tp_gap)]
  zc <- as.matrix(d[, .(z_sue, z_C04, z_C02, z_tpgap)])
  n_c19 <- rowSums(!is.na(zc))
  c19v <- rowMeans(zc, na.rm = TRUE)
  d[, C19 := fifelse(n_c19 >= 2L, c19v, NA_real_)]

  # ---- INTERACTION scores (anchor = G/20d/blend) ----
  mk_variants <- function(zr, zf, tag) {
    data.table(
      Ticker = d$Ticker, Date = t,
      P  = zr * zf,
      G  = zr * pmax(zf, 0),
      S  = fifelse(zr < 0 & zf < 0, 0, zr * zf),
      M_revOnly = zr, M_flowOnly = zf, M_linadd = 0.5 * zr + 0.5 * zf,
      leg = tag
    )
  }
  # anchor: blend rev, 20d flow
  sc <- mk_variants(d$z_rev_blend, d$z_flow20, "blend20")
  # robustness legs (computed but stored separately)
  sc_eps   <- mk_variants(d$z_rev_eps,   d$z_flow20, "eps20")
  sc_esbr  <- mk_variants(d$z_rev_esbr,  d$z_flow20, "esbr20")
  sc_b60   <- mk_variants(d$z_rev_blend, d$z_flow60, "blend60")

  score_list[[k]] <- list(
    anchor = sc, eps = sc_eps, esbr = sc_esbr, b60 = sc_b60,
    ortho = d[, .(Ticker, Date, z_INV08, z_INV10, C19, z_C02, z_C04)]
  )
  liq_list[[k]] <- usnap[, .(Date = t, Ticker, adv)]
 }, error = function(e) { cat("ERR at k=", k, " t=", as.character(sig_dates[k]), ": ", conditionMessage(e), "\nCALL: ", deparse(conditionCall(e)), "\n"); stop(e) })
}
cat("scored sig_dates:", sum(!sapply(score_list, is.null)), "\n")

cat("=== STEP 8: forward 1M returns (compound raw$Ret between consecutive sig_dates) ===\n")
# For each sig_date t_k, Ret_1m = prod(1+Ret) - 1 over (t_k, t_{k+1}]  per Ticker.
# Use Return.cumulative-equivalent via product over the forward window — but
# answer-principles forbids self-synth prod(1+r) for PORTFOLIO returns. For ASSET
# forward 1M return construction we use the standard compounding of single-asset
# daily returns (this is the asset return series, not a portfolio synthesis).
# Per python-policy/backtest-contract, portfolio aggregation is done by
# canonical_screen_bt (sum w*Ret_1m) — the contract path. Asset 1M compounding is
# the legitimate forward realized return.
setkey(raw, Ticker, Date)
ret_rows <- list()
for (k in seq_len(length(sig_dates) - 1L)) {
  t0 <- sig_dates[k]; t1 <- sig_dates[k + 1L]
  win <- raw[Date > t0 & Date <= t1 & !is.na(Ret), .(Ret_1m = prod(1 + Ret) - 1), by = Ticker]
  win[, Date := t0]
  ret_rows[[k]] <- win
}
returns_dt <- rbindlist(ret_rows)
cat("returns_dt rows:", nrow(returns_dt), "\n")

# monthly benchmark return aligned to sig_dates: compound BM daily over forward window
bench_rows <- list()
for (k in seq_len(length(sig_dates) - 1L)) {
  t0 <- sig_dates[k]; t1 <- sig_dates[k + 1L]
  bw <- bench[Date > t0 & Date <= t1, BM_Ret]
  bench_rows[[k]] <- data.table(Date = t0, BM_Ret = prod(1 + bw) - 1)
}
bench_dt <- rbindlist(bench_rows)
cat("bench_dt rows:", nrow(bench_dt), " range:", as.character(range(bench_dt$BM_Ret)), "\n")

# liquidity dt
liq_dt <- rbindlist(liq_list)

saveRDS(list(score_list = score_list, returns_dt = returns_dt, bench_dt = bench_dt,
             liq_dt = liq_dt, sig_dates = sig_dates),
        file.path(OUT, "c21_intermediate.rds"))
cat("[saved intermediate]\n")
cat("BUILD-PART1-DONE\n")
