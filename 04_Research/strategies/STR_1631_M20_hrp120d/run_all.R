cat("=== STR_1631 v5 M20: HRP + Gerber + RMT 120d Lookback ===\n")
## 핵심 아이디어: HRP 공분산 lookback 60d → 120d로 확장
## Mutation M_B1: HRP_LOOKBACK 60 → 120 거래일
## 효과: N/T ratio 0.33 → 0.17, RMT Marcenko-Pastur 노이즈 탐지 정확도 향상
## 기반: STR_1631 v5 M11 (Gerber + RMT + HRP)

t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. Environment Setup
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
CONS_DIR   <- file.path(CACHE_DIR, "consensus")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

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
N_HOLD        <- 20L
MAX21D_EXCL   <- 0.80
HRP_LOOKBACK  <- 120L   # M_B1: 60d → 120d. N/T ratio 0.33→0.17

cat(sprintf("[setup] HRP_LOOKBACK: %d trading days (M_B1)\n", HRP_LOOKBACK))

# ═══════════════════════════════════════════════════════════════════
# Gerber Statistic + RMT Denoise + HRP
# ═══════════════════════════════════════════════════════════════════
gerber_cor <- function(ret_matrix, threshold = 0.5) {
  n <- ncol(ret_matrix)
  mat <- matrix(0, n, n)
  med_abs <- apply(ret_matrix, 2, function(x) median(abs(x), na.rm = TRUE))
  med_abs <- ifelse(med_abs < 1e-12, apply(ret_matrix, 2, sd, na.rm = TRUE), med_abs)
  for (i in seq_len(n)) {
    thresh_i <- threshold * med_abs[i]
    hi <- ret_matrix[, i] > thresh_i
    li <- ret_matrix[, i] < -thresh_i
    for (j in i:n) {
      if (i == j) { mat[i, j] <- 1; next }
      thresh_j <- threshold * med_abs[j]
      hj <- ret_matrix[, j] > thresh_j; lj <- ret_matrix[, j] < -thresh_j
      concordant <- sum((hi & hj) | (li & lj), na.rm = TRUE)
      discordant <- sum((hi & lj) | (li & hj), na.rm = TRUE)
      total <- concordant + discordant
      val <- if (total > 0L) (concordant - discordant) / total else 0
      mat[i, j] <- val; mat[j, i] <- val
    }
  }
  diag(mat) <- 1
  colnames(mat) <- rownames(mat) <- colnames(ret_matrix)
  mat
}

rmt_denoise_cov <- function(cov_mat, T_obs, N_assets) {
  if (N_assets < 2L || T_obs < N_assets) return(cov_mat)
  vol <- sqrt(pmax(diag(cov_mat), 1e-16))
  cor_mat <- cov_mat / (vol %o% vol)
  cor_mat <- pmin(pmax(cor_mat, -1), 1); diag(cor_mat) <- 1
  eig <- tryCatch(eigen(cor_mat, symmetric = TRUE), error = function(e) NULL)
  if (is.null(eig)) return(cov_mat)
  vals <- eig$values; vecs <- eig$vectors
  q <- T_obs / N_assets
  lambda_plus <- (1 + 1 / sqrt(q))^2
  noise_idx <- vals <= lambda_plus
  if (any(noise_idx) && !all(noise_idx)) vals[noise_idx] <- mean(vals[noise_idx])
  vals <- pmax(vals, 1e-8)
  denoised_cor <- vecs %*% diag(vals) %*% t(vecs)
  d_diag <- sqrt(pmax(diag(denoised_cor), 1e-16))
  denoised_cor <- denoised_cor / (d_diag %o% d_diag); diag(denoised_cor) <- 1
  denoised_cov <- denoised_cor * (vol %o% vol)
  colnames(denoised_cov) <- rownames(denoised_cov) <- colnames(cov_mat)
  denoised_cov
}

