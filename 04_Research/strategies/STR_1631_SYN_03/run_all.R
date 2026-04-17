cat("=== STR_1631 SYN_03: Score Tilt + HRP 120d + Bimonthly (M23 x M20 x M19) ===\n")
## 핵심 아이디어: 3축 결합 — Weight(Score Tilt) x Weight(HRP 120d) x Structural(격월)
## M23: 0.6*HRP + 0.4*Score(t-1 frozen) hybrid weighting
## M20: HRP lookback 60d -> 120d (N/T 0.33->0.17, RMT 정확도 개선)
## M19: 격월 리밸런싱 (TO ~50% 감소)
## 기대: SR ~1.08 + TO ~310% + MDD ~34%
## C2 준수: Score = t-1 frozen
## Ref: Ledoit & Wolf(2004) + Novy-Marx & Velikov(2016) + Briere & Szafarz(2021)
## 기반: STR_1631 v5 M11 (Gerber + RMT + HRP)

t0 <- Sys.time()

# ===================================================================
# 0. Environment Setup
# ===================================================================
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
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(tidyr); library(lubridate); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

LIQ_THRESHOLD  <- 2e8
N_HOLD         <- 20L
MAX21D_EXCL    <- 0.80
HRP_LOOKBACK   <- 120L     # M20: 60d -> 120d
REBAL_MONTHS   <- 2L       # M19: bimonthly
HRP_TILT_W     <- 0.6      # M23: HRP proportion
SCORE_TILT_W   <- 0.4      # M23: Score proportion

cat(sprintf("[SYN_03] 3-axis: %.1f*HRP(120d) + %.1f*Score | Bimonthly\n",
            HRP_TILT_W, SCORE_TILT_W))

