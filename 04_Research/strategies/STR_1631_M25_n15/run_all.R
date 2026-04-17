cat("=== STR_1631_M25_n15: HRP + Gerber + RMT, N=15 집중 포트폴리오 ===\n")
## 핵심 아이디어: M11 기반 + N=15 집중 (buffer keep_n=25/entry_n=12)
## 종목 수 축소로 상위 신호 집중 → alpha 밀도 향상 검증

t0 <- Sys.time()
STRATEGY_ID <- "STR_1631_M25_n15"

# ═══════════════════════════════════════════════════════════════════
# 0. Environment Setup
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
CONS_DIR  <- file.path(CACHE_DIR, "consensus")
STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR   <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))
source(file.path(STRAT_DIR, "helpers.R"))   # Gerber + RMT + HRP + pq_load

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
  library(tidyr)
  library(lubridate)
  library(jsonlite)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

LIQ_THRESHOLD <- 2e8
N_HOLD        <- 15L       # M25: N=15 집중 (M11은 20)
MAX21D_EXCL   <- 0.80
HRP_LOOKBACK  <- 60L

cat(sprintf("[setup] STRATEGY_ID: %s | N_HOLD: %d\n", STRATEGY_ID, N_HOLD))
cat(sprintf("[setup] PROJECT_ROOT: %s\n", PROJECT_ROOT))

# ═══════════════════════════════════════════════════════════════════
# 1. Load RAWDATA
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

RAWDATA[, Date := as.Date(Date)]
BM_DT[,   Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]
BM_DT   <- BM_DT[Date >= ANALYSIS_START_DATE]

drop_cols <- intersect(c("Open","High","Low","source","Size","Market"), names(RAWDATA))
if (length(drop_cols) > 0) RAWDATA[, (drop_cols) := NULL]

if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  cat("[Step 1] Adding Name/Sector...\n")
  univ_dt <- pq_load(file.path(CACHE_DIR, "universe.parquet"))
  univ_dt[, Date := as.Date(Date)]
  setorder(univ_dt, Ticker, -Date)
  ticker_info <- univ_dt[, .(Name=Name[1], Sector=Sector[1]), by=Ticker]
  if (!"Name"   %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ticker_info[, c("Ticker","Name"),   with=FALSE], by="Ticker", all.x=TRUE)
  if (!"Sector" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ticker_info[, c("Ticker","Sector"), with=FALSE], by="Ticker", all.x=TRUE)
  rm(univ_dt, ticker_info)
}
gc(verbose = FALSE)

cat(sprintf("[Step 1] RAWDATA: %s rows | %d tickers\n",
            format(nrow(RAWDATA), big.mark=","), uniqueN(RAWDATA$Ticker)))

RAWDATA[, YM := format(Date, "%Y-%m")]
sig_dates_dt <- RAWDATA[, .(sig_date=max(Date)), by=YM]
setorder(sig_dates_dt, sig_date)
SIG_DATES <- sig_dates_dt[sig_date >= SIGNAL_START_DATE, sig_date]

setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := frollmean(TradVal, n=20L, align="right", na.rm=TRUE), by=Ticker]
RAWDATA[, TradVal := NULL]

RAWDATA[, Ret_abs := abs(Ret)]
RAWDATA[, MAX21d_raw := {
  ra <- Ret_abs; n <- length(ra)
  if (n < 21L) cummax(fifelse(is.na(ra), -Inf, ra))
  else frollapply(ra, n=21L, FUN=max, fill=NA, align="right")
}, by=Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n=1L, type="lag"), by=Ticker]
RAWDATA[, c("Ret_abs","MAX21d_raw") := NULL]

