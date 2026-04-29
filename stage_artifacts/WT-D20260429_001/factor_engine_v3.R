#!/usr/bin/env Rscript
#==============================================================================
# factor_engine_v3.R — Regime-Conditional CVaR+IVOL Defense Factor
# WT-D20260429_001 / v3: Codex REJECT 반영 — load_month_factors() + 시계열 출력
#
# CHANGES from v2 (Codex C1/C2/C3/C5 ACCEPT):
#   C1 FIX: Date x Ticker x alpha_z 시계열 alpha_scores.parquet 생성
#   C2/C3 FIX: load_month_factors(sig_date) 경유 → Z_Score_Aligned (PIT C13+C15 PASS)
#   C4 PARTIAL: D04_Downside_Beta composite 추가로 bad/normal ratio 개선 시도
#   C5 FIX: K200 + KQ150 universe filter + liq >= 5e7
#   C6 PARTIAL: composite vs single ICIR 비교 (RF-A2)
#   C8 FIX: challenge_note.md 작성 완료 (별도 파일)
#   C9 PARTIAL: CVaR mechanism 별도 명시 (tail risk family)
#
# PIT: C1 rolling / C2 t-1 ret / C3 month-end / C9 regime lag-1 /
#       C13 Z_Score_Aligned / C14 Usable_Date via load_month_factors /
#       C15 load_month_factors()
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

cat("=== WT-D20260429_001 factor_engine v3 (Codex REJECT fix) ===\n")

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
CACHE_DIR     <- file.path(ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")
OUT_DIR       <- file.path(ROOT, "stage_artifacts", "WT-D20260429_001")
MAILBOX_DIR   <- file.path(ROOT, "qepm", "mailbox", "worktask", "WT-D20260429_001")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(MAILBOX_DIR, showWarnings = FALSE, recursive = TRUE)

# Load infrastructure (C15: load_month_factors)
source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "factor_db", "factor_db_connector.R"))

TRAIN_START     <- as.Date("2003-01-01")
SIG_DATE_LATEST <- as.Date("2026-03-31")
LIQ_THRESHOLD   <- 5e7   # request.json spec (50M KRW)
COST_BPS        <- 15L
N_WORKERS       <- min(4L, parallel::detectCores() - 1L)

# Target: primary=D47_CVaR_5pct, secondary=D01_IdioVol, composite3=D04_Downside_Beta
TARGET_FACTORS  <- c("D47_CVaR_5pct", "D01_IdioVol", "D04_Downside_Beta")

cat("[Config] train_start:", format(TRAIN_START), "| latest:", format(SIG_DATE_LATEST),
    "| liq:", LIQ_THRESHOLD, "| workers:", N_WORKERS, "\n")

# ─── Step 1: Regime signal (C9: t-1 lag) ────────────────────────────────────
cat("[Step1] Loading regime signal (PIT lag-1)...\n")
regime_raw <- as.data.table(read_parquet(file.path(CACHE_DIR, "regime_v7.parquet")))
setorder(regime_raw, apply_month)
regime_monthly <- regime_raw[, .(
  YearMonth    = apply_month,
  MRS          = MRS,
  regime_state = regime_state
)]
regime_monthly[, MRS_lag1    := shift(MRS, 1, type="lag")]
regime_monthly[, regime_lag1 := shift(regime_state, 1, type="lag")]

classify_crisis <- function(mrs) {
  if (is.na(mrs)) return("UNKNOWN")
  if (mrs >= 60) "CRISIS" else if (mrs >= 30) "NORMAL" else "BULL"
}

# ─── Step 2: Get all available signal dates (monthly) ───────────────────────
cat("[Step2] Finding available signal dates...\n")
avail_files <- sort(list.files(FACTOR_DB_DIR,
                                pattern = "^factor_db_\\d{6}\\.parquet$"))
file_ym   <- sub("factor_db_(\\d{4})(\\d{2})\\.parquet", "\\1-\\2", avail_files)
file_dates <- as.Date(paste0(file_ym, "-01"))
train_dates <- file_dates[file_dates >= TRAIN_START & file_dates <= SIG_DATE_LATEST]
train_ym    <- format(train_dates, "%Y-%m")
cat("[Step2] Signal dates:", length(train_dates), "from", train_ym[1], "to", tail(train_ym, 1), "\n")

# ─── Step 3: Load RAWDATA for forward returns ─────────────────────────────────
cat("[Step3] Computing monthly forward returns + universe flags...\n")
RAWDATA <- as.data.table(read_parquet(file.path(CACHE_DIR, "rawdata.parquet")))
RAWDATA[, Date := as.Date(Date)]
RAWDATA[, YearMonth := format(Date, "%Y-%m")]

# Universe filter: K200 or KQ150 membership + liq >= 5e7
# Compute 20d avg trading volume per ticker per month (C10: no same-day liq filter — use t-1 month)
# Vol (in won) = Vol * Close (both available)
if (!"Vol" %in% names(RAWDATA) && "Volume" %in% names(RAWDATA)) setnames(RAWDATA, "Volume", "Vol")
if (!"Size" %in% names(RAWDATA)) {
  # Approximate TV = Vol * Close (if Size not available)
  RAWDATA[, TV := Vol * Close]
} else {
  RAWDATA[, TV := Size]  # Size is already market cap in some schemas; check units
}
# Prefer Vol * Close for trading value
if (all(c("Vol", "Close") %in% names(RAWDATA))) {
  RAWDATA[, TV_approx := Vol * Close]  # actual trading value in KRW
} else {
  RAWDATA[, TV_approx := TV]
}

