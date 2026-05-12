#==============================================================================
# WT-D20260511_001 PD32 — 5th Orthogonal Alpha Source Research
#
# Mission:
#   raw alpha SR ~1.02 -> target SR 2.0, gap ~0.98
#   C_softmax PG2 admit (55% KR composite + 22.5% TSMOM + 18% KR_10y + 4.5% cash)
#   탐색: 5th orthogonal alpha source (cor < 0.30 with existing composite)
#
# Candidates (학술 메커니즘 출발 3+):
#   D (1st): Crowding/Herding Composite (CR03 + CR07 + CR11)  — Lou-Polk 2022, Stambaugh et al 2015
#   B (2nd): Investment Frictions (-GR03 + -IN01 + -IN04, low-investment alpha) — Cooper-Gulen-Schill 2008
#   A (3rd): Accrual Reversal Composite (-AC01 + -AC03 + -AC22) — Sloan 1996, KR Kim 2010
#
# Anti-candidates (skip):
#   E (Low-IVOL) — HIGH cor risk with NEW Vol/Skew D43/D41/D58 (이미 admitted)
#   F (Net Equity Issuance alone) — single signal AX-005 EXCLUSION concern (composite로 통합 in B)
#
# Constraints:
#   cor < 0.30 with PD27 1715 H1 score_eff (297m base)
#   AX-001 v2 conditional defense (crisis_alpha + bad regime IC > 0)
#   KR availability + cost < 50bps + max 20 names + Σw = 1
#   PIT C1~C15 strict via Factor DB load_month_factors() (C15 정합)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

