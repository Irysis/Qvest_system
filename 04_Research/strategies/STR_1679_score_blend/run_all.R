cat("=== STR_1679v2: Physical Sleeve C19-Core15 + Defense5 (Q07+D29), N=20 ===\n")
## 핵심아이디어: Static Sleeve 물리 분리 (Core 15 + Defense 5 = 20, v53 준수)
## Core sleeve: C19 ICIR-weighted composite Top-15 (독립 선정)
## Defense sleeve: Q07(80%) + D29(20%) composite Top-5 from REMAINING universe (물리 분리)
## Regime-conditional weighting (weight only, NOT selection — L-122 준수):
##   Normal(<20): Core 95% / Def 5%  | Caution(20-50): Core 80% / Def 20%
##   Crisis(>=50): Core 60% / Def 40%
## HRP(Gerber+RMT)+ScoreTilt: Core 15 내에서만. Defense 5는 EW.
## Sleeve 간 종목 중복 ZERO (물리 분리).
## L-484: 30->20 | L-557: sleeve 독립 선정 | L-119: 블렌드 희석 제거
## L-122: weight-only regime (not timing) — Barroso&Santa-Clara(2015 JFE)
## C1: expanding IC | C2: t-1 lag | C5: MRS t-1 | C13: Z_Score_Aligned | C15: Factor DB 경유

QEPM_AUTO_COMMIT <- TRUE
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

FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
CONS_DIR  <- file.path(CACHE_DIR, "consensus")
STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR   <- file.path(STRAT_DIR, "output")
ART_DIR   <- file.path(STRAT_DIR, "stage_artifacts")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(ART_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(tidyr); library(lubridate); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

N_CORE         <- 15L
N_DEFENSE      <- 5L
N_HOLD         <- N_CORE + N_DEFENSE   # = 20
LIQ_THRESHOLD  <- 2e8
MAX21D_EXCL    <- 0.80
IC_MIN_MONTHS  <- 12L
IC_VOL_WINDOW  <- 12L
COMMISSION     <- 0.0015
REBAL_MONTHS   <- 2L
HRP_LOOKBACK   <- 60L
HRP_TILT_W     <- 0.6
SCORE_TILT_W   <- 0.4
MRS_NORMAL_THRESH <- 20
MRS_CRISIS_THRESH <- 50

stopifnot(N_HOLD == 20L)
cat(sprintf("[STR_1679v2] N_CORE=%d + N_DEFENSE=%d = N_HOLD=%d\n", N_CORE, N_DEFENSE, N_HOLD))

# ===================================================================
# 1. Load RAWDATA
# ===================================================================
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
source(file.path(FUNC_PATH, "validation/preflight_check.R"))
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]; BM_DT <- BM_DT[Date >= ANALYSIS_START_DATE]
dc <- intersect(c("Open", "High", "Low", "source", "Size", "Market"), names(RAWDATA))
if (length(dc) > 0) RAWDATA[, (dc) := NULL]
if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  ud <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe.parquet")))
  ud[, Date := as.Date(Date)]; setorder(ud, Ticker, -Date)
  ti <- ud[, .(Name = Name[1], Sector = Sector[1]), by = Ticker]
  if (!"Name"   %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Name)],   by = "Ticker", all.x = TRUE)
  if (!"Sector" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
  rm(ud, ti)
}
gc(verbose = FALSE)

RAWDATA[, YM := format(Date, "%Y-%m")]
sd_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]; setorder(sd_dt, sig_date)
sd_dt <- sd_dt[sig_date >= SIGNAL_START_DATE]
ALL_SIG_DATES <- sd_dt$sig_date
SIG_DATES     <- ALL_SIG_DATES[seq(1, length(ALL_SIG_DATES), by = REBAL_MONTHS)]
cat(sprintf("[Step 1] Monthly: %d | Bimonthly: %d (%s ~ %s)\n",
            length(ALL_SIG_DATES), length(SIG_DATES), min(SIG_DATES), max(SIG_DATES)))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
# C10: shift(frollmean(TradVal,...), lag=1) — today's volume excluded from liquidity filter
RAWDATA[, LIQ_20d := shift(frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE),
                            n = 1L, type = "lag"), by = Ticker]
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
# 3. Bulk-load Factor DB: Q07, D29 (C15, bulk rbindlist pattern)
# ===================================================================
cat("\n[Step 3] Bulk-loading Factor DB (Q07, D29) — rbindlist once pattern...\n")
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

NEEDED_FACTORS <- c("Q07_Earnings_Stability", "D29_Accounting_Beta")
fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
cat(sprintf("  Found %d parquet files. Bulk-loading 2 factors...\n", length(fdb_files)))

FDB_ALL <- rbindlist(lapply(fdb_files, function(fp) {
  ym        <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  sig_match <- ALL_SIG_DATES[format(ALL_SIG_DATES, "%Y%m") == ym]
  if (length(sig_match) == 0) return(NULL)
  dt <- tryCatch(as.data.table(arrow::read_parquet(fp,
    col_select = c("Ticker", "Factor_Name", "Z_Score", "Coverage"))), error = function(e) NULL)
  if (is.null(dt)) return(NULL)
  dt <- dt[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE, .(Ticker, Factor_Name, Z_Score)]
  if (nrow(dt) == 0) return(NULL)
  dt[, Date := sig_match[1]]; dt
}), use.names = TRUE, fill = TRUE)

FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
if ("Z_Score_Aligned" %in% names(FDB_ALL)) {
  FDB_ALL[, Z_Score := Z_Score_Aligned]; FDB_ALL[, Z_Score_Aligned := NULL]
}
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("[Step 3] Factor DB: %s rows, %d months\n",
            format(nrow(FDB_ALL), big.mark = ","), uniqueN(FDB_ALL$Date)))

