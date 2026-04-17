#==============================================================================
# G12 Fix: Regenerate factor_engine.R for all 20 strategies
# Uses direct construction instead of template substitution
#==============================================================================
cat("[G12 Fix] Regenerating factor_engine.R files...\n")

PROJECT_ROOT <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  dirname(dirname(d))
}, error = function(e) getwd())

strat_dir <- file.path(PROJECT_ROOT, "research_output", "strategies")

strategies <- data.frame(
  id   = 353:372,
  name = c("zombie_gate","roic_gate","gpa_gate","icr_gate","sgr_gate",
           "operating_roa_gate","ocf_growth_gate","ebitda_growth_gate",
           "equity_mult_gate","quickratio_gate","opm_gate","sga_eff_gate",
           "fixed_at_gate","equity_turn_gate","borrow_dep_gate",
           "delta_roe_gate","delta_gpa_gate","ocf_to_ni_gate",
           "fcf_to_assets_gate","cogs_rev_gate"),
  ind  = c("IsZombie","ROIC","GPA","ICR","SGR",
           "OperatingROA","OCFGrowth","EBITDAGrowth",
           "EquityMultiplier","QuickRatio","OPM","SGAEfficiency",
           "FixedAssetTurnover","EquityTurnover","BorrowingDependency",
           "Delta_ROE","Delta_GPA","OCFToNI",
           "FCFToAssets","COGSToRevenue"),
  gate = c("flag","bottom","bottom","bottom","bottom",
           "bottom","bottom","bottom",
           "top","bottom","bottom","top",
           "bottom","bottom","top",
           "bottom","bottom","bottom",
           "bottom","top"),
  q    = c(NA, 0.10, 0.10, 0.10, 0.10,
           0.10, 0.10, 0.10,
           0.90, 0.10, 0.10, 0.90,
           0.10, 0.10, 0.90,
           0.10, 0.10, 0.10,
           0.10, 0.90),
  desc = c("Zombie company exclusion (persistent ICR<1)",
           "Low ROIC exclusion (Greenblatt)",
           "Low Gross Profitability/Assets (Novy-Marx 2013)",
           "Low Interest Coverage Ratio (distress risk)",
           "Low Sustainable Growth Rate",
           "Low Operating ROA",
           "Low OCF Growth (deteriorating cash flow)",
           "Low EBITDA Growth (declining earnings)",
           "High Equity Multiplier (over-leverage, DuPont)",
           "Low Quick Ratio (illiquidity risk)",
           "Low Operating Profit Margin",
           "High SGA/Revenue ratio (cost inefficiency)",
           "Low Fixed Asset Turnover (poor capital use)",
           "Low Equity Turnover (poor capital efficiency)",
           "High Borrowing Dependency",
           "Declining ROE (deteriorating profitability)",
           "Declining GPA (deteriorating quality)",
           "Low OCF/NI ratio (poor cash conversion)",
           "Low FCF/Assets (poor FCF yield)",
           "High COGS/Revenue ratio (low margin)"),
  stringsAsFactors = FALSE
)

