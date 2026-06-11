# =============================================================================
# census v3 targeted — winsorize Z rebuild (437/437, max|Z| 42.6 -> 7.7) impact check
#   (1) XF_* ratio-type factors (denominator-explosion group, 25) single-factor sweep
#   (2) reference singles for anchor comparison: V02_EP, V14_EBIT_EV, IN03_RD_to_Market
#   (3) composites: value6_tail (anchor PORT_t 2.04) + val_rd_wc variants A/B (anchor 2.30)
#
# Methodology (old census replication — Dohoon approval 2026-06-11):
#   canonical_screen_bt() ONLY (no proxy hand-calc), long-only top-25 EW,
#   Z_Score_Aligned via load_month_factors (C13/C15), universe K200 u KQ150 (PIT
#   time-varying membership at sig month-end), liq 20d ADV >= 2e8 (t-1, C10),
#   bad-flag exclusion (AdminStock/TradingHalt/UnfaithfulDisc), 15bps one-way,
#   monthly rebal. Sig months 200612..202604 -> forward return months
#   200701..202605 (~233). metric_type = canonical_screen.
#   SR/CAGR/MDD/Calmar: PerformanceAnalytics standard functions on the identically
#   constructed monthly net series (SharpeRatio.annualized / Return.annualized /
#   maxDrawdown / CalmarRatio) — no self-synthesized compounding.
#
# Restart tolerance: per-month factor-Z chunks (fz_chunks/) + per-factor CSV append.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE   <- file.path(PROJECT_ROOT, ".cache")
OUT     <- file.path(PROJECT_ROOT, "04_Research/factor_db/census_v3_targeted")
CHUNKS  <- file.path(OUT, "fz_chunks")
RESULTS_CSV <- file.path(OUT, "census_v3_sweep.csv")
dir.create(CHUNKS, recursive = TRUE, showWarnings = FALSE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

TOP_N    <- 25L
COST_BPS <- 15
LIQ_MIN  <- 2e8
SIG_FIRST <- "200612"   # forward return month 200701
SIG_LAST  <- "202604"   # forward return month 202605

XF_FACTORS <- c(
  "XF_DU01_NetMargin","XF_DU02_AssetTurnover","XF_DU03_EquityMultiplier",
  "XF_LL01_DebtToCapital","XF_LL02_NetDebt","XF_LL03_CashRatio",
  "XF_LL04_QuickRatio","XF_LL05_WorkingCapital",
  "XF_PR01_EBITDA_Margin","XF_PR02_RetainedEarnings_Ratio","XF_PR03_TaxRate",
  "XF_PR04_NetInterestMargin","XF_PR05_EBITDA_to_Assets",
  "XF_EF01_InventoryTurnover","XF_EF02_DaysPayable","XF_EF03_DaysReceivable",
  "XF_EF04_CCC",
  "XF_GD01_GrossProfit_Growth","XF_GD02_OpProfit_Growth","XF_GD03_OCF_Growth",
  "XF_GD04_Dividend_Growth",
  "XF_RI01_RnD_to_Revenue","XF_RI02_CapEx_proxy","XF_RI03_SGA_to_Revenue",
  "XF_Q06_Op_Margin"
)
VALUE_FACTORS <- c("V02_EP","V14_EBIT_EV","V07_EV_EBITDA","V20_SP","V13_EV_Sales","V01_BM")
REF_SINGLES   <- c("V02_EP","V14_EBIT_EV","IN03_RD_to_Market")
EXTRA         <- c("IN03_RD_to_Market","R05_Tail_Risk")
TARGETS <- unique(c(XF_FACTORS, VALUE_FACTORS, EXTRA))

# =============================================================================
# 1. RAWDATA -> monthly returns / month-end ADV / membership / bad flags
# =============================================================================
cat("[1] Loading RAWDATA (selected cols)...\n")
raw <- as.data.table(read_parquet(file.path(CACHE, "rawdata.parquet"),
  col_select = c("Date","Ticker","Close","Vol","Ret","K200","KQ150",
                 "AdminStock","TradingHalt","UnfaithfulDisc")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2005-06-01") & Date <= as.Date("2026-06-30")]
raw[, ym := format(Date, "%Y%m")]
setorder(raw, Ticker, Date)

me_dates <- raw[, .(eom = max(Date)), by = ym]
setorder(me_dates, ym)
ym_sorted <- me_dates$ym
next_map  <- data.table(ym = ym_sorted[-length(ym_sorted)], ym_next = ym_sorted[-1])
ym2date   <- me_dates[, .(ym, Date = eom)]

# monthly compounded asset return (asset-level input to contract; allowed)
mret <- raw[!is.na(Ret), .(mret = prod(1 + Ret) - 1, ndays = .N), by = .(Ticker, ym)]
mret <- mret[ndays >= 5]

# benchmark monthly
bm <- as.data.table(read_parquet(file.path(CACHE, "benchmark.parquet")))
bm[, Date := as.Date(Date)]
bm <- bm[Date >= as.Date("2005-06-01")]
bm[, ym := format(Date, "%Y%m")]
bmret <- bm[!is.na(BM_Ret), .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]

# month-end state: 20d ADV (t-1 PIT), membership K200|KQ150, bad flags
raw[, tv := Vol * Close]
raw[, adv20 := frollmean(tv, 20, align = "right"), by = Ticker]
me_state <- raw[Date %in% me_dates$eom,
  .(Ticker, ym, adv20,
    member = (K200 %in% 1) | (KQ150 %in% 1),
    bad = (AdminStock %in% 1) | (TradingHalt %in% 1) | (UnfaithfulDisc %in% 1))]
me_state[is.na(bad), bad := FALSE]
uni <- me_state[member == TRUE & bad == FALSE & !is.na(adv20) & adv20 >= LIQ_MIN,
                .(ym, Ticker)]
cat(sprintf("   universe rows=%d | months=%d | median stocks/month=%.0f\n",
            nrow(uni), uniqueN(uni$ym), median(uni[, .N, by = ym]$N)))
rm(raw); gc(verbose = FALSE)

# global forward returns / bench aligned to sig Date
fwd <- merge(next_map, mret[, .(Ticker, ym_next = ym, Ret_1m = mret)],
             by = "ym_next", allow.cartesian = TRUE)[, .(ym, Ticker, Ret_1m)]
returns_dt <- merge(fwd, ym2date, by = "ym")[, .(Date, Ticker, Ret_1m)]
bench_fwd  <- merge(next_map, bmret[, .(ym_next = ym, BM_Ret = bm_mret)], by = "ym_next")
bench_dt   <- merge(bench_fwd[, .(ym, BM_Ret)], ym2date, by = "ym")[, .(Date, BM_Ret)]

# =============================================================================
# 2. Stage A — per-month factor-Z chunks (load_month_factors, C15), universe-filtered
# =============================================================================
sig_months <- ym_sorted[ym_sorted >= SIG_FIRST & ym_sorted <= SIG_LAST]
cat(sprintf("[2] Stage A: factor-Z chunks for %d sig months (%s..%s)\n",
            length(sig_months), SIG_FIRST, SIG_LAST))
t0 <- Sys.time()
n_new <- 0L
for (i in seq_along(sig_months)) {
  ym_tag <- sig_months[i]
  cpath <- file.path(CHUNKS, paste0("fz_", ym_tag, ".parquet"))
  if (file.exists(cpath)) next
  eom <- me_dates[ym == ym_tag, eom]
  fm <- tryCatch(suppressWarnings(load_month_factors(eom, coverage_min = 0.05)),
                 error = function(e) { cat(sprintf("   [ERR] %s: %s\n", ym_tag, conditionMessage(e))); NULL })
  if (is.null(fm) || nrow(fm) == 0) {
    write_parquet(data.table(ym = character(0), Ticker = character(0),
                             Factor_Name = character(0), Z = numeric(0)), cpath)
    next
  }
  fm <- as.data.table(fm)[Factor_Name %in% TARGETS]
  fm <- merge(fm, uni[ym == ym_tag, .(Ticker)], by = "Ticker")
  fm[, ym := ym_tag]
  write_parquet(fm[, .(ym, Ticker, Factor_Name, Z = Z_Score_Aligned)], cpath)
  n_new <- n_new + 1L
  if (i %% 12 == 0) {
    cat(sprintf("   ... %d/%d months (%.1f min elapsed)\n", i, length(sig_months),
                as.numeric(Sys.time() - t0, "mins")))
    gc(verbose = FALSE)
  }
}
cat(sprintf("   Stage A done: %d new chunks, %.1f min\n", n_new,
            as.numeric(Sys.time() - t0, "mins")))

FZ <- rbindlist(lapply(sig_months, function(m) {
  p <- file.path(CHUNKS, paste0("fz_", m, ".parquet"))
  if (file.exists(p)) as.data.table(read_parquet(p)) else NULL
}), fill = TRUE)
cat(sprintf("   FZ loaded: rows=%d factors=%d months=%d\n",
            nrow(FZ), uniqueN(FZ$Factor_Name), uniqueN(FZ$ym)))

# =============================================================================
# 3. Stage B — measurement helpers
# =============================================================================

# local series builder — identical construction to canonical_screen_bt internals
# (top-N EW, traded = sum|dw|, cost = traded*15bps). Series consumed ONLY by
# PerformanceAnalytics standard functions.
.build_series <- function(scores_dt) {
  S <- copy(scores_dt)[!is.na(score)]
  setorder(S, Date, -score)
  W <- S[, { n <- min(TOP_N, .N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n, n)) }, by = Date]
  R <- returns_dt[!is.na(Ret_1m)]
  WR <- merge(W, R, by = c("Date","Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
  }
  port[, cost := traded[as.character(Date)] * COST_BPS / 1e4]
  port[, ret_net := port_gross - cost]
  setorder(port, Date)
  port[, .(Date, ret_net)]
}

measure_one <- function(scores_dt, fid, kind) {
  scores_dt <- scores_dt[Date %in% bench_dt$Date]
  if (nrow(scores_dt) == 0 || uniqueN(scores_dt$Date) < 24) {
    return(data.table(factor_id = fid, kind = kind, status = "SKIP_THIN",
                      n_months = uniqueN(scores_dt$Date)))
  }
  res <- canonical_screen_bt(scores_dt, returns_dt, bench_dt,
                             top_n = TOP_N, cost_bps_oneway = COST_BPS,
                             liq_dt = NULL,   # universe+liq pre-filtered (caller duty per contract)
                             run_id = paste0("censusv3_", fid), strategy_id = fid)
  ser <- .build_series(scores_dt)
  rx <- xts(ser$ret_net, order.by = ser$Date)
  sr_abs <- as.numeric(SharpeRatio.annualized(rx, Rf = 0, scale = 12))
  cagr   <- as.numeric(Return.annualized(rx, scale = 12, geometric = TRUE))
  mdd    <- as.numeric(maxDrawdown(rx))
  calmar <- as.numeric(CalmarRatio(rx, scale = 12))
  data.table(
    factor_id = fid, kind = kind, status = "OK",
    n_months = res$n_months,
    first_sig = as.character(min(scores_dt$Date)),
    last_sig = as.character(max(scores_dt$Date)),
    port_alpha_t_nw = round(res$portfolio_alpha_t_nw_lag3, 3),
    port_alpha_p = round(res$portfolio_alpha_t_pvalue, 4),
    information_ratio = round(res$information_ratio, 3),
    alpha_annualized = round(res$alpha_annualized, 4),
    net_active_sr = round(res$net_sr, 3),
    sr_abs = round(sr_abs, 3),
    cagr = round(cagr, 4),
    mdd = round(mdd, 4),
    calmar = round(calmar, 3),
    turnover_annual = round(res$turnover_annual, 2),
    metric_type = "canonical_screen",
    run_ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )
}

append_row <- function(row) {
  fwrite(row, RESULTS_CSV, append = file.exists(RESULTS_CSV))
}

done_ids <- if (file.exists(RESULTS_CSV)) fread(RESULTS_CSV)$factor_id else character(0)

# =============================================================================
# 4. Singles sweep: 25 XF + 3 reference
# =============================================================================
cat("[4] Singles sweep...\n")
singles <- unique(c(XF_FACTORS, REF_SINGLES))
for (f in singles) {
  if (f %in% done_ids) { cat(sprintf("   [skip done] %s\n", f)); next }
  sc <- FZ[Factor_Name == f, .(ym, Ticker, score = Z)]
  sc <- merge(sc, ym2date, by = "ym")[, .(Date, Ticker, score)]
  row <- tryCatch(measure_one(sc, f, "single"),
                  error = function(e) data.table(factor_id = f, kind = "single",
                                                 status = paste0("ERR: ", conditionMessage(e))))
  append_row(row)
  cat(sprintf("   %s: %s PORT_t=%s SR=%s MDD=%s n=%s\n", f,
              row$status[1],
              if ("port_alpha_t_nw" %in% names(row)) row$port_alpha_t_nw[1] else NA,
              if ("sr_abs" %in% names(row)) row$sr_abs[1] else NA,
              if ("mdd" %in% names(row)) row$mdd[1] else NA,
              if ("n_months" %in% names(row)) row$n_months[1] else NA))
}

# =============================================================================
# 5. Composites: value6_tail / val_rd_wc variant A (sum) / variant B (mean-of-3)
# =============================================================================
cat("[5] Composites...\n")
CW <- dcast(FZ[Factor_Name %in% c(VALUE_FACTORS, "IN03_RD_to_Market",
                                  "XF_LL05_WorkingCapital", "R05_Tail_Risk")],
            ym + Ticker ~ Factor_Name, value.var = "Z")
vcols <- intersect(VALUE_FACTORS, names(CW))
CW[, n_val := rowSums(!is.na(.SD)), .SDcols = vcols]
CW[, value_z := rowMeans(.SD, na.rm = TRUE), .SDcols = vcols]
CW[n_val < 3, value_z := NA_real_]
.z0 <- function(x) fifelse(is.na(x), 0, x)
if (!"IN03_RD_to_Market" %in% names(CW)) CW[, IN03_RD_to_Market := NA_real_]
if (!"XF_LL05_WorkingCapital" %in% names(CW)) CW[, XF_LL05_WorkingCapital := NA_real_]
if (!"R05_Tail_Risk" %in% names(CW)) CW[, R05_Tail_Risk := NA_real_]

CW[, score_value6_tail := value_z + 0.5 * .z0(R05_Tail_Risk)]
CW[, score_val_rd_wc_A := value_z + .z0(IN03_RD_to_Market) + .z0(XF_LL05_WorkingCapital) +
                          0.5 * .z0(R05_Tail_Risk)]
CW[, score_val_rd_wc_B := rowMeans(cbind(value_z, IN03_RD_to_Market, XF_LL05_WorkingCapital),
                                   na.rm = TRUE) + 0.5 * .z0(R05_Tail_Risk)]
CW[is.na(value_z), `:=`(score_value6_tail = NA_real_, score_val_rd_wc_A = NA_real_,
                        score_val_rd_wc_B = NA_real_)]

for (comp in c("value6_tail","val_rd_wc_A","val_rd_wc_B")) {
  if (comp %in% done_ids) { cat(sprintf("   [skip done] %s\n", comp)); next }
  scol <- paste0("score_", comp)
  sc <- CW[!is.na(get(scol)), .(ym, Ticker, score = get(scol))]
  sc <- merge(sc, ym2date, by = "ym")[, .(Date, Ticker, score)]
  row <- tryCatch(measure_one(sc, comp, "composite"),
                  error = function(e) data.table(factor_id = comp, kind = "composite",
                                                 status = paste0("ERR: ", conditionMessage(e))))
  append_row(row)
  cat(sprintf("   %s: %s PORT_t=%s SR=%s CAGR=%s MDD=%s TO=%s\n", comp,
              row$status[1],
              if ("port_alpha_t_nw" %in% names(row)) row$port_alpha_t_nw[1] else NA,
              if ("sr_abs" %in% names(row)) row$sr_abs[1] else NA,
              if ("cagr" %in% names(row)) row$cagr[1] else NA,
              if ("mdd" %in% names(row)) row$mdd[1] else NA,
              if ("turnover_annual" %in% names(row)) row$turnover_annual[1] else NA))
}

cat("\n[6] Sweep complete. Results:", RESULTS_CSV, "\n")
print(fread(RESULTS_CSV)[, .(factor_id, kind, status, n_months, port_alpha_t_nw,
                             net_active_sr, sr_abs, cagr, mdd, calmar, turnover_annual)])
cat("DONE_CENSUS_V3_SWEEP\n")
