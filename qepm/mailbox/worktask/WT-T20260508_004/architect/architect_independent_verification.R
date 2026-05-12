## ============================================================================
## WT-T20260508_004 ARCHITECT INDEPENDENT VERIFICATION
## AX-008 3rd-source mandate. S4 PG2 admit (Hybrid 50/25/20/5cash) 정합 검증.
##
## 검증 path 다양화 (Forge run_all.R / phase3_run_5family.R 와 다른 path):
##   PATH_A "metrics replay": 03_period_returns.csv ret_net → PerformanceAnalytics
##           표준 함수만 (Return.cumulative / maxDrawdown / SharpeRatio.annualized
##           / SortinoRatio / table.AnnualizedReturns) — pure xts 기반.
##   PATH_B "composition replay": weights.csv + 3 leg returns → ret_net 자체 합성
##           (단순 c_AR*r_AR + c_TS*r_TS + c_KR*r_KR - cost) → Forge ret_net 비교.
##
## Tolerance:
##   - |ΔSR| ≤ 0.05 (Forge phase4 fabrication threshold) → PASS
##   - |ΔSR| > 0.05 → FABRICATION 의심 escalate
##   - PATH_B ret_net cor pre/post ≥ 0.999 → composition 무결
##
## Pure Function R12: weights/leg returns/period_returns 모두 read-only.
## ============================================================================

suppressMessages({
  library(data.table)
  library(jsonlite)
  library(xts)
  library(PerformanceAnalytics)
  library(zoo)
})

## ─── Paths ────────────────────────────────────────────────────────────────────
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_004")
ARCHITECT    <- file.path(WT_DIR, "architect")
FAMILY_DIR   <- file.path(WT_DIR, "output/5family_post_incremental")
SOURCE_WT    <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260505_001")

dir.create(ARCHITECT, showWarnings = FALSE, recursive = TRUE)

ANN <- 12L
RF  <- 0
COST_BPS_ONEWAY <- 15
COST_PER_DOLLAR <- COST_BPS_ONEWAY / 1e4

