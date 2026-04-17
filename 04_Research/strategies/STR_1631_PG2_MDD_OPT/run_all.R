cat("=== STR_1631 PG2 MDD Optimization: Portfolio Structure Comparison ===\n")
## 핵심 아이디어: 팩터가 아닌 포트폴리오 구조로 MDD 34% → 25% 달성
## SYN_05 base를 재현 후 4가지 MDD 감소 방안 비교:
##   V1: Regime overlay 강화 (Caution threshold 25, Crisis inverse 40%)
##   V2: Vol Targeting 15% (expanding vol, t-1 lag, C9 준수)
##   V3: DD Brake 5/15 (base SR 1.248 > 1.0 → L-728 충족)
##   V4: V1+V2+V3 통합
## PIT: C9 (VT/DD t-1 lag), C5 (overlay t-1), regime already t-1 lagged
## Ref: Moskowitz et al.(2012) vol targeting, Grossman & Zhou(1993) CPPI, L-728, L-729

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

# ===================================================================
# 1. Load SYN_05 base simulation data
# ===================================================================
cat("\n[Step 1] Running SYN_05 base to get daily NAV...\n")

SYN05_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1631_SYN_05")

# We need to re-run SYN_05's base simulation to get DAILY_NAV_DT
# Source SYN_05's run_all.R up to step 4 (before overlay)
# Instead, we'll replicate the essential parts inline

source(file.path(FUNC_PATH, "backtest_harness.R"))

LIQ_THRESHOLD  <- 2e8
N_HOLD         <- 20L
MAX21D_EXCL    <- 0.80
HRP_LOOKBACK   <- 60L
REBAL_MONTHS   <- 2L
HRP_TILT_W     <- 0.6
SCORE_TILT_W   <- 0.4
IC_MIN_MONTHS  <- 12L
CONS_DIR       <- file.path(CACHE_DIR, "consensus")

# ── Load RAWDATA ──
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
ALL_SIG_DATES <- sd_dt$sig_date
SIG_DATES <- ALL_SIG_DATES[seq(1, length(ALL_SIG_DATES), by = REBAL_MONTHS)]

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

SIG_SNAP <- RAWDATA[Date %in% ALL_SIG_DATES & !is.na(Close), .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d", "MAX21d", "YM") := NULL]; setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

# ── Load Consensus ──
cat("[Step 2] Loading Consensus...\n")
lc <- function(f) {
  dt <- as.data.table(read_parquet(file.path(CONS_DIR, f))); dt[, Date := as.Date(Date)]
  dt <- dt[Date >= ANALYSIS_START_DATE]; setkey(dt, Ticker, Date); dt
}
SUE_DT <- lc("sue.parquet"); ESBR_DT <- lc("esbr.parquet")
EPS1M_DT <- lc("eps_chg_1m.parquet"); COV_DT <- lc("coverage.parquet")
TP_DT <- lc("target_price.parquet")

# ── IC + Factors ──
cat("[Step 3] Computing IC-weighted factors...\n")
z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

fwd_map <- list()
for (i in seq_along(ALL_SIG_DATES)) {
  sd <- ALL_SIG_DATES[i]
  if (i < length(ALL_SIG_DATES)) {
    next_sd <- ALL_SIG_DATES[i + 1]
    ret_sub <- RAWDATA[Date > sd & Date <= next_sd, .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    fwd_map[[as.character(sd)]] <- ret_sub
  }
}

raw_scores_list <- vector("list", length(ALL_SIG_DATES))
for (i in seq_along(ALL_SIG_DATES)) {
  sd <- ALL_SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) next
  mq <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= mq]; if (nrow(univ) < 30L) next
  probe <- data.table(Ticker = univ$Ticker, Date = sd); setkey(probe, Ticker, Date)
  sue_j <- SUE_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, sue)]
  esbr_j <- ESBR_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, eps_chg_1m)]
  cov_j <- COV_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, coverage)]
  tp_j <- TP_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, target_price)]
  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker, Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]; if (nrow(sig) < 20L) next
  sig[, TP_Gap := (target_price - Close) / Close]
  sig[, z_sue := z_safe(sue)]; sig[, z_esbr := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]; sig[, z_tpgap := z_safe(TP_Gap)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if (nrow(sig) < 20L) next
  raw_scores_list[[i]] <- data.table(Date = sd, Ticker = sig$Ticker,
    z_sue = sig$z_sue, z_esbr = sig$z_esbr, z_eps1m = sig$z_eps1m, z_tpgap = sig$z_tpgap)
}
RAW_SCORES <- rbindlist(raw_scores_list[!sapply(raw_scores_list, is.null)])