.recursive_bisect <- function(cov_mat, sort_idx) {
  n <- length(sort_idx); nms <- colnames(cov_mat)
  if (n == 1L) return(setNames(1.0, nms[sort_idx]))
  mid <- floor(n / 2)
  left <- sort_idx[1:mid]; right <- sort_idx[(mid + 1):n]
  w_left <- .recursive_bisect(cov_mat, left)
  w_right <- .recursive_bisect(cov_mat, right)
  nl <- names(w_left); nr <- names(w_right)
  var_left  <- as.numeric(t(w_left) %*% cov_mat[nl, nl, drop = FALSE] %*% w_left)
  var_right <- as.numeric(t(w_right) %*% cov_mat[nr, nr, drop = FALSE] %*% w_right)
  total_var <- var_left + var_right
  alpha <- if (is.na(total_var) || total_var < 1e-16) 0.5 else 1 - var_left / total_var
  c(w_left * alpha, w_right * (1 - alpha))
}

compute_hrp_weights <- function(ret_matrix, use_gerber = TRUE, use_rmt = TRUE) {
  n_col <- ncol(ret_matrix); n_row <- nrow(ret_matrix)
  ew_fallback <- setNames(rep(1 / n_col, n_col), colnames(ret_matrix))
  if (n_col < 2L) return(setNames(1.0, colnames(ret_matrix)))
  cov_mat <- cov(ret_matrix, use = "pairwise.complete.obs")
  if (any(is.na(cov_mat))) return(ew_fallback)
  if (use_gerber) {
    cor_mat <- tryCatch(gerber_cor(ret_matrix, threshold = 0.5), error = function(e) NULL)
    if (is.null(cor_mat)) cor_mat <- cor(ret_matrix, use = "pairwise.complete.obs")
  } else {
    cor_mat <- cor(ret_matrix, use = "pairwise.complete.obs")
  }
  if (any(is.na(cor_mat))) { cor_mat[is.na(cor_mat)] <- 0; diag(cor_mat) <- 1 }
  if (use_rmt && n_row > n_col)
    cov_mat <- tryCatch(rmt_denoise_cov(cov_mat, T_obs = n_row, N_assets = n_col),
                        error = function(e) cov_mat)
  cor_clamped <- pmin(pmax(cor_mat, -1), 1)
  dist_mat <- sqrt(0.5 * (1 - cor_clamped))
  dist_mat[is.na(dist_mat)] <- 1; diag(dist_mat) <- 0
  hc <- tryCatch(hclust(as.dist(dist_mat), method = "single"), error = function(e) NULL)
  if (is.null(hc)) return(ew_fallback)
  weights <- tryCatch(.recursive_bisect(cov_mat, hc$order), error = function(e) NULL)
  if (is.null(weights)) return(ew_fallback)
  w_sum <- sum(weights)
  if (is.na(w_sum) || w_sum < 1e-10) return(ew_fallback)
  weights / w_sum
}

# ═══════════════════════════════════════════════════════════════════
# 1. Load RAWDATA
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)

RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]
BM_DT   <- BM_DT[Date >= ANALYSIS_START_DATE]

drop_cols <- intersect(c("Open","High","Low","source","Size","Market"), names(RAWDATA))
if (length(drop_cols) > 0) RAWDATA[, (drop_cols) := NULL]

if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  univ_dt <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe.parquet")))
  univ_dt[, Date := as.Date(Date)]; setorder(univ_dt, Ticker, -Date)
  ticker_info <- univ_dt[, .(Name = Name[1], Sector = Sector[1]), by = Ticker]
  if (!"Name" %in% names(RAWDATA))
    RAWDATA <- merge(RAWDATA, ticker_info[, .(Ticker, Name)], by = "Ticker", all.x = TRUE)
  if (!"Sector" %in% names(RAWDATA))
    RAWDATA <- merge(RAWDATA, ticker_info[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
  rm(univ_dt, ticker_info)
}
gc(verbose = FALSE)

RAWDATA[, YM := format(Date, "%Y-%m")]
sig_dates_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setorder(sig_dates_dt, sig_date)
sig_dates_dt <- sig_dates_dt[sig_date >= SIGNAL_START_DATE]
SIG_DATES <- sig_dates_dt$sig_date

setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, TradVal := NULL]
RAWDATA[, Ret_abs := abs(Ret)]
RAWDATA[, MAX21d_raw := {
  ra <- Ret_abs; n <- length(ra)
  if (n < 21L) cummax(fifelse(is.na(ra), -Inf, ra))
  else frollapply(ra, n = 21L, FUN = max, fill = NA, align = "right")
}, by = Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, c("Ret_abs", "MAX21d_raw") := NULL]

