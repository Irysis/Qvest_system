# =============================================================================
# flow_closet_reversal_diag.R — Cycle 2 flow/microstructure near-miss resolution
#
# Builds on prior Cycle 1 Track S fair-trial (2026-06-12, prereg FLOW-S01..S09).
# investor_wide max Date = 2026-03-26 (UNCHANGED since prior run) => base 9-spec
# numbers are frozen/reproduced; this script adds the MISSING diagnostics:
#   (A) CLOSET-INDEXING check for the best flow signals (S04 composite, S01 single,
#       S03 retail-follow): active-share, top-2 mega-cap weight, and EX-MEGA-CAP
#       re-test (exclude top-2 mcap each month, re-rank top-25) -> canonical PORT_t.
#   (B) 1-month cross-sectional REVERSAL secondary test (classic retail-overreaction
#       anomaly): score = -1 * prior-1m return, canonical top-25, full + 2017+ + oos.
#
# Conditions IDENTICAL to prior Stage A (frozen):
#   universe K200|KQ150 PIT month-end + no AdminStock/TradingHalt/UnfaithfulDisc
#     + 20d ADV>=2e8 (t-1 PIT C10); top-25 EW monthly; 15bps one-way delta cost;
#   engine 02_Infrastructure/contracts/canonical_screen_bt.R (contract-grade).
#   INV Z: reuse prior raw-Z chunks (invz_chunks/, 255m 200501..202603), same
#     preregistered direction_multiplier on RAW Z (Z_Score_Aligned NOT used —
#     data-driven sign would override preregistered direction).
# PIT: INV Date<sig_date strict (compute_investor.R); reversal signal = prior-month
#   realized return known at month-end t (C5 overlay-signal t-1 by construction:
#   ranked at sig month-end, applied to FORWARD 1m return).
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
setDTthreads(1L)  # segfault guard

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE   <- file.path(PROJECT_ROOT, ".cache")
FDB_DIR <- file.path(CACHE, "factor_db")
TRACKS  <- file.path(PROJECT_ROOT, "04_Research/composition_search/cycle1_trackS")
CHUNKS  <- file.path(TRACKS, "invz_chunks")
OUT     <- file.path(PROJECT_ROOT, "stage_artifacts/flow_microstructure_cycle2")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

TOP_N    <- 25L
COST_BPS <- 15
LIQ_MIN  <- 2e8
SIG_FIRST <- "200501"
SIG_LAST  <- "202603"   # freshness-truncated (investor_wide max 2026-03-26)
D2017 <- as.Date("2017-01-01")

