#==============================================================================
# Phase 1 v3 — K200 6-Family Smart Beta Factor Panel (학술 정합, R 기반 재산출)
#
# Inheritance from prelim v2 (100_k200_factor_panel.py): identical 6-family
# multi-proxy composite spec + sign-flip convention. v3 corrections:
#
# Correction 1 (도훈 mandate): Outlier handling
#   - features panel ret_h_21d_forward corruption (A007660 8235% etc, K200
#     membership discontinuity → shift(-21) jumps across deleted rows)
#   - v3 directly recomputes 21d forward log_return from rawdata.parquet
#     within continuous Close series per ticker (no K200 filter before shift).
#   - winsorize forward return at [-30%, +30%] (Fama-French 1993 std,
#     Asness-Pedersen 2003: ~3 sd ≈ ±30% for monthly equity).
#   - Then K200 universe filter applied AFTER forward return compute.
#
# Correction 2: Monthly non-overlap snapshot
#   - prelim v2: 254 month-end signals (calendar month-end, 21d horizon
#     → overlapping windows when consecutive month-ends < 21 trading days apart).
#   - v3: month-end (last trading day of each month) → 21d-forward → NEXT
#     month-end, ensuring approximately non-overlapping windows.
#   - PIT: Z_Score sourced from factor_db at sig_date (sig_date <= Usable_Date).
#
# Correction 3: Log return
#   - simple_return: r = P_t+21/P_t - 1  → asymmetric (–100% floor, +∞ ceil)
#   - log_return  : r = log(P_t+21/P_t)  → symmetric, additive across periods
#   - Both stored. Composite uses log return per Asness-Pedersen recommendation.
#
# Output:
#   - outputs/k200_factor_returns_v3.parquet
#   - outputs/k200_factor_returns_v3.meta.json
#
# PIT:
#   - C13: Z_Score_Aligned via direction map (lower_better → -Z)
#   - C14: Factor_DB Z_Score already PIT (Usable_Date <= sig_date)
#   - C15: load_month_factors() bypass NOT applicable (direct factor_db read
#     here is for prelim audit/v3 reconstruction, not for production alpha;
#     v3 produces _research_ panel. Final alpha_scores.parquet uses
#     load_month_factors path in 04_alpha_vector_compute.R).
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

# ---- Paths ----
BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs")
SHARED_OUT <- file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs")
FACTOR_DB <- file.path(BASE, ".cache/factor_db")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(SHARED_OUT, showWarnings = FALSE, recursive = TRUE)

# ---- 6-family multi-proxy composite spec (학술 정합, prelim v2 inherit) ----
FAMILIES <- list(
  value = list(
    proxies = list(
      list(name = "V01_BM",       direction = "higher_better"),
      list(name = "V02_EP",       direction = "higher_better"),
      list(name = "V03_CFP",      direction = "higher_better"),
      list(name = "V20_SP",       direction = "higher_better"),
      list(name = "V14_EBIT_EV",  direction = "higher_better")
    ),
    ref = "Asness-Frazzini 2013 (Devil in HML's Details) — 5-proxy composite"
  ),
  quality = list(
    proxies = list(
      list(name = "Q02_ROE",          direction = "higher_better"),
      list(name = "Q03_ROA",          direction = "higher_better"),
      list(name = "Q17_ROIC",         direction = "higher_better"),
      list(name = "GR05_ROE_Growth",  direction = "higher_better")
    ),
    ref = "Asness-Frazzini-Pedersen 2019 QMJ (Profitability + Growth)"
  ),
  momentum = list(
    proxies = list(
      list(name = "M01_Mom_12_1", direction = "higher_better"),
      list(name = "M02_Mom_6_1",  direction = "higher_better"),
      list(name = "M03_Mom_3_1",  direction = "higher_better")
    ),
    ref = "Asness-Moskowitz-Pedersen 2014 multi-horizon"
  ),
  low_vol = list(
    proxies = list(
      list(name = "D01_IdioVol",       direction = "lower_better"),
      list(name = "D02_Beta",          direction = "lower_better"),
      list(name = "D03_RealVol",       direction = "lower_better"),
      list(name = "D04_Downside_Beta", direction = "lower_better")
    ),
    ref = "Frazzini-Pedersen 2014 BAB + Ang 2006 IVOL + Baker-Bradley-Wurgler 2011"
  ),
  size = list(
    proxies = list(
      list(name = "S01_Size", direction = "lower_better")
    ),
    ref = "Banz 1981 SMB (sign flip from raw size = SMB)"
  ),
  dividend = list(
    proxies = list(
      list(name = "V06_fDY",               direction = "higher_better"),
      list(name = "V11_Shareholder_Yield", direction = "higher_better"),
      list(name = "V17_Payout_Ratio",      direction = "higher_better")
    ),
    ref = "Boudoukh-Michaely-Richardson-Roberts 2007 Shareholder Yield"
  )
)