SIG_SNAP <- RAWDATA[Date %in% SIG_DATES & !is.na(Close), .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d", "MAX21d", "YM") := NULL]
setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

# ═══════════════════════════════════════════════════════════════════
# 2. Load Consensus
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Loading Consensus parquets...\n")
load_cons <- function(fname) {
  dt <- as.data.table(read_parquet(file.path(CONS_DIR, fname)))
  dt[, Date := as.Date(Date)]; dt <- dt[Date >= ANALYSIS_START_DATE]
  setkey(dt, Ticker, Date); cat(sprintf("  > %s: %s rows\n", fname, format(nrow(dt), big.mark=",")))
  dt
}
SUE_DT   <- load_cons("sue.parquet")
ESBR_DT  <- load_cons("esbr.parquet")
EPS1M_DT <- load_cons("eps_chg_1m.parquet")
COV_DT   <- load_cons("coverage.parquet")
TP_DT    <- load_cons("target_price.parquet")

# ═══════════════════════════════════════════════════════════════════
# 3. C19 Signals (월간, 동일 구성)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Building C19 signals...\n")
z_safe <- function(x) {
  n_valid <- sum(!is.na(x))
  if (n_valid < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (x - mu) / s
}
FACTORS_list <- vector("list", length(SIG_DATES))
for (i in seq_along(SIG_DATES)) {
  sd <- SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) next
  max21_q80 <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= max21_q80]
  if (nrow(univ) < 30L) next
  probe <- data.table(Ticker = univ$Ticker, Date = sd); setkey(probe, Ticker, Date)
  sue_j   <- SUE_DT[probe,   roll = 7L, nomatch = NA][, .(Ticker, sue)]
  esbr_j  <- ESBR_DT[probe,  roll = 7L, nomatch = NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, eps_chg_1m)]
  cov_j   <- COV_DT[probe,   roll = 7L, nomatch = NA][, .(Ticker, coverage)]
  tp_j    <- TP_DT[probe,    roll = 7L, nomatch = NA][, .(Ticker, target_price)]
  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker, Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]
  if (nrow(sig) < 20L) next
  sig[, TP_Gap := (target_price - Close) / Close]
  sig[, z_sue := z_safe(sue)]; sig[, z_esbr := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]; sig[, z_tpgap := z_safe(TP_Gap)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if (nrow(sig) < 20L) next
  sig[, C19 := (z_sue + z_esbr + z_eps1m + z_tpgap) / 4]
  setorder(sig, -C19)
  FACTORS_list[[i]] <- data.table(Date = sd, Ticker = head(sig, N_HOLD)$Ticker, Score = head(sig, N_HOLD)$C19)
}
FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
cat(sprintf("[Step 3] FACTORS: %d rows | %d months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, FACTORS_list, SIG_SNAP)
gc(verbose = FALSE)

# ═══════════════════════════════════════════════════════════════════
# 4. HRP Weights (120d lookback, t-1 lag)
# ═══════════════════════════════════════════════════════════════════
cat(sprintf("\n[Step 4] Computing HRP weights (%dd lookback)...\n", HRP_LOOKBACK))
FACTORS_hrp <- copy(FACTORS)
FACTORS_hrp[, Weight_hrp := NA_real_]
hrp_success <- 0L; hrp_fallback <- 0L

for (sd in unique(FACTORS_hrp$Date)) {
  tickers <- FACTORS_hrp[Date == sd, Ticker]
  all_dates <- sort(unique(RAWDATA[Date < sd, Date]))
  if (length(all_dates) < HRP_LOOKBACK) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]
    hrp_fallback <- hrp_fallback + 1L; next
  }
  lookback_dates <- tail(all_dates, HRP_LOOKBACK)
  ret_sub  <- RAWDATA[Date %in% lookback_dates & Ticker %in% tickers, .(Date, Ticker, Ret)]
  ret_wide <- dcast(ret_sub, Date ~ Ticker, value.var = "Ret")
  ret_mat  <- as.matrix(ret_wide[, -1, with = FALSE])
  colnames(ret_mat) <- names(ret_wide)[-1]
  # 120d 기준: 최소 60 obs 요구
  valid_cols <- colSums(!is.na(ret_mat)) >= 60L
  if (sum(valid_cols) < 2L) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]
    hrp_fallback <- hrp_fallback + 1L; next
  }
  ret_mat_clean <- ret_mat[, valid_cols, drop = FALSE]
  ret_mat_clean[is.na(ret_mat_clean)] <- 0
  hrp_w <- tryCatch(compute_hrp_weights(ret_mat_clean), error = function(e) NULL)
  if (is.null(hrp_w)) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]
    hrp_fallback <- hrp_fallback + 1L; next
  }
  w_vec <- rep(0, length(tickers)); names(w_vec) <- tickers
  matched <- intersect(names(hrp_w), tickers)
  w_vec[matched] <- hrp_w[matched]
  unmatched <- setdiff(tickers, matched)
  if (length(unmatched) > 0) w_vec[unmatched] <- 0.01 / length(unmatched)
  w_vec <- w_vec / sum(w_vec)
  for (tk in tickers) FACTORS_hrp[Date == sd & Ticker == tk, Weight_hrp := w_vec[tk]]
  hrp_success <- hrp_success + 1L
}
cat(sprintf("[Step 4] HRP: %d success, %d fallback\n", hrp_success, hrp_fallback))