SIG_SNAP <- RAWDATA[Date %in% SIG_DATES & !is.na(Close),
                    .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d","MAX21d","YM") := NULL]
setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

cat(sprintf("[Step 1] Signal dates: %d (%s ~ %s)\n",
            length(SIG_DATES), min(SIG_DATES), max(SIG_DATES)))

# ═══════════════════════════════════════════════════════════════════
# 2. Load Consensus Data — 일괄 로드 (OPT-1 준수)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Loading Consensus parquets (bulk)...\n")

# pq_load는 helpers.R 정의 래퍼 — 루프 밖에서 일괄 로드
cons_paths <- list(
  sue          = file.path(CONS_DIR, "sue.parquet"),
  esbr         = file.path(CONS_DIR, "esbr.parquet"),
  eps_chg_1m   = file.path(CONS_DIR, "eps_chg_1m.parquet"),
  coverage     = file.path(CONS_DIR, "coverage.parquet"),
  target_price = file.path(CONS_DIR, "target_price.parquet")
)

cons_list <- lapply(names(cons_paths), function(nm) {
  dt <- pq_load(cons_paths[[nm]])
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= ANALYSIS_START_DATE]
  setkey(dt, Ticker, Date)
  cat(sprintf("  > %s: %s rows\n", nm, format(nrow(dt), big.mark=",")))
  dt
})
names(cons_list) <- names(cons_paths)

SUE_DT   <- cons_list[["sue"]]
ESBR_DT  <- cons_list[["esbr"]]
EPS1M_DT <- cons_list[["eps_chg_1m"]]
COV_DT   <- cons_list[["coverage"]]
TP_DT    <- cons_list[["target_price"]]
rm(cons_list); gc(verbose = FALSE)

# ═══════════════════════════════════════════════════════════════════
# 3. Build Monthly C19 Signals — lapply (OPT-1 준수)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Building monthly C19 signals (N=15)...\n")

z_safe <- function(x) {
  if (sum(!is.na(x)) < 3L) return(rep(NA_real_, length(x)))
  s <- sd(x, na.rm=TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (x - mean(x, na.rm=TRUE)) / s
}

FACTORS_list <- lapply(SIG_DATES, function(sd) {
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d) & LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) return(NULL)

  q80 <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm=TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= q80]
  if (nrow(univ) < 20L) return(NULL)

  probe <- data.table(Ticker=univ$Ticker, Date=sd)
  setkey(probe, Ticker, Date)

  sue_j   <- SUE_DT[probe,  roll=7L, nomatch=NA][, .(Ticker, sue)]
  esbr_j  <- ESBR_DT[probe, roll=7L, nomatch=NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll=7L, nomatch=NA][, .(Ticker, eps_chg_1m)]
  cov_j   <- COV_DT[probe,  roll=7L, nomatch=NA][, .(Ticker, coverage)]
  tp_j    <- TP_DT[probe,   roll=7L, nomatch=NA][, .(Ticker, target_price)]

  # Close 컬럼 선택: with=FALSE 방식 (Close) 패턴 회피)
  ticker_px <- univ[, c("Ticker","Close"), with=FALSE]

  sig <- Reduce(function(a, b) merge(a, b, by="Ticker", all=FALSE),
                list(ticker_px, sue_j, esbr_j, eps1m_j, cov_j, tp_j))

  sig <- sig[!is.na(coverage) & coverage >= 3L]
  if (nrow(sig) < 15L) return(NULL)

  sig[, TP_Gap  := (target_price - Close) / Close]
  sig[, z_sue   := z_safe(sue)]
  sig[, z_esbr  := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]
  sig[, z_tpgap := z_safe(TP_Gap)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if (nrow(sig) < 15L) return(NULL)

  sig[, C19 := (z_sue + z_esbr + z_eps1m + z_tpgap) / 4]
  setorder(sig, -C19)
  data.table(Date=sd, Ticker=head(sig$Ticker, N_HOLD), Score=head(sig$C19, N_HOLD))
})

FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
cat(sprintf("[Step 3] FACTORS: %d rows | %d months | %s ~ %s\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$Date), max(FACTORS$Date)))

rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, FACTORS_list, SIG_SNAP)
gc(verbose = FALSE)

# ═══════════════════════════════════════════════════════════════════
# 4. HRP Weights — lapply (OPT-1 준수)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 4] Computing HRP weights (N=15)...\n")

FACTORS_hrp <- copy(FACTORS)
FACTORS_hrp[, Weight_hrp := NA_real_]

hrp_results <- lapply(unique(FACTORS_hrp$Date), function(sd) {
  tickers   <- FACTORS_hrp[Date == sd, Ticker]
  all_dates <- sort(unique(RAWDATA[Date < sd, Date]))
  ew_w      <- setNames(rep(1/length(tickers), length(tickers)), tickers)

  if (length(all_dates) < HRP_LOOKBACK)
    return(list(date=sd, weights=ew_w, fallback=TRUE))

  lb_dates <- tail(all_dates, HRP_LOOKBACK)
  ret_sub  <- RAWDATA[Date %in% lb_dates & Ticker %in% tickers, .(Date, Ticker, Ret)]
  ret_wide <- dcast(ret_sub, Date ~ Ticker, value.var="Ret")
  ret_mat  <- as.matrix(ret_wide[, -1, with=FALSE])
  colnames(ret_mat) <- names(ret_wide)[-1]

  ok <- colSums(!is.na(ret_mat)) >= 30L
  if (sum(ok) < 2L) return(list(date=sd, weights=ew_w, fallback=TRUE))

  rm_clean <- ret_mat[, ok, drop=FALSE]
  rm_clean[is.na(rm_clean)] <- 0

  hrp_w <- tryCatch(compute_hrp_weights(rm_clean), error=function(e) NULL)
  if (is.null(hrp_w)) return(list(date=sd, weights=ew_w, fallback=TRUE))

  w_vec <- setNames(rep(0, length(tickers)), tickers)
  matched <- intersect(names(hrp_w), tickers)
  w_vec[matched] <- hrp_w[matched]
  unmatched <- setdiff(tickers, matched)
  if (length(unmatched) > 0) w_vec[unmatched] <- 0.01 / length(unmatched)
  w_vec <- w_vec / sum(w_vec)
  list(date=sd, weights=w_vec, fallback=FALSE)
})

hrp_success    <- sum(!sapply(hrp_results, `[[`, "fallback"))
hrp_fallback_n <- sum( sapply(hrp_results, `[[`, "fallback"))

invisible(lapply(hrp_results, function(res) {
  nms <- names(res$weights)
  FACTORS_hrp[Date == res$date & Ticker %in% nms,
              Weight_hrp := res$weights[Ticker]]
}))

cat(sprintf("[Step 4] HRP: %d success, %d EW fallback\n", hrp_success, hrp_fallback_n))

hrp_weight_lookup <- setNames(
  lapply(hrp_results, function(r) r$weights),
  as.character(sapply(hrp_results, `[[`, "date"))
)

# Override calc_ivol_weights — vectorized match (OPT-3 준수)
orig_ivol <- calc_ivol_weights
calc_ivol_weights <<- function(tickers, ret_dt, n_days=60, max_w=0.15) {
  matched_key <- names(hrp_weight_lookup)[
    sapply(hrp_weight_lookup, function(hw) all(tickers %in% names(hw)))
  ]
  if (length(matched_key) > 0) {
    hw <- hrp_weight_lookup[[matched_key[1]]]
    w  <- hw[tickers]
    return(as.numeric(w / sum(w)))
  }
  rep(1/length(tickers), length(tickers))
}

# M25: N=15, buffer keep_n=25/entry_n=12
sim_base <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS,
  n_holdings    = N_HOLD,
  weight_method = "ivol",
  commission    = 0.0015,
  buffer_zone   = list(keep_n=25L, entry_n=12L)
)
calc_ivol_weights <<- orig_ivol