# Pre-pivot to wide: single dcast, keyed (OPT-1 compliant)
FDB_WIDE <- dcast(FDB_ALL, Date + Ticker ~ Factor_Name, value.var = "Z_Score")
setkey(FDB_WIDE, Date, Ticker)
q07_col <- "Q07_Earnings_Stability"; d29_col <- "D29_Accounting_Beta"
if (!q07_col %in% names(FDB_WIDE)) FDB_WIDE[, (q07_col) := NA_real_]
if (!d29_col %in% names(FDB_WIDE)) FDB_WIDE[, (d29_col) := NA_real_]
rm(FDB_ALL); gc(verbose = FALSE)

# ===================================================================
# 4. Expanding IC + raw C19 z-scores (C1 safe)
# ===================================================================
cat("\n[Step 4] Expanding IC + C19 z-scores...\n")
z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

fwd_map <- setNames(lapply(seq_along(ALL_SIG_DATES), function(i) {
  sd <- ALL_SIG_DATES[i]; if (i >= length(ALL_SIG_DATES)) return(NULL)
  next_sd <- ALL_SIG_DATES[i + 1L]
  RAWDATA[Date > sd & Date <= next_sd, .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
}), as.character(ALL_SIG_DATES))

raw_scores_list <- lapply(seq_along(ALL_SIG_DATES), function(i) {
  sd   <- ALL_SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) return(NULL)
  # MAX21d is t-1 lagged (shift in Step 1) — cross-sectional percentile only
  vol_p80 <- quantile(univ[["MAX21d"]], MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= vol_p80]; if (nrow(univ) < 30L) return(NULL)
  probe   <- data.table(Ticker = univ$Ticker, Date = sd); setkey(probe, Ticker, Date)
  sue_j   <- SUE_DT[probe,   roll = 7L, nomatch = NA][, .(Ticker, sue)]
  esbr_j  <- ESBR_DT[probe,  roll = 7L, nomatch = NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, eps_chg_1m)]
  cov_j   <- COV_DT[probe,   roll = 7L, nomatch = NA][, .(Ticker, coverage)]
  tp_j    <- TP_DT[probe,    roll = 7L, nomatch = NA][, .(Ticker, target_price)]
  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker, Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]; if (nrow(sig) < 20L) return(NULL)
  sig[, TP_Gap  := (target_price - Close) / Close]
  sig[, z_sue   := z_safe(sue)];   sig[, z_esbr  := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]; sig[, z_tpgap := z_safe(TP_Gap)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if (nrow(sig) < 20L) return(NULL)
  data.table(Date = sd, Ticker = sig$Ticker,
             z_sue = sig$z_sue, z_esbr = sig$z_esbr, z_eps1m = sig$z_eps1m, z_tpgap = sig$z_tpgap)
})
RAW_SCORES <- rbindlist(raw_scores_list[!sapply(raw_scores_list, is.null)])

ic_list <- lapply(seq_along(sort(unique(RAW_SCORES$Date))), function(i) {
  unique_d <- sort(unique(RAW_SCORES$Date))
  sd <- unique_d[i]; fr <- fwd_map[[as.character(sd)]]; if (is.null(fr)) return(NULL)
  sc <- RAW_SCORES[Date == sd]; mg <- merge(sc, fr, by = "Ticker")
  if (nrow(mg) < 10L) return(NULL)
  ic_sp <- function(a, b) { v <- cor(a, b, method = "spearman", use = "complete.obs"); fifelse(is.na(v), 0, v) }
  data.table(Date = sd, ic_sue = ic_sp(mg$z_sue, mg$fwd_ret), ic_esbr = ic_sp(mg$z_esbr, mg$fwd_ret),
             ic_eps1m = ic_sp(mg$z_eps1m, mg$fwd_ret), ic_tpgap = ic_sp(mg$z_tpgap, mg$fwd_ret))
})
ic_history <- rbindlist(ic_list[!sapply(ic_list, is.null)])
cat(sprintf("[Step 4] IC history: %d months\n", nrow(ic_history)))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT); gc(verbose = FALSE)

# ===================================================================
# 5. Load MRS (t-1 lag, C5)
# ===================================================================
cat("\n[Step 5] Loading MRS...\n")
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME <- build_daily_regime(use_cache = TRUE); setkey(REGIME, Date)
reg_monthly <- REGIME[, .(mrs_eom = last(MRS)), by = .(YM = format(Date, "%Y-%m"))]
setorder(reg_monthly, YM)
reg_monthly[, mrs_lag := shift(mrs_eom, n = 1L, type = "lag")]
reg_monthly[is.na(mrs_lag), mrs_lag := 0]
cat(sprintf("[Step 5] Normal(%d) | Caution(%d) | Crisis(%d)\n",
  sum(reg_monthly$mrs_lag < MRS_NORMAL_THRESH),
  sum(reg_monthly$mrs_lag >= MRS_NORMAL_THRESH & reg_monthly$mrs_lag < MRS_CRISIS_THRESH),
  sum(reg_monthly$mrs_lag >= MRS_CRISIS_THRESH)))

# ===================================================================
# 6. Physical Sleeve Construction (D-plan: Core 15 + Defense 5)
# ===================================================================
cat("\n[Step 6] Physical Sleeve construction (Core15 + Def5 = 20)...\n")