# Build gate code block for each strategy
build_gate <- function(ind, gate, q) {
  if (gate == "flag") {
    return(paste0(
      '  # -- ', ind, ' FLAG EXCLUSION --\n',
      '  n_before <- nrow(stats)\n',
      '  if (HAS_DART) {\n',
      '    avail_dates <- sort(unique(FUND_DT$Factor_Date))\n',
      '    valid_dates <- avail_dates[avail_dates <= sig_d]\n',
      '    if (length(valid_dates) > 0) {\n',
      '      latest_fd <- max(valid_dates)\n',
      '      fund_snap <- FUND_DT[Factor_Date == latest_fd, .(Ticker, ', ind, ')]\n',
      '      stats <- merge(stats, fund_snap, by = "Ticker", all.x = TRUE)\n',
      '      n_with <- sum(!is.na(stats$', ind, '))\n',
      '      if (n_with > 50) {\n',
      '        stats <- stats[is.na(', ind, ') | ', ind, ' != TRUE]\n',
      '        n_excluded <- n_excluded + (n_before - nrow(stats))\n',
      '      }\n',
      '    }\n',
      '  }\n'
    ))
  } else if (gate == "bottom") {
    return(paste0(
      '  # -- ', ind, ' BOTTOM ', round(q * 100), '% EXCLUSION --\n',
      '  n_before <- nrow(stats)\n',
      '  if (HAS_DART) {\n',
      '    avail_dates <- sort(unique(FUND_DT$Factor_Date))\n',
      '    valid_dates <- avail_dates[avail_dates <= sig_d]\n',
      '    if (length(valid_dates) > 0) {\n',
      '      latest_fd <- max(valid_dates)\n',
      '      fund_snap <- FUND_DT[Factor_Date == latest_fd & !is.na(', ind, '), .(Ticker, ', ind, ')]\n',
      '      stats <- merge(stats, fund_snap, by = "Ticker", all.x = TRUE)\n',
      '      n_with <- sum(!is.na(stats$', ind, '))\n',
      '      if (n_with > 50) {\n',
      '        gate_thresh <- quantile(stats$', ind, '[!is.na(stats$', ind, ')], GATE_EXCLUDE_Q)\n',
      '        stats <- stats[is.na(', ind, ') | ', ind, ' >= gate_thresh]\n',
      '        n_excluded <- n_excluded + (n_before - nrow(stats))\n',
      '      }\n',
      '    }\n',
      '  }\n'
    ))
  } else {  # top
    return(paste0(
      '  # -- ', ind, ' TOP ', round((1 - q) * 100), '% EXCLUSION --\n',
      '  n_before <- nrow(stats)\n',
      '  if (HAS_DART) {\n',
      '    avail_dates <- sort(unique(FUND_DT$Factor_Date))\n',
      '    valid_dates <- avail_dates[avail_dates <= sig_d]\n',
      '    if (length(valid_dates) > 0) {\n',
      '      latest_fd <- max(valid_dates)\n',
      '      fund_snap <- FUND_DT[Factor_Date == latest_fd & !is.na(', ind, '), .(Ticker, ', ind, ')]\n',
      '      stats <- merge(stats, fund_snap, by = "Ticker", all.x = TRUE)\n',
      '      n_with <- sum(!is.na(stats$', ind, '))\n',
      '      if (n_with > 50) {\n',
      '        gate_thresh <- quantile(stats$', ind, '[!is.na(stats$', ind, ')], GATE_EXCLUDE_Q)\n',
      '        stats <- stats[is.na(', ind, ') | ', ind, ' <= gate_thresh]\n',
      '        n_excluded <- n_excluded + (n_before - nrow(stats))\n',
      '      }\n',
      '    }\n',
      '  }\n'
    ))
  }
}

for (i in seq_len(nrow(strategies))) {
  s <- strategies[i, ]
  str_id <- paste0("STR_", sprintf("%03d", s$id))
  g12_num <- paste0("G12-", sprintf("%03d", s$id - 352))
  dir_path <- file.path(strat_dir, paste0(str_id, "_", s$name))

  if (s$gate == "flag") {
    gate_param <- paste0(toupper(s$ind), "_EXCLUDE <- TRUE")
  } else {
    gate_param <- paste0("GATE_EXCLUDE_Q  <- ", s$q, "   # ",
                         ifelse(s$gate == "bottom",
                                paste0("Remove bottom ", round(s$q * 100), "% ", s$ind),
                                paste0("Remove top ", round((1 - s$q) * 100), "% ", s$ind)))
  }

  gate_block <- build_gate(s$ind, s$gate, s$q)

  fe_code <- paste0(
'#==============================================================================
# ', str_id, ': ', s$ind, ' Exclusion (Quarterly 0.5/0.5)
# ', g12_num, ': ', s$desc, '
#==============================================================================
cat("[factor_engine] ', str_id, ': ', s$ind, ' Exclusion (', g12_num, ')...\\n")
set.seed(42)

LOOKBACK           <- 252L
MIN_OBS            <- 200L
VOL_FLOOR_Q        <- 0.05
REGIME_SCALE_SOFT  <- 0.5
MACRO_HARD_THRESH <- if(exists("MACRO_HARD_THRESH")) MACRO_HARD_THRESH else 40L
BUDDHA_CASH_OUT    <- TRUE
', gate_param, '

IVOL_WEIGHT <- 0.5
BETA_WEIGHT <- 0.5

DART_FACTOR_CACHE <- file.path(CACHE_DIR, "fundamental_dart.parquet")
HAS_DART <- file.exists(DART_FACTOR_CACHE)
if (HAS_DART) {
  FUND_DT <- as.data.table(read_parquet(DART_FACTOR_CACHE))
  setnames(FUND_DT, "bsns_year", "biz_year", skip_absent = TRUE)
  FUND_DT[, Factor_Date := as.Date(Factor_Date)]
  cat(sprintf("[factor_engine] DART loaded: %d rows, %d tickers\\n",
              nrow(FUND_DT), uniqueN(FUND_DT$Ticker)))
}

macro_regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
macro_regime_dt[, YM := substr(Date, 1, 7)]
setkey(macro_regime_dt, YM)

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]
all_signal_dates[, Month := as.integer(substr(YM, 6, 7))]
quarterly_dates <- all_signal_dates[Month %in% c(3, 6, 9, 12)]$Signal_Date
quarterly_dates <- sort(quarterly_dates)

all_dates <- sort(unique(RAWDATA$Date))
min_start <- all_dates[min(LOOKBACK + 1L, length(all_dates))]
quarterly_dates <- quarterly_dates[quarterly_dates >= min_start]

bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)])
setorder(bm_daily, Date)

factor_list <- list()
n_done <- 0L; n_skipped <- 0L; n_excluded <- 0L