# ===================================================================
# Gerber + RMT + HRP (M11 동일)
# ===================================================================
gerber_cor <- function(ret_matrix, threshold = 0.5) {
  n <- ncol(ret_matrix); mat <- matrix(0, n, n)
  med_abs <- apply(ret_matrix, 2, function(x) median(abs(x), na.rm = TRUE))
  med_abs <- ifelse(med_abs < 1e-12, apply(ret_matrix, 2, sd, na.rm = TRUE), med_abs)
  for (i in seq_len(n)) {
    ti <- threshold * med_abs[i]; hi <- ret_matrix[, i] > ti; li <- ret_matrix[, i] < -ti
    for (j in i:n) {
      if (i == j) { mat[i, j] <- 1; next }
      tj <- threshold * med_abs[j]; hj <- ret_matrix[, j] > tj; lj <- ret_matrix[, j] < -tj
      co <- sum((hi & hj) | (li & lj), na.rm = TRUE)
      di <- sum((hi & lj) | (li & hj), na.rm = TRUE)
      tot <- co + di; val <- if (tot > 0L) (co - di) / tot else 0
      mat[i, j] <- val; mat[j, i] <- val
    }
  }
  diag(mat) <- 1; colnames(mat) <- rownames(mat) <- colnames(ret_matrix); mat
}
rmt_denoise_cov <- function(cov_mat, T_obs, N_assets) {
  if (N_assets < 2L || T_obs < N_assets) return(cov_mat)
  vol <- sqrt(pmax(diag(cov_mat), 1e-16)); cor_mat <- cov_mat / (vol %o% vol)
  cor_mat <- pmin(pmax(cor_mat, -1), 1); diag(cor_mat) <- 1
  eig <- tryCatch(eigen(cor_mat, symmetric = TRUE), error = function(e) NULL)
  if (is.null(eig)) return(cov_mat)
  vals <- eig$values; vecs <- eig$vectors; q <- T_obs / N_assets
  lp <- (1 + 1 / sqrt(q))^2; ni <- vals <= lp
  if (any(ni) && !all(ni)) vals[ni] <- mean(vals[ni]); vals <- pmax(vals, 1e-8)
  dc <- vecs %*% diag(vals) %*% t(vecs); dd <- sqrt(pmax(diag(dc), 1e-16))
  dc <- dc / (dd %o% dd); diag(dc) <- 1; dcov <- dc * (vol %o% vol)
  colnames(dcov) <- rownames(dcov) <- colnames(cov_mat); dcov
}
.recursive_bisect <- function(cov_mat, sort_idx) {
  n <- length(sort_idx); nms <- colnames(cov_mat)
  if (n == 1L) return(setNames(1.0, nms[sort_idx]))
  mid <- floor(n / 2); left <- sort_idx[1:mid]; right <- sort_idx[(mid + 1):n]
  wl <- .recursive_bisect(cov_mat, left); wr <- .recursive_bisect(cov_mat, right)
  nl <- names(wl); nr <- names(wr)
  vl <- as.numeric(t(wl) %*% cov_mat[nl, nl, drop = FALSE] %*% wl)
  vr <- as.numeric(t(wr) %*% cov_mat[nr, nr, drop = FALSE] %*% wr)
  tv <- vl + vr; a <- if (is.na(tv) || tv < 1e-16) 0.5 else 1 - vl / tv
  c(wl * a, wr * (1 - a))
}
compute_hrp_weights <- function(ret_matrix, use_gerber = TRUE, use_rmt = TRUE) {
  nc <- ncol(ret_matrix); nr <- nrow(ret_matrix)
  ew <- setNames(rep(1 / nc, nc), colnames(ret_matrix))
  if (nc < 2L) return(setNames(1.0, colnames(ret_matrix)))
  cm <- cov(ret_matrix, use = "pairwise.complete.obs"); if (any(is.na(cm))) return(ew)
  if (use_gerber) {
    cor_mat <- tryCatch(gerber_cor(ret_matrix, 0.5), error = function(e) NULL)
    if (is.null(cor_mat)) cor_mat <- cor(ret_matrix, use = "pairwise.complete.obs")
  } else cor_mat <- cor(ret_matrix, use = "pairwise.complete.obs")
  if (any(is.na(cor_mat))) { cor_mat[is.na(cor_mat)] <- 0; diag(cor_mat) <- 1 }
  if (use_rmt && nr > nc) cm <- tryCatch(rmt_denoise_cov(cm, nr, nc), error = function(e) cm)
  cc <- pmin(pmax(cor_mat, -1), 1); dm <- sqrt(0.5 * (1 - cc)); dm[is.na(dm)] <- 1; diag(dm) <- 0
  hc <- tryCatch(hclust(as.dist(dm), method = "single"), error = function(e) NULL)
  if (is.null(hc)) return(ew)
  w <- tryCatch(.recursive_bisect(cm, hc$order), error = function(e) NULL)
  if (is.null(w)) return(ew); ws <- sum(w); if (is.na(ws) || ws < 1e-10) return(ew); w / ws
}

# ===================================================================
# 1. Load RAWDATA
# ===================================================================
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]; BM_DT <- BM_DT[Date >= ANALYSIS_START_DATE]
dc <- intersect(c("Open", "High", "Low", "source", "Size", "Market"), names(RAWDATA))
if (length(dc) > 0) RAWDATA[, (dc) := NULL]
if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  ud <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe.parquet"))); ud[, Date := as.Date(Date)]
  setorder(ud, Ticker, -Date); ti <- ud[, .(Name = Name[1], Sector = Sector[1]), by = Ticker]
  if (!"Name" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Name)], by = "Ticker", all.x = TRUE)
  if (!"Sector" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
  rm(ud, ti)
}
gc(verbose = FALSE)

RAWDATA[, YM := format(Date, "%Y-%m")]
sd_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]; setorder(sd_dt, sig_date)
sd_dt <- sd_dt[sig_date >= SIGNAL_START_DATE]
all_sig_dates <- sd_dt$sig_date

# M19: bimonthly filter
SIG_DATES <- all_sig_dates[seq(1, length(all_sig_dates), by = REBAL_MONTHS)]
cat(sprintf("[Step 1] Bimonthly SIG_DATES: %d (%s ~ %s)\n",
            length(SIG_DATES), min(SIG_DATES), max(SIG_DATES)))

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
RAWDATA[, c("LIQ_20d", "MAX21d", "YM") := NULL]; setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