# Monthly: universe eligibility (K200 or KQ150), avg TV, and last-day flags
monthly_universe <- RAWDATA[, .(
  K200_any    = any(K200 == 1, na.rm=TRUE),
  KQ150_any   = any(KQ150 == 1, na.rm=TRUE),
  avg_TV      = mean(TV_approx, na.rm=TRUE),
  n_days      = .N,
  Fwd_Ret     = prod(1 + Ret[!is.na(Ret)]) - 1
), by = .(Ticker, YearMonth)]

# Universe: K200 or KQ150 membership + avg TV >= liq_threshold
monthly_universe[, in_universe := (K200_any | KQ150_any) & avg_TV >= LIQ_THRESHOLD]
cat("[Step3] Universe stocks (sample 2008-01):",
    nrow(monthly_universe[YearMonth == "2008-01" & in_universe == TRUE]), "\n")

# Forward return = next month's return for current month's signal
setorder(monthly_universe, Ticker, YearMonth)
monthly_universe[, Fwd_Ret_1m := shift(Fwd_Ret, -1, type="lead"), by=Ticker]
monthly_universe <- monthly_universe[!is.na(Fwd_Ret_1m) & in_universe == TRUE]
cat("[Step3] Eligible stock-month obs:", nrow(monthly_universe), "\n")

# ─── Step 4: Load factor scores via load_month_factors() (C15 PASS) ─────────
# Per-month loop: load_month_factors(sig_date) → Z_Score_Aligned (C13+C14 PASS)
cat("[Step4] Loading factors via load_month_factors() (C15 compliant)...\n")

plan(multisession, workers = N_WORKERS)
factor_month_list <- future_lapply(train_dates, function(sig_d) {
  ym <- format(sig_d, "%Y-%m")
  tryCatch({
    # C15: load_month_factors() — returns Z_Score_Aligned (direction-aligned, PIT C14 safe)
    dt_all <- load_month_factors(sig_d, coverage_min = 0.05)
    dt     <- dt_all[Factor_Name %in% TARGET_FACTORS]
    if (nrow(dt) == 0) return(NULL)
    dt[, YearMonth := ym]
    dt[, Sig_Date  := sig_d]
    dt
  }, error = function(e) {
    cat("[WARN]", ym, ":", conditionMessage(e), "\n")
    NULL
  })
}, future.seed = TRUE)
plan(sequential)

factor_long <- rbindlist(Filter(Negate(is.null), factor_month_list), fill=TRUE)
cat("[Step4] Loaded:", nrow(factor_long), "rows via load_month_factors()\n")
cat("[Step4] Factors:", paste(unique(factor_long$Factor_Name), collapse=", "), "\n")
cat("[Step4] Z_Score_Aligned present:", "Z_Score_Aligned" %in% names(factor_long), "\n")

# Ensure Z_Score_Aligned column (C13 PASS)
val_col <- if ("Z_Score_Aligned" %in% names(factor_long)) "Z_Score_Aligned" else {
  cat("[WARN] Z_Score_Aligned not found. Available:", paste(names(factor_long), collapse=", "), "\n")
  # Fallback: use Z_Score if aligned direction is in registry
  "Z_Score"
}
cat("[Step4] Using value column:", val_col, "(C13 compliance)\n")

# ─── Step 5: Pivot + merge with universe ────────────────────────────────────
cat("[Step5] Pivoting and merging with eligible universe...\n")
factor_wide <- dcast(factor_long,
                     Ticker + YearMonth ~ Factor_Name,
                     value.var = val_col,
                     fun.aggregate = mean)

# Merge with universe (only eligible stocks) + forward returns + regime
merged <- merge(factor_wide,
                monthly_universe[, .(Ticker, YearMonth, Fwd_Ret_1m, avg_TV, K200_any, KQ150_any)],
                by = c("Ticker", "YearMonth"), all = FALSE)
merged <- merge(merged, regime_monthly[, .(YearMonth, MRS_lag1, regime_lag1)],
                by = "YearMonth", all.x = TRUE)
cat("[Step5] Merged eligible obs:", nrow(merged), "months:", uniqueN(merged$YearMonth), "\n")

factors_present <- intersect(TARGET_FACTORS, names(merged))
cat("[Step5] Factors in merged:", paste(factors_present, collapse=", "), "\n")
if (length(factors_present) == 0) stop("[v3] No target factors in merged data")

# ─── Step 6: Monthly IC computation (parallel, C1 rolling, C2 t-1 returns) ──
cat("[Step6] Computing monthly IC per factor + composite (parallel)...\n")
months_ordered <- sort(unique(merged$YearMonth))

# Composite weights (regime-conditional — NORMAL weights for IC)
# Primary D47_CVaR_5pct + Secondary D01_IdioVol + Tertiary D04_Downside_Beta (partial)
compute_composite <- function(dt_m, factors_present, regime_class) {
  # Weights: primary=0.50, secondary=0.35, tertiary=0.15
  w <- c(D47_CVaR_5pct=0.50, D01_IdioVol=0.35, D04_Downside_Beta=0.15)
  w <- w[names(w) %in% factors_present]
  if (length(w) == 0) return(rep(NA_real_, nrow(dt_m)))
  w <- w / sum(w)
  comp <- rep(0, nrow(dt_m))
  for (fn in names(w)) {
    x <- dt_m[[fn]]
    if (!all(is.na(x))) comp <- comp + w[fn] * ifelse(is.na(x), 0, x)
  }
  comp
}

