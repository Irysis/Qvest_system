#==============================================================================
# M36_SignedFlowRun — Investor-Flow Directional Run-Length Momentum
# WT-D20260621_007 — alpha-research (alpha-hat ONLY; no cov/weights)
#
# Concept: directional RUN-LENGTH of smart-money (Foreign+Institutional) daily
#   NetBuy = count of CONSECUTIVE same-sign net-buy days (T+1 lag).
#   Make-or-break: prove it adds over INV09_Flow_Persistence (sign-COUNT, blind
#   to consecutiveness). Target |corr| < 0.5 (monthly-median Spearman).
#
# PIT: Date < sig_date strict (C2); cross-sectional z per sig_date (C1, no pool);
#   C13 Z_Score_Aligned; C14; C15 (investor sidecar audited loader pattern).
# Real-computation: canonical_screen_bt() ONLY for the long-only top-N EW screen.
#==============================================================================
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1L)
Sys.setenv(OMP_NUM_THREADS = "1", ARROW_NUM_THREADS = "1")
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||is.na(a)) b else a

ROOT   <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUTDIR <- file.path(ROOT, "stage_artifacts", "WT-D20260621_007")
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

LOG <- file.path(OUTDIR, "build_log.txt")
logf <- function(...) { cat(..., "\n", file = LOG, append = TRUE); cat(..., "\n") }
cat("", file = LOG)  # truncate

#------------------------------------------------------------------------------
# 1. Load data
#------------------------------------------------------------------------------
logf("[1] Loading investor_wide + rawdata + benchmark ...")
inv <- as.data.table(arrow::read_parquet(
  file.path(ROOT, ".cache/investor_stock/investor_wide.parquet"),
  col_select = c("Date","Ticker","Foreign","Institutional")))
inv[, Date := as.Date(Date)]
setorder(inv, Ticker, Date)

raw <- as.data.table(arrow::read_parquet(
  file.path(ROOT, ".cache/rawdata.parquet"),
  col_select = c("Date","Ticker","Close","Vol","Size","Ret","K200","KQ150")))
raw[, Date := as.Date(Date)]
setorder(raw, Ticker, Date)

bench <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
bench[, Date := as.Date(Date)]
bench <- bench[, .(Date, BM_Ret)]

logf("    inv rows:", nrow(inv), " raw rows:", nrow(raw), " bench rows:", nrow(bench))

#------------------------------------------------------------------------------
# 2. month-end sig_dates: 2005-01 .. 2026-03 (investor data ends 2026-03-26)
#    sig_date = first trading day of month m; we evaluate forward 1M return.
#    Use month-end of each calendar month from rawdata trading calendar.
#------------------------------------------------------------------------------
cal <- sort(unique(raw[Date >= as.Date("2004-06-01"), Date]))
# month-end trading day per (year,month)
caldt <- data.table(Date = cal)
caldt[, ym := format(Date, "%Y-%m")]
me <- caldt[, .(sig_date = max(Date)), by = ym][order(sig_date)]
me <- me[sig_date >= as.Date("2005-01-01") & sig_date <= as.Date("2026-03-31")]
sig_dates <- me$sig_date
logf("[2] n sig_dates:", length(sig_dates), " from", as.character(min(sig_dates)), "to", as.character(max(sig_dates)))

#------------------------------------------------------------------------------
# 3. Vectorized run-length encoding per Ticker over the FULL daily panel (causal).
#    smart_t = Foreign+Institutional; s_t = sign with eps noise floor.
#    RunLen_t = signed consecutive same-sign streak ending at t (zero breaks).
#    This is computed once globally (left-to-right, causal) — at each sig_date we
#    then snapshot the most recent value with Date < sig_date (PIT C2).
#------------------------------------------------------------------------------
build_runlen <- function(inv, eps_krw, run_cap) {
  d <- copy(inv)
  d[, smart := Foreign + Institutional]
  d[, s := fifelse(is.na(smart), 0L,
            fifelse(smart >  eps_krw,  1L,
            fifelse(smart < -eps_krw, -1L, 0L)))]
  # run-length encoding by Ticker: cumulative same-sign streak length (abs), zero breaks
  # block id increments when sign changes OR when s==0
  d[, blk := {
      sgn <- s
      chg <- c(TRUE, sgn[-1] != sgn[-.N] | sgn[-1] == 0L)
      cumsum(chg)
    }, by = Ticker]
  # within-block cumulative count, but zero-days have run length 0
  d[, runabs := seq_len(.N), by = .(Ticker, blk)]
  d[s == 0L, runabs := 0L]
  d[, runabs := pmin(runabs, run_cap)]
  d[, RunLen := s * runabs]          # signed run length
  # MAG_RUN support: average abs flow within current streak (per-day intensity)
  d[, abs_smart := abs(smart)]
  d[, cum_abs := cumsum(fifelse(is.na(abs_smart),0,abs_smart)), by = .(Ticker, blk)]
  d[, AvgAbsFlowInRun := fifelse(runabs > 0, cum_abs / runabs, 0)]
  # NET_RUN support: cumulative signed net flow over current streak
  d[, cum_net := cumsum(fifelse(is.na(smart),0,smart)), by = .(Ticker, blk)]
  d[, NetRunCum := fifelse(s == 0L, 0, cum_net)]
  d[, .(Date, Ticker, smart, s, RunLen, AvgAbsFlowInRun, NetRunCum)]
}

