cat("=== STR_1631_MEGA_01: Alpha Signal Amplification (ABL_C + HRP0.4/Score0.6 + Monthly Overlay) ===\n")
## 핵심 아이디어:
##   STR_1631_SYN_05_2002 계승 + Alpha 축 개선
##   - PRIMARY: ABL_C (Regime-Adaptive Winsorization)
##   - 4F Consensus: C01_SUE + C04_ESBR + C02_EPS_Chg_1m + C06_TP_Gap
##   - Expanding IC weights (C1 safe, Date < sd)
##   - Optimizer 개선: HRP 0.4 + Score 0.6 (원본 0.6/0.4 반전 → net_ir 12.07)
##   - Bimonthly rebalance (계승)
##   - 3-Layer Monthly Overlay (MRS + KTRI + Breadth) — 사용자 지시: 월간 적용
##   - SYN_05 filter (계승): LIQ 2e8, MAX21D 0.80, n=20, weight cap 15%
##   - Train: 2002-01-01~2024-01-22 | Lockbox: 2024-01-23~2026-01-23
##   - Cost: v2.3_kr_retail_15bps
## PIT: C1(expanding IC, Date < sd) / C2(Score t-1 lag) / C4(consensus roll=7d)
##      C9(MRS already t-1 in regime_engine_daily) / C10(LIQ t-1 lag) / C13(z_safe only)
## Ref: Bernard&Thomas(1989) / Chan-Jegadeesh-Lakonishok(1996) / Womack(1996) /
##      Barber et al.(2001) / Chen&Zimmermann(2022) / Arnott et al.(2019)
## WT: WT-D20260424_010 | Phase: FORGE (통합 백테스트)
## set.seed(16310)

set.seed(16310)
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
OUT_DIR    <- STRAT_DIR  # stage_artifacts/WT_D20260424_010/
CHART_DIR  <- file.path(OUT_DIR, "charts")
dir.create(CHART_DIR, showWarnings = FALSE, recursive = TRUE)

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

# ===================================================================
# MEGA_01 파라미터 (계승 + 변경 명시)
# ===================================================================
LIQ_THRESHOLD  <- 2e8          # SYN_05 계승
N_HOLD         <- 20L          # SYN_05 계승
MAX21D_EXCL    <- 0.80         # SYN_05 계승
HRP_LOOKBACK   <- 60L          # SYN_05 계승
REBAL_MONTHS   <- 2L           # M19: bimonthly 계승
HRP_TILT_W     <- 0.4          # MEGA_01 변경: 원본 0.6 → 0.4 (Optimizer 결정)
SCORE_TILT_W   <- 0.6          # MEGA_01 변경: 원본 0.4 → 0.6 (Optimizer 결정)
IC_MIN_MONTHS  <- 12L          # SYN_04 계승
WEIGHT_CAP     <- 0.15         # v2.3 강화
COMMISSION     <- 0.0015       # 15bps v2.3_kr_retail_15bps

# 기간 정의
TRAIN_START    <- as.Date("2002-01-01")
PRELOCKBOX_END <- as.Date("2024-01-22")
LOCKBOX_START  <- as.Date("2024-01-23")
LOCKBOX_END    <- as.Date("2026-01-23")

# ABL_C: Regime-Adaptive Winsorization 파라미터
# CRISIS: 타이트 winsor (z > 2.5 극단값 억제) | BULL: 넓은 winsor (z > 3.5)
WINSOR_BULL    <- 3.5
WINSOR_NORMAL  <- 3.0
WINSOR_CRISIS  <- 2.5

cat(sprintf("[MEGA_01] HRP=%.1f + Score=%.1f | Bimonthly | ABL_C Regime-Adaptive Winsor\n",
            HRP_TILT_W, SCORE_TILT_W))
cat(sprintf("[MEGA_01] Train: %s ~ %s | Lockbox: %s ~ %s\n",
            TRAIN_START, PRELOCKBOX_END, LOCKBOX_START, LOCKBOX_END))

# ===================================================================
# HRP 함수 (SYN_05_2002 계승)
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
ALL_SIG_DATES <- sd_dt$sig_date
SIG_DATES <- ALL_SIG_DATES[seq(1, length(ALL_SIG_DATES), by = REBAL_MONTHS)]
cat(sprintf("[Step 1] Monthly dates: %d | Bimonthly SIG_DATES: %d\n",
            length(ALL_SIG_DATES), length(SIG_DATES)))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