hrp_weight_lookup <- list()
for (d in unique(FACTORS_hrp$Date)) {
  month_f <- FACTORS_hrp[Date == d]; w <- month_f$Weight_hrp
  if (all(is.na(w))) w <- rep(1 / nrow(month_f), nrow(month_f))
  hrp_weight_lookup[[as.character(d)]] <- setNames(w, month_f$Ticker)
}

orig_ivol <- calc_ivol_weights
calc_ivol_weights <<- function(tickers, ret_dt, n_days = 60, max_w = 0.15) {
  for (d in names(hrp_weight_lookup)) {
    hw <- hrp_weight_lookup[[d]]
    if (all(tickers %in% names(hw))) { w <- hw[tickers]; return(as.numeric(w / sum(w))) }
  }
  rep(1 / length(tickers), length(tickers))
}

sim_base <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS,
  n_holdings    = N_HOLD,
  weight_method = "ivol",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 35L, entry_n = 20L)
)
calc_ivol_weights <<- orig_ivol

perf_base <- summarise_perf(sim_base$strategy_xts, "M20_HRP120d_Base")
to_base   <- calc_turnover(sim_base$PORTFOLIO_LOG, sim_base$DAILY_NAV_DT)

# ═══════════════════════════════════════════════════════════════════
# 5. Regime Overlay
# ═══════════════════════════════════════════════════════════════════
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME <- build_daily_regime(use_cache = TRUE); setkey(REGIME, Date)

inv_path <- file.path(CACHE_DIR, "kodex_inverse_114800.csv")
INV_DT <- if (file.exists(inv_path)) {
  dt <- fread(inv_path); dt[, Date := as.Date(Date)]; setkey(dt, Date); dt
} else NULL