#------------------------------------------------------------------------------
# 4. Snapshot at each sig_date (Date < sig_date, latest per ticker) + variant score
#    variant: RAW_RUN / MAG_RUN / NET_RUN ; size-normalize via t-1 Size.
#------------------------------------------------------------------------------
# precompute t-1 latest Size per (sig_date, ticker) is expensive; instead we
# build a daily Size carry and merge by last-obs.
size_daily <- raw[!is.na(Size) & Size > 0, .(Date, Ticker, Size)]
setorder(size_daily, Ticker, Date)

winsor_cs <- function(x){ q <- quantile(x, c(.01,.99), na.rm=TRUE); pmax(pmin(x,q[2]),q[1]) }
zscore_cs <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-12) return(rep(NA_real_,length(x))); (x-m)/s }

snapshot_scores <- function(rl, sig_dates, variant, transform, size_daily) {
  out <- vector("list", length(sig_dates))
  for (i in seq_along(sig_dates)) {
    sd_i <- sig_dates[i]
    sub <- rl[Date < sd_i]
    if (nrow(sub) == 0) next
    snap <- sub[, .SD[.N], by = Ticker,
                .SDcols = c("RunLen","AvgAbsFlowInRun","NetRunCum")]
    # t-1 latest size
    sz <- size_daily[Date < sd_i, .SD[.N], by = Ticker, .SDcols = "Size"]
    snap <- merge(snap, sz, by = "Ticker", all.x = TRUE)
    snap <- snap[!is.na(Size) & Size > 0]
    if (nrow(snap) < 30) next
    if (variant == "RAW_RUN") {
      snap[, raw := as.numeric(RunLen)]
    } else if (variant == "MAG_RUN") {
      snap[, raw := RunLen * (AvgAbsFlowInRun / Size)]
    } else if (variant == "NET_RUN") {
      snap[, raw := NetRunCum / Size]
    }
    snap <- snap[is.finite(raw)]
    if (nrow(snap) < 30) next
    if (transform == "z") {
      snap[, raw := winsor_cs(raw)]
      snap[, score := zscore_cs(raw)]
    } else {
      snap[, score := frank(raw, ties.method = "average")]
      snap[, score := (score - mean(score)) / sd(score)]
    }
    snap <- snap[!is.na(score)]
    out[[i]] <- snap[, .(Date = sd_i, Ticker, score)]
  }
  rbindlist(out)
}

#------------------------------------------------------------------------------
# 5. returns_dt (forward 1M), bench_dt, liq_dt — built once.
#    Universe: KOSPI200 ∪ KOSDAQ150 (K200|KQ150 flag at sig_date), liq 2e8.
#------------------------------------------------------------------------------
# forward 1M return per ticker per sig_date: compound daily Ret over (sig_date, next sig_date]
logf("[5] Building forward 1M returns + liquidity + universe ...")
# map each trading day to its "owning" sig_date bucket via findInterval
sig_idx <- sig_dates
# forward return: from day after sig_date[i] through sig_date[i+1]
ret_list <- vector("list", length(sig_dates)-1)
raw_ret <- raw[!is.na(Ret), .(Date, Ticker, Ret, Close, Vol, Size, K200, KQ150)]
setkey(raw_ret, Ticker, Date)
for (i in seq_len(length(sig_dates)-1)) {
  d0 <- sig_dates[i]; d1 <- sig_dates[i+1]
  win <- raw_ret[Date > d0 & Date <= d1]
  fr <- win[, .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]  # forward realized; gross compounding of realized monthly window (PIT: window is AFTER sig_date)
  # universe membership + liquidity as of t-1 (last obs < sig_date)
  univ <- raw_ret[Date < d0, .SD[.N], by = Ticker, .SDcols = c("K200","KQ150")]
  univ <- univ[(!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)]
  fr <- fr[Ticker %in% univ$Ticker]
  fr[, Date := d0]
  ret_list[[i]] <- fr
}
returns_dt <- rbindlist(ret_list)
logf("    returns_dt rows:", nrow(returns_dt))

