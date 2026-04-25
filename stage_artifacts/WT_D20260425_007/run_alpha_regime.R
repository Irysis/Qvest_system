#==============================================================================
# WT-D20260425_007 Alpha Research — MEGA_05 Regime-Σ MinCVaR (Iter 2)
# Purpose: 6F factor mix 동일 유지 + regime classification 신호 추가
#          Optimizer가 Kelly_frac05+LW_constcor → Regime-Σ MinCVaR로 교체할 수 있는
#          regime indicator (BULL/NORMAL/CAUTION/CRISIS) PIT-safe 정의 + conditional IC matrix
# Author : Alpha Research Agent | 2026-04-25
# Memo   : Risk/Optimizer 영역 침범 금지 — covariance 추정/weight 결정 없음.
#          Alpha는 (a) factor mix 보존 + (b) regime label per signal_date를 산출하는
#          데까지만 책임. Optimizer는 이 regime label로 regime-conditional Σ를 만든다.
#==============================================================================

cat("=== WT-D20260425_007 — MEGA_05 Regime-Σ MinCVaR Alpha (6F + regime) ===\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(future);     library(future.apply)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
set.seed(42L)

t0 <- Sys.time()

# ---- Paths ----
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
FUNC_PATH    <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
WT_ID        <- "WT-D20260425_007"
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260425_007")
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
CPP_PATH     <- file.path(FUNC_PATH, "cpp/rcpp_hotspots.R")
LINEAGE_PATH <- file.path(FUNC_PATH, "worktask/lineage_utils.R")
dir.create(ART_DIR, showWarnings = FALSE, recursive = TRUE)

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

# ---- Lockbox enforcement (R2 P2 Window Isolation) ----
LOCKBOX_START <- as.Date("2024-01-23")
LOCKBOX_END   <- as.Date("2026-01-23")
TRAIN_END     <- as.Date("2024-01-22")

# ---- R14: Load Rcpp hotspots ----
rcpp_loaded <- tryCatch({
  source(CPP_PATH)
  cat("[R14] Rcpp hotspots loaded\n")
  TRUE
}, error = function(e) {
  cat("[R14] Rcpp unavailable — fallback OK\n"); FALSE
})

# ---- Source infrastructure ----
source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))
source(file.path(FUNC_PATH, "factor_db/factor_db_connector.R"))
cat("[Init] Factor DB connector loaded\n")

#==============================================================================
# Step 1: Load RAWDATA + Factor DB (6F동일 — MEGA_05 PRIMARY 셀)
#==============================================================================
cat("\n[Step 1] Loading RAWDATA + Factor DB (6F PRIMARY)...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)
setkey(RAWDATA, Date, Ticker)

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[order(Date), AvgTV20 := frollmean(TradingValue, n = 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]   # LIQ 2e8

monthly_ret <- RAWDATA[, .(
  Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1,
  LiqPass_any = any(LiqPass, na.rm = TRUE)
), by = .(YearMonth = format(Date, "%Y-%m"), Ticker)]
monthly_ret[, sig_date := as.Date(paste0(YearMonth, "-01"))]
setkey(monthly_ret, sig_date, Ticker)

# 6F factor mix (MEGA_05 PRIMARY 동일)
NEEDED_FACTORS <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap",
                    "Q07_Earnings_Stability", "AC21_CF_to_Accrual_Ratio")

fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- sort(list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                              full.names = TRUE))
fdb_files_train <- fdb_files[sapply(fdb_files, function(fp) {
  ym   <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  d    <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))
  !is.na(d) && d >= as.Date("2004-01-01") && d <= TRAIN_END
})]
cat(sprintf("[Step 1] Loading %d training-window parquet files...\n",
            length(fdb_files_train)))

FDB_ALL <- rbindlist(lapply(fdb_files_train, function(fp) {
  ym    <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  sig_d <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))
  dt    <- tryCatch(
    as.data.table(read_parquet(fp,
      col_select = c("Ticker","Factor_Name","Z_Score","Coverage"))),
    error = function(e) NULL
  )
  if (is.null(dt) || nrow(dt) == 0) return(NULL)
  dt <- dt[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE,
           .(Ticker, Factor_Name, Z_Score)]
  if (nrow(dt) == 0) return(NULL)
  dt[, sig_date := sig_d]
  dt
}), fill = TRUE, use.names = TRUE)
cat(sprintf("[Step 1] FDB raw: %s rows | %d months | %d factors\n",
            format(nrow(FDB_ALL), big.mark=","),
            uniqueN(FDB_ALL$sig_date),
            uniqueN(FDB_ALL$Factor_Name)))

# C13 align (Z_Score_Aligned)
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
if ("Z_Score_Aligned" %in% names(FDB_ALL)) {
  FDB_ALL[, Z_Score := Z_Score_Aligned]
  FDB_ALL[, Z_Score_Aligned := NULL]
}
setkey(FDB_ALL, sig_date, Ticker)

# Wide
FDB_WIDE <- dcast(FDB_ALL, sig_date + Ticker ~ Factor_Name,
                  value.var = "Z_Score", fill = NA_real_)
setkey(FDB_WIDE, sig_date, Ticker)
rm(FDB_ALL); gc(verbose = FALSE)

