#==============================================================================
# G12 Batch Generator: 20 Untested DART Indicator Exclusion Gates
# STR_353 ~ STR_372
# Template: STR_311 (ROE Bottom 10% Exclusion, Quarterly IVol0.5+Beta0.5)
#==============================================================================
cat("[G12 Generator] Creating 20 strategy directories...\n")

PROJECT_ROOT <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  dirname(dirname(d))
}, error = function(e) getwd())

strat_dir <- file.path(PROJECT_ROOT, "research_output", "strategies")

# Read STR_311 template files as base
template_fe <- readLines(file.path(strat_dir, "STR_311_roe_gate", "factor_engine.R"))
template_run <- readLines(file.path(strat_dir, "STR_311_roe_gate", "run_all.R"))

# Define the 20 strategies
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

for (i in seq_len(nrow(strategies))) {
  s <- strategies[i, ]
  str_id <- sprintf("STR_%03d", s$id)
  g12_num <- sprintf("G12-%03d", s$id - 352)
  dir_name <- paste0(str_id, "_", s$name)
  dir_path <- file.path(strat_dir, dir_name)
  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)

  # ── Build factor_engine.R ──
  # Generate the gate section
  if (s$gate == "flag") {
    gate_param_line <- paste0(toupper(s$ind), "_EXCLUDE  <- TRUE")
    gate_code <- c(
      paste0("  # ── ", s$ind, " FLAG EXCLUSION ──"),
      "  n_before <- nrow(stats)",
      "  if (HAS_DART) {",
      "    avail_dates <- sort(unique(FUND_DT$Factor_Date))",
      "    valid_dates <- avail_dates[avail_dates <= sig_d]",
      "    if (length(valid_dates) > 0) {",
      "      latest_fd <- max(valid_dates)",
      paste0("      fund_snap <- FUND_DT[Factor_Date == latest_fd, .(Ticker, ", s$ind, ")]"),
      paste0("      stats <- merge(stats, fund_snap, by = \"Ticker\", all.x = TRUE)"),
      paste0("      n_with <- sum(!is.na(stats$", s$ind, "))"),
      "      if (n_with > 50) {",
      paste0("        stats <- stats[is.na(", s$ind, ") | ", s$ind, " != TRUE]"),
      "        n_excluded <- n_excluded + (n_before - nrow(stats))",
      "      }",
      "    }",
      "  }"
    )
  } else if (s$gate == "bottom") {
    gate_param_line <- paste0("GATE_EXCLUDE_Q  <- ", s$q, "   # Remove bottom ", round(s$q*100), "% ", s$ind)
    gate_code <- c(
      paste0("  # ── ", s$ind, " BOTTOM ", round(s$q*100), "% EXCLUSION ──"),
      "  n_before <- nrow(stats)",
      "  if (HAS_DART) {",
      "    avail_dates <- sort(unique(FUND_DT$Factor_Date))",
      "    valid_dates <- avail_dates[avail_dates <= sig_d]",
      "    if (length(valid_dates) > 0) {",
      "      latest_fd <- max(valid_dates)",
      paste0("      fund_snap <- FUND_DT[Factor_Date == latest_fd & !is.na(", s$ind, "), .(Ticker, ", s$ind, ")]"),
      "      stats <- merge(stats, fund_snap, by = \"Ticker\", all.x = TRUE)",
      paste0("      n_with <- sum(!is.na(stats$", s$ind, "))"),
      "      if (n_with > 50) {",
      paste0("        threshold <- quantile(stats$", s$ind, "[!is.na(stats$", s$ind, ")], GATE_EXCLUDE_Q)"),
      paste0("        stats <- stats[is.na(", s$ind, ") | ", s$ind, " >= threshold]"),
      "        n_excluded <- n_excluded + (n_before - nrow(stats))",
      "      }",
      "    }",
      "  }"
    )
  } else {  # top
    top_pct <- round((1 - s$q) * 100)
    gate_param_line <- paste0("GATE_EXCLUDE_Q  <- ", s$q, "   # Remove top ", top_pct, "% ", s$ind)
    gate_code <- c(
      paste0("  # ── ", s$ind, " TOP ", top_pct, "% EXCLUSION ──"),
      "  n_before <- nrow(stats)",
      "  if (HAS_DART) {",
      "    avail_dates <- sort(unique(FUND_DT$Factor_Date))",
      "    valid_dates <- avail_dates[avail_dates <= sig_d]",
      "    if (length(valid_dates) > 0) {",
      "      latest_fd <- max(valid_dates)",
      paste0("      fund_snap <- FUND_DT[Factor_Date == latest_fd & !is.na(", s$ind, "), .(Ticker, ", s$ind, ")]"),
      "      stats <- merge(stats, fund_snap, by = \"Ticker\", all.x = TRUE)",
      paste0("      n_with <- sum(!is.na(stats$", s$ind, "))"),
      "      if (n_with > 50) {",
      paste0("        threshold <- quantile(stats$", s$ind, "[!is.na(stats$", s$ind, ")], GATE_EXCLUDE_Q)"),
      paste0("        stats <- stats[is.na(", s$ind, ") | ", s$ind, " <= threshold]"),
      "        n_excluded <- n_excluded + (n_before - nrow(stats))",
      "      }",
      "    }",
      "  }"
    )
  }

  # Transform template: Replace ROE-specific parts
  fe <- template_fe
  fe <- gsub("STR_311", str_id, fe)
  fe <- gsub("G6-027", g12_num, fe)
  fe <- gsub("ROE Bottom 10% Exclusion", paste0(s$ind, " Exclusion"), fe)
  fe <- gsub("ROE Bottom10% Exclusion", paste0(s$ind, " Exclusion"), fe)
  fe <- gsub("Low ROE = poor capital allocation.*$", s$desc, fe)
  fe <- gsub("Haugen & Baker.*$", s$desc, fe)
  fe <- gsub("ROE = NetIncome.*$", paste0(s$ind, " gate"), fe)

  # Replace parameter line
  fe <- gsub("ROE_EXCLUDE_Q      <- 0.10   # Remove bottom 10% ROE", gate_param_line, fe, fixed = TRUE)

  # Replace gate section (lines 104-120 in original)
  gate_start <- grep("ROE BOTTOM 10% EXCLUSION", fe, fixed = TRUE)
  if (length(gate_start) > 0) {
    # Find the closing brace of the gate section
    gate_end <- gate_start
    brace_depth <- 0
    for (j in gate_start:length(fe)) {
      brace_depth <- brace_depth + nchar(gsub("[^{]", "", fe[j])) - nchar(gsub("[^}]", "", fe[j]))
      if (j > gate_start && brace_depth <= 0) { gate_end <- j; break }
    }
    fe <- c(fe[1:(gate_start - 1)], gate_code, fe[(gate_end + 1):length(fe)])
  }

  # Fix the final log message
  fe <- gsub("ROE_excl", paste0(s$ind, "_excl"), fe)

  writeLines(fe, file.path(dir_path, "factor_engine.R"))

  # ── Build run_all.R ──
  ra <- template_run
  ra <- gsub("STR_311", str_id, ra)
  ra <- gsub("G6-027", g12_num, ra)
  ra <- gsub("ROE Bottom 10% Exclusion", paste0(s$ind, " Exclusion"), ra)
  ra <- gsub("ROE Gate", paste0(s$ind, " Gate"), ra)

  writeLines(ra, file.path(dir_path, "run_all.R"))

  cat(sprintf("  %s: %s (%s %s)\n", dir_name, s$ind, s$gate,
              ifelse(s$gate == "flag", "exclude",
                     paste0(ifelse(s$gate == "top", round((1-s$q)*100), round(s$q*100)), "%"))))
}

cat(sprintf("\n[G12 Generator] Created %d strategy directories (STR_353~372).\n",
            nrow(strategies)))