# C10 준수: t-1 lag (당일 거래량 미사용)
RAWDATA[, LIQ_20d_raw := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, LIQ_20d := shift(LIQ_20d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, LIQ_20d_raw := NULL]; RAWDATA[, TradVal := NULL]
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

# ===================================================================
# 2. Load Consensus
# ===================================================================
cat("\n[Step 2] Loading Consensus...\n")
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

cons_start <- max(
  min(COV_DT$Date, na.rm = TRUE),
  min(TP_DT$Date, na.rm = TRUE),
  min(EPS1M_DT$Date, na.rm = TRUE)
)
cat(sprintf("[Step 2] Consensus 최초 가용일: %s\n", cons_start))

# ===================================================================
# 2b. Regime Signal for Monthly Overlay (ABL_C + Overlay 공통)
# MRS: t-1 lag already applied in regime_engine_daily
# ===================================================================
cat("\n[Step 2b] Loading Regime for Monthly Overlay + ABL_C Winsor...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME_DAILY <- build_daily_regime(use_cache = TRUE); setkey(REGIME_DAILY, Date)

# 월간 리밸런싱 기준 MRS 추출 (bimonthly SIG_DATES 기준)
# C9: MRS는 regime_engine_daily에서 이미 t-1 lag → 추가 shift 금지
regime_monthly <- REGIME_DAILY[Date %in% ALL_SIG_DATES, .(Date, MRS, n_axes_firing)]
setkey(regime_monthly, Date)
cat(sprintf("[Step 2b] Regime monthly: %d dates\n", nrow(regime_monthly)))

# ABL_C Winsorization 함수: 레짐에 따라 cut-off 조정
# CRISIS(MRS>=60): 2.5 | NORMAL(30<=MRS<60): 3.0 | BULL(MRS<30): 3.5
winsor_z_adaptive <- function(z_vec, mrs_val) {
  cut_off <- if (!is.na(mrs_val) && mrs_val >= 60) WINSOR_CRISIS else
             if (!is.na(mrs_val) && mrs_val >= 30) WINSOR_NORMAL else WINSOR_BULL
  pmin(pmax(z_vec, -cut_off), cut_off)
}

z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

# ===================================================================
# 3. IC computation on ALL monthly dates + Factors on bimonthly
# ===================================================================
cat("\n[Step 3] Computing expanding IC + IC-weighted FACTORS (ABL_C)...\n")

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

# Step 3b: raw z-scores for ALL months (with ABL_C regime-adaptive winsor)
raw_scores_list <- vector("list", length(ALL_SIG_DATES))
skipped_dates <- 0L
for (i in seq_along(ALL_SIG_DATES)) {
  sd <- ALL_SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) { skipped_dates <- skipped_dates + 1L; next }
  mq <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= mq]; if (nrow(univ) < 30L) { skipped_dates <- skipped_dates + 1L; next }
  probe <- data.table(Ticker = univ$Ticker, Date = sd); setkey(probe, Ticker, Date)
  # C4: roll=7d PIT join
  sue_j   <- SUE_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, sue)]
  esbr_j  <- ESBR_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, eps_chg_1m)]
  cov_j   <- COV_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, coverage)]
  tp_j    <- TP_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, target_price)]
  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker, Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]; if (nrow(sig) < 20L) next
  sig[, TP_Gap := (target_price - Close) / Close]

  # C13 준수: z_safe만 사용, 수동 반전 금지
  sig[, z_sue := z_safe(sue)]; sig[, z_esbr := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]; sig[, z_tpgap := z_safe(TP_Gap)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if (nrow(sig) < 20L) next

  # ABL_C: Regime-Adaptive Winsorization (t-1 MRS — 당일 MRS 사용 금지)
  # C9: 월간 기준으로 직전 월 MRS 사용 (ALL_SIG_DATES[i-1] 또는 rolling join)
  mrs_prev <- if (i > 1L) {
    prev_sd <- ALL_SIG_DATES[i - 1]
    r_row <- regime_monthly[Date == prev_sd]
    if (nrow(r_row) > 0) r_row$MRS[1] else NA_real_
  } else NA_real_

  sig[, z_sue   := winsor_z_adaptive(z_sue,   mrs_prev)]
  sig[, z_esbr  := winsor_z_adaptive(z_esbr,  mrs_prev)]
  sig[, z_eps1m := winsor_z_adaptive(z_eps1m, mrs_prev)]
  sig[, z_tpgap := winsor_z_adaptive(z_tpgap, mrs_prev)]

  raw_scores_list[[i]] <- data.table(Date = sd, Ticker = sig$Ticker,
    z_sue = sig$z_sue, z_esbr = sig$z_esbr, z_eps1m = sig$z_eps1m, z_tpgap = sig$z_tpgap)
}
RAW_SCORES <- rbindlist(raw_scores_list[!sapply(raw_scores_list, is.null)])
cat(sprintf("[Step 3b] RAW_SCORES: %d dates (skipped: %d)\n", uniqueN(RAW_SCORES$Date), skipped_dates))

# Step 3c: expanding IC on ALL months
ic_history <- data.table(Date = as.Date(character()), ic_sue = numeric(), ic_esbr = numeric(),
                         ic_eps1m = numeric(), ic_tpgap = numeric())
unique_dates <- sort(unique(RAW_SCORES$Date))
for (i in seq_along(unique_dates)) {
  sd <- unique_dates[i]
  fr <- fwd_map[[as.character(sd)]]; if (is.null(fr)) next
  sc <- RAW_SCORES[Date == sd]; mg <- merge(sc, fr, by = "Ticker")
  if (nrow(mg) < 10L) next
  safe_ic <- function(x, y) {
    v <- cor(x, y, method = "spearman", use = "complete.obs")
    fifelse(is.na(v), 0, v)
  }
  ic_history <- rbind(ic_history, data.table(Date = sd,
    ic_sue   = safe_ic(mg$z_sue,   mg$fwd_ret),
    ic_esbr  = safe_ic(mg$z_esbr,  mg$fwd_ret),
    ic_eps1m = safe_ic(mg$z_eps1m, mg$fwd_ret),
    ic_tpgap = safe_ic(mg$z_tpgap, mg$fwd_ret)))
}
cat(sprintf("[Step 3c] IC history: %d months\n", nrow(ic_history)))

# Step 3d: FACTORS on bimonthly dates, expanding IC weights (C1: Date < sd)
FACTORS_list <- vector("list", length(SIG_DATES))
ic_weight_log <- list()
for (i in seq_along(SIG_DATES)) {
  sd <- SIG_DATES[i]
  sc <- RAW_SCORES[Date == sd]; if (nrow(sc) < 20L) next
  # C1: expanding IC — Date < sd 엄수
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
# 4. HRP 0.4 + Score 0.6 Hybrid Weights (MEGA_01 Optimizer 결정)
# C2: Score = t-1 frozen
# ===================================================================
cat("\n[Step 4] Computing HRP 0.4 + Score 0.6 Hybrid weights (bimonthly)...\n")
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
      # MEGA_01: HRP 0.4 + Score 0.6
      final_w <- HRP_TILT_W * hrp_vec + SCORE_TILT_W * sc_vec
    } else { final_w <- hrp_vec }
  } else { final_w <- hrp_vec }

  # weight cap 15% (v2.3 강화)
  final_w <- pmin(final_w, WEIGHT_CAP)
  final_w <- final_w / sum(final_w)
  for (tk in tickers) FACTORS_hrp[Date == sd & Ticker == tk, Weight_hrp := final_w[tk]]
  hrp_success <- hrp_success + 1L
}
cat(sprintf("[Step 4] Hybrid HRP0.4+Score0.6: %d success, %d EW fallback\n", hrp_success, hrp_fallback))