cat("========================================================\n")
cat(" Architect Independent Verification — WT-T20260508_004\n")
cat(sprintf(" Run: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

families <- c("S0_baseline", "S1_KR10y_only", "S2_TSMOM_only",
              "S3_Hybrid_70_15_15", "S4_Hybrid_50_25_25")

## ============================================================================
## PATH_A — Metrics replay (10-component bt_result ret_net → PerfA)
## ============================================================================
cat(">>> PATH_A: 03_period_returns.csv → PerformanceAnalytics 표준 함수 재산출\n\n")

forge_metrics <- list()
arch_metrics_A <- list()

for (fam in families) {
  pr_path <- file.path(FAMILY_DIR, fam, "03_period_returns.csv")
  m_path  <- file.path(FAMILY_DIR, fam, "06_metrics.csv")
  stopifnot(file.exists(pr_path), file.exists(m_path))

  pr <- fread(pr_path)
  pr[, date := as.Date(date)]
  setorder(pr, date)

  ## net returns xts (skip first row if ret_net is establishment cost only — Forge S0~S4 0+1st cost)
  ## NOTE: Forge sets ret_gross[1]=0 + ret_net[1]=-cost (establishment). PerfA가 첫 row 포함해도
  ## Total_Return / CAGR / Sharpe 계산 가능. 단 그게 표준 — 모두 그대로 처리.
  ret_net_xts <- xts(pr$ret_net, order.by = pr$date)

  ## --- PATH_A Architect metrics (PerformanceAnalytics 표준 함수만) ---
  ## Sharpe via SharpeRatio.annualized (RF=0, std method)
  sr_perfA <- as.numeric(SharpeRatio.annualized(ret_net_xts, Rf = RF, scale = ANN, geometric = FALSE))
  ## also via direct ER mean/sd (Charter §12 ER-based) — should equal sr_perfA when RF=0
  ER <- pr$ret_net - RF
  sr_direct <- mean(ER) / sd(ER) * sqrt(ANN)
  ## CAGR via Return.cumulative + n-period geometric annualization
  total_ret <- as.numeric(Return.cumulative(ret_net_xts, geometric = TRUE))
  n_obs <- nrow(pr)
  cagr <- (1 + total_ret)^(ANN / n_obs) - 1
  ## CAGR via Return.annualized (PerfA standard)
  cagr_perfA <- as.numeric(Return.annualized(ret_net_xts, scale = ANN, geometric = TRUE))
  ## MDD via maxDrawdown (return-based, no NAV anchor needed)
  mdd <- as.numeric(maxDrawdown(ret_net_xts, geometric = TRUE))
  ## Sortino — table.AnnualizedReturns is informative; SortinoRatio direct
  sortino <- as.numeric(SortinoRatio(ret_net_xts, MAR = 0)) * sqrt(ANN)
  ## Vol annualized
  vol <- as.numeric(StdDev.annualized(ret_net_xts, scale = ANN))
  ## Calmar
  calmar <- if (mdd > 0) cagr_perfA / mdd else NA_real_

  arch_metrics_A[[fam]] <- list(
    n_obs      = n_obs,
    SR_PerfA   = round(sr_perfA, 6),
    SR_direct  = round(sr_direct, 6),
    CAGR_geom  = round(cagr, 6),
    CAGR_PerfA = round(cagr_perfA, 6),
    MDD        = round(mdd, 6),
    Sortino    = round(sortino, 6),
    Vol_ann    = round(vol, 6),
    Calmar     = round(calmar, 6),
    Total_Return = round(total_ret, 6)
  )

  ## --- Forge reported metrics ---
  m <- fread(m_path)
  forge_metrics[[fam]] <- list(
    SR     = m[metric_name == "Sharpe", as.numeric(metric_value)],
    CAGR   = m[metric_name == "CAGR", as.numeric(metric_value)],
    MDD    = m[metric_name == "MDD", as.numeric(metric_value)],
    Sortino = m[metric_name == "Sortino", as.numeric(metric_value)],
    Vol     = m[metric_name == "Annualized_Volatility", as.numeric(metric_value)],
    Calmar  = m[metric_name == "Calmar", as.numeric(metric_value)],
    Total_Return = m[metric_name == "Total_Return", as.numeric(metric_value)]
  )

  cat(sprintf("[%-22s] Forge SR=%.4f MDD=%.4f CAGR=%.4f | Architect PATH_A SR=%.4f MDD=%.4f CAGR=%.4f\n",
              fam,
              forge_metrics[[fam]]$SR, forge_metrics[[fam]]$MDD, forge_metrics[[fam]]$CAGR,
              arch_metrics_A[[fam]]$SR_PerfA, arch_metrics_A[[fam]]$MDD, arch_metrics_A[[fam]]$CAGR_PerfA))
}

cat("\n")

## ============================================================================
## PATH_B — Composition replay (weights + 3 legs → ret_net 자체 합성)
## ============================================================================
cat(">>> PATH_B: weights.csv + 3 leg returns 자체 합성 (cap_AR×r_AR + cap_TS×r_TS + cap_KR×r_KR - cost)\n\n")

## Load 3 leg returns
ar  <- fread(file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260504_001/four_layer_returns_path.csv"))
ar[, date := as.Date(date)]
ar_dt <- ar[, .(date, ret_AR_on_M4)]
setkey(ar_dt, date)

kr <- fread(file.path(PROJECT_ROOT, "stage_artifacts/WT_S20260504_008/merged_returns.csv"))
kr[, date := as.Date(date)]
kr_dt <- kr[, .(date, kr_10y)]
setkey(kr_dt, date)

ts <- fread(file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-S20260504_009/docs/rotation_path_TSMOM.csv"))
ts[, date := as.Date(date)]
ts_dt <- ts[, .(date, tsmom_gross = ml_realized)]   ## ml_realized is gross (Forge phase3 line 73)
setkey(ts_dt, date)

## Schedule dates from weights.csv (S3 source)
weights <- fread(file.path(SOURCE_WT, "weights.csv"))
weights[, as_of_date := as.Date(as_of_date)]
schedule_dates <- sort(unique(weights$as_of_date))
n_sched <- length(schedule_dates)
cat(sprintf("[INPUT] schedule_dates: %d (%s ~ %s)\n", n_sched, min(schedule_dates), max(schedule_dates)))

master <- data.table(date = schedule_dates)
master <- merge(master, ar_dt, by = "date", all.x = TRUE)
master <- merge(master, kr_dt, by = "date", all.x = TRUE)
master <- merge(master, ts_dt, by = "date", all.x = TRUE)
master[is.na(ret_AR_on_M4), ret_AR_on_M4 := 0]
master[is.na(kr_10y),       kr_10y := 0]
master[is.na(tsmom_gross),  tsmom_gross := 0]

## STR_1715 sleeve internal turnover (for cost)
str1715_pr <- fread(file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
str1715_pr[, date := as.Date(date)]
str_to_dt <- str1715_pr[, .(date, str_to = turnover)]
str_to_dt[is.na(str_to), str_to := 0]
master <- merge(master, str_to_dt, by = "date", all.x = TRUE)
master[is.na(str_to), str_to := 0]

## TSMOM internal turnover from w_etf_* matrix
tsmom_w_cols <- grep("^w_etf_", names(ts), value = TRUE)
ts_wmat <- as.matrix(ts[, ..tsmom_w_cols])
ts_internal_to <- c(0, sapply(2:nrow(ts_wmat), function(i) sum(abs(ts_wmat[i,] - ts_wmat[i-1,])) / 2))
ts_to_dt <- data.table(date = ts$date, ts_to = ts_internal_to)
master <- merge(master, ts_to_dt, by = "date", all.x = TRUE)
master[is.na(ts_to), ts_to := 0]

## Define capital allocations per family
build_caps <- function(label, dates) {
  n <- length(dates)
  if (label == "S0_baseline") {
    return(data.table(date = dates, c_AR = 1.0, c_TS = 0, c_KR = 0, c_CSH = 0))
  } else if (label == "S1_KR10y_only") {
    return(data.table(date = dates, c_AR = 0.70, c_TS = 0, c_KR = 0.20, c_CSH = 0.10))
  } else if (label == "S2_TSMOM_only") {
    post15 <- as.Date(dates) >= as.Date("2015-01-01")
    return(data.table(date = dates,
                      c_AR = 0.70,
                      c_TS = ifelse(post15, 0.30, 0),
                      c_KR = 0,
                      c_CSH = ifelse(post15, 0, 0.30)))
  } else if (label == "S3_Hybrid_70_15_15") {
    ## Use weights.csv aggregation (pre/post-2015 mix per Path C admit)
    agg <- weights[, .(
      c_AR = sum(weight[asset_class == "EQ_KR_TOP20_SLEEVE"]),
      c_TS = sum(weight[asset_class == "ETF_KR_TSMOM_LEG"]),
      c_KR = sum(weight[asset_class == "ETF_KR_BOND10Y_LEG"]),
      c_CSH = sum(weight[asset_class == "CASH_RESIDUAL_LEG"])
    ), by = .(date = as_of_date)]
    return(agg)
  } else if (label == "S4_Hybrid_50_25_25") {
    post15 <- as.Date(dates) >= as.Date("2015-01-01")
    return(data.table(date = dates,
                      c_AR = 0.50,
                      c_TS = ifelse(post15, 0.25, 0),
                      c_KR = 0.20,
                      c_CSH = ifelse(post15, 0.05, 0.30)))
  }
}

arch_metrics_B  <- list()
arch_compose_diag <- list()

for (fam in families) {
  caps <- build_caps(fam, master$date)
  ## Σcap = 1
  cap_dev <- max(abs(caps$c_AR + caps$c_TS + caps$c_KR + caps$c_CSH - 1))
  stopifnot(cap_dev < 1e-8)

  dt <- merge(master, caps, by = "date")

  ## Gross return
  dt[, ret_gross := c_AR * ret_AR_on_M4 + c_TS * tsmom_gross + c_KR * kr_10y + c_CSH * 0]

  ## Cost: sleeve + tsmom + cap reallocation
  cap_mat <- as.matrix(dt[, .(c_AR, c_TS, c_KR, c_CSH)])
  cap_to <- c(0, sapply(2:nrow(cap_mat), function(i) sum(abs(cap_mat[i,] - cap_mat[i-1,])) / 2))
  dt[, cap_to := cap_to]
  dt[, cost_total := (c_AR * str_to + c_TS * ts_to + cap_to) * COST_PER_DOLLAR]
  dt[, ret_net := ret_gross - cost_total]

  ## --- Architect PATH_B metrics ---
  rxts <- xts(dt$ret_net, order.by = dt$date)
  sr_B    <- as.numeric(SharpeRatio.annualized(rxts, Rf = 0, scale = ANN, geometric = FALSE))
  cagr_B  <- as.numeric(Return.annualized(rxts, scale = ANN, geometric = TRUE))
  mdd_B   <- as.numeric(maxDrawdown(rxts, geometric = TRUE))
  sortino_B <- as.numeric(SortinoRatio(rxts, MAR = 0)) * sqrt(ANN)

  arch_metrics_B[[fam]] <- list(
    n_obs    = nrow(dt),
    SR       = round(sr_B, 6),
    CAGR     = round(cagr_B, 6),
    MDD      = round(mdd_B, 6),
    Sortino  = round(sortino_B, 6)
  )

  ## --- Composition diagnostics: PATH_B ret_net vs Forge ret_net ---
  pr_path <- file.path(FAMILY_DIR, fam, "03_period_returns.csv")
  forge_pr <- fread(pr_path)[, .(date = as.Date(date), forge_ret_net = ret_net)]
  cmp <- merge(dt[, .(date, arch_ret_net = ret_net)], forge_pr, by = "date")
  cmp[, delta_ret := arch_ret_net - forge_ret_net]
  cor_pre_post <- cor(cmp$arch_ret_net, cmp$forge_ret_net)
  max_abs_delta <- max(abs(cmp$delta_ret))
  mean_abs_delta <- mean(abs(cmp$delta_ret))

  arch_compose_diag[[fam]] <- list(
    cor_arch_vs_forge = round(cor_pre_post, 8),
    max_abs_delta_ret = round(max_abs_delta, 8),
    mean_abs_delta_ret = round(mean_abs_delta, 8)
  )

  cat(sprintf("[%-22s] PATH_B SR=%.4f MDD=%.4f CAGR=%.4f | cor(arch,forge)=%.6f max|Δret|=%.6f\n",
              fam, sr_B, mdd_B, cagr_B, cor_pre_post, max_abs_delta))
}

cat("\n")

## ============================================================================
## DELTA TABLE — Forge vs Architect (PATH_A + PATH_B)
## ============================================================================
cat(">>> Delta vs Forge\n\n")

delta_dt <- rbindlist(lapply(families, function(fam) {
  data.table(
    family = fam,
    Forge_SR    = forge_metrics[[fam]]$SR,
    Arch_SR_A   = arch_metrics_A[[fam]]$SR_PerfA,
    Arch_SR_B   = arch_metrics_B[[fam]]$SR,
    Delta_SR_A  = arch_metrics_A[[fam]]$SR_PerfA - forge_metrics[[fam]]$SR,
    Delta_SR_B  = arch_metrics_B[[fam]]$SR - forge_metrics[[fam]]$SR,
    Forge_MDD   = forge_metrics[[fam]]$MDD,
    Arch_MDD_A  = arch_metrics_A[[fam]]$MDD,
    Arch_MDD_B  = arch_metrics_B[[fam]]$MDD,
    Delta_MDD_A = arch_metrics_A[[fam]]$MDD - forge_metrics[[fam]]$MDD,
    Delta_MDD_B = arch_metrics_B[[fam]]$MDD - forge_metrics[[fam]]$MDD,
    Forge_CAGR  = forge_metrics[[fam]]$CAGR,
    Arch_CAGR_A = arch_metrics_A[[fam]]$CAGR_PerfA,
    Arch_CAGR_B = arch_metrics_B[[fam]]$CAGR,
    Delta_CAGR_A = arch_metrics_A[[fam]]$CAGR_PerfA - forge_metrics[[fam]]$CAGR,
    Delta_CAGR_B = arch_metrics_B[[fam]]$CAGR - forge_metrics[[fam]]$CAGR,
    cor_arch_vs_forge = arch_compose_diag[[fam]]$cor_arch_vs_forge,
    max_abs_delta_ret = arch_compose_diag[[fam]]$max_abs_delta_ret
  )
}))

print(delta_dt[, .(family, Forge_SR, Arch_SR_A, Arch_SR_B, Delta_SR_A, Delta_SR_B)])
cat("\n")
print(delta_dt[, .(family, Forge_MDD, Arch_MDD_A, Arch_MDD_B, Delta_MDD_A, Delta_MDD_B)])
cat("\n")
print(delta_dt[, .(family, cor_arch_vs_forge, max_abs_delta_ret)])

## Save deliverables
fwrite(delta_dt, file.path(ARCHITECT, "architect_vs_forge_delta.csv"))

## Independent metrics CSV (PATH_A + PATH_B side by side)
indep_dt <- rbindlist(lapply(families, function(fam) {
  data.table(
    family = fam,
    PATH_A_SR_PerfA = arch_metrics_A[[fam]]$SR_PerfA,
    PATH_A_SR_direct = arch_metrics_A[[fam]]$SR_direct,
    PATH_A_CAGR_PerfA = arch_metrics_A[[fam]]$CAGR_PerfA,
    PATH_A_CAGR_geom_calc = arch_metrics_A[[fam]]$CAGR_geom,
    PATH_A_MDD = arch_metrics_A[[fam]]$MDD,
    PATH_A_Sortino = arch_metrics_A[[fam]]$Sortino,
    PATH_A_Vol = arch_metrics_A[[fam]]$Vol_ann,
    PATH_A_Calmar = arch_metrics_A[[fam]]$Calmar,
    PATH_A_Total_Return = arch_metrics_A[[fam]]$Total_Return,
    PATH_B_SR = arch_metrics_B[[fam]]$SR,
    PATH_B_CAGR = arch_metrics_B[[fam]]$CAGR,
    PATH_B_MDD = arch_metrics_B[[fam]]$MDD,
    PATH_B_Sortino = arch_metrics_B[[fam]]$Sortino
  )
}))
fwrite(indep_dt, file.path(ARCHITECT, "architect_independent_5family_metrics.csv"))

## ============================================================================
## VERDICT — AX-008 3rd-source PASS / FAIL
## ============================================================================
cat("\n>>> AX-008 3rd-source verdict\n\n")

threshold_sr <- 0.05
threshold_mdd <- 0.02
threshold_cor <- 0.999

verdict_per_family <- rbindlist(lapply(families, function(fam) {
  d <- delta_dt[family == fam]
  pass_sr_A    <- abs(d$Delta_SR_A) <= threshold_sr
  pass_sr_B    <- abs(d$Delta_SR_B) <= threshold_sr
  pass_mdd_A   <- abs(d$Delta_MDD_A) <= threshold_mdd
  pass_mdd_B   <- abs(d$Delta_MDD_B) <= threshold_mdd
  pass_cor     <- d$cor_arch_vs_forge >= threshold_cor
  data.table(
    family = fam,
    pass_SR_A = pass_sr_A, pass_SR_B = pass_sr_B,
    pass_MDD_A = pass_mdd_A, pass_MDD_B = pass_mdd_B,
    pass_cor = pass_cor,
    overall = pass_sr_A && pass_sr_B && pass_mdd_A && pass_mdd_B && pass_cor
  )
}))

print(verdict_per_family)

s4_verdict <- verdict_per_family[family == "S4_Hybrid_50_25_25"]
overall_pass <- all(verdict_per_family$overall)
s4_pass <- s4_verdict$overall

cat(sprintf("\n>>> Overall verdict: %s\n", ifelse(overall_pass, "PASS (5/5)", "FAIL")))
cat(sprintf(">>> S4 admit verdict: %s\n", ifelse(s4_pass, "PASS — RETAIN_VALIDATED", "FAIL — REVOKE")))

## Verdict JSON
verdict_json <- list(
  schema_version = "1.0",
  task_id = "WT-T20260508_004",
  agent  = "architect",
  mandate = "AX-008 3rd-source independent verification of S4 PG2 admit (Hybrid 50/25/20/5cash)",
  verification_paths = list(
    PATH_A = "03_period_returns.csv ret_net → PerformanceAnalytics 표준 함수만 (SharpeRatio.annualized / Return.annualized / maxDrawdown / SortinoRatio)",
    PATH_B = "weights.csv + 3 leg returns (ret_AR_on_M4 / kr_10y / tsmom_gross) 자체 합성 → ret_net → PerfA"
  ),
  tolerance = list(
    delta_SR_threshold  = threshold_sr,
    delta_MDD_threshold = threshold_mdd,
    cor_arch_vs_forge_threshold = threshold_cor
  ),
  per_family_verdict = verdict_per_family,
  forge_metrics = forge_metrics,
  architect_metrics_PATH_A = arch_metrics_A,
  architect_metrics_PATH_B = arch_metrics_B,
  composition_diagnostics = arch_compose_diag,
  delta_table_path = "architect_vs_forge_delta.csv",
  independent_metrics_path = "architect_independent_5family_metrics.csv",
  s4_admit_verdict = ifelse(s4_pass, "PASS — RETAIN_VALIDATED", "FAIL — REVOKE"),
  overall_verdict = ifelse(overall_pass, "PASS — 5/5 family within tolerance", "FAIL"),
  ax_008_3rd_source_status = ifelse(overall_pass && s4_pass, "PASS_3RD_OF_3", "FAIL_3RD_SOURCE_DISAGREE"),
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

write_json(verdict_json,
           file.path(ARCHITECT, "ax008_3rd_source_verdict.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

cat(sprintf("\n>>> Deliverables:\n"))
cat(sprintf("    - %s\n", file.path(ARCHITECT, "architect_independent_5family_metrics.csv")))
cat(sprintf("    - %s\n", file.path(ARCHITECT, "architect_vs_forge_delta.csv")))
cat(sprintf("    - %s\n", file.path(ARCHITECT, "ax008_3rd_source_verdict.json")))

cat("\n========================================================\n")
cat(" Architect PATH_A + PATH_B verification complete.\n")
cat("========================================================\n")
