# =============================================================================
# flow_stage_a_engine.R — Track S Stage A: FLOW family fair-trial screen
#   Prereg: PREREG_FLOW_STAGEA_CYCLE1_TRACKS (prereg_flow_specs.json,
#           FROZEN 2026-06-12T07:59:21+0900). 9 specs, selection_type="sweep".
#   ALL 9 specs measured + reported (silent drop forbidden). No spec added.
#
# Conditions (prereg measurement_conditions_frozen):
#   universe K200|KQ150 PIT month-end membership + bad-flag exclusion
#     (AdminStock/TradingHalt/UnfaithfulDisc — census v3 / harness standard)
#   liquidity 20d ADV >= 2e8 KRW at sig month-end (t-1 PIT, C10)
#   top-25 EW monthly rebal, 15bps one-way DELTA cost (v2.4 — canonical native)
#   engine: 02_Infrastructure/contracts/canonical_screen_bt.R (contract-grade,
#           build_benchmark_compare -> PORT_t NW lag-3). metric_type=canonical_screen.
#   gate: full PORT_t_nw_lag3 >= 1.96 AND 2017-01~ subwindow PORT_t > 0
#
# FRESHNESS TRUNCATION (prereg freshness_flag obligation — verified 2026-06-12):
#   investor_wide.parquet max Date = 2026-03-26 (re-verified at measurement time).
#   factor DB INV rows exist for 202604..202606 but are STALE-BUILT (their
#   Date<sig_date windows end at 2026-03-26 regardless of label month).
#   => last fresh INV sig month = 202603. SIG window = 200501..202603.
#
# RAW Z vs Z_Score_Aligned (documented deviation, bulk_loader F-01 precedent):
#   Prereg freezes score = direction_multiplier * Z_Score (raw, ex-ante direction).
#   load_month_factors() returns only Z_Score_Aligned (expanding-IC data-driven
#   sign). Using it would silently overwrite the preregistered direction with an
#   adaptive sign — breaking the prereg. Therefore this script reads raw Z_Score
#   directly with the connector's EXACT coverage filter replicated
#   (C15 letter deviation; C15 spirit = PIT discipline preserved: factor month
#   values are built strictly Date < sig_date by compute_investor.R).
#   Equivalence proof: 3 sample months, per-factor cor(raw Z, aligned Z) must be
#   +/-1 (alignment = pure sign flip; pipeline otherwise identical) — recorded.
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE   <- file.path(PROJECT_ROOT, ".cache")
FDB_DIR <- file.path(CACHE, "factor_db")
OUT     <- file.path(PROJECT_ROOT, "04_Research/composition_search/cycle1_trackS")
CHUNKS  <- file.path(OUT, "invz_chunks")
RESULTS_CSV <- file.path(OUT, "flow_stage_a_results.csv")
DETAIL_JSON <- file.path(OUT, "flow_stage_a_detail.json")
dir.create(CHUNKS, recursive = TRUE, showWarnings = FALSE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

TOP_N    <- 25L
COST_BPS <- 15
LIQ_MIN  <- 2e8
SIG_FIRST <- "200501"
SIG_LAST  <- "202603"   # freshness-truncated (see header)

NEEDED <- c("INV02_Foreign_NetBuy_60d","INV04_Inst_NetBuy_60d","INV05_Foreign_Momentum",
            "INV07_Retail_Contrarian","INV08_Foreign_Inst_Agreement","INV09_Flow_Persistence",
            "INV10_Smart_Money_Flow","INV11_Foreign_Concentration",
            "INV13_Foreign_Resid_Individual_63d")

SPECS <- list(
  list(spec_id="FLOW-S01", factors="INV02_Foreign_NetBuy_60d",            dir=-1, kind="single"),
  list(spec_id="FLOW-S02", factors="INV04_Inst_NetBuy_60d",               dir=-1, kind="single"),
  list(spec_id="FLOW-S03", factors="INV07_Retail_Contrarian",             dir=-1, kind="single"),
  list(spec_id="FLOW-S04", factors=c("INV02_Foreign_NetBuy_60d","INV04_Inst_NetBuy_60d",
                                     "INV09_Flow_Persistence","INV11_Foreign_Concentration",
                                     "INV07_Retail_Contrarian"),          dir=-1, kind="composite_rez"),
  list(spec_id="FLOW-S05", factors="INV10_Smart_Money_Flow",              dir=-1, kind="single"),
  list(spec_id="FLOW-S06", factors="INV05_Foreign_Momentum",              dir=+1, kind="single"),
  list(spec_id="FLOW-S07", factors="INV13_Foreign_Resid_Individual_63d",  dir=-1, kind="single"),
  list(spec_id="FLOW-S08", factors="INV08_Foreign_Inst_Agreement",        dir=-1, kind="single"),
  list(spec_id="FLOW-S09", factors="INV09_Flow_Persistence",              dir=-1, kind="single")
)

# =============================================================================
# 0. Freshness re-verification (prereg obligation)
# =============================================================================
cat("[0] Freshness re-verification...\n")
iw_max <- {
  d <- read_parquet(file.path(CACHE, "investor_stock/investor_wide.parquet"), col_select = "Date")
  max(as.Date(d$Date))
}
cat(sprintf("   investor_wide.parquet max Date = %s (expected 2026-03-26)\n", iw_max))
if (iw_max >= as.Date("2026-04-15")) {
  cat("   NOTE: investor cache fresher than prereg snapshot — SIG_LAST may be extendable;\n")
  cat("   keeping preregistered truncation logic (last month with window ending within sig month).\n")
}
stopifnot(iw_max == as.Date("2026-03-26"))  # if this fails, re-derive SIG_LAST manually

# =============================================================================
# 1. RAWDATA -> monthly returns / month-end state (member, ADV, bad) / benchmark
# =============================================================================
cat("[1] Loading RAWDATA (selected cols)...\n")
raw <- as.data.table(read_parquet(file.path(CACHE, "rawdata.parquet"),
  col_select = c("Date","Ticker","Close","Vol","Ret","K200","KQ150",
                 "AdminStock","TradingHalt","UnfaithfulDisc")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2004-10-01") & Date <= as.Date("2026-06-30")]
raw[, ym := format(Date, "%Y%m")]
setorder(raw, Ticker, Date)

me_dates <- raw[, .(eom = max(Date)), by = ym]
setorder(me_dates, ym)
ym_sorted <- me_dates$ym
next_map  <- data.table(ym = ym_sorted[-length(ym_sorted)], ym_next = ym_sorted[-1])
ym2date   <- me_dates[, .(ym, Date = eom)]

# monthly compounded ASSET return (input to contract — asset-level, allowed)
mret <- raw[!is.na(Ret), .(mret = prod(1 + Ret) - 1, ndays = .N), by = .(Ticker, ym)]
mret <- mret[ndays >= 5]

# benchmark monthly
bm <- as.data.table(read_parquet(file.path(CACHE, "benchmark.parquet")))
bm[, Date := as.Date(Date)]
bm <- bm[Date >= as.Date("2004-12-01")]
bm[, ym := format(Date, "%Y%m")]
bmret <- bm[!is.na(BM_Ret), .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]

# month-end state: 20d ADV (t-1 PIT C10), K200|KQ150 membership, bad flags
raw[, tv := Vol * Close]
# C10 fix (2026-06-12, pre-measurement): t-1 PIT per prereg liquidity_filter — shift(frollmean, 1) per Ticker (dpl_census.py L91-93 harness-standard pattern)
raw[, adv20 := shift(frollmean(tv, 20, align = "right"), 1L), by = Ticker]
me_state <- raw[Date %in% me_dates$eom,
  .(Ticker, ym, adv20,
    member = (K200 %in% 1) | (KQ150 %in% 1),
    bad = (AdminStock %in% 1) | (TradingHalt %in% 1) | (UnfaithfulDisc %in% 1))]
me_state[is.na(bad), bad := FALSE]
uni <- me_state[member == TRUE & bad == FALSE & !is.na(adv20) & adv20 >= LIQ_MIN,
                .(ym, Ticker)]
cat(sprintf("   universe rows=%d | months=%d | median stocks/month=%.0f\n",
            nrow(uni), uniqueN(uni$ym), median(uni[, .N, by = ym]$N)))
rm(raw); invisible(gc(verbose = FALSE))

# global forward returns / bench aligned to sig Date
fwd <- merge(next_map, mret[, .(Ticker, ym_next = ym, Ret_1m = mret)],
             by = "ym_next", allow.cartesian = TRUE)[, .(ym, Ticker, Ret_1m)]
returns_dt <- merge(fwd, ym2date, by = "ym")[, .(Date, Ticker, Ret_1m)]
bench_fwd  <- merge(next_map, bmret[, .(ym_next = ym, BM_Ret = bm_mret)], by = "ym_next")
bench_dt   <- merge(bench_fwd[, .(ym, BM_Ret)], ym2date, by = "ym")[, .(Date, BM_Ret)]

# =============================================================================
# 2. Raw INV Z chunks (connector coverage filter replicated EXACTLY; no alignment)
# =============================================================================
sig_months <- ym_sorted[ym_sorted >= SIG_FIRST & ym_sorted <= SIG_LAST]
cat(sprintf("[2] Raw INV Z chunks: %d sig months (%s..%s)\n",
            length(sig_months), SIG_FIRST, SIG_LAST))

load_raw_inv_month <- function(ym_tag) {
  fpath <- file.path(FDB_DIR, paste0("factor_db_", ym_tag, ".parquet"))
  if (!file.exists(fpath)) return(NULL)
  dt <- as.data.table(read_parquet(fpath,
        col_select = c("Ticker","Factor_Name","Z_Score","Coverage")))
  # connector-identical coverage filter (load_month_factors v2.1)
  n_tickers <- uniqueN(dt$Ticker)
  factor_cov <- dt[, .(N_Covered = sum(Coverage == TRUE & !is.na(Z_Score))), by = Factor_Name]
  factor_cov[, Pct := N_Covered / n_tickers]
  keep_factors <- factor_cov[Pct >= 0.05, Factor_Name]
  dt <- dt[Factor_Name %in% keep_factors & Coverage == TRUE & !is.na(Z_Score)]
  dt[Factor_Name %in% NEEDED, .(Ticker, Factor_Name, Z_Score)]
}

t0 <- Sys.time(); n_new <- 0L
for (i in seq_along(sig_months)) {
  ym_tag <- sig_months[i]
  cpath <- file.path(CHUNKS, paste0("invz_", ym_tag, ".parquet"))
  if (file.exists(cpath)) next
  fm <- tryCatch(load_raw_inv_month(ym_tag),
                 error = function(e) { cat(sprintf("   [ERR] %s: %s\n", ym_tag, conditionMessage(e))); NULL })
  if (is.null(fm) || nrow(fm) == 0) {
    write_parquet(data.table(ym = character(0), Ticker = character(0),
                             Factor_Name = character(0), Z = numeric(0)), cpath)
    next
  }
  fm <- merge(fm, uni[ym == ym_tag, .(Ticker)], by = "Ticker")
  fm[, ym := ym_tag]
  write_parquet(fm[, .(ym, Ticker, Factor_Name, Z = Z_Score)], cpath)
  n_new <- n_new + 1L
  if (i %% 24 == 0) {
    cat(sprintf("   ... %d/%d months (%.1f min)\n", i, length(sig_months),
                as.numeric(Sys.time() - t0, "mins")))
    invisible(gc(verbose = FALSE))
  }
}
cat(sprintf("   chunks done: %d new, %.1f min\n", n_new, as.numeric(Sys.time() - t0, "mins")))

FZ <- rbindlist(lapply(sig_months, function(m) {
  p <- file.path(CHUNKS, paste0("invz_", m, ".parquet"))
  if (file.exists(p)) as.data.table(read_parquet(p)) else NULL
}), fill = TRUE)
cat(sprintf("   FZ rows=%d factors=%d months=%d\n",
            nrow(FZ), uniqueN(FZ$Factor_Name), uniqueN(FZ$ym)))

# =============================================================================
# 3. Equivalence spot-check vs load_month_factors (C15-spirit proof, F-01 precedent)
# =============================================================================
cat("[3] Equivalence spot-check (raw vs aligned = pure sign)...\n")
equiv_rows <- list()
for (ym_tag in c("200806","201406","202006")) {
  eom <- me_dates[ym == ym_tag, eom]
  al <- tryCatch(as.data.table(load_month_factors(eom, coverage_min = 0.05)),
                 error = function(e) NULL)
  if (is.null(al)) { equiv_rows[[ym_tag]] <- data.table(ym = ym_tag, note = "load_month_factors ERR"); next }
  rawz <- load_raw_inv_month(ym_tag)
  mm <- merge(rawz, al[Factor_Name %in% NEEDED], by = c("Ticker","Factor_Name"))
  eq <- mm[, .(n = .N, cor_raw_aligned = cor(Z_Score, Z_Score_Aligned)), by = Factor_Name]
  eq[, ym := ym_tag]
  equiv_rows[[ym_tag]] <- eq
}
equiv_dt <- rbindlist(equiv_rows, fill = TRUE)
print(equiv_dt)
equiv_ok <- equiv_dt[!is.na(cor_raw_aligned), all(abs(abs(cor_raw_aligned) - 1) < 1e-9)]
cat(sprintf("   equivalence (|cor|==1): %s\n", ifelse(isTRUE(equiv_ok), "PASS", "FAIL — investigate")))

# =============================================================================
# 4. Spec score construction (preregistered direction on RAW Z)
# =============================================================================
cat("[4] Building spec scores...\n")
build_scores <- function(spec) {
  if (spec$kind == "single") {
    sc <- FZ[Factor_Name == spec$factors, .(ym, Ticker, score = spec$dir * Z)]
  } else {  # composite_rez (S04): -mean(Z of 5, na.rm) then re-z per Date
    CW <- dcast(FZ[Factor_Name %in% spec$factors], ym + Ticker ~ Factor_Name, value.var = "Z")
    fcols <- intersect(spec$factors, names(CW))
    CW[, raw_mean := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
    CW <- CW[is.finite(raw_mean)]
    CW[, score := spec$dir * raw_mean]
    CW[, score := (score - mean(score, na.rm = TRUE)) / sd(score, na.rm = TRUE), by = ym]
    sc <- CW[, .(ym, Ticker, score)]
  }
  merge(sc, ym2date, by = "ym")[, .(Date, Ticker, score)]
}

# =============================================================================
# 5. Measurement: full / 2017+ / anchored 3-split OOS — canonical_screen_bt only
# =============================================================================
cat("[5] Measuring 9 specs...\n")

run_screen <- function(sdt, tag) {
  canonical_screen_bt(sdt, returns_dt, bench_dt, top_n = TOP_N,
                      cost_bps_oneway = COST_BPS,
                      liq_dt = NULL,   # universe+liq+bad pre-filtered (caller duty per contract)
                      run_id = tag, strategy_id = tag)
}

# net series, construction identical to canonical_screen_bt internals;
# consumed ONLY by PerformanceAnalytics standard functions (census v3 precedent)
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

detail <- list()
res_rows <- list()
for (spec in SPECS) {
  sid <- spec$spec_id
  cat(sprintf("   == %s (%s, dir %+d) ==\n", sid,
              paste(substr(spec$factors, 1, 5), collapse = "+"), spec$dir))
  row <- tryCatch({
    sdt <- build_scores(spec)
    sdt <- sdt[Date %in% bench_dt$Date]
    if (nrow(sdt) == 0 || uniqueN(sdt$Date) < 24) {
      data.table(spec_id = sid, status = "SKIP_THIN", n_months = uniqueN(sdt$Date))
    } else {
      full <- run_screen(sdt, paste0("flowA_", sid))
      ser  <- .build_series(sdt)
      rx   <- xts(ser$ret_net, order.by = ser$Date)
      sr_abs <- as.numeric(SharpeRatio.annualized(rx, Rf = 0, scale = 12))
      cagr   <- as.numeric(Return.annualized(rx, scale = 12, geometric = TRUE))
      mdd    <- as.numeric(maxDrawdown(rx))
      calmar <- as.numeric(CalmarRatio(rx, scale = 12))

      d2017 <- as.Date("2017-01-01")
      s17 <- run_screen(sdt[Date >= d2017], paste0("flowA_", sid, "_2017p"))

      all_dates <- sort(unique(sdt$Date)); n_d <- length(all_dates)
      oos_splits <- list()
      for (frac in c(0.55, 0.65, 0.75)) {
        cut_date <- all_dates[floor(n_d * frac)]
        is_r  <- run_screen(sdt[Date <= cut_date], sprintf("flowA_%s_IS%d", sid, round(frac*100)))
        oos_r <- run_screen(sdt[Date >  cut_date], sprintf("flowA_%s_OOS%d", sid, round(frac*100)))
        oos_splits[[sprintf("%.2f", frac)]] <- list(
          cut_date = as.character(cut_date),
          is_net_sr = is_r$net_sr, oos_net_sr = oos_r$net_sr,
          is_port_t = is_r$portfolio_alpha_t_nw_lag3,
          oos_port_t = oos_r$portfolio_alpha_t_nw_lag3,
          retention = if (!is.na(is_r$net_sr) && is_r$net_sr != 0) oos_r$net_sr / is_r$net_sr else NA_real_)
      }
      retentions <- sapply(oos_splits, function(x) x$retention)
      oos_ret_med <- median(retentions, na.rm = TRUE)

      gate_full <- !is.na(full$portfolio_alpha_t_nw_lag3) && full$portfolio_alpha_t_nw_lag3 >= 1.96
      gate_2017 <- !is.na(s17$portfolio_alpha_t_nw_lag3) && s17$portfolio_alpha_t_nw_lag3 > 0

      detail[[sid]] <- list(full = full[c("n_months","portfolio_alpha_t_nw_lag3",
                                          "portfolio_alpha_t_pvalue","information_ratio",
                                          "alpha_annualized","net_sr","turnover_annual")],
                            sub2017 = s17[c("n_months","portfolio_alpha_t_nw_lag3","net_sr",
                                            "information_ratio")],
                            oos = oos_splits, oos_retention_median = oos_ret_med,
                            sr_abs = sr_abs, cagr = cagr, mdd = mdd, calmar = calmar)

      data.table(
        spec_id = sid,
        factor = paste(spec$factors, collapse = "+"),
        direction = spec$dir, status = "OK",
        n_months = full$n_months,
        first_sig = as.character(min(sdt$Date)), last_sig = as.character(max(sdt$Date)),
        port_t_full = round(full$portfolio_alpha_t_nw_lag3, 3),
        port_t_p_full = round(full$portfolio_alpha_t_pvalue, 4),
        ir_full = round(full$information_ratio, 3),
        alpha_ann_full = round(full$alpha_annualized, 4),
        net_active_sr_full = round(full$net_sr, 3),
        sr_abs = round(sr_abs, 3), cagr = round(cagr, 4),
        mdd = round(mdd, 4), calmar = round(calmar, 3),
        turnover_annual = round(full$turnover_annual, 2),
        n_2017p = s17$n_months,
        port_t_2017p = round(s17$portfolio_alpha_t_nw_lag3, 3),
        net_sr_2017p = round(s17$net_sr, 3),
        oos_retention_median = round(oos_ret_med, 3),
        oos_port_t_55 = round(oos_splits[["0.55"]]$oos_port_t, 3),
        oos_port_t_65 = round(oos_splits[["0.65"]]$oos_port_t, 3),
        oos_port_t_75 = round(oos_splits[["0.75"]]$oos_port_t, 3),
        gate_full_t196 = gate_full, gate_2017_pos = gate_2017,
        gate_pass = gate_full && gate_2017,
        metric_type = "canonical_screen",
        cost_model = "v2.4_kr_retail_15bps_delta",
        run_ts = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
    }
  }, error = function(e) data.table(spec_id = sid, status = paste0("ERR: ", conditionMessage(e))))
  res_rows[[sid]] <- row
  fwrite(row, RESULTS_CSV, append = file.exists(RESULTS_CSV))
  if ("port_t_full" %in% names(row)) {
    cat(sprintf("      PORT_t=%.3f (2017+ %.3f) SR=%.3f MDD=%.1f%% TO=%.2f gate=%s\n",
                row$port_t_full, row$port_t_2017p, row$sr_abs, row$mdd*100,
                row$turnover_annual, ifelse(row$gate_pass, "PASS", "FAIL")))
  } else cat(sprintf("      %s\n", row$status))
}

# =============================================================================
# 6. Emit detail JSON + summary
# =============================================================================
out <- list(
  meta = list(
    prereg_id = "PREREG_FLOW_STAGEA_CYCLE1_TRACKS",
    measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    n_specs_preregistered = 9L, n_specs_measured = length(res_rows),
    selection_type = "sweep", n_trials_this_stage = 9L,
    sig_window = c(SIG_FIRST, SIG_LAST),
    freshness = list(investor_wide_max_date = as.character(iw_max),
                     truncation = "factor DB INV 202604..202606 present but stale-built (windows end 2026-03-26) -> SIG_LAST=202603 per prereg freshness_flag obligation"),
    universe = "K200|KQ150 PIT month-end + no AdminStock/TradingHalt/UnfaithfulDisc + 20d ADV>=2e8 (t-1 C10)",
    portfolio = sprintf("top-%d EW monthly", TOP_N),
    cost_model = "v2.4_kr_retail_15bps_delta (canonical_screen_bt native sum|dw|*15bps)",
    metric_type = "canonical_screen",
    raw_z_deviation_note = "score=direction_multiplier*RAW Z_Score per prereg; load_month_factors Z_Score_Aligned NOT used (data-driven sign would override preregistered direction). Connector coverage filter replicated exactly; equivalence spot-check below.",
    equivalence_check = equiv_dt
  ),
  results = res_rows,
  detail = detail
)
write_json(out, DETAIL_JSON, pretty = TRUE, auto_unbox = TRUE, digits = 6, na = "null")

cat("\n========== STAGE A RESULTS ==========\n")
fin <- rbindlist(res_rows, fill = TRUE)
print(fin[, .(spec_id, status, n_months, port_t_full, port_t_2017p, net_active_sr_full,
              sr_abs, mdd, turnover_annual, oos_retention_median, gate_pass)])
cat("\nGate PASS list:", paste(fin[gate_pass == TRUE, spec_id], collapse = ", "), "\n")
writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), file.path(OUT, "DONE_FLOW_STAGE_A"))
cat("DONE_FLOW_STAGE_A\n")