# ===================================================================
# 2. Load Consensus
# ===================================================================
cat("\n[Step 2] Loading Consensus...\n")
lc <- function(f) {
  dt <- as.data.table(read_parquet(file.path(CONS_DIR, f))); dt[, Date := as.Date(Date)]
  dt <- dt[Date >= ANALYSIS_START_DATE]; setkey(dt, Ticker, Date)
  cat(sprintf("  > %s: %s rows\n", f, format(nrow(dt), big.mark = ","))); dt
}
SUE_DT   <- lc("sue.parquet")
ESBR_DT  <- lc("esbr.parquet")
EPS1M_DT <- lc("eps_chg_1m.parquet")
COV_DT   <- lc("coverage.parquet")
TP_DT    <- lc("target_price.parquet")

# ===================================================================
# 3. Build C19 Signals (M11 동일 — 4F with TP_Gap, bimonthly)
# ===================================================================
cat("\n[Step 3] Building bimonthly C19 signals...\n")
z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

FACTORS_list <- vector("list", length(SIG_DATES))
for (i in seq_along(SIG_DATES)) {
  sd <- SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) next
  mq <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= mq]; if (nrow(univ) < 30L) next
  probe <- data.table(Ticker = univ$Ticker, Date = sd); setkey(probe, Ticker, Date)
  sue_j   <- SUE_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, sue)]
  esbr_j  <- ESBR_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, eps_chg_1m)]
  cov_j   <- COV_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, coverage)]
  tp_j    <- TP_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, target_price)]
  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker, Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]; if (nrow(sig) < 20L) next
  sig[, TP_Gap := (target_price - Close) / Close]
  sig[, z_sue := z_safe(sue)]; sig[, z_esbr := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]; sig[, z_tpgap := z_safe(TP_Gap)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if (nrow(sig) < 20L) next
  sig[, C19 := (z_sue + z_esbr + z_eps1m + z_tpgap) / 4]
  setorder(sig, -C19); top <- head(sig, N_HOLD)
  FACTORS_list[[i]] <- data.table(Date = sd, Ticker = top$Ticker, Score = top$C19)
}
FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
cat(sprintf("[Step 3] FACTORS: %d rows | %d bimonthly months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, FACTORS_list, SIG_SNAP); gc(verbose = FALSE)

# ===================================================================
# 4. HRP 120d + Score Tilt Hybrid Weights (M20 lookback + M23 tilt)
# C2: Score = t-1 frozen
# M20: valid_cols threshold = 60L (120d lookback needs 60+ obs)
# ===================================================================
cat("\n[Step 4] Computing HRP 120d + Score Tilt Hybrid weights (bimonthly)...\n")
FACTORS_hrp <- copy(FACTORS); FACTORS_hrp[, Weight_hrp := NA_real_]
hrp_success <- 0L; hrp_fallback <- 0L

all_sig_dates_sorted <- sort(unique(FACTORS$Date))
prev_score_map <- list()
for (k in seq_along(all_sig_dates_sorted)) {
  d <- all_sig_dates_sorted[k]
  if (k == 1L) { prev_score_map[[as.character(d)]] <- NULL
  } else {
    prev_d <- all_sig_dates_sorted[k - 1]
    prev_score_map[[as.character(d)]] <- FACTORS[Date == prev_d, .(Ticker, Score)]
  }
}

for (sd in all_sig_dates_sorted) {
  tickers <- FACTORS_hrp[Date == sd, Ticker]
  ad <- sort(unique(RAWDATA[Date < sd, Date]))
  if (length(ad) < HRP_LOOKBACK) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]; hrp_fallback <- hrp_fallback + 1L; next
  }
  ld <- tail(ad, HRP_LOOKBACK)  # M20: 120 trading days
  rs <- RAWDATA[Date %in% ld & Ticker %in% tickers, .(Date, Ticker, Ret)]
  rw <- dcast(rs, Date ~ Ticker, value.var = "Ret")
  rm_ <- as.matrix(rw[, -1, with = FALSE]); colnames(rm_) <- names(rw)[-1]
  vc <- colSums(!is.na(rm_)) >= 60L  # M20: 120d lookback needs 60+ valid obs
  if (sum(vc) < 2L) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]; hrp_fallback <- hrp_fallback + 1L; next
  }
  rc <- rm_[, vc, drop = FALSE]; rc[is.na(rc)] <- 0
  hw <- tryCatch(compute_hrp_weights(rc), error = function(e) NULL)
  if (is.null(hw)) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]; hrp_fallback <- hrp_fallback + 1L; next
  }

  # HRP base weights
  hrp_vec <- rep(0, length(tickers)); names(hrp_vec) <- tickers
  mt <- intersect(names(hw), tickers); hrp_vec[mt] <- hw[mt]
  um <- setdiff(tickers, mt); if (length(um) > 0) hrp_vec[um] <- 0.01 / length(um)
  hrp_vec <- hrp_vec / sum(hrp_vec)

  # C2: t-1 Score (이전 리밸런싱일 frozen)
  prev_scores <- prev_score_map[[as.character(sd)]]
  if (!is.null(prev_scores) && nrow(prev_scores) > 0) {
    matched_prev <- prev_scores[Ticker %in% tickers]
    if (nrow(matched_prev) >= 2L) {
      sc_vec <- rep(0, length(tickers)); names(sc_vec) <- tickers
      sc_min <- min(matched_prev$Score, na.rm = TRUE)
      matched_prev[, Score_pos := Score - sc_min + 0.01]
      sc_matched <- matched_prev$Score_pos; names(sc_matched) <- matched_prev$Ticker
      sc_vec[names(sc_matched)] <- sc_matched
      sc_vec[sc_vec == 0] <- mean(sc_matched, na.rm = TRUE)
      sc_vec <- sc_vec / sum(sc_vec)
      final_w <- HRP_TILT_W * hrp_vec + SCORE_TILT_W * sc_vec
    } else { final_w <- hrp_vec }
  } else { final_w <- hrp_vec }
  final_w <- final_w / sum(final_w)
  for (tk in tickers) FACTORS_hrp[Date == sd & Ticker == tk, Weight_hrp := final_w[tk]]
  hrp_success <- hrp_success + 1L
}
cat(sprintf("[Step 4] HRP 120d + Score Tilt: %d success, %d EW fallback\n", hrp_success, hrp_fallback))

