cat("=== STR_1631 v5 M21: HRP + C13_Revision_Breadth_3m (TP_Gap 교체) ===\n")
## 핵심 아이디어: C19의 TP_Gap(ICIR 0.117) → C13_Revision_Breadth_3m(ICIR 0.438) 교체
## Mutation M_A1: TP_Gap 제거, C13_Revision_Breadth_3m 추가
## C13 준수: Factor DB Z_Score_Aligned 사용 (C13 위반 방지)
## C15 준수: load_month_factors() 경유 (직접 parquet 로드 금지)
## C19_Rev composite = (z_SUE + z_ESBR + z_EPS_CHG_1M + z_RevBreadth3m) / 4
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
# C15: factor_db_connector 로드 (load_month_factors 사용)
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

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
HRP_LOOKBACK  <- 60L
REVBREADTH_FACTOR <- "C13_Revision_Breadth_3m"  # Factor DB 팩터명

cat(sprintf("[setup] Factor substitution: TP_Gap -> %s\n", REVBREADTH_FACTOR))
cat("[setup] C15: using load_month_factors() | C13: Z_Score_Aligned only\n")

# ═══════════════════════════════════════════════════════════════════
# Gerber + RMT + HRP (M11과 동일)
# ═══════════════════════════════════════════════════════════════════
gerber_cor <- function(ret_matrix, threshold = 0.5) {
  n <- ncol(ret_matrix); mat <- matrix(0, n, n)
  med_abs <- apply(ret_matrix, 2, function(x) median(abs(x), na.rm = TRUE))
  med_abs <- ifelse(med_abs < 1e-12, apply(ret_matrix, 2, sd, na.rm = TRUE), med_abs)
  for (i in seq_len(n)) {
    thresh_i <- threshold * med_abs[i]; hi <- ret_matrix[, i] > thresh_i; li <- ret_matrix[, i] < -thresh_i
    for (j in i:n) {
      if (i == j) { mat[i, j] <- 1; next }
      thresh_j <- threshold * med_abs[j]; hj <- ret_matrix[, j] > thresh_j; lj <- ret_matrix[, j] < -thresh_j
      concordant <- sum((hi & hj) | (li & lj), na.rm = TRUE)
      discordant <- sum((hi & lj) | (li & hj), na.rm = TRUE)
      total <- concordant + discordant
      val <- if (total > 0L) (concordant - discordant) / total else 0
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
  lambda_plus <- (1 + 1 / sqrt(q))^2; noise_idx <- vals <= lambda_plus
  if (any(noise_idx) && !all(noise_idx)) vals[noise_idx] <- mean(vals[noise_idx])
  vals <- pmax(vals, 1e-8)
  denoised_cor <- vecs %*% diag(vals) %*% t(vecs)
  d_diag <- sqrt(pmax(diag(denoised_cor), 1e-16))
  denoised_cor <- denoised_cor / (d_diag %o% d_diag); diag(denoised_cor) <- 1
  denoised_cov <- denoised_cor * (vol %o% vol)
  colnames(denoised_cov) <- rownames(denoised_cov) <- colnames(cov_mat); denoised_cov
}
.recursive_bisect <- function(cov_mat, sort_idx) {
  n <- length(sort_idx); nms <- colnames(cov_mat)
  if (n == 1L) return(setNames(1.0, nms[sort_idx]))
  mid <- floor(n / 2); left <- sort_idx[1:mid]; right <- sort_idx[(mid+1):n]
  w_left <- .recursive_bisect(cov_mat, left); w_right <- .recursive_bisect(cov_mat, right)
  nl <- names(w_left); nr <- names(w_right)
  var_left <- as.numeric(t(w_left) %*% cov_mat[nl, nl, drop=FALSE] %*% w_left)
  var_right <- as.numeric(t(w_right) %*% cov_mat[nr, nr, drop=FALSE] %*% w_right)
  total_var <- var_left + var_right
  alpha <- if (is.na(total_var) || total_var < 1e-16) 0.5 else 1 - var_left / total_var
  c(w_left * alpha, w_right * (1 - alpha))
}
compute_hrp_weights <- function(ret_matrix, use_gerber = TRUE, use_rmt = TRUE) {
  n_col <- ncol(ret_matrix); n_row <- nrow(ret_matrix)
  ew_fallback <- setNames(rep(1/n_col, n_col), colnames(ret_matrix))
  if (n_col < 2L) return(setNames(1.0, colnames(ret_matrix)))
  cov_mat <- cov(ret_matrix, use = "pairwise.complete.obs")
  if (any(is.na(cov_mat))) return(ew_fallback)
  if (use_gerber) {
    cor_mat <- tryCatch(gerber_cor(ret_matrix, 0.5), error = function(e) NULL)
    if (is.null(cor_mat)) cor_mat <- cor(ret_matrix, use = "pairwise.complete.obs")
  } else cor_mat <- cor(ret_matrix, use = "pairwise.complete.obs")
  if (any(is.na(cor_mat))) { cor_mat[is.na(cor_mat)] <- 0; diag(cor_mat) <- 1 }
  if (use_rmt && n_row > n_col)
    cov_mat <- tryCatch(rmt_denoise_cov(cov_mat, n_row, n_col), error = function(e) cov_mat)
  cor_clamped <- pmin(pmax(cor_mat, -1), 1)
  dist_mat <- sqrt(0.5 * (1 - cor_clamped)); dist_mat[is.na(dist_mat)] <- 1; diag(dist_mat) <- 0
  hc <- tryCatch(hclust(as.dist(dist_mat), method = "single"), error = function(e) NULL)
  if (is.null(hc)) return(ew_fallback)
  weights <- tryCatch(.recursive_bisect(cov_mat, hc$order), error = function(e) NULL)
  if (is.null(weights)) return(ew_fallback)
  w_sum <- sum(weights); if (is.na(w_sum) || w_sum < 1e-10) return(ew_fallback)
  weights / w_sum
}

# ═══════════════════════════════════════════════════════════════════
# 1. Load RAWDATA
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]; BM_DT <- BM_DT[Date >= ANALYSIS_START_DATE]
drop_cols <- intersect(c("Open","High","Low","source","Size","Market"), names(RAWDATA))
if (length(drop_cols) > 0) RAWDATA[, (drop_cols) := NULL]
if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  univ_dt <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe.parquet")))
  univ_dt[, Date := as.Date(Date)]; setorder(univ_dt, Ticker, -Date)
  ticker_info <- univ_dt[, .(Name=Name[1], Sector=Sector[1]), by=Ticker]
  if (!"Name" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ticker_info[, .(Ticker,Name)], by="Ticker", all.x=TRUE)
  if (!"Sector" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ticker_info[, .(Ticker,Sector)], by="Ticker", all.x=TRUE)
  rm(univ_dt, ticker_info)
}
gc(verbose = FALSE)

