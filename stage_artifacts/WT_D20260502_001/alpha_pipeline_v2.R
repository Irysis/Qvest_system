#==============================================================================
# WT-D20260502_001 Alpha Pipeline v2 — Extended window 2008-2026 + multi-regime defs
#
# v2 changes from v1:
#  - Window 2021-2026 → 2008-2026 (capture 2008 GFC + 2011 EU + 2018 + 2020 COVID)
#  - 3 regime definitions tested (Definition A: Category, B: Layer1_Alert, C: MRS percentile)
#  - Per-definition conditional IC reported for AX-001 v2 4-axis
#  - Honest reporting: if NO definition produces positive bad-state IC, declare HYPOTHESIS_FAILED
#==============================================================================

suppressMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(dplyr)
  library(future)
  library(future.apply)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260502_001"
WT_DIR <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)
SA_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001")
FUNC_PATH <- file.path(PROJ, "02_Infrastructure")
CACHE_DIR <- file.path(PROJ, ".cache")

dir.create(SA_DIR, showWarnings = FALSE, recursive = TRUE)
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

cat("\n==== STEP 1: Hypothesis Intake ====\n")
req <- jsonlite::fromJSON(file.path(WT_DIR, "request.json"))

PRIMARY_FACTORS <- c(
  "Q07_Earnings_Stability",
  "Q33_Earnings_Persistence",
  "Q25_Ohlson_O",
  "Q35_CashBased_OpProf",
  "Q08_Composite_Quality"
)
AUX_FACTORS <- c("D43_Skewness", "R13_NCSKEW")
ALL_FACTORS <- c(PRIMARY_FACTORS, AUX_FACTORS)

cat("\n==== STEP 2: Factor Sourcing (extended window) ====\n")
START_DATE <- as.Date("2008-01-01")
END_DATE <- as.Date("2026-04-30")
LIQ_THRESHOLD <- as.numeric(req$universe_definition$liquidity_min_won_20d_avg)
cat(sprintf("Window: %s to %s | LIQ_THRESHOLD: %.0e KRW\n", START_DATE, END_DATE, LIQ_THRESHOLD))

#=== Universe + returns ========================================================
cat("\nLoading rawdata...\n")
rd <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "rawdata.parquet")))
rd[, Date := as.Date(Date)]
setkey(rd, Ticker, Date)
rd <- rd[Date >= START_DATE & Date <= END_DATE]

rd[, ym := format(Date, "%Y-%m")]
month_ends <- rd[, .(month_end = max(Date)), by = ym]
setkey(month_ends, month_end)

setkey(rd, Ticker, Date)
rd[, TV := Close * Vol]
rd[, ADV20 := frollmean(TV, 20, fill = NA, na.rm = TRUE), by = Ticker]

month_panel <- rd[Date %in% month_ends$month_end,
                  .(Ticker, Date, ym, Close, ADV20, K200, KQ150,
                    AdminStock, TradingHalt, UnfaithfulDisc)]
setkey(month_panel, Ticker, Date)
month_panel[, fwd_ret := (shift(Close, type = "lead") / Close) - 1, by = Ticker]
month_panel[, sig_date := Date]
month_panel[, in_uni := (K200 == 1 | KQ150 == 1)]
month_panel[is.na(in_uni), in_uni := FALSE]
month_panel[, liq_ok := !is.na(ADV20) & ADV20 >= LIQ_THRESHOLD]
month_panel[, healthy := is.na(AdminStock) | AdminStock == 0]
month_panel[is.na(healthy), healthy := TRUE]
month_panel[, eligible := in_uni & liq_ok & healthy]

cat(sprintf("Monthly panel: nrow=%d, eligible=%d (%.1f%%)\n",
            nrow(month_panel), sum(month_panel$eligible),
            100 * mean(month_panel$eligible)))