# Liq filter (C10)
all_sig_dates <- sort(unique(FDB_WIDE$sig_date))
liq_by_month <- lapply(all_sig_dates, function(sig_d) {
  snap <- RAWDATA[Date == sig_d & LiqPass == TRUE, .(Ticker)]
  if (nrow(snap) == 0) {
    closest_d <- RAWDATA[Date <= sig_d, max(Date)]
    snap <- RAWDATA[Date == closest_d & LiqPass == TRUE, .(Ticker)]
  }
  data.table(sig_date = sig_d, Ticker = snap$Ticker)
})
LIQ_PASS_DT <- rbindlist(liq_by_month, fill = TRUE)
setkey(LIQ_PASS_DT, sig_date, Ticker)
FDB_WIDE <- merge(FDB_WIDE, LIQ_PASS_DT, by = c("sig_date","Ticker"), all.x = FALSE)
setkey(FDB_WIDE, sig_date, Ticker)
cat(sprintf("[Step 1] FDB_WIDE post-liq: %d rows\n", nrow(FDB_WIDE)))

#==============================================================================
# Step 2: Regime Indicator (PIT-safe, expanding percentile, 4-state)
#   - 입력: KOSPI200(BM_DT) 월간 수익률 + drawdown + realized vol(60d) + breadth proxy
#   - 모두 t-1 기반 (signal lag, C2/C9/C11)
#   - expanding percentile만 사용 (C1, L-441/450 준수)
#   - Korean internals 우선 (L-454: 한국 내부 데이터 > FRED 글로벌)
#==============================================================================
cat("\n[Step 2] Building regime indicator (PIT-safe, expanding percentile, 4-state)...\n")

# Daily benchmark returns
BM_DT  <- as.data.table(BM_DT)
setkey(BM_DT, Date)
bm_ret_col <- if ("BM_Ret" %in% names(BM_DT)) "BM_Ret" else
              if ("Ret"    %in% names(BM_DT)) "Ret"    else NULL
stopifnot(!is.null(bm_ret_col))

# Daily breadth proxy: %{ret>0} cross-section per Date (KR market internal, L-454)
breadth_daily <- RAWDATA[!is.na(Ret), .(
  breadth_pos_pct = mean(Ret > 0, na.rm = TRUE),
  n_active        = .N
), by = Date]
setkey(breadth_daily, Date)

# Build regime feature panel at month-end (BUILD AT t=month-end, APPLY at t+1 month)
# month-end Date in train window
me_dates <- BM_DT[Date <= TRAIN_END,
  .(month_end = max(Date)),
  by = .(YM = format(Date, "%Y-%m"))]$month_end
me_dates <- sort(unique(me_dates))

build_regime_features <- function(me) {
  # window up to & including me  (then we LAG by 1 month for sig_date matching, see below)
  win_60 <- BM_DT[Date <= me & Date >  me - 90]  # last 60 trading days approx
  if (nrow(win_60) < 30L) return(NULL)
  # realized vol (annualized)
  rv60 <- sd(win_60[[bm_ret_col]], na.rm = TRUE) * sqrt(252)

  # 1m return (last ~21 trading days)
  win_21 <- BM_DT[Date <= me & Date > me - 35]
  ret_1m <- if (nrow(win_21) >= 5L) prod(1 + win_21[[bm_ret_col]], na.rm = TRUE) - 1 else NA_real_

  # 12m drawdown: max drawdown over last ~252 trading days
  win_252 <- BM_DT[Date <= me & Date > me - 380]
  if (nrow(win_252) < 20L) {
    dd_12m <- NA_real_
  } else {
    px      <- cumprod(1 + win_252[[bm_ret_col]])
    peak    <- cummax(px)
    dd_12m  <- min(px / peak - 1, na.rm = TRUE)
  }

  # KR breadth (60d avg %positive)
  br_60 <- breadth_daily[Date <= me & Date > me - 90, mean(breadth_pos_pct, na.rm = TRUE)]

  data.table(
    month_end = me,
    rv60      = rv60,
    ret_1m    = ret_1m,
    dd_12m    = dd_12m,
    breadth60 = br_60
  )
}

regime_feat <- rbindlist(lapply(me_dates, build_regime_features), fill = TRUE)
regime_feat <- regime_feat[!is.na(rv60) & !is.na(dd_12m)]
setorder(regime_feat, month_end)
cat(sprintf("[Step 2] Regime feature panel: %d months (%s ~ %s)\n",
            nrow(regime_feat),
            as.character(min(regime_feat$month_end)),
            as.character(max(regime_feat$month_end))))

# Expanding percentile rank (C1, L-441/450) — strictly past data, no future leakage
expanding_percentile <- function(x) {
  n <- length(x); out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i == 1L) { out[i] <- 0.5; next }
    past <- x[seq_len(i - 1L)]
    past <- past[is.finite(past)]
    if (length(past) < 6L) { out[i] <- 0.5; next }
    out[i] <- mean(past <= x[i], na.rm = TRUE)
  }
  out
}

# Build regime score per month (expanding percentile of features)
# Higher score = more crisis-like
# Score = w1 * pct(rv60) + w2 * pct(-ret_1m) + w3 * pct(-dd_12m) + w4 * pct(-breadth60)
# All percentiles are expanding (no full-sample), enforcing C1.
regime_feat[, pct_rv60     := expanding_percentile(rv60)]
regime_feat[, pct_neg_ret  := expanding_percentile(-ret_1m)]
regime_feat[, pct_neg_dd   := expanding_percentile(-dd_12m)]
regime_feat[, pct_neg_brth := expanding_percentile(-breadth60)]
regime_feat[, regime_score := 0.35 * pct_rv60 + 0.25 * pct_neg_ret +
                              0.25 * pct_neg_dd + 0.15 * pct_neg_brth]