RAWDATA[, YM := format(Date, "%Y-%m")]
sig_dates_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setorder(sig_dates_dt, sig_date)
SIG_DATES <- sig_dates_dt[sig_date >= SIGNAL_START_DATE]$sig_date

setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, TradVal := NULL]
RAWDATA[, Ret_abs := abs(Ret)]
RAWDATA[, MAX21d_raw := {
  ra <- Ret_abs; n <- length(ra)
  if (n < 21L) cummax(fifelse(is.na(ra), -Inf, ra)) else frollapply(ra, n=21L, FUN=max, fill=NA, align="right")
}, by = Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n=1L, type="lag"), by=Ticker]
RAWDATA[, c("Ret_abs","MAX21d_raw") := NULL]
SIG_SNAP <- RAWDATA[Date %in% SIG_DATES & !is.na(Close), .(Date,Ticker,Close,LIQ_20d,MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d","MAX21d","YM") := NULL]; setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

# ═══════════════════════════════════════════════════════════════════
# 2. Load Consensus (SUE, ESBR, EPS_CHG_1M)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Loading Consensus (SUE/ESBR/EPS1M) + Factor DB (RevBreadth3m)...\n")
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

# ═══════════════════════════════════════════════════════════════════
# 3. Build C19_Rev Signals
# C14 준수: Usable_Date <= sig_date 기반 접근 (load_month_factors 내부 처리)
# C15 준수: load_month_factors() 경유
# C13 준수: Z_Score_Aligned 그대로 사용 (방향 반전 금지)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Building C19_Rev signals (TP_Gap -> C13_Revision_Breadth_3m)...\n")
z_safe <- function(x) {
  n_valid <- sum(!is.na(x)); if (n_valid < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm=TRUE); s <- sd(x, na.rm=TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

FACTORS_list <- vector("list", length(SIG_DATES))
fdb_load_errors <- 0L

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

  # C15: load_month_factors() 경유로 C13_Revision_Breadth_3m 로드
  # C14: sig_date 기준 Factor DB 파일 선택 (load_month_factors 내부 처리)
  # C13: Z_Score_Aligned 그대로 사용
  fdb_dt <- tryCatch(
    load_month_factors(sd, coverage_min = 0.05),
    error = function(e) { fdb_load_errors <<- fdb_load_errors + 1L; NULL }
  )

  # RevBreadth3m 추출
  if (!is.null(fdb_dt) && REVBREADTH_FACTOR %in% fdb_dt$Factor_Name) {
    rb_j <- fdb_dt[Factor_Name == REVBREADTH_FACTOR,
                   .(Ticker, z_revbreadth = Z_Score_Aligned)]
  } else {
    # Factor DB 로드 실패 or 팩터 없음 → skip
    next
  }

  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker)], sue_j, esbr_j, eps1m_j, cov_j, rb_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]
  if (nrow(sig) < 20L) next

  sig[, z_sue      := z_safe(sue)]
  sig[, z_esbr     := z_safe(esbr)]
  sig[, z_eps1m    := z_safe(eps_chg_1m)]
  # z_revbreadth는 이미 Z_Score_Aligned (Factor DB에서 직접) - C13 준수
  # 단, cross-section 재표준화는 허용 (within-period, not full-sample)
  sig[, z_rb_cs    := z_safe(z_revbreadth)]  # cross-section 정규화

  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_rb_cs)]
  if (nrow(sig) < 20L) next

  sig[, C19_Rev := (z_sue + z_esbr + z_eps1m + z_rb_cs) / 4]
  setorder(sig, -C19_Rev)
  top <- head(sig, N_HOLD)
  FACTORS_list[[i]] <- data.table(Date = sd, Ticker = top$Ticker, Score = top$C19_Rev)
}

FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
cat(sprintf("[Step 3] FACTORS: %d rows | %d months | FDB load errors: %d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), fdb_load_errors))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, FACTORS_list, SIG_SNAP)
gc(verbose = FALSE)

if (nrow(FACTORS) < 50L) stop("[M21] Insufficient FACTORS rows. RevBreadth3m coverage may be too low.")

# ═══════════════════════════════════════════════════════════════════
# 4. HRP Weights (60d lookback, t-1 lag)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 4] Computing HRP weights...\n")
FACTORS_hrp <- copy(FACTORS); FACTORS_hrp[, Weight_hrp := NA_real_]
hrp_success <- 0L; hrp_fallback <- 0L

for (sd in unique(FACTORS_hrp$Date)) {
  tickers <- FACTORS_hrp[Date == sd, Ticker]
  all_dates <- sort(unique(RAWDATA[Date < sd, Date]))
  if (length(all_dates) < HRP_LOOKBACK) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1/length(tickers)]
    hrp_fallback <- hrp_fallback + 1L; next
  }
  lookback_dates <- tail(all_dates, HRP_LOOKBACK)
  ret_sub <- RAWDATA[Date %in% lookback_dates & Ticker %in% tickers, .(Date,Ticker,Ret)]
  ret_wide <- dcast(ret_sub, Date ~ Ticker, value.var = "Ret")
  ret_mat  <- as.matrix(ret_wide[, -1, with=FALSE]); colnames(ret_mat) <- names(ret_wide)[-1]
  valid_cols <- colSums(!is.na(ret_mat)) >= 30L
  if (sum(valid_cols) < 2L) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1/length(tickers)]; hrp_fallback <- hrp_fallback + 1L; next
  }
  ret_mat_clean <- ret_mat[, valid_cols, drop=FALSE]; ret_mat_clean[is.na(ret_mat_clean)] <- 0
  hrp_w <- tryCatch(compute_hrp_weights(ret_mat_clean), error = function(e) NULL)
  if (is.null(hrp_w)) {
    FACTORS_hrp[Date == sd, Weight_hrp := 1/length(tickers)]; hrp_fallback <- hrp_fallback + 1L; next
  }
  w_vec <- rep(0, length(tickers)); names(w_vec) <- tickers
  matched <- intersect(names(hrp_w), tickers); w_vec[matched] <- hrp_w[matched]
  unmatched <- setdiff(tickers, matched)
  if (length(unmatched) > 0) w_vec[unmatched] <- 0.01/length(unmatched)
  w_vec <- w_vec / sum(w_vec)
  for (tk in tickers) FACTORS_hrp[Date == sd & Ticker == tk, Weight_hrp := w_vec[tk]]
  hrp_success <- hrp_success + 1L
}
cat(sprintf("[Step 4] HRP: %d success, %d fallback\n", hrp_success, hrp_fallback))