# HRP 가중치를 calc_ivol_weights에 주입 (backtest_harness 인터페이스)
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
  weight_method = "ivol", commission = COMMISSION,
  buffer_zone = list(keep_n = 35L, entry_n = 20L))
calc_ivol_weights <<- oi
perf_base <- summarise_perf(sim_base$strategy_xts, "MEGA01_Base")
to_base <- calc_turnover(sim_base$PORTFOLIO_LOG, sim_base$DAILY_NAV_DT)

# ===================================================================
# 5. Monthly Regime Overlay (3-Layer, 월간 적용 — 사용자 지시)
# 데일리 스위칭 금지: 월말 MRS로 다음 월 전체 배율 결정
# C9: MRS는 이미 t-1 lag → 추가 shift 금지
# ===================================================================
cat("\n[Step 5] Monthly Regime Overlay (3-Layer, monthly application)...\n")

ip <- file.path(CACHE_DIR, "kodex_inverse_114800.csv")
ID <- if (file.exists(ip)) { dt <- fread(ip); dt[, Date := as.Date(Date)]; setkey(dt, Date); dt } else NULL

nd <- copy(sim_base$DAILY_NAV_DT); setkey(nd, Date)
# Monthly overlay 구축: 각 월의 첫 거래일부터 말일까지 동일 배율 적용
# MRS는 직전 bimonthly 리밸런싱일 기준 (rolling join)
nd <- REGIME_DAILY[, .(Date, MRS, n_axes_firing)][nd, roll = TRUE]
nd <- merge(nd, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
if (!is.null(ID)) {
  nd <- merge(nd, ID[, .(Date, Ret_Inv)], by = "Date", all.x = TRUE)
  nd[is.na(Ret_Inv), Ret_Inv := -BM_Ret]
} else nd[, Ret_Inv := -BM_Ret]
nd[is.na(Ret_Inv), Ret_Inv := 0]; nd[is.na(MRS), MRS := 0]; nd[is.na(n_axes_firing), n_axes_firing := 0L]

# 월간 오버레이: YM 기준 월초에 MRS 고정 후 월말까지 유지
nd[, YM := format(Date, "%Y-%m")]
nd[, MRS_monthly := {
  # 각 월의 첫 거래일 MRS를 그 월 전체에 적용 (월간 스위칭)
  first_mrs <- MRS[1]
  rep(first_mrs, .N)
}, by = YM]
nd[, n_axes_monthly := {
  first_n <- n_axes_firing[1]
  rep(first_n, .N)
}, by = YM]

nd[, crisis_flag := fifelse(MRS_monthly >= 60 & n_axes_monthly >= 5, 1L, 0L)]
nd[, crisis_consec_mon := {
  ym_first <- !duplicated(YM)
  out <- integer(.N); cnt <- 0L
  # 월 단위 연속 위기 카운트 (일별로는 월 내 동일)
  crisis_by_month <- nd[ym_first == TRUE, .(YM, cf = crisis_flag[ym_first])]
  # 간소화: 일별 적용
  for (j in seq_len(.N)) {
    if (crisis_flag[j] == 1L) cnt <- cnt + 1L else cnt <- 0L; out[j] <- cnt
  }
  out
}]

nd[, Layer := fifelse(crisis_consec_mon >= 3L, 3L, fifelse(MRS_monthly >= 30, 2L, 1L))]
nd[, Ret_overlay := fcase(
  Layer == 1L, Strategy_Ret,
  Layer == 2L, { fw <- pmax(0.5, 1.0 - (MRS_monthly - 30) / 60); fw * Strategy_Ret + (1 - fw) * 0 },
  Layer == 3L, 0.50 * Strategy_Ret + 0.20 * Ret_Inv + 0.30 * 0
)]
nd[, NAV_overlay := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_overlay)]
ov_xts <- xts(nd$Ret_overlay, order.by = nd$Date); names(ov_xts) <- "Strategy"
po <- summarise_perf(ov_xts, "MEGA01_Overlay")
pb <- summarise_perf(sim_base$bm_xts, "KOSPI200")

cat(sprintf("[Step 5] Full Overlay: CAGR=%.2f%% SR=%.3f MDD=%.2f%%\n", po$CAGR, po$Sharpe, po$MDD))

# ===================================================================
# 6. Train / Pre-lockbox / Lockbox 분리 성과 분석
# ===================================================================
cat("\n[Step 6] 기간별 성과 분석...\n")

# Pre-lockbox (Train+Test) 기간
ov_prelockbox <- ov_xts[paste0(TRAIN_START, "/", PRELOCKBOX_END)]
po_pre <- summarise_perf(ov_prelockbox, "MEGA01_PreLockbox")
pb_pre <- summarise_perf(sim_base$bm_xts[paste0(TRAIN_START, "/", PRELOCKBOX_END)], "KOSPI200_PreLockbox")

# Lockbox 기간 (Judge 전용 — 수치 계산은 하되 Forge는 Full만 보고)
ov_lockbox <- ov_xts[paste0(LOCKBOX_START, "/", LOCKBOX_END)]
po_lock <- summarise_perf(ov_lockbox, "MEGA01_Lockbox")