for (sig_d in quarterly_dates) {
  sig_d <- as.Date(sig_d)
  sig_ym <- format(sig_d, "%Y-%m")
  idx <- which(all_dates == sig_d)

  macro_row <- macro_regime_dt[YM == sig_ym]
  buddha_mode <- if (nrow(macro_row) > 0 && !is.na(macro_row$Buddha_Mode[1]))
    macro_row$Buddha_Mode[1] else FALSE
  risk_score <- if (nrow(macro_row) > 0 && !is.na(macro_row$Macro_Risk_Score[1]))
    macro_row$Macro_Risk_Score[1] else 0
  vix_regime <- if (nrow(macro_row) > 0 && !is.na(macro_row$VIX_Regime[1]))
    macro_row$VIX_Regime[1] else "normal"

  hard_cashout <- (BUDDHA_CASH_OUT && buddha_mode) ||
                  (risk_score >= MACRO_HARD_THRESH) ||
                  (vix_regime %in% c("extreme", "crisis"))

  if (hard_cashout) { n_skipped <- n_skipped + 1L; next }

  regime_scale <- if (risk_score >= (if(exists("REGIME_SOFT_THRESH")) REGIME_SOFT_THRESH else 10L)) REGIME_SCALE_SOFT else 1.0

  lb_start <- all_dates[max(1, idx - LOOKBACK)]
  window <- RAWDATA[Date >= lb_start & Date <= sig_d]

  stats <- window[!is.na(Ret) & !is.na(Close), {
    n <- .N
    if (n < MIN_OBS) {
      list(idiovol = NA_real_, beta_raw = NA_real_, avg_vol = NA_real_, ret_12m = NA_real_)
    } else {
      bm_w <- bm_daily[Date >= lb_start & Date <= sig_d]
      merged <- merge(data.table(Date = Date, Ret = Ret), bm_w, by = "Date", all.x = TRUE)
      merged <- merged[!is.na(Ret) & !is.na(BM_Ret)]
      if (nrow(merged) < MIN_OBS) {
        list(idiovol = NA_real_, beta_raw = NA_real_,
             avg_vol = mean(tail(Vol, 20), na.rm = TRUE),
             ret_12m = prod(1 + Ret, na.rm = TRUE) - 1)
      } else {
        fit <- .lm.fit(cbind(1, merged$BM_Ret), merged$Ret)
        list(idiovol = sd(fit$residuals), beta_raw = fit$coefficients[2],
             avg_vol = mean(tail(Vol, 20), na.rm = TRUE),
             ret_12m = prod(1 + Ret, na.rm = TRUE) - 1)
      }
    }
  }, by = Ticker]

  stats <- stats[!is.na(idiovol) & !is.na(beta_raw)]
  stats[, vol_rank := frank(avg_vol, ties.method = "average") / .N]
  stats <- stats[vol_rank > VOL_FLOOR_Q & ret_12m > -0.40]

', gate_block, '
  if (nrow(stats) < 30) next

  stats[, beta_shrunk := 0.6 * beta_raw + 0.4 * 1.0]

  .w <- function(x) { q <- quantile(x, c(0.01, 0.99), na.rm = TRUE); pmin(pmax(x, q[1]), q[2]) }
  stats[, idiovol_w := .w(idiovol)]
  stats[, beta_w := .w(beta_shrunk)]
  stats[, z_idiovol := -(idiovol_w - mean(idiovol_w)) / sd(idiovol_w)]
  stats[, z_beta := -(beta_w - mean(beta_w)) / sd(beta_w)]
  stats[, score_raw := z_idiovol * IVOL_WEIGHT + z_beta * BETA_WEIGHT]

  sector_info <- unique(RAWDATA[Date == sig_d, .(Ticker, Sector)])
  stats <- merge(stats, sector_info, by = "Ticker", all.x = TRUE)
  stats[, Score := (score_raw - mean(score_raw, na.rm = TRUE)) * regime_scale, by = Sector]

  stats[, Date := sig_d]
  factor_list[[length(factor_list) + 1]] <- stats[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
  if (n_done %% 10 == 0 || n_done == 1)
    cat(sprintf("  [%d done/%d skipped] %s -- %d tickers, excluded=%d\\n",
                n_done, n_skipped, sig_d, nrow(stats), n_before - nrow(stats)))
}

if (length(factor_list) == 0) stop("[factor_engine] No factor data.")
FACTORS <- rbindlist(factor_list)
setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
cat(sprintf("[factor_engine] FACTORS: %d rows | %d dates | %d skipped | ', s$ind, '_excl=%d\\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped, n_excluded))
')

  writeLines(fe_code, file.path(dir_path, "factor_engine.R"))
  cat(sprintf("  Fixed: %s\n", paste0(str_id, "_", s$name)))
}

cat("[G12 Fix] All 20 factor_engine.R files regenerated.\n")