ic_history <- data.table(Date = as.Date(character()), ic_sue = numeric(), ic_esbr = numeric(),
                         ic_eps1m = numeric(), ic_tpgap = numeric())
unique_dates <- sort(unique(RAW_SCORES$Date))
for (i in seq_along(unique_dates)) {
  sd <- unique_dates[i]
  fr <- fwd_map[[as.character(sd)]]; if (is.null(fr)) next
  sc <- RAW_SCORES[Date == sd]; mg <- merge(sc, fr, by = "Ticker")
  if (nrow(mg) < 10L) next
  ic_history <- rbind(ic_history, data.table(Date = sd,
    ic_sue   = fifelse(is.na(cor(mg$z_sue, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_sue, mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_esbr  = fifelse(is.na(cor(mg$z_esbr, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_esbr, mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_eps1m = fifelse(is.na(cor(mg$z_eps1m, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_eps1m, mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_tpgap = fifelse(is.na(cor(mg$z_tpgap, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_tpgap, mg$fwd_ret, method = "spearman", use = "complete.obs"))))
}

FACTORS_list <- vector("list", length(SIG_DATES))
for (i in seq_along(SIG_DATES)) {
  sd <- SIG_DATES[i]
  sc <- RAW_SCORES[Date == sd]; if (nrow(sc) < 20L) next
  past_ic <- ic_history[Date < sd]
  if (nrow(past_ic) < IC_MIN_MONTHS) {
    w_factors <- c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25)
  } else {
    mean_ic <- c(sue = mean(past_ic$ic_sue, na.rm = TRUE), esbr = mean(past_ic$ic_esbr, na.rm = TRUE),
                 eps1m = mean(past_ic$ic_eps1m, na.rm = TRUE), tpgap = mean(past_ic$ic_tpgap, na.rm = TRUE))
    mean_ic <- pmax(mean_ic, 0); ic_sum <- sum(mean_ic)
    w_factors <- if (ic_sum < 1e-8) c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25) else mean_ic / ic_sum
  }
  sc[, C19_icw := w_factors["sue"] * z_sue + w_factors["esbr"] * z_esbr +
                  w_factors["eps1m"] * z_eps1m + w_factors["tpgap"] * z_tpgap]
  setorder(sc, -C19_icw); top <- head(sc, N_HOLD)
  FACTORS_list[[i]] <- data.table(Date = sd, Ticker = top$Ticker, Score = top$C19_icw)
}
FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
cat(sprintf("[Step 3] FACTORS: %d rows | %d months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, RAW_SCORES, FACTORS_list, SIG_SNAP)
gc(verbose = FALSE)

# ── HRP + Score Tilt (identical to SYN_05) ──
cat("[Step 4] HRP + Score Tilt...\n")
# Gerber + RMT + HRP functions
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

FACTORS_hrp <- copy(FACTORS); FACTORS_hrp[, Weight_hrp := NA_real_]
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
    FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]; next
  }
  ld <- tail(ad, HRP_LOOKBACK)
  rs <- RAWDATA[Date %in% ld & Ticker %in% tickers, .(Date, Ticker, Ret)]
  rw <- dcast(rs, Date ~ Ticker, value.var = "Ret")
  rm_ <- as.matrix(rw[, -1, with = FALSE]); colnames(rm_) <- names(rw)[-1]
  vc <- colSums(!is.na(rm_)) >= 30L
  if (sum(vc) < 2L) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]; next
  }
  rc <- rm_[, vc, drop = FALSE]; rc[is.na(rc)] <- 0
  hw <- tryCatch(compute_hrp_weights(rc), error = function(e) NULL)
  if (is.null(hw)) { FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]; next }
  hrp_vec <- rep(0, length(tickers)); names(hrp_vec) <- tickers
  mt <- intersect(names(hw), tickers); hrp_vec[mt] <- hw[mt]
  um <- setdiff(tickers, mt); if (length(um) > 0) hrp_vec[um] <- 0.01 / length(um)
  hrp_vec <- hrp_vec / sum(hrp_vec)
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
}

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

cat("[Step 4] Base simulation complete.\n")

# ===================================================================
# 5. Build daily NAV for overlay experiments
# ===================================================================
cat("\n[Step 5] Loading regime + building daily NAV...\n")
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

# ===================================================================
# 6. VARIANT 0: Original SYN_05 Overlay (baseline)
# ===================================================================
cat("\n[Step 6] V0: Original SYN_05 overlay...\n")
nd[, crisis_flag_v0 := fifelse(MRS >= 60 & n_axes_firing >= 5, 1L, 0L)]
nd[, crisis_consec_v0 := {
  out <- integer(.N); cnt <- 0L
  for (j in seq_len(.N)) { if (nd$crisis_flag_v0[j] == 1L) cnt <- cnt + 1L else cnt <- 0L; out[j] <- cnt }
  out
}]
nd[, Layer_v0 := fifelse(crisis_consec_v0 >= 3L, 3L, fifelse(MRS >= 30, 2L, 1L))]
nd[, Ret_v0 := fcase(
  Layer_v0 == 1L, Strategy_Ret,
  Layer_v0 == 2L, { fw <- pmax(0.5, 1.0 - (MRS - 30) / 60); fw * Strategy_Ret + (1 - fw) * 0 },
  Layer_v0 == 3L, 0.50 * Strategy_Ret + 0.20 * Ret_Inv + 0.30 * 0
)]
nd[, NAV_v0 := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_v0)]

# ===================================================================
# 7. VARIANT 1: Regime overlay 강화
#    - Caution threshold: MRS 30 → 25
#    - Crisis: 50/20/30 → 40/30/30 (inverse 20→30%)
#    - Caution에서도 inverse 10% 배분
# ===================================================================
cat("[Step 7] V1: Enhanced regime overlay...\n")
nd[, crisis_flag_v1 := fifelse(MRS >= 55 & n_axes_firing >= 4, 1L, 0L)]  # slightly easier trigger
nd[, crisis_consec_v1 := {
  out <- integer(.N); cnt <- 0L
  for (j in seq_len(.N)) { if (nd$crisis_flag_v1[j] == 1L) cnt <- cnt + 1L else cnt <- 0L; out[j] <- cnt }
  out
}]
nd[, Layer_v1 := fifelse(crisis_consec_v1 >= 3L, 3L, fifelse(MRS >= 25, 2L, 1L))]
nd[, Ret_v1 := fcase(
  Layer_v1 == 1L, Strategy_Ret,
  Layer_v1 == 2L, {
    fw <- pmax(0.4, 1.0 - (MRS - 25) / 50)
    fw * Strategy_Ret + 0.10 * Ret_Inv + (1 - fw - 0.10) * 0  # 10% inverse in caution
  },
  Layer_v1 == 3L, 0.40 * Strategy_Ret + 0.30 * Ret_Inv + 0.30 * 0  # 30% inverse in crisis
)]
# Clamp caution blending so factor weight >=0
nd[Layer_v1 == 2L & Ret_v1 == Strategy_Ret, Ret_v1 := {
  fw <- pmax(0.4, 1.0 - (MRS - 25) / 50)
  inv_w <- pmin(0.10, 1 - fw)
  fw * Strategy_Ret + inv_w * Ret_Inv + (1 - fw - inv_w) * 0
}]
nd[, NAV_v1 := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_v1)]

# ===================================================================
# 8. VARIANT 2: Vol Targeting (15% annualized)
#    - C9: expanding vol with t-1 lag
#    - Moskowitz et al. (2012): vol scaling improves SR
# ===================================================================
cat("[Step 8] V2: Vol Targeting 15%...\n")
VOL_TARGET <- 0.15  # annualized
VOL_LOOKBACK <- 60L  # expanding minimum, then use expanding

# Compute expanding vol from base strategy returns (t-1 lagged)
nd[, base_vol_expanding := {
  n <- .N; vol <- rep(NA_real_, n)
  for (j in seq_len(n)) {
    if (j < VOL_LOOKBACK) { vol[j] <- NA_real_ }
    else { vol[j] <- sd(Strategy_Ret[1:j], na.rm = TRUE) * sqrt(252) }
  }
  vol
}]

# C9 CRITICAL: t-1 lag — today's vol_scale uses YESTERDAY's computed vol
nd[, vol_scale := shift(fifelse(!is.na(base_vol_expanding) & base_vol_expanding > 0.01,
                                pmin(VOL_TARGET / base_vol_expanding, 1.5),  # cap at 150%
                                1.0),
                        n = 1L, type = "lag")]
nd[is.na(vol_scale), vol_scale := 1.0]

# Apply vol targeting to base overlay (V0)
nd[, Ret_v2 := Ret_v0 * vol_scale]
nd[, NAV_v2 := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_v2)]

# ===================================================================
# 9. VARIANT 3: DD Brake 5/15 (L-728: base SR > 1.0 required)
#    - C9: dd_exposure uses t-1 NAV drawdown
#    - L-729: tight 5/15 better than wide 10/30
# ===================================================================
cat("[Step 9] V3: DD Brake 5/15...\n")
DD_TRIGGER  <- 0.05   # 5% drawdown triggers partial exit
DD_MAX_EXIT <- 0.15   # 15% drawdown = max exit (exposure → 0)

# Compute drawdown from V0 overlay NAV (already regime-adjusted)
nd[, running_max_v0 := cummax(NAV_v0)]
nd[, dd_pct_v0 := (NAV_v0 - running_max_v0) / running_max_v0]  # negative values

# C9 CRITICAL: t-1 lag for DD exposure
nd[, dd_exposure := {
  exp_raw <- fifelse(dd_pct_v0 >= -DD_TRIGGER, 1.0,
                     fifelse(dd_pct_v0 <= -DD_MAX_EXIT, 0.0,
                             (dd_pct_v0 + DD_MAX_EXIT) / (DD_MAX_EXIT - DD_TRIGGER)))
  # t-1 lag: use yesterday's exposure for today's return
  c(1.0, head(exp_raw, -1))
}]
nd[, Ret_v3 := Ret_v0 * dd_exposure]
nd[, NAV_v3 := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_v3)]