# -----------------------------------------------------------------------------
# 1. RAWDATA -> monthly returns / month-end state (member, ADV, bad, Size) / bench
#    (construction identical to prior flow_stage_a_engine.R + Size for mega-cap)
# -----------------------------------------------------------------------------
cat("[1] Loading RAWDATA...\n")
raw <- as.data.table(read_parquet(file.path(CACHE, "rawdata.parquet"),
  col_select = c("Date","Ticker","Close","Vol","Ret","Size","K200","KQ150",
                 "AdminStock","TradingHalt","UnfaithfulDisc")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2004-10-01") & Date <= as.Date("2026-06-30")]
raw[, ym := format(Date, "%Y%m")]
setorder(raw, Ticker, Date)

me_dates <- raw[, .(eom = max(Date)), by = ym]; setorder(me_dates, ym)
ym_sorted <- me_dates$ym
next_map  <- data.table(ym = ym_sorted[-length(ym_sorted)], ym_next = ym_sorted[-1])
ym2date   <- me_dates[, .(ym, Date = eom)]

# monthly compounded ASSET return (asset-level; contract input)
mret <- raw[!is.na(Ret), .(mret = prod(1 + Ret) - 1, ndays = .N), by = .(Ticker, ym)]
mret <- mret[ndays >= 5]

# prior-1m realized return (for reversal signal: known at month-end t)
# rev_score at ym = -1 * mret(ym)   [long past losers], applied to forward mret(ym_next)

# benchmark monthly
bm <- as.data.table(read_parquet(file.path(CACHE, "benchmark.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[Date >= as.Date("2004-12-01")]
bm[, ym := format(Date, "%Y%m")]
bmret <- bm[!is.na(BM_Ret), .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]

# month-end state: 20d ADV (t-1 PIT C10), membership, bad flags, Size (mega-cap)
raw[, tv := Vol * Close]
raw[, adv20 := shift(frollmean(tv, 20, align = "right"), 1L), by = Ticker]
me_state <- raw[Date %in% me_dates$eom,
  .(Ticker, ym, adv20, Size,
    member = (K200 %in% 1) | (KQ150 %in% 1),
    bad = (AdminStock %in% 1) | (TradingHalt %in% 1) | (UnfaithfulDisc %in% 1))]
me_state[is.na(bad), bad := FALSE]
uni <- me_state[member == TRUE & bad == FALSE & !is.na(adv20) & adv20 >= LIQ_MIN,
                .(ym, Ticker, Size)]
cat(sprintf("   universe rows=%d months=%d median stocks/mo=%.0f\n",
            nrow(uni), uniqueN(uni$ym), median(uni[, .N, by = ym]$N)))
rm(raw); invisible(gc(FALSE))

# forward returns / bench aligned to sig Date
fwd <- merge(next_map, mret[, .(Ticker, ym_next = ym, Ret_1m = mret)],
             by = "ym_next", allow.cartesian = TRUE)[, .(ym, Ticker, Ret_1m)]
returns_dt <- merge(fwd, ym2date, by = "ym")[, .(Date, Ticker, Ret_1m)]
bench_fwd  <- merge(next_map, bmret[, .(ym_next = ym, BM_Ret = bm_mret)], by = "ym_next")
bench_dt   <- merge(bench_fwd[, .(ym, BM_Ret)], ym2date, by = "ym")[, .(Date, BM_Ret)]

# top-2 mega-cap per ym (by Size within eligible universe) — for closet-index check
setorder(uni, ym, -Size)
mega2 <- uni[, .(Ticker = Ticker[seq_len(min(2L, .N))]), by = ym]
mega2[, is_mega := TRUE]

# -----------------------------------------------------------------------------
# 2. Load prior raw INV-Z chunks (255m) — reuse, no recompute
# -----------------------------------------------------------------------------
cat("[2] Loading prior INV-Z chunks...\n")
sig_months <- ym_sorted[ym_sorted >= SIG_FIRST & ym_sorted <= SIG_LAST]
FZ <- rbindlist(lapply(sig_months, function(m) {
  p <- file.path(CHUNKS, paste0("invz_", m, ".parquet"))
  if (file.exists(p)) as.data.table(read_parquet(p)) else NULL
}), fill = TRUE)
stopifnot(nrow(FZ) > 0)
cat(sprintf("   FZ rows=%d factors=%d months=%d\n",
            nrow(FZ), uniqueN(FZ$Factor_Name), uniqueN(FZ$ym)))

# -----------------------------------------------------------------------------
# 3. Score builders (preregistered directions on RAW Z; reversal from returns)
# -----------------------------------------------------------------------------
build_single <- function(fac, dir) {
  sc <- FZ[Factor_Name == fac, .(ym, Ticker, score = dir * Z)]
  merge(sc, ym2date, by = "ym")[, .(Date, Ticker, score)]
}
build_S04 <- function() {  # -mean(Z of 5), then re-z per ym  (incumbent composite)
  facs <- c("INV02_Foreign_NetBuy_60d","INV04_Inst_NetBuy_60d",
            "INV09_Flow_Persistence","INV11_Foreign_Concentration","INV07_Retail_Contrarian")
  CW <- dcast(FZ[Factor_Name %in% facs], ym + Ticker ~ Factor_Name, value.var = "Z")
  fcols <- intersect(facs, names(CW))
  CW[, raw_mean := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
  CW <- CW[is.finite(raw_mean)]
  CW[, score := -1 * raw_mean]
  CW[, score := (score - mean(score, na.rm = TRUE)) / sd(score, na.rm = TRUE), by = ym]
  merge(CW[, .(ym, Ticker, score)], ym2date, by = "ym")[, .(Date, Ticker, score)]
}
build_reversal <- function() {  # 1-month reversal: score = -1 * prior-1m return
  # prior-month return known at month-end ym; universe-filtered; applied to forward ret
  rv <- merge(mret[, .(ym, Ticker, prev_ret = mret)], uni[, .(ym, Ticker)], by = c("ym","Ticker"))
  rv[, score := -1 * prev_ret]
  merge(rv[, .(ym, Ticker, score)], ym2date, by = "ym")[, .(Date, Ticker, score)]
}

# -----------------------------------------------------------------------------
# 4. Measurement helpers
# -----------------------------------------------------------------------------
run_screen <- function(sdt, tag) {
  sdt <- sdt[Date %in% bench_dt$Date & !is.na(score)]
  canonical_screen_bt(sdt, returns_dt, bench_dt, top_n = TOP_N,
                      cost_bps_oneway = COST_BPS, liq_dt = NULL,
                      run_id = tag, strategy_id = tag)
}

# oos_retention (anchored 3-split median of net_sr OOS/IS) — matches essence_score v2 style
oos_retention <- function(sdt, tag) {
  sdt <- sdt[Date %in% bench_dt$Date & !is.na(score)]
  all_dates <- sort(unique(sdt$Date)); n_d <- length(all_dates)
  rets <- c()
  for (frac in c(0.55, 0.65, 0.75)) {
    cd <- all_dates[floor(n_d * frac)]
    isr  <- run_screen(sdt[Date <= cd], paste0(tag,"_IS"))
    oosr <- run_screen(sdt[Date >  cd], paste0(tag,"_OOS"))
    r <- if (!is.na(isr$net_sr) && isr$net_sr != 0) oosr$net_sr / isr$net_sr else NA_real_
    rets <- c(rets, r)
  }
  median(rets, na.rm = TRUE)
}

# closet-indexing metrics: build top-25 EW book, compute active-share vs cap-weight
# benchmark proxy, top-2 mega-cap weight in book
closet_metrics <- function(sdt) {
  sdt <- sdt[Date %in% bench_dt$Date & !is.na(score)]
  setorder(sdt, Date, -score)
  W <- sdt[, { n <- min(TOP_N, .N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n, n)) }, by = Date]
  W[, ym := format(Date, "%Y%m")]
  # top-2 mega-cap weight held in book
  W2 <- merge(W, mega2[, .(ym, Ticker, is_mega)], by = c("ym","Ticker"), all.x = TRUE)
  mega_w <- W2[is_mega == TRUE, .(mega_w = sum(w)), by = ym]
  mega_w_full <- merge(data.table(ym = unique(W$ym)), mega_w, by = "ym", all.x = TRUE)
  mega_w_full[is.na(mega_w), mega_w := 0]
  # active-share vs cap-weight benchmark (per ym): 0.5 * sum|w_book - w_bench_capw|
  # bench weights = Size / sum(Size) within eligible universe (cap-weight proxy of K200∪KQ150)
  uni_capw <- uni[, .(ym, Ticker, wbench = Size / sum(Size)), by = ym][, .(ym, Ticker, wbench)]
  as_rows <- list()
  for (m in unique(W$ym)) {
    bk <- W[ym == m, .(Ticker, w)]
    bn <- uni_capw[ym == m, .(Ticker, wbench)]
    mm <- merge(bk, bn, by = "Ticker", all = TRUE)
    mm[is.na(w), w := 0]; mm[is.na(wbench), wbench := 0]
    as_rows[[m]] <- data.table(ym = m, active_share = 0.5 * sum(abs(mm$w - mm$wbench)))
  }
  asdt <- rbindlist(as_rows)
  list(active_share_mean = mean(asdt$active_share),
       active_share_median = median(asdt$active_share),
       mega_top2_weight_mean = mean(mega_w_full$mega_w),
       mega_top2_weight_median = median(mega_w_full$mega_w),
       n_months = nrow(asdt))
}

# ex-mega-cap re-test: drop top-2 mega each ym, re-rank top-25
run_ex_mega <- function(sdt, tag) {
  sdt <- copy(sdt); sdt[, ym := format(Date, "%Y%m")]
  sdt <- merge(sdt, mega2[, .(ym, Ticker, is_mega)], by = c("ym","Ticker"), all.x = TRUE)
  sdt <- sdt[is.na(is_mega)][, .(Date, Ticker, score)]
  run_screen(sdt, tag)
}

pick <- function(x, nm) { v <- x[[nm]]; if (is.null(v)||length(v)==0) NA_real_ else as.numeric(v) }

# -----------------------------------------------------------------------------
# 5. Run diagnostics on best flow signals + reversal
# -----------------------------------------------------------------------------
cat("[5] Running diagnostics...\n")
specs <- list(
  S04_composite = build_S04(),
  S01_foreign60 = build_single("INV02_Foreign_NetBuy_60d", -1),
  S03_retailfollow = build_single("INV07_Retail_Contrarian", -1),
  REV_1m = build_reversal()
)

results <- list()
for (nm in names(specs)) {
  cat(sprintf("   == %s ==\n", nm))
  sdt <- specs[[nm]]
  full <- run_screen(sdt, paste0("diag_", nm))
  s17  <- run_screen(sdt[Date >= D2017], paste0("diag_", nm, "_2017p"))
  oosm <- tryCatch(oos_retention(sdt, paste0("diag_", nm)), error=function(e) NA_real_)
  cl   <- closet_metrics(sdt)
  exm  <- run_ex_mega(sdt, paste0("diag_", nm, "_exmega"))
  results[[nm]] <- list(
    port_t_full  = round(pick(full,"portfolio_alpha_t_nw_lag3"),3),
    ir_full      = round(pick(full,"information_ratio"),3),
    net_sr_full  = round(pick(full,"net_sr"),3),
    turnover     = round(pick(full,"turnover_annual"),2),
    n_months     = pick(full,"n_months"),
    port_t_2017p = round(pick(s17,"portfolio_alpha_t_nw_lag3"),3),
    net_sr_2017p = round(pick(s17,"net_sr"),3),
    oos_retention_median = round(oosm,3),
    active_share_mean    = round(cl$active_share_mean,3),
    active_share_median  = round(cl$active_share_median,3),
    mega_top2_w_mean     = round(cl$mega_top2_weight_mean,3),
    mega_top2_w_median   = round(cl$mega_top2_weight_median,3),
    exmega_port_t_full   = round(pick(exm,"portfolio_alpha_t_nw_lag3"),3),
    exmega_port_t_2017p  = round(pick(run_ex_mega(sdt[Date>=D2017], paste0("diag_",nm,"_exmega2017")),
                                       "portfolio_alpha_t_nw_lag3"),3),
    metric_type = "canonical_screen"
  )
  r <- results[[nm]]
  cat(sprintf("      PORT_t=%.3f (2017+ %.3f) oos=%.3f | AS=%.2f mega2_w=%.2f | exMega PORT_t=%.3f (2017+ %.3f)\n",
              r$port_t_full, r$port_t_2017p, r$oos_retention_median,
              r$active_share_mean, r$mega_top2_w_mean, r$exmega_port_t_full, r$exmega_port_t_2017p))
}

out <- list(
  meta = list(
    program = "Cycle 2 flow/microstructure near-miss resolution — closet-index + reversal diagnostics",
    measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    builds_on = "Cycle 1 Track S prereg FLOW-S01..S09 (2026-06-12); investor_wide max 2026-03-26 UNCHANGED",
    sig_window = c(SIG_FIRST, SIG_LAST),
    universe = "K200|KQ150 PIT month-end + no bad-flag + 20d ADV>=2e8 (t-1 C10)",
    portfolio = sprintf("top-%d EW monthly, 15bps delta cost", TOP_N),
    metric_type = "canonical_screen (screening tier — forge build_bt_result authoritative)",
    benchmark_capw_proxy = "active-share uses Size-weighted eligible universe as cap-weight benchmark proxy",
    reversal_pit = "score=-1*prior-1m realized return; ranked at month-end t, applied to FORWARD 1m (C5 t-1 by construction)"
  ),
  results = results
)
write_json(out, file.path(OUT, "flow_closet_reversal_result.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6, na = "null")
cat("\n========== DIAGNOSTIC RESULTS ==========\n")
print(rbindlist(lapply(names(results), function(n) cbind(spec=n, as.data.table(results[[n]]))), fill=TRUE)[
  , .(spec, port_t_full, port_t_2017p, oos_retention_median, active_share_mean,
      mega_top2_w_mean, exmega_port_t_full, exmega_port_t_2017p)])
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), file.path(OUT, "DONE_DIAG"))
cat("DONE_DIAG\n")