hwl <- list()
for (d in unique(FACTORS_hrp$Date)) {
  mf <- FACTORS_hrp[Date == d]; w <- mf$Weight_hrp
  if (all(is.na(w))) w <- rep(1 / nrow(mf), nrow(mf))
  hwl[[as.character(d)]] <- setNames(w, mf$Ticker)
}
oi <- calc_ivol_weights
calc_ivol_weights <<- function(tickers, ret_dt, n_days = 60, max_w = 0.15) {
  for (d in names(hwl)) {
    hw <- hwl[[d]]; if (all(tickers %in% names(hw))) { w <- hw[tickers]; return(as.numeric(w / sum(w))) }
  }
  rep(1 / length(tickers), length(tickers))
}
sim_base <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS, n_holdings = N_HOLD,
  weight_method = "ivol", commission = 0.0015, buffer_zone = list(keep_n = 35L, entry_n = 20L))
calc_ivol_weights <<- oi
perf_base <- summarise_perf(sim_base$strategy_xts, "SYN03_Base")
to_base <- calc_turnover(sim_base$PORTFOLIO_LOG, sim_base$DAILY_NAV_DT)

# ===================================================================
# 5. Regime Overlay (3-Layer, M11 동일)
# ===================================================================
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME <- build_daily_regime(use_cache = TRUE); setkey(REGIME, Date)
ip <- file.path(CACHE_DIR, "kodex_inverse_114800.csv")
ID <- if (file.exists(ip)) { dt <- fread(ip); dt[, Date := as.Date(Date)]; setkey(dt, Date); dt } else NULL
nd <- copy(sim_base$DAILY_NAV_DT); setkey(nd, Date)
nd <- REGIME[, .(Date, MRS, n_axes_firing)][nd, roll = TRUE]
nd <- merge(nd, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
if (!is.null(ID)) {
  nd <- merge(nd, ID[, .(Date, Ret_Inv)], by = "Date", all.x = TRUE)
  nd[is.na(Ret_Inv), Ret_Inv := -BM_Ret]
} else nd[, Ret_Inv := -BM_Ret]
nd[is.na(Ret_Inv), Ret_Inv := 0]; nd[is.na(MRS), MRS := 0]; nd[is.na(n_axes_firing), n_axes_firing := 0L]
# PIT NOTE: MRS is already t-1 lagged in regime_engine_daily.R (Step 5, line 339).
# MRS[t] = MRS_raw[t-1]. No additional shift() needed — double-lag would create t-2 error.
nd[, crisis_flag := fifelse(MRS >= 60 & n_axes_firing >= 5, 1L, 0L)]
nd[, crisis_consec := {
  out <- integer(.N); cnt <- 0L
  for (j in seq_len(.N)) { if (nd$crisis_flag[j] == 1L) cnt <- cnt + 1L else cnt <- 0L; out[j] <- cnt }
  out
}]
nd[, Layer := fifelse(crisis_consec >= 3L, 3L, fifelse(MRS >= 30, 2L, 1L))]
nd[, Ret_overlay := fcase(
  Layer == 1L, Strategy_Ret,
  Layer == 2L, { fw <- pmax(0.5, 1.0 - (MRS - 30) / 60); fw * Strategy_Ret + (1 - fw) * 0 },
  Layer == 3L, 0.50 * Strategy_Ret + 0.20 * Ret_Inv + 0.30 * 0
)]
nd[, NAV_overlay := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_overlay)]
ov_xts <- xts(nd$Ret_overlay, order.by = nd$Date); names(ov_xts) <- "Strategy"

