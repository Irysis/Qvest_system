cat("=== STR_1679: Score Blend + M29 Full Stack (HRP+ScoreTilt, Bimonthly) ===\n")
## 핵심 아이디어: C19(ICIR) + Defense(Q07+D29) Score-Level 블렌드 + M29 전체 스택
## Factor 축: ICIR scaling (IC_mean/IC_vol) — Barroso & Santa-Clara
## Stock 축: 0.6×HRP(Gerber+RMT) + 0.4×Score Tilt — M29 동일
## 구조: 격월 리밸런싱 (M19)
## MRS Conditional: Defense 비중 Normal(95/5) | Caution(80/20) | Crisis(60/40)
## 30종목 제약 준수 (L-484)
## C1: expanding IC only | C2: t-1 lag | C5: MRS t-1 | C13: Z_Score_Aligned | C15: Factor DB 경유
## Ref: Arnott et al.(2019), Barroso & Santa-Clara (2015)
## S5 artifact: s5_research_slate_STR_1679_score_blend.json

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

# --- Parameters ---
LIQ_THRESHOLD  <- 2e8
N_HOLD         <- 30L     # Score blend: 30 stocks (L-484 compliant)
MAX21D_EXCL    <- 0.80
IC_MIN_MONTHS  <- 12L
IC_VOL_WINDOW  <- 12L
COMMISSION     <- 0.0015
REBAL_MONTHS   <- 2L      # M29: bimonthly rebalancing
HRP_LOOKBACK   <- 60L     # M29: HRP lookback days
HRP_TILT_W     <- 0.6     # M29: 0.6*HRP + 0.4*ScoreTilt
SCORE_TILT_W   <- 0.4

# MRS thresholds for score blend weights
MRS_NORMAL_THRESH   <- 20
MRS_CRISIS_THRESH   <- 50

cat(sprintf("[STR_1679] Score Blend + M29 Full Stack | N=%d | Bimonthly | HRP(%.0f%%)+ScoreTilt(%.0f%%)\n",
            N_HOLD, HRP_TILT_W*100, SCORE_TILT_W*100))

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
ALL_SIG_DATES <- sd_dt$sig_date   # all monthly dates (for IC computation)
SIG_DATES     <- ALL_SIG_DATES[seq(1, length(ALL_SIG_DATES), by = REBAL_MONTHS)]  # bimonthly
cat(sprintf("[Step 1] Monthly dates: %d | Bimonthly SIG_DATES: %d (%s ~ %s)\n",
            length(ALL_SIG_DATES), length(SIG_DATES), min(SIG_DATES), max(SIG_DATES)))

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

# ===================================================================
# 2. Load Consensus (C19 sub-factors)
# ===================================================================
cat("\n[Step 2] Loading Consensus...\n")
lc <- function(f) {
  dt <- as.data.table(read_parquet(file.path(CONS_DIR, f))); dt[, Date := as.Date(Date)]
  dt <- dt[Date >= ANALYSIS_START_DATE]; setkey(dt, Ticker, Date)
  cat(sprintf("  > %s: %s rows\n", f, format(nrow(dt), big.mark = ",")))
  dt
}
SUE_DT   <- lc("sue.parquet")
ESBR_DT  <- lc("esbr.parquet")
EPS1M_DT <- lc("eps_chg_1m.parquet")
COV_DT   <- lc("coverage.parquet")
TP_DT    <- lc("target_price.parquet")

# ===================================================================
# 3. Bulk-load Factor DB for Q07, D29, D04 (C15 compliant, OPT-1)
#    Per-file read with col_select for 3 factors only (fast)
# ===================================================================
cat("\n[Step 3] Bulk-loading Factor DB (Q07, D29, D04)...\n")
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

NEEDED_FACTORS <- c("Q07_Earnings_Stability", "D29_Accounting_Beta", "D04_Downside_Beta")
fdb_dir <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
cat(sprintf("  Found %d parquet files. Reading 3 factors only...\n", length(fdb_files)))

FDB_ALL <- rbindlist(lapply(fdb_files, function(fp) {
  ym <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  sig_match <- ALL_SIG_DATES[format(ALL_SIG_DATES, "%Y%m") == ym]
  if (length(sig_match) == 0) return(NULL)
  dt <- tryCatch(as.data.table(arrow::read_parquet(fp,
    col_select = c("Ticker", "Factor_Name", "Z_Score", "Coverage"))), error = function(e) NULL)
  if (is.null(dt)) return(NULL)
  dt <- dt[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE, .(Ticker, Factor_Name, Z_Score)]
  if (nrow(dt) == 0) return(NULL)
  dt[, Date := sig_match[1]]
  dt
}), use.names = TRUE, fill = TRUE)