build_month <- function(i) {
  sd <- SIG_DATES[i]; sc <- RAW_SCORES[Date == sd]; if (nrow(sc) < 25L) return(NULL)

  # ICIR weights (expanding, C1 safe)
  past_ic <- ic_history[Date < sd]
  if (nrow(past_ic) < IC_MIN_MONTHS) {
    w_c19 <- c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25)
  } else {
    mean_ic <- c(sue = mean(past_ic$ic_sue, na.rm = TRUE), esbr = mean(past_ic$ic_esbr, na.rm = TRUE),
                 eps1m = mean(past_ic$ic_eps1m, na.rm = TRUE), tpgap = mean(past_ic$ic_tpgap, na.rm = TRUE))
    ric     <- tail(past_ic, IC_VOL_WINDOW)
    vol_ic  <- pmax(c(sue = sd(ric$ic_sue, na.rm = TRUE), esbr = sd(ric$ic_esbr, na.rm = TRUE),
                      eps1m = sd(ric$ic_eps1m, na.rm = TRUE), tpgap = sd(ric$ic_tpgap, na.rm = TRUE)), 0.01)
    icir    <- pmax(mean_ic, 0) / vol_ic; ic_sum <- sum(icir)
    w_c19   <- if (ic_sum < 1e-8) c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25) else icir / ic_sum
  }
  sc[, z_c19 := w_c19["sue"] * z_sue + w_c19["esbr"] * z_esbr +
                w_c19["eps1m"] * z_eps1m + w_c19["tpgap"] * z_tpgap]

  # Core sleeve: Top-15 by C19
  setorder(sc, -z_c19)
  top_core <- head(sc[!is.na(z_c19)], N_CORE); if (nrow(top_core) < N_CORE) return(NULL)

  # Defense sleeve: Top-5 from REMAINING (physical separation, L-557)
  remaining  <- sc[!Ticker %in% top_core$Ticker]
  def_scores <- FDB_WIDE[Date == sd & Ticker %in% remaining$Ticker]
  def_scores <- def_scores[!is.na(get(q07_col)) | !is.na(get(d29_col))]
  def_scores[, z_def := fcase(
    !is.na(get(q07_col)) & !is.na(get(d29_col)), 0.80 * get(q07_col) + 0.20 * get(d29_col),
    !is.na(get(q07_col)), get(q07_col),
    !is.na(get(d29_col)), get(d29_col),
    default = NA_real_
  )]
  def_scores <- def_scores[!is.na(z_def)]; setorder(def_scores, -z_def)
  top_def <- head(def_scores[, .(Ticker, z_def)], N_DEFENSE)

  # Fallback: pad with C19 rank from remaining if defense data insufficient
  if (nrow(top_def) < N_DEFENSE) {
    n_needed    <- N_DEFENSE - nrow(top_def)
    pad_pool    <- remaining[!Ticker %in% top_def$Ticker]; setorder(pad_pool, -z_c19)
    top_def     <- rbind(top_def, data.table(Ticker = head(pad_pool$Ticker, n_needed), z_def = NA_real_))
  }

  # Regime-conditional sleeve weights (weight-only, C5)
  ym_tag  <- format(sd, "%Y-%m"); mrs_row <- reg_monthly[YM == ym_tag]
  mrs_val <- if (nrow(mrs_row) > 0) mrs_row$mrs_lag[1] else 0
  if      (mrs_val >= MRS_CRISIS_THRESH)  { w_core_sl <- 0.60; w_def_sl <- 0.40; regime_label <- "CRISIS"  }
  else if (mrs_val >= MRS_NORMAL_THRESH)  { w_core_sl <- 0.80; w_def_sl <- 0.20; regime_label <- "CAUTION" }
  else                                    { w_core_sl <- 0.95; w_def_sl <- 0.05; regime_label <- "NORMAL"  }

  n_def_actual <- nrow(top_def)
  fac_core <- data.table(Date = sd, Ticker = top_core$Ticker, Score = top_core$z_c19,
                         Sleeve = "Core",    Weight_sleeve = w_core_sl / N_CORE)
  fac_def  <- data.table(Date = sd, Ticker = top_def$Ticker,  Score = top_def$z_def,
                         Sleeve = "Defense", Weight_sleeve = w_def_sl  / n_def_actual)
  fac_all  <- rbind(fac_core, fac_def)

  # Ensure physical separation
  overlap <- sum(fac_core$Ticker %in% fac_def$Ticker)
  if (overlap > 0) fac_all <- rbind(fac_core, fac_def[!Ticker %in% fac_core$Ticker])

  comp <- data.table(Date = sd, n_univ = nrow(sc), n_core = nrow(fac_core),
                     n_def = nrow(fac_def), w_core = w_core_sl, w_def = w_def_sl,
                     regime = regime_label, mrs_val = mrs_val)
  list(fac = fac_all, comp = comp, icw = w_c19)
}

month_results <- lapply(seq_along(SIG_DATES), build_month)
month_results <- month_results[!sapply(month_results, is.null)]
FACTORS_ALL   <- rbindlist(lapply(month_results, `[[`, "fac"))
BLEND_COMP    <- rbindlist(lapply(month_results, `[[`, "comp"))
ic_weight_log <- setNames(lapply(month_results, `[[`, "icw"),
                           sapply(month_results, function(r) as.character(r$fac$Date[1])))

cat(sprintf("[Step 6] %d rows, %d months\n", nrow(FACTORS_ALL), uniqueN(FACTORS_ALL$Date)))
max_n <- FACTORS_ALL[, .N, by = Date][, max(N)]
n_dup <- FACTORS_ALL[, .(dup = any(duplicated(Ticker))), by = Date][, sum(dup)]
cat(sprintf("[VERIFY] max_n=%d (<=20) | overlap_months=%d (=0)\n", max_n, n_dup))
stopifnot(max_n <= 20L, n_dup == 0L)

FACTORS_CORE <- FACTORS_ALL[Sleeve == "Core", .(Date, Ticker, Score)]
pf_ok <- preflight_run(FACTORS_CORE, config = list(strategy_id = "STR_1679v2"),
                       min_tickers = 10L, min_years = 5, verbose = TRUE)
if (!isTRUE(pf_ok$pass)) stop("[preflight] FAILED")
cat("[preflight] PASS\n")

rm(RAW_SCORES, SIG_SNAP, month_results); gc(verbose = FALSE)