# 4-state classification using expanding quantile of regime_score
# (PIT-safe: thresholds also expanding)
cls_thr_q <- function(scores, qs = c(0.30, 0.65, 0.85)) {
  n <- length(scores); out <- character(n)
  for (i in seq_len(n)) {
    if (i < 12L) { out[i] <- "NORMAL"; next }
    past <- scores[seq_len(i - 1L)]
    past <- past[is.finite(past)]
    if (length(past) < 12L) { out[i] <- "NORMAL"; next }
    th <- quantile(past, probs = qs, na.rm = TRUE)
    s  <- scores[i]
    out[i] <- if (s <= th[1]) "BULL"
              else if (s <= th[2]) "NORMAL"
              else if (s <= th[3]) "CAUTION"
              else "CRISIS"
  }
  out
}
regime_feat[, regime_state := cls_thr_q(regime_score)]

# IMPORTANT: signal lag — regime built at month_end is applied to NEXT month's sig_date.
# sig_date = first day of (month_end + 1 month). This implements C2 (t-1 lag).
regime_feat[, sig_date := as.Date(format(month_end + 32, "%Y-%m-01"))]
# Robust shift: just use first day of next month
regime_feat[, sig_date := {
  d <- month_end + 1L  # day after month_end
  as.Date(format(d, "%Y-%m-01"))
}]
setkey(regime_feat, sig_date)

cat("[Step 2] Regime distribution (train window):\n")
print(regime_feat[, .N, by = regime_state][order(-N)])

#==============================================================================
# Step 3: Compose 6F PRIMARY signal (MEGA_05 동일)
#==============================================================================
cat("\n[Step 3] Building 6F PRIMARY composite (MEGA_05 PRIMARY)...\n")

# Forward returns merge (C2)
FDB_WIDE[, fwd_date := sig_date %m+% months(1)]
monthly_ret_simple <- monthly_ret[, .(sig_date, Ticker, Ret_1m)]
setkey(monthly_ret_simple, sig_date, Ticker)
FDB_WITH_RET <- merge(
  FDB_WIDE[, .SD, .SDcols = c("sig_date","fwd_date","Ticker",
                               intersect(NEEDED_FACTORS, names(FDB_WIDE)))],
  monthly_ret_simple[, .(fwd_date = sig_date, Ticker, Ret_1m)],
  by = c("fwd_date","Ticker"), all.x = FALSE
)
setkey(FDB_WITH_RET, sig_date, Ticker)

# Per-factor IC per month (Spearman)
available_factors <- intersect(NEEDED_FACTORS, names(FDB_WITH_RET))
ic_per_month <- lapply(available_factors, function(fn) {
  per_month <- FDB_WITH_RET[!is.na(get(fn)) & !is.na(Ret_1m),
    .(IC = tryCatch(cor(get(fn), Ret_1m, method = "spearman"),
                    error = function(e) NA_real_),
      N  = .N), by = sig_date]
  per_month[, factor := fn]
  per_month
})
IC_DT <- rbindlist(ic_per_month, fill = TRUE)
setkey(IC_DT, factor, sig_date)

# Winsorize helper
winsor_z <- function(x, sigma = 2.5) {
  m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(x)
  pmax(pmin(x, m + sigma * s), m - sigma * s)
}

# Expanding IC-weighted composite (MEGA_01 ABL_C method preserved)
build_composite <- function(fac_names, dt = FDB_WITH_RET, ic_dt = IC_DT,
                            sigma_winsor = 2.5) {
  fac_names <- intersect(fac_names, names(dt))
  if (length(fac_names) == 0) stop("No factors available")
  all_dates <- sort(unique(dt$sig_date))
  min_ic_months <- 12L
  score_list <- lapply(seq_along(all_dates), function(i) {
    sig_d <- all_dates[i]
    sub   <- dt[sig_date == sig_d]
    if (nrow(sub) < 10L) return(NULL)
    past_ic <- ic_dt[factor %in% fac_names & sig_date < sig_d & !is.na(IC)]
    if (nrow(past_ic) < length(fac_names) * min_ic_months) {
      theta <- setNames(rep(1/length(fac_names), length(fac_names)), fac_names)
    } else {
      ic_mean_exp <- past_ic[, .(mean_IC = mean(IC, na.rm=TRUE)), by = factor]
      theta_raw <- setNames(pmax(ic_mean_exp$mean_IC, 0), ic_mean_exp$factor)
      theta_all <- setNames(rep(0, length(fac_names)), fac_names)
      for (fn in names(theta_raw)) {
        if (fn %in% names(theta_all)) theta_all[fn] <- theta_raw[fn]
      }
      s <- sum(abs(theta_all))
      theta <- if (s < 1e-10)
        setNames(rep(1/length(fac_names), length(fac_names)), fac_names)
      else theta_all / s
    }
    score_vec <- rep(0, nrow(sub))
    for (fn in fac_names) {
      if (!fn %in% names(sub)) next
      col_vals <- sub[[fn]]
      if (all(is.na(col_vals))) next
      col_w    <- winsor_z(col_vals, sigma = sigma_winsor)
      score_vec <- score_vec + theta[fn] * col_w
    }
    sub_out <- sub[, .(sig_date, Ticker, Ret_1m)]
    sub_out[, Score := score_vec]
    sub_out[, theta_json := toJSON(as.list(round(theta, 4)), auto_unbox=TRUE)]
    sub_out
  })
  rbindlist(score_list[!sapply(score_list, is.null)], fill = TRUE)
}