# Apply direction alignment (C13: Z_Score_Aligned)
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
if ("Z_Score_Aligned" %in% names(FDB_ALL)) {
  FDB_ALL[, Z_Score := Z_Score_Aligned]
  FDB_ALL[, Z_Score_Aligned := NULL]
}

setkey(FDB_ALL, Date, Ticker)
cat(sprintf("[Step 3] Factor DB bulk loaded: %s rows, %d months, %d factors\n",
            format(nrow(FDB_ALL), big.mark = ","), uniqueN(FDB_ALL$Date), uniqueN(FDB_ALL$Factor_Name)))

# Pre-pivot to wide format once (OPT-1: no per-date I/O in scoring loop)
FDB_WIDE <- dcast(FDB_ALL, Date + Ticker ~ Factor_Name, value.var = "Z_Score")
setkey(FDB_WIDE, Date, Ticker)
q07_col <- "Q07_Earnings_Stability"
d29_col <- "D29_Accounting_Beta"
d04_col <- "D04_Downside_Beta"
if (!q07_col %in% names(FDB_WIDE)) FDB_WIDE[, (q07_col) := NA_real_]
if (!d29_col %in% names(FDB_WIDE)) FDB_WIDE[, (d29_col) := NA_real_]
if (!d04_col %in% names(FDB_WIDE)) FDB_WIDE[, (d04_col) := NA_real_]
rm(FDB_ALL); gc(verbose = FALSE)

# ===================================================================
# 4. Compute expanding IC + raw z-scores for all months
# ===================================================================
cat("\n[Step 4] Computing expanding IC + raw z-scores...\n")
z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

# Step 4a: forward returns
fwd_map <- setNames(lapply(seq_along(ALL_SIG_DATES), function(i) {
  sd <- ALL_SIG_DATES[i]
  if (i >= length(ALL_SIG_DATES)) return(NULL)
  next_sd <- ALL_SIG_DATES[i + 1]
  RAWDATA[Date > sd & Date <= next_sd, .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
}), as.character(ALL_SIG_DATES))

# Step 4b: raw consensus z-scores for each month
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

# Step 4c: expanding IC history (C1 safe: past-only)
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
cat(sprintf("[Step 4c] IC history: %d months\n", nrow(ic_history)))

rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT); gc(verbose = FALSE)

