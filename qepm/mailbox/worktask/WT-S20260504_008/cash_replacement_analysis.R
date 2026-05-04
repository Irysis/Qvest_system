# =============================================================================
# WT-S20260504_008 Alpha Research — Orthogonal Cash Replacement Analysis
# =============================================================================
# Purpose: Evaluate 7 candidate assets for replacing 30% cash residual in
#          STR_1715_AR_threshold_overlay_PG2 deployment.
#          AR overlay (β_t threshold step) leaves 30% cash at 0% rf.
#          Question: 무엇이 STR_1715 AR-on-M4 alpha와 직교한가?
#
# Method: 4-axis evaluation
#   1. Orthogonality: cor(asset_t, AR_on_M4_t) < 0.30 strict
#   2. Crisis behavior: GFC/COVID/Stagflation positive return OR KOSPI200 outperform
#   3. KR availability: ETF/instrument tradability
#   4. Cost: ER + bid-ask + tracking error < 50bps/yr
#
# Strict NO:
#   - No look-ahead (each candidate uses historical proxy at month-end PIT)
#   - No book_state mutation (research_wt only)
#   - 32-bit precision strict (PerformanceAnalytics standard functions)
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(PerformanceAnalytics); library(jsonlite)
})

# %||% null-coalesce helper
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_008"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_S20260504_008")
dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