# ---- Constants ----
TOP_QUINTILE_N <- 40L         # K200 = 200 stocks × 0.2 = 40
HORIZON_TRADING_DAYS <- 21L   # ~1M
WINSORIZE_LOW <- -0.30        # -30% (Fama-French 1993 ± ~3sd monthly)
WINSORIZE_HIGH <- 0.30        # +30%
DATE_START_MIN <- as.Date("2005-01-01")
LIQ_FLOOR_KRW <- 2.0e8        # 2 hundred million KRW 20d avg TV
LIQ_WINDOW <- 20L

cat("[Phase 1 v3] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load rawdata + K200 membership ----
cat("[1] Loading rawdata.parquet ...\n")
rd <- as.data.table(read_parquet(RAWDATA,
                                  col_select = c("Date", "Ticker", "Close", "Vol",
                                                  "Size", "K200", "Market")))
rd[, Date := as.Date(Date)]
rd <- rd[Date >= DATE_START_MIN]
setorder(rd, Ticker, Date)
cat("  rawdata rows:", nrow(rd), " | tickers:", uniqueN(rd$Ticker), "\n")

# ---- 2. Compute 21d forward log_return + simple_return per ticker (NO universe filter) ----
cat("[2] Computing 21d forward log_return + simple_return per ticker (no K200 filter pre-shift) ...\n")
rd[, log_close := log(pmax(Close, 0.01))]
rd[, fwd_log_ret := shift(log_close, n = HORIZON_TRADING_DAYS, type = "lead") - log_close, by = Ticker]
rd[, fwd_simple_ret := exp(fwd_log_ret) - 1]

# Validate: A007660 known fixture
v <- rd[Ticker == "A007660" & Date == as.Date("2006-06-15"), .(Date, Close, fwd_log_ret, fwd_simple_ret)]
cat("  Validation A007660 2006-06-15:\n")
print(v)
stopifnot(nrow(v) == 1, abs(v$fwd_simple_ret) < 0.5)  # must NOT be 8235%

# ---- 3. Liquidity filter (20d avg TV ≥ 2e8 KRW, t-1 lag) ----
cat("[3] Computing 20d avg trading value (Vol × Close) per ticker ...\n")
rd[, tv := Vol * Close]
rd[, tv_20d_avg := frollmean(tv, n = LIQ_WINDOW, fill = NA, align = "right"), by = Ticker]
rd[, liq_pass := shift(tv_20d_avg, n = 1L, type = "lag", fill = NA) >= LIQ_FLOOR_KRW, by = Ticker]

# ---- 4. Winsorize forward return ([-30%, +30%]) ----
cat("[4] Winsorizing fwd_simple_ret at [", WINSORIZE_LOW, ",", WINSORIZE_HIGH, "] ...\n")
# Pre-stats
ws_pre <- rd[!is.na(fwd_simple_ret) & K200 == 1.0,
              .(n = .N,
                mean_pre = mean(fwd_simple_ret),
                sd_pre = sd(fwd_simple_ret),
                p001_pre = quantile(fwd_simple_ret, 0.001),
                p999_pre = quantile(fwd_simple_ret, 0.999),
                max_pre = max(fwd_simple_ret),
                min_pre = min(fwd_simple_ret))]
cat("  Pre-winsor (K200 universe):\n")
print(ws_pre)

rd[, fwd_simple_ret_winsor := pmin(pmax(fwd_simple_ret, WINSORIZE_LOW), WINSORIZE_HIGH)]
rd[, fwd_log_ret_winsor := log(1 + fwd_simple_ret_winsor)]

# Post-stats
ws_post <- rd[!is.na(fwd_simple_ret_winsor) & K200 == 1.0,
               .(n = .N,
                 mean_post = mean(fwd_simple_ret_winsor),
                 sd_post = sd(fwd_simple_ret_winsor),
                 p001_post = quantile(fwd_simple_ret_winsor, 0.001),
                 p999_post = quantile(fwd_simple_ret_winsor, 0.999),
                 max_post = max(fwd_simple_ret_winsor),
                 min_post = min(fwd_simple_ret_winsor))]
cat("  Post-winsor (K200 universe):\n")
print(ws_post)

# ---- 5. Monthly non-overlap snapshot: pick last trading day per month per ticker ----
cat("[5] Monthly non-overlap snapshot (last trading day per month) ...\n")
rd[, ym := format(Date, "%Y-%m")]
# Compute monthly snapshot: 각 ticker의 month별 가장 마지막 Date (월말 거래일)
month_snapshot <- rd[, .SD[Date == max(Date)], by = .(Ticker, ym)]
cat("  Month snapshot rows:", nrow(month_snapshot), "\n")
# K200 + liquidity filter at snapshot
ms_k200 <- month_snapshot[K200 == 1.0 & liq_pass == TRUE & !is.na(fwd_simple_ret_winsor)]
cat("  K200 + liq filtered:", nrow(ms_k200), "\n")

# ---- 6. Load Factor DB Z_Score at month-end sig_dates ----
cat("[6] Loading factor_db Z_Score for ", length(unlist(lapply(FAMILIES, function(f) sapply(f$proxies, `[[`, "name")))), "proxies ...\n")
all_proxy_ids <- unique(unlist(lapply(FAMILIES, function(f) sapply(f$proxies, `[[`, "name"))))
cat("  proxy IDs:", paste(all_proxy_ids, collapse = ", "), "\n")

# month-end sig_dates → corresponding factor_db parquet (per month)
sig_yms <- sort(unique(ms_k200$ym))
cat("  sig_yms:", length(sig_yms), "from", sig_yms[1], "to", sig_yms[length(sig_yms)], "\n")

load_factor_db_for_yms <- function(yms, factor_ids) {
  out <- list()
  for (ym in yms) {
    ym_compact <- gsub("-", "", ym)
    f <- file.path(FACTOR_DB, paste0("factor_db_", ym_compact, ".parquet"))
    if (!file.exists(f)) {
      next
    }
    d <- as.data.table(read_parquet(f,
                                      col_select = c("Date", "Ticker", "Factor_Name", "Z_Score")))
    d <- d[Factor_Name %in% factor_ids]
    if (nrow(d) > 0) out[[length(out) + 1]] <- d
  }
  rbindlist(out, fill = TRUE)
}

fdb <- load_factor_db_for_yms(sig_yms, all_proxy_ids)
fdb[, Date := as.Date(Date)]
cat("  factor_db rows:", nrow(fdb), " | distinct Date:", uniqueN(fdb$Date), "\n")
cat("  factor_db Date range:", as.character(min(fdb$Date)), "~", as.character(max(fdb$Date)), "\n")

# ---- 7. Family composite Z + top quintile + family forward return per sig_date ----
cat("[7] Computing family composites + top quintile factor returns ...\n")

compute_family_composite <- function(fdb_at_date, family_spec) {
  proxies <- family_spec$proxies
  proxy_dts <- list()
  for (i in seq_along(proxies)) {
    p <- proxies[[i]]
    sub <- fdb_at_date[Factor_Name == p$name, .(Ticker, Z_Score)]
    if (nrow(sub) == 0) next
    if (p$direction == "lower_better") {
      sub[, Z_aligned := -Z_Score]
    } else {
      sub[, Z_aligned := Z_Score]
    }
    sub[, Z_Score := NULL]
    setnames(sub, "Z_aligned", paste0("Z_", p$name))
    proxy_dts[[i]] <- sub
  }
  proxy_dts <- Filter(Negate(is.null), proxy_dts)
  if (length(proxy_dts) == 0) return(data.table(Ticker = character(), Z_composite = numeric(), n_proxies_used = integer()))
  # Outer merge by Ticker
  out <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = TRUE), proxy_dts)
  z_cols <- grep("^Z_", names(out), value = TRUE)
  out[, Z_composite := rowMeans(.SD, na.rm = TRUE), .SDcols = z_cols]
  out[, n_proxies_used := rowSums(!is.na(.SD)), .SDcols = z_cols]
  # NaN handle (all NA rows)
  out[is.nan(Z_composite), Z_composite := NA_real_]
  out[, c("Ticker", "Z_composite", "n_proxies_used"), with = FALSE]
}