perf_base <- summarise_perf(sim_base$strategy_xts, "M25_Base_N15")
perf_bm   <- summarise_perf(sim_base$bm_xts, "KOSPI200")
to_base   <- calc_turnover(sim_base$PORTFOLIO_LOG, sim_base$DAILY_NAV_DT)

cat("\n=== BASE (N=15, HRP-Weighted) ===\n")
print(rbind(perf_base, perf_bm))
cat(sprintf("  Turnover: %.1f%%\n", to_base))

# ═══════════════════════════════════════════════════════════════════
# 5. Regime Overlay
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 5] Regime Overlay...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME <- build_daily_regime(use_cache=TRUE)
setkey(REGIME, Date)

inv_path <- file.path(CACHE_DIR, "kodex_inverse_114800.csv")
INV_DT <- if (file.exists(inv_path)) {
  dt <- fread(inv_path); dt[, Date := as.Date(Date)]; setkey(dt, Date)
  cat("[Step 5] Inverse ETF loaded.\n"); dt
} else {
  cat("[Step 5] No inverse ETF -- using -BM proxy.\n"); NULL
}

nav_dt <- copy(sim_base$DAILY_NAV_DT)
setkey(nav_dt, Date)
nav_dt <- REGIME[, .(Date, MRS, n_axes_firing)][nav_dt, roll=TRUE]
nav_dt <- merge(nav_dt, BM_DT[, .(Date, BM_Ret)], by="Date", all.x=TRUE)

if (!is.null(INV_DT)) {
  nav_dt <- merge(nav_dt, INV_DT[, .(Date, Ret_Inv)], by="Date", all.x=TRUE)
  nav_dt[is.na(Ret_Inv), Ret_Inv := -BM_Ret]
} else {
  nav_dt[, Ret_Inv := -BM_Ret]
}
nav_dt[is.na(Ret_Inv), Ret_Inv := 0]
nav_dt[is.na(MRS), MRS := 0]
nav_dt[is.na(n_axes_firing), n_axes_firing := 0L]

# PIT NOTE: MRS already t-1 lagged in regime_engine_daily.R
nav_dt[, crisis_flag := fifelse(MRS >= 60 & n_axes_firing >= 5, 1L, 0L)]

# Vectorized consecutive count — Reduce (OPT-3 준수: 인라인 daily loop 금지)
nav_dt[, crisis_consec := Reduce(
  function(acc, x) if (x == 1L) acc + 1L else 0L,
  crisis_flag, accumulate=TRUE
)]

nav_dt[, Layer := fifelse(crisis_consec >= 3L, 3L, fifelse(MRS >= 30, 2L, 1L))]

nav_dt[, Ret_overlay := fcase(
  Layer == 1L, Strategy_Ret,
  Layer == 2L, pmax(0.5, 1.0 - (MRS - 30)/60) * Strategy_Ret,
  Layer == 3L, 0.50 * Strategy_Ret + 0.20 * Ret_Inv
)]
nav_dt[, NAV_overlay := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_overlay)]

overlay_xts <- xts(nav_dt$Ret_overlay, order.by=nav_dt$Date)
names(overlay_xts) <- "Strategy"

# ═══════════════════════════════════════════════════════════════════
# 6. Performance Summary
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 6] Performance Summary...\n")

perf_overlay <- summarise_perf(overlay_xts, "M25_Overlay_N15")
perf_bm2     <- summarise_perf(sim_base$bm_xts, "KOSPI200")

cat("\n================================================================\n")
cat(sprintf("   %s — HRP+Gerber+RMT N=15 (buffer 25/12)\n", STRATEGY_ID))
cat("================================================================\n")
cat("\n--- Base (N=15, no overlay) ---\n"); print(perf_base)
cat("\n--- With 3-Layer Regime Overlay [FINAL] ---\n"); print(perf_overlay)
cat("\n--- Benchmark ---\n"); print(perf_bm2)
cat(sprintf("\nTurnover (ann.): %.1f%%\n", to_base))
cat(sprintf("HRP success: %d | EW fallback: %d\n", hrp_success, hrp_fallback_n))
cat("================================================================\n")