hrp_weight_lookup <- list()
for (d in unique(FACTORS_hrp$Date)) {
  month_f <- FACTORS_hrp[Date == d]; w <- month_f$Weight_hrp
  if (all(is.na(w))) w <- rep(1/nrow(month_f), nrow(month_f))
  hrp_weight_lookup[[as.character(d)]] <- setNames(w, month_f$Ticker)
}
orig_ivol <- calc_ivol_weights
calc_ivol_weights <<- function(tickers, ret_dt, n_days=60, max_w=0.15) {
  for (d in names(hrp_weight_lookup)) {
    hw <- hrp_weight_lookup[[d]]
    if (all(tickers %in% names(hw))) { w <- hw[tickers]; return(as.numeric(w/sum(w))) }
  }
  rep(1/length(tickers), length(tickers))
}

sim_base <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS, n_holdings=N_HOLD,
  weight_method="ivol", commission=0.0015, buffer_zone=list(keep_n=35L, entry_n=20L))
calc_ivol_weights <<- orig_ivol

perf_base <- summarise_perf(sim_base$strategy_xts, "M21_RevBreadth_Base")
to_base   <- calc_turnover(sim_base$PORTFOLIO_LOG, sim_base$DAILY_NAV_DT)
cat(sprintf("[Step 4] Turnover: %.1f%%\n", to_base))

# ═══════════════════════════════════════════════════════════════════
# 5. Regime Overlay
# ═══════════════════════════════════════════════════════════════════
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME <- build_daily_regime(use_cache = TRUE); setkey(REGIME, Date)
inv_path <- file.path(CACHE_DIR, "kodex_inverse_114800.csv")
INV_DT <- if (file.exists(inv_path)) { dt <- fread(inv_path); dt[, Date:=as.Date(Date)]; setkey(dt,Date); dt } else NULL
nav_dt <- copy(sim_base$DAILY_NAV_DT); setkey(nav_dt, Date)
nav_dt <- REGIME[, .(Date, MRS, n_axes_firing)][nav_dt, roll=TRUE]
nav_dt <- merge(nav_dt, BM_DT[, .(Date, BM_Ret)], by="Date", all.x=TRUE)
if (!is.null(INV_DT)) {
  nav_dt <- merge(nav_dt, INV_DT[, .(Date, Ret_Inv)], by="Date", all.x=TRUE)
  nav_dt[is.na(Ret_Inv), Ret_Inv := -BM_Ret]
} else nav_dt[, Ret_Inv := -BM_Ret]
nav_dt[is.na(Ret_Inv), Ret_Inv := 0]; nav_dt[is.na(MRS), MRS := 0]; nav_dt[is.na(n_axes_firing), n_axes_firing := 0L]
# PIT NOTE: MRS is already t-1 lagged in regime_engine_daily.R (Step 5, line 339).
# MRS[t] = MRS_raw[t-1]. No additional shift() needed — double-lag would create t-2 error.
nav_dt[, crisis_flag := fifelse(MRS >= 60 & n_axes_firing >= 5, 1L, 0L)]
nav_dt[, crisis_consec := { out <- integer(.N); cnt <- 0L
  for (j in seq_len(.N)) { if (crisis_flag[j]==1L) cnt<-cnt+1L else cnt<-0L; out[j]<-cnt }; out }]