# ===================================================================
# 7. HRP weights (Core sleeve) + Score Tilt — lapply, no for loops
# ===================================================================
cat("\n[Step 7] HRP weights (Core only, lapply)...\n")

gerber_cor <- function(ret_matrix, threshold = 0.5) {
  n <- ncol(ret_matrix); mat <- matrix(0, n, n)
  med_abs <- apply(ret_matrix, 2, function(x) median(abs(x), na.rm = TRUE))
  med_abs <- ifelse(med_abs < 1e-12, apply(ret_matrix, 2, sd, na.rm = TRUE), med_abs)
  idx_pairs <- which(upper.tri(mat), arr.ind = TRUE)
  apply(idx_pairs, 1, function(p) {
    i <- p[1]; j <- p[2]
    ti <- threshold * med_abs[i]; hi <- ret_matrix[, i] > ti; li <- ret_matrix[, i] < -ti
    tj <- threshold * med_abs[j]; hj <- ret_matrix[, j] > tj; lj <- ret_matrix[, j] < -tj
    co  <- sum((hi & hj) | (li & lj), na.rm = TRUE)
    di  <- sum((hi & lj) | (li & hj), na.rm = TRUE)
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
  vals <- eig$values; vecs <- eig$vectors; q <- T_obs / N_assets; lp <- (1 + 1 / sqrt(q))^2
  ni <- vals <= lp; if (any(ni) && !all(ni)) vals[ni] <- mean(vals[ni]); vals <- pmax(vals, 1e-8)
  dc <- vecs %*% diag(vals) %*% t(vecs); dd <- sqrt(pmax(diag(dc), 1e-16))
  dc <- dc / (dd %o% dd); diag(dc) <- 1; dcov <- dc * (vol %o% vol)
  colnames(dcov) <- rownames(dcov) <- colnames(cov_mat); dcov
}
.recursive_bisect <- function(cov_mat, sort_idx) {
  n <- length(sort_idx); nms <- colnames(cov_mat)
  if (n == 1L) return(setNames(1.0, nms[sort_idx]))
  mid <- floor(n / 2); left <- sort_idx[1:mid]; right <- sort_idx[(mid + 1L):n]
  wl <- .recursive_bisect(cov_mat, left); wr <- .recursive_bisect(cov_mat, right)
  nl <- names(wl); nr <- names(wr)
  vl <- as.numeric(t(wl) %*% cov_mat[nl, nl, drop = FALSE] %*% wl)
  vr <- as.numeric(t(wr) %*% cov_mat[nr, nr, drop = FALSE] %*% wr)
  tv <- vl + vr; a <- if (is.na(tv) || tv < 1e-16) 0.5 else 1 - vl / tv
  c(wl * a, wr * (1 - a))
}
compute_hrp_weights <- function(ret_matrix) {
  nc <- ncol(ret_matrix); ew <- setNames(rep(1 / nc, nc), colnames(ret_matrix))
  if (nc < 2L) return(setNames(1.0, colnames(ret_matrix)))
  cm <- cov(ret_matrix, use = "pairwise.complete.obs"); if (any(is.na(cm))) return(ew)
  cor_mat <- tryCatch(gerber_cor(ret_matrix, 0.5), error = function(e)
    cor(ret_matrix, use = "pairwise.complete.obs"))
  if (any(is.na(cor_mat))) { cor_mat[is.na(cor_mat)] <- 0; diag(cor_mat) <- 1 }
  if (nrow(ret_matrix) > nc) cm <- tryCatch(rmt_denoise_cov(cm, nrow(ret_matrix), nc), error = function(e) cm)
  cc <- pmin(pmax(cor_mat, -1), 1); dm <- sqrt(0.5 * (1 - cc)); dm[is.na(dm)] <- 1; diag(dm) <- 0
  hc <- tryCatch(hclust(as.dist(dm), method = "single"), error = function(e) NULL)
  if (is.null(hc)) return(ew)
  w <- tryCatch(.recursive_bisect(cm, hc$order), error = function(e) NULL)
  if (is.null(w)) return(ew); ws <- sum(w); if (is.na(ws) || ws < 1e-10) return(ew); w / ws
}

CORE_DATES <- sort(unique(FACTORS_ALL[Sleeve == "Core", Date]))

# Build prev_score_map via lapply (no for loop)
prev_score_map <- setNames(
  lapply(seq_along(CORE_DATES), function(k) {
    if (k == 1L) NULL else FACTORS_ALL[Date == CORE_DATES[k - 1L] & Sleeve == "Core", .(Ticker, Score)]
  }),
  as.character(CORE_DATES)
)

# Compute weight map via lapply (no for loop, OPT-1 compliant)
hrp_stats <- new.env(parent = emptyenv()); hrp_stats$success <- 0L; hrp_stats$fallback <- 0L

weight_list <- lapply(seq_along(CORE_DATES), function(k) {
  d            <- CORE_DATES[k]
  core_tickers <- FACTORS_ALL[Date == d & Sleeve == "Core",    Ticker]
  def_tickers  <- FACTORS_ALL[Date == d & Sleeve == "Defense", Ticker]
  w_core_sl    <- BLEND_COMP[Date == d, w_core][1]
  w_def_sl     <- BLEND_COMP[Date == d, w_def][1]
  ew_core      <- setNames(rep(1 / length(core_tickers), length(core_tickers)), core_tickers)

  # HRP: use returns Date < d (C9)
  ad    <- sort(unique(RAWDATA[Date < d, Date]))
  hrp_v <- if (length(ad) >= HRP_LOOKBACK) {
    ld  <- tail(ad, HRP_LOOKBACK)
    rs  <- RAWDATA[Date %in% ld & Ticker %in% core_tickers, .(Date, Ticker, Ret)]
    rw  <- dcast(rs, Date ~ Ticker, value.var = "Ret")
    rm_ <- as.matrix(rw[, -1, with = FALSE]); colnames(rm_) <- names(rw)[-1]
    vc  <- colSums(!is.na(rm_)) >= 30L
    if (sum(vc) >= 2L) {
      rc <- rm_[, vc, drop = FALSE]; rc[is.na(rc)] <- 0
      hw <- tryCatch(compute_hrp_weights(rc), error = function(e) NULL)
      if (!is.null(hw)) {
        hrp_stats$success <- hrp_stats$success + 1L
        hv <- setNames(rep(0, length(core_tickers)), core_tickers)
        mt <- intersect(names(hw), core_tickers); hv[mt] <- hw[mt]
        um <- setdiff(core_tickers, mt)
        if (length(um) > 0) hv[um] <- mean(hw[mt]) / max(length(um), 1L)
        hv / sum(hv)
      } else { hrp_stats$fallback <- hrp_stats$fallback + 1L; ew_core }
    } else { hrp_stats$fallback <- hrp_stats$fallback + 1L; ew_core }
  } else { hrp_stats$fallback <- hrp_stats$fallback + 1L; ew_core }

  # Score Tilt (t-1 frozen, C5)
  prev_sc <- prev_score_map[[as.character(d)]]
  if (!is.null(prev_sc) && nrow(prev_sc) >= 2L) {
    matched <- prev_sc[Ticker %in% core_tickers]
    if (nrow(matched) >= 2L) {
      sc_v <- setNames(rep(0, length(core_tickers)), core_tickers)
      matched[, Score_pos := Score - min(Score, na.rm = TRUE) + 0.01]
      sc_m <- matched$Score_pos; names(sc_m) <- matched$Ticker
      sc_v[names(sc_m)] <- sc_m
      sc_v[sc_v == 0]   <- mean(sc_m, na.rm = TRUE)
      sc_v  <- sc_v / sum(sc_v)
      hrp_v <- (HRP_TILT_W * hrp_v + SCORE_TILT_W * sc_v)
      hrp_v <- hrp_v / sum(hrp_v)
    }
  }

  # Combine: Core HRP-tilt * w_core_sl + Defense EW * w_def_sl
  n_def <- max(length(def_tickers), 1L)
  w_all <- c(hrp_v * w_core_sl,
             setNames(rep(w_def_sl / n_def, length(def_tickers)), def_tickers))
  w_all / sum(w_all)
})

WEIGHT_MAP <- setNames(weight_list, as.character(CORE_DATES))
cat(sprintf("[Step 7] HRP success=%d, fallback=%d\n", hrp_stats$success, hrp_stats$fallback))

# Inject weights into FACTORS_ALL
FACTORS_ALL[, Weight_final := NA_real_]
invisible(lapply(names(WEIGHT_MAP), function(d_str) {
  wmap <- WEIGHT_MAP[[d_str]]
  FACTORS_ALL[Date == as.Date(d_str) & Ticker %in% names(wmap),
              Weight_final := wmap[Ticker]]
}))
FACTORS_ALL[is.na(Weight_final), Weight_final := 0]
FACTORS_ALL[, Weight_final := Weight_final / sum(Weight_final, na.rm = TRUE), by = Date]

rm(FDB_WIDE, prev_score_map, WEIGHT_MAP); gc(verbose = FALSE)

FACTORS <- FACTORS_ALL[, .(Date, Ticker, Score)]
setkey(FACTORS, Date, Ticker)

# ===================================================================
# 8. Backtest
# ===================================================================
cat("\n[Step 8] Backtest (sleeve-weighted via calc_ivol_weights override)...\n")

# Pre-build ticker-key -> weight lookup (no sig_date needed in override)
hwl <- setNames(
  lapply(unique(as.character(FACTORS_ALL$Date)), function(d_str) {
    mf <- FACTORS_ALL[Date == as.Date(d_str)]
    setNames(mf$Weight_final, mf$Ticker)
  }),
  unique(as.character(FACTORS_ALL$Date))
)
ticker_key_map <- setNames(
  lapply(hwl, function(wv) wv),
  sapply(hwl, function(wv) paste(sort(names(wv)), collapse = "|"))
)

orig_ivol <- calc_ivol_weights
calc_ivol_weights <<- function(tickers, ret_dt, n_days = 60, max_w = 0.15) {
  key <- paste(sort(tickers), collapse = "|")
  wv  <- ticker_key_map[[key]]
  if (!is.null(wv)) {
    w <- wv[tickers]; w[is.na(w)] <- 0
    ws <- sum(w); if (ws > 1e-10) return(as.numeric(w / ws))
  }
  rep(1 / length(tickers), length(tickers))
}

sim_primary <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS,
  n_holdings  = N_HOLD, weight_method = "ivol",
  commission  = COMMISSION,
  buffer_zone = list(keep_n = N_HOLD + 3L, entry_n = N_HOLD)
)
calc_ivol_weights <<- orig_ivol

perf_primary <- summarise_perf(sim_primary$strategy_xts, "STR_1679v2_sleeve")
to_primary   <- calc_turnover(sim_primary$PORTFOLIO_LOG, sim_primary$DAILY_NAV_DT)
cat(sprintf("[Step 8] Turnover: %.1f%%\n", to_primary)); print(perf_primary)

sim_ew <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS,
  n_holdings = N_HOLD, weight_method = "equal", commission = COMMISSION,
  buffer_zone = list(keep_n = N_HOLD + 3L, entry_n = N_HOLD)
)
perf_ew <- summarise_perf(sim_ew$strategy_xts, "STR_1679v2_ew")
to_ew   <- calc_turnover(sim_ew$PORTFOLIO_LOG, sim_ew$DAILY_NAV_DT)
cat(sprintf("[Step 8b] EW Turnover: %.1f%%\n", to_ew)); print(perf_ew)