# ===================================================================
# 5. Load MRS for regime-conditional weights (t-1 lag, C5)
# ===================================================================
cat("\n[Step 5] Loading MRS...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME <- build_daily_regime(use_cache = TRUE); setkey(REGIME, Date)

# Month-end MRS, then t-1 lag
reg_monthly <- REGIME[, .(mrs_eom = last(MRS)), by = .(YM = format(Date, "%Y-%m"))]
setorder(reg_monthly, YM)
reg_monthly[, mrs_lag := shift(mrs_eom, n = 1L, type = "lag")]
reg_monthly[is.na(mrs_lag), mrs_lag := 0]
cat(sprintf("[Step 5] MRS months: %d | Normal(<20)=%d | Caution(20-50)=%d | Crisis(50+)=%d\n",
  nrow(reg_monthly),
  sum(reg_monthly$mrs_lag < MRS_NORMAL_THRESH),
  sum(reg_monthly$mrs_lag >= MRS_NORMAL_THRESH & reg_monthly$mrs_lag < MRS_CRISIS_THRESH),
  sum(reg_monthly$mrs_lag >= MRS_CRISIS_THRESH)))

# ===================================================================
# 6. Score-Level Blend: 3 variants (vectorized, no loop I/O)
# ===================================================================
cat("\n[Step 6] Building Score-Level Blend portfolios...\n")

# Build FACTORS for 3 strategies via lapply (no loop-internal I/O)
build_month <- function(i) {
  sd <- SIG_DATES[i]
  sc <- RAW_SCORES[Date == sd]; if (nrow(sc) < 20L) return(NULL)

  # --- IC-weighted C19 scores (expanding, C1 safe) ---
  past_ic <- ic_history[Date < sd]
  if (nrow(past_ic) < IC_MIN_MONTHS) {
    w_c19 <- c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25)
  } else {
    mean_ic <- c(sue = mean(past_ic$ic_sue, na.rm = TRUE), esbr = mean(past_ic$ic_esbr, na.rm = TRUE),
                 eps1m = mean(past_ic$ic_eps1m, na.rm = TRUE), tpgap = mean(past_ic$ic_tpgap, na.rm = TRUE))
    recent_ic <- tail(past_ic, IC_VOL_WINDOW)
    vol_ic <- c(sue = sd(recent_ic$ic_sue, na.rm = TRUE), esbr = sd(recent_ic$ic_esbr, na.rm = TRUE),
                eps1m = sd(recent_ic$ic_eps1m, na.rm = TRUE), tpgap = sd(recent_ic$ic_tpgap, na.rm = TRUE))
    vol_ic <- pmax(vol_ic, 0.01)
    mean_ic_pos <- pmax(mean_ic, 0)
    icir <- mean_ic_pos / vol_ic
    ic_sum <- sum(icir)
    w_c19 <- if (ic_sum < 1e-8) c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25) else icir / ic_sum
  }

  # C19 composite z-score
  sc[, z_c19 := w_c19["sue"] * z_sue + w_c19["esbr"] * z_esbr +
                w_c19["eps1m"] * z_eps1m + w_c19["tpgap"] * z_tpgap]

  # --- Strategy C: Core only, Top 30 ---
  setorder(sc, -z_c19)
  top_core <- head(sc, N_HOLD)
  fac_C <- data.table(Date = sd, Ticker = top_core$Ticker, Score = top_core$z_c19)

  # --- Defense z-scores from pre-loaded FDB_WIDE (memory lookup, no I/O) ---
  def_scores <- FDB_WIDE[Date == sd & Ticker %in% sc$Ticker]

  if (nrow(def_scores) < 10L) {
    # Fallback: no defense data => all three are pure core
    comp <- data.table(Date = sd, n_univ = nrow(sc), n_def = 0L,
      w_core = 1, w_def = 0, regime = "FALLBACK", n_core_dominant = N_HOLD, n_defense_dominant = 0L)
    return(list(A = fac_C, B = fac_C, C = fac_C, comp = comp, icw = w_c19))
  }

  # Merge C19 + defense
  blend_dt <- merge(sc[, .(Ticker, z_c19)], def_scores[, .(Ticker, Q07_Earnings_Stability, D29_Accounting_Beta, D04_Downside_Beta)],
                    by = "Ticker", all.x = TRUE)

  # D04 filter: remove bottom 10% (Z_Score_Aligned: higher = better = lower downside beta)
  if (sum(!is.na(blend_dt$D04_Downside_Beta)) > 10) {
    d04_thresh <- quantile(blend_dt$D04_Downside_Beta, 0.10, na.rm = TRUE)
    blend_dt <- blend_dt[is.na(D04_Downside_Beta) | D04_Downside_Beta >= d04_thresh]
  }

  # Defense composite: 0.80*Q07 + 0.20*D29
  blend_dt[, z_def := NA_real_]
  has_q07 <- !is.na(blend_dt$Q07_Earnings_Stability)
  has_d29 <- !is.na(blend_dt$D29_Accounting_Beta)
  blend_dt[has_q07 & has_d29, z_def := 0.80 * Q07_Earnings_Stability + 0.20 * D29_Accounting_Beta]
  blend_dt[has_q07 & !has_d29, z_def := Q07_Earnings_Stability]
  blend_dt[!has_q07 & has_d29, z_def := D29_Accounting_Beta]

  # Re-standardize to same scale
  blend_dt[, z_c19_std := z_safe(z_c19)]
  blend_dt[, z_def_std := z_safe(z_def)]
  blend_dt[is.na(z_def_std), z_def_std := 0]
  blend_dt[is.na(z_c19_std), z_c19_std := 0]

  # --- (A) MRS conditional blend ---
  ym_tag <- format(sd, "%Y-%m")
  mrs_row <- reg_monthly[YM == ym_tag]
  mrs_val <- if (nrow(mrs_row) > 0) mrs_row$mrs_lag[1] else 0

  if (mrs_val >= MRS_CRISIS_THRESH) {
    w_core_a <- 0.60; w_def_a <- 0.40; regime_label <- "CRISIS"
  } else if (mrs_val >= MRS_NORMAL_THRESH) {
    w_core_a <- 0.80; w_def_a <- 0.20; regime_label <- "CAUTION"
  } else {
    w_core_a <- 0.95; w_def_a <- 0.05; regime_label <- "NORMAL"
  }

  blend_dt[, final_score_A := w_core_a * z_c19_std + w_def_a * z_def_std]
  setorder(blend_dt, -final_score_A)
  top_A <- head(blend_dt[!is.na(final_score_A)], N_HOLD)
  fac_A <- data.table(Date = sd, Ticker = top_A$Ticker, Score = top_A$final_score_A)

  # --- (B) Static 80/20 blend ---
  blend_dt[, final_score_B := 0.80 * z_c19_std + 0.20 * z_def_std]
  setorder(blend_dt, -final_score_B)
  top_B <- head(blend_dt[!is.na(final_score_B)], N_HOLD)
  fac_B <- data.table(Date = sd, Ticker = top_B$Ticker, Score = top_B$final_score_B)

  # Composition tracking
  n_core_dom <- sum(top_A$z_c19_std > top_A$z_def_std, na.rm = TRUE)
  comp <- data.table(Date = sd, n_univ = nrow(sc), n_def = sum(!is.na(blend_dt$z_def)),
    w_core = w_core_a, w_def = w_def_a, regime = regime_label,
    n_core_dominant = n_core_dom, n_defense_dominant = N_HOLD - n_core_dom)

  list(A = fac_A, B = fac_B, C = fac_C, comp = comp, icw = w_c19)
}

