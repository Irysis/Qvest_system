cat("=== STR_1631 Core + H_1675 Defense Blend Simulation ===\n")
## 핵심 아이디어: M29 Core(ICIR) + H_1675 Defense(Q07+D29) 수익률 블렌드
## 월간 리밸런싱만 사용
## 5가지 블렌드: 90/10, 80/20, 70/30, 60/40, Regime-Conditional
## PIT: 각 전략 자체가 PIT 준수. 블렌드는 월간 수익률 가중평균만.
## MRS lag: Regime conditional 블렌드에서 mrs_lag = t-1 (C5 준수)

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

# ===================================================================
# PART A: Reconstruct M29 Core daily returns
# ===================================================================
cat("\n[Part A] Reconstructing M29 Core strategy...\n")

LIQ_THRESHOLD  <- 2e8
N_HOLD         <- 20L
MAX21D_EXCL    <- 0.80
HRP_LOOKBACK   <- 60L
REBAL_MONTHS   <- 2L
HRP_TILT_W     <- 0.6
SCORE_TILT_W   <- 0.4
IC_MIN_MONTHS  <- 12L
IC_VOL_WINDOW  <- 12L

# Step 1: Load RAWDATA
cat("[A1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]; BM_DT <- BM_DT[Date >= ANALYSIS_START_DATE]
dc <- intersect(c("Open", "High", "Low", "source", "Size", "Market"), names(RAWDATA))
if (length(dc) > 0) RAWDATA[, (dc) := NULL]
if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  ud <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "universe.parquet"))); ud[, Date := as.Date(Date)]
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

# Step 2: Load Consensus
cat("[A2] Loading Consensus...\n")
lc <- function(f) {
  dt <- as.data.table(arrow::read_parquet(file.path(CONS_DIR, f))); dt[, Date := as.Date(Date)]
  dt <- dt[Date >= ANALYSIS_START_DATE]; setkey(dt, Ticker, Date); dt
}
SUE_DT   <- lc("sue.parquet")
ESBR_DT  <- lc("esbr.parquet")
EPS1M_DT <- lc("eps_chg_1m.parquet")
COV_DT   <- lc("coverage.parquet")
TP_DT    <- lc("target_price.parquet")

# Step 3: IC + Factor Vol Scaling
cat("[A3] Computing IC + Factor Vol Scaling...\n")
z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

fwd_map <- setNames(lapply(seq_along(ALL_SIG_DATES), function(i) {
  sd <- ALL_SIG_DATES[i]
  if (i >= length(ALL_SIG_DATES)) return(NULL)
  next_sd <- ALL_SIG_DATES[i + 1]
  RAWDATA[Date > sd & Date <= next_sd, .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
}), as.character(ALL_SIG_DATES))

raw_scores_list <- lapply(seq_along(ALL_SIG_DATES), function(i) {
  sd <- ALL_SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) return(NULL)
  mq <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= mq]; if (nrow(univ) < 30L) return(NULL)
  probe <- data.table(Ticker = univ$Ticker, Date = sd); setkey(probe, Ticker, Date)
  sue_j   <- SUE_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, sue)]
  esbr_j  <- ESBR_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, eps_chg_1m)]
  cov_j   <- COV_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, coverage)]
  tp_j    <- TP_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, target_price)]
  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker, Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]; if (nrow(sig) < 20L) return(NULL)
  sig[, TP_Gap := (target_price - Close) / Close]
  sig[, z_sue := z_safe(sue)]; sig[, z_esbr := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]; sig[, z_tpgap := z_safe(TP_Gap)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if (nrow(sig) < 20L) return(NULL)
  data.table(Date = sd, Ticker = sig$Ticker,
    z_sue = sig$z_sue, z_esbr = sig$z_esbr, z_eps1m = sig$z_eps1m, z_tpgap = sig$z_tpgap)
})
RAW_SCORES <- rbindlist(raw_scores_list[!sapply(raw_scores_list, is.null)])