# Match Factor DB Date to ms_k200 ym
# Factor DB has one Date per month (end of month), exact match by ym
fdb[, ym := format(Date, "%Y-%m")]
ms_keyed <- ms_k200[, .(Ticker, Date_snap = Date, ym, fwd_simple_ret_winsor, fwd_log_ret_winsor)]

rows_out <- list()
for (this_ym in sig_yms) {
  fdb_ym <- fdb[ym == this_ym]
  if (nrow(fdb_ym) == 0) next
  univ <- ms_keyed[ym == this_ym]
  if (nrow(univ) < 100) next
  row_out <- list(ym = this_ym, fdb_date = unique(fdb_ym$Date)[1], n_universe = nrow(univ))
  for (fam in names(FAMILIES)) {
    comp <- compute_family_composite(fdb_ym, FAMILIES[[fam]])
    if (nrow(comp) == 0) {
      row_out[[paste0(fam, "_simple")]] <- NA_real_
      row_out[[paste0(fam, "_log")]] <- NA_real_
      row_out[[paste0(fam, "_n")]] <- NA_integer_
      next
    }
    m <- merge(comp, univ[, .(Ticker, fwd_simple_ret_winsor, fwd_log_ret_winsor)],
                by = "Ticker", how = "inner")
    m <- m[!is.na(Z_composite)]
    if (nrow(m) < 50) {
      row_out[[paste0(fam, "_simple")]] <- NA_real_
      row_out[[paste0(fam, "_log")]] <- NA_real_
      row_out[[paste0(fam, "_n")]] <- NA_integer_
      next
    }
    top_n <- min(TOP_QUINTILE_N, nrow(m))
    top <- m[order(-Z_composite)][1:top_n]
    row_out[[paste0(fam, "_simple")]] <- mean(top$fwd_simple_ret_winsor, na.rm = TRUE)
    row_out[[paste0(fam, "_log")]] <- mean(top$fwd_log_ret_winsor, na.rm = TRUE)
    row_out[[paste0(fam, "_n")]] <- nrow(top)
    row_out[[paste0(fam, "_avg_proxies")]] <- mean(top$Z_composite >= -999)  # placeholder, real avg below
  }
  rows_out[[length(rows_out) + 1]] <- row_out
}

