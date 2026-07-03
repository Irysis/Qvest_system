cat("=== S3 Q07 Cluster Pairwise TDC — Preliminary (Governor) ===\n")
cat("Goal: STR_1679v3 + H_1689 v3 variant_1 + STR_1687 pairwise TDC\n")
cat("Note: H_1689/STR_1679v3 codes not yet built; using available proxies\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]

# ─────────────────────────────────────────────────────────
# Empirical upper/lower TDC
# ─────────────────────────────────────────────────────────
compute_tdc <- function(x, y, q = 0.95) {
  n     <- length(x)
  u     <- rank(x, na.last = "keep") / (n + 1)
  v     <- rank(y, na.last = "keep") / (n + 1)
  upper <- sum(u > q & v > q, na.rm = TRUE) / max(sum(u > q, na.rm = TRUE), 1)
  lower <- sum(u < (1-q) & v < (1-q), na.rm = TRUE) / max(sum(u < (1-q), na.rm = TRUE), 1)
  list(upper = round(upper, 4), lower = round(lower, 4),
       max = round(max(upper, lower), 4))
}

pair_result <- function(label_a, label_b, daily_a, daily_b) {
  a <- daily_a[, .(Date, Return)]
  b <- daily_b[, .(Date, Return)]
  merged <- merge(a, b, by = "Date")
  setnames(merged, c("Date", "ret_a", "ret_b"))
  merged <- merged[!is.na(ret_a) & !is.na(ret_b)]

  # Monthly aggregation
  merged[, YM := format(Date, "%Y-%m")]
  monthly <- merged[, .(
    ret_a = prod(1 + ret_a) - 1,
    ret_b = prod(1 + ret_b) - 1
  ), by = YM]

  tdc_daily   <- compute_tdc(merged$ret_a,   merged$ret_b)
  tdc_monthly <- compute_tdc(monthly$ret_a,  monthly$ret_b)
  pearson     <- cor(merged$ret_a,  merged$ret_b,  use = "complete.obs")
  spearman    <- cor(monthly$ret_a, monthly$ret_b, method = "spearman", use = "complete.obs")

  gate11 <- tdc_daily$max < 0.50
  seq_gate <- tdc_daily$max < 0.30

  cat(sprintf("  [%s vs %s]\n", label_a, label_b))
  cat(sprintf("    n_days=%d  n_months=%d  date=%s~%s\n",
              nrow(merged), nrow(monthly), min(merged$Date), max(merged$Date)))
  cat(sprintf("    Pearson(daily)=%.3f  Spearman(monthly)=%.3f\n", pearson, spearman))
  cat(sprintf("    TDC_upper=%.3f  TDC_lower=%.3f  TDC_max=%.3f\n",
              tdc_daily$upper, tdc_daily$lower, tdc_daily$max))
  cat(sprintf("    Gate11(<0.50)=%s  SeqAdmission(<0.30)=%s\n",
              ifelse(gate11, "PASS", "FAIL"), ifelse(seq_gate, "PASS", "REVIEW")))

  list(
    pair_label       = paste(label_a, "vs", label_b),
    n_days           = nrow(merged),
    n_months         = nrow(monthly),
    date_start       = as.character(min(merged$Date)),
    date_end         = as.character(max(merged$Date)),
    pearson_daily    = round(pearson,  4),
    spearman_monthly = round(spearman, 4),
    tdc_upper_95     = tdc_daily$upper,
    tdc_lower_95     = tdc_daily$lower,
    tdc_max          = tdc_daily$max,
    tdc_monthly_upper = tdc_monthly$upper,
    gate11_pass      = gate11,
    sequential_admission_pass = seq_gate
  )
}

# ─────────────────────────────────────────────────────────
# Load available daily returns
# ─────────────────────────────────────────────────────────
cat("[1] Loading strategy daily returns...\n")

load_dr <- function(path, ret_col = "Return") {
  if (!file.exists(path)) { cat(sprintf("  MISSING: %s\n", path)); return(NULL) }
  dt <- fread(path)
  if (!"Date" %in% names(dt)) return(NULL)
  rc <- if (ret_col %in% names(dt)) ret_col else
        if ("Strategy_Ret" %in% names(dt)) "Strategy_Ret" else
        setdiff(names(dt), c("Date","NAV","YM"))[1]
  dt <- dt[, .(Date = as.Date(Date), Return = get(rc))]
  dt[!is.na(Return)]
}

# STR_1687: daily_returns.csv 미생성 → 재실행 대기
# Proxy: analysis_ic.csv 월별 IC 방향 (신호 품질 체크용만, TDC 실측 불가)
STR_1687_dr_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1687_q07_sector_neutral_defense/output/daily_returns.csv")

# STR_1679_score_blend (STR_1679v3 전신 — Q25 팩터 포함)
STR_1679_dr_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1679_score_blend/output/daily_returns_primary.csv")

# STR_1656_MLRA (현 PG2 Diversifier)
STR_1656_dr_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1656_MLRA/output/nav_S1_A.csv")

# STR_1631 Core: blend_monthly_returns.csv (core_ret column)
STR_1631_monthly_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1631_core_defense_blend/output/blend_monthly_returns.csv")

str_1679 <- load_dr(STR_1679_dr_path)
str_1656 <- load_dr(STR_1656_dr_path, ret_col = "Strategy_Ret")
str_1687 <- load_dr(STR_1687_dr_path)

# STR_1631 monthly (last trading day of month)
str_1631_monthly <- if (file.exists(STR_1631_monthly_path)) {
  dt <- fread(STR_1631_monthly_path)
  dt[, .(Date = as.Date(Date), Return = core_ret)]
} else NULL

`%||%` <- function(a, b) if (is.null(a)) b else a

cat(sprintf("  STR_1679: %s (%d rows)\n",
            if (is.null(str_1679)) "MISSING" else "OK", if (is.null(str_1679)) 0L else nrow(str_1679)))
cat(sprintf("  STR_1656: %s (%d rows)\n",
            if (is.null(str_1656)) "MISSING" else "OK", if (is.null(str_1656)) 0L else nrow(str_1656)))
cat(sprintf("  STR_1631 monthly: %s (%d rows)\n",
            if (is.null(str_1631_monthly)) "MISSING" else "OK",
            if (is.null(str_1631_monthly)) 0L else nrow(str_1631_monthly)))
cat(sprintf("  STR_1687: %s (%d rows)\n",
            if (is.null(str_1687)) "MISSING — Task#1 재실행 후 확정 TDC 계산 필요" else "OK",
            if (is.null(str_1687)) 0L else nrow(str_1687)))

# ─────────────────────────────────────────────────────────
# Pair calculations (available strategies only)
# ─────────────────────────────────────────────────────────
cat("\n[2] Pairwise TDC (available pairs)...\n")
results <- list()

# Monthly-only pair function (for STR_1631 monthly data)
pair_result_monthly <- function(label_a, label_b, monthly_a, monthly_b) {
  # monthly_a/b: data.table with Date (last-of-month), Return
  merged <- merge(monthly_a, monthly_b, by = "Date")
  setnames(merged, c("Date", "ret_a", "ret_b"))
  merged <- merged[!is.na(ret_a) & !is.na(ret_b)]
  tdc    <- compute_tdc(merged$ret_a, merged$ret_b)
  spear  <- cor(merged$ret_a, merged$ret_b, method = "spearman", use = "complete.obs")
  gate11 <- tdc$max < 0.50
  seq_gate <- tdc$max < 0.30
  cat(sprintf("  [%s vs %s] (monthly)\n", label_a, label_b))
  cat(sprintf("    n_months=%d  date=%s~%s\n", nrow(merged), min(merged$Date), max(merged$Date)))
  cat(sprintf("    Spearman=%.3f  TDC_upper=%.3f  TDC_lower=%.3f  TDC_max=%.3f\n",
              spear, tdc$upper, tdc$lower, tdc$max))
  cat(sprintf("    Gate11(<0.50)=%s  SeqAdmission(<0.30)=%s\n",
              ifelse(gate11,"PASS","FAIL"), ifelse(seq_gate,"PASS","REVIEW")))
  list(pair_label=paste(label_a,"vs",label_b), n_months=nrow(merged),
       date_start=as.character(min(merged$Date)), date_end=as.character(max(merged$Date)),
       spearman_monthly=round(spear,4), tdc_upper_95=tdc$upper,
       tdc_lower_95=tdc$lower, tdc_max=tdc$max,
       gate11_pass=gate11, sequential_admission_pass=seq_gate, granularity="monthly")
}

if (!is.null(str_1679) && !is.null(str_1631_monthly)) {
  # Convert STR_1679 daily to monthly for comparison
  str_1679_m <- str_1679[, YM := format(Date, "%Y-%m")]
  str_1679_m <- str_1679_m[, .(Date = max(Date), Return = prod(1+Return)-1), by = YM][, .(Date, Return)]
  cat("\n--- STR_1679 (Q25 proxy for STR_1679v3) vs STR_1631 (Core Primary, monthly) ---\n")
  results[["STR_1679v3_proxy_vs_STR_1631"]] <- pair_result_monthly(
    "STR_1679_Q25", "STR_1631", str_1679_m, str_1631_monthly)
}

if (!is.null(str_1631_monthly) && !is.null(str_1656)) {
  # Convert STR_1656 daily to monthly
  str_1656_m <- str_1656[, YM := format(Date, "%Y-%m")]
  str_1656_m <- str_1656_m[, .(Date = max(Date), Return = prod(1+Return)-1), by = YM][, .(Date, Return)]
  cat("\n--- STR_1631 (Core Primary, monthly) vs STR_1656 (Diversifier) ---\n")
  results[["STR_1631_vs_STR_1656"]] <- pair_result_monthly(
    "STR_1631", "STR_1656", str_1631_monthly, str_1656_m)
}

if (!is.null(str_1679) && !is.null(str_1656)) {
  cat("\n--- STR_1679 (Q25 proxy) vs STR_1656 (Diversifier) ---\n")
  results[["STR_1679v3_proxy_vs_STR_1656"]] <- pair_result(
    "STR_1679_Q25", "STR_1656", str_1679, str_1656)
}

if (!is.null(str_1687)) {
  if (!is.null(str_1679)) {
    cat("\n--- STR_1687 (Q07 Defense) vs STR_1679 (Q25 proxy for STR_1679v3) ---\n")
    results[["STR_1687_vs_STR_1679v3_proxy"]] <- pair_result(
      "STR_1687", "STR_1679_Q25", str_1687, str_1679)
  }
  if (!is.null(str_1631_monthly)) {
    str_1687_m <- str_1687[, YM := format(Date, "%Y-%m")]
    str_1687_m <- str_1687_m[, .(Date = max(Date), Return = prod(1+Return)-1), by = YM][, .(Date, Return)]
    cat("\n--- STR_1687 (Q07 Defense) vs STR_1631 (Core Primary, monthly) ---\n")
    results[["STR_1687_vs_STR_1631"]] <- pair_result_monthly(
      "STR_1687", "STR_1631", str_1687_m, str_1631_monthly)
  }
  if (!is.null(str_1656)) {
    cat("\n--- STR_1687 (Q07 Defense) vs STR_1656 (Diversifier) ---\n")
    results[["STR_1687_vs_STR_1656"]] <- pair_result(
      "STR_1687", "STR_1656", str_1687, str_1656)
  }
}

# ─────────────────────────────────────────────────────────
# Summary + Gate verdict
# ─────────────────────────────────────────────────────────
cat("\n[3] Summary + Sequential Admission Gate...\n")

if (length(results) > 0) {
  for (nm in names(results)) {
    r <- results[[nm]]
    cat(sprintf("  %-45s TDC_max=%.3f  Gate11=%s  SeqAdm=%s\n",
                r$pair_label,
                r$tdc_max,
                ifelse(r$gate11_pass, "PASS", "FAIL"),
                ifelse(r$sequential_admission_pass, "PASS", "REVIEW")))
  }
}

# Scenario_B 핵심 판정: H_1689 v3 variant_1 vs STR_1687
# (H_1689 미실행이므로 PENDING — STR_1679 proxy로 방향만 추정)
cat("\n[Scenario_B KEY JUDGMENT]\n")
cat("  H_1689 v3 variant_1 vs STR_1687: PENDING (H_1689 코드 미작성 — Task#3)\n")
cat("  예상 TDC: 0.20~0.35 (PASS_LIKELY) — Q24-exclude 구조 차별화\n")
cat("  근거: H_1689는 Q01+Q04+Q25 기반, STR_1687은 Q07+SUE sector-neutral\n")
cat("        두 전략의 factor identity overlap 없음 (Q07≠Q25, SUE≠Q01/Q04)\n")

# ─────────────────────────────────────────────────────────
# Save artifact
# ─────────────────────────────────────────────────────────
output <- list(
  artifact_type      = "s3_q07_cluster_tdc_preliminary",
  measured_by        = "Governor (s3_q07_cluster_tdc_preliminary.R)",
  measured_at        = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  session            = "68_Day_2",
  status             = "PRELIMINARY",
  pending_pairs      = c(
    "STR_1687 vs H_1689_v3_variant1 — H_1689 not yet built (Task#3)",
    "STR_1687 vs STR_1679v3 — STR_1679v3 not yet built",
    "STR_1687 daily_returns.csv — Task#1 재실행 필요"
  ),
  available_pairs    = results,
  scenario_b_verdict = list(
    pair              = "H_1689_v3_variant1 vs STR_1687",
    status            = "PENDING",
    expected_tdc_range = c(0.20, 0.35),
    expected_verdict  = "PASS_LIKELY",
    rationale         = "Factor identity: Q01+Q04+Q25 vs Q07+SUE. 구조적 overlap 없음",
    rerun_trigger     = "Task#1 (STR_1687 재실행) + Task#3 (H_1689 코드 작성) 완료 후"
  ),
  q07_cluster_sequential_admission = list(
    STR_1687_vs_existing_portfolio = "STR_1687 daily_returns 생성 후 확정 TDC 실측 예정",
    gate11_threshold   = 0.50,
    seq_gate_threshold = 0.30,
    target_verdict     = "PASS (<0.30)"
  )
)

out_path <- file.path(PROJECT_ROOT, "stage_artifacts",
                       "s3_q07_cluster_tdc_preliminary_20260419.json")
write(toJSON(output, pretty = TRUE, auto_unbox = TRUE, na = "null"), out_path)
cat(sprintf("\n[4] Saved: %s\n", out_path))
cat("\n=== S3 Preliminary TDC Complete ===\n")
cat("NOTE: 완전한 S3 artifact는 Task#1+Task#3 완료 후 확정 실행 필요\n")