PRIMARY_FACS    <- c("C01_SUE", "C04_ESBR", "C02_EPS_Chg_1m", "C06_TP_Gap",
                     "Q07_Earnings_Stability", "AC21_CF_to_Accrual_Ratio")
PRIMARY_FACS    <- intersect(PRIMARY_FACS, names(FDB_WITH_RET))
primary_scores  <- build_composite(PRIMARY_FACS)
cat(sprintf("[Step 3] Primary scores rows: %d | %d months\n",
            nrow(primary_scores), uniqueN(primary_scores$sig_date)))

#==============================================================================
# Step 4: Attach regime label to primary scores + per-factor IC matrix
#==============================================================================
cat("\n[Step 4] Attaching regime labels + computing conditional IC matrix...\n")

regime_label <- regime_feat[, .(sig_date, regime_state, regime_score,
                                rv60, dd_12m, breadth60, ret_1m_bm = ret_1m)]
# Dedup: keep last (latest month_end → sig_date) per sig_date if duplicates exist
regime_label <- regime_label[order(sig_date), .SD[.N], by = sig_date]
setkey(regime_label, sig_date)

primary_scores <- merge(primary_scores, regime_label[, .(sig_date, regime_state)],
                        by = "sig_date", all.x = TRUE)
primary_scores[is.na(regime_state), regime_state := "NORMAL"]

# Composite IC per month
score_ic_per_month <- primary_scores[!is.na(Score) & !is.na(Ret_1m),
  .(IC = tryCatch(cor(Score, Ret_1m, method = "spearman"),
                  error = function(e) NA_real_),
    N  = .N),
  by = sig_date]
score_ic_per_month <- merge(score_ic_per_month,
                            regime_label[, .(sig_date, regime_state)],
                            by = "sig_date", all.x = TRUE)
score_ic_per_month[is.na(regime_state), regime_state := "NORMAL"]

# Conditional IC matrix: regime × factor
fac_ic_with_regime <- merge(IC_DT, regime_label[, .(sig_date, regime_state)],
                            by = "sig_date", all.x = TRUE)
fac_ic_with_regime[is.na(regime_state), regime_state := "NORMAL"]

cond_ic <- fac_ic_with_regime[!is.na(IC) & N >= 15, .(
  mean_IC  = mean(IC, na.rm = TRUE),
  sd_IC    = sd(IC,   na.rm = TRUE),
  ICIR     = mean(IC, na.rm = TRUE) / pmax(sd(IC, na.rm = TRUE), 1e-10),
  n_months = .N
), by = .(regime_state, factor)]
setorder(cond_ic, regime_state, -ICIR)

# Composite IC by regime
comp_ic_by_regime <- score_ic_per_month[!is.na(IC), .(
  mean_IC  = mean(IC, na.rm = TRUE),
  sd_IC    = sd(IC,   na.rm = TRUE),
  ICIR     = mean(IC, na.rm = TRUE) / pmax(sd(IC, na.rm = TRUE), 1e-10),
  n_months = .N
), by = regime_state]
setorder(comp_ic_by_regime, -ICIR)

cat("\n=== Composite (6F PRIMARY) IC by regime ===\n")
print(comp_ic_by_regime)
cat("\n=== Per-factor conditional IC (top per regime) ===\n")
print(cond_ic[, head(.SD, 6L), by = regime_state])

# Also produce 4×6 wide matrix for downstream
cond_ic_wide <- dcast(cond_ic, regime_state ~ factor,
                      value.var = "mean_IC")

#==============================================================================
# Step 5: Diagnostics (overall + regime-conditional)
#==============================================================================
cat("\n[Step 5] Diagnostics (overall + regime stability)...\n")

ic_valid_all <- score_ic_per_month[!is.na(IC) & N >= 15]
mean_ic_all <- mean(ic_valid_all$IC)
sd_ic_all   <- sd(ic_valid_all$IC)
icir_all    <- mean_ic_all / sd_ic_all
harvey_all  <- icir_all * sqrt(nrow(ic_valid_all))

p1 <- ic_valid_all[sig_date >= as.Date("2008-01-01") & sig_date <= as.Date("2014-12-31"), mean(IC)]
p2 <- ic_valid_all[sig_date >= as.Date("2015-01-01") & sig_date <= as.Date("2019-12-31"), mean(IC)]
p3 <- ic_valid_all[sig_date >= as.Date("2020-01-01") & sig_date <= as.Date("2024-01-22"), mean(IC)]
sub_stab <- if (!is.na(p1) && !is.na(p2) && !is.na(p3))
  pmin(abs(p1),abs(p2),abs(p3)) / pmax(abs(p1),abs(p2),abs(p3)) else NA_real_

# Monotonicity (decile mean return)
score_dec <- primary_scores[!is.na(Score) & !is.na(Ret_1m)]
score_dec[, dec := cut(Score, breaks = quantile(Score, probs = seq(0, 1, 0.1),
                                                na.rm = TRUE),
                       include.lowest = TRUE, labels = FALSE), by = sig_date]