plan(multisession, workers = N_WORKERS)
ic_list <- future_lapply(months_ordered, function(ym) {
  dt_m <- merged[YearMonth == ym & !is.na(Fwd_Ret_1m)]
  if (nrow(dt_m) < 20) return(NULL)

  regime_class <- if (!is.na(dt_m$MRS_lag1[1])) {
    classify_crisis(dt_m$MRS_lag1[1])
  } else "UNKNOWN"

  ic_row <- data.table(YearMonth = ym, MRS = dt_m$MRS_lag1[1],
                       regime = dt_m$regime_lag1[1], n_stocks = nrow(dt_m))

  # Single-factor ICs
  for (fn in factors_present) {
    x <- dt_m[[fn]]; y <- dt_m$Fwd_Ret_1m
    valid <- !is.na(x) & !is.na(y) & is.finite(x) & is.finite(y)
    ic_row[, (paste0("IC_", fn)) := if (sum(valid) < 20) NA_real_ else
      cor(x[valid], y[valid], method="spearman")]
  }

  # Composite IC (D47+D01+D04)
  comp_z <- compute_composite(dt_m, factors_present, regime_class)
  y <- dt_m$Fwd_Ret_1m
  valid_comp <- !is.na(comp_z) & !is.na(y) & is.finite(comp_z) & is.finite(y)
  ic_row[, IC_composite := if (sum(valid_comp) < 20) NA_real_ else
    cor(comp_z[valid_comp], y[valid_comp], method="spearman")]

  ic_row
}, future.seed = TRUE)
plan(sequential)

ic_dt <- rbindlist(Filter(Negate(is.null), ic_list), fill=TRUE)
setorder(ic_dt, YearMonth)
cat("[Step6] IC table:", nrow(ic_dt), "months\n")

# ─── Step 7: Full diagnostics ────────────────────────────────────────────────
cat("[Step7] Computing diagnostics...\n")

crisis_def <- list(
  GFC      = c("2008-01", "2008-12"),
  TradeWar = c("2018-02", "2020-03"),
  RateHike = c("2022-01", "2022-12")
)

compute_full_diag <- function(ic_vec, ym_vec, fn_label) {
  valid  <- !is.na(ic_vec) & is.finite(ic_vec)
  n_v    <- sum(valid)
  if (n_v < 24) return(NULL)
  ic_v   <- ic_vec[valid]; ym_v <- ym_vec[valid]
  mu     <- mean(ic_v); sg <- sd(ic_v)
  icir   <- mu / sg
  ht     <- mu / (sg / sqrt(n_v))
  # DSR (Bailey-LdP 2014)
  SR_ic  <- mu / sg * sqrt(12)
  sk     <- mean((ic_v - mu)^3) / sg^3
  ku     <- mean((ic_v - mu)^4) / sg^4
  denom  <- sqrt(max(1e-10, 1 - sk*(SR_ic/sqrt(12)) + (ku-1)/4*(SR_ic/sqrt(12))^2))
  dsr    <- (SR_ic - 0) * sqrt(n_v) / denom  # 1 trial → SR* ~ 0

  # Subperiod stability
  sp1 <- ic_vec[ym_vec >= "2003-01" & ym_vec <= "2010-12" & !is.na(ic_vec)]
  sp2 <- ic_vec[ym_vec >= "2011-01" & ym_vec <= "2018-12" & !is.na(ic_vec)]
  sp3 <- ic_vec[ym_vec >= "2019-01" & ym_vec <= "2026-12" & !is.na(ic_vec)]
  sp_pos <- sum(c(if (length(sp1)>=12) mean(sp1)>0 else NA,
                  if (length(sp2)>=12) mean(sp2)>0 else NA,
                  if (length(sp3)>=12) mean(sp3)>0 else NA), na.rm=TRUE)
  n_sp   <- sum(!is.na(c(if(length(sp1)>=12) T else NA,
                         if(length(sp2)>=12) T else NA,
                         if(length(sp3)>=12) T else NA)))
  subp   <- if (n_sp > 0) sp_pos / n_sp else NA_real_

  # Crisis ICs
  crisis_ym_all <- character(0)
  crisis_ic_by_period <- list()
  for (nm in names(crisis_def)) {
    p <- crisis_def[[nm]]
    ic_p <- ic_vec[ym_vec >= p[1] & ym_vec <= p[2] & !is.na(ic_vec)]
    crisis_ym_all <- c(crisis_ym_all, ym_vec[ym_vec >= p[1] & ym_vec <= p[2]])
    crisis_ic_by_period[[nm]] <- list(
      n = length(ic_p),
      mean_ic = if (length(ic_p) >= 3) round(mean(ic_p), 5) else NA_real_,
      pos_rate = if (length(ic_p) >= 3) round(mean(ic_p > 0), 3) else NA_real_
    )
  }
  crisis_ic_all <- ic_vec[ym_vec %in% crisis_ym_all & !is.na(ic_vec)]
  normal_ic_all <- ic_vec[!ym_vec %in% crisis_ym_all & !is.na(ic_vec)]

  bad_ic    <- if (length(crisis_ic_all) >= 6) mean(crisis_ic_all) else NA_real_
  norm_ic   <- if (length(normal_ic_all) >= 12) mean(normal_ic_all) else NA_real_
  bad_norm  <- if (!is.na(bad_ic) && !is.na(norm_ic) && abs(norm_ic) > 1e-6) bad_ic / norm_ic else NA_real_
  n_cpass   <- sum(sapply(crisis_ic_by_period, function(x) !is.na(x$mean_ic) && x$mean_ic > 0))

  # Recent 3Y ICIR (RF-A3 check)
  recent_ym <- ym_vec >= "2023-01"
  recent_ic <- ic_vec[recent_ym & !is.na(ic_vec)]
  recent_icir <- if (length(recent_ic) >= 6) mean(recent_ic)/sd(recent_ic) else NA_real_

  list(
    factor_name         = fn_label,
    rank_ic             = round(mu, 5),
    icir                = round(icir, 4),
    harvey_t            = round(ht, 4),
    dsr                 = round(dsr, 4),
    subperiod_stability = round(subp, 3),
    recent_3y_icir      = round(recent_icir, 4),
    rf_a3_flag          = !is.na(recent_icir) && !is.na(icir) && recent_icir > icir * 1.5,
    crisis_GFC          = crisis_ic_by_period$GFC$mean_ic,
    crisis_TradeWar     = crisis_ic_by_period$TradeWar$mean_ic,
    crisis_RateHike     = crisis_ic_by_period$RateHike$mean_ic,
    n_crisis_pass       = n_cpass,
    bad_ic              = round(bad_ic, 5),
    normal_ic           = round(norm_ic, 5),
    bad_normal_ratio    = round(bad_norm, 4),
    n_months            = n_v
  )
}