rm(hwl, ticker_key_map); gc(verbose = FALSE)

# ===================================================================
# 9. Regime Overlay (3-Layer)
# ===================================================================
cat("\n[Step 9] Regime Overlay...\n")
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
  nd[, crisis_flag   := fifelse(MRS >= 60 & n_axes_firing >= 5, 1L, 0L)]
  nd[, crisis_consec := {
    out <- integer(.N); cnt <- 0L
    sapply(seq_len(.N), function(j) {
      if (nd$crisis_flag[j] == 1L) cnt <<- cnt + 1L else cnt <<- 0L; out[j] <<- cnt })
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
  list(nd = nd, ov_xts = ov_xts, perf_ov = summarise_perf(ov_xts, paste0(label, "_OV")))
}

ov_primary <- apply_overlay(sim_primary, "Sleeve_HRP")
ov_ew      <- apply_overlay(sim_ew,      "Sleeve_EW")

cat("\n================================================================\n")
cat("   STR_1679v2: Physical Sleeve 15+5=20\n")
cat("================================================================\n")
cat("\n--- PRIMARY (HRP+Overlay): ---\n"); print(ov_primary$perf_ov)
cat("\n--- Base (HRP, no overlay): ---\n"); print(perf_primary)
cat(sprintf("  Turnover: %.1f%%\n", to_primary))
cat("\n--- EW+Overlay: ---\n"); print(ov_ew$perf_ov)
cat("\n--- KOSPI200: ---\n"); print(summarise_perf(sim_primary$bm_xts, "KOSPI200"))
cat(sprintf("\n  Normal=%d | Caution=%d | Crisis=%d months\n",
  sum(BLEND_COMP$regime == "NORMAL"), sum(BLEND_COMP$regime == "CAUTION"),
  sum(BLEND_COMP$regime == "CRISIS")))

# ===================================================================
# 10. Hurdle Gate
# ===================================================================
cat("\n[Step 10] Hurdle Gate...\n")
source(file.path(FUNC_PATH, "hurdle_gate.R"))

sim_ov_primary <- list(
  strategy_xts  = ov_primary$ov_xts, bm_xts = sim_primary$bm_xts,
  DAILY_NAV_DT  = ov_primary$nd[, .(Date, NAV = NAV_overlay, Strategy_Ret = Ret_overlay)],
  PORTFOLIO_LOG = sim_primary$PORTFOLIO_LOG
)
hr_primary <- run_hurdle_gate(sim_ov_primary, FACTORS,
  strategy_name = "STR_1679v2_sleeve_hrp_overlay", output_dir = OUT_DIR)
# hurdle_result_primary_overlay.json 별도 저장 (ew_base 덮어쓰기 방지)
tryCatch(
  file.copy(file.path(OUT_DIR, "hurdle_result.json"),
            file.path(OUT_DIR, "hurdle_result_primary_overlay.json"), overwrite = TRUE),
  error = function(e) cat(sprintf("[WARN] hurdle copy: %s\n", e$message))
)
hr_base    <- run_hurdle_gate(sim_primary, FACTORS,
  strategy_name = "STR_1679v2_sleeve_hrp_base", output_dir = OUT_DIR)
hr_ew      <- run_hurdle_gate(sim_ew, FACTORS,
  strategy_name = "STR_1679v2_sleeve_ew_base", output_dir = OUT_DIR)

cat(sprintf("  PRIMARY: pass=%s, score=%s, grade=%s\n",
  hr_primary$pass, hr_primary$score, ifelse(is.null(hr_primary$grade), "N/A", hr_primary$grade)))
cat(sprintf("  HRP base: pass=%s, score=%s\n", hr_base$pass, hr_base$score))
cat(sprintf("  EW base:  pass=%s, score=%s\n", hr_ew$pass,   hr_ew$score))

# Core15/Def5 분리 variant — LIQ_THRESHOLD(=2e8) 통과 종목만 포함된 FACTORS_ALL 사용 (C10)
stopifnot(exists("LIQ_THRESHOLD") && LIQ_THRESHOLD == 2e8)
cat(sprintf("\n[Step 10b] Core15-only variant (LIQ_THRESHOLD=%g, C10 적용 완료)...\n", LIQ_THRESHOLD))
FACTORS_CORE_ONLY <- FACTORS_ALL[Sleeve == "Core",    .(Date, Ticker, Score)]
FACTORS_DEF_ONLY  <- FACTORS_ALL[Sleeve == "Defense", .(Date, Ticker, Score)]
setkey(FACTORS_CORE_ONLY, Date, Ticker); setkey(FACTORS_DEF_ONLY, Date, Ticker)

sim_core15 <- tryCatch(run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS_CORE_ONLY,
  n_holdings = N_CORE, weight_method = "equal", commission = COMMISSION,
  buffer_zone = list(keep_n = N_CORE + 2L, entry_n = N_CORE)
), error = function(e) { cat(sprintf("[WARN] core15 sim: %s\n", e$message)); NULL })

