cat("=== Batch S2 ICIR Computation for STR_1619/1620/1621/1622 ===\n")
## S2 프로파일 ICIR 계산 — Alpha Lab Gate (§8) 충족 검증

options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

INFRA_DIR  <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")
STRAT_BASE <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "research_output/strategies")

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(arrow)
})

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))

# Load RAWDATA once
cat("Loading RAWDATA...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

# Forward 1-month returns by ticker
cat("Computing forward returns...\n")
month_ret <- RAWDATA[, .(Date, Ticker, Ret)]
month_dates <- sort(unique(month_ret$Date))

# Monthly return: sum daily returns within each month
month_ret[, YM := format(Date, "%Y-%m")]
monthly <- month_ret[, .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = .(YM, Ticker)]
monthly[, YM_lag := shift(YM, -1, type = "lead"), by = Ticker]

strategies <- list(
  list(id = "STR_1619", dir = "STR_1619_defense_coskew_kurtosis_blend",
       fid = "D16_Coskewness+D44_Kurtosis+D60_Leverage", role = "RoleBias_Defense"),
  list(id = "STR_1620", dir = "STR_1620_quality_momentum_diversifier",
       fid = "Q01_GPA+M25_Earnings_Mom_Streak+TR02_Trend_Consistency", role = "RoleBias_Diversifier"),
  list(id = "STR_1621", dir = "STR_1621_regime_conditional_allweather",
       fid = "C19_FY1_Revision_1m+V14_EBIT_EV+D01_Low_Vol+D44_Kurtosis", role = "RoleBias_Core"),
  list(id = "STR_1622", dir = "STR_1622_ic_weighted_statistical_blend",
       fid = "C19+V14+Q01+D01+M25_IC_Weighted", role = "RoleBias_Core")
)

results <- list()

for (strat in strategies) {
  cat(sprintf("\n--- %s: %s ---\n", strat$id, strat$fid))
  strat_dir <- file.path(STRAT_BASE, strat$dir)

  tryCatch({
    # Fresh environment for factor_engine
    RAWDATA_ORIG <- copy(RAWDATA)
    FACTOR_REG_PATH <<- file.path(INFRA_DIR, "factor_db", "factor_registry.json")
    source(file.path(strat_dir, "factor_engine.R"), local = FALSE)
    FACTOR_REG_PATH <<- file.path(INFRA_DIR, "factor_db", "factor_registry.json")

    if (!exists("FACTORS") || is.null(FACTORS) || nrow(FACTORS) == 0) {
      cat("  SKIP: FACTORS not generated\n")
      next
    }

    # Monthly scores: last date per month
    fdt <- copy(FACTORS)[, YM := format(Date, "%Y-%m")]
    monthly_scores <- fdt[, .SD[Date == max(Date)], by = YM][, .(YM, Ticker, Score)]

    # Merge with forward returns (next month)
    monthly_fwd <- monthly[, .(Ticker, YM, fwd_ret)]
    merged <- merge(monthly_scores, monthly_fwd, by = c("YM", "Ticker"), all.x = TRUE)
    merged <- merged[!is.na(Score) & !is.na(fwd_ret)]

    # Compute rank IC per month (Spearman correlation)
    ic_by_month <- merged[, {
      if (.N >= 10) {
        list(ic = cor(Score, fwd_ret, method = "spearman", use = "complete.obs"))
      } else {
        list(ic = NA_real_)
      }
    }, by = YM]
    ic_by_month <- ic_by_month[!is.na(ic)]

    if (nrow(ic_by_month) < 12) {
      cat(sprintf("  SKIP: Only %d months of IC data\n", nrow(ic_by_month)))
      next
    }

    ic_mean <- mean(ic_by_month$ic, na.rm = TRUE)
    ic_sd   <- sd(ic_by_month$ic, na.rm = TRUE)
    icir    <- if (ic_sd > 0) ic_mean / ic_sd else NA_real_
    n_months <- nrow(ic_by_month)

    # 5Y subset
    recent_5y <- ic_by_month[YM >= format(Sys.Date() - 1825, "%Y-%m")]
    icir_5y <- if (nrow(recent_5y) >= 12 && sd(recent_5y$ic, na.rm = TRUE) > 0) {
      mean(recent_5y$ic, na.rm = TRUE) / sd(recent_5y$ic, na.rm = TRUE)
    } else NA_real_

    # t-stat for IC significance
    t_stat <- if (ic_sd > 0) ic_mean / (ic_sd / sqrt(n_months)) else NA_real_

    cat(sprintf("  IC mean: %.4f | IC sd: %.4f\n", ic_mean, ic_sd))
    cat(sprintf("  ICIR (full): %.4f | ICIR (5Y): %.4f | t-stat: %.2f\n", icir, icir_5y, t_stat))
    cat(sprintf("  n_months: %d | Alpha Lab Gate: %s\n", n_months,
                if (!is.na(icir) && icir >= 0.20) "PASS" else "REVIEW"))

    # Update S2 profile
    s2_files <- list.files(file.path(strat_dir, "stage_artifacts"),
                           pattern = "^s2_profile_", full.names = TRUE)
    if (length(s2_files) > 0) {
      s2 <- fromJSON(s2_files[1])
      s2$ic_ir    <- round(icir, 4)
      s2$t_stat   <- round(t_stat, 2)
      s2$ic_mean  <- round(ic_mean, 4)
      s2$ic_sd    <- round(ic_sd, 4)
      s2$icir_5y  <- round(icir_5y, 4)
      s2$n_ic_months <- n_months
      s2$role_bias <- strat$role
      s2$alpha_lab_gate <- if (!is.na(icir) && icir >= 0.20) "PASS" else "REVIEW"
      write_json(s2, s2_files[1], auto_unbox = TRUE, pretty = TRUE)
      cat(sprintf("  S2 profile updated: %s\n", basename(s2_files[1])))
    }

    results[[strat$id]] <- list(
      icir = icir, icir_5y = icir_5y, t_stat = t_stat,
      ic_mean = ic_mean, n_months = n_months, role = strat$role
    )

  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n", conditionMessage(e)))
  })
}

# Summary
cat("\n\n=== S2 ICIR Summary ===\n")
cat(sprintf("%-12s  %-7s  %-8s  %-8s  %-6s  %s\n",
            "Strategy", "ICIR", "ICIR_5Y", "t_stat", "Gate", "Role"))
cat(strrep("-", 70), "\n")
for (sid in names(results)) {
  r <- results[[sid]]
  gate <- if (!is.na(r$icir) && r$icir >= 0.20) "PASS" else "REVIEW"
  cat(sprintf("%-12s  %7.4f  %8.4f  %8.2f  %-6s  %s\n",
              sid, r$icir, r$icir_5y, r$t_stat, gate, r$role))
}
cat("\nDone.\n")