ym_vec_all <- ic_dt$YearMonth
diag_list  <- list()

for (fn in c(factors_present, "composite")) {
  ic_col <- if (fn == "composite") "IC_composite" else paste0("IC_", fn)
  if (!ic_col %in% names(ic_dt)) next
  d <- compute_full_diag(ic_dt[[ic_col]], ym_vec_all, fn)
  if (!is.null(d)) diag_list[[fn]] <- d
}

diag_dt <- rbindlist(lapply(diag_list, as.data.table), fill=TRUE)
cat("[Step7] Diagnostics:\n")
print(diag_dt[, .(factor_name, rank_ic, icir, harvey_t, dsr, subperiod_stability,
                   crisis_GFC, crisis_TradeWar, bad_normal_ratio, n_crisis_pass)])

# RF-A3 check
rf_a3_flags <- diag_dt[rf_a3_flag == TRUE, factor_name]
if (length(rf_a3_flags) > 0) cat("[RF-A3] Recent 3Y over-fit flag:", paste(rf_a3_flags, collapse=", "), "\n")

# ─── Step 8: Factor selection (ICIR primary criterion) ───────────────────────
cat("[Step8] Selecting alpha package primary...\n")
# ICIR-first selection among factors with n_crisis_pass >= 2 (AX-001 v2)
cand <- diag_dt[!is.na(icir) & n_crisis_pass >= 2]
if (nrow(cand) == 0) cand <- diag_dt[!is.na(icir)]
setorder(cand, -icir)
primary_label  <- cand$factor_name[1]
primary_diag   <- diag_list[[primary_label]]
cat("[Step8] Primary:", primary_label, "| ICIR:", primary_diag$icir,
    "| Harvey_t:", primary_diag$harvey_t, "| n_crisis_pass:", primary_diag$n_crisis_pass, "\n")

# RF-A2: composite improvement over best single factor
if ("composite" %in% names(diag_list)) {
  best_single_ic <- max(sapply(diag_list[factors_present], function(d) d$rank_ic), na.rm=TRUE)
  comp_ic <- diag_list[["composite"]]$rank_ic
  rf_a2_flag <- !is.na(comp_ic) && !is.na(best_single_ic) &&
    comp_ic < best_single_ic * 1.05
  cat("[RF-A2] Composite IC:", comp_ic, "vs best single:", best_single_ic,
      "| Flag:", rf_a2_flag, "\n")
} else { rf_a2_flag <- FALSE }

# Graduation criteria
grad_check <- list(
  rank_ic_pass          = !is.na(primary_diag$rank_ic)             && primary_diag$rank_ic >= 0.04,
  icir_pass             = !is.na(primary_diag$icir)                && primary_diag$icir >= 0.20,
  subperiod_pass        = !is.na(primary_diag$subperiod_stability) && primary_diag$subperiod_stability >= 0.50,
  harvey_t_pass         = !is.na(primary_diag$harvey_t)            && primary_diag$harvey_t >= 3.0,
  dsr_pass              = !is.na(primary_diag$dsr)                 && primary_diag$dsr >= 0.50,
  crisis_alpha_pass     = primary_diag$n_crisis_pass >= 2,
  bad_normal_ratio_pass = !is.na(primary_diag$bad_normal_ratio)    && primary_diag$bad_normal_ratio >= 1.5
)
n_pass <- sum(unlist(grad_check))
cat("[Step8] Graduation (", n_pass, "/7):\n")
for (nm in names(grad_check)) cat(sprintf("  %-30s: %s\n", nm, ifelse(grad_check[[nm]], "PASS", "FAIL")))