#=== Regime: 3 definitions =====================================================
cat("\nLoading regime signals (3 definitions)...\n")
regime <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "unified_regime_signal.parquet")))
regime <- regime[, .(ym = YM, Category, MSM_Crisis_Prob, FRED_MRS, KTRI_Score,
                     Regime_Score, Layer1_Alert, Layer2_Alert, Layer3_Alert)]
setkey(regime, ym)

# Lag by 1 month (PIT C5)
regime[, ym_for_apply := shift(ym, type = "lead", n = 1L)]
# Equivalent: at sig_date in month X, use regime info from month X-1
# So regime row for ym=X-1 is applied at sig_date in month X
# i.e. ym_for_apply tells us "this row's signals apply at sig_date in month=ym_for_apply"

# Definition A: Category ∈ {CAUTION, CRISIS, RISK_OFF}
regime[, def_A_bad := Category %in% c("CAUTION", "CRISIS", "RISK_OFF")]

# Definition B: Layer1_Alert == TRUE (MSM crisis prob)
regime[, def_B_bad := Layer1_Alert == TRUE]
regime[is.na(def_B_bad), def_B_bad := FALSE]

# Definition C: MRS percentile (rolling 60m) — to make PIT-safe
# Use expanding median to avoid lookahead
regime[, mrs_expanding_p70 := NA_real_]
for (i in 60:nrow(regime)) {
  regime[i, mrs_expanding_p70 := quantile(regime$FRED_MRS[1:i],
                                          probs = 0.7, na.rm = TRUE)]
}
regime[, def_C_bad := !is.na(FRED_MRS) & !is.na(mrs_expanding_p70) &
                     FRED_MRS >= mrs_expanding_p70]

cat("Bad-state count by definition (full history, n=", nrow(regime), "):\n", sep="")
cat(sprintf("  A (Category {CAUTION,CRISIS,RISK_OFF}): %d (%.1f%%)\n",
            sum(regime$def_A_bad, na.rm=TRUE),
            100*mean(regime$def_A_bad, na.rm=TRUE)))
cat(sprintf("  B (Layer1_Alert TRUE): %d (%.1f%%)\n",
            sum(regime$def_B_bad, na.rm=TRUE),
            100*mean(regime$def_B_bad, na.rm=TRUE)))
cat(sprintf("  C (MRS >= expanding p70): %d (%.1f%%)\n",
            sum(regime$def_C_bad, na.rm=TRUE),
            100*mean(regime$def_C_bad, na.rm=TRUE)))

# Merge to month_panel using ym_for_apply (this is the sig_date month)
regime_apply <- regime[, .(ym_apply = ym_for_apply,
                            def_A_bad, def_B_bad, def_C_bad,
                            FRED_MRS_lag = FRED_MRS,
                            MSM_lag = MSM_Crisis_Prob,
                            Category_lag = Category,
                            Regime_Score_lag = Regime_Score)]
month_panel <- merge(month_panel, regime_apply,
                     by.x = "ym", by.y = "ym_apply", all.x = TRUE)

cat("\nMonthly panel regime distribution (after lagged merge):\n")
cat(sprintf("  def_A_bad: %d / %d (%.1f%%)\n",
            sum(month_panel$def_A_bad, na.rm=TRUE), nrow(month_panel),
            100*mean(month_panel$def_A_bad, na.rm=TRUE)))
cat(sprintf("  def_B_bad: %d / %d (%.1f%%)\n",
            sum(month_panel$def_B_bad, na.rm=TRUE), nrow(month_panel),
            100*mean(month_panel$def_B_bad, na.rm=TRUE)))
cat(sprintf("  def_C_bad: %d / %d (%.1f%%)\n",
            sum(month_panel$def_C_bad, na.rm=TRUE), nrow(month_panel),
            100*mean(month_panel$def_C_bad, na.rm=TRUE)))

#=== STEP 3: Signal Engineering (Z-scores via Factor DB) ======================
cat("\n==== STEP 3: Signal Engineering ====\n")
months_seq <- sort(unique(month_panel$Date))
months_seq <- months_seq[months_seq >= START_DATE & months_seq <= END_DATE]
cat(sprintf("Sig dates: %d (from %s to %s)\n",
            length(months_seq), min(months_seq), max(months_seq)))