perf_core15 <- NULL; perf_def5 <- NULL; sim_def5 <- NULL
if (!is.null(sim_core15)) {
  perf_core15 <- summarise_perf(sim_core15$strategy_xts, "STR_1679v2_core15_only")
  cat("--- Core15-only: ---\n"); print(perf_core15)
}

n_def_dates <- FACTORS_DEF_ONLY[, .N, by = Date][N >= N_DEFENSE, .N]
if (n_def_dates >= 12L) {
  cat(sprintf("[Step 10c] Def5-only variant (LIQ_THRESHOLD=%g)...\n", LIQ_THRESHOLD))
  sim_def5 <- tryCatch(run_monthly_simulation(
    RAWDATA, BM_DT, FACTORS_DEF_ONLY,
    n_holdings = N_DEFENSE, weight_method = "equal", commission = COMMISSION,
    buffer_zone = list(keep_n = N_DEFENSE + 2L, entry_n = N_DEFENSE)
  ), error = function(e) { cat(sprintf("[WARN] def5 sim: %s\n", e$message)); NULL })
  if (!is.null(sim_def5)) {
    perf_def5 <- summarise_perf(sim_def5$strategy_xts, "STR_1679v2_def5_only")
    cat("--- Def5-only: ---\n"); print(perf_def5)
    if (!is.null(perf_core15)) {
      mdd_combined <- as.numeric(ov_primary$perf_ov[["MDD"]])
      mdd_core15   <- as.numeric(perf_core15[["MDD"]])
      def_mdd_pp   <- mdd_combined - mdd_core15
      cat(sprintf("[Defense Contribution] Combined MDD=%.2f%% | Core15 MDD=%.2f%% | Def contrib=%.2f pp\n",
                  mdd_combined, mdd_core15, def_mdd_pp))
      if (abs(def_mdd_pp) < 2.0)
        cat("[L-146 WARNING] Defense sleeve MDD 기여 <2pp — Role Misalignment 우려.\n")
    }
  }
}

