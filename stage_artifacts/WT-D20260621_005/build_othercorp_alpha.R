# build_othercorp_alpha.R — WT-D20260621_005
# OtherCorp (기타법인) Strategic Accumulation Momentum
# alpha-only. canonical_screen_bt real-computation. PIT C1-C15.
# R segfault guard: single-thread, open_dataset col_select, no set_io_thread_count(1).

suppressMessages({
  library(arrow); library(data.table); library(dplyr)
})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260621_005")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

source("02_Infrastructure/contracts/canonical_screen_bt.R")

set.seed(20260621)
START_DATE <- as.Date("2005-01-01")

cat("=== STEP 1: load investor OtherCorp + rawdata ===\n")
# OtherCorp daily NetBuy (quantity)
iv <- as.data.table(
  open_dataset(".cache/investor_stock/investor_wide.parquet") %>%
    select(Date, Ticker, OtherCorp) %>% collect()
)
iv[, Date := as.Date(Date)]
iv <- iv[Date >= START_DATE - 90]  # 90d buffer for rolling warmup pre-START

# rawdata: Close, Size, Vol, Ret, membership
rd <- as.data.table(
  open_dataset(".cache/rawdata.parquet") %>%
    select(Date, Ticker, Close, Size, Vol, Ret, K200, KQ150) %>% collect()
)
rd[, Date := as.Date(Date)]
rd <- rd[Date >= START_DATE - 90]

# benchmark (KOSPI200 TR) — rawdata BM_Ret empty
bm <- as.data.table(
  open_dataset(".cache/benchmark.parquet") %>% select(Date, BM_Ret) %>% collect()
)
bm[, Date := as.Date(Date)]
bm <- bm[!is.na(BM_Ret) & Date >= START_DATE - 5]
setorder(bm, Date)

cat("iv rows:", nrow(iv), " rd rows:", nrow(rd), " bm rows:", nrow(bm), "\n")

cat("=== STEP 2: notional conversion OC_notional = OtherCorp * Close ===\n")
# join Close onto iv (daily). Both keyed Date+Ticker.
setkey(iv, Date, Ticker); setkey(rd, Date, Ticker)
dt <- merge(iv, rd[, .(Date, Ticker, Close, Size, Vol, Ret, K200, KQ150)],
            by = c("Date","Ticker"), all.x = TRUE)
# OC_notional: NetBuy quantity * close price (KRW notional). NA close -> NA notional
dt[, OC_notional := OtherCorp * Close]
# treat exact-zero OtherCorp as "no activity" (non-NA but zero) — kept for COV/PERS logic
setorder(dt, Ticker, Date)

cat("=== STEP 3: rolling ACC/COV/PERS by Ticker, align=right, ENDED AT d-1 (C2 strict) ===\n")
Lacc <- 40L
# rolling sums computed at day d (inclusive). To respect C2 (no same-day),
# we shift the rolling series by 1 within ticker -> value as of d-1.
roll_one <- function(x, n) frollsum(x, n, align = "right", na.rm = TRUE)
dt[, OC_notional_filled := fifelse(is.na(OC_notional), 0, OC_notional)]
dt[, obs_flag := as.integer(!is.na(OC_notional) & OC_notional != 0)]   # observed (non-NA non-zero)
dt[, pos_flag := as.integer(!is.na(OC_notional) & OC_notional > 0)]
dt[, nonNA_flag := as.integer(!is.na(OC_notional))]

dt[, ACC_raw_d  := roll_one(OC_notional_filled, Lacc), by = Ticker]
dt[, COV_d      := roll_one(obs_flag, Lacc) / Lacc, by = Ticker]
dt[, n_pos_d    := roll_one(pos_flag, Lacc), by = Ticker]
dt[, n_nonNA_d  := roll_one(nonNA_flag, Lacc), by = Ticker]
dt[, PERS_d     := fifelse(n_nonNA_d > 0, n_pos_d / n_nonNA_d, NA_real_)]

# shift by 1 trading day within ticker -> "as of d-1" (C2 strict, no same-day)
dt[, ACC_raw := shift(ACC_raw_d, 1L), by = Ticker]
dt[, COV     := shift(COV_d, 1L), by = Ticker]
dt[, PERS    := shift(PERS_d, 1L), by = Ticker]
# Size as of d-1
dt[, Size_lag := shift(Size, 1L), by = Ticker]