n_workers <- min(8L, parallel::detectCores() - 1L)
cat(sprintf("Loading factors (parallel %d workers)...\n", n_workers))
plan(multisession, workers = n_workers)

all_factor_data <- future_lapply(months_seq, function(sd) {
  tryCatch({
    suppressMessages({library(data.table); library(arrow); library(jsonlite)})
    PROJ_LOCAL <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
    source(file.path(PROJ_LOCAL, "02_Infrastructure", "factor_db", "factor_db_connector.R"))
    fdt <- load_month_factors(as.Date(sd), coverage_min = 0.3)
    fdt <- fdt[Factor_Name %in% ALL_FACTORS]
    fdt[, sig_date := as.Date(sd)]
    fdt[]
  }, error = function(e) NULL)
}, future.globals = c("ALL_FACTORS"))
plan(sequential)

factor_long <- rbindlist(all_factor_data, use.names = TRUE, fill = TRUE)
factor_wide <- dcast(factor_long, sig_date + Ticker ~ Factor_Name,
                     value.var = "Z_Score_Aligned")
cat(sprintf("Factor wide: %d rows × %d cols\n", nrow(factor_wide), ncol(factor_wide)))

month_panel[, sig_date := Date]
panel <- merge(month_panel[, .(sig_date, Ticker, ym, fwd_ret, eligible,
                                def_A_bad, def_B_bad, def_C_bad,
                                FRED_MRS_lag, MSM_lag, Category_lag, Regime_Score_lag)],
               factor_wide, by = c("sig_date", "Ticker"), all.x = TRUE)
setkey(panel, sig_date, Ticker)

analysis_panel <- panel[eligible == TRUE & !is.na(fwd_ret)]
cat(sprintf("Analysis panel after eligibility: %d rows (%d unique sig_dates)\n",
            nrow(analysis_panel), length(unique(analysis_panel$sig_date))))

# Winsorize 3-std per sig_date
winsor_panel <- copy(analysis_panel)
for (f in ALL_FACTORS) {
  if (f %in% colnames(winsor_panel)) {
    winsor_panel[, (f) := pmin(pmax(get(f), -3), 3)]
  }
}

#=== STEP 4: Diagnostics with all 3 regime definitions ========================
cat("\n==== STEP 4: Signal Diagnostics ====\n")

compute_ic <- function(dt, factor_col) {
  if (!factor_col %in% colnames(dt)) return(NULL)
  dt[, .(
    n = sum(!is.na(get(factor_col)) & !is.na(fwd_ret)),
    ic = if (sum(!is.na(get(factor_col)) & !is.na(fwd_ret)) >= 30) {
      cor(get(factor_col), fwd_ret, method = "spearman", use = "pairwise.complete.obs")
    } else { NA_real_ }
  ), by = sig_date][!is.na(ic)]
}

compute_monotonicity <- function(dt, factor_col, n_bins = 10) {
  if (!factor_col %in% colnames(dt)) return(NA_real_)
  dt2 <- dt[!is.na(get(factor_col)) & !is.na(fwd_ret)]
  dt2[, bin := cut(get(factor_col),
                   breaks = quantile(get(factor_col), probs = seq(0, 1, length.out = n_bins + 1),
                                     na.rm = TRUE),
                   include.lowest = TRUE, labels = FALSE), by = sig_date]
  bin_means <- dt2[, .(mean_ret = mean(fwd_ret, na.rm = TRUE)), by = bin][order(bin)]
  if (nrow(bin_means) < n_bins) return(NA_real_)
  cor(bin_means$bin, bin_means$mean_ret, method = "spearman")
}