cat("\n=== Regime Layer Distribution ===\n")
ld <- nav_dt[, .N, by=Layer]; ld[, Pct:=round(N/sum(N)*100,1)]; print(ld)

# ═══════════════════════════════════════════════════════════════════
# 7. Stress Test — 8대 정본 (reference_stress_periods.md)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 7] Stress Period Analysis...\n")

# 8대 스트레스 구간 (reference_stress_periods.md 정본)
stress_periods <- list(
  list(label="9/11",       start="2001-09-01", end="2001-12-31"),
  list(label="GFC",        start="2007-10-01", end="2009-03-31"),
  list(label="EuDebt",     start="2011-07-01", end="2011-12-31"),
  list(label="ChinaShock", start="2015-06-01", end="2016-02-29"),
  list(label="TradeWar",   start="2018-03-01", end="2018-12-31"),
  list(label="COVID",      start="2020-01-01", end="2020-06-30"),
  list(label="RateHike",   start="2022-01-01", end="2022-12-31"),
  list(label="IranWar",    start="2026-02-01", end="2026-04-30")
)

bm_xts_s <- xts(BM_DT[Date %in% nav_dt$Date, BM_Ret],
                 order.by=BM_DT[Date %in% nav_dt$Date, Date])
ms <- merge(overlay_xts, bm_xts_s, join="inner")
colnames(ms) <- c("Strategy","Benchmark")

stress_res <- rbindlist(lapply(stress_periods, function(sp) {
  sub <- ms[paste0(sp$start, "/", sp$end)]
  if (nrow(sub) < 5) return(NULL)
  rbind(summarise_perf(sub[,1], paste0("M25_N15 | ", sp$label)),
        summarise_perf(sub[,2], paste0("BM      | ", sp$label)))
}), fill=TRUE)

if (nrow(stress_res) > 0) {
  cat("\n=== STRESS TEST ===\n")
  print(stress_res[, .(Label, CAGR, Sharpe, MDD)])
}

# ═══════════════════════════════════════════════════════════════════
# 8. Charts
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 8] Charts...\n")
generate_charts(
  list(strategy_xts=overlay_xts, bm_xts=sim_base$bm_xts,
       DAILY_NAV_DT=nav_dt[, .(Date, NAV=NAV_overlay, Strategy_Ret=Ret_overlay)]),
  output_dir=OUT_DIR,
  strategy_name=paste(STRATEGY_ID, "-- HRP+Gerber+RMT N=15")
)

# ═══════════════════════════════════════════════════════════════════
# 9. Save
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 9] Saving results...\n")
fwrite(FACTORS_hrp, file.path(OUT_DIR, "factors.csv"))
fwrite(nav_dt[, .(Date, NAV_base=NAV, NAV_overlay,
                   Strategy_Ret, Ret_overlay, MRS, Layer)],
       file.path(OUT_DIR, "daily_nav.csv"))

write_json(list(
  strategy    = STRATEGY_ID,
  description = "HRP+Gerber+RMT N=15 concentrated portfolio",
  mutation    = "M25: M11 N20->N15, buffer keep_n=25/entry_n=12",
  base        = as.list(perf_base),
  overlay     = as.list(perf_overlay),
  benchmark   = as.list(perf_bm2),
  turnover    = to_base,
  hrp_stats   = list(success=hrp_success, fallback=hrp_fallback_n),
  params      = list(N_HOLD=N_HOLD, keep_n=25L, entry_n=12L),
  run_time    = as.numeric(difftime(Sys.time(), t0, units="secs"))
), file.path(OUT_DIR, "performance.json"), pretty=TRUE, auto_unbox=TRUE)

cat(sprintf("\n[DONE] %s in %.1f sec.\n", STRATEGY_ID,
            as.numeric(difftime(Sys.time(), t0, units="secs"))))
cat("=== END ===\n")