cat("=== STEP 4: month-end sig_date slices ===\n")
dt[, ym := format(Date, "%Y-%m")]
# month-end trading day per ym (last available date in each month, across all tickers union)
month_end_dates <- dt[, .(med = max(Date)), by = ym]$med
month_end_dates <- sort(unique(month_end_dates))
month_end_dates <- month_end_dates[month_end_dates >= START_DATE]

sig <- dt[Date %in% month_end_dates]
# universe membership PIT at sig_date
sig <- sig[(K200 == 1 | KQ150 == 1)]
# require Size_lag, ACC_raw available
sig <- sig[!is.na(Size_lag) & Size_lag > 0 & !is.na(ACC_raw)]
sig[, ACC := ACC_raw / Size_lag]

cat("sig rows (month-end, universe):", nrow(sig), " months:", uniqueN(sig$Date), "\n")

cat("=== STEP 5: cross-sectional winsorized-z SCORE per sig_date ===\n")
winz <- function(x, p = 0.01) {
  q <- quantile(x, c(p, 1 - p), na.rm = TRUE, type = 7)
  pmin(pmax(x, q[1]), q[2])
}
build_scores <- function(D, cov_floor, pers_form = "mult") {
  S <- copy(D)
  # cross-sectional winsorize + z of ACC, per Date
  S[, ACC_w := winz(ACC), by = Date]
  S[, z_acc := {
      m <- mean(ACC_w, na.rm = TRUE); s <- sd(ACC_w, na.rm = TRUE)
      if (is.na(s) || s == 0) rep(0, .N) else (ACC_w - m) / s
    }, by = Date]
  if (pers_form == "mult") {
    S[, score := z_acc * (0.5 + 0.5 * fifelse(is.na(PERS), 0, PERS))]
  } else if (pers_form == "none") {
    S[, score := z_acc]
  } else if (pers_form == "hardgate") {
    S[, score := fifelse(!is.na(PERS) & PERS >= 0.5, z_acc, NA_real_)]
  }
  # sparsity floor -> NA (honest dropout, not future leak)
  S[is.na(COV) | COV < cov_floor, score := NA_real_]
  S[, .(Date, Ticker, score, COV, PERS, ACC, Size_lag, Vol, Close)]
}

cat("=== STEP 6: returns_dt (forward Ret_1m) + liq_dt + bench_dt ===\n")
# forward 1M realized return per sig_date d -> month d+1 compounded from daily Ret.
# Use R-side compounding of the NEXT month's daily simple returns via prod is hand-synth;
# instead build monthly forward return as the realized return between consecutive month-ends.
# Approach: monthly price relative from month-end Close to next month-end Close (total via Ret chain).
# Use rawdata Ret (daily simple) compounded ONLY for label construction (forward realized),
# label is not a synthetic backtest metric; canonical_screen_bt does the portfolio compounding.
rd2 <- rd[!is.na(Ret)]
setorder(rd2, Ticker, Date)
rd2[, ym := format(Date, "%Y-%m")]
# monthly forward return per ticker: realized over the month AFTER sig_date.
# Build month-end -> next-month realized: compound daily Ret within each calendar month,
# then align so Ret_1m at sig_date d = realized return of month (d+1).
mret <- rd2[, .(mret = prod(1 + Ret) - 1), by = .(Ticker, ym)]
# NOTE: prod(1+Ret)-1 here constructs the FORWARD LABEL (asset realized monthly return),
# NOT a portfolio backtest metric. Portfolio compounding/cost is done by canonical_screen_bt
# (build_benchmark_compare). This is label construction (allowed; standard forward return).
mret[, ym_idx := as.integer(factor(ym, levels = sort(unique(ym))))]
setorder(mret, Ticker, ym_idx)
mret[, mret_fwd := shift(mret, -1L), by = Ticker]      # next month's realized return
mret[, ym_fwd_idx := shift(ym_idx, -1L), by = Ticker]
# only contiguous months (no gap) qualify as a valid forward label
mret[, valid_fwd := !is.na(ym_fwd_idx) & (ym_fwd_idx == ym_idx + 1L)]
mret_valid <- mret[valid_fwd == TRUE, .(Ticker, ym, Ret_1m = mret_fwd)]