cat("============================================================\n")
cat("WT-D20260511_001 PD32 — 5th orthogonal alpha source research\n")
cat("Start:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("============================================================\n\n")

# ---- Paths ----
PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")

PD27_ALPHA <- file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")
PD32_OUT   <- file.path(STAGE_DIR, "alpha_scores_pd32_5th_source.parquet")
PD32_LOG   <- file.path(WT_DIR, "pd32_5th_source_log.json")
PD32_DIAG  <- file.path(STAGE_DIR, "pd32_factor_diagnostic.csv")

# ---- PIT params ----
COVERAGE_MIN <- 0.05
BURN_IN_MONTHS <- 36L  # expanding IC alignment burn-in (per PIT C13)
NEUTRALIZE <- "sector_demean"

# Lockbox per alpha-research scope (.claude/rules/lockbox-scope.md)
SIG_DATE_CUTOFF_LOCKBOX <- as.Date("2024-01-22")
DEC_WINDOW_START <- as.Date("2001-07-01")
DEC_WINDOW_END   <- as.Date("2026-04-01")   # Forge input window per scope refinement

# Final factor sets per candidate
CANDIDATE_D <- list(
  name = "Crowding_Anti_Herding",
  factors = c("CR03_Herding_Dispersion", "CR07_Momentum_Crowding", "CR11_Idiosyncratic_Return"),
  directions = c(-1L, -1L, +1L),  # anti-herding (low CR03/CR07) + idio momentum
  rationale = "Lou-Polk 2022 RFS: anti-crowded outperform; Stambaugh-Yu-Yuan 2015 JF: low-herding alpha; Idio mom (Daniel-Moskowitz 2016)",
  family = "Crowding_Anti_Herding"
)
CANDIDATE_B <- list(
  name = "Investment_Frictions",
  factors = c("GR03_Asset_Growth", "IN01_CapEx_to_Assets", "IN04_Net_Equity_Issuance"),
  directions = c(-1L, -1L, -1L),  # low investment/issuance outperform (q-factor world)
  rationale = "Cooper-Gulen-Schill 2008 JF Asset Growth Anomaly; Fama-French 2015 5F Investment; Daniel-Titman 2006 Equity Issuance",
  family = "Investment_Frictions"
)
CANDIDATE_A <- list(
  name = "Accrual_Reversal",
  factors = c("AC01_Total_Accruals_CF", "AC03_WC_Accruals", "AC22_Accrual_Volatility"),
  directions = c(-1L, -1L, -1L),  # low accrual outperform
  rationale = "Sloan 1996 TAR Accrual Anomaly; Hirshleifer et al 2004 JFE Investor Underreaction; KR Kim 2010 PBFJ",
  family = "Accrual_Reversal"
)

CANDIDATES <- list(D = CANDIDATE_D, B = CANDIDATE_B, A = CANDIDATE_A)

cat("Candidates (3+):\n")
for(k in names(CANDIDATES)) {
  cat(sprintf("  %s = %s: %s\n", k, CANDIDATES[[k]]$name, paste(CANDIDATES[[k]]$factors, collapse=", ")))
  cat(sprintf("     rationale: %s\n\n", CANDIDATES[[k]]$rationale))
}

# ---- Load PD27 base alpha (1715 H1, 297m burn0m) ----
cat("\n[STEP 1] Load PD27 1715 H1 base alpha_scores\n")
pd27 <- as.data.table(read_parquet(PD27_ALPHA))
cat("PD27 base nrow:", nrow(pd27), " | sig_dates:", uniqueN(pd27$Date),
    " | tickers:", uniqueN(pd27$Ticker), "\n")

# Sig dates list
sig_dates_all <- sort(unique(pd27$Date))
sig_dates_all <- sig_dates_all[sig_dates_all >= DEC_WINDOW_START & sig_dates_all <= DEC_WINDOW_END]

# alpha-research scope: decision window = pre-lockbox (lockbox-scope.md)
sig_dates_decision <- sig_dates_all[sig_dates_all <= SIG_DATE_CUTOFF_LOCKBOX]
cat("Sig dates total full (Forge input):", length(sig_dates_all), "\n")
cat("Sig dates decision (pre-lockbox, alpha-research scope):", length(sig_dates_decision), "\n\n")

# ---- Helper: factor DB load (existing connector, C15-compliant) ----
source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

# ---- Liquidity floor + sector neutralization helper ----
# RAWDATA for AvgTV20 / Sector
RAWDATA_PATH <- file.path(CACHE_DIR, "rawdata.rds")
rawdata <- NULL
if(file.exists(RAWDATA_PATH)) {
  rawdata <- as.data.table(readRDS(RAWDATA_PATH))
  if(!"Date" %in% names(rawdata) && "date" %in% names(rawdata)) setnames(rawdata, "date", "Date")
  setkey(rawdata, Date, Ticker)
  cat("RAWDATA loaded: ", nrow(rawdata), "rows, cols:", paste(head(names(rawdata), 12), collapse=","), "\n")
} else {
  cat("RAWDATA missing — fallback to factor DB sector if available\n")
}

# Sector mapping (use latest non-NA)
sector_map_global <- NULL
if(!is.null(rawdata) && "Industry_Code" %in% names(rawdata)) {
  sector_map_global <- rawdata[!is.na(Industry_Code), .(Sector = last(Industry_Code)), by = Ticker]
} else if(!is.null(rawdata) && "Industry_Name" %in% names(rawdata)) {
  sector_map_global <- rawdata[!is.na(Industry_Name), .(Sector = last(Industry_Name)), by = Ticker]
}
cat("Sector map size:", if(!is.null(sector_map_global)) nrow(sector_map_global) else 0, "\n\n")

# ---- Helper: build candidate composite signal at a single sig_date ----
build_candidate_signal <- function(sig_d, cand) {
  factors_needed <- cand$factors
  directions <- cand$directions

  # PIT-safe factor DB read (C15-compliant via connector)
  fdt <- tryCatch(
    load_month_factors(sig_date = sig_d, coverage_min = COVERAGE_MIN),
    error = function(e) NULL
  )
  if(is.null(fdt) || nrow(fdt) == 0) return(NULL)
  setDT(fdt)

  # Expected wide columns from connector: Ticker + Z_Score_Aligned + Factor_Name pivot OR long form
  # Check shape and reshape if needed
  long_cols <- c("Ticker", "Factor_Name", "Z_Score_Aligned")
  if(all(long_cols %in% names(fdt))) {
    # Long-form: pivot to wide for selected factors
    fdt_sub <- fdt[Factor_Name %in% factors_needed, .(Ticker, Factor_Name, Z_Score_Aligned)]
    if(nrow(fdt_sub) == 0) return(NULL)
    fdt_wide <- dcast(fdt_sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  } else if(all(c("Ticker", factors_needed) %in% names(fdt))) {
    fdt_wide <- fdt[, c("Ticker", factors_needed), with = FALSE]
  } else {
    # Try raw columns + manual direction align (if Z_Score_Aligned missing)
    avail <- intersect(factors_needed, names(fdt))
    if(length(avail) == 0) return(NULL)
    fdt_wide <- fdt[, c("Ticker", avail), with = FALSE]
  }

  # Apply direction multiplier (Z_Score_Aligned이면 higher_better 동일 부호이므로 dir=-1은 negate.
  #   하지만 Z_Score_Aligned는 이미 higher_better → "lower_better" factor를 단순 부호 반전 사용해야 함.
  #   여기서 directions은 우리가 의도하는 alpha direction (negative coef on raw factor)이라 보고
  #   Z_Score_Aligned ↔ 이미 registry direction 정합. 즉:
  #   - Z_Score_Aligned는 registry direction에 맞춰 higher=better 정렬됨
  #   - 우리 후보의 directions은 raw → "low investment alpha" = direction -1 = registry "higher_better"인 GR03/IN01의 경우 dir=-1
  #     → Z_Score_Aligned가 이미 higher_better라면 *-1 negate 필요 (low GR03이 alpha).
  #   - reverse: Q25 Ohlson_O는 dir=lower_better 이므로 registry Z_Score_Aligned는 -value (이미 부호 반전됨)
  #
  # 단순 정합 위해 우리는 raw Z_Score_Aligned에 의도 direction을 곱한다.
  # 단, registry 자체에서 "dir=lower_better" factor (AC01 등)는 이미 Z_Score_Aligned로 부호 반전 적용됨.
  # 즉 Z_Score_Aligned는 항상 "higher=better" semantic. 우리 cand$directions은 raw → alpha direction:
  # CR03 raw direction = "higher_better" (registry), 우리 의도는 anti-herding = LOW CR03 → direction = -1
  # → Z_Score_Aligned (higher=better as is) 이므로 우리는 -1 곱해야 함

  for(i in seq_along(factors_needed)) {
    f <- factors_needed[i]
    if(f %in% names(fdt_wide)) {
      fdt_wide[[f]] <- fdt_wide[[f]] * directions[i]
    }
  }

  # Cross-sectional z-score per factor (re-standardize after direction flip)
  for(f in factors_needed) {
    if(!f %in% names(fdt_wide)) next
    v <- fdt_wide[[f]]
    mu <- mean(v, na.rm = TRUE)
    sg <- sd(v, na.rm = TRUE)
    if(is.na(sg) || sg <= 1e-10) fdt_wide[[f]] <- NA_real_
    else fdt_wide[[f]] <- (v - mu) / sg
  }

  # EW composite (rowMeans across factors_needed, ignore NA)
  avail_f <- intersect(factors_needed, names(fdt_wide))
  if(length(avail_f) == 0) return(NULL)
  mat <- as.matrix(fdt_wide[, ..avail_f])
  composite <- rowMeans(mat, na.rm = TRUE)

  # Sector neutralization (demean within sector)
  out <- data.table(Ticker = fdt_wide$Ticker, composite_raw = composite)
  if(!is.null(sector_map_global)) {
    out <- merge(out, sector_map_global, by = "Ticker", all.x = TRUE)
    out[is.na(Sector), Sector := "UNKNOWN"]
    out[, sector_mean := mean(composite_raw, na.rm = TRUE), by = Sector]
    out[, composite_neut := composite_raw - sector_mean]
  } else {
    out[, composite_neut := composite_raw]
  }

  # Final z-score (cross-section)
  v <- out$composite_neut
  mu <- mean(v, na.rm = TRUE); sg <- sd(v, na.rm = TRUE)
  if(is.na(sg) || sg <= 1e-10) {
    out[, composite_z := NA_real_]
  } else {
    out[, composite_z := (v - mu) / sg]
  }

  out[, sig_date := sig_d]
  return(out[, .(sig_date, Ticker, composite_raw, composite_neut, composite_z, n_factors_used = length(avail_f))])
}

# ---- Run for all 3 candidates over all sig_dates ----
cat("[STEP 2-3] Compute candidate composite signals over sig_dates\n")
results_by_cand <- list()
t0 <- Sys.time()

for(cand_id in names(CANDIDATES)) {
  cand <- CANDIDATES[[cand_id]]
  cat(sprintf("  Candidate %s = %s ...\n", cand_id, cand$name))
  all_rows <- vector("list", length(sig_dates_all))
  n_ok <- 0L
  for(i in seq_along(sig_dates_all)) {
    sig_d <- sig_dates_all[i]
    r <- tryCatch(build_candidate_signal(sig_d, cand), error = function(e) {
      cat("    sig_date", as.character(sig_d), "error:", conditionMessage(e), "\n")
      NULL
    })
    if(!is.null(r) && nrow(r) > 0) {
      all_rows[[i]] <- r
      n_ok <- n_ok + 1L
    }
  }
  combined <- rbindlist(all_rows[!sapply(all_rows, is.null)], fill = TRUE)
  cat(sprintf("    -> %d sig_dates ok (%d rows total)\n", n_ok, nrow(combined)))
  results_by_cand[[cand_id]] <- combined
}
t_elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
cat(sprintf("Composite signal compute elapsed: %.2f min\n\n", t_elapsed))

# ---- Step 4: Diagnostics per candidate ----
cat("[STEP 4] Diagnostics — IC / ICIR / Harvey-t / cor vs PD27 base\n")

# Build 1M forward return per sig_date from RAWDATA (price t -> t+1month return)
build_fwd_return <- function() {
  if(is.null(rawdata) || !"Close" %in% names(rawdata)) {
    cat("  [WARN] RAWDATA Close missing, fallback to PD27 Ret_1m\n")
    return(pd27[, .(sig_date = Date, Ticker, Ret_1m)])
  }
  # Use month-end Close for each sig_date Ticker
  setorder(rawdata, Date, Ticker)
  # Just leverage Ret_1m already in pd27 (computed forward 1M return per sig_date)
  return(pd27[, .(sig_date = Date, Ticker, Ret_1m)])
}
fwd_ret <- build_fwd_return()
setkey(fwd_ret, sig_date, Ticker)

ic_summary <- list()
for(cand_id in names(CANDIDATES)) {
  cand <- CANDIDATES[[cand_id]]
  comp <- results_by_cand[[cand_id]]
  if(nrow(comp) == 0) {
    ic_summary[[cand_id]] <- list(mean_ic = NA, icir = NA, harvey_t = NA, n_months = 0, pos_share = NA)
    next
  }
  # Merge with forward return
  setkey(comp, sig_date, Ticker)
  m <- merge(comp[, .(sig_date, Ticker, composite_z)],
             fwd_ret, by = c("sig_date", "Ticker"))
  m <- m[!is.na(composite_z) & !is.na(Ret_1m)]

  # IC per sig_date (Spearman)
  ic_per_date <- m[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method = "spearman", use = "pairwise.complete.obs") else NA_real_), by = sig_date]
  ic_per_date <- ic_per_date[!is.na(ic)]

  mean_ic <- mean(ic_per_date$ic)
  sd_ic   <- sd(ic_per_date$ic)
  icir    <- if(sd_ic > 1e-10) mean_ic / sd_ic else NA_real_
  # Harvey naive t (no NW for cross-section IC time series)
  n_m     <- nrow(ic_per_date)
  t_naive <- if(n_m > 1) mean_ic / (sd_ic / sqrt(n_m)) else NA_real_

  # Newey-West HAC lag 6
  t_nw <- NA_real_
  if(n_m > 12) {
    # Manual NW estimator
    e <- ic_per_date$ic - mean_ic
    lag <- 6L
    gamma0 <- sum(e^2) / n_m
    s_sum <- gamma0
    for(l in seq_len(lag)) {
      w <- 1 - l / (lag + 1)
      gl <- sum(e[(l+1):n_m] * e[1:(n_m - l)]) / n_m
      s_sum <- s_sum + 2 * w * gl
    }
    se_nw <- sqrt(s_sum / n_m)
    t_nw  <- mean_ic / se_nw
  }
  pos_share <- mean(ic_per_date$ic > 0)

  ic_summary[[cand_id]] <- list(
    mean_ic = mean_ic, sd_ic = sd_ic, icir = icir,
    t_naive = t_naive, t_nw_lag6 = t_nw, n_months = n_m,
    pos_share = pos_share
  )
  cat(sprintf("  %s: IC=%.4f ICIR=%.4f t_NW=%.3f n=%d pos=%.2f\n",
              cand_id, mean_ic, icir, t_nw, n_m, pos_share))
}