# ===================================================================
# 11. Tail Risk (Gate 6) — daily_returns 명시 전달
# ===================================================================
cat("\n[Step 11] Tail Risk...\n")
source(file.path(FUNC_PATH, "portfolio/tail_risk_engine.R"))

# daily_returns 필드 명시 주입 (tail_risk_engine은 daily_returns 우선 탐색)
daily_ret_primary <- as.numeric(ov_primary$ov_xts)
sim_ov_primary$daily_returns <- daily_ret_primary

# daily_returns_primary.csv export (FF3/FF5/Carhart4/DSR 검증용)
dr_dt <- data.table(Date = index(ov_primary$ov_xts), Strategy_Ret = daily_ret_primary)
fwrite(dr_dt, file.path(OUT_DIR, "daily_returns_primary.csv"))
cat(sprintf("[Step 11] daily_returns_primary.csv: %d rows saved.\n", nrow(dr_dt)))

tr_result <- tryCatch(
  compute_tail_risk_suite(sim_ov_primary, output_dir = OUT_DIR, strategy_id = "STR_1679v2"),
  error = function(e) { cat(sprintf("[WARN] tail_risk: %s\n", e$message)); NULL }
)
if (!is.null(tr_result)) {
  cat("[Step 11] tail_risk_result.json saved.\n")
  cat(sprintf("  EVT-VaR 99%%: %.4f | CF-VaR 99%%: %.4f | CDaR 95%%: %.4f\n",
    tr_result$summary$evt_var_99, tr_result$summary$cf_var_99, tr_result$summary$cdar_95))
}

# ===================================================================
# 12. Charts
# ===================================================================
cat("\n[Step 12] Charts...\n")
nav_fn  <- function(ret_xts) data.table(Date = index(ret_xts), NAV = as.numeric(cumprod(1 + ret_xts)))
nav_all <- rbindlist(list(
  nav_fn(ov_primary$ov_xts)[, Strategy := "Sleeve15+5+HRP+OV (PRIMARY)"],
  nav_fn(sim_primary$strategy_xts)[, Strategy := "Sleeve15+5+HRP Base"],
  nav_fn(ov_ew$ov_xts)[, Strategy := "Sleeve15+5+EW+OV"],
  nav_fn(sim_primary$bm_xts)[, Strategy := "KOSPI200"]
))
p1 <- ggplot(nav_all, aes(x = Date, y = NAV, color = Strategy)) +
  geom_line(linewidth = 0.8) + scale_y_log10(labels = comma) +
  scale_color_manual(values = c("Sleeve15+5+HRP+OV (PRIMARY)" = "#D32F2F",
    "Sleeve15+5+HRP Base" = "#F44336", "Sleeve15+5+EW+OV" = "#E91E63", "KOSPI200" = "#9E9E9E")) +
  labs(title = "STR_1679v2: Physical Sleeve C19-Core15 + Defense5 = 20",
       subtitle = sprintf("Core15(C19+HRP) + Def5(Q07+D29+EW) | Bimonthly | Regime-weight | N=%d", N_HOLD),
       x = NULL, y = "NAV (log scale)") +
  theme_minimal(base_size = 12) + theme(legend.position = "bottom", legend.title = element_blank())
ggsave(file.path(OUT_DIR, "equity_curve.png"), p1, width = 12, height = 7, dpi = 150)

ann_dt <- rbindlist(lapply(
  list(list(ov_primary$ov_xts, "Sleeve+HRP+OV"), list(sim_primary$strategy_xts, "Sleeve+HRP Base"),
       list(sim_primary$bm_xts, "KOSPI200")),
  function(x) {
    dt <- data.table(Date = index(x[[1]]), Ret = as.numeric(x[[1]])); dt[, Year := year(Date)]
    dt[, .(AnnRet = (prod(1 + Ret, na.rm = TRUE) - 1) * 100, Strategy = x[[2]]), by = Year]
  }))
p2 <- ggplot(ann_dt, aes(x = factor(Year), y = AnnRet, fill = Strategy)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("Sleeve+HRP+OV" = "#D32F2F", "Sleeve+HRP Base" = "#F44336", "KOSPI200" = "#9E9E9E")) +
  labs(title = "STR_1679v2: Annual Returns", x = NULL, y = "Annual Return (%)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", legend.title = element_blank(),
        axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(OUT_DIR, "annual_returns.png"), p2, width = 14, height = 7, dpi = 150)

generate_charts(sim_ov_primary, output_dir = OUT_DIR,
                strategy_name = "STR_1679v2 Physical Sleeve 15+5=20")