month_results <- lapply(seq_along(SIG_DATES), build_month)
month_results <- month_results[!sapply(month_results, is.null)]

FACTORS_A <- rbindlist(lapply(month_results, `[[`, "A"))
FACTORS_B <- rbindlist(lapply(month_results, `[[`, "B"))
FACTORS_C <- rbindlist(lapply(month_results, `[[`, "C"))
BLEND_COMP <- rbindlist(lapply(month_results, `[[`, "comp"))
ic_weight_log <- setNames(lapply(month_results, `[[`, "icw"),
  sapply(month_results, function(r) as.character(r$A$Date[1])))

cat(sprintf("[Step 6] FACTORS_A (MRS cond): %d rows, %d months\n", nrow(FACTORS_A), uniqueN(FACTORS_A$Date)))
cat(sprintf("[Step 6] FACTORS_B (static 80/20): %d rows, %d months\n", nrow(FACTORS_B), uniqueN(FACTORS_B$Date)))
cat(sprintf("[Step 6] FACTORS_C (core only): %d rows, %d months\n", nrow(FACTORS_C), uniqueN(FACTORS_C$Date)))

# Verify 30-stock constraint
max_n_A <- FACTORS_A[, .N, by = Date][, max(N)]
max_n_B <- FACTORS_B[, .N, by = Date][, max(N)]
max_n_C <- FACTORS_C[, .N, by = Date][, max(N)]
cat(sprintf("[VERIFY] Max stocks: A=%d, B=%d, C=%d (must be <=30)\n", max_n_A, max_n_B, max_n_C))
stopifnot(max_n_A <= 30, max_n_B <= 30, max_n_C <= 30)

rm(RAW_SCORES, SIG_SNAP, FDB_WIDE, month_results); gc(verbose = FALSE)

# ===================================================================
# 7. HRP + Score Tilt Hybrid Weights (M29 full stack)
# ===================================================================
cat("\n[Step 7] Computing HRP-Score Tilt Hybrid weights (bimonthly)...\n")

# Gerber + RMT + HRP functions (from M29)
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

# Compute HRP+ScoreTilt for primary variant (FACTORS_A = MRS conditional)
compute_hrp_for_factors <- function(FACTORS_dt) {
  FACTORS_hrp <- copy(FACTORS_dt); FACTORS_hrp[, Weight_hrp := NA_real_]
  hrp_success <- 0L; hrp_fallback <- 0L

  all_sig_dates_sorted <- sort(unique(FACTORS_dt$Date))
  prev_score_map <- list()
  invisible(lapply(seq_along(all_sig_dates_sorted), function(k) {
    d <- all_sig_dates_sorted[k]
    if (k == 1L) { prev_score_map[[as.character(d)]] <<- NULL
    } else {
      prev_d <- all_sig_dates_sorted[k - 1]
      prev_score_map[[as.character(d)]] <<- FACTORS_dt[Date == prev_d, .(Ticker, Score)]
    }
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
    # Score Tilt: use t-1 frozen scores (C5 safe)
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
    if (r$fb) hrp_fallback <<- hrp_fallback + 1L else hrp_success <<- hrp_success + 1L
  }))
  cat(sprintf("[Step 7] HRP: %d success, %d EW fallback\n", hrp_success, hrp_fallback))
  list(FACTORS_hrp = FACTORS_hrp, hrp_results = hrp_results)
}