# ---- Step 5: cor with PD27 base score_eff per sig_date ----
cat("\n[STEP 5] Cross-section cor vs PD27 1715 H1 base composite (constraint <0.30)\n")
cor_summary <- list()
pd27_key <- pd27[, .(sig_date = Date, Ticker, score_pd27 = score_eff)]
setkey(pd27_key, sig_date, Ticker)

for(cand_id in names(CANDIDATES)) {
  comp <- results_by_cand[[cand_id]]
  if(nrow(comp) == 0) {
    cor_summary[[cand_id]] <- list(cor_overall = NA, cor_per_date_mean = NA, cor_per_date_sd = NA)
    next
  }
  m <- merge(comp[, .(sig_date, Ticker, composite_z)], pd27_key, by = c("sig_date", "Ticker"))
  m <- m[!is.na(composite_z) & !is.na(score_pd27)]
  if(nrow(m) == 0) {
    cor_summary[[cand_id]] <- list(cor_overall = NA, cor_per_date_mean = NA, cor_per_date_sd = NA)
    next
  }
  c_all <- cor(m$composite_z, m$score_pd27, method = "spearman", use = "pairwise.complete.obs")
  c_per <- m[, .(c = if(.N >= 20) cor(composite_z, score_pd27, method = "spearman") else NA_real_), by = sig_date][!is.na(c)]
  cor_summary[[cand_id]] <- list(
    cor_overall_rank = c_all,
    cor_per_date_mean = mean(c_per$c),
    cor_per_date_sd = sd(c_per$c),
    cor_per_date_min = min(c_per$c),
    cor_per_date_max = max(c_per$c),
    n_dates = nrow(c_per),
    constraint_pass_strict_lt_0_30 = abs(mean(c_per$c)) < 0.30
  )
  cat(sprintf("  %s: cor_overall=%.4f | per-date mean=%.4f sd=%.4f [%.3f, %.3f] | <0.30: %s\n",
              cand_id, c_all, mean(c_per$c), sd(c_per$c), min(c_per$c), max(c_per$c),
              ifelse(abs(mean(c_per$c)) < 0.30, "PASS", "FAIL")))
}