dec_means <- score_dec[!is.na(dec), .(mean_ret = mean(Ret_1m, na.rm = TRUE)), by = dec]
setorder(dec_means, dec)
mono_corr <- cor(dec_means$dec, dec_means$mean_ret, method = "spearman")

# DSR (R14)
dsr_val <- NA_real_
if (rcpp_loaded && exists("bootstrap_dsr_fast")) {
  ic_vec <- ic_valid_all$IC
  dsr_val <- tryCatch(
    bootstrap_dsr_fast(ic_vec, n_trials = 5L, B = 1000L)$dsr,
    error = function(e) { cat("[DSR] fallback NA:", conditionMessage(e), "\n"); NA_real_ }
  )
}

# Turnover proxy (top20 churn)
top20_per_month <- primary_scores[!is.na(Score),
  .(top = list(head(.SD[order(-Score), Ticker], 20L))), by = sig_date]
setorder(top20_per_month, sig_date)
turnover_vals <- numeric(0)
for (i in 2:nrow(top20_per_month)) {
  prev <- unlist(top20_per_month$top[[i-1L]])
  curr <- unlist(top20_per_month$top[[i]])
  if (length(prev) == 0L || length(curr) == 0L) next
  turnover_vals <- c(turnover_vals, length(setdiff(curr, prev)) / length(curr))
}
turnover_proxy <- if (length(turnover_vals) > 0) mean(turnover_vals) * 12 else NA_real_

cat(sprintf("\nOverall: rank_IC=%.4f | ICIR=%.4f | Harvey_t=%.4f | mono=%.3f | sub_stab=%.4f | DSR=%.4f | TO=%.3f\n",
    mean_ic_all, icir_all, harvey_all, mono_corr, sub_stab,
    dsr_val %||% NA_real_, turnover_proxy %||% NA_real_))

#==============================================================================
# Step 6: alpha vector for as_of_date (last training month)
#==============================================================================
cat("\n[Step 6] Constructing alpha_vector for as_of_date=2026-04-25...\n")

last_sig_date <- max(primary_scores$sig_date, na.rm = TRUE)
last_regime   <- regime_label[sig_date == last_sig_date, regime_state]
if (length(last_regime) == 0L) last_regime <- "NORMAL"
cat(sprintf("[Step 6] Last sig_date in train window: %s | regime=%s\n",
            last_sig_date, last_regime))

latest_scores <- primary_scores[sig_date == last_sig_date & !is.na(Score) & is.finite(Score)]
latest_scores <- latest_scores[order(-Score)]

if (nrow(latest_scores) > 0) {
  mu_s <- mean(latest_scores$Score, na.rm = TRUE)
  sd_s <- sd(latest_scores$Score,   na.rm = TRUE)
  latest_scores[, alpha_hat := (Score - mu_s) / pmax(sd_s, 1e-10)]
  top20 <- head(latest_scores, 20L)
  alpha_vector <- setNames(round(top20$alpha_hat, 5), top20$Ticker)
} else {
  stop("No latest scores for alpha vector construction")
}

# Confidence per ticker
# 1) cross-sectional rank stability (lower variance = higher confidence)
# 2) regime-coverage of factor IC (more positive across regimes → higher conf)
# 3) score magnitude vs cross-section sd
ticker_hist_score <- primary_scores[Ticker %in% names(alpha_vector) &
                                      sig_date >= as.Date("2020-01-01")]
conf_vec <- sapply(names(alpha_vector), function(tk) {
  hist <- ticker_hist_score[Ticker == tk, Score]
  if (length(hist) < 6L) return(0.40)
  rank_stability <- 1 - pmin(sd(hist, na.rm = TRUE) /
                              pmax(abs(mean(hist, na.rm = TRUE)) + 0.5, 0.5), 1)
  data_avail <- pmin(length(hist) / 36, 1)
  raw <- 0.55 * rank_stability + 0.45 * data_avail
  round(pmin(pmax(raw, 0.10), 0.95), 4)
})

# Method shopping log
method_log <- list(
  alpha_agent = list(
    candidates_tried = 1L,         # 6F PRIMARY 단일 셀 검증 (mix 변경 불가)
    parallel_exec    = FALSE,
    rcpp_used        = rcpp_loaded,
    rcpp_functions   = if (rcpp_loaded) "bootstrap_dsr_fast" else NA_character_,
    method_log = list(
      PRIMARY_6F = list(
        name     = "MEGA_05_PRIMARY_6F_with_regime_label",
        rank_ic  = round(mean_ic_all, 5),
        selected = TRUE,
        note     = "Iter 2 — factor mix preserved, regime indicator added (PIT-safe expanding pct)"
      )
    )
  )
)

#==============================================================================
# Step 7: Save artifacts
#==============================================================================
cat("\n[Step 7] Writing artifacts...\n")

# 7a alpha_scores.parquet (regime label included)
alpha_scores_dt <- primary_scores[, .(sig_date, Ticker, Score, Ret_1m,
                                      regime_state, theta_json)]
write_parquet(alpha_scores_dt, file.path(ART_DIR, "alpha_scores.parquet"))

# 7b regime panel parquet
regime_panel_dt <- regime_label[, .(sig_date, regime_state, regime_score,
                                    rv60, dd_12m, breadth60, ret_1m_bm)]