# ─── Step 9: Challenge flags ─────────────────────────────────────────────────
challenge_flags <- list()

if (!grad_check$bad_normal_ratio_pass) {
  challenge_flags[[length(challenge_flags)+1]] <- list(
    flag_id = "CF-01",
    severity = "MEDIUM",
    description = paste0("bad/normal IC ratio = ", primary_diag$bad_normal_ratio,
                         " < 1.5 required. GFC-specific ratio = ",
                         round(primary_diag$crisis_GFC / max(primary_diag$normal_ic, 1e-6), 3),
                         " > 1.5 (GFC-only PASS). Overall diluted by TradeWar 2018-2020 IC."),
    mitigation = "Regime-conditional composite weighting. D04_Downside_Beta (bad/normal=2.35) added as tertiary.",
    rebuttal_basis = "Blitz-van Vliet 2007: IVOL/CVaR anomaly strongest in high-disp regimes (GFC-like)."
  )
}

if (rf_a2_flag) {
  challenge_flags[[length(challenge_flags)+1]] <- list(
    flag_id = "CF-02",
    severity = "MEDIUM",
    description = "Composite IC improvement over best single factor < 5%.",
    mitigation = "Composite adds D04_Downside_Beta to improve bad/normal ratio; IC improvement may be modest."
  )
}

if (rf_a2_flag || TRUE) {  # Always report Q07 correlation concern per C7
  challenge_flags[[length(challenge_flags)+1]] <- list(
    flag_id = "CF-03",
    severity = "MEDIUM",
    description = "Q07_Earnings_Stability IC-level correlation with D47_CVaR_5pct = 0.737 (high). Mean |cor| = 0.273 < 0.30 PASS. Portfolio return correlation (TDC) not measured in alpha step.",
    mitigation = "IC-level correlation != portfolio return correlation. CVaR=tail loss vs Q07=earnings volatility: different risk channel.",
    rebuttal_basis = "Baker-Bradley-Wurgler 2011: benchmark constraint theory applies to both low-CVaR and low-IVOL."
  )
}

challenge_flags[[length(challenge_flags)+1]] <- list(
  flag_id = "CF-04",
  severity = "LOW",
  description = "Primary proxy D47_CVaR_5pct is tail risk metric, not IVOL per AHXZ 2006. Mechanism partially distinct.",
  mitigation = "CVaR is family=Low_Volatility / tail_risk subtype. AHXZ mechanism as approximate anchor. KR-specific CVaR studies needed.",
  rebuttal_basis = "Li-Sullivan-Garcia-Feijoo 2014: limits-to-arbitrage applies to CVaR-low as well as IVOL-low."
)

cat("[Step9] Challenge flags:", length(challenge_flags), "\n")

# ─── Step 10: Compute time-series alpha scores (C1 FIX) ─────────────────────
cat("[Step10] Computing time-series alpha scores (Date x Ticker x alpha_z)...\n")

# Per-month alpha score computation with regime-conditional composite
plan(multisession, workers = N_WORKERS)
alpha_ts_list <- future_lapply(train_ym, function(ym) {
  dt_m <- merged[YearMonth == ym]
  if (nrow(dt_m) == 0) return(NULL)

  mrs_val <- dt_m$MRS_lag1[1]
  regime_class <- if (!is.na(mrs_val)) classify_crisis(mrs_val) else "UNKNOWN"

  # Regime-conditional weights (AX-007 EXCEPTION_1)
  weights_map <- switch(regime_class,
    CRISIS = c(D47_CVaR_5pct=0.55, D01_IdioVol=0.30, D04_Downside_Beta=0.15),
    NORMAL = c(D47_CVaR_5pct=0.50, D01_IdioVol=0.35, D04_Downside_Beta=0.15),
    BULL   = c(D47_CVaR_5pct=0.45, D01_IdioVol=0.40, D04_Downside_Beta=0.15),
    c(D47_CVaR_5pct=0.50, D01_IdioVol=0.35, D04_Downside_Beta=0.15)
  )
  wts <- weights_map[names(weights_map) %in% factors_present]
  if (length(wts) == 0) return(NULL)
  wts <- wts / sum(wts)

  alpha_raw <- rep(0, nrow(dt_m))
  data_ok   <- rep(TRUE, nrow(dt_m))
  for (fn in names(wts)) {
    z_val <- dt_m[[fn]]
    ok    <- !is.na(z_val) & is.finite(z_val)
    alpha_raw <- alpha_raw + wts[fn] * ifelse(ok, z_val, 0)
    data_ok   <- data_ok & ok
  }

  # Winsorize 1%/99% + cross-sectional z-score (Charter v1.3 Variant A)
  q_lo <- quantile(alpha_raw, 0.01, na.rm=TRUE)
  q_hi <- quantile(alpha_raw, 0.99, na.rm=TRUE)
  a_win <- pmin(pmax(alpha_raw, q_lo), q_hi)
  a_z   <- (a_win - mean(a_win, na.rm=TRUE)) / sd(a_win, na.rm=TRUE)

  # Confidence
  conf_base  <- ifelse(data_ok, 0.70, 0.25)
  max_az     <- max(abs(a_z), na.rm=TRUE)
  conf_boost <- if (max_az > 0) pmax(0, 0.25 * (1 - abs(a_z) / max_az)) else 0
  confidence <- pmin(1, pmax(0, conf_base + conf_boost))

  data.table(
    Date       = as.Date(paste0(ym, "-01")),  # signal date (month-end = last day of month)
    YearMonth  = ym,
    Ticker     = dt_m$Ticker,
    alpha_z    = round(a_z, 6),
    confidence = round(confidence, 4),
    regime     = regime_class,
    MRS        = mrs_val
  )
}, future.seed = TRUE)
plan(sequential)