# Build HRP weight maps for each variant
cat("  Computing HRP for MRS Conditional (A)...\n")
hrp_A <- compute_hrp_for_factors(FACTORS_A)
cat("  Computing HRP for Core Only (C)...\n")
hrp_C <- compute_hrp_for_factors(FACTORS_C)

# ===================================================================
# 7b. Run backtests (HRP+ScoreTilt, bimonthly) via weight injection
# ===================================================================
cat("\n[Step 7b] Running backtests with HRP+ScoreTilt weights...\n")

run_bt_hrp <- function(FACTORS_dt, hrp_obj, label) {
  cat(sprintf("  [%s] Running HRP+ScoreTilt backtest...\n", label))
  hwl <- list()
  invisible(lapply(as.character(unique(hrp_obj$FACTORS_hrp$Date)), function(d) {
    mf <- hrp_obj$FACTORS_hrp[Date == as.Date(d)]; w <- mf$Weight_hrp
    if (all(is.na(w))) w <- rep(1 / nrow(mf), nrow(mf))
    hwl[[d]] <<- setNames(w, mf$Ticker)
  }))
  # Inject HRP weights via calc_ivol_weights override
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
  sim <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_dt, n_holdings = N_HOLD,
    weight_method = "ivol", commission = COMMISSION,
    buffer_zone = list(keep_n = N_HOLD + 5L, entry_n = N_HOLD))
  calc_ivol_weights <<- oi
  perf <- summarise_perf(sim$strategy_xts, label)
  to <- calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT)
  list(sim = sim, perf = perf, turnover = to)
}

# Also run EW variant for comparison
run_bt_ew <- function(factors_dt, label) {
  cat(sprintf("  [%s] Running EW backtest...\n", label))
  sim <- run_monthly_simulation(RAWDATA, BM_DT, factors_dt,
    n_holdings = N_HOLD, weight_method = "equal", commission = COMMISSION,
    buffer_zone = list(keep_n = N_HOLD + 5L, entry_n = N_HOLD))
  perf <- summarise_perf(sim$strategy_xts, label)
  to <- calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT)
  list(sim = sim, perf = perf, turnover = to)
}

res_A   <- run_bt_hrp(FACTORS_A, hrp_A, "MRS_Cond_HRP")
res_A_ew <- run_bt_ew(FACTORS_A, "MRS_Cond_EW")
res_C   <- run_bt_hrp(FACTORS_C, hrp_C, "Core_HRP")
res_C_ew <- run_bt_ew(FACTORS_C, "Core_EW")

# ===================================================================
# 8. Regime Overlay (3-Layer, M29 identical)
# ===================================================================
cat("\n[Step 8] Applying Regime Overlay...\n")
ip <- file.path(CACHE_DIR, "kodex_inverse_114800.csv")
ID <- if (file.exists(ip)) { dt <- fread(ip); dt[, Date := as.Date(Date)]; setkey(dt, Date); dt } else NULL

apply_overlay <- function(sim_obj, label) {
  nd <- copy(sim_obj$DAILY_NAV_DT); setkey(nd, Date)
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
    idx <- seq_len(.N)
    sapply(idx, function(j) { if (nd$crisis_flag[j] == 1L) cnt <<- cnt + 1L else cnt <<- 0L; out[j] <<- cnt })
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
  po <- summarise_perf(ov_xts, paste0(label, "_OV"))
  list(nd = nd, ov_xts = ov_xts, perf_ov = po)
}

ov_A <- apply_overlay(res_A$sim, "MRS_HRP")
ov_C <- apply_overlay(res_C$sim, "Core_HRP")
ov_A_ew <- apply_overlay(res_A_ew$sim, "MRS_EW")

# ===================================================================
# 8b. Performance summary
# ===================================================================
cat("\n================================================================\n")
cat("   STR_1679: Score Blend + M29 Full Stack\n")
cat("================================================================\n")

cat("\n--- PRIMARY: (A) MRS Conditional + HRP+ScoreTilt + Bimonthly ---\n")
cat("  Base:\n"); print(res_A$perf)
cat(sprintf("  Turnover: %.1f%%\n", res_A$turnover))
cat("  Overlay:\n"); print(ov_A$perf_ov)