# liquidity: 20d trailing ADV (Close*Vol) at t-1
raw_adv <- raw[!is.na(Close) & !is.na(Vol), .(Date, Ticker, tv = Close * Vol)]
setorder(raw_adv, Ticker, Date)
raw_adv[, adv20 := frollmean(tv, 20, na.rm = TRUE, align = "right"), by = Ticker]
liq_list <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  d0 <- sig_dates[i]
  l <- raw_adv[Date < d0, .SD[.N], by = Ticker, .SDcols = "adv20"]
  l[, Date := d0]; setnames(l, "adv20", "adv")
  liq_list[[i]] <- l[, .(Date, Ticker, adv)]
}
liq_dt <- rbindlist(liq_list)

# bench_dt: monthly KOSPI200 TR over the same forward windows (compound daily BM_Ret)
bench_list <- vector("list", length(sig_dates)-1)
for (i in seq_len(length(sig_dates)-1)) {
  d0 <- sig_dates[i]; d1 <- sig_dates[i+1]
  bw <- bench[Date > d0 & Date <= d1]
  bench_list[[i]] <- data.table(Date = d0, BM_Ret = prod(1 + bw$BM_Ret, na.rm = TRUE) - 1)
}
bench_dt <- rbindlist(bench_list)
logf("    bench_dt rows:", nrow(bench_dt), " liq_dt rows:", nrow(liq_dt))

# Universe-restrict scores too (only score names in returns_dt universe)
univ_keys <- unique(returns_dt[, .(Date, Ticker)])

saveRDS(list(returns_dt=returns_dt, bench_dt=bench_dt, liq_dt=liq_dt, univ_keys=univ_keys,
             sig_dates=sig_dates),
        file.path(OUTDIR, "_panels.rds"))

#------------------------------------------------------------------------------
# 6. PRIMARY config screen: MAG_RUN, run_cap=10, eps=1e8, z, top_n=20
#    + ablation variants RAW_RUN, NET_RUN at same config; top_n 15/25 robustness.
#------------------------------------------------------------------------------
logf("[6] Running canonical screens ...")
run_one <- function(variant, eps, run_cap, transform, top_n, tag) {
  rl <- build_runlen(inv, eps_krw = eps, run_cap = run_cap)
  sc <- snapshot_scores(rl, sig_dates, variant, transform, size_daily)
  # restrict scores to universe (intersection with returns_dt keys)
  sc <- merge(sc, univ_keys, by = c("Date","Ticker"))
  res <- canonical_screen_bt(sc, returns_dt, bench_dt, top_n = top_n,
                             cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                             run_id = tag, strategy_id = tag)
  list(scores = sc, res = res)
}

configs <- list(
  list(v="MAG_RUN", eps=1e8, cap=10L, tr="z",    tn=20L, tag="MAG_cap10_eps1e8_z_n20_PRIMARY"),
  list(v="RAW_RUN", eps=1e8, cap=10L, tr="z",    tn=20L, tag="RAW_cap10_eps1e8_z_n20"),
  list(v="NET_RUN", eps=1e8, cap=10L, tr="z",    tn=20L, tag="NET_cap10_eps1e8_z_n20"),
  list(v="MAG_RUN", eps=1e8, cap=10L, tr="z",    tn=15L, tag="MAG_cap10_eps1e8_z_n15"),
  list(v="MAG_RUN", eps=1e8, cap=10L, tr="z",    tn=25L, tag="MAG_cap10_eps1e8_z_n25"),
  list(v="MAG_RUN", eps=1e8, cap=10L, tr="rank", tn=20L, tag="MAG_cap10_eps1e8_rank_n20")
)

results <- list(); primary_scores <- NULL
for (cf in configs) {
  r <- run_one(cf$v, cf$eps, cf$cap, cf$tr, cf$tn, cf$tag)
  results[[cf$tag]] <- r$res
  if (cf$tag == "MAG_cap10_eps1e8_z_n20_PRIMARY") primary_scores <- r$scores
  rr <- r$res
  logf(sprintf("    %-34s n=%d PORT_t=%.2f IR=%.3f netSR=%.3f TO=%.2f alpha_ann=%.4f",
       cf$tag, rr$n_months %||% 0,
       rr$portfolio_alpha_t_nw_lag3 %||% NA, rr$information_ratio %||% NA,
       rr$net_sr %||% NA, rr$turnover_annual %||% NA, rr$alpha_annualized %||% NA))
}

saveRDS(results, file.path(OUTDIR, "_screen_results.rds"))
arrow::write_parquet(primary_scores, file.path(OUTDIR, "alpha_scores.parquet"))
logf("[6] done. primary_scores rows:", nrow(primary_scores))