# ===================================================================
# 6. Summary & Save
# ===================================================================
po <- summarise_perf(ov_xts, "SYN03_Overlay"); pb <- summarise_perf(sim_base$bm_xts, "KOSPI200")
cat("\n================================================================\n")
cat("   STR_1631 SYN_03: Score Tilt + HRP 120d + Bimonthly (M23 x M20 x M19)\n")
cat("================================================================\n")
cat("--- Base ---\n"); print(perf_base)
cat("--- Overlay ---\n"); print(po)
cat("--- BM ---\n"); print(pb)
cat(sprintf("Turnover: %.1f%% | HRP_w: %.1f | Score_w: %.1f | HRP_LB: %dd | Bimonthly: %dM\n",
            to_base, HRP_TILT_W, SCORE_TILT_W, HRP_LOOKBACK, REBAL_MONTHS))

source(file.path(FUNC_PATH, "hurdle_gate.R"))
sim_ov_h <- list(strategy_xts = ov_xts, bm_xts = sim_base$bm_xts,
  DAILY_NAV_DT = nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)],
  PORTFOLIO_LOG = sim_base$PORTFOLIO_LOG)
hr <- run_hurdle_gate(sim_ov_h, FACTORS,
  strategy_name = "STR_1631_SYN_03_scoretilt_hrp120d_bimonthly", output_dir = OUT_DIR)
cat("--- Hurdle ---\n"); print(hr[c("pass", "score")])

generate_charts(list(strategy_xts = ov_xts, bm_xts = sim_base$bm_xts,
  DAILY_NAV_DT = nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)]),
  output_dir = OUT_DIR, strategy_name = "STR_1631 SYN_03 - ScoreTilt+HRP120d+Bimonthly")

write_json(list(
  strategy = "STR_1631_SYN_03_scoretilt_hrp120d_bimonthly",
  synthesis = "M23(Score Tilt) + M20(HRP 120d) + M19(Bimonthly)",
  components = list("M23_score_tilt", "M20_hrp120d", "M19_bimonthly"),
  axes = list("weight", "weight", "structural"),
  hrp_tilt_w = HRP_TILT_W, score_tilt_w = SCORE_TILT_W,
  hrp_lookback = HRP_LOOKBACK, rebal_months = REBAL_MONTHS,
  pit_notes = list(C2 = "Score is t-1 frozen (prev rebal signal)"),
  base = as.list(perf_base), overlay = as.list(po), benchmark = as.list(pb),
  turnover = to_base, hurdle_pass = hr$pass, hurdle_score = hr$score,
  run_time = as.numeric(difftime(Sys.time(), t0, units = "secs"))
), file.path(OUT_DIR, "performance.json"), pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[DONE] SYN_03 complete in %.1f sec\n", difftime(Sys.time(), t0, units = "secs")))