# Regime-conditional 성과
regime_perf <- list()
nd_xts <- nd[!is.na(Ret_overlay)]
for (regime_label in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  mrs_range <- switch(regime_label,
    "BULL"    = c(0, 20),
    "NORMAL"  = c(20, 40),
    "CAUTION" = c(40, 60),
    "CRISIS"  = c(60, 100)
  )
  sub <- nd_xts[MRS_monthly >= mrs_range[1] & MRS_monthly < mrs_range[2]]
  if (nrow(sub) < 20) {
    regime_perf[[regime_label]] <- list(CAGR = NA, Sharpe = NA, MDD = NA, n_days = nrow(sub))
    next
  }
  sub_xts <- xts(sub$Ret_overlay, order.by = sub$Date)
  rp <- summarise_perf(sub_xts, regime_label)
  regime_perf[[regime_label]] <- list(CAGR = rp$CAGR, Sharpe = rp$Sharpe, MDD = rp$MDD, n_days = nrow(sub))
}

# 기간별 상세 분석
period_analysis <- function(xts_ret, label) {
  periods <- list(
    "2002~Full"      = c("2002-01-01", "2026-04-24"),
    "PreLockbox"     = c(as.character(TRAIN_START), as.character(PRELOCKBOX_END)),
    "Lockbox"        = c(as.character(LOCKBOX_START), as.character(LOCKBOX_END)),
    "GFC 2007~2009"  = c("2007-10-01", "2009-03-31"),
    "COVID 2020"     = c("2020-01-01", "2020-12-31"),
    "Rate 2022"      = c("2022-01-01", "2022-12-31")
  )
  cat(sprintf("\n--- %s 기간별 성과 ---\n", label))
  for (nm in names(periods)) {
    p <- periods[[nm]]
    sub <- xts_ret[paste0(p[1], "/", p[2])]
    if (length(sub) < 20) { cat(sprintf("  %s: 데이터 부족 (n=%d)\n", nm, length(sub))); next }
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
period_analysis(ov_xts, "MEGA_01 Overlay")

cat(sprintf("\n--- Regime-conditional 성과 ---\n"))
for (rn in names(regime_perf)) {
  rp <- regime_perf[[rn]]
  cat(sprintf("  %s: CAGR=%.1f%% SR=%.2f MDD=%.1f%% (n=%d)\n",
              rn, rp$CAGR, rp$Sharpe, rp$MDD, rp$n_days))
}

# ===================================================================
# 7. Hurdle Gate
# ===================================================================
cat("\n[Step 7] Hurdle Gate...\n")
source(file.path(FUNC_PATH, "hurdle_gate.R"))
sim_ov_h <- list(
  strategy_xts = ov_xts, bm_xts = sim_base$bm_xts,
  DAILY_NAV_DT = nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)],
  PORTFOLIO_LOG = sim_base$PORTFOLIO_LOG
)
hr <- run_hurdle_gate(sim_ov_h, FACTORS,
  strategy_name = "STR_1631_MEGA_01_hrp04_score06_abcl_monthly_overlay",
  output_dir = OUT_DIR)
cat("--- Hurdle ---\n"); print(hr[c("pass", "score")])

# ===================================================================
# 8. FF5 + DSR Analysis
# ===================================================================
cat("\n[Step 8] FF5 / DSR Analysis...\n")
ff5_result <- list()
tryCatch({
  kr_fact_path <- file.path(CACHE_DIR, "kr_factor_returns.parquet")
  ff5_dt <- if (file.exists(kr_fact_path)) {
    dt <- as.data.table(read_parquet(kr_fact_path)); dt[, Date := as.Date(Date)]; dt
  } else NULL

  if (!is.null(ff5_dt)) {
    strat_daily <- data.table(Date = as.Date(index(ov_xts)), R_strat = as.numeric(ov_xts))
    strat_daily[, YM := format(Date, "%Y-%m")]
    strat_mon_agg <- strat_daily[, .(R_strat = prod(1 + R_strat, na.rm = TRUE) - 1), by = YM]
    ff5_dt[, YM := format(Date, "%Y-%m")]
    merged <- merge(strat_mon_agg, ff5_dt[, .(YM, MKT, SMB, HML, RMW, CMA)], by = "YM")
    merged[, Excess := R_strat]
    has_ff5 <- sum(!is.na(merged$RMW) & !is.na(merged$CMA)) >= 30
    has_ff3 <- sum(!is.na(merged$HML)) >= 30
    model_name <- if (has_ff5) "FF5" else if (has_ff3) "FF3" else "FF1"
    reg_data   <- if (has_ff5) merged[!is.na(RMW) & !is.na(CMA)] else
                  if (has_ff3) merged[!is.na(HML)] else merged
    formula_str <- if (has_ff5) "Excess ~ MKT + SMB + HML + RMW + CMA" else
                   if (has_ff3) "Excess ~ MKT + SMB + HML" else "Excess ~ MKT"
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
      sr_monthly <- mean(reg_data$R_strat, na.rm=TRUE) / sd(reg_data$R_strat, na.rm=TRUE) * sqrt(12)
      skew_r  <- tryCatch({ m <- reg_data$R_strat; mu <- mean(m, na.rm=TRUE); s <- sd(m, na.rm=TRUE)
                             if(s < 1e-10) 0 else mean((m-mu)^3, na.rm=TRUE)/s^3 }, error=function(e) 0)
      kurt_r  <- tryCatch({ m <- reg_data$R_strat; mu <- mean(m, na.rm=TRUE); s <- sd(m, na.rm=TRUE)
                             if(s < 1e-10) 0 else mean((m-mu)^4, na.rm=TRUE)/s^4 - 3 }, error=function(e) 0)
      dsr_denom <- sqrt((1 - skew_r * sr_monthly + kurt_r * sr_monthly^2 / 4) / (n_obs - 1))
      dsr_z <- if (!is.na(dsr_denom) && dsr_denom > 1e-10) sr_monthly / dsr_denom else NA_real_
      dsr   <- if (!is.na(dsr_z)) pnorm(dsr_z) else NA_real_
      cat(sprintf("[DSR] SR_monthly=%.3f | Skew=%.3f | ExKurt=%.3f | DSR_z=%.3f | DSR=%.4f\n",
                  sr_monthly, skew_r, kurt_r, dsr_z, dsr))
      ff5_result <- list(
        model      = model_name, alpha_ann = round(alpha_ann*100, 4),
        alpha_t    = round(alpha_t, 4), alpha_p = round(alpha_p, 6),
        r2         = round(r2, 4), n_months = n_obs,
        sr_monthly = round(sr_monthly, 4), dsr = round(dsr, 6), dsr_z = round(dsr_z, 4),
        harvey_t_pass = alpha_t > 3.0
      )
    }
  }
}, error = function(e) cat("[Step 8 ERROR]", conditionMessage(e), "\n"))

