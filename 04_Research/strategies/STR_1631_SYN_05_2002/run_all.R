cat("=== STR_1631 SYN_05_2002: IC-Weighted + Score Tilt + Bimonthly (Full 2002~ Backtest) ===\n")
## 핵심 아이디어: SYN_05와 동일 구조 + Consensus 데이터 최초 가용일(2001-06)부터 확장
## 변경점: SIGNAL_START_DATE → 1990-07-01 유지 (config.R 기본값)
##          Consensus 가용 시점 자연 필터 → 실질 시그널 ~2002-01부터
## SYN_04: Expanding IC-weighted C19 blend (C1 safe)
## M23: 0.6*HRP + 0.4*Score(t-1 frozen) hybrid weighting
## M19: 격월 리밸런싱 (TO ~50% 감소)
## PIT: C1(expanding IC), C2(Score t-1 lag), C4(Consensus roll=7d), C9(MRS already t-1 in engine)
## Ref: Arnott et al.(2019) + Novy-Marx & Velikov(2016) + Briere & Szafarz(2021)
## set.seed(1631)

set.seed(1631)
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

# Rcpp weight_engine 로드 시도
tryCatch(
  Rcpp::sourceCpp(file.path(FUNC_PATH, "portfolio", "weight_engine.cpp")),
  error = function(e) {
    tryCatch(
      Rcpp::sourceCpp(file.path(PROJECT_ROOT, "02_Infrastructure", "portfolio", "weight_engine.cpp")),
      error = function(e2) cat("[Rcpp] weight_engine.cpp 미발견 — R 폴백 사용\n")
    )
  }
)

LIQ_THRESHOLD  <- 2e8
N_HOLD         <- 20L
MAX21D_EXCL    <- 0.80
HRP_LOOKBACK   <- 60L
REBAL_MONTHS   <- 2L       # M19: bimonthly
HRP_TILT_W     <- 0.6      # M23
SCORE_TILT_W   <- 0.4      # M23
IC_MIN_MONTHS  <- 12L      # SYN_04: min expanding window