subperiod_stability <- function(ic_dt) {
  ic_dt[, subp := fcase(
    sig_date < as.Date("2014-01-01"), "P1_2008-2013",
    sig_date < as.Date("2020-01-01"), "P2_2014-2019",
    default = "P3_2020-2026"
  )]
  by_sub <- ic_dt[, .(ic_mean = mean(ic, na.rm = TRUE), n = .N), by = subp]
  pos_count <- sum(by_sub$ic_mean > 0, na.rm = TRUE)
  pos_count / nrow(by_sub)
}

# NW-t computation
nw_t_stat <- function(ic_vec, lag = 3) {
  m <- length(ic_vec)
  if (m < 5) return(NA_real_)
  mu <- mean(ic_vec, na.rm = TRUE)
  ic_vec <- ic_vec[!is.na(ic_vec)]
  m <- length(ic_vec)
  v0 <- mean((ic_vec - mu)^2)
  bw <- min(lag, floor(m/4))
  if (bw >= 1) {
    s <- 0
    for (l in 1:bw) {
      w_l <- 1 - l / (bw + 1)
      cov_l <- mean((ic_vec[1:(m - l)] - mu) * (ic_vec[(l + 1):m] - mu))
      s <- s + 2 * w_l * cov_l
    }
    nw_var <- v0 + s
  } else { nw_var <- v0 }
  nw_se <- sqrt(max(nw_var, 1e-12) / m)
  mu / nw_se
}

# Per-factor diagnostics across all 3 definitions
diag_full <- list()
for (f in ALL_FACTORS) {
  if (!f %in% colnames(winsor_panel)) next
  ic_dt <- compute_ic(winsor_panel, f)
  if (is.null(ic_dt) || nrow(ic_dt) < 24) next

  # Add bad-state markers per definition
  bad_dates_A <- unique(winsor_panel[def_A_bad == TRUE, sig_date])
  bad_dates_B <- unique(winsor_panel[def_B_bad == TRUE, sig_date])
  bad_dates_C <- unique(winsor_panel[def_C_bad == TRUE, sig_date])
  ic_dt[, bad_A := sig_date %in% bad_dates_A]
  ic_dt[, bad_B := sig_date %in% bad_dates_B]
  ic_dt[, bad_C := sig_date %in% bad_dates_C]

  # Stats
  ic_mean <- mean(ic_dt$ic, na.rm = TRUE)
  ic_std <- sd(ic_dt$ic, na.rm = TRUE)
  icir <- ic_mean / ic_std
  nw_t <- nw_t_stat(ic_dt$ic)
  mono <- compute_monotonicity(winsor_panel, f)
  sub_stab <- subperiod_stability(ic_dt)

  diag_full[[f]] <- list(
    factor = f,
    rank_ic = round(ic_mean, 4),
    ic_std = round(ic_std, 4),
    icir = round(icir, 4),
    nw_t = round(nw_t, 4),
    n_periods = nrow(ic_dt),
    monotonicity = round(mono, 4),
    subperiod_stability = round(sub_stab, 4),
    # Definition A
    ic_bad_A = round(ic_dt[bad_A == TRUE, mean(ic, na.rm=TRUE)], 4),
    ic_norm_A = round(ic_dt[bad_A == FALSE, mean(ic, na.rm=TRUE)], 4),
    nw_t_bad_A = round(nw_t_stat(ic_dt[bad_A == TRUE, ic]), 4),
    n_bad_A = ic_dt[bad_A == TRUE, .N],
    # Definition B
    ic_bad_B = round(ic_dt[bad_B == TRUE, mean(ic, na.rm=TRUE)], 4),
    ic_norm_B = round(ic_dt[bad_B == FALSE, mean(ic, na.rm=TRUE)], 4),
    nw_t_bad_B = round(nw_t_stat(ic_dt[bad_B == TRUE, ic]), 4),
    n_bad_B = ic_dt[bad_B == TRUE, .N],
    # Definition C
    ic_bad_C = round(ic_dt[bad_C == TRUE, mean(ic, na.rm=TRUE)], 4),
    ic_norm_C = round(ic_dt[bad_C == FALSE, mean(ic, na.rm=TRUE)], 4),
    nw_t_bad_C = round(nw_t_stat(ic_dt[bad_C == TRUE, ic]), 4),
    n_bad_C = ic_dt[bad_C == TRUE, .N]
  )
  cat(sprintf("\n%s: IC=%.4f ICIR=%.3f NW_t=%.2f Mono=%.2f SubStab=%.2f\n",
              f, ic_mean, icir, nw_t, mono, sub_stab))
  cat(sprintf("  Def A: ic_bad=%.4f norm=%.4f nw_t_bad=%.2f n_bad=%d\n",
              diag_full[[f]]$ic_bad_A, diag_full[[f]]$ic_norm_A,
              diag_full[[f]]$nw_t_bad_A, diag_full[[f]]$n_bad_A))
  cat(sprintf("  Def B: ic_bad=%.4f norm=%.4f nw_t_bad=%.2f n_bad=%d\n",
              diag_full[[f]]$ic_bad_B, diag_full[[f]]$ic_norm_B,
              diag_full[[f]]$nw_t_bad_B, diag_full[[f]]$n_bad_B))
  cat(sprintf("  Def C: ic_bad=%.4f norm=%.4f nw_t_bad=%.2f n_bad=%d\n",
              diag_full[[f]]$ic_bad_C, diag_full[[f]]$ic_norm_C,
              diag_full[[f]]$nw_t_bad_C, diag_full[[f]]$n_bad_C))
}