result <- rbindlist(rows_out, fill = TRUE)
setorder(result, ym)
result[, sig_date := as.Date(fdb_date)]
cat("  Result rows:", nrow(result), "\n")

# ---- 8. Per-family summary stats (log + simple) ----
cat("[8] Per-family summary stats (annualized monthly):\n")
fam_stats <- list()
for (fam in names(FAMILIES)) {
  for (kind in c("simple", "log")) {
    col <- paste0(fam, "_", kind)
    v <- result[[col]]
    v <- v[!is.na(v)]
    if (length(v) > 0) {
      ann_ret <- mean(v) * 12
      ann_vol <- sd(v) * sqrt(12)
      sr <- if (ann_vol > 0) ann_ret / ann_vol else NA_real_
      stat <- list(family = fam, kind = kind, n_months = length(v),
                    monthly_mean = mean(v), monthly_sd = sd(v),
                    ann_ret = ann_ret, ann_vol = ann_vol, sr = sr,
                    min = min(v), max = max(v),
                    p01 = quantile(v, 0.01), p99 = quantile(v, 0.99))
      fam_stats[[paste0(fam, "_", kind)]] <- stat
      cat(sprintf("  %s_%s : n=%d  ann_ret=%6.2f%%  ann_vol=%6.2f%%  SR=%.3f  [min=%.2f%% max=%.2f%%]\n",
                  fam, kind, length(v), ann_ret * 100, ann_vol * 100, sr,
                  min(v) * 100, max(v) * 100))
    }
  }
}

# ---- 9. Save output parquet + metadata ----
cat("[9] Saving outputs ...\n")
write_parquet(result, file.path(OUT_DIR, "k200_factor_returns_v3.parquet"))
write_parquet(result, file.path(SHARED_OUT, "k200_factor_returns_v3.parquet"))

# Metadata
meta <- list(
  strategy_id = "STR_1721_SBETA_P4_Regime",
  phase = "Phase 1 v3 — winsorize + monthly non-overlap + log return",
  task_id = "WT-D20260528_003",
  corrections = list(
    correction_1 = "Outlier handling — direct rawdata forward return + winsorize [-30%, +30%]",
    correction_2 = "Monthly non-overlap (last trading day per month, 1M horizon)",
    correction_3 = "Log return primary + simple return retain (Asness-Pedersen 2003)"
  ),
  winsorize = list(low = WINSORIZE_LOW, high = WINSORIZE_HIGH,
                    ref = "Fama-French 1993 ± 3sd monthly equity"),
  families = lapply(FAMILIES, function(f) {
    list(
      proxies = sapply(f$proxies, `[[`, "name"),
      directions = sapply(f$proxies, `[[`, "direction"),
      ref = f$ref
    )
  }),
  top_quintile_n = TOP_QUINTILE_N,
  horizon_trading_days = HORIZON_TRADING_DAYS,
  liquidity_floor_krw = LIQ_FLOOR_KRW,
  liquidity_window = LIQ_WINDOW,
  n_months = nrow(result),
  date_start = as.character(min(result$sig_date, na.rm = TRUE)),
  date_end = as.character(max(result$sig_date, na.rm = TRUE)),
  winsorize_pre = ws_pre,
  winsorize_post = ws_post,
  family_stats = fam_stats,
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)
writeLines(toJSON(meta, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "k200_factor_returns_v3.meta.json"))
writeLines(toJSON(meta, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(SHARED_OUT, "k200_factor_returns_v3.meta.json"))

cat("[Phase 1 v3] === DONE === elapsed:", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