cat("\n--- COMPARISON: (A) MRS Conditional + EW + Bimonthly ---\n")
cat("  Base:\n"); print(res_A_ew$perf)
cat(sprintf("  Turnover: %.1f%%\n", res_A_ew$turnover))
cat("  Overlay:\n"); print(ov_A_ew$perf_ov)

cat("\n--- COMPARISON: (C) Core Only + HRP + Bimonthly ---\n")
cat("  Base:\n"); print(res_C$perf)
cat(sprintf("  Turnover: %.1f%%\n", res_C$turnover))
cat("  Overlay:\n"); print(ov_C$perf_ov)

cat("\n--- COMPARISON: (C) Core Only + EW + Bimonthly ---\n")
print(res_C_ew$perf)
cat(sprintf("  Turnover: %.1f%%\n", res_C_ew$turnover))

cat("\n--- Benchmark ---\n")
perf_bm <- summarise_perf(res_A$sim$bm_xts, "KOSPI200")
print(perf_bm)

# Regime allocation summary
if (nrow(BLEND_COMP) > 0) {
  cat("\n--- Regime Allocation ---\n")
  cat(sprintf("  Normal (95/5):  %d months\n", sum(BLEND_COMP$regime == "NORMAL")))
  cat(sprintf("  Caution (80/20): %d months\n", sum(BLEND_COMP$regime == "CAUTION")))
  cat(sprintf("  Crisis (60/40):  %d months\n", sum(BLEND_COMP$regime == "CRISIS")))
  cat(sprintf("  Fallback:        %d months\n", sum(BLEND_COMP$regime == "FALLBACK")))
  cat(sprintf("  Avg core-dominant stocks: %.1f / %d\n",
    mean(BLEND_COMP$n_core_dominant, na.rm = TRUE), N_HOLD))
}

# ===================================================================
# 9. Hurdle Gate (primary = overlay A)
# ===================================================================
cat("\n[Step 9] Running Hurdle Gate...\n")
source(file.path(FUNC_PATH, "hurdle_gate.R"))

# Primary: MRS + HRP + Overlay
sim_ov_A <- list(strategy_xts = ov_A$ov_xts, bm_xts = res_A$sim$bm_xts,
  DAILY_NAV_DT = ov_A$nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)],
  PORTFOLIO_LOG = res_A$sim$PORTFOLIO_LOG)
hr_A <- run_hurdle_gate(sim_ov_A, FACTORS_A,
  strategy_name = "STR_1679_full_mrs_hrp_overlay", output_dir = OUT_DIR)

# Base (no overlay) for comparison
hr_A_base <- run_hurdle_gate(res_A$sim, FACTORS_A,
  strategy_name = "STR_1679_mrs_hrp_base", output_dir = OUT_DIR)

# EW comparison
hr_A_ew <- run_hurdle_gate(res_A_ew$sim, FACTORS_A,
  strategy_name = "STR_1679_mrs_ew_base", output_dir = OUT_DIR)

cat("\n--- Hurdle Results ---\n")
cat(sprintf("  PRIMARY (A+HRP+OV): pass=%s, score=%s, grade=%s\n",
  hr_A$pass, hr_A$score, ifelse(is.null(hr_A$grade), "N/A", hr_A$grade)))
cat(sprintf("  A+HRP base:         pass=%s, score=%s, grade=%s\n",
  hr_A_base$pass, hr_A_base$score, ifelse(is.null(hr_A_base$grade), "N/A", hr_A_base$grade)))
cat(sprintf("  A+EW base:          pass=%s, score=%s, grade=%s\n",
  hr_A_ew$pass, hr_A_ew$score, ifelse(is.null(hr_A_ew$grade), "N/A", hr_A_ew$grade)))

# ===================================================================
# 10. Charts
# ===================================================================
cat("\n[Step 10] Generating charts...\n")

# Equity curve comparison (5 lines: primary + comparisons)
nav_fn <- function(ret_xts) data.table(Date = index(ret_xts), NAV = as.numeric(cumprod(1 + ret_xts)))
nav_all <- rbindlist(list(
  nav_fn(ov_A$ov_xts)[, Strategy := "MRS+HRP+Overlay (PRIMARY)"],
  nav_fn(res_A$sim$strategy_xts)[, Strategy := "MRS+HRP Base"],
  nav_fn(res_A_ew$sim$strategy_xts)[, Strategy := "MRS+EW Base (prev)"],
  nav_fn(res_C$sim$strategy_xts)[, Strategy := "Core+HRP (M29 N=30)"],
  nav_fn(res_A$sim$bm_xts)[, Strategy := "KOSPI200"]
))
nav_all[, Strategy := factor(Strategy, levels = c("MRS+HRP+Overlay (PRIMARY)", "MRS+HRP Base",
  "MRS+EW Base (prev)", "Core+HRP (M29 N=30)", "KOSPI200"))]