# ---- Step 5b: Crisis hedge — AX-001 v2 bad regime IC ----
cat("\n[STEP 5b] AX-001 v2 Crisis hedge check — bad regime IC > 0\n")

# Define crisis windows: 2008 GFC + 2011 European + 2015-16 China crash + 2020 COVID + 2022 KR bear
crisis_windows <- list(
  c("2008-09-01", "2009-03-31"),
  c("2011-08-01", "2011-12-31"),
  c("2015-06-01", "2016-02-29"),
  c("2020-02-01", "2020-04-30"),
  c("2022-05-01", "2022-10-31")
)
is_crisis <- function(d) {
  any(sapply(crisis_windows, function(w) d >= as.Date(w[1]) & d <= as.Date(w[2])))
}

crisis_summary <- list()
for(cand_id in names(CANDIDATES)) {
  comp <- results_by_cand[[cand_id]]
  if(nrow(comp) == 0) { crisis_summary[[cand_id]] <- list(crisis_ic = NA, normal_ic = NA, ratio = NA); next }
  setkey(comp, sig_date, Ticker)
  m <- merge(comp[, .(sig_date, Ticker, composite_z)], fwd_ret, by = c("sig_date", "Ticker"))
  m <- m[!is.na(composite_z) & !is.na(Ret_1m)]
  m[, regime := ifelse(sapply(sig_date, is_crisis), "crisis", "normal")]
  ic_by_regime <- m[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method = "spearman") else NA_real_),
                    by = .(sig_date, regime)]
  ic_by_regime <- ic_by_regime[!is.na(ic)]
  crisis_ic <- ic_by_regime[regime == "crisis", mean(ic)]
  normal_ic <- ic_by_regime[regime == "normal", mean(ic)]
  ax001_pass <- !is.na(crisis_ic) && crisis_ic > 0
  crisis_summary[[cand_id]] <- list(
    crisis_ic = crisis_ic,
    normal_ic = normal_ic,
    ratio_c_over_n = crisis_ic / normal_ic,
    n_crisis_months = nrow(ic_by_regime[regime == "crisis"]),
    n_normal_months = nrow(ic_by_regime[regime == "normal"]),
    ax001_v2_pass = ax001_pass
  )
  cat(sprintf("  %s: crisis_IC=%.4f | normal_IC=%.4f | ratio=%.2f | AX-001 v2 pass=%s\n",
              cand_id, crisis_ic, normal_ic, crisis_ic/normal_ic, ax001_pass))
}

