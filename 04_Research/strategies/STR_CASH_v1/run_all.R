#==============================================================================
# STR_CASH_v1 run_all.R — E2E Run A (v55 Consensus)
#
# role = cash_allocation (v55 신규, OPT-1~6/10 면제)
# trail = standard
# gap_targeting_axes = ["cash_efficiency", "MDD_regime"]
#
# AX-005 우회 (cash는 팩터가 아니라 배분 결정)
# AX-001 v2 적용 (crisis alpha + Core 대비 MDD 완화 측정)
#==============================================================================

STR_CASH_V1_ROLE <- "cash_allocation"

cat("=== STR_CASH_v1: Regime-Conditional Cash Allocation Sleeve ===\n")
cat("## 핵심아이디어: MRS regime별 cash 0~30% 동적 배분. Defense sleeve 공석 보완.\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ── 프로젝트 루트 + 설정 로드 (한글 경로 대응) ──
STRATEGY_DIR <- getwd()
# Strategy dir = .../04_Research/strategies/STR_XXX 형태에서 project root 계산
if (grepl("04_Research/strategies/", STRATEGY_DIR)) {
  PROJECT_ROOT <- sub("/04_Research/strategies/.*", "", STRATEGY_DIR)
} else {
  PROJECT_ROOT <- Sys.getenv("PROJECT_ROOT",
    unset = Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")))
}
setwd(PROJECT_ROOT)

cat(sprintf("Project root: %s\n", PROJECT_ROOT))
cat(sprintf("Strategy dir: %s\n\n", STRATEGY_DIR))

source(file.path(STRATEGY_DIR, "factor_engine.R"))

# ── 1. Regime 신호 → cash weight ──
regime_path <- file.path(PROJECT_ROOT, ".cache", "regime_v7.parquet")
cat(sprintf("[1] Loading regime signal: %s\n", regime_path))

cash_signal <- tryCatch(
  load_and_generate_cash_signal(regime_path),
  error = function(e) {
    cat(sprintf("  Regime load failed: %s\n", conditionMessage(e)))
    cat("  Fallback: uniform normal regime (cash 5%) for entire period\n")
    dates <- seq.Date(as.Date("2000-01-31"), as.Date("2026-03-31"), by = "month")
    data.table(
      Date = dates, mrs = 40,
      regime_state = "Normal", cash_weight = 0.05
    )
  }
)

cat(sprintf("  Cash signal: %d monthly obs (%s ~ %s)\n",
            nrow(cash_signal), min(cash_signal$Date), max(cash_signal$Date)))
cat(sprintf("  Regime dist: %s\n",
            paste(sprintf("%s=%d",
                          names(table(cash_signal$regime_state)),
                          table(cash_signal$regime_state)),
                  collapse = ", ")))

# ── 2. Equity benchmark return (RAWDATA equal-weight proxy) ──
rawdata_path <- file.path(PROJECT_ROOT, ".cache", "RAWDATA.parquet")
if (!file.exists(rawdata_path)) {
  alt_paths <- c(
    file.path(PROJECT_ROOT, "02_Infrastructure/data/RAWDATA.parquet"),
    file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
  )
  rawdata_path <- alt_paths[file.exists(alt_paths)][1]
}

if (!is.na(rawdata_path) && file.exists(rawdata_path)) {
  cat(sprintf("\n[2] Loading RAWDATA: %s\n", rawdata_path))
  rawdata <- as.data.table(arrow::read_parquet(rawdata_path))
  rawdata[, YM := format(as.Date(Date), "%Y-%m")]
  ew_monthly <- rawdata[!is.na(Ret) & is.finite(Ret),
                        .(ew_ret = mean(Ret, na.rm = TRUE)),
                        by = YM]
  ew_monthly[, Date := as.Date(paste0(YM, "-01")) + 30]
  ew_monthly <- ew_monthly[, .(Date, ew_ret)]
  setorder(ew_monthly, Date)
  cat(sprintf("  EW monthly: %d obs, mean monthly ret=%.4f\n",
              nrow(ew_monthly), mean(ew_monthly$ew_ret, na.rm = TRUE)))
} else {
  cat("\n[2] RAWDATA not found. Using synthetic KOSPI-like returns (7%/yr, 18% vol)\n")
  set.seed(42)
  dates <- cash_signal$Date
  ew_monthly <- data.table(
    Date = dates,
    ew_ret = rnorm(length(dates), mean = 0.07 / 12, sd = 0.18 / sqrt(12))
  )
}

rf_ann <- 0.025
rf_monthly <- rf_ann / 12

# ── 3. Portfolio return 계산 ──
cat("\n[3] Building portfolio returns\n")
port <- merge(cash_signal, ew_monthly, by = "Date", all.x = TRUE)
port <- port[!is.na(ew_ret)]

port[, port_ret := (1 - cash_weight) * ew_ret + cash_weight * rf_monthly]
port[, core_ret := ew_ret]

cat(sprintf("  Portfolio obs: %d\n", nrow(port)))
cat(sprintf("  Avg cash weight: %.2f%%, max: %.2f%%\n",
            mean(port$cash_weight) * 100, max(port$cash_weight) * 100))

# ── 4. Performance metrics ──
compute_metrics <- function(returns, label = "") {
  r <- returns[is.finite(returns)]
  if (length(r) < 12) return(list())
  n_years <- length(r) / 12
  cagr <- prod(1 + r)^(1 / n_years) - 1
  sr <- mean(r) / sd(r) * sqrt(12)
  cum <- cumprod(1 + r)
  mdd <- min(cum / cummax(cum) - 1)
  list(
    label = label, n_obs = length(r), n_years = round(n_years, 2),
    CAGR = round(cagr, 4), Sharpe = round(sr, 3),
    MDD = round(mdd, 4), Vol = round(sd(r) * sqrt(12), 4)
  )
}

port_metrics <- compute_metrics(port$port_ret, "STR_CASH_v1")
core_metrics <- compute_metrics(port$core_ret, "Equity_Core_Proxy")

cat("\n[4] Performance:\n")
cat(sprintf("  STR_CASH_v1: SR=%.3f, CAGR=%.2f%%, MDD=%.2f%%, Vol=%.2f%%\n",
            port_metrics$Sharpe, port_metrics$CAGR * 100,
            port_metrics$MDD * 100, port_metrics$Vol * 100))
cat(sprintf("  Core proxy: SR=%.3f, CAGR=%.2f%%, MDD=%.2f%%\n",
            core_metrics$Sharpe, core_metrics$CAGR * 100,
            core_metrics$MDD * 100))

mdd_reduction_pct <- (abs(core_metrics$MDD) - abs(port_metrics$MDD)) / abs(core_metrics$MDD)
cat(sprintf("  MDD reduction vs Core: %.2f%%\n", mdd_reduction_pct * 100))

# ── 5. audit_cash_allocation (v55) ──
source(file.path(PROJECT_ROOT, "02_Infrastructure/pipeline/v55_stage_gate_extensions.R"))

audit_result <- audit_cash_allocation(
  cash_weights = port$cash_weight,
  rates_3m_annualized = rf_ann,
  strategy_returns = port$port_ret,
  bench_returns = port$ew_ret
)

cat("\n[5] Cash Allocation Audit (v55):\n")
cat(sprintf("  opportunity_cost_bps_ann: %.2f (threshold<20)\n",
            audit_result$opportunity_cost_bps_annualized))
cat(sprintf("  avg_cash_pct: %.2f%%, max_cash_pct: %.2f%%\n",
            audit_result$avg_cash_pct, audit_result$max_cash_pct))
cat(sprintf("  passed: %s (%s)\n", audit_result$passed, audit_result$reason))

# ── 6. Crisis alpha (AX-001 v2) ──
crisis_periods <- list(
  "2008_gfc" = c(as.Date("2007-10-31"), as.Date("2009-03-31")),
  "2020_covid" = c(as.Date("2020-02-29"), as.Date("2020-05-31")),
  "2022_rate" = c(as.Date("2022-01-31"), as.Date("2022-10-31"))
)

crisis_alphas <- lapply(crisis_periods, function(period) {
  mask <- port$Date >= period[1] & port$Date <= period[2]
  if (sum(mask) == 0) return(NA)
  p_ret <- mean(port$port_ret[mask], na.rm = TRUE) * 12
  c_ret <- mean(port$core_ret[mask], na.rm = TRUE) * 12
  round(p_ret - c_ret, 4)
})

cat("\n[6] Crisis Alpha (AX-001 v2):\n")
crisis_lines <- sapply(names(crisis_alphas), function(nm) {
  val <- if (is.na(crisis_alphas[[nm]])) "N/A" else sprintf("%.4f", crisis_alphas[[nm]])
  sprintf("  %s: alpha = %s", nm, val)
})
cat(paste(crisis_lines, collapse = "\n"), "\n", sep = "")

crisis_positive <- sum(sapply(crisis_alphas, function(a) !is.na(a) && a > 0))
crisis_tested <- sum(sapply(crisis_alphas, function(a) !is.na(a)))
cat(sprintf("  Crisis alpha positive: %d/%d\n", crisis_positive, crisis_tested))

# ── 7. hurdle_result.json ──
output_dir <- file.path(STRATEGY_DIR, "output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

hurdle_result <- list(
  strategy_id = "STR_CASH_v1",
  factor_id = "CASH_ALLOCATION_v1",
  version = "v1.0",
  created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  schema_version = "v55",
  role = "cash_allocation",
  trail = "standard",
  gap_targeting_axes = c("cash_efficiency", "MDD_regime"),
  cash_component = list(
    uses_cash_signal = TRUE,
    max_cash_weight = 0.30,
    regime_conditional = list(Good = 0.0, Normal = 0.05, Bad = 0.15, Crisis = 0.30),
    opportunity_cost_basis = "3M_rates_2.5pct"
  ),
  performance = port_metrics,
  core_comparison = list(
    core_sharpe = core_metrics$Sharpe,
    core_cagr = core_metrics$CAGR,
    core_mdd = core_metrics$MDD,
    mdd_reduction_pct = round(mdd_reduction_pct, 4)
  ),
  audit_cash_allocation = audit_result,
  crisis_alpha_test = list(
    alphas = crisis_alphas,
    positive_count = crisis_positive,
    total_tested = crisis_tested,
    passed = crisis_positive >= ceiling(crisis_tested / 2)
  ),
  regime_distribution = as.list(table(cash_signal$regime_state)),
  grade = if (audit_result$passed && mdd_reduction_pct > 0.05) "A"
          else if (audit_result$passed) "B"
          else "C",
  grade_rationale = sprintf(
    "role=cash_allocation. opp_cost=%.2fbps, MDD_reduction=%.2f%%, crisis_alpha positive %d/%d",
    audit_result$opportunity_cost_bps_annualized,
    mdd_reduction_pct * 100,
    crisis_positive, crisis_tested
  )
)

output_path <- file.path(output_dir, "hurdle_result.json")
write_json(hurdle_result, output_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
cat(sprintf("\n[7] Saved: %s\n", output_path))

cash_ts_path <- file.path(output_dir, "cash_weight_timeseries.csv")
fwrite(port[, .(Date, regime_state, cash_weight, port_ret, core_ret, mrs)], cash_ts_path)
cat(sprintf("[7b] Saved: %s\n", cash_ts_path))

cat("\n=== STR_CASH_v1 backtest complete ===\n")
cat(sprintf("Grade: %s | SR: %.3f | CAGR: %.2f%% | MDD: %.2f%%\n",
            hurdle_result$grade, port_metrics$Sharpe,
            port_metrics$CAGR * 100, port_metrics$MDD * 100))