# ===================================================================
# 10. VARIANT 4: V1 + V2 + V3 통합 (강화 regime + VT + DD)
# ===================================================================
cat("[Step 10] V4: Combined (V1 regime + VT + DD)...\n")

# First apply enhanced regime (V1)
# Then Vol Target on top of V1
nd[, Ret_v4_step1 := Ret_v1 * vol_scale]  # V1 + VT

# DD Brake on the combined V4 NAV (need iterative computation)
nd[, NAV_v4_temp := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_v4_step1)]
nd[, running_max_v4 := cummax(NAV_v4_temp)]
nd[, dd_pct_v4 := (NAV_v4_temp - running_max_v4) / running_max_v4]
nd[, dd_exposure_v4 := {
  exp_raw <- fifelse(dd_pct_v4 >= -DD_TRIGGER, 1.0,
                     fifelse(dd_pct_v4 <= -DD_MAX_EXIT, 0.0,
                             (dd_pct_v4 + DD_MAX_EXIT) / (DD_MAX_EXIT - DD_TRIGGER)))
  c(1.0, head(exp_raw, -1))  # t-1 lag
}]
nd[, Ret_v4 := Ret_v4_step1 * dd_exposure_v4]
nd[, NAV_v4 := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_v4)]

# ===================================================================
# 11. Performance Summary
# ===================================================================
cat("\n[Step 11] Computing performance metrics...\n")