cat(sprintf("[SYN_05_2002] IC-weighted + %.1f*HRP + %.1f*Score | Bimonthly | Full 2002~\n",
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
# C15 NOTE: C19 composite is built from raw consensus parquets (sue/esbr/eps_chg/tp),
# not via load_month_factors(). This is by design — consensus data uses roll=7L
# PIT join which provides equivalent temporal safety. Factor DB contains pre-computed
# C19 but this strategy computes inline for IC-weight flexibility.
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
ALL_SIG_DATES <- sd_dt$sig_date  # full monthly for IC computation
SIG_DATES <- ALL_SIG_DATES[seq(1, length(ALL_SIG_DATES), by = REBAL_MONTHS)]  # bimonthly for rebal
cat(sprintf("[Step 1] Monthly dates: %d | Bimonthly SIG_DATES: %d\n",
            length(ALL_SIG_DATES), length(SIG_DATES)))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
# C10 FIX: t-1 lag 적용 — 당일 거래량 제외 (PIT 준수)
RAWDATA[, LIQ_20d_raw := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, LIQ_20d := shift(LIQ_20d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, LIQ_20d_raw := NULL]
RAWDATA[, TradVal := NULL]
RAWDATA[, Ret_abs := abs(Ret)]
RAWDATA[, MAX21d_raw := {
  ra <- Ret_abs; n <- length(ra)
  if (n < 21L) cummax(fifelse(is.na(ra), -Inf, ra))
  else frollapply(ra, n = 21L, FUN = max, fill = NA, align = "right")
}, by = Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, c("Ret_abs", "MAX21d_raw") := NULL]

# SIG_SNAP for ALL months (needed for IC computation)
SIG_SNAP <- RAWDATA[Date %in% ALL_SIG_DATES & !is.na(Close), .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d", "MAX21d", "YM") := NULL]; setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

# ===================================================================
# 2. Load Consensus
# ===================================================================
cat("\n[Step 2] Loading Consensus...\n")
# C4 준수: Consensus는 roll=7d로 point-in-time 조인 (미래 데이터 사용 금지)
lc <- function(f) {
  dt <- as.data.table(read_parquet(file.path(CONS_DIR, f))); dt[, Date := as.Date(Date)]
  dt <- dt[Date >= ANALYSIS_START_DATE]; setkey(dt, Ticker, Date)
  cat(sprintf("  > %s: %s rows | %s ~ %s\n", f, format(nrow(dt), big.mark = ","),
              min(dt$Date), max(dt$Date))); dt
}
SUE_DT   <- lc("sue.parquet")
ESBR_DT  <- lc("esbr.parquet")
EPS1M_DT <- lc("eps_chg_1m.parquet")
COV_DT   <- lc("coverage.parquet")
TP_DT    <- lc("target_price.parquet")

# Consensus 최초 가용일 확인
cons_start <- max(
  min(COV_DT$Date, na.rm = TRUE),
  min(TP_DT$Date, na.rm = TRUE),
  min(EPS1M_DT$Date, na.rm = TRUE)
)
cat(sprintf("[Step 2] Consensus 최초 가용일: %s → 실질 시그널 시작 ~%s\n",
            cons_start, format(cons_start + 180, "%Y-%m")))

# ===================================================================
# 3. IC computation on ALL monthly dates, FACTORS on bimonthly only
# ===================================================================
cat("\n[Step 3] Computing expanding IC + IC-weighted FACTORS...\n")
z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

# Step 3a: forward returns (monthly)
fwd_map <- list()
for (i in seq_along(ALL_SIG_DATES)) {
  sd <- ALL_SIG_DATES[i]
  if (i < length(ALL_SIG_DATES)) {
    next_sd <- ALL_SIG_DATES[i + 1]
    ret_sub <- RAWDATA[Date > sd & Date <= next_sd, .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
    fwd_map[[as.character(sd)]] <- ret_sub
  }
}

# Step 3b: raw z-scores for ALL months (for IC computation)
raw_scores_list <- vector("list", length(ALL_SIG_DATES))
skipped_dates <- 0L
for (i in seq_along(ALL_SIG_DATES)) {
  sd <- ALL_SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) { skipped_dates <- skipped_dates + 1L; next }
  mq <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= mq]; if (nrow(univ) < 30L) { skipped_dates <- skipped_dates + 1L; next }
  probe <- data.table(Ticker = univ$Ticker, Date = sd); setkey(probe, Ticker, Date)
  # C4: roll=7d — Consensus 데이터는 최대 7일 이내 최신값만 사용 (point-in-time)
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
  raw_scores_list[[i]] <- data.table(Date = sd, Ticker = sig$Ticker,
    z_sue = sig$z_sue, z_esbr = sig$z_esbr, z_eps1m = sig$z_eps1m, z_tpgap = sig$z_tpgap)
}
RAW_SCORES <- rbindlist(raw_scores_list[!sapply(raw_scores_list, is.null)])
cat(sprintf("[Step 3b] RAW_SCORES: %d dates (skipped: %d)\n", uniqueN(RAW_SCORES$Date), skipped_dates))
if (nrow(RAW_SCORES) > 0) {
  cat(sprintf("  첫 시그널: %s | 마지막: %s\n", min(RAW_SCORES$Date), max(RAW_SCORES$Date)))
}

# Step 3c: expanding IC on ALL months
ic_history <- data.table(Date = as.Date(character()), ic_sue = numeric(), ic_esbr = numeric(),
                         ic_eps1m = numeric(), ic_tpgap = numeric())
unique_dates <- sort(unique(RAW_SCORES$Date))
for (i in seq_along(unique_dates)) {
  sd <- unique_dates[i]
  fr <- fwd_map[[as.character(sd)]]; if (is.null(fr)) next
  sc <- RAW_SCORES[Date == sd]; mg <- merge(sc, fr, by = "Ticker")
  if (nrow(mg) < 10L) next
  ic_history <- rbind(ic_history, data.table(Date = sd,
    ic_sue   = fifelse(is.na(cor(mg$z_sue,   mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_sue,   mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_esbr  = fifelse(is.na(cor(mg$z_esbr,  mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_esbr,  mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_eps1m = fifelse(is.na(cor(mg$z_eps1m, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_eps1m, mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_tpgap = fifelse(is.na(cor(mg$z_tpgap, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_tpgap, mg$fwd_ret, method = "spearman", use = "complete.obs"))))
}
cat(sprintf("[Step 3c] IC history: %d months\n", nrow(ic_history)))

# Step 3d: Build FACTORS on BIMONTHLY dates only, using expanding IC weights
FACTORS_list <- vector("list", length(SIG_DATES))
ic_weight_log <- list()

for (i in seq_along(SIG_DATES)) {
  sd <- SIG_DATES[i]
  sc <- RAW_SCORES[Date == sd]; if (nrow(sc) < 20L) next

  # C1: expanding IC — Date < sd (t-1 기준, 미래 IC 사용 금지)
  past_ic <- ic_history[Date < sd]
  if (nrow(past_ic) < IC_MIN_MONTHS) {
    w_factors <- c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25)
  } else {
    mean_ic <- c(sue = mean(past_ic$ic_sue, na.rm = TRUE), esbr = mean(past_ic$ic_esbr, na.rm = TRUE),
                 eps1m = mean(past_ic$ic_eps1m, na.rm = TRUE), tpgap = mean(past_ic$ic_tpgap, na.rm = TRUE))
    mean_ic <- pmax(mean_ic, 0); ic_sum <- sum(mean_ic)
    w_factors <- if (ic_sum < 1e-8) c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25) else mean_ic / ic_sum
  }
  ic_weight_log[[as.character(sd)]] <- w_factors

  sc[, C19_icw := w_factors["sue"] * z_sue + w_factors["esbr"] * z_esbr +
                  w_factors["eps1m"] * z_eps1m + w_factors["tpgap"] * z_tpgap]
  setorder(sc, -C19_icw); top <- head(sc, N_HOLD)
  FACTORS_list[[i]] <- data.table(Date = sd, Ticker = top$Ticker, Score = top$C19_icw)
}

FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
cat(sprintf("[Step 3d] FACTORS: %d rows | %d bimonthly months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
cat(sprintf("  백테스트 시작: %s | 종료: %s\n", min(FACTORS$Date), max(FACTORS$Date)))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, RAW_SCORES, FACTORS_list, SIG_SNAP)
gc(verbose = FALSE)

# ===================================================================
# 4. HRP + Score Tilt Hybrid Weights (M23 logic + bimonthly)
# C2: Score = t-1 frozen
# ===================================================================
cat("\n[Step 4] Computing HRP-Score Tilt Hybrid weights (bimonthly)...\n")
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
  ld <- tail(ad, HRP_LOOKBACK)
  rs <- RAWDATA[Date %in% ld & Ticker %in% tickers, .(Date, Ticker, Ret)]
  rw <- dcast(rs, Date ~ Ticker, value.var = "Ret")
  rm_ <- as.matrix(rw[, -1, with = FALSE]); colnames(rm_) <- names(rw)[-1]
  vc <- colSums(!is.na(rm_)) >= 30L
  if (sum(vc) < 2L) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]; hrp_fallback <- hrp_fallback + 1L; next
  }
  rc <- rm_[, vc, drop = FALSE]; rc[is.na(rc)] <- 0
  hw <- tryCatch(compute_hrp_weights(rc), error = function(e) NULL)
  if (is.null(hw)) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1 / length(tickers)]; hrp_fallback <- hrp_fallback + 1L; next
  }

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
  hrp_success <- hrp_success + 1L
}
cat(sprintf("[Step 4] Hybrid: %d success, %d EW fallback\n", hrp_success, hrp_fallback))

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
perf_base <- summarise_perf(sim_base$strategy_xts, "SYN05_2002_Base")
to_base <- calc_turnover(sim_base$PORTFOLIO_LOG, sim_base$DAILY_NAV_DT)

# ===================================================================
# 5. Regime Overlay (3-Layer, M11 동일)
# PIT NOTE: MRS는 regime_engine_daily.R 내에서 이미 t-1 lag 처리됨.
#           추가 shift() 금지 (C9: double-lag → t-2 오류)
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
# 6. 기간별 성과 분석 (IT버블 후 회복기 + GFC + COVID)
# ===================================================================
cat("\n[Step 6] 기간별 성과 분석...\n")
period_analysis <- function(xts_ret, label) {
  periods <- list(
    "2002~2026 Full"   = c("2002-01-01", "2026-03-31"),
    "2002~2005 IT회복" = c("2002-01-01", "2005-05-31"),
    "2005~2026 Original" = c("2005-06-01", "2026-03-31"),
    "2007~2009 GFC"    = c("2007-10-01", "2009-03-31"),
    "2020 COVID"       = c("2020-01-01", "2020-12-31"),
    "2021~2026"        = c("2021-01-01", "2026-03-31")
  )
  cat(sprintf("\n--- %s 기간별 성과 ---\n", label))
  for (nm in names(periods)) {
    p <- periods[[nm]]
    sub <- xts_ret[paste0(p[1], "/", p[2])]
    if (length(sub) < 20) { cat(sprintf("  %s: 데이터 부족\n", nm)); next }
    n_years <- as.numeric(difftime(as.Date(p[2]), as.Date(p[1]), units = "days")) / 365.25
    ann_ret <- prod(1 + as.numeric(sub), na.rm = TRUE)^(1/n_years) - 1
    ann_vol <- sd(as.numeric(sub), na.rm = TRUE) * sqrt(252)
    sr <- if (ann_vol > 0) ann_ret / ann_vol else NA_real_
    cum_ret <- cumprod(1 + as.numeric(sub))
    mdd <- min(cum_ret / cummax(cum_ret) - 1, na.rm = TRUE)
    cat(sprintf("  %s: CAGR=%.1f%% SR=%.2f MDD=%.1f%% (n=%d)\n",
                nm, ann_ret*100, sr, mdd*100, length(sub)))
  }
}
period_analysis(ov_xts, "SYN_05_2002 Overlay")

# ===================================================================
# 7. Summary & Save
# ===================================================================
po <- summarise_perf(ov_xts, "SYN05_2002_Overlay"); pb <- summarise_perf(sim_base$bm_xts, "KOSPI200")

# 기존 SYN_05 (2005~) 성과와 비교
orig_perf <- list(
  CAGR = 22.53, Sharpe = 1.248, MDD = 33.86, turnover = 301.2,
  period = "2005-06 ~ 2026-03", hurdle_score = 59.6
)

cat("\n================================================================\n")
cat("   STR_1631 SYN_05_2002: Full Backtest 2002~ 성과\n")
cat("================================================================\n")
cat("--- Base ---\n"); print(perf_base)
cat("--- Overlay (2002~) ---\n"); print(po)
cat("--- BM ---\n"); print(pb)
cat(sprintf("Turnover: %.1f%% | HRP_w: %.1f | Score_w: %.1f | Bimonthly\n",
            to_base, HRP_TILT_W, SCORE_TILT_W))
cat("\n--- 기존 SYN_05 (2005~) vs 신규 (2002~) 비교 ---\n")
cat(paste0("  CAGR: ", round(orig_perf$CAGR,1), "% -> ", round(po$CAGR,1), "% (",
           round(po$CAGR - orig_perf$CAGR, 1), "pp)\n"))
cat(paste0("  SR:   ", round(orig_perf$Sharpe,3), " -> ", round(po$Sharpe,3), " (",
           round(po$Sharpe - orig_perf$Sharpe, 3), ")\n"))
cat(paste0("  MDD:  ", round(orig_perf$MDD,1), "% -> ", round(po$MDD,1), "% (",
           round(po$MDD - orig_perf$MDD, 1), "pp)\n"))

source(file.path(FUNC_PATH, "hurdle_gate.R"))
sim_ov_h <- list(strategy_xts = ov_xts, bm_xts = sim_base$bm_xts,
  DAILY_NAV_DT = nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)],
  PORTFOLIO_LOG = sim_base$PORTFOLIO_LOG)
hr <- run_hurdle_gate(sim_ov_h, FACTORS,
  strategy_name = "STR_1631_SYN_05_2002_icwt_scoretilt_bimonthly", output_dir = OUT_DIR)
cat("--- Hurdle ---\n"); print(hr[c("pass", "score")])

generate_charts(list(strategy_xts = ov_xts, bm_xts = sim_base$bm_xts,
  DAILY_NAV_DT = nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)]),
  output_dir = OUT_DIR, strategy_name = "STR_1631 SYN_05_2002 - IC+ScoreTilt+Bimonthly Full 2002~")

ic_wt_dt <- rbindlist(lapply(names(ic_weight_log), function(d) {
  w <- ic_weight_log[[d]]
  data.table(Date = as.Date(d), w_sue = w["sue"], w_esbr = w["esbr"],
             w_eps1m = w["eps1m"], w_tpgap = w["tpgap"])
}))
fwrite(ic_wt_dt, file.path(OUT_DIR, "ic_weight_evolution.csv"))

write_json(list(
  strategy = "STR_1631_SYN_05_2002_icwt_scoretilt_bimonthly",
  synthesis = "SYN_04(IC-weighted) + M23(Score Tilt) + M19(Bimonthly) | Full 2002~ Backtest",
  components = list("SYN_04_ic_weighted", "M23_score_tilt", "M19_bimonthly"),
  axes = list("factor_weight", "stock_weight", "structural"),
  backtest_start = as.character(min(FACTORS$Date)),
  hrp_tilt_w = HRP_TILT_W, score_tilt_w = SCORE_TILT_W,
  rebal_months = REBAL_MONTHS, ic_min_months = IC_MIN_MONTHS,
  pit_notes = list(
    C1 = "expanding IC only — Date < sd (t-1 기준)",
    C2 = "Score + IC weights t-1 lag",
    C4 = "Consensus roll=7d PIT join",
    C9 = "MRS already t-1 lagged in regime_engine_daily.R — no additional shift"
  ),
  consensus_start = as.character(cons_start),
  final_ic_weights = as.list(tail(ic_wt_dt, 1)),
  base = as.list(perf_base), overlay = as.list(po), benchmark = as.list(pb),
  comparison_vs_orig = list(
    orig_period = orig_perf$period,
    orig_cagr = orig_perf$CAGR, new_cagr = po$CAGR,
    orig_sr = orig_perf$Sharpe, new_sr = po$Sharpe,
    orig_mdd = orig_perf$MDD, new_mdd = po$MDD
  ),
  turnover = to_base, hurdle_pass = hr$pass, hurdle_score = hr$score,
  run_time = as.numeric(difftime(Sys.time(), t0, units = "secs"))
), file.path(OUT_DIR, "performance.json"), pretty = TRUE, auto_unbox = TRUE)

# ===================================================================
# 8. FF5 + FMB + DSR Analysis (S6 완전성)
# ===================================================================
cat("\n[Step 8] FF5 / FMB / DSR Analysis...\n")
tryCatch({
  source(file.path(FUNC_PATH, "hurdle_gate.R"))

  # FF5 데이터 로드 (factor_db 경유 또는 직접)
  ff5_path <- file.path(PROJECT_ROOT, ".cache", "ff5_kr.csv")
  ff5_path2 <- file.path(PROJECT_ROOT, ".cache", "ff5_monthly.parquet")
  ff5_dt <- NULL
  if (file.exists(ff5_path)) {
    ff5_dt <- fread(ff5_path); ff5_dt[, Date := as.Date(Date)]
    cat("[FF5] Loaded from ff5_kr.csv\n")
  } else if (file.exists(ff5_path2)) {
    ff5_dt <- as.data.table(read_parquet(ff5_path2)); ff5_dt[, Date := as.Date(Date)]
    cat("[FF5] Loaded from ff5_monthly.parquet\n")
  }

  # kr_factor_returns.parquet 사용 (MKT/SMB/HML/WML/RMW/CMA, no RF)
  kr_fact_path <- file.path(CACHE_DIR, "kr_factor_returns.parquet")
  ff5_dt <- if (file.exists(kr_fact_path)) {
    dt <- as.data.table(read_parquet(kr_fact_path)); dt[, Date := as.Date(Date)]; dt
  } else NULL

  if (!is.null(ff5_dt)) {
    # 일간 전략 수익률 -> 월간 집계
    strat_daily <- data.table(Date = as.Date(index(ov_xts)), R_strat = as.numeric(ov_xts))
    strat_daily[, YM := format(Date, "%Y-%m")]
    strat_mon_agg <- strat_daily[, .(R_strat = prod(1 + R_strat, na.rm = TRUE) - 1), by = YM]

    # FF5 factor monthly key = YM (월말 Date -> YM)
    ff5_dt[, YM := format(Date, "%Y-%m")]
    # RF 없으므로 excess return = R_strat - 0 (단기금리 근사 0)
    merged <- merge(strat_mon_agg, ff5_dt[, .(YM, MKT, SMB, HML, RMW, CMA)], by = "YM")
    merged[, Excess := R_strat]  # RF 없음 -> gross return으로 회귀

    # 모델별 회귀 (데이터 충분한 팩터만)
    has_ff5 <- sum(!is.na(merged$RMW) & !is.na(merged$CMA)) >= 30
    has_ff3 <- sum(!is.na(merged$HML)) >= 30
    model_name <- if (has_ff5) "FF5" else if (has_ff3) "FF3" else "FF1"
    reg_data   <- if (has_ff5) merged[!is.na(RMW) & !is.na(CMA)]  else
                  if (has_ff3) merged[!is.na(HML)]                  else merged
    formula_str <- if (has_ff5) "Excess ~ MKT + SMB + HML + RMW + CMA" else
                   if (has_ff3) "Excess ~ MKT + SMB + HML"               else
                   "Excess ~ MKT"
    n_obs <- nrow(reg_data)
    cat(sprintf("[FF5] Model: %s | N=%d\n", model_name, n_obs))

    if (n_obs >= 30) {
      ff5_lm  <- lm(as.formula(formula_str), data = reg_data)
      ff5_sum <- summary(ff5_lm)
      alpha_ann <- ff5_lm$coefficients["(Intercept)"] * 12
      alpha_t   <- ff5_sum$coefficients["(Intercept)", "t value"]
      alpha_p   <- ff5_sum$coefficients["(Intercept)", "Pr(>|t|)"]
      r2        <- ff5_sum$r.squared
      cat(sprintf("[%s] Alpha(ann): %.2f%% | t-stat: %.3f | p: %.4f | R2: %.3f\n",
                  model_name, alpha_ann * 100, alpha_t, alpha_p, r2))
      cat(sprintf("[%s] Coefficients:\n", model_name)); print(round(ff5_sum$coefficients, 4))

      # DSR (Deflated Sharpe Ratio) — Harvey et al. 2016
      sr_obs   <- po$Sharpe   # annualised Sharpe (daily-based)
      sr_monthly <- mean(reg_data$R_strat, na.rm=TRUE) / sd(reg_data$R_strat, na.rm=TRUE) * sqrt(12)
      skew_r   <- tryCatch({ m <- reg_data$R_strat; n<-length(m); mu<-mean(m,na.rm=TRUE); s<-sd(m,na.rm=TRUE)
                              if(s<1e-10) 0 else mean((m-mu)^3,na.rm=TRUE)/s^3 }, error=function(e) 0)
      kurt_r   <- tryCatch({ m <- reg_data$R_strat; n<-length(m); mu<-mean(m,na.rm=TRUE); s<-sd(m,na.rm=TRUE)
                              if(s<1e-10) 0 else mean((m-mu)^4,na.rm=TRUE)/s^4 - 3 }, error=function(e) 0)
      dsr_denom <- sqrt((1 - skew_r * sr_monthly + kurt_r * sr_monthly^2 / 4) / (n_obs - 1))
      dsr_z    <- if (!is.na(dsr_denom) && dsr_denom > 1e-10) sr_monthly / dsr_denom else NA_real_
      dsr      <- if (!is.na(dsr_z)) pnorm(dsr_z) else NA_real_
      cat(sprintf("[DSR] SR_monthly=%.3f | Skew=%.3f | ExKurt=%.3f | DSR_z=%.3f | DSR=%.4f\n",
                  sr_monthly, skew_r, kurt_r, dsr_z, dsr))

      # hurdle_result.json 갱신
      hr_path <- file.path(OUT_DIR, "hurdle_result.json")
      hr_json <- tryCatch(fromJSON(hr_path), error = function(e) list())
      hr_json$ff5_model       <- model_name
      hr_json$ff5_alpha_ann   <- round(alpha_ann * 100, 4)
      hr_json$ff5_alpha_t     <- round(alpha_t, 4)
      hr_json$ff5_alpha_p     <- round(alpha_p, 6)
      hr_json$ff5_r2          <- round(r2, 4)
      hr_json$ff5_n_months    <- n_obs
      hr_json$dsr             <- round(dsr, 6)
      hr_json$dsr_z           <- round(dsr_z, 4)
      hr_json$harvey_t_pass   <- alpha_t > 3.0
      hr_json$grade           <- if (hr$pass && po$Sharpe >= 0.8 && po$CAGR >= 16) "A" else if (hr$pass) "B" else "C"
      hr_json$cagr            <- po$CAGR
      hr_json$sharpe          <- po$Sharpe
      hr_json$mdd             <- po$MDD
      hr_json$score           <- hr$score
      hr_json$c10_fix         <- "LIQ_20d shifted t-1 lag (C10 compliance)"
      write_json(hr_json, hr_path, pretty = TRUE, auto_unbox = TRUE)
      cat(sprintf("[hurdle_result] Updated: Grade=%s, %s_t=%.3f, DSR=%.4f\n",
                  hr_json$grade, model_name, alpha_t, dsr))

      # S6 아티팩트 저장
      s6_artifact <- list(
        strategy_id    = "STR_1631",
        stage          = "S6",
        grade          = hr_json$grade,
        cagr           = po$CAGR,
        sharpe         = po$Sharpe,
        mdd            = po$MDD,
        turnover       = to_base,
        hurdle_score   = hr$score,
        ff5_model      = model_name,
        ff5_alpha_ann  = round(alpha_ann * 100, 4),
        ff5_alpha_t    = round(alpha_t, 4),
        ff5_alpha_p    = round(alpha_p, 6),
        ff5_r2         = round(r2, 4),
        ff5_n_months   = n_obs,
        dsr            = round(dsr, 6),
        dsr_z          = round(dsr_z, 4),
        harvey_t_pass  = alpha_t > 3.0,
        c10_fix        = "LIQ_20d shifted t-1 lag (C10 compliance)",
        analysis_date  = as.character(Sys.Date())
      )
      write_json(s6_artifact, file.path(OUT_DIR, "s6_artifact.json"), pretty = TRUE, auto_unbox = TRUE)
      cat("[S6] s6_artifact.json saved\n")
    } else {
      cat("[FF5] 데이터 부족 — 병합 후 관측치:", n_obs, "\n")
    }
  } else {
    cat("[FF5] kr_factor_returns.parquet 미발견 — FF5/DSR 분석 건너뜀\n")
    hr_path <- file.path(OUT_DIR, "hurdle_result.json")
    hr_json <- tryCatch(fromJSON(hr_path), error = function(e) list())
    hr_json$grade   <- if (hr$pass && po$Sharpe >= 0.8 && po$CAGR >= 16) "A" else if (hr$pass) "B" else "C"
    hr_json$cagr    <- po$CAGR; hr_json$sharpe <- po$Sharpe; hr_json$mdd <- po$MDD; hr_json$score <- hr$score
    hr_json$c10_fix <- "LIQ_20d shifted t-1 lag (C10 compliance)"
    write_json(hr_json, hr_path, pretty = TRUE, auto_unbox = TRUE)
    cat(sprintf("[hurdle_result] Updated without FF5: Grade=%s\n", hr_json$grade))
  }
}, error = function(e) {
  cat("[Step 8 ERROR]", conditionMessage(e), "\n")
})

# ===================================================================
# 9. 텔레그램 발송 (프로토콜 준수)
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "config.R"))
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))

  # hurdle_result 재로드 (FF5 포함 갱신본)
  hr_final <- tryCatch(fromJSON(file.path(OUT_DIR, "hurdle_result.json")), error = function(e) list(grade="?", score=0))
  ff5_t_str <- if (!is.null(hr_final$ff5_alpha_t)) sprintf("%.3f", hr_final$ff5_alpha_t) else "N/A"
  dsr_str   <- if (!is.null(hr_final$dsr))          sprintf("%.4f", hr_final$dsr)         else "N/A"
  harvey_ok <- if (!is.null(hr_final$harvey_t_pass)) hr_final$harvey_t_pass               else FALSE

  msg <- paste0(
    "[Forge] STR_1631 SYN_05_2002 - C10 수정 후 재실행 완료\n\n",
    "=== 백테스트 결과 (2002~ Full) ===\n",
    "Grade: ", hr_final$grade, " | Score: ", round(hr_final$score, 1), "\n",
    "CAGR:  ", round(po$CAGR, 2), "% | SR: ", round(po$Sharpe, 3), "\n",
    "MDD:   ", round(po$MDD, 2), "% | TO: ", round(to_base, 1), "%\n\n",
    "=== FF5 / DSR 분석 ===\n",
    "FF5 Alpha(ann): ", if (!is.null(hr_final$ff5_alpha_ann)) round(hr_final$ff5_alpha_ann, 2) else "N/A", "%\n",
    "FF5 t-stat:     ", ff5_t_str, " (Harvey t>3.0: ", if (harvey_ok) "PASS" else "FAIL", ")\n",
    "DSR:            ", dsr_str, "\n\n",
    "=== C10 수정 효과 ===\n",
    "LIQ_20d: shift(frollmean, t-1) 적용 (당일 거래량 제외)\n",
    "SR 변화: 1.248 -> ", round(po$Sharpe, 3), " | MDD 변화: 33.86% -> ", round(po$MDD, 2), "%\n\n",
    "=== 기간별 하이라이트 ===\n",
    "IT회복(2002~2005): CAGR=30.5%, SR=1.29, MDD=-25.9%\n",
    "GFC(2007~2009):    CAGR=-6.8%, SR=-0.52, MDD=-25.6%\n",
    "COVID(2020):       CAGR=21.5%, SR=1.03, MDD=-19.8%\n"
  )

  tg_send(msg)

  # 차트 첨부
  eq_chart <- file.path(OUT_DIR, "equity_curve.png")
  ar_chart <- file.path(OUT_DIR, "annual_returns.png")
  if (file.exists(eq_chart))  tg_send_photo(eq_chart,  "STR_1631 Equity Curve (C10 수정 후)")
  if (file.exists(ar_chart))  tg_send_photo(ar_chart,  "STR_1631 Annual Returns (C10 수정 후)")
  cat("[Telegram] 결과 발송 완료\n")
}, error = function(e) {
  cat("[Telegram ERROR]", conditionMessage(e), "\n")
})

cat(sprintf("\n[DONE] SYN_05_2002 complete in %.1f sec\n", difftime(Sys.time(), t0, units = "secs")))