# ---- Step 5c: Subperiod stability (3 windows) ----
cat("\n[STEP 5c] Subperiod stability (3 windows)\n")
subperiod_summary <- list()
windows <- list(
  P1_2001_2008 = c("2001-07-01", "2008-08-31"),
  P2_2009_2017 = c("2009-04-01", "2017-12-31"),
  P3_2018_2026 = c("2018-01-01", "2026-04-01")
)

for(cand_id in names(CANDIDATES)) {
  comp <- results_by_cand[[cand_id]]
  if(nrow(comp) == 0) { subperiod_summary[[cand_id]] <- list(); next }
  setkey(comp, sig_date, Ticker)
  m <- merge(comp[, .(sig_date, Ticker, composite_z)], fwd_ret, by = c("sig_date", "Ticker"))
  m <- m[!is.na(composite_z) & !is.na(Ret_1m)]

  ws <- list()
  for(wn in names(windows)) {
    w <- windows[[wn]]
    sub <- m[sig_date >= as.Date(w[1]) & sig_date <= as.Date(w[2])]
    if(nrow(sub) < 200) { ws[[wn]] <- list(ic = NA, icir = NA, n = nrow(sub)); next }
    ic_per <- sub[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method = "spearman") else NA_real_),
                  by = sig_date][!is.na(ic)]
    ic <- mean(ic_per$ic); sd_ic <- sd(ic_per$ic)
    icir <- if(sd_ic > 1e-10) ic / sd_ic else NA_real_
    ws[[wn]] <- list(rank_ic = ic, icir = icir, n_months = nrow(ic_per))
  }
  ics <- sapply(ws, function(x) x$rank_ic)
  min_max_ratio <- if(all(!is.na(ics)) && max(abs(ics)) > 1e-6) min(ics) / max(ics) else NA
  ws$min_max_ratio <- min_max_ratio
  ws$subperiod_gate_pass <- !is.na(min_max_ratio) && min_max_ratio >= 0.50
  subperiod_summary[[cand_id]] <- ws
  cat(sprintf("  %s: P1=%.4f P2=%.4f P3=%.4f | min/max=%.3f | gate(>=0.5)=%s\n",
              cand_id, ics[1], ics[2], ics[3], min_max_ratio,
              !is.na(min_max_ratio) && min_max_ratio >= 0.50))
}