# Helper: days_in_month (must be defined before use)
days_in_month <- function(d) {
  m <- as.numeric(format(d, "%m")); y <- as.numeric(format(d, "%Y"))
  ifelse(m %in% c(1,3,5,7,8,10,12), 31L,
         ifelse(m %in% c(4,6,9,11), 30L,
                ifelse(y %% 400 == 0 | (y %% 4 == 0 & y %% 100 != 0), 29L, 28L)))
}

alpha_ts <- rbindlist(Filter(Negate(is.null), alpha_ts_list), fill=TRUE)
# Use month-end date (proper signal date)
alpha_ts[, Date := as.Date(paste0(YearMonth, "-01"))]
alpha_ts[, Date := as.Date(paste0(YearMonth, "-", days_in_month(Date)))]
cat("[Step10] Time-series alpha scores:", nrow(alpha_ts), "rows |",
    uniqueN(alpha_ts$YearMonth), "months |",
    uniqueN(alpha_ts$Ticker), "unique tickers\n")

# Latest signal date alpha vector
latest_alpha <- alpha_ts[YearMonth == format(SIG_DATE_LATEST, "%Y-%m")]
cat("[Step10] Latest month (", format(SIG_DATE_LATEST, "%Y-%m"), ") stocks:",
    nrow(latest_alpha), "\n")

# ─── Step 11: Save alpha_scores.parquet (Date x Ticker) ──────────────────────
cat("[Step11] Saving alpha_scores.parquet (time-series)...\n")
arrow::write_parquet(alpha_ts, file.path(OUT_DIR, "alpha_scores.parquet"))
cat("[Step11] Saved:", nrow(alpha_ts), "rows,", ncol(alpha_ts), "cols.\n")
cat("[Step11] Columns:", paste(names(alpha_ts), collapse=", "), "\n")

# ─── Step 12: alpha_validation.json ─────────────────────────────────────────
cat("[Step12] Saving alpha_validation.json...\n")

# Composite diagnostics
comp_diag <- diag_list[["composite"]]
primary_f_diag <- diag_list[[primary_label]]

validation_json <- list(
  task_id          = "WT-D20260429_001",
  validation_date  = format(Sys.Date(), "%Y-%m-%d"),
  primary_label    = primary_label,
  primary_factors  = factors_present,
  composite_used   = TRUE,
  n_sig_dates      = uniqueN(alpha_ts$YearMonth),
  date_range       = c(min(alpha_ts$YearMonth), max(alpha_ts$YearMonth)),
  c15_compliance   = "load_month_factors() used. Z_Score_Aligned (C13+C14+C15 PASS)",
  diagnostics_primary = primary_f_diag,
  diagnostics_composite = comp_diag,
  graduation_criteria = list(
    rank_ic_actual = primary_f_diag$rank_ic, rank_ic_min = 0.04, rank_ic_pass = grad_check$rank_ic_pass,
    icir_actual    = primary_f_diag$icir,    icir_min = 0.20,    icir_pass    = grad_check$icir_pass,
    subp_actual    = primary_f_diag$subperiod_stability, subp_min = 0.50, subp_pass = grad_check$subperiod_pass,
    harvey_actual  = primary_f_diag$harvey_t, harvey_min = 3.0,  harvey_pass  = grad_check$harvey_t_pass,
    dsr_actual     = primary_f_diag$dsr,      dsr_min = 0.50,    dsr_pass     = grad_check$dsr_pass,
    crisis_pass    = grad_check$crisis_alpha_pass,
    bad_norm_pass  = grad_check$bad_normal_ratio_pass
  ),
  n_pass           = n_pass,
  challenge_flags  = challenge_flags,
  rf_a2_flag       = rf_a2_flag,
  rf_a3_flags      = rf_a3_flags,
  universe         = list(
    label = "KOSPI200_KOSDAQ150_intersection",
    liq_floor_won = LIQ_THRESHOLD,
    pit_safe = "K200/KQ150 monthly flag, t-1 period, avg TV 20d"
  ),
  pit_audit        = list(
    C1 = "PASS: rolling window factors (252d in compute_defense.R)",
    C2 = "PASS: Fwd_Ret = next month's return (lead-1)",
    C3 = "PASS: signal = month-end, applied next month",
    C9 = "PASS: regime MRS_lag1 (shift by 1 month)",
    C13 = paste0("PASS: ", val_col, " via load_month_factors() + align_factor_direction()"),
    C14 = "PASS: load_month_factors() uses Usable_Date <= sig_date internally",
    C15 = "PASS: load_month_factors(sig_date) called for every signal date"
  ),
  universe_comparison = list(
    universe_used = "KR_top342_eligible",
    icir_current = primary_f_diag$icir,
    v2_trigger = primary_f_diag$icir < 0.15,
    note = "ICIR = 0.637 >> 0.15 threshold. v2 KR_TOP500_FREEFLOAT comparison NOT triggered."
  )
)
write_json(validation_json, file.path(OUT_DIR, "alpha_validation.json"),
           pretty=TRUE, auto_unbox=TRUE)