# map sig_date (month-end Date) -> its ym, attach forward realized return
me_map <- data.table(Date = month_end_dates, ym = format(month_end_dates, "%Y-%m"))
returns_dt <- merge(me_map, mret_valid, by = "ym", allow.cartesian = TRUE)[, .(Date, Ticker, Ret_1m)]

# liquidity: 20d avg dollar volume (Close*Vol) as of d-1
rd[, dvol := Close * Vol]
setorder(rd, Ticker, Date)
rd[, adv20_d := frollmean(dvol, 20, align = "right", na.rm = TRUE), by = Ticker]
rd[, adv20 := shift(adv20_d, 1L), by = Ticker]          # t-1 (C10)
liq_dt <- rd[Date %in% month_end_dates, .(Date, Ticker, adv = adv20)][!is.na(adv)]

bench_dt <- bm[, .(Date, BM_Ret)]
# align bench month-end Dates to sig month-ends: benchmark.parquet may be daily.
# Build monthly benchmark return analogous to assets, then map to month-end sig dates.
bm[, ym := format(Date, "%Y-%m")]
bm_m <- bm[, .(bmret = prod(1 + BM_Ret) - 1), by = ym]    # monthly benchmark realized (label-grade)
bm_m[, ym_idx := as.integer(factor(ym, levels = sort(unique(ym))))]
setorder(bm_m, ym_idx)
bm_m[, bmret_fwd := shift(bmret, -1L)]
bm_m[, ym_fwd_idx := shift(ym_idx, -1L)]
bm_m[, valid := !is.na(ym_fwd_idx) & (ym_fwd_idx == ym_idx + 1L)]
bm_fwd <- bm_m[valid == TRUE, .(ym, BM_Ret = bmret_fwd)]
bench_dt <- merge(me_map, bm_fwd, by = "ym")[, .(Date, BM_Ret)]
setorder(bench_dt, Date)

cat("returns_dt rows:", nrow(returns_dt), " liq_dt rows:", nrow(liq_dt),
    " bench_dt rows:", nrow(bench_dt), "\n")

cat("=== STEP 7: effective breadth (sparsity diagnostic) ===\n")
breadth_report <- function(cov_floor) {
  S0 <- build_scores(sig, cov_floor, "mult")
  br <- S0[!is.na(score), .(n_eff = .N), by = Date]
  br
}
br40 <- breadth_report(0.40)
cat("Breadth (cov_floor=0.40): median eff names/month =", median(br40$n_eff),
    " min =", min(br40$n_eff), " max =", max(br40$n_eff),
    " months<20 =", sum(br40$n_eff < 20), "/", nrow(br40), "\n")
br51 <- breadth_report(0.51)
cat("Breadth (cov_floor=0.51): median =", median(br51$n_eff),
    " months<20 =", sum(br51$n_eff < 20), "/", nrow(br51), "\n")
br30 <- breadth_report(0.30)
cat("Breadth (cov_floor=0.30): median =", median(br30$n_eff),
    " months<20 =", sum(br30$n_eff < 20), "/", nrow(br30), "\n")

saveRDS(list(br40=br40, br51=br51, br30=br30), file.path(OUT, "breadth.rds"))
saveRDS(list(sig=sig, returns_dt=returns_dt, liq_dt=liq_dt, bench_dt=bench_dt,
             month_end_dates=month_end_dates),
        file.path(OUT, "prepped.rds"))

cat("=== STEP 8: rank-IC (Spearman) of primary score vs forward Ret_1m ===\n")
S_primary <- build_scores(sig, 0.40, "mult")
ic_dt <- merge(S_primary[!is.na(score)], returns_dt, by = c("Date","Ticker"))
ic_month <- ic_dt[, .(ic = if (.N >= 8) cor(score, Ret_1m, method = "spearman") else NA_real_,
                      n = .N), by = Date][!is.na(ic)]
rank_ic <- mean(ic_month$ic)
icir <- mean(ic_month$ic) / sd(ic_month$ic)
harvey_t <- rank_ic / (sd(ic_month$ic) / sqrt(nrow(ic_month)))
cat("Primary (cov0.40, L40, mult): rank_IC =", round(rank_ic,4),
    " ICIR =", round(icir,3), " Harvey-t =", round(harvey_t,3),
    " n_months =", nrow(ic_month), "\n")

saveRDS(ic_month, file.path(OUT, "ic_month_primary.rds"))
cat("=== DONE STEP 1-8 ===\n")