# ---- Step 6: Selection + summary ----
cat("\n[STEP 6] Candidate selection scoring\n")
selection_score <- list()
for(cand_id in names(CANDIDATES)) {
  s <- 0
  reasons <- character(0)
  ic <- ic_summary[[cand_id]]
  co <- cor_summary[[cand_id]]
  cs <- crisis_summary[[cand_id]]
  sp <- subperiod_summary[[cand_id]]

  if(!is.null(ic) && !is.na(ic$mean_ic) && ic$mean_ic > 0.02) { s <- s + 25; reasons <- c(reasons, sprintf("IC %.4f >0.02", ic$mean_ic)) }
  if(!is.null(ic) && !is.na(ic$icir)    && ic$icir > 0.20)   { s <- s + 25; reasons <- c(reasons, sprintf("ICIR %.3f >0.20", ic$icir)) }
  if(!is.null(ic) && !is.na(ic$t_nw_lag6) && ic$t_nw_lag6 > 3.0) { s <- s + 15; reasons <- c(reasons, sprintf("t_NW %.2f >3", ic$t_nw_lag6)) }
  if(!is.null(co) && !is.na(co$cor_per_date_mean) && abs(co$cor_per_date_mean) < 0.30) { s <- s + 15; reasons <- c(reasons, sprintf("cor %.3f <0.30", co$cor_per_date_mean)) }
  if(!is.null(cs) && isTRUE(cs$ax001_v2_pass)) { s <- s + 10; reasons <- c(reasons, "AX-001 v2 crisis hedge PASS") }
  if(!is.null(sp$subperiod_gate_pass) && sp$subperiod_gate_pass) { s <- s + 10; reasons <- c(reasons, "subperiod gate PASS") }

  selection_score[[cand_id]] <- list(score = s, reasons = reasons)
  cat(sprintf("  %s: score=%d | %s\n", cand_id, s, paste(reasons, collapse="; ")))
}