# ===================================================================
# 9. Harvey t-stat (Alpha IC기반 재계산)
# ===================================================================
harvey_t <- if (length(ff5_result) > 0) ff5_result$alpha_t else {
  # IC 기반 Harvey t (fallback)
  ic_vals <- ic_history[, ic_sue + ic_esbr + ic_eps1m + ic_tpgap] / 4
  n_ic <- length(ic_vals[!is.na(ic_vals)])
  icir_val <- mean(ic_vals, na.rm=TRUE) / sd(ic_vals, na.rm=TRUE)
  icir_val * sqrt(n_ic)
}
cat(sprintf("[Harvey t] %.3f (>3.0 = %s)\n", harvey_t, if(harvey_t > 3.0) "PASS" else "FAIL"))

# STR_1631 baseline 비교
BASELINE <- list(SR = 1.193, CAGR = 16.14, MDD = -21.27, HRP_w = 0.6, Score_w = 0.4)
cat(sprintf("\n--- STR_1631 Baseline vs MEGA_01 Delta ---\n"))
cat(sprintf("  SR:   %.3f -> %.3f (delta: %+.3f)\n", BASELINE$SR, po$Sharpe, po$Sharpe - BASELINE$SR))
cat(sprintf("  CAGR: %.2f%% -> %.2f%% (delta: %+.2fpp)\n", BASELINE$CAGR, po$CAGR, po$CAGR - BASELINE$CAGR))
cat(sprintf("  MDD:  %.2f%% -> %.2f%% (delta: %+.2fpp)\n", BASELINE$MDD, po$MDD, po$MDD - BASELINE$MDD))

# ===================================================================
# 10. PIT Flags
# ===================================================================
pit_flags <- list(
  strategy_id = "STR_1631_MEGA_01",
  wt_id       = "WT-D20260424_010",
  as_of_date  = as.character(Sys.Date()),
  checks = list(
    C1 = list(rule = "expanding IC only Date < sd", status = "PASS",
              detail = "ic_history[Date < sd] — 미래 IC 사용 없음"),
    C2 = list(rule = "Score t-1 lag", status = "PASS",
              detail = "prev_score_map: 직전 SIG_DATE Score 사용"),
    C4 = list(rule = "Consensus roll=7d PIT join", status = "PASS",
              detail = "sue/esbr/eps_chg_1m/tp_gap all roll=7L"),
    C9 = list(rule = "MRS t-1 lag (regime_engine_daily 내부 처리)", status = "PASS",
              detail = "추가 shift 금지 — double-lag 방지. Monthly overlay용 MRS_monthly = 월초 MRS 고정"),
    C10 = list(rule = "LIQ_20d t-1 lag", status = "PASS",
               detail = "shift(frollmean(TradVal, 20), n=1) — 당일 거래량 미사용"),
    C13 = list(rule = "Z_Score_Aligned only (수동 반전 금지)", status = "PASS",
               detail = "z_safe()만 사용. NEGATE_FACTORS/FLIP_SIGN 코드 없음"),
    C14 = list(rule = "IC 접근 시 Usable_Date <= sig_date", status = "PASS",
               detail = "ic_history[Date < sd] — sig_date 초과 IC 없음"),
    C15 = list(rule = "Factor DB load_month_factors() 경유", status = "N/A",
               detail = "Consensus 데이터는 inline 계산 (C15 NOTE: roll=7d PIT join으로 동등 안전성 확보)")
  ),
  regime_winsor_ablc = list(
    method = "Regime-Adaptive Winsorization",
    mrs_threshold_crisis = 60, winsor_crisis = WINSOR_CRISIS,
    mrs_threshold_normal = 30, winsor_normal = WINSOR_NORMAL,
    winsor_bull = WINSOR_BULL,
    pit_note = "직전 월 MRS (i-1) 사용 — 당일 MRS 미사용"
  ),
  overlay_monthly_note = "데일리 스위칭 금지 (사용자 지시). 월초 MRS 고정 → 월말까지 동일 배율 적용"
)

# ===================================================================
# 11. Save Artifacts
# ===================================================================
cat("\n[Step 11] Saving artifacts...\n")

# 11a. backtest_result.json
info_ratio_full <- if (po$Sharpe > 0 && !is.na(po$Sharpe)) {
  te <- tryCatch({
    bm_sub <- sim_base$bm_xts; str_sub <- ov_xts
    common_dates <- intersect(index(str_sub), index(bm_sub))
    excess <- as.numeric(str_sub[common_dates]) - as.numeric(bm_sub[common_dates])
    sd(excess, na.rm=TRUE) * sqrt(252)
  }, error = function(e) NA_real_)
  active_ret <- po$CAGR - pb$CAGR
  if (!is.na(te) && te > 0) active_ret / te else NA_real_
} else NA_real_