perf_fn <- function(ret_vec, label) {
  rx <- xts(ret_vec, order.by = nd$Date); names(rx) <- "Strategy"
  summarise_perf(rx, label)
}

p0 <- perf_fn(nd$Ret_v0, "V0_Original")
p1 <- perf_fn(nd$Ret_v1, "V1_EnhRegime")
p2 <- perf_fn(nd$Ret_v2, "V2_VolTarget")
p3 <- perf_fn(nd$Ret_v3, "V3_DDBrake")
p4 <- perf_fn(nd$Ret_v4, "V4_Combined")
pb <- summarise_perf(sim_base$bm_xts, "KOSPI200")

cat("\n================================================================\n")
cat("   PG2 MDD OPTIMIZATION COMPARISON\n")
cat("================================================================\n")
cat("--- V0: Original SYN_05 Overlay ---\n"); print(p0)
cat("--- V1: Enhanced Regime (Caution 25, Inverse 30%) ---\n"); print(p1)
cat("--- V2: Vol Targeting 15% ---\n"); print(p2)
cat("--- V3: DD Brake 5/15 ---\n"); print(p3)
cat("--- V4: Combined (V1+V2+V3) ---\n"); print(p4)
cat("--- BM: KOSPI200 ---\n"); print(pb)

# Regime activity stats
cat("\n--- Regime Activity ---\n")
cat(sprintf("V0: Normal=%.1f%% Caution=%.1f%% Crisis=%.1f%%\n",
  100 * mean(nd$Layer_v0 == 1), 100 * mean(nd$Layer_v0 == 2), 100 * mean(nd$Layer_v0 == 3)))