nav_dt[, Layer := fifelse(crisis_consec >= 3L, 3L, fifelse(MRS >= 30, 2L, 1L))]
nav_dt[, Ret_overlay := fcase(
  Layer==1L, Strategy_Ret,
  Layer==2L, { f_w <- pmax(0.5, 1.0-(MRS-30)/60); f_w*Strategy_Ret + (1-f_w)*0 },
  Layer==3L, 0.50*Strategy_Ret + 0.20*Ret_Inv + 0.30*0
)]
nav_dt[, NAV_overlay := DEFAULT_INITIAL_CAPITAL * cumprod(1+Ret_overlay)]
overlay_xts <- xts(nav_dt$Ret_overlay, order.by=nav_dt$Date); names(overlay_xts) <- "Strategy"

# ═══════════════════════════════════════════════════════════════════
# 6. Summary & Save
# ═══════════════════════════════════════════════════════════════════
perf_overlay <- summarise_perf(overlay_xts, "M21_RevBreadth_Overlay")
perf_bm2     <- summarise_perf(sim_base$bm_xts, "KOSPI200")
cat("\n================================================================\n")
cat("   STR_1631 v5 M21: TP_Gap -> C13_Revision_Breadth_3m (M_A1)\n")
cat("================================================================\n")
cat("--- Base ---\n"); print(perf_base)
cat("--- Overlay ---\n"); print(perf_overlay)
cat("--- BM ---\n"); print(perf_bm2)
cat(sprintf("Turnover: %.1f%%\n", to_base))

source(file.path(FUNC_PATH, "hurdle_gate.R"))
sim_ov_h <- list(strategy_xts=overlay_xts, bm_xts=sim_base$bm_xts,
  DAILY_NAV_DT=nav_dt[,.(Date,NAV=NAV_overlay,Strategy_Ret=Ret_overlay)], PORTFOLIO_LOG=sim_base$PORTFOLIO_LOG)
hurdle_res <- run_hurdle_gate(sim_ov_h, FACTORS, strategy_name="STR_1631_v5_M21_revbreadth", output_dir=OUT_DIR)
cat("--- Hurdle ---\n"); print(hurdle_res[c("pass","score")])

generate_charts(list(strategy_xts=overlay_xts, bm_xts=sim_base$bm_xts,
  DAILY_NAV_DT=nav_dt[, .(Date, NAV=NAV_overlay, Strategy_Ret=Ret_overlay)]),
  output_dir=OUT_DIR, strategy_name="STR_1631 v5 M21 - RevBreadth3m")

write_json(list(
  strategy="STR_1631_v5_M21_revbreadth",
  mutation="M_A1: TP_Gap -> C13_Revision_Breadth_3m via load_month_factors()",
  pit_notes=list(C13="Z_Score_Aligned from Factor DB", C14="Usable_Date<=sig_date", C15="load_month_factors()"),
  fdb_load_errors=fdb_load_errors,
  base=as.list(perf_base), overlay=as.list(perf_overlay), benchmark=as.list(perf_bm2),
  turnover=to_base, hurdle_pass=hurdle_res$pass, hurdle_score=hurdle_res$score,
  run_time=as.numeric(difftime(Sys.time(), t0, units="secs"))
), file.path(OUT_DIR, "performance.json"), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("\n[DONE] M21 complete in %.1f sec\n", difftime(Sys.time(), t0, units="secs")))