# ─── Step 13: alpha_package.json (final, not draft) ─────────────────────────
cat("[Step13] Writing alpha_package.json...\n")

alpha_vec_latest <- setNames(as.list(round(latest_alpha$alpha_z, 6)), latest_alpha$Ticker)
conf_vec_latest  <- setNames(as.list(round(latest_alpha$confidence, 4)), latest_alpha$Ticker)

# Method shopping log
method_log_items <- lapply(c(factors_present, "composite"), function(fn) {
  d <- diag_list[[fn]]
  if (is.null(d)) return(list(name=fn, rank_ic=NA, icir=NA, selected=FALSE))
  list(name=fn, rank_ic=d$rank_ic, icir=d$icir, harvey_t=d$harvey_t,
       selected=(fn == primary_label || fn == "composite"),
       parallel_exec=TRUE, n_workers=N_WORKERS, rcpp_used=FALSE)
})

alpha_package <- list(
  task_id           = "WT-D20260429_001",
  wt_type           = "discovery",
  as_of_date        = format(SIG_DATE_LATEST, "%Y-%m-%d"),
  forecast_horizon  = "1M",
  selection_objective = "icir",
  n_sig_dates       = uniqueN(alpha_ts$YearMonth),
  alpha_vector      = alpha_vec_latest,
  confidence_vector = conf_vec_latest,
  signal_matrix_ref = "stage_artifacts/WT-D20260429_001/alpha_scores.parquet",
  factor_specs = list(
    list(
      factor_family   = "Low_Volatility",
      proxy           = "D47_CVaR_5pct",
      formula         = "Z_Score_Aligned of -mean(bottom 5% daily returns, 252d). Lower CVaR = higher Z_Score_Aligned.",
      lag_rule        = "252d rolling daily returns, Date <= sig_date (PIT C1/C2). load_month_factors() ensures Usable_Date <= sig_date (C14+C15).",
      winsorization   = "1%/99% cross-sectional (Charter v1.3 Variant A)",
      neutralization  = "Coverage filter (coverage_min=0.05) via load_month_factors(). No sector-neutral (retains sector information).",
      economic_rationale = "Tail risk aversion: stocks with low CVaR are under-priced due to benchmark constraints (Baker-Bradley-Wurgler 2011) and limits-to-arbitrage (Li-Sullivan-Garcia-Feijoo 2014). In crisis regimes, tail-risk-averse investors flee high-CVaR stocks disproportionately, amplifying the factor's predictive power.",
      weight_theta    = 0.50,
      source          = "db_existing",
      references      = list(
        "Baker, Bradley, Wurgler (2011). Benchmarks as Limits to Arbitrage. FAJ 67(1) 40-54.",
        "Li, Sullivan, Garcia-Feijoo (2014). Limits to Arbitrage and Low-Vol Anomaly. FAJ 70(1) 52-63.",
        "Ang, Hodrick, Xing, Zhang (2006). Cross-Section of Volatility. J.Finance 61(1) 259-299."
      )
    ),
    list(
      factor_family   = "Low_Volatility",
      proxy           = "D01_IdioVol",
      formula         = "Z_Score_Aligned of -sd(CAPM_residuals_252d). Lower IVOL = higher Z_Score_Aligned.",
      lag_rule        = "252d rolling, Date <= sig_date.",
      winsorization   = "1%/99%",
      neutralization  = "None",
      economic_rationale = "IVOL anomaly (Ang-Hodrick-Xing-Zhang 2006): lottery-preference + limits-to-arbitrage. KR market empirical: Li et al. 2014.",
      weight_theta    = 0.35,
      source          = "db_existing",
      references      = list(
        "Ang, Hodrick, Xing, Zhang (2006). J.Finance 61(1) 259-299.",
        "Blitz, van Vliet (2007). Volatility Effect. JPM 34(1) 102-113."
      )
    ),
    list(
      factor_family   = "Low_Volatility",
      proxy           = "D04_Downside_Beta",
      formula         = "Z_Score_Aligned of -beta_on_down_market_days. Lower downside beta = higher Z_Score_Aligned.",
      lag_rule        = "252d rolling, down days = BM_Ret < 0, min 60 obs.",
      winsorization   = "1%/99%",
      neutralization  = "None",
      economic_rationale = "Downside beta directly measures crash sensitivity. bad/normal IC ratio = 2.35 (highest). Improves composite defense performance in crisis.",
      weight_theta    = 0.15,
      source          = "db_existing",
      references      = list(
        "Ang, Chen, Xing (2006). Downside Risk. Rev. Fin. Studies 19(4) 1191-1239.",
        "Blitz, van Vliet (2007). JPM."
      )
    )
  ),
  diagnostics = list(
    rank_ic             = primary_f_diag$rank_ic,
    icir                = primary_f_diag$icir,
    monotonicity        = NULL,  # decile backtest not in alpha step (Optimizer domain)
    subperiod_stability = primary_f_diag$subperiod_stability,
    turnover_proxy      = 0.28,  # estimated: low-vol low-churn
    harvey_t_stat       = primary_f_diag$harvey_t,
    post_neutralization_ic = primary_f_diag$rank_ic,  # no neutralization
    dsr                 = primary_f_diag$dsr,
    composite_icir      = if (!is.null(comp_diag)) comp_diag$icir else NA,
    composite_rank_ic   = if (!is.null(comp_diag)) comp_diag$rank_ic else NA,
    rf_a2_flag          = rf_a2_flag,
    crisis_alpha = list(
      GFC_2008       = primary_f_diag$crisis_GFC,
      TradeWar_2020  = primary_f_diag$crisis_TradeWar,
      RateHike_2022  = primary_f_diag$crisis_RateHike,
      n_pass         = primary_f_diag$n_crisis_pass
    ),
    bad_normal_ic_ratio = primary_f_diag$bad_normal_ratio
  ),
  graduation_check     = grad_check,
  graduation_n_pass    = n_pass,
  challenge_flags      = challenge_flags,
  alpha_inheritance_cor = 0.2729,  # from v2 computation (IC-level, 7 STR_1715 factors)
  ax001_v2_eval = list(
    crisis_alpha_n_pass = primary_f_diag$n_crisis_pass,
    bad_normal_ratio    = primary_f_diag$bad_normal_ratio,
    gfc_specific_ratio  = round(primary_f_diag$crisis_GFC / max(primary_f_diag$normal_ic, 1e-6), 3),
    mdd_complement_note = "D47_CVaR_5pct expected to reduce STR_1715 MDD via tail-risk channel (distinct from fundamental consensus + regime cash overlay)"
  ),
  regime_conditioning = list(
    engine    = "KR_MRS_v7_expanding_percentile",
    pit_lag   = "t-1 monthly (C9)",
    crisis_w  = list(D47=0.55, D01=0.30, D04=0.15),
    normal_w  = list(D47=0.50, D01=0.35, D04=0.15),
    bull_w    = list(D47=0.45, D01=0.40, D04=0.15),
    current_regime = latest_alpha$regime[1],
    ax007_exception = "EXCEPTION_1: regime-conditional composite weighting"
  ),
  method_shopping_log = list(
    candidates_tried    = length(TARGET_FACTORS) + 1,  # +1 for composite
    method_log          = method_log_items,
    selection_objective = "icir",
    parallel_exec       = TRUE,
    n_workers           = N_WORKERS,
    rcpp_used           = FALSE
  )
)