nav_dt <- copy(sim_base$DAILY_NAV_DT); setkey(nav_dt, Date)
nav_dt <- REGIME[, .(Date, MRS, n_axes_firing)][nav_dt, roll = TRUE]
nav_dt <- merge(nav_dt, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
if (!is.null(INV_DT)) {
  nav_dt <- merge(nav_dt, INV_DT[, .(Date, Ret_Inv)], by = "Date", all.x = TRUE)
  nav_dt[is.na(Ret_Inv), Ret_Inv := -BM_Ret]
} else nav_dt[, Ret_Inv := -BM_Ret]
nav_dt[is.na(Ret_Inv), Ret_Inv := 0]
nav_dt[is.na(MRS), MRS := 0]; nav_dt[is.na(n_axes_firing), n_axes_firing := 0L]
# PIT NOTE: MRS is already t-1 lagged in regime_engine_daily.R (Step 5, line 339).
# MRS[t] = MRS_raw[t-1]. No additional shift() needed — double-lag would create t-2 error.
nav_dt[, crisis_flag := fifelse(MRS >= 60 & n_axes_firing >= 5, 1L, 0L)]
nav_dt[, crisis_consec := { out <- integer(.N); cnt <- 0L
  for (j in seq_len(.N)) { if (crisis_flag[j] == 1L) cnt <- cnt + 1L else cnt <- 0L; out[j] <- cnt }; out }]
nav_dt[, Layer := fifelse(crisis_consec >= 3L, 3L, fifelse(MRS >= 30, 2L, 1L))]
nav_dt[, Ret_overlay := fcase(
  Layer == 1L, Strategy_Ret,
  Layer == 2L, { f_w <- pmax(0.5, 1.0 - (MRS - 30) / 60); f_w * Strategy_Ret + (1 - f_w) * 0 },
  Layer == 3L, 0.50 * Strategy_Ret + 0.20 * Ret_Inv + 0.30 * 0
)]
nav_dt[, NAV_overlay := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_overlay)]
overlay_xts <- xts(nav_dt$Ret_overlay, order.by = nav_dt$Date)
names(overlay_xts) <- "Strategy"

# ═══════════════════════════════════════════════════════════════════
# 6. Summary & Save
# ═══════════════════════════════════════════════════════════════════
perf_overlay <- summarise_perf(overlay_xts, "M20_HRP120d_Overlay")
perf_bm2     <- summarise_perf(sim_base$bm_xts, "KOSPI200")

cat("\n================================================================\n")
cat("   STR_1631 v5 M20: HRP 120d Lookback (M_B1)\n")
cat("================================================================\n")
cat("--- Base ---\n"); print(perf_base)
cat("--- Overlay ---\n"); print(perf_overlay)
cat("--- BM ---\n"); print(perf_bm2)
cat(sprintf("Turnover: %.1f%% | HRP success: %d, fallback: %d\n",
            to_base, hrp_success, hrp_fallback))

source(file.path(FUNC_PATH, "hurdle_gate.R"))
sim_ov_h <- list(strategy_xts=overlay_xts, bm_xts=sim_base$bm_xts,
  DAILY_NAV_DT=nav_dt[,.(Date,NAV=NAV_overlay,Strategy_Ret=Ret_overlay)], PORTFOLIO_LOG=sim_base$PORTFOLIO_LOG)
hurdle_res <- run_hurdle_gate(sim_ov_h, FACTORS, strategy_name="STR_1631_v5_M20_hrp120d", output_dir=OUT_DIR)
cat("--- Hurdle ---\n"); print(hurdle_res[c("pass","score")])

generate_charts(list(strategy_xts = overlay_xts, bm_xts = sim_base$bm_xts,
                     DAILY_NAV_DT = nav_dt[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)]),
                output_dir = OUT_DIR, strategy_name = "STR_1631 v5 M20 - HRP 120d")

write_json(list(
  strategy = "STR_1631_v5_M20_hrp120d", mutation = "M_B1: HRP lookback 60d -> 120d",
  hrp_lookback = HRP_LOOKBACK, base = as.list(perf_base),
  overlay = as.list(perf_overlay), benchmark = as.list(perf_bm2),
  turnover = to_base, hurdle_pass = hurdle_res$pass, hurdle_score = hurdle_res$score,
  hrp_stats = list(success = hrp_success, fallback = hrp_fallback),
  run_time = as.numeric(difftime(Sys.time(), t0, units = "secs"))
), file.path(OUT_DIR, "performance.json"), pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[DONE] M20 complete in %.1f sec\n", difftime(Sys.time(), t0, units = "secs")))