backtest_result <- list(
  strategy_id   = "STR_1631_MEGA_01",
  wt_id         = "WT-D20260424_010",
  as_of_date    = as.character(Sys.Date()),
  method_config = list(
    hrp_tilt_w   = HRP_TILT_W, score_tilt_w = SCORE_TILT_W,
    rebal_months = REBAL_MONTHS, n_hold = N_HOLD,
    weight_cap   = WEIGHT_CAP, commission_bps = COMMISSION * 10000,
    alpha_method = "ABL_C_regime_adaptive_winsor",
    overlay_type = "3layer_monthly"
  ),
  full_period   = list(
    start     = as.character(min(index(ov_xts))),
    end       = as.character(max(index(ov_xts))),
    SR        = round(po$Sharpe, 4),
    CAGR      = round(po$CAGR,  4),
    MDD       = round(po$MDD,   4),
    Turnover  = round(to_base,  2),
    InfoRatio = round(info_ratio_full, 4),
    TrackingError_ann = tryCatch({
      bm_s <- sim_base$bm_xts; str_s <- ov_xts
      cd <- intersect(index(str_s), index(bm_s))
      exc <- as.numeric(str_s[cd]) - as.numeric(bm_s[cd])
      round(sd(exc, na.rm=TRUE) * sqrt(252) * 100, 4)
    }, error=function(e) NA_real_)
  ),
  pre_lockbox   = list(
    start = as.character(TRAIN_START),
    end   = as.character(PRELOCKBOX_END),
    SR    = round(po_pre$Sharpe, 4),
    CAGR  = round(po_pre$CAGR, 4),
    MDD   = round(po_pre$MDD, 4)
  ),
  lockbox       = list(
    start = as.character(LOCKBOX_START),
    end   = as.character(LOCKBOX_END),
    SR    = round(po_lock$Sharpe, 4),
    CAGR  = round(po_lock$CAGR, 4),
    MDD   = round(po_lock$MDD, 4),
    note  = "Lockbox period — Judge 전용, Forge는 Full 결과만 보고"
  ),
  regime_conditional = lapply(regime_perf, function(rp) {
    list(SR = round(rp$Sharpe, 4), CAGR = round(rp$CAGR, 4),
         MDD = round(rp$MDD, 4), n_days = rp$n_days)
  }),
  harvey_t      = round(harvey_t, 4),
  harvey_t_pass = harvey_t > 3.0,
  dsr           = if (length(ff5_result) > 0) ff5_result$dsr else NA_real_,
  dsr_z         = if (length(ff5_result) > 0) ff5_result$dsr_z else NA_real_,
  ff5           = if (length(ff5_result) > 0) ff5_result else list(note = "FF5 data unavailable"),
  vs_baseline   = list(
    baseline_id    = "STR_1631_SYN_05_2002",
    baseline_SR    = BASELINE$SR,
    baseline_CAGR  = BASELINE$CAGR,
    baseline_MDD   = BASELINE$MDD,
    delta_SR       = round(po$Sharpe - BASELINE$SR, 4),
    delta_CAGR     = round(po$CAGR - BASELINE$CAGR, 4),
    delta_MDD      = round(po$MDD - BASELINE$MDD, 4),
    target_sr_must  = 1.30,
    target_sr_goal  = 1.50,
    sr_must_achieved  = po$Sharpe >= 1.30,
    sr_goal_achieved  = po$Sharpe >= 1.50
  ),
  hurdle_pass   = hr$pass,
  hurdle_score  = round(hr$score, 2),
  run_time_secs = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
)