cat(sprintf("V1: Normal=%.1f%% Caution=%.1f%% Crisis=%.1f%%\n",
  100 * mean(nd$Layer_v1 == 1), 100 * mean(nd$Layer_v1 == 2), 100 * mean(nd$Layer_v1 == 3)))
cat(sprintf("V2: Mean vol_scale=%.3f\n", mean(nd$vol_scale, na.rm = TRUE)))
cat(sprintf("V3: Mean dd_exposure=%.3f\n", mean(nd$dd_exposure, na.rm = TRUE)))
cat(sprintf("V4: Mean dd_exposure_v4=%.3f\n", mean(nd$dd_exposure_v4, na.rm = TRUE)))

# ===================================================================
# 12. Charts & JSON output
# ===================================================================
cat("\n[Step 12] Generating charts...\n")

# Equity curves
eq_dt <- nd[, .(Date, V0_Original = NAV_v0, V1_EnhRegime = NAV_v1,
                V2_VolTarget = NAV_v2, V3_DDBrake = NAV_v3, V4_Combined = NAV_v4)]
eq_long <- melt(eq_dt, id.vars = "Date", variable.name = "Variant", value.name = "NAV")

g1 <- ggplot(eq_long, aes(x = Date, y = NAV, color = Variant)) +
  geom_line(linewidth = 0.6) +
  scale_y_log10(labels = comma) +
  labs(title = "PG2 MDD Optimization: Equity Curves",
       subtitle = "V0=Original | V1=EnhRegime | V2=VolTarget | V3=DDBrake | V4=Combined",
       x = NULL, y = "NAV (log scale)") +
  theme_minimal(base_size = 11) +
  scale_color_manual(values = c("V0_Original" = "gray50", "V1_EnhRegime" = "steelblue",
    "V2_VolTarget" = "darkorange", "V3_DDBrake" = "darkgreen", "V4_Combined" = "red3"))
ggsave(file.path(OUT_DIR, "equity_curve.png"), g1, width = 12, height = 7, dpi = 150)

# Drawdown chart
dd_fn <- function(nav) { rm <- cummax(nav); (nav - rm) / rm * 100 }
dd_dt <- nd[, .(Date, V0 = dd_fn(NAV_v0), V1 = dd_fn(NAV_v1),
                V2 = dd_fn(NAV_v2), V3 = dd_fn(NAV_v3), V4 = dd_fn(NAV_v4))]
dd_long <- melt(dd_dt, id.vars = "Date", variable.name = "Variant", value.name = "Drawdown")