p1 <- ggplot(nav_all, aes(x = Date, y = NAV, color = Strategy)) +
  geom_line(aes(linewidth = Strategy)) +
  scale_linewidth_manual(values = c("MRS+HRP+Overlay (PRIMARY)" = 1.2, "MRS+HRP Base" = 0.8,
    "MRS+EW Base (prev)" = 0.6, "Core+HRP (M29 N=30)" = 0.6, "KOSPI200" = 0.5)) +
  scale_y_log10(labels = comma) +
  scale_color_manual(values = c("MRS+HRP+Overlay (PRIMARY)" = "#D32F2F", "MRS+HRP Base" = "#F44336",
    "MRS+EW Base (prev)" = "#E91E63", "Core+HRP (M29 N=30)" = "#2196F3", "KOSPI200" = "#9E9E9E")) +
  labs(title = "STR_1679: Score Blend + M29 Full Stack",
       subtitle = sprintf("N=%d | HRP(Gerber+RMT)+ScoreTilt(60/40) | Bimonthly | C19(ICIR)+Q07+D29", N_HOLD),
       x = NULL, y = "NAV (log scale)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", legend.title = element_blank()) +
  guides(linewidth = "none")
ggsave(file.path(OUT_DIR, "equity_curve.png"), p1, width = 12, height = 7, dpi = 150)

# Drawdown comparison
dd_fn <- function(ret_xts) {
  nav <- cumprod(1 + as.numeric(ret_xts))
  peak <- cummax(nav)
  (nav - peak) / peak * 100
}
dd_dt <- rbindlist(list(
  data.table(Date = index(ov_A$ov_xts), DD = dd_fn(ov_A$ov_xts), Strategy = "MRS+HRP+Overlay"),
  data.table(Date = index(res_A$sim$strategy_xts), DD = dd_fn(res_A$sim$strategy_xts), Strategy = "MRS+HRP Base"),
  data.table(Date = index(res_A_ew$sim$strategy_xts), DD = dd_fn(res_A_ew$sim$strategy_xts), Strategy = "MRS+EW (prev)")
))

p2 <- ggplot(dd_dt, aes(x = Date, y = DD, color = Strategy)) +
  geom_line(linewidth = 0.6, alpha = 0.8) +
  scale_color_manual(values = c("MRS+HRP+Overlay" = "#D32F2F", "MRS+HRP Base" = "#F44336",
    "MRS+EW (prev)" = "#E91E63")) +
  labs(title = "STR_1679: Drawdown Comparison", x = NULL, y = "Drawdown (%)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom", legend.title = element_blank())
ggsave(file.path(OUT_DIR, "drawdown.png"), p2, width = 12, height = 7, dpi = 150)

# Annual returns
annual_fn <- function(ret_xts, label) {
  dt <- data.table(Date = index(ret_xts), Ret = as.numeric(ret_xts))
  dt[, Year := year(Date)]
  dt[, .(AnnRet = (prod(1 + Ret, na.rm = TRUE) - 1) * 100, Strategy = label), by = Year]
}
ann_dt <- rbindlist(list(
  annual_fn(ov_A$ov_xts, "MRS+HRP+OV"),
  annual_fn(res_A$sim$strategy_xts, "MRS+HRP Base"),
  annual_fn(res_A_ew$sim$strategy_xts, "MRS+EW (prev)"),
  annual_fn(res_A$sim$bm_xts, "KOSPI200")
))

p3 <- ggplot(ann_dt, aes(x = factor(Year), y = AnnRet, fill = Strategy)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("MRS+HRP+OV" = "#D32F2F", "MRS+HRP Base" = "#F44336",
    "MRS+EW (prev)" = "#E91E63", "KOSPI200" = "#9E9E9E")) +
  labs(title = "STR_1679: Annual Returns", x = NULL, y = "Annual Return (%)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", legend.title = element_blank(),
        axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(OUT_DIR, "annual_returns.png"), p3, width = 14, height = 7, dpi = 150)