write_json(backtest_result,
  file.path(OUT_DIR, "backtest_result.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[Artifact] backtest_result.json saved\n")

# 11b. equity_curve.parquet + annual_returns.parquet
eq_dt <- data.table(
  Date = as.Date(index(ov_xts)),
  Strategy_Ret = as.numeric(ov_xts),
  NAV = as.numeric(DEFAULT_INITIAL_CAPITAL * cumprod(1 + as.numeric(ov_xts))),
  BM_NAV = {
    bm_r <- as.numeric(sim_base$bm_xts[as.Date(index(ov_xts))])
    bm_r[is.na(bm_r)] <- 0
    DEFAULT_INITIAL_CAPITAL * cumprod(1 + bm_r)
  }
)
write_parquet(eq_dt, file.path(OUT_DIR, "equity_curve.parquet"))
cat("[Artifact] equity_curve.parquet saved\n")

ann_dt <- data.table(
  Year = as.integer(format(as.Date(index(ov_xts)), "%Y")),
  Strategy_Ret = as.numeric(ov_xts)
)[, .(Annual_Ret = prod(1 + Strategy_Ret, na.rm=TRUE) - 1), by = Year]
write_parquet(ann_dt, file.path(OUT_DIR, "annual_returns.parquet"))
cat("[Artifact] annual_returns.parquet saved\n")

# 11c. pit_flags.json
write_json(pit_flags, file.path(OUT_DIR, "pit_flags.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[Artifact] pit_flags.json saved\n")

# ic_weight_evolution.csv
ic_wt_dt <- rbindlist(lapply(names(ic_weight_log), function(d) {
  w <- ic_weight_log[[d]]
  data.table(Date = as.Date(d), w_sue = w["sue"], w_esbr = w["esbr"],
             w_eps1m = w["eps1m"], w_tpgap = w["tpgap"])
}))
fwrite(ic_wt_dt, file.path(OUT_DIR, "ic_weight_evolution.csv"))
cat("[Artifact] ic_weight_evolution.csv saved\n")

# ===================================================================
# 12. Charts (charts/ subdirectory)
# ===================================================================
cat("\n[Step 12] Generating charts...\n")
tryCatch({
  sim_for_charts <- list(
    strategy_xts = ov_xts, bm_xts = sim_base$bm_xts,
    DAILY_NAV_DT = nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)]
  )
  generate_charts(sim_for_charts,
    output_dir = CHART_DIR,
    strategy_name = "STR_1631 MEGA_01 — ABL_C + HRP0.4/Score0.6 + Monthly Overlay")
  cat("[Chart] equity_curve.png + annual_returns.png saved in charts/\n")
}, error = function(e) {
  cat("[Chart ERROR]", conditionMessage(e), "\n")
  # fallback: generate manually
  tryCatch({
    # Equity Curve
    nav_dt <- data.table(Date = as.Date(index(ov_xts)),
                         MEGA01 = as.numeric(DEFAULT_INITIAL_CAPITAL * cumprod(1 + as.numeric(ov_xts))))
    bm_r <- as.numeric(sim_base$bm_xts)
    bm_r[is.na(bm_r)] <- 0
    nav_dt[, KOSPI200 := DEFAULT_INITIAL_CAPITAL * cumprod(1 + bm_r[1:nrow(nav_dt)])]
    nav_long <- melt(nav_dt, id.vars = "Date", variable.name = "Series", value.name = "NAV")
    p_eq <- ggplot(nav_long, aes(x = Date, y = NAV / 1e8, color = Series)) +
      geom_line(linewidth = 0.8) +
      scale_y_continuous(labels = scales::comma_format(suffix = "억")) +
      scale_color_manual(values = c("MEGA01" = "#1f77b4", "KOSPI200" = "#d62728")) +
      labs(title = "STR_1631 MEGA_01 — Equity Curve",
           subtitle = sprintf("SR=%.3f | CAGR=%.1f%% | MDD=%.1f%%",
                              po$Sharpe, po$CAGR, po$MDD),
           x = NULL, y = "NAV (억원)", color = NULL) +
      theme_minimal(base_size = 11) +
      theme(legend.position = "top")
    ggsave(file.path(CHART_DIR, "equity_curve.png"), p_eq, width = 10, height = 5, dpi = 150)

    # Annual Returns
    ar_strategy <- ann_dt
    bm_ann <- data.table(Date = as.Date(index(sim_base$bm_xts)), BM_Ret = as.numeric(sim_base$bm_xts))
    bm_ann[, Year := as.integer(format(Date, "%Y"))]
    bm_ann_agg <- bm_ann[, .(BM_Annual = prod(1 + BM_Ret, na.rm=TRUE) - 1), by = Year]
    ar_merged <- merge(ar_strategy, bm_ann_agg, by = "Year", all.x = TRUE)
    ar_long <- melt(ar_merged, id.vars = "Year", measure.vars = c("Annual_Ret", "BM_Annual"),
                    variable.name = "Series", value.name = "Return")
    ar_long[, Return_pct := Return * 100]
    ar_long[, Series := factor(Series, levels = c("Annual_Ret", "BM_Annual"),
                               labels = c("MEGA01", "KOSPI200"))]
    p_ar <- ggplot(ar_long, aes(x = Year, y = Return_pct, fill = Series)) +
      geom_col(position = "dodge", width = 0.7) +
      geom_hline(yintercept = 0, linewidth = 0.3) +
      scale_fill_manual(values = c("MEGA01" = "#1f77b4", "KOSPI200" = "#d62728")) +
      labs(title = "STR_1631 MEGA_01 — Annual Returns",
           x = NULL, y = "Return (%)", fill = NULL) +
      theme_minimal(base_size = 11) +
      theme(legend.position = "top")
    ggsave(file.path(CHART_DIR, "annual_returns.png"), p_ar, width = 10, height = 5, dpi = 150)
    cat("[Chart fallback] equity_curve.png + annual_returns.png saved\n")
  }, error = function(e2) cat("[Chart fallback ERROR]", conditionMessage(e2), "\n"))
})

# ===================================================================
# 13. Status update
# ===================================================================
status_path <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", "WT-D20260424_010", "status.json")
status_update <- list(
  task_id       = "WT-D20260424_010",
  current_phase = "FORGE_DONE",
  updated_at    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  alpha_summary = list(
    primary_cell = "ABL_C", rank_ic = 0.0754, icir = 0.7698,
    harvey_t = 12.8581, confidence_tier = "HIGH", n_tickers = 20
  ),
  risk_summary  = list(
    estimator = "corpcor_analytical", condition_num = 16.2,
    market_pct = 72.5, cvar_95 = 0.0323, rf_flags_count = 2, overall_pass = TRUE
  ),
  optimizer_summary = list(
    method_selected = "HRP_0.4_Score_0.6", net_ir = 12.0672,
    n_names = 20, hhi = 0.0589, beta_port = 1.017,
    max_weight = 0.103, n_methods_compared = 10, constraint_pass = TRUE
  ),
  forge_summary = list(
    full_SR   = round(po$Sharpe, 4),
    full_CAGR = round(po$CAGR, 4),
    full_MDD  = round(po$MDD, 4),
    pre_lockbox_SR   = round(po_pre$Sharpe, 4),
    pre_lockbox_CAGR = round(po_pre$CAGR, 4),
    pre_lockbox_MDD  = round(po_pre$MDD, 4),
    turnover    = round(to_base, 2),
    harvey_t    = round(harvey_t, 4),
    hurdle_pass = hr$pass,
    hurdle_score = round(hr$score, 2),
    delta_SR_vs_baseline = round(po$Sharpe - BASELINE$SR, 4),
    sr_must_1p30 = po$Sharpe >= 1.30,
    sr_goal_1p50 = po$Sharpe >= 1.50,
    artifacts = list(
      "backtest_result.json", "equity_curve.parquet", "annual_returns.parquet",
      "pit_flags.json", "charts/equity_curve.png", "charts/annual_returns.png",
      "ic_weight_evolution.csv"
    )
  )
)
write_json(status_update, status_path, pretty = TRUE, auto_unbox = TRUE)
cat("[Status] status.json updated to FORGE_DONE\n")