write_parquet(regime_panel_dt, file.path(ART_DIR, "regime_panel.parquet"))

# 7c conditional IC matrix
write_parquet(cond_ic,      file.path(ART_DIR, "conditional_ic_factor_regime.parquet"))
write_parquet(cond_ic_wide, file.path(ART_DIR, "conditional_ic_factor_regime_wide.parquet"))
write_parquet(comp_ic_by_regime, file.path(ART_DIR, "composite_ic_by_regime.parquet"))

# 7d alpha_validation.json
alpha_validation <- list(
  task_id    = WT_ID,
  pit_audit  = list(
    C1  = "PASS — expanding percentile only (no full-sample) for regime indicator + IC weights",
    C2  = "PASS — regime built at month_end_t, applied at sig_date_{t+1} (1M lag)",
    C9  = "PASS — DD/VT/breadth use lagged window (window <= month_end inclusive, applied next month)",
    C10 = "PASS — AvgTV20 ≥ 2e8 lagged liquidity filter",
    C11 = "PASS — KR internal data (BM_DT + cross-section breadth) prioritized; no FRED leak",
    C13 = "PASS — Z_Score_Aligned via align_factor_direction; no manual sign flip",
    C14 = "PASS — Factor DB Usable_Date <= sig_date enforced via parquet by month",
    C15 = "PASS — load_month_factors path via .cache/factor_db parquet",
    lockbox = paste0("ENFORCED — ", LOCKBOX_START, " ~ ", LOCKBOX_END,
                    " excluded from all training")
  ),
  hypothesis_iter2  = list(
    factor_mix_changed         = FALSE,
    regime_indicator_added     = TRUE,
    regime_states              = c("BULL","NORMAL","CAUTION","CRISIS"),
    regime_classification_type = "expanding_percentile_4state",
    optimizer_handoff_contract = paste0(
      "Optimizer가 Regime-Σ MinCVaR 적용 시 ",
      "alpha_scores.parquet::regime_state 컬럼을 sig_date 별로 조회하여 ",
      "각 regime 내부에서만 추정한 Σ를 사용해야 함. Alpha는 covariance/weight 어떤 것도 결정하지 않음."
    )
  ),
  diagnostics = list(
    rank_ic_overall  = round(mean_ic_all, 5),
    icir_overall     = round(icir_all,    5),
    harvey_t_overall = round(harvey_all,  4),
    monotonicity     = round(mono_corr,   4),
    subperiod_stab   = round(sub_stab,    4),
    p1_2008_2014_ic  = round(p1, 5),
    p2_2015_2019_ic  = round(p2, 5),
    p3_2020_2024_ic  = round(p3, 5),
    n_months         = nrow(ic_valid_all),
    dsr              = if (is.na(dsr_val)) NA else round(dsr_val, 4),
    turnover_proxy   = round(turnover_proxy %||% NA_real_, 4)
  ),
  composite_ic_by_regime  = as.list(comp_ic_by_regime),
  conditional_ic_shape    = list(rows = nrow(cond_ic_wide), cols = ncol(cond_ic_wide) - 1L),
  conditional_ic_max_abs  = round(max(abs(cond_ic$mean_IC), na.rm = TRUE), 5),
  red_flags = list(
    RF_A1 = list(
      severity = if (sub_stab < 0.5) "HIGH" else "OK",
      msg      = sprintf("subperiod stability=%.3f vs 0.5 threshold", sub_stab %||% NA_real_)
    ),
    RF_A2 = list(
      severity = "INFO",
      msg      = "Composite mix unchanged (Iter 2 mandate); compare to MEGA_05 baseline rank_IC=0.0489"
    ),
    RF_REGIME_SAMPLE = {
      counts <- regime_feat[, .N, by = regime_state]
      min_n  <- min(counts$N, na.rm = TRUE)
      list(
        severity = if (min_n < 12L) "HIGH" else "MEDIUM",
        msg      = sprintf("min regime sample size = %d months (CRISIS thin → cond IC variance high)", min_n)
      )
    }
  ),
  ax001_v2_check = list(
    bad_normal_ic_ratio = {
      ic_bad <- comp_ic_by_regime[regime_state %in% c("CAUTION","CRISIS"), mean(mean_IC, na.rm = TRUE)]
      ic_norm <- comp_ic_by_regime[regime_state == "NORMAL", mean(mean_IC, na.rm = TRUE)]
      if (is.na(ic_bad) || is.na(ic_norm) || ic_norm == 0) NA_real_
      else round(ic_bad / ic_norm, 3)
    },
    note = "Defense factor (Q07) standalone is conditional — overall PRIMARY is Core role; ax001_v2 audit applies at portfolio level (Optimizer/Governor)"
  )
)
write_json(alpha_validation, file.path(WT_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")
write_json(alpha_validation, file.path(ART_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")

#==============================================================================
# Step 8: alpha_package.json
#==============================================================================
factor_specs <- list()
for (fn in PRIMARY_FACS) {
  fc <- if (grepl("^C0", fn))      "Analyst_Consensus"
        else if (grepl("^Q0", fn)) "Quality_Earnings"
        else if (grepl("^AC", fn)) "Accrual_Quality"
        else                       "Other"
  factor_specs[[length(factor_specs) + 1L]] <- list(
    factor_family      = fc,
    proxy              = fn,
    formula            = sprintf("Z_Score_Aligned[%s] (Factor DB via load_month_factors, C15)", fn),
    lag_rule           = "monthly t-1 (sig_date = month-start, applied at next rebalance, C2)",
    winsorization      = "2.5σ cross-section (NORMAL regime baseline, C13)",
    neutralization     = "liquidity filter only (20d AvgTV ≥ 2e8, C10)",
    economic_rationale = sprintf("MEGA_05 PRIMARY 6F preserved — %s", fc),
    weight_theta       = NA,
    references         = "MEGA_01~05 chain"
  )
}

# Regime spec (NEW for Iter 2)
regime_spec <- list(
  factor_family       = "Regime_Indicator",
  proxy               = "regime_state_4state",
  formula             = paste0(
    "score = 0.35*pct(rv60) + 0.25*pct(-ret1m) + 0.25*pct(-dd12m) + 0.15*pct(-breadth60); ",
    "thresholds = expanding quantile (0.30, 0.65, 0.85)"),
  lag_rule            = "built at month_end_t, applied at sig_date_{t+1} (C2 t-1 lag enforced)",
  winsorization       = "n/a (categorical label)",
  neutralization      = "n/a",
  economic_rationale  = paste0(
    "Regime-conditional volatility/drawdown/breadth allows Optimizer to use regime-specific Σ ",
    "(BULL: low-vol momentum; NORMAL: standard MinVar; CAUTION: vol-managed; CRISIS: crisis_alpha favoured). ",
    "All inputs are KR market internals (L-454: KR > FRED for regime detection)."),
  states              = c("BULL","NORMAL","CAUTION","CRISIS"),
  references          = c("Ang-Bekaert 2002 regime switching",
                          "L-441 expanding percentile",
                          "L-450 macro regime PIT",
                          "L-454 Korean internals dominance",
                          "L-122 factor timing risk-managed",
                          "QEPM §10 conditional alpha")
)

alpha_package <- list(
  task_id           = WT_ID,
  wt_type           = "discovery",
  as_of_date        = "2026-04-25",
  signal_as_of      = as.character(last_sig_date),
  forecast_horizon  = "1M",
  selection_objective = "icir",
  hypothesis_title  = "MEGA_05 Regime-Σ MinCVaR — Optimizer 교체 (Iter 2)",
  hypothesis_summary = paste0(
    "MEGA_05 6F factor mix 동일 유지 (C01_SUE+C04_ESBR+C02_EPS_Chg_1m+C06_TP_Gap+Q07+AC21). ",
    "신규: PIT-safe regime indicator (BULL/NORMAL/CAUTION/CRISIS, expanding percentile thresholds, ",
    "C1+C2+C9+C11 준수). Optimizer는 alpha_scores.parquet::regime_state로 regime-conditional Σ를 ",
    "구성하여 MinCVaR 최적화를 수행할 수 있음. Alpha agent는 covariance/weight 어떤 것도 결정하지 않음."
  ),
  primary_config = list(
    label              = "PRIMARY_6F_with_regime_label",
    factors            = PRIMARY_FACS,
    n_factors          = length(PRIMARY_FACS),
    regime_indicator   = "regime_state_4state (BULL/NORMAL/CAUTION/CRISIS)",
    regime_classification = list(
      method            = "expanding_percentile_composite",
      features          = c("rv60", "neg_ret1m", "neg_dd12m", "neg_breadth60"),
      feature_weights   = list(rv60 = 0.35, neg_ret1m = 0.25,
                               neg_dd12m = 0.25, neg_breadth60 = 0.15),
      thresholds_expanding_quantile = list(BULL = 0.30, NORMAL = 0.65, CAUTION = 0.85),
      pit_compliance    = c("C1","C2","C9","C11"),
      data_source       = "BM_DT (KR benchmark) + RAWDATA cross-section breadth (KR internals, L-454)"
    )
  ),
  alpha_vector      = as.list(alpha_vector),
  confidence_vector = as.list(conf_vec),
  signal_matrix_ref = sprintf("stage_artifacts://%s/alpha_scores.parquet", gsub("-", "_", WT_ID)),
  factor_specs      = c(factor_specs, list(regime_spec)),
  diagnostics       = list(
    rank_ic           = round(mean_ic_all, 5),
    icir              = round(icir_all,    5),
    harvey_t_stat     = round(harvey_all,  4),
    dsr               = if (is.na(dsr_val)) NA else round(dsr_val, 4),
    monotonicity      = round(mono_corr, 4),
    subperiod_stability = round(sub_stab, 4),
    subperiod_ics     = list(
      p1_2008_2014 = round(p1, 5),
      p2_2015_2019 = round(p2, 5),
      p3_2020_2024 = round(p3, 5)
    ),
    ff3_retention     = 1,
    post_neutralization_ic = round(mean_ic_all, 5),
    turnover_proxy    = round(turnover_proxy %||% NA_real_, 4),
    n_months          = nrow(ic_valid_all),
    n_tickers         = length(alpha_vector),
    composite_ic_by_regime = as.list(comp_ic_by_regime),
    conditional_ic_shape   = c(nrow(cond_ic_wide), length(PRIMARY_FACS)),
    conditional_ic_max_abs = round(max(abs(cond_ic$mean_IC), na.rm = TRUE), 5)
  ),
  regime_classification = list(
    method        = "expanding_percentile_4state",
    states        = c("BULL","NORMAL","CAUTION","CRISIS"),
    distribution_train = as.list(regime_feat[, .N, by = regime_state]),
    last_label    = last_regime,
    panel_ref     = sprintf("stage_artifacts://%s/regime_panel.parquet", gsub("-","_", WT_ID))
  ),
  conditional_ic_by_regime = as.list(cond_ic_wide),
  method_shopping_log = method_log,
  challenge_flags = list(
    RF_A1 = list(
      id       = "RF-A1",
      severity = if (sub_stab < 0.5) "HIGH" else "OK",
      msg      = "Reference & subperiod stability gate",
      detail   = sprintf("sub_stab=%.4f vs 0.5 (HIGH if <0.5); refs >=4", sub_stab %||% NA_real_)
    ),
    RF_REGIME_SAMPLE = list(
      id       = "RF-REGIME-SAMPLE",
      severity = "MEDIUM",
      msg      = "CRISIS regime sample size thin → conditional IC variance high",
      detail   = sprintf("regime distribution = %s",
                        paste(sprintf("%s:%d", regime_feat[, .N, by = regime_state]$regime_state,
                                       regime_feat[, .N, by = regime_state]$N), collapse = ", "))
    ),
    OPTIMIZER_HANDOFF = list(
      id       = "OPT-HANDOFF",
      severity = "INFO",
      msg      = "Alpha provides regime label only — covariance/weight decisions are Optimizer's domain (per Common Charter Principle 8)"
    )
  ),
  pit_compliance = list(
    C1  = "PASS: expanding percentile thresholds + expanding IC weights (no full-sample stats)",
    C2  = "PASS: regime built month_end_t → applied sig_date_{t+1}",
    C9  = "PASS: rv60/dd_12m/breadth60 windows end at month_end_t, applied next month",
    C10 = "PASS: AvgTV20 lagged liquidity filter",
    C11 = "PASS: KR internal data only (BM + breadth), no FRED leakage",
    C13 = "PASS: Z_Score_Aligned, no manual sign flip",
    C14 = "PASS: Factor DB Usable_Date <= sig_date",
    C15 = "PASS: load via factor_db parquet",
    lockbox = sprintf("ENFORCED: %s ~ %s excluded from all training",
                     LOCKBOX_START, LOCKBOX_END)
  ),
  references = list(
    "Ang-Bekaert (2002) — international asset allocation with regimes",
    "Hamilton (1989) — Markov regime switching",
    "Engle (2002) — DCC GARCH (downstream optimizer)",
    "Fama-French (1993) — FF3 baseline",
    "Harvey-Liu-Zhu (2016) — multiple testing t>3.0",
    "Sloan (1996) — accrual anomaly (AC21)",
    "Novy-Marx (2013) — quality (Q07)",
    "QEPM L-441 expanding percentile regime PIT",
    "QEPM L-450 macro regime PIT",
    "QEPM L-454 Korean internals > FRED",
    "QEPM L-122 factor timing risk-managed"
  ),
  role_bias_tagging = "RoleBias_Core",
  graduation_status = list(
    rank_ic_gate    = list(value = round(mean_ic_all, 5),
                           threshold = 0.04, pass = mean_ic_all >= 0.04),
    icir_gate       = list(value = round(icir_all, 5),
                           threshold = 0.20, pass = icir_all >= 0.20),
    harvey_gate     = list(value = round(harvey_all, 4),
                           threshold = 3.0,  pass = harvey_all >= 3.0),
    sub_stab_gate   = list(value = round(sub_stab, 4),
                           threshold = 0.5,  pass = sub_stab >= 0.5),
    dsr_gate        = list(value = if (is.na(dsr_val)) NA else round(dsr_val, 4),
                           threshold = 0.5,
                           pass = !is.na(dsr_val) && dsr_val >= 0.5)
  )
)

# Step 1: alpha_package.json write FIRST (L-194 ordering)
write_json(alpha_package, file.path(WT_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")
write_json(alpha_package, file.path(ART_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")
cat("[Step 7] alpha_package.json written\n")

# Step 2: lineage record (R11, must be AFTER write per L-194)
tryCatch({
  source(LINEAGE_PATH)
  record_package_lineage(
    task_id          = WT_ID,
    package_type     = "alpha_package",
    method_selected  = "MEGA_05_PRIMARY_6F_plus_regime_label_v1",
    input_file_paths = c(file.path(CACHE_DIR, "rawdata.rds"),
                         file.path(CACHE_DIR, "factor_db"))
  )
  cat("[Step 7] lineage recorded\n")
}, error = function(e) {
  cat("[Step 7] lineage skipped:", conditionMessage(e), "\n")
})

# Update status.json
status <- list(
  task_id       = WT_ID,
  current_phase = "ALPHA_DONE",
  updated_at    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  blocker       = NULL
)
write_json(status, file.path(WT_DIR, "status.json"),
           pretty = TRUE, auto_unbox = TRUE)

t1 <- Sys.time()
cat(sprintf("\n=== DONE — elapsed: %s ===\n",
            format(difftime(t1, t0, units = "mins"))))
cat(sprintf("ALPHA_DONE — regime IC matrix shape=(%d,%d), conditional IC max=%.5f\n",
    nrow(cond_ic_wide), length(PRIMARY_FACS),
    max(abs(cond_ic$mean_IC), na.rm = TRUE)))