unique_dates <- sort(unique(RAW_SCORES$Date))
ic_list <- lapply(seq_along(unique_dates), function(i) {
  sd <- unique_dates[i]
  fr <- fwd_map[[as.character(sd)]]; if (is.null(fr)) return(NULL)
  sc <- RAW_SCORES[Date == sd]; mg <- merge(sc, fr, by = "Ticker")
  if (nrow(mg) < 10L) return(NULL)
  data.table(Date = sd,
    ic_sue   = fifelse(is.na(cor(mg$z_sue,   mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_sue,   mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_esbr  = fifelse(is.na(cor(mg$z_esbr,  mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_esbr,  mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_eps1m = fifelse(is.na(cor(mg$z_eps1m, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_eps1m, mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_tpgap = fifelse(is.na(cor(mg$z_tpgap, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_tpgap, mg$fwd_ret, method = "spearman", use = "complete.obs")))
})
ic_history <- rbindlist(ic_list[!sapply(ic_list, is.null)])

FACTORS_list <- lapply(seq_along(SIG_DATES), function(i) {
  sd <- SIG_DATES[i]
  sc <- RAW_SCORES[Date == sd]; if (nrow(sc) < 20L) return(NULL)
  past_ic <- ic_history[Date < sd]
  if (nrow(past_ic) < IC_MIN_MONTHS) {
    w_factors <- c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25)
  } else {
    mean_ic <- c(sue = mean(past_ic$ic_sue, na.rm = TRUE), esbr = mean(past_ic$ic_esbr, na.rm = TRUE),
                 eps1m = mean(past_ic$ic_eps1m, na.rm = TRUE), tpgap = mean(past_ic$ic_tpgap, na.rm = TRUE))
    recent_ic <- tail(past_ic, IC_VOL_WINDOW)
    vol_ic <- c(sue = sd(recent_ic$ic_sue, na.rm = TRUE), esbr = sd(recent_ic$ic_esbr, na.rm = TRUE),
                eps1m = sd(recent_ic$ic_eps1m, na.rm = TRUE), tpgap = sd(recent_ic$ic_tpgap, na.rm = TRUE))
    vol_ic <- pmax(vol_ic, 0.01)
    mean_ic_pos <- pmax(mean_ic, 0)
    vs_ic <- mean_ic_pos / vol_ic
    ic_sum <- sum(vs_ic)
    w_factors <- if (ic_sum < 1e-8) c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25) else vs_ic / ic_sum
  }
  sc[, C19_icw := w_factors["sue"] * z_sue + w_factors["esbr"] * z_esbr +
                  w_factors["eps1m"] * z_eps1m + w_factors["tpgap"] * z_tpgap]
  setorder(sc, -C19_icw); top <- head(sc, N_HOLD)
  data.table(Date = sd, Ticker = top$Ticker, Score = top$C19_icw)
})
FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
cat(sprintf("[A3] FACTORS: %d rows | %d bimonthly months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, RAW_SCORES, FACTORS_list, SIG_SNAP)
gc(verbose = FALSE)

# Step 4: HRP + Score Tilt (M29 identical)
cat("[A4] Computing HRP-Score Tilt weights...\n")
gerber_cor <- function(ret_matrix, threshold = 0.5) {
  n <- ncol(ret_matrix); mat <- matrix(0, n, n)
  med_abs <- apply(ret_matrix, 2, function(x) median(abs(x), na.rm = TRUE))
  med_abs <- ifelse(med_abs < 1e-12, apply(ret_matrix, 2, sd, na.rm = TRUE), med_abs)
  idx_pairs <- which(upper.tri(mat), arr.ind = TRUE)
  apply(idx_pairs, 1, function(p) {
    i <- p[1]; j <- p[2]
    ti <- threshold * med_abs[i]; hi <- ret_matrix[, i] > ti; li <- ret_matrix[, i] < -ti
    tj <- threshold * med_abs[j]; hj <- ret_matrix[, j] > tj; lj <- ret_matrix[, j] < -tj
    co <- sum((hi & hj) | (li & lj), na.rm = TRUE)
    di <- sum((hi & lj) | (li & hj), na.rm = TRUE)
    tot <- co + di; val <- if (tot > 0L) (co - di) / tot else 0
    mat[i, j] <<- val; mat[j, i] <<- val
  })
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
invisible(lapply(seq_along(all_sig_dates_sorted), function(k) {
  d <- all_sig_dates_sorted[k]
  if (k == 1L) prev_score_map[[as.character(d)]] <<- NULL
  else prev_score_map[[as.character(d)]] <<- FACTORS[Date == all_sig_dates_sorted[k-1], .(Ticker, Score)]
}))

hrp_results <- lapply(all_sig_dates_sorted, function(sd) {
  tickers <- FACTORS_hrp[Date == sd, Ticker]
  ad <- sort(unique(RAWDATA[Date < sd, Date]))
  if (length(ad) < HRP_LOOKBACK) return(list(sd = sd, w = setNames(rep(1/length(tickers), length(tickers)), tickers), fb = TRUE))
  ld <- tail(ad, HRP_LOOKBACK)
  rs <- RAWDATA[Date %in% ld & Ticker %in% tickers, .(Date, Ticker, Ret)]
  rw <- dcast(rs, Date ~ Ticker, value.var = "Ret")
  rm_ <- as.matrix(rw[, -1, with = FALSE]); colnames(rm_) <- names(rw)[-1]
  vc <- colSums(!is.na(rm_)) >= 30L
  if (sum(vc) < 2L) return(list(sd = sd, w = setNames(rep(1/length(tickers), length(tickers)), tickers), fb = TRUE))
  rc <- rm_[, vc, drop = FALSE]; rc[is.na(rc)] <- 0
  hw <- tryCatch(compute_hrp_weights(rc), error = function(e) NULL)
  if (is.null(hw)) return(list(sd = sd, w = setNames(rep(1/length(tickers), length(tickers)), tickers), fb = TRUE))
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
    } else final_w <- hrp_vec
  } else final_w <- hrp_vec
  final_w <- final_w / sum(final_w)
  list(sd = sd, w = setNames(final_w, tickers), fb = FALSE)
})
invisible(lapply(hrp_results, function(r) {
  tickers <- names(r$w)
  sapply(tickers, function(tk) FACTORS_hrp[Date == r$sd & Ticker == tk, Weight_hrp := r$w[tk]])
}))

hwl <- list()
invisible(lapply(as.character(unique(FACTORS_hrp$Date)), function(d) {
  mf <- FACTORS_hrp[Date == as.Date(d)]; w <- mf$Weight_hrp
  if (all(is.na(w))) w <- rep(1 / nrow(mf), nrow(mf))
  hwl[[d]] <<- setNames(w, mf$Ticker)
}))
oi <- calc_ivol_weights
calc_ivol_weights <<- function(tickers, ret_dt, n_days = 60, max_w = 0.15) {
  lapply(names(hwl), function(d) {
    hw <- hwl[[d]]; if (all(tickers %in% names(hw))) { w <- hw[tickers]; return(as.numeric(w / sum(w))) }
    NULL
  }) -> matches
  matches <- matches[!sapply(matches, is.null)]
  if (length(matches) > 0) return(matches[[1]])
  rep(1 / length(tickers), length(tickers))
}
sim_core <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS, n_holdings = N_HOLD,
  weight_method = "ivol", commission = 0.0015, buffer_zone = list(keep_n = 35L, entry_n = 20L))
calc_ivol_weights <<- oi
cat(sprintf("[A4] Core simulation complete: %d trading days\n", nrow(sim_core$DAILY_NAV_DT)))

# ===================================================================
# PART B: Load Defense monthly returns
# ===================================================================
cat("\n[Part B] Loading Defense monthly returns...\n")
def_csv <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1675_Q07_D29_defense/output/performance_STR_1675c.csv")
DEF_MONTHLY <- fread(def_csv)
DEF_MONTHLY[, Date := as.Date(Date)]
setnames(DEF_MONTHLY, "port_ret", "def_ret")
cat(sprintf("[B] Defense: %d months, %s ~ %s\n", nrow(DEF_MONTHLY), min(DEF_MONTHLY$Date), max(DEF_MONTHLY$Date)))

# ===================================================================
# PART C: Aggregate Core daily to monthly + merge
# ===================================================================
cat("\n[Part C] Aggregating Core to monthly...\n")
core_daily <- sim_core$DAILY_NAV_DT[, .(Date, Strategy_Ret)]
core_daily[, YM := format(Date, "%Y-%m")]
core_monthly <- core_daily[, .(
  Date = max(Date),
  core_ret = prod(1 + Strategy_Ret, na.rm = TRUE) - 1
), by = YM]
setorder(core_monthly, Date)
cat(sprintf("[C] Core monthly: %d months, %s ~ %s\n", nrow(core_monthly), min(core_monthly$Date), max(core_monthly$Date)))

# BM monthly
bm_daily <- merge(data.table(Date = index(sim_core$bm_xts), BM_Ret = as.numeric(sim_core$bm_xts)),
                  core_daily[, .(Date)], by = "Date")
bm_daily[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm_daily[, .(Date = max(Date), bm_ret = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = YM]

# Merge core + defense + bm on YM
BLEND_DT <- merge(core_monthly[, .(YM, Date, core_ret)],
                  DEF_MONTHLY[, .(YM = format(Date, "%Y-%m"), def_ret)],
                  by = "YM", all = FALSE)
BLEND_DT <- merge(BLEND_DT, bm_monthly[, .(YM, bm_ret)], by = "YM", all.x = TRUE)
setorder(BLEND_DT, Date)
cat(sprintf("[C] Merged: %d months overlap, %s ~ %s\n", nrow(BLEND_DT), min(BLEND_DT$Date), max(BLEND_DT$Date)))

# ===================================================================
# PART D: MRS monthly for conditional blend (S5 artifact present)
# ===================================================================
cat("\n[Part D] Loading MRS for conditional blend...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REG_DATA <- build_daily_regime(use_cache = TRUE); setkey(REG_DATA, Date)

# Get month-end MRS (last trading day of each month)
reg_monthly <- REG_DATA[, .(mrs_eom = last(MRS)), by = .(YM = format(Date, "%Y-%m"))]
# t-1 lag: use previous month's MRS for current month blend decision (C5 compliant)
setorder(reg_monthly, YM)
reg_monthly[, mrs_lag := shift(mrs_eom, n = 1L, type = "lag")]
reg_monthly[is.na(mrs_lag), mrs_lag := 0]

BLEND_DT <- merge(BLEND_DT, reg_monthly[, .(YM, mrs_lag)], by = "YM", all.x = TRUE)
BLEND_DT[is.na(mrs_lag), mrs_lag := 0]

# ===================================================================
# PART E: Compute 5 blends
# ===================================================================
cat("\n[Part E] Computing 5 blends...\n")

# Static blends
BLEND_DT[, b_90_10 := 0.90 * core_ret + 0.10 * def_ret]
BLEND_DT[, b_80_20 := 0.80 * core_ret + 0.20 * def_ret]
BLEND_DT[, b_70_30 := 0.70 * core_ret + 0.30 * def_ret]
BLEND_DT[, b_60_40 := 0.60 * core_ret + 0.40 * def_ret]

# MRS conditional blend (mrs_lag is t-1 lagged, C5 compliant)
BLEND_DT[, b_cond := fifelse(
  mrs_lag >= 50, 0.60 * core_ret + 0.40 * def_ret,
  fifelse(mrs_lag >= 20, 0.80 * core_ret + 0.20 * def_ret,
          0.95 * core_ret + 0.05 * def_ret)
)]

# Log allocation stats
alloc_stats <- BLEND_DT[, .(
  n_normal = sum(mrs_lag < 20),
  n_caution = sum(mrs_lag >= 20 & mrs_lag < 50),
  n_crisis = sum(mrs_lag >= 50)
)]
cat(sprintf("[E] Conditional months: Normal(95/5)=%d | Caution(80/20)=%d | Crisis(60/40)=%d\n",
            alloc_stats$n_normal, alloc_stats$n_caution, alloc_stats$n_crisis))

# ===================================================================
# PART F: Performance summary
# ===================================================================
cat("\n[Part F] Computing performance...\n")

calc_perf <- function(ret_vec, dates, label) {
  n_yr <- as.numeric(difftime(max(dates), min(dates), units = "days")) / 365.25
  cagr <- (prod(1 + ret_vec) ^ (1 / n_yr) - 1) * 100
  ann_vol <- sd(ret_vec, na.rm = TRUE) * sqrt(12) * 100
  sr <- if (ann_vol > 0) (cagr / ann_vol) else 0
  nav <- cumprod(1 + ret_vec)
  peak <- cummax(nav)
  dd <- (nav - peak) / peak
  mdd <- min(dd) * 100
  neg_ret <- ret_vec[ret_vec < 0]
  down_vol <- if (length(neg_ret) > 1) sd(neg_ret, na.rm = TRUE) * sqrt(12) * 100 else ann_vol
  sortino <- if (down_vol > 0) (cagr / down_vol) else 0
  calmar <- if (mdd < 0) cagr / abs(mdd) else NA_real_

  data.table(Label = label, CAGR = round(cagr, 2), AnnVol = round(ann_vol, 2),
             Sharpe = round(sr, 3), Sortino = round(sortino, 3),
             MDD = round(mdd, 2), Calmar = round(calmar, 3))
}

results <- rbindlist(list(
  calc_perf(BLEND_DT$core_ret, BLEND_DT$Date, "Core (M29)"),
  calc_perf(BLEND_DT$def_ret,  BLEND_DT$Date, "Defense (H1675c)"),
  calc_perf(BLEND_DT$b_90_10,  BLEND_DT$Date, "Blend 90/10"),
  calc_perf(BLEND_DT$b_80_20,  BLEND_DT$Date, "Blend 80/20"),
  calc_perf(BLEND_DT$b_70_30,  BLEND_DT$Date, "Blend 70/30"),
  calc_perf(BLEND_DT$b_60_40,  BLEND_DT$Date, "Blend 60/40"),
  calc_perf(BLEND_DT$b_cond,   BLEND_DT$Date, "MRS Conditional"),
  calc_perf(BLEND_DT$bm_ret,   BLEND_DT$Date, "KOSPI200")
))

cat("\n================================================================\n")
cat("   Core + Defense Blend Comparison\n")
cat("================================================================\n")
print(results)

# Correlation between core and defense
cor_cd <- cor(BLEND_DT$core_ret, BLEND_DT$def_ret, use = "complete.obs")
cat(sprintf("\nCore-Defense monthly correlation: %.3f\n", cor_cd))

# ===================================================================
# PART G: Charts
# ===================================================================
cat("\n[Part G] Generating charts...\n")

# Equity curves comparison
nav_dt <- data.table(
  Date = rep(BLEND_DT$Date, 7),
  NAV = c(
    cumprod(1 + BLEND_DT$core_ret),
    cumprod(1 + BLEND_DT$def_ret),
    cumprod(1 + BLEND_DT$b_90_10),
    cumprod(1 + BLEND_DT$b_80_20),
    cumprod(1 + BLEND_DT$b_70_30),
    cumprod(1 + BLEND_DT$b_60_40),
    cumprod(1 + BLEND_DT$b_cond)
  ),
  Strategy = rep(c("Core (M29)", "Defense (H1675c)", "90/10", "80/20", "70/30", "60/40", "MRS Conditional"),
                 each = nrow(BLEND_DT))
)
nav_dt[, Strategy := factor(Strategy, levels = c("Core (M29)", "Defense (H1675c)",
  "90/10", "80/20", "70/30", "60/40", "MRS Conditional"))]

p1 <- ggplot(nav_dt, aes(x = Date, y = NAV, color = Strategy)) +
  geom_line(linewidth = 0.7) +
  scale_y_log10(labels = comma) +
  scale_color_manual(values = c("Core (M29)" = "#2196F3", "Defense (H1675c)" = "#4CAF50",
    "90/10" = "#FF9800", "80/20" = "#E91E63", "70/30" = "#9C27B0",
    "60/40" = "#795548", "MRS Conditional" = "#F44336")) +
  labs(title = "Core + Defense Blend: Equity Curves",
       subtitle = sprintf("Core-Defense corr: %.3f | MRS months: Normal %d / Caution %d / Crisis %d",
                          cor_cd, alloc_stats$n_normal, alloc_stats$n_caution, alloc_stats$n_crisis),
       x = NULL, y = "NAV (log scale)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", legend.title = element_blank())
ggsave(file.path(OUT_DIR, "equity_curve.png"), p1, width = 12, height = 7, dpi = 150)

# Drawdown comparison
dd_calc <- function(ret_vec) {
  nav <- cumprod(1 + ret_vec); peak <- cummax(nav); (nav - peak) / peak
}
dd_dt <- data.table(
  Date = rep(BLEND_DT$Date, 4),
  DD = c(dd_calc(BLEND_DT$core_ret), dd_calc(BLEND_DT$b_80_20),
         dd_calc(BLEND_DT$b_cond), dd_calc(BLEND_DT$def_ret)),
  Strategy = rep(c("Core (M29)", "Blend 80/20", "MRS Conditional", "Defense (H1675c)"),
                 each = nrow(BLEND_DT))
)

p2 <- ggplot(dd_dt, aes(x = Date, y = DD * 100, color = Strategy)) +
  geom_line(linewidth = 0.6, alpha = 0.8) +
  scale_color_manual(values = c("Core (M29)" = "#2196F3", "Blend 80/20" = "#E91E63",
    "MRS Conditional" = "#F44336", "Defense (H1675c)" = "#4CAF50")) +
  labs(title = "Drawdown Comparison", x = NULL, y = "Drawdown (%)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", legend.title = element_blank())
ggsave(file.path(OUT_DIR, "drawdown_comparison.png"), p2, width = 12, height = 6, dpi = 150)

# Annual returns heatmap
BLEND_DT[, Year := year(Date)]
annual_dt <- BLEND_DT[, .(
  Core = (prod(1 + core_ret) - 1) * 100,
  Defense = (prod(1 + def_ret) - 1) * 100,
  `80/20` = (prod(1 + b_80_20) - 1) * 100,
  MRS_Cond = (prod(1 + b_cond) - 1) * 100,
  BM = (prod(1 + bm_ret, na.rm = TRUE) - 1) * 100
), by = Year]

annual_long <- melt(annual_dt, id.vars = "Year", variable.name = "Strategy", value.name = "Return")
p3 <- ggplot(annual_long, aes(x = Year, y = Strategy, fill = Return)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.1f%%", Return)), size = 3) +
  scale_fill_gradient2(low = "#c62828", mid = "white", high = "#2e7d32", midpoint = 0) +
  labs(title = "Annual Returns Heatmap", x = NULL, y = NULL) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "right")
ggsave(file.path(OUT_DIR, "annual_returns.png"), p3, width = 14, height = 5, dpi = 150)

# ===================================================================
# PART H: Save results
# ===================================================================
cat("\n[Part H] Saving results...\n")
fwrite(BLEND_DT, file.path(OUT_DIR, "blend_monthly_returns.csv"))
fwrite(results, file.path(OUT_DIR, "blend_comparison.csv"))
fwrite(annual_dt, file.path(OUT_DIR, "annual_returns.csv"))

write_json(list(
  strategy = "STR_1631_core_defense_blend",
  description = "Core(M29 ICIR) + Defense(H1675c Q07+D29) monthly return blend",
  core = "STR_1631_M29_facvol (ICIR Factor Vol Scaling, HRP+ScoreTilt)",
  defense = "STR_1675c (Q07_80_D29_20, Earnings Stability + Accounting Beta)",
  overlap_months = nrow(BLEND_DT),
  overlap_period = paste(min(BLEND_DT$Date), "~", max(BLEND_DT$Date)),
  core_defense_corr = round(cor_cd, 4),
  alloc_months = as.list(alloc_stats),
  results = lapply(seq_len(nrow(results)), function(i) as.list(results[i])),
  pit_notes = list(
    core = "M29 PIT compliant (expanding IC, t-1 lag)",
    defense = "H1675 PIT compliant (factor DB z-score aligned)",
    blend = "monthly return weighted average only, no lookahead",
    mrs_lag = "conditional blend uses mrs_lag = t-1 month end (C5)"
  ),
  run_time = as.numeric(difftime(Sys.time(), t0, units = "secs"))
), file.path(OUT_DIR, "performance.json"), pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\n[DONE] Blend simulation complete in %.1f sec\n", difftime(Sys.time(), t0, units = "secs")))