g2 <- ggplot(dd_long, aes(x = Date, y = Drawdown, color = Variant)) +
  geom_line(linewidth = 0.5, alpha = 0.8) +
  geom_hline(yintercept = -25, linetype = "dashed", color = "red", linewidth = 0.7) +
  annotate("text", x = min(dd_long$Date) + 365, y = -26.5, label = "Target MDD -25%",
           color = "red", size = 3.5) +
  labs(title = "PG2 MDD Optimization: Drawdown Comparison",
       x = NULL, y = "Drawdown (%)") +
  theme_minimal(base_size = 11) +
  scale_color_manual(values = c("V0" = "gray50", "V1" = "steelblue",
    "V2" = "darkorange", "V3" = "darkgreen", "V4" = "red3"))
ggsave(file.path(OUT_DIR, "drawdown_comparison.png"), g2, width = 12, height = 6, dpi = 150)

# Annual returns
ar_fn <- function(ret_vec, label) {
  rx <- xts(ret_vec, order.by = nd$Date)
  yr <- endpoints(rx, "years")
  ann <- period.apply(rx, yr, function(x) prod(1 + x) - 1)
  data.table(Year = year(index(ann)), Variant = label, AnnRet = as.numeric(ann) * 100)
}
ar_all <- rbindlist(list(
  ar_fn(nd$Ret_v0, "V0"), ar_fn(nd$Ret_v1, "V1"),
  ar_fn(nd$Ret_v2, "V2"), ar_fn(nd$Ret_v3, "V3"), ar_fn(nd$Ret_v4, "V4")
))
g3 <- ggplot(ar_all, aes(x = factor(Year), y = AnnRet, fill = Variant)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.7), width = 0.6) +
  labs(title = "PG2 MDD Optimization: Annual Returns", x = "Year", y = "Return (%)") +
  theme_minimal(base_size = 11) +
  scale_fill_manual(values = c("V0" = "gray50", "V1" = "steelblue",
    "V2" = "darkorange", "V3" = "darkgreen", "V4" = "red3"))
ggsave(file.path(OUT_DIR, "annual_returns.png"), g3, width = 12, height = 7, dpi = 150)

# Save comparison JSON
results <- list(
  task = "PG2_MDD_Optimization",
  base_strategy = "STR_1631_SYN_05",
  target_mdd = 25.0,
  pit_notes = list(
    C5 = "Regime overlay uses MRS t-1 from regime_engine_daily.R",
    C9_VT = "vol_scale = shift(vol, n=1, type='lag') — expanding vol t-1",
    C9_DD = "dd_exposure = c(1.0, head(exp_raw, -1)) — t-1 lagged"
  ),
  references = list(
    "Moskowitz et al. (2012) — Vol targeting",
    "L-728: DD Brake only when base SR > 1.0",
    "L-729: tight 5/15 > wide 10/30"
  ),
  variants = list(
    V0_Original = as.list(p0),
    V1_EnhRegime = as.list(p1),
    V2_VolTarget = as.list(p2),
    V3_DDBrake = as.list(p3),
    V4_Combined = as.list(p4)
  ),
  regime_stats = list(
    V0_crisis_days_pct = round(100 * mean(nd$Layer_v0 == 3), 1),
    V1_crisis_days_pct = round(100 * mean(nd$Layer_v1 == 3), 1),
    V2_mean_vol_scale = round(mean(nd$vol_scale, na.rm = TRUE), 3),
    V3_mean_dd_exposure = round(mean(nd$dd_exposure, na.rm = TRUE), 3)
  ),
  recommendation = "TBD — compare MDD vs CAGR tradeoff",
  run_time = as.numeric(difftime(Sys.time(), t0, units = "secs"))
)
write_json(results, file.path(OUT_DIR, "pg2_mdd_comparison.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Save daily data for further analysis
fwrite(nd[, .(Date, Strategy_Ret, MRS, n_axes_firing,
             Ret_v0, NAV_v0, Layer_v0,
             Ret_v1, NAV_v1, Layer_v1,
             Ret_v2, NAV_v2, vol_scale,
             Ret_v3, NAV_v3, dd_exposure,
             Ret_v4, NAV_v4, dd_exposure_v4)],
       file.path(OUT_DIR, "daily_nav_comparison.csv"))

cat(sprintf("\n[DONE] PG2 MDD Optimization in %.1f sec\n", difftime(Sys.time(), t0, units = "secs")))
cat(sprintf("Output: %s\n", OUT_DIR))