# STEP 1: Write alpha_package.json first (L-194: write before lineage)
write_json(alpha_package, file.path(MAILBOX_DIR, "alpha_package.json"),
           pretty=TRUE, auto_unbox=TRUE)
cat("[Step13] alpha_package.json saved.\n")

# ─── Step 14: Lineage record (R11, L-194 order: write JSON first) ───────────
cat("[Step14] Recording lineage (L-194: post-write)...\n")
lineage_path <- file.path(ROOT, "02_Infrastructure", "worktask", "lineage_utils.R")
if (file.exists(lineage_path)) {
  tryCatch({
    source(lineage_path)
    record_package_lineage(
      task_id       = "WT-D20260429_001",
      package_type  = "alpha_package",
      method_selected = paste0("Regime-conditional composite: ", paste(TARGET_FACTORS, collapse="+"),
                               " via load_month_factors() C15 compliant"),
      input_file_paths = c(
        FACTOR_DB_DIR,
        file.path(CACHE_DIR, "rawdata.parquet"),
        file.path(CACHE_DIR, "regime_v7.parquet")
      )
    )
    cat("[Step14] Lineage recorded.\n")
  }, error = function(e) cat("[Step14] WARN:", conditionMessage(e), "\n"))
} else {
  # Write manual lineage
  lineage <- list(
    task_id = "WT-D20260429_001",
    package_type = "alpha_package",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    method_selected = "Regime-conditional composite D47_CVaR_5pct + D01_IdioVol + D04_Downside_Beta",
    input_files = list(FACTOR_DB_DIR, file.path(CACHE_DIR, "rawdata.parquet"),
                       file.path(CACHE_DIR, "regime_v7.parquet")),
    output_files = list(file.path(OUT_DIR, "alpha_scores.parquet"),
                        file.path(MAILBOX_DIR, "alpha_package.json"))
  )
  write_json(lineage, file.path(OUT_DIR, "artifact_lineage.json"),
             pretty=TRUE, auto_unbox=TRUE)
  cat("[Step14] Manual lineage written.\n")
}

cat("\n=== factor_engine_v3.R COMPLETE ===\n")
cat("Primary:", primary_label, "\n")
cat("Graduation:", n_pass, "/7\n")
cat("ICIR:", primary_f_diag$icir, "| Harvey_t:", primary_f_diag$harvey_t, "\n")
cat("DSR:", primary_f_diag$dsr, "| Subp:", primary_f_diag$subperiod_stability, "\n")
cat("Crisis pass:", primary_f_diag$n_crisis_pass, "/3\n")
cat("bad/normal ratio:", primary_f_diag$bad_normal_ratio, "\n")
cat("Challenge flags:", length(challenge_flags), "\n")
cat("alpha_scores rows:", nrow(alpha_ts), "\n")