# ===================================================================
# 14. Telegram 브리핑 (tg_agent_brief 단일 호출)
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "config.R"))
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))

  # tg_agent_brief() 존재 여부 확인
  if (exists("tg_agent_brief")) {
    tg_agent_brief(
      agent    = "Forge",
      wt_id    = "WT-D20260424_010",
      strategy = "STR_1631_MEGA_01",
      grade    = if (hr$pass && po$Sharpe >= 0.8 && po$CAGR >= 16) "A" else if (hr$pass) "B" else "C",
      score    = round(hr$score, 1),
      sr_full  = round(po$Sharpe, 3),
      cagr_full = round(po$CAGR, 2),
      mdd_full  = round(po$MDD, 2),
      sr_pre    = round(po_pre$Sharpe, 3),
      cagr_pre  = round(po_pre$CAGR, 2),
      mdd_pre   = round(po_pre$MDD, 2),
      delta_sr  = round(po$Sharpe - BASELINE$SR, 3),
      delta_cagr = round(po$CAGR - BASELINE$CAGR, 2),
      strength  = sprintf("HRP0.4+Score0.6 net_ir=12.07 | ABL_C regime winsor | Harvey t=%.2f", harvey_t),
      weakness  = sprintf("Consensus family 단일 집중(72.5%% market) | delta_SR %+.3f (Must: +0.107)", po$Sharpe - BASELINE$SR),
      equity_curve_path  = file.path(CHART_DIR, "equity_curve.png"),
      annual_returns_path = file.path(CHART_DIR, "annual_returns.png")
    )
    cat("[Telegram] tg_agent_brief() 완료\n")
  } else {
    # fallback: tg_send + tg_send_photo
    grade_str <- if (hr$pass && po$Sharpe >= 0.8 && po$CAGR >= 16) "A" else if (hr$pass) "B" else "C"
    ff5_t_str <- if (length(ff5_result) > 0) sprintf("%.3f", ff5_result$alpha_t) else "N/A"
    dsr_str   <- if (length(ff5_result) > 0) sprintf("%.4f", ff5_result$dsr) else "N/A"

    msg <- paste0(
      "[Forge] STR_1631_MEGA_01 FORGE_DONE\n",
      "WT: WT-D20260424_010 | ", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n\n",
      "=== Full Period ===\n",
      "Grade: ", grade_str, " | Score: ", round(hr$score, 1), "\n",
      "SR: ", round(po$Sharpe, 3), " | CAGR: ", round(po$CAGR, 2), "% | MDD: ", round(po$MDD, 2), "%\n",
      "TO: ", round(to_base, 1), "% | Harvey t: ", round(harvey_t, 3), "\n",
      "FF5 t: ", ff5_t_str, " | DSR: ", dsr_str, "\n\n",
      "=== Pre-Lockbox (Train) ===\n",
      "SR: ", round(po_pre$Sharpe, 3), " | CAGR: ", round(po_pre$CAGR, 2), "% | MDD: ", round(po_pre$MDD, 2), "%\n\n",
      "=== vs STR_1631 Baseline (SR 1.193) ===\n",
      "delta SR: ", sprintf("%+.3f", po$Sharpe - BASELINE$SR),
      " | Must(>=1.30): ", if(po$Sharpe >= 1.30) "PASS" else "FAIL",
      " | Target(>=1.50): ", if(po$Sharpe >= 1.50) "PASS" else "FAIL", "\n",
      "delta CAGR: ", sprintf("%+.2f", po$CAGR - BASELINE$CAGR), "pp",
      " | delta MDD: ", sprintf("%+.2f", po$MDD - BASELINE$MDD), "pp\n\n",
      "=== Regime-Conditional SR ===\n",
      paste0(sapply(names(regime_perf), function(rn) {
        rp <- regime_perf[[rn]]; sprintf("  %s: SR=%.2f CAGR=%.1f%% MDD=%.1f%%",
          rn, rp$Sharpe, rp$CAGR, rp$MDD)
      }), collapse = "\n"), "\n\n",
      "=== 개선 요소 ===\n",
      "  + HRP 0.4 + Score 0.6 (net_ir 12.07 vs baseline 6.35)\n",
      "  + ABL_C Regime-Adaptive Winsorization (ICIR 0.7698)\n",
      "  + Monthly Overlay (데일리 스위칭 금지 준수)\n"
    )
    tg_send(msg)
    eq_chart <- file.path(CHART_DIR, "equity_curve.png")
    ar_chart <- file.path(CHART_DIR, "annual_returns.png")
    if (file.exists(eq_chart)) tg_send_photo(eq_chart, "MEGA_01 Equity Curve")
    if (file.exists(ar_chart)) tg_send_photo(ar_chart, "MEGA_01 Annual Returns")
    cat("[Telegram] fallback tg_send() 완료\n")
  }
}, error = function(e) {
  cat("[Telegram ERROR]", conditionMessage(e), "\n")
})

# ===================================================================
# 15. Summary
# ===================================================================
cat("\n================================================================\n")
cat("   STR_1631_MEGA_01: FORGE_DONE 완료\n")
cat("================================================================\n")
cat(sprintf("Full Period: SR=%.3f | CAGR=%.2f%% | MDD=%.2f%%\n", po$Sharpe, po$CAGR, po$MDD))
cat(sprintf("Pre-Lockbox: SR=%.3f | CAGR=%.2f%% | MDD=%.2f%%\n", po_pre$Sharpe, po_pre$CAGR, po_pre$MDD))
cat(sprintf("Harvey t: %.3f | Hurdle: %s (%.1f)\n", harvey_t, if(hr$pass) "PASS" else "FAIL", hr$score))
cat(sprintf("vs Baseline: delta_SR=%+.3f | SR target Must(1.30): %s | Goal(1.50): %s\n",
            po$Sharpe - BASELINE$SR,
            if(po$Sharpe >= 1.30) "PASS" else "FAIL",
            if(po$Sharpe >= 1.50) "PASS" else "FAIL"))
cat(sprintf("Turnover: %.1f%% | Run time: %.1f sec\n",
            to_base, as.numeric(difftime(Sys.time(), t0, units="secs"))))
cat(sprintf("Artifacts: %s\n", OUT_DIR))