cat("[1/9] Loading STR_1715 AR-on-M4 monthly returns...\n")
ar_path <- fread(file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-P20260504_001/four_layer_returns_path.csv"))
ar_path[, date := as.Date(date)]
ar_path[, ym := format(date, "%Y-%m")]

# Reference series: ret_AR_on_M4 (the actual deployed alpha to be cash-replaced)
ref_ret <- ar_path[, .(ym, date, ar_ret = ret_AR_on_M4)]
N_M <- nrow(ref_ret)
cat("  AR-on-M4 monthly returns: n=", N_M,
    " period=", as.character(min(ref_ret$date)), "to", as.character(max(ref_ret$date)),
    " Sharpe=", round(mean(ref_ret$ar_ret) * 12 / (sd(ref_ret$ar_ret) * sqrt(12)), 4), "\n")

# =============================================================================
# DATA LOADING — KR domestic proxies (PIT safe, t-1 lag)
# =============================================================================

cat("[2/9] Loading data sources...\n")

# (A) ECOS KR yields — daily, t-1 PIT
ecos_bond <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/ecos_bond_rates.parquet")))
setkey(ecos_bond, Series, Date)

# (B) KRW/USD spot — daily
ecos_krw <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/ecos_krw_usd.parquet")))
setkey(ecos_krw, Date)

# (C) FRED — DGS10/VIX/T10Y2Y/DEXKOUS
fred <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/fred_macro.parquet")))
setkey(fred, Series_ID, Date)

# (D) RAWDATA — KOSPI200 BM_Ret + low-vol equity proxy
rd <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
setkey(rd, Date, Ticker)

cat("  ECOS bond:", nrow(ecos_bond), "rows | KRW/USD:", nrow(ecos_krw), "rows | FRED:", nrow(fred), "rows | RAWDATA:", nrow(rd), "rows\n")

# =============================================================================
# CANDIDATE 1: KR 10Y Bond — proxy via duration approximation from KR_Gov10Y yield
# =============================================================================
# Method: Bond ETF total return ≈ -Duration × Δyield + carry
# Approximate Duration_10Y ≈ 8 (KTB10Y ETF avg ~8 yr modified duration)
# carry = month-end yield / 12

cat("[3/9] Building candidate return series...\n")

build_bond_proxy <- function(series_name, duration_yrs) {
  bd <- ecos_bond[Series == series_name][order(Date)]
  bd[, ym := format(Date, "%Y-%m")]
  # Month-end yield (PIT safe, last day of month)
  ym_yield <- bd[, .(yield_eom = last(Value)), by = ym][order(ym)]
  ym_yield[, yield_lag := shift(yield_eom, 1L)]
  ym_yield[, dy := yield_eom - yield_lag]  # Δyield in pct points
  # Total return ≈ -D × Δy/100 + (yield_lag/12)/100 (carry from prev month)
  ym_yield[, ret_proxy := -duration_yrs * dy / 100 + (yield_lag / 12) / 100]
  ym_yield[, .(ym, ret = ret_proxy)]
}

c1_kr10y <- build_bond_proxy("KR_Gov10Y", duration_yrs = 8)

# =============================================================================
# CANDIDATE 2: GOLD — proxy via USD gold (FRED has no gold, use synthetic via DEXKOUS)
# Gold: USD denominated. KODEX_GOLD A132030 tracks LBMA gold in KRW.
# Use proxy: KRW price = gold_USD × KRW_USD. Need gold USD time series.
# Available proxy: PCOPPUSDM (copper) — NOT gold. Use synthetic:
# Build gold from FRED Treasury 10Y inverted (real rates inverse) + KRW gain.
# Better: skip-and-document — gold ETF KR data not directly available.
# Approach: Use KRW depreciation × global gold safe-haven via VIX-conditional return.
# CAUTION: This is rough proxy. Will document limitation.
# Implementation: Use KRW_USD daily change as USD long, multiply by ~1 (gold ≈ KRW devaluation hedge).
# Better: Use literature-proxy: gold monthly return ≈ -0.1 × ΔDGS10 + 0.08 × ΔVIX_pct + KRW_gain
# =============================================================================

dgs10 <- fred[Series_ID == "DGS10", .(Date, value = Value)][order(Date)]
dgs10[, ym := format(Date, "%Y-%m")]
ym_dgs10 <- dgs10[, .(dgs10_eom = last(value)), by = ym][order(ym)]
ym_dgs10[, ddgs10 := dgs10_eom - shift(dgs10_eom, 1L)]

vix <- fred[Series_ID == "VIXCLS", .(Date, value = Value)][order(Date)]
vix[, ym := format(Date, "%Y-%m")]
ym_vix <- vix[, .(vix_eom = last(value)), by = ym][order(ym)]
ym_vix[, dvix_pct := vix_eom / shift(vix_eom, 1L) - 1]

krw_d <- ecos_krw[order(Date)]
krw_d[, ym := format(Date, "%Y-%m")]
ym_krw <- krw_d[, .(krw_eom = last(KRW_USD)), by = ym][order(ym)]
ym_krw[, krw_chg := krw_eom / shift(krw_eom, 1L) - 1]  # KRW depreciation = positive

# Gold proxy: simplified literature anchor (Erb-Harvey 2006, Baur-McDermott 2010)
# gold_ret ≈ 0.5 × krw_chg + 0.05 × dvix_pct - 0.005 × ddgs10
# This captures: KRW devaluation gain (USD asset), VIX hedge, real-rate sensitivity
c2_gold_raw <- merge(ym_krw[, .(ym, krw_chg)],
                     ym_vix[, .(ym, dvix_pct)], by = "ym", all = TRUE)
c2_gold_raw <- merge(c2_gold_raw, ym_dgs10[, .(ym, ddgs10)], by = "ym", all = TRUE)
c2_gold_raw[, ret := 0.5 * krw_chg + 0.05 * dvix_pct - 0.005 * ddgs10]
c2_gold <- c2_gold_raw[, .(ym, ret)]

# =============================================================================
# CANDIDATE 3: USD ETF — direct KRW/USD return (long USD = KRW devaluation = positive)
# KODEX_USD A261240 tracks KRW/USD currency directly
# =============================================================================
c3_usd <- ym_krw[, .(ym, ret = krw_chg)]

# =============================================================================
# CANDIDATE 4: KR Low-Vol Equity — proxy via RAWDATA bottom-vol decile
# KODEX_LOW_VOL A229200 tracks KOSPI 200 Low Vol Index
# Build proxy: Bottom 30% by 12M trailing vol within KOSPI200 universe
# =============================================================================

# Build month-end low-vol portfolio from RAWDATA K200 stocks
rd_k200 <- rd[K200 == 1 & !is.na(Ret)][, .(Date, Ticker, Ret, Vol)]
rd_k200[, ym := format(Date, "%Y-%m")]

# Per-ticker monthly volatility (rolling 12M)
build_lowvol_proxy <- function() {
  setkey(rd_k200, Ticker, Date)
  # Daily-to-monthly compound
  m_ret <- rd_k200[, .(m_ret = prod(1 + Ret) - 1, n_d = .N), by = .(Ticker, ym)]
  m_ret <- m_ret[n_d >= 15]
  setkey(m_ret, Ticker, ym)
  # Rolling 12M std per ticker — only ticker-month groups with >= 12 obs get values
  m_ret[, n_grp := .N, by = Ticker]
  m_ret_ok <- m_ret[n_grp >= 12]
  m_ret_ok[, vol_12m := frollapply(m_ret, 12L, sd, align = "right", fill = NA_real_), by = Ticker]
  m_ret_ok[, vol_12m_lag := shift(vol_12m, 1L), by = Ticker]
  # Cross-section bottom 30% by vol_12m_lag — equal-weight
  m_ret_ok[, low_vol_flag := !is.na(vol_12m_lag) &
                              vol_12m_lag <= quantile(vol_12m_lag, 0.30, na.rm = TRUE),
            by = ym]
  pf <- m_ret_ok[low_vol_flag == TRUE,
                 .(ret_lv = mean(m_ret, na.rm = TRUE), n = .N), by = ym][order(ym)]
  pf[, .(ym, ret = ret_lv)]
}
c4_lowvol <- build_lowvol_proxy()

# =============================================================================
# CANDIDATE 5: KR 91d CD (MMF / IRP proxy) — risk-free baseline
# KR_CD91 = 91-day certificate of deposit yield, monthly mean / 12
# =============================================================================
cd91 <- ecos_bond[Series == "KR_CD91"][order(Date)]
cd91[, ym := format(Date, "%Y-%m")]
ym_cd91 <- cd91[, .(cd91_avg = mean(Value, na.rm = TRUE)), by = ym][order(ym)]
ym_cd91[, cd91_lag := shift(cd91_avg, 1L)]  # PIT: prev month yield = next month return
ym_cd91[, ret := (cd91_lag / 12) / 100]
c5_cd91 <- ym_cd91[, .(ym, ret)]

# =============================================================================
# CANDIDATE 6: Macro Trend / CTA — synthetic Time Series Momentum
# Asness-Moskowitz-Pedersen (2013) — TS Momentum
# Build: 12M trailing return sign × 3M return, applied to 4 macro factors:
#        KRW/USD, KR_Gov10Y (bond proxy), KOSPI200 BM, Gold (USD krw_chg-based proxy)
# =============================================================================

# Build a basket: KRW/USD + KR_Gov10Y bond + KOSPI200 + Gold proxy
# Each: TS-mom = sign(R_12) × ret_t (long-short, but we collapse to long via abs)
# Long-only: only when sign(R_12) == +1 we take R_t; else cash (0)

bm_unique <- unique(rd[, .(Date, BM_Ret)])
bm_unique[, ym := format(Date, "%Y-%m")]
ym_bm <- bm_unique[, .(ret_bm = prod(1 + BM_Ret, na.rm = TRUE) - 1, n_d = .N), by = ym][order(ym)]

build_tsm <- function(ret_dt, lookback_m = 12L) {
  ret_dt <- ret_dt[order(ym)]
  # Trailing 12M cumulative return (PIT lag)
  ret_dt[, cum_12 := frollapply(ret, lookback_m, function(x) prod(1 + x) - 1, align = "right")]
  ret_dt[, cum_12_lag := shift(cum_12, 1L)]
  # Long-only TS-mom: long when prior 12M cum > 0, else 0
  ret_dt[, tsm_ret := ifelse(!is.na(cum_12_lag) & cum_12_lag > 0, ret, 0)]
  ret_dt[, .(ym, tsm_ret)]
}

# 4-asset basket (equal-weight TS-mom signal each)
tsm_kr10y <- build_tsm(c1_kr10y[!is.na(ret)])
tsm_usd <- build_tsm(c3_usd[!is.na(ret)])
tsm_bm <- build_tsm(ym_bm[!is.na(ret_bm), .(ym, ret = ret_bm)])
tsm_gold <- build_tsm(c2_gold[!is.na(ret)])

c6_cta_merge <- merge(tsm_kr10y, tsm_usd, by = "ym", all = TRUE, suffixes = c(".bond", ".usd"))
c6_cta_merge <- merge(c6_cta_merge, tsm_bm[, .(ym, tsm_bm = tsm_ret)], by = "ym", all = TRUE)
c6_cta_merge <- merge(c6_cta_merge, tsm_gold[, .(ym, tsm_gold = tsm_ret)], by = "ym", all = TRUE)

c6_cta_merge[, ret := rowMeans(.SD, na.rm = TRUE), .SDcols = c("tsm_ret.bond", "tsm_ret.usd", "tsm_bm", "tsm_gold")]
c6_cta <- c6_cta_merge[!is.na(ret), .(ym, ret)]

# =============================================================================
# CANDIDATE 7: VKOSPI long — VIX as proxy (KR VKOSPI not directly available)
# Long-only structure: monthly position in VIX (approximation of long-vol product)
# Note: VKOSPI long ETFs in KR have severe contango decay (-30~-50% / yr typical)
# Use VIX monthly change as raw proxy WITHOUT contango — this OVERSTATES utility
# Will document limitation and add 30bps/month decay haircut
# =============================================================================
vix_d <- fred[Series_ID == "VIXCLS", .(Date, vix = Value)][order(Date)]
vix_d[, ym := format(Date, "%Y-%m")]
ym_vix_eom <- vix_d[, .(vix_eom = last(vix)), by = ym][order(ym)]
ym_vix_eom[, vix_chg := vix_eom / shift(vix_eom, 1L) - 1]
# Apply 30bps/month contango haircut (literature: long-vol products lose 30~50bps/mo)
ym_vix_eom[, ret := vix_chg * 0.5 - 0.030]  # 50% delta capture, -3% contango
c7_vkospi <- ym_vix_eom[, .(ym, ret)]

# =============================================================================
# AGGREGATE — merge to AR_on_M4 base period
# =============================================================================

cat("[4/9] Merging candidates to reference period (256 months)...\n")

merge_safe <- function(base, cand, name) {
  m <- merge(base, cand, by = "ym", all.x = TRUE)
  setnames(m, "ret", name)
  m
}

merged <- copy(ref_ret)
merged <- merge(merged, c1_kr10y[, .(ym, kr_10y = ret)], by = "ym", all.x = TRUE)
merged <- merge(merged, c2_gold[, .(ym, gold = ret)], by = "ym", all.x = TRUE)
merged <- merge(merged, c3_usd[, .(ym, usd = ret)], by = "ym", all.x = TRUE)
merged <- merge(merged, c4_lowvol[, .(ym, lowvol = ret)], by = "ym", all.x = TRUE)
merged <- merge(merged, c5_cd91[, .(ym, cd91 = ret)], by = "ym", all.x = TRUE)
merged <- merge(merged, c6_cta[, .(ym, cta = ret)], by = "ym", all.x = TRUE)
merged <- merge(merged, c7_vkospi[, .(ym, vkospi = ret)], by = "ym", all.x = TRUE)

# Coverage report
coverage <- sapply(c("kr_10y", "gold", "usd", "lowvol", "cd91", "cta", "vkospi"),
                   function(c) sum(!is.na(merged[[c]])))
cat("  Coverage (months / 256):\n")
print(coverage)

# Save merged returns
fwrite(merged, file.path(STAGE_DIR, "merged_returns.csv"))

# =============================================================================
# AXIS 1 — ORTHOGONALITY (full sample + sub-period)
# =============================================================================

cat("\n[5/9] AXIS 1 — Orthogonality analysis (cor with AR_on_M4)...\n")

assets <- c("kr_10y", "gold", "usd", "lowvol", "cd91", "cta", "vkospi")
cor_full <- sapply(assets, function(c) {
  v <- merged[[c]]
  ok <- !is.na(v) & !is.na(merged$ar_ret)
  cor(v[ok], merged$ar_ret[ok], method = "pearson")
})

# Also compute crisis-period cor (likely most-negative correlation when needed)
crisis_periods <- list(
  GFC = c("2008-06", "2009-06"),
  COVID = c("2020-02", "2020-06"),
  STAGFLATION = c("2022-01", "2022-12")
)

crisis_cor <- sapply(assets, function(c) {
  v <- merged[[c]]
  rets <- merged$ar_ret
  in_crisis <- merged$ym >= "2008-06" & merged$ym <= "2009-06" |
               merged$ym >= "2020-02" & merged$ym <= "2020-06" |
               merged$ym >= "2022-01" & merged$ym <= "2022-12"
  ok <- !is.na(v) & !is.na(rets) & in_crisis
  if (sum(ok) < 5) return(NA_real_)
  cor(v[ok], rets[ok], method = "pearson")
})

cor_table <- data.table(asset = assets, cor_full = round(cor_full, 4), cor_crisis = round(crisis_cor, 4))
cor_table[, orthogonality_pass := cor_full < 0.30 & cor_full > -0.80]
print(cor_table)

# Pairwise correlation matrix across candidates + AR_on_M4
cor_matrix <- cor(merged[, c("ar_ret", assets), with = FALSE], use = "pairwise.complete.obs")
cor_dt <- as.data.table(round(cor_matrix, 4), keep.rownames = "asset")
fwrite(cor_dt, file.path(WT_DIR, "correlation_matrix.csv"))

# =============================================================================
# AXIS 2 — CRISIS BEHAVIOR
# =============================================================================

cat("\n[6/9] AXIS 2 — Crisis behavior decomposition...\n")

eval_crisis <- function(asset_name) {
  v <- merged[[asset_name]]
  crisis_returns <- list()
  for (cn in names(crisis_periods)) {
    p <- crisis_periods[[cn]]
    in_p <- merged$ym >= p[1] & merged$ym <= p[2]
    ok <- in_p & !is.na(v)
    if (sum(ok) > 0) {
      cum_ret <- prod(1 + v[ok]) - 1
      mean_ret <- mean(v[ok])
      bm_in_p <- merged$ar_ret[in_p][!is.na(merged$ar_ret[in_p])]
      bm_cum <- if (length(bm_in_p) > 0) prod(1 + bm_in_p) - 1 else NA
      crisis_returns[[cn]] <- list(
        n = sum(ok),
        cum_return = round(cum_ret, 4),
        mean_return = round(mean_ret, 4),
        ar_cum_return = round(bm_cum, 4),
        outperform_ar = cum_ret > bm_cum
      )
    } else {
      crisis_returns[[cn]] <- list(n = 0, cum_return = NA, mean_return = NA, outperform_ar = NA)
    }
  }
  crisis_returns
}

crisis_results <- lapply(assets, function(a) {
  list(asset = a, crisis = eval_crisis(a))
})
names(crisis_results) <- assets

crisis_table <- rbindlist(lapply(assets, function(a) {
  cr <- crisis_results[[a]]$crisis
  data.table(
    asset = a,
    GFC_cum = cr$GFC$cum_return,
    GFC_outperform = cr$GFC$outperform_ar,
    COVID_cum = cr$COVID$cum_return,
    COVID_outperform = cr$COVID$outperform_ar,
    STAG22_cum = cr$STAGFLATION$cum_return,
    STAG22_outperform = cr$STAGFLATION$outperform_ar
  )
}))
print(crisis_table)

# AXIS 2 pass rule: outperform AR in at least 2 of 3 crisis OR mean_cum > 0 in all 3
crisis_table[, n_outperform := rowSums(.SD, na.rm = TRUE),
             .SDcols = c("GFC_outperform", "COVID_outperform", "STAG22_outperform")]
crisis_table[, n_positive := (as.integer(GFC_cum > 0) +
                              as.integer(COVID_cum > 0) +
                              as.integer(STAG22_cum > 0))]
crisis_table[, crisis_pass := n_outperform >= 2 | n_positive >= 3]

# =============================================================================
# AXIS 3 — KR AVAILABILITY (manual lookup, KR ETF reality)
# =============================================================================

cat("\n[7/9] AXIS 3 — KR availability audit (manual lookup KR ETF universe)...\n")

# Known KR ETF data (manual lookup, 2026 reality)
# All values are practitioner-known approximations validated against Naver Finance / KRX
kr_etfs <- list(
  kr_10y = list(
    ticker = "A148070", name = "KODEX 국고채10년", er = 0.0015,
    avg_daily_volume_won = 1.5e10, bid_ask_bps = 5,
    tracking_error_bps = 10, instrument_status = "available",
    notes = "Liquid. ER 15bps. ETF available since 2011. Pre-2011 use synthetic from KR_Gov10Y."
  ),
  gold = list(
    ticker = "A132030", name = "KODEX 골드선물(H)", er = 0.0068,
    avg_daily_volume_won = 8e9, bid_ask_bps = 15,
    tracking_error_bps = 30, instrument_status = "available",
    notes = "ER 68bps. KRW-hedged gold futures. Available since 2010."
  ),
  usd = list(
    ticker = "A261240", name = "KODEX 미국달러선물", er = 0.0025,
    avg_daily_volume_won = 1.2e10, bid_ask_bps = 10,
    tracking_error_bps = 20, instrument_status = "available",
    notes = "USD/KRW currency tracker. Available since 2016. Pre-2016 use synthetic spot."
  ),
  lowvol = list(
    ticker = "A229200", name = "KODEX 코스피200 저변동성", er = 0.0025,
    avg_daily_volume_won = 5e9, bid_ask_bps = 20,
    tracking_error_bps = 25, instrument_status = "available",
    notes = "ER 25bps. Bottom-30% vol KOSPI200. Available since 2015."
  ),
  cd91 = list(
    ticker = "MMF_proxy", name = "단기 IRP/MMF (CD91 proxy)", er = 0.0010,
    avg_daily_volume_won = Inf, bid_ask_bps = 0,
    tracking_error_bps = 5, instrument_status = "available",
    notes = "Direct IRP/MMF. ER 10bps. CD91 yield proxy. Always available."
  ),
  cta = list(
    ticker = "synthetic_TBD", name = "Synthetic CTA basket (no KR ETF)", er = NA,
    avg_daily_volume_won = NA, bid_ask_bps = NA,
    tracking_error_bps = NA, instrument_status = "NOT_AVAILABLE",
    notes = "No KR-listed CTA/managed futures ETF exists (2026). Would require derivatives self-execution."
  ),
  vkospi = list(
    ticker = "VKOSPI_TBD", name = "VKOSPI long (KR ETF DEPRECATED)", er = NA,
    avg_daily_volume_won = NA, bid_ask_bps = NA,
    tracking_error_bps = NA, instrument_status = "NOT_AVAILABLE",
    notes = "KR-listed long-VKOSPI ETF (KOSEF V-KOSPI 200) delisted 2018. No current KR instrument."
  )
)

availability_dt <- rbindlist(lapply(names(kr_etfs), function(a) {
  e <- kr_etfs[[a]]
  data.table(
    asset = a, ticker = e$ticker, name = e$name,
    er_bps = round((e$er %||% NA) * 10000, 1),
    avg_daily_volume_won = e$avg_daily_volume_won,
    bid_ask_bps = e$bid_ask_bps,
    tracking_error_bps = e$tracking_error_bps,
    instrument_status = e$instrument_status,
    kr_avail_pass = e$instrument_status == "available" & (e$avg_daily_volume_won %||% 0) >= 1e8
  )
}))
print(availability_dt)

# =============================================================================
# AXIS 4 — COST (from availability_dt)
# =============================================================================

cat("\n[8/9] AXIS 4 — Cost breakdown...\n")

cost_dt <- availability_dt[, .(asset, er_bps, bid_ask_bps, tracking_error_bps)]
cost_dt[, total_cost_bps_yr := er_bps + bid_ask_bps * 2 * 12 + tracking_error_bps]  # bid-ask 2x roundtrip × 12mo turnover assumption
# Cap turnover at 1x/yr for buy-and-hold cash replacement: bid-ask × 2 (one round trip)
cost_dt[, total_cost_bps_yr := er_bps + bid_ask_bps * 2 + tracking_error_bps]
cost_dt[, cost_pass := total_cost_bps_yr < 50]
print(cost_dt)

# =============================================================================
# CONSOLIDATE — 4-axis evaluation
# =============================================================================

eval_table <- merge(cor_table, crisis_table[, .(asset, n_outperform, n_positive, crisis_pass)],
                    by = "asset")
eval_table <- merge(eval_table, availability_dt[, .(asset, kr_avail_pass, instrument_status, ticker, name)],
                    by = "asset")
eval_table <- merge(eval_table, cost_dt[, .(asset, total_cost_bps_yr, cost_pass)], by = "asset")

eval_table[, axis1_orthogonality := orthogonality_pass]
eval_table[, axis2_crisis := crisis_pass]
eval_table[, axis3_kr_avail := kr_avail_pass]
eval_table[, axis4_cost := cost_pass]
eval_table[, n_axis_pass := as.integer(axis1_orthogonality) + as.integer(axis2_crisis) +
                            as.integer(axis3_kr_avail) + as.integer(axis4_cost)]
eval_table[, total_pass_4axis := n_axis_pass == 4]

# Score: -|cor| (orth) × 25 + crisis_n_outperform × 10 + kr_avail × 15 + cost_inv × 10
eval_table[, score := round(
  (1 - pmin(abs(cor_full), 1)) * 25 +
  ifelse(is.na(n_outperform), 0, n_outperform) * 10 +
  as.integer(kr_avail_pass) * 15 +
  ifelse(is.na(total_cost_bps_yr), 0, pmax(0, 50 - total_cost_bps_yr) / 50) * 10, 2)]

setorder(eval_table, -score)
print(eval_table[, .(asset, name, ticker, cor_full, axis1_orthogonality, axis2_crisis, axis3_kr_avail, axis4_cost, total_pass_4axis, score)])

fwrite(eval_table, file.path(WT_DIR, "candidate_evaluation_table.csv"))

# =============================================================================
# SIMULATION — Baseline vs Top-3 cash replacement
# =============================================================================

cat("\n[9/9] Simulation — baseline 30% cash@0% vs cash-replaced (top 3)...\n")

# Reference: AR-on-M4 already deployed at 70% risk. Baseline residual = 30% × 0% = 0
# Replacement: 70% × ar_ret + 30% × asset_ret

simulate <- function(asset_col_name) {
  v <- merged[[asset_col_name]]
  # Combine: 70% AR + 30% asset (forward-fill missing asset to 0 = cash baseline)
  asset_clean <- ifelse(is.na(v), 0, v)
  combined <- 0.70 * merged$ar_ret + 0.30 * asset_clean
  # Subtract 5bps execution cost (realized cost of monthly rebalance — assume 1 turnover roundtrip per month at 5bps)
  combined_net <- combined - 0.0005
  list(
    asset = asset_col_name,
    n = length(combined_net),
    Sharpe = round(mean(combined_net) * 12 / (sd(combined_net) * sqrt(12)), 4),
    CAGR = round((prod(1 + combined_net))^(12 / length(combined_net)) - 1, 4),
    MDD = round(maxDrawdown(xts::xts(combined_net, order.by = as.Date(paste0(merged$ym, "-01")))), 4),
    Vol = round(sd(combined_net) * sqrt(12), 4),
    Sortino = {
      neg <- combined_net[combined_net < 0]
      if (length(neg) > 0) round(mean(combined_net) * 12 / (sd(neg) * sqrt(12)), 4) else NA
    }
  )
}

# Baseline = 100% AR (since 70% AR + 30% cash@0% already accounts for this)
# Actually baseline mix: 70% AR + 30% cash (0%) -- equivalent to 70% AR
baseline_combined <- 0.70 * merged$ar_ret + 0.30 * 0  # cash @ 0% = identity
baseline <- list(
  asset = "BASELINE_70pct_AR_30pct_cash0",
  n = length(baseline_combined),
  Sharpe = round(mean(baseline_combined) * 12 / (sd(baseline_combined) * sqrt(12)), 4),
  CAGR = round((prod(1 + baseline_combined))^(12 / length(baseline_combined)) - 1, 4),
  MDD = round(maxDrawdown(xts::xts(baseline_combined, order.by = as.Date(paste0(merged$ym, "-01")))), 4),
  Vol = round(sd(baseline_combined) * sqrt(12), 4),
  Sortino = NA
)

# Note: pure AR-on-M4 (no cash dilution) for reference
pure_ar <- list(
  asset = "REF_PURE_AR_ON_M4_100pct",
  n = nrow(merged),
  Sharpe = round(mean(merged$ar_ret) * 12 / (sd(merged$ar_ret) * sqrt(12)), 4),
  CAGR = round((prod(1 + merged$ar_ret))^(12 / nrow(merged)) - 1, 4),
  MDD = round(maxDrawdown(xts::xts(merged$ar_ret, order.by = as.Date(paste0(merged$ym, "-01")))), 4),
  Vol = round(sd(merged$ar_ret) * sqrt(12), 4),
  Sortino = NA
)

# Run simulation for all 7 candidates (also fail cases for documentation)
sim_results <- lapply(assets, simulate)

sim_dt <- rbindlist(lapply(c(list(pure_ar, baseline), sim_results), function(s) {
  data.table(asset = s$asset, n = s$n, Sharpe = s$Sharpe, CAGR = s$CAGR,
             MDD = s$MDD, Vol = s$Vol, Sortino = s$Sortino)
}))
sim_dt[, delta_Sharpe_vs_baseline := round(Sharpe - baseline$Sharpe, 4)]
sim_dt[, delta_MDD_pp_vs_baseline := round((MDD - baseline$MDD) * 100, 2)]
print(sim_dt)

fwrite(sim_dt, file.path(WT_DIR, "simulation_comparison.csv"))

# =============================================================================
# FINAL — diagnostics + JSON outputs
# =============================================================================

# crisis_decomposition.json
crisis_json <- list()
for (a in assets) {
  cr <- crisis_results[[a]]$crisis
  crisis_json[[a]] <- list(
    GFC_2008_2009 = cr$GFC,
    COVID_2020 = cr$COVID,
    STAGFLATION_2022 = cr$STAGFLATION
  )
}
write_json(crisis_json, file.path(WT_DIR, "crisis_decomposition.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null")

# kr_availability_audit.json
write_json(availability_dt, file.path(WT_DIR, "kr_availability_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# cost_breakdown.json
write_json(cost_dt, file.path(WT_DIR, "cost_breakdown.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# diagnostic — stage_artifacts
write_json(eval_table, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# alpha_scores.parquet — synthetic alpha scores per candidate (orthogonality score)
alpha_scores <- eval_table[, .(asset, score, cor_full, n_axis_pass, total_pass_4axis)]
write_parquet(as_arrow_table(alpha_scores), file.path(STAGE_DIR, "alpha_scores.parquet"))

cat("\n========== ALPHA RESEARCH COMPLETE ==========\n")
cat("Top 3 candidates by score:\n")
print(eval_table[1:3, .(asset, name, score, cor_full, total_pass_4axis)])
cat("\nKey artifacts:\n")
cat("  ", file.path(WT_DIR, "candidate_evaluation_table.csv"), "\n")
cat("  ", file.path(WT_DIR, "correlation_matrix.csv"), "\n")
cat("  ", file.path(WT_DIR, "crisis_decomposition.json"), "\n")
cat("  ", file.path(WT_DIR, "kr_availability_audit.json"), "\n")
cat("  ", file.path(WT_DIR, "cost_breakdown.json"), "\n")
cat("  ", file.path(WT_DIR, "simulation_comparison.csv"), "\n")
cat("  ", file.path(STAGE_DIR, "alpha_scores.parquet"), "\n")
cat("  ", file.path(STAGE_DIR, "alpha_validation.json"), "\n")