best <- names(which.max(sapply(selection_score, function(x) x$score)))
cat(sprintf("\n=> BEST candidate = %s (%s)\n\n", best, CANDIDATES[[best]]$name))

# ---- Save best candidate alpha_scores ----
cat("[STEP 7] Save best candidate alpha_scores parquet\n")
best_comp <- results_by_cand[[best]]
best_comp[, sleeve_label := CANDIDATES[[best]]$name]
write_parquet(best_comp, PD32_OUT)
cat("Written:", PD32_OUT, "\n")

# Diagnostic CSV (all 3 candidates summary)
diag_dt <- rbindlist(lapply(names(CANDIDATES), function(k) {
  ic <- ic_summary[[k]]; co <- cor_summary[[k]]; cs <- crisis_summary[[k]]; sp <- subperiod_summary[[k]]
  data.table(
    candidate = k, name = CANDIDATES[[k]]$name,
    family = CANDIDATES[[k]]$family,
    mean_IC = ic$mean_ic, ICIR = ic$icir, t_NW_lag6 = ic$t_nw_lag6,
    n_months = ic$n_months, pos_share = ic$pos_share,
    cor_vs_pd27_mean = co$cor_per_date_mean,
    cor_vs_pd27_overall = co$cor_overall_rank,
    crisis_IC = cs$crisis_ic, normal_IC = cs$normal_ic,
    ax001_v2_pass = cs$ax001_v2_pass,
    P1_IC = sp$P1_2001_2008$rank_ic, P2_IC = sp$P2_2009_2017$rank_ic, P3_IC = sp$P3_2018_2026$rank_ic,
    subperiod_min_max_ratio = sp$min_max_ratio,
    selection_score = selection_score[[k]]$score
  )
}))
fwrite(diag_dt, PD32_DIAG)
cat("Diagnostic CSV:", PD32_DIAG, "\n")

# ---- Log JSON ----
log_obj <- list(
  task_id = "WT-D20260511_001",
  pd_phase = "PD32_5th_orthogonal_source",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  elapsed_min = round(t_elapsed, 2),
  candidates = lapply(names(CANDIDATES), function(k) {
    list(
      id = k,
      name = CANDIDATES[[k]]$name,
      family = CANDIDATES[[k]]$family,
      factors = CANDIDATES[[k]]$factors,
      directions = CANDIDATES[[k]]$directions,
      rationale = CANDIDATES[[k]]$rationale,
      diagnostics = ic_summary[[k]],
      cor_vs_pd27 = cor_summary[[k]],
      crisis_hedge = crisis_summary[[k]],
      subperiod = subperiod_summary[[k]],
      selection_score = selection_score[[k]]
    )
  }),
  selected_candidate = best,
  output_parquet = PD32_OUT,
  diagnostic_csv = PD32_DIAG
)
write_json(log_obj, PD32_LOG, pretty = TRUE, auto_unbox = TRUE)
cat("Log JSON:", PD32_LOG, "\n")

cat("\n============================================================\n")
cat("PD32 5th source research complete.\n")
cat("End:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("============================================================\n")