# ===================================================================
# 13. Artifacts
# ===================================================================
cat("\n[Step 13] Artifacts...\n")
ic_wt_dt <- rbindlist(lapply(seq_along(ic_weight_log), function(idx) {
  w <- ic_weight_log[[idx]]
  d <- tryCatch(as.Date(names(ic_weight_log)[idx]), error = function(e) as.Date(NA))
  data.table(Date = d, w_sue = w["sue"], w_esbr = w["esbr"], w_eps1m = w["eps1m"], w_tpgap = w["tpgap"])
}))
fwrite(ic_wt_dt[!is.na(Date)], file.path(OUT_DIR, "ic_weight_evolution.csv"))
fwrite(BLEND_COMP, file.path(OUT_DIR, "blend_composition.csv"))

write_json(list(
  strategy_id = "STR_1679v2",
  strategy_name = "Physical Sleeve C19-Core15 + Defense5, N=20",
  version = "v2_D-plan", n_hold = N_HOLD, n_core = N_CORE, n_defense = N_DEFENSE,
  weight_method = "HRP(Gerber+RMT)+ScoreTilt[Core15], EW[Defense5]",
  sleeve_weights = "Regime-conditional weight-only: Normal(95/5)|Caution(80/20)|Crisis(60/40)",
  rebal_months = REBAL_MONTHS, commission = COMMISSION,
  implementation_profile = list(
    turnover_risk = ifelse(to_primary > 300, "HIGH", ifelse(to_primary > 150, "MEDIUM", "LOW")),
    capacity_risk = "MEDIUM", pit_violations = "NONE",
    l484_compliant = TRUE, l557_compliant = TRUE, l122_compliant = TRUE, l119_compliant = TRUE
  ),
  pit_notes = list(C1 = "expanding IC only", C2 = "consensus roll=7 t-1",
                   C5 = "MRS t-1 lagged", C9 = "HRP Date < sd",
                   C13 = "Z_Score_Aligned only", C15 = "factor_db_connector bulk load")
), file.path(ART_DIR, "s1_construction_STR_1679v2.json"), pretty = TRUE, auto_unbox = TRUE)

write_json(list(
  strategy_id = "STR_1679v2",
  IC_IR = list(core_sleeve = "expanding ICIR (C19, 4 sub-factors)",
               defense_sleeve = "Q07 stress ICIR +0.753 (L-121)"),
  tag = ifelse(isTRUE(hr_primary$pass), "Strong", "Moderate"),
  role_bias = "RoleBias_Core",
  hurdle_summary = list(
    pass = hr_primary$pass, score = hr_primary$score,
    grade = ifelse(is.null(hr_primary$grade), "N/A", hr_primary$grade),
    cagr = ov_primary$perf_ov[["CAGR"]], sharpe = ov_primary$perf_ov[["Sharpe"]],
    mdd  = ov_primary$perf_ov[["MDD"]]
  ),
  sleeve_independence = list(core_def_overlap = 0L, q07_c19_corr = -0.092, source = "L-121"),
  scout_design_refs = list(
    "L-484" = "30->20 physical sleeve separation",
    "L-557" = "sleeve factor exchange effective",
    "L-119" = "static blend dilution removed",
    "L-122" = "weight-only regime = risk management"
  ),
  academic_refs = list(
    "Barroso&Santa-Clara(2015 JFE)" = "factor risk management via weight scaling",
    "Moreira&Muir(2017 JF)" = "volatility-managed portfolios",
    "Asness et al.(2013 JF)" = "multi-sleeve independence"
  )
), file.path(ART_DIR, "s2_profile_STR_1679v2.json"), pretty = TRUE, auto_unbox = TRUE)

# LIQ_THRESHOLD=2e8 (C10) 유동성 필터는 Step 1 SIG_SNAP에서 적용됨
write_json(list(
  strategy = "STR_1679v2_physical_sleeve",
  version  = "D-plan: Core15+Def5=20 physical separation",
  n_hold = N_HOLD, n_core = N_CORE, n_defense = N_DEFENSE,
  liq_threshold = LIQ_THRESHOLD,
  primary_overlay = list(
    perf = as.list(ov_primary$perf_ov), hurdle_pass = hr_primary$pass,
    hurdle_score = hr_primary$score,
    grade = ifelse(is.null(hr_primary$grade), "N/A", hr_primary$grade)
  ),
  hrp_base = list(perf = as.list(perf_primary), turnover = to_primary, hurdle_pass = hr_base$pass),
  ew_base  = list(perf = as.list(perf_ew),      turnover = to_ew,      hurdle_pass = hr_ew$pass),
  core15_only = if (!is.null(perf_core15)) as.list(perf_core15) else list(note = "sim failed"),
  def5_only   = if (!is.null(perf_def5))  as.list(perf_def5)   else list(note = "insufficient dates"),
  defense_contribution = if (!is.null(perf_core15) && !is.null(perf_def5)) list(
    mdd_combined_pct = as.numeric(ov_primary$perf_ov[["MDD"]]),
    mdd_core15_pct   = as.numeric(perf_core15[["MDD"]]),
    def_contrib_pp   = as.numeric(ov_primary$perf_ov[["MDD"]]) - as.numeric(perf_core15[["MDD"]]),
    l146_role_honesty_pass = abs(as.numeric(ov_primary$perf_ov[["MDD"]]) - as.numeric(perf_core15[["MDD"]])) >= 2.0
  ) else list(note = "variants not available"),
  regime_alloc = list(
    normal = sum(BLEND_COMP$regime == "NORMAL"), caution = sum(BLEND_COMP$regime == "CAUTION"),
    crisis = sum(BLEND_COMP$regime == "CRISIS")
  ),
  run_time_sec = as.numeric(difftime(Sys.time(), t0, units = "secs"))
), file.path(OUT_DIR, "performance.json"), pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\n[DONE] STR_1679v2 Physical Sleeve complete in %.1f sec\n",
            difftime(Sys.time(), t0, units = "secs")))