# Also generate standard charts via harness for hurdle attachment
generate_charts(list(strategy_xts = ov_A$ov_xts, bm_xts = res_A$sim$bm_xts,
  DAILY_NAV_DT = ov_A$nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)]),
  output_dir = OUT_DIR, strategy_name = "STR_1679 Score Blend + M29 Full Stack")

# ===================================================================
# 11. Save artifacts
# ===================================================================
cat("\n[Step 11] Saving artifacts...\n")

# IC weight evolution
ic_wt_dt <- rbindlist(lapply(seq_along(ic_weight_log), function(idx) {
  w <- ic_weight_log[[idx]]
  d <- tryCatch(as.Date(names(ic_weight_log)[idx]), error = function(e) as.Date(NA))
  data.table(Date = d, w_sue = w["sue"], w_esbr = w["esbr"],
             w_eps1m = w["eps1m"], w_tpgap = w["tpgap"])
}))
ic_wt_dt <- ic_wt_dt[!is.na(Date)]
fwrite(ic_wt_dt, file.path(OUT_DIR, "ic_weight_evolution.csv"))

# Blend composition log
fwrite(BLEND_COMP, file.path(OUT_DIR, "blend_composition.csv"))

# Performance JSON
write_json(list(
  strategy = "STR_1679_score_blend_full_stack",
  description = "Score-level C19(ICIR)+Defense(Q07+D29) blend + M29 full stack: HRP(Gerber+RMT)+ScoreTilt(60/40), bimonthly, 3-layer overlay",
  mutation = "M29 full stack applied to score blend: EW->HRP+ScoreTilt, monthly->bimonthly, +overlay",
  parent = "STR_1679_score_blend (EW monthly SR 1.075)",
  axes = list(
    factor = "ICIR scaling (IC_mean/IC_vol, Barroso & Santa-Clara)",
    stock = "0.6*HRP(Gerber+RMT) + 0.4*Score Tilt (t-1 frozen)",
    structure = "bimonthly rebalancing",
    overlay = "3-layer MRS regime overlay",
    defense = "MRS conditional: Normal(95/5) | Caution(80/20) | Crisis(60/40)"
  ),
  primary_overlay = list(
    perf = as.list(ov_A$perf_ov),
    hurdle_pass = hr_A$pass, hurdle_score = hr_A$score,
    hurdle_grade = ifelse(is.null(hr_A$grade), "N/A", hr_A$grade)
  ),
  primary_base = list(
    perf = as.list(res_A$perf), turnover = res_A$turnover,
    hurdle_pass = hr_A_base$pass, hurdle_score = hr_A_base$score
  ),
  comparison_ew_base = list(
    perf = as.list(res_A_ew$perf), turnover = res_A_ew$turnover,
    hurdle_pass = hr_A_ew$pass, hurdle_score = hr_A_ew$score,
    note = "Previous EW version for comparison"
  ),
  comparison_core_hrp = list(
    perf = as.list(res_C$perf), turnover = res_C$turnover,
    note = "Core only (no defense) with HRP"
  ),
  benchmark = as.list(perf_bm),
  n_hold = N_HOLD,
  weight_method = "HRP(Gerber+RMT)+ScoreTilt",
  rebal_months = REBAL_MONTHS,
  commission = COMMISSION,
  regime_allocation = if (nrow(BLEND_COMP) > 0) list(
    normal = sum(BLEND_COMP$regime == "NORMAL"),
    caution = sum(BLEND_COMP$regime == "CAUTION"),
    crisis = sum(BLEND_COMP$regime == "CRISIS"),
    avg_core_dominant = mean(BLEND_COMP$n_core_dominant, na.rm = TRUE)
  ) else NULL,
  pit_notes = list(
    C1 = "expanding IC only (no full-sample)",
    C2 = "consensus roll=7 (t-1 lag), Factor DB Date < sig_date",
    C5 = "MRS t-1 lagged (shift in reg_monthly)",
    C9 = "HRP uses t-1 returns (Date < sd)",
    C13 = "Z_Score_Aligned from Factor DB (no manual flip)",
    C15 = "Factor DB via load_month_factors()"
  ),
  run_time = as.numeric(difftime(Sys.time(), t0, units = "secs"))
), file.path(OUT_DIR, "performance.json"), pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\n[DONE] STR_1679 full stack complete in %.1f sec\n", difftime(Sys.time(), t0, units = "secs")))