# Save full diagnostics
diag_dt <- rbindlist(lapply(diag_full, function(x) as.data.table(x)), fill = TRUE)
fwrite(diag_dt, file.path(SA_DIR, "per_factor_diagnostics_v2.csv"))

#=== Honest evaluation: which definition gives positive bad-state IC for primary factors? ====
cat("\n==== AX-001 v2 4-axis Defense Evaluation ====\n")
cat("Primary Quality factors per definition (positive ic_bad with sufficient n):\n\n")

definitions <- c("A", "B", "C")
def_stats <- list()
for (def in definitions) {
  cat(sprintf("Definition %s:\n", def))
  pass_count <- 0
  for (f in PRIMARY_FACTORS) {
    if (!f %in% names(diag_full)) next
    d <- diag_full[[f]]
    ic_bad <- d[[paste0("ic_bad_", def)]]
    ic_norm <- d[[paste0("ic_norm_", def)]]
    nw_t_bad <- d[[paste0("nw_t_bad_", def)]]
    n_bad <- d[[paste0("n_bad_", def)]]
    pass <- !is.na(ic_bad) && ic_bad > 0 && n_bad >= 8
    cat(sprintf("  %s: ic_bad=%.4f norm=%.4f n_bad=%d nw_t_bad=%.2f → %s\n",
                f, ic_bad, ic_norm, n_bad, nw_t_bad,
                ifelse(pass, "PASS", "FAIL")))
    if (pass) pass_count <- pass_count + 1
  }
  def_stats[[def]] <- pass_count
  cat(sprintf("  TOTAL pass: %d / %d primary factors\n\n", pass_count, length(PRIMARY_FACTORS)))
}

best_def <- names(which.max(unlist(def_stats)))
cat(sprintf("Best definition: %s (%d primary factors PASS)\n",
            best_def, def_stats[[best_def]]))

#=== Save state for next-step finalization (v3 if any) =========================
saveRDS(list(
  diag_full = diag_full,
  def_stats = def_stats,
  best_def = best_def,
  PRIMARY_FACTORS = PRIMARY_FACTORS,
  AUX_FACTORS = AUX_FACTORS,
  ALL_FACTORS = ALL_FACTORS,
  winsor_panel = winsor_panel,
  panel = panel,
  months_seq = months_seq
), file.path(SA_DIR, "alpha_pipeline_v2_state.rds"))

cat("\n==== v2 diagnostics complete. State saved. ====\n")
cat(sprintf("Outputs in: %s\n", SA_DIR))
