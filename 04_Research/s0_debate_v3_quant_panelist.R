cat("=== S0 Debate v3 — Quant Panelist 채점 ===\n")
cat("=== Q07 / Q03 / D29 / C19 재평가 (L-112 defense 기준) ===\n\n")

suppressMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

ROOT      <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
CACHE_DIR <- file.path(ROOT, ".cache")

source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

target_factors <- c("Q07_Earnings_Stability", "Q03_ROA",
                    "D29_Accounting_Beta",    "C19_Composite_Earnings")

# ── 0. 캐시 로드 ────────────────────────────────────────────────────
s  <- fread(file.path(CACHE_DIR, "stress_factor_ic_analysis.csv"))
r4 <- fread(file.path(CACHE_DIR, "conditional_ic_matrix_4regime.csv"))

cat("=== [Step 1] 각 팩터 IC 지표 (stress 기준 / 4-regime 기준) ===\n\n")

result_tbl <- rbindlist(lapply(target_factors, function(f) {
  sv <- s[Factor_Name == f]
  rv <- r4[factor_id == f]
  data.table(
    factor       = f,
    stress_icir  = if (nrow(sv) > 0) sv$stress_icir  else NA_real_,
    stress_n     = if (nrow(sv) > 0) sv$stress_n      else NA_integer_,
    stress_pct_pos = if (nrow(sv) > 0) sv$stress_pct_pos else NA_real_,
    normal_icir  = if (nrow(sv) > 0) sv$normal_icir   else NA_real_,
    crisis_ratio = if (nrow(sv) > 0) sv$crisis_ratio  else NA_real_,
    crisis_premium = if (nrow(sv) > 0) sv$crisis_premium else NA_real_,
    r4_icir_CALM   = if (nrow(rv) > 0) rv$icir_CALM   else NA_real_,
    r4_icir_NORMAL = if (nrow(rv) > 0) rv$icir_NORMAL else NA_real_,
    r4_icir_CAUTION= if (nrow(rv) > 0) rv$icir_CAUTION else NA_real_,
    r4_icir_CRISIS = if (nrow(rv) > 0) rv$icir_CRISIS else NA_real_,
    r4_icir_all    = if (nrow(rv) > 0) rv$icir_all    else NA_real_
  )
}))

cat("팩터별 IC 지표 요약:\n")
for (i in 1:nrow(result_tbl)) {
  r <- result_tbl[i]
  cat(sprintf("\n[%s]\n", r$factor))
  cat(sprintf("  Stress ICIR   : %+.4f  (n=%d개월, pct_pos=%.1f%%)\n",
              r$stress_icir, r$stress_n, r$stress_pct_pos * 100))
  cat(sprintf("  Normal ICIR   : %+.4f\n", r$normal_icir))
  cat(sprintf("  Crisis Ratio  : %.3f  (>1 = 위기에 더 강함)\n", r$crisis_ratio))
  cat(sprintf("  Crisis Premium: %+.4f\n", r$crisis_premium))
  cat(sprintf("  4r CALM ICIR  : %+.4f\n", r$r4_icir_CALM))
  cat(sprintf("  4r NORMAL ICIR: %+.4f\n", r$r4_icir_NORMAL))
  cat(sprintf("  4r CAUTION    : %+.4f\n", r$r4_icir_CAUTION))
  cat(sprintf("  4r CRISIS ICIR: %+.4f\n", r$r4_icir_CRISIS))
  cat(sprintf("  Overall ICIR  : %+.4f\n", r$r4_icir_all))
}

# ── 2. Factor DB에서 직접 상관 계산 ─────────────────────────────────
cat("\n\n=== [Step 2] Factor DB → 내부 상관 계산 (Q07/Q03/D29/C19) ===\n")
cat("    C15: load_month_factors() | C13: Z_Score_Aligned\n\n")

# 36개월 (2021-01 ~ 2023-12) 월별 wide 피벗 후 평균 상관
sig_dates_36 <- format(seq(as.Date("2021-01-01"), as.Date("2023-12-01"), by = "month"), "%Y-%m-%d")

fdb_list_36 <- lapply(sig_dates_36, function(d) {
  tryCatch({
    dt <- load_month_factors(d)
    dt <- dt[Factor_Name %in% target_factors]
    # wide pivot: Ticker × Factor
    w <- dcast(dt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    w[, sig_date := d]
    w
  }, error = function(e) NULL)
})
fdb_wide <- rbindlist(Filter(Negate(is.null), fdb_list_36), fill = TRUE)
cat(sprintf("Wide 데이터: %d rows × %d cols\n", nrow(fdb_wide), ncol(fdb_wide)))

# 종목×월 레벨에서 상관 계산 (pairwise)
fac_cols <- intersect(target_factors, names(fdb_wide))
cat(sprintf("사용 팩터 컬럼: %s\n", paste(fac_cols, collapse = ", ")))

fdb_mat <- fdb_wide[, fac_cols, with = FALSE]
fdb_mat <- fdb_mat[complete.cases(fdb_mat)]
cat(sprintf("완전 케이스: %d개\n", nrow(fdb_mat)))

corr_mat <- cor(fdb_mat, use = "pairwise.complete.obs")
cat("\n내부 상관 행렬:\n")
print(round(corr_mat, 4))

# 페어별 출력
pairs <- list(
  c("Q07_Earnings_Stability", "Q03_ROA"),
  c("Q07_Earnings_Stability", "D29_Accounting_Beta"),
  c("Q03_ROA",                "D29_Accounting_Beta"),
  c("Q07_Earnings_Stability", "C19_Composite_Earnings"),
  c("Q03_ROA",                "C19_Composite_Earnings"),
  c("D29_Accounting_Beta",    "C19_Composite_Earnings")
)

cat("\n페어별 상관:\n")
for (p in pairs) {
  f1 <- p[1]; f2 <- p[2]
  if (f1 %in% rownames(corr_mat) && f2 %in% rownames(corr_mat)) {
    val <- corr_mat[f1, f2]
    flag <- if (abs(val) < 0.5) "OK(<0.5)" else "WARNING(>=0.5)"
    cat(sprintf("  %-40s <-> %-40s : %+.4f  [%s]\n", f1, f2, val, flag))
  }
}

# ── 3. 8대 스트레스 구간별 D29 IC (L-112 기준) ──────────────────────
cat("\n\n=== [Step 3] D29 스트레스 구간별 IC (L-112 defense 기준) ===\n\n")

stress_periods <- list(
  GFC        = c(as.Date("2008-01-01"), as.Date("2009-03-31")),
  EU_Debt    = c(as.Date("2011-07-01"), as.Date("2011-09-30")),
  Trade_War  = c(as.Date("2018-02-01"), as.Date("2018-12-31")),
  COVID      = c(as.Date("2020-01-01"), as.Date("2020-04-30")),
  Rate_Hike  = c(as.Date("2022-01-01"), as.Date("2022-06-30")),
  Iran_War   = c(as.Date("2025-03-01"), as.Date("2026-03-31"))
)

# rawdata 로드 (Ret 필요)
rawdata <- tryCatch(
  as.data.table(read_parquet(file.path(CACHE_DIR, "rawdata.parquet"))),
  error = function(e) { cat("rawdata.parquet 로드 실패:", e$message, "\n"); NULL }
)

if (!is.null(rawdata)) {
  cat(sprintf("RAWDATA: %d rows, 컬럼: %s\n", nrow(rawdata),
              paste(head(names(rawdata), 8), collapse = ", ")))

  # Date 컬럼 확인 및 월 단위 집계
  if ("Date" %in% names(rawdata)) {
    rawdata[, Date := as.Date(Date)]
    rawdata[, YearMonth := format(Date, "%Y-%m")]

    # 월간 수익률 (forward 1M return을 위해 t+1 lag: IC는 t 신호 → t+1 수익률)
    # 이미 factor_ic_monthly에 전처리되어 있으므로 factor_ic_monthly를 이용
    cat("\n  [Note] Factor IC monthly 파일에서 구간별 IC 직접 추출 시도...\n")
  }
} else {
  cat("  rawdata 없음 — stress_factor_ic_analysis.csv의 D29 결과 활용\n")
}

# stress_factor_ic_analysis.csv에 구간별 IC가 없으면 aggregate 값으로 평가
d29_s <- s[Factor_Name == "D29_Accounting_Beta"]
d29_r4 <- r4[factor_id == "D29_Accounting_Beta"]

cat("\nD29 방어 팩터 평가 (L-112 기준):\n")
cat(sprintf("  [stress ICIR]     = %+.4f  (기준 >= 0.5: %s)\n",
            d29_s$stress_icir, if (d29_s$stress_icir >= 0.5) "PASS" else "FAIL"))
cat(sprintf("  [4r CRISIS ICIR]  = %+.4f  (기준 > 0: %s)\n",
            d29_r4$icir_CRISIS, if (!is.na(d29_r4$icir_CRISIS) && d29_r4$icir_CRISIS > 0) "PASS" else "FAIL"))
cat(sprintf("  [crisis_ratio]    = %.3f   (>1 = 위기 프리미엄 확인)\n",
            d29_s$crisis_ratio))
cat(sprintf("  [stress_pct_pos]  = %.1f%%  (위기 구간 중 양수 IC 비율)\n",
            d29_s$stress_pct_pos * 100))

# factor_ic_monthly 로드 (구간별 IC)
fi_path <- file.path(CACHE_DIR, "factor_db", "factor_ic_monthly.parquet")
if (file.exists(fi_path)) {
  fi <- as.data.table(read_parquet(fi_path))
  fi[, Date := as.Date(Date)]
  cat(sprintf("\n  factor_ic_monthly: %d rows, 컬럼: %s\n", nrow(fi), paste(names(fi)[1:6], collapse=",")))

  # D29 IC 시계열 추출
  d29_ic <- fi[Factor_Name == "D29_Accounting_Beta", .(Date, IC)]
  if (nrow(d29_ic) > 0) {
    cat(sprintf("  D29 IC rows: %d\n", nrow(d29_ic)))
    cat("\n  스트레스 구간별 D29 IC:\n")
    for (nm in names(stress_periods)) {
      p <- stress_periods[[nm]]
      sub <- d29_ic[Date >= p[1] & Date <= p[2]]
      if (nrow(sub) > 0) {
        ic_mean <- mean(sub$IC, na.rm = TRUE)
        ic_sd   <- sd(sub$IC, na.rm = TRUE)
        icir_p  <- if (!is.na(ic_sd) && ic_sd > 0) ic_mean / ic_sd * sqrt(nrow(sub)) else NA
        pct_pos <- mean(sub$IC > 0, na.rm = TRUE)
        cat(sprintf("    %-12s: IC_mean=%+.4f  ICIR=%+.4f  n=%d  pct_pos=%.0f%%\n",
                    nm, ic_mean, ifelse(is.na(icir_p), 0, icir_p), nrow(sub), pct_pos * 100))
      } else {
        cat(sprintf("    %-12s: 데이터 없음\n", nm))
      }
    }
  }
} else {
  cat("  factor_ic_monthly.parquet 없음 — aggregate 지표만 사용\n")
}

# ── 4. 채점 ─────────────────────────────────────────────────────────
cat("\n\n=== [Step 4] 채점 Rubric (0~25점) ===\n\n")

q07  <- result_tbl[factor == "Q07_Earnings_Stability"]
q03  <- result_tbl[factor == "Q03_ROA"]
d29  <- result_tbl[factor == "D29_Accounting_Beta"]
c19  <- result_tbl[factor == "C19_Composite_Earnings"]

# icir_pass (0~5)
# Q07: 전체기간 ICIR >= 0.3
q07_pass  <- !is.na(q07$r4_icir_all) && q07$r4_icir_all >= 0.30
# Q03: 전체기간 ICIR >= 0.3
q03_pass  <- !is.na(q03$r4_icir_all) && q03$r4_icir_all >= 0.30
# D29: defense 기준 — stress ICIR >= 0.5 AND 4r CRISIS ICIR > 0
d29_stress_ok <- !is.na(d29$stress_icir)      && d29$stress_icir >= 0.50
d29_crisis_ok <- !is.na(d29$r4_icir_CRISIS)   && d29$r4_icir_CRISIS > 0

icir_pass_score <- 0
icir_pass_score <- icir_pass_score + if (q07_pass) 2 else 0
icir_pass_score <- icir_pass_score + if (q03_pass) 2 else 0
icir_pass_score <- icir_pass_score + if (d29_stress_ok && d29_crisis_ok) 1 else if (d29_stress_ok || d29_crisis_ok) 0.5 else 0
icir_pass_score <- as.integer(round(icir_pass_score))
icir_pass_score <- min(5L, max(0L, icir_pass_score))

cat(sprintf("[icir_pass] Q07_all_ICIR=%.4f(%s) | Q03_all_ICIR=%.4f(%s)\n",
            q07$r4_icir_all, if(q07_pass)"PASS" else "FAIL",
            q03$r4_icir_all, if(q03_pass)"PASS" else "FAIL"))
cat(sprintf("           D29_stress_ICIR=%.4f(%s) | D29_4r_CRISIS=%.4f(%s)\n",
            d29$stress_icir, if(d29_stress_ok)">=0.5 PASS" else "<0.5 FAIL",
            ifelse(is.na(d29$r4_icir_CRISIS), NA, d29$r4_icir_CRISIS),
            if(d29_crisis_ok)">0 PASS" else "FAIL"))
cat(sprintf("  => icir_pass 점수: %d/5\n\n", icir_pass_score))

# internal_corr (0~5): Q07-Q03-D29 간 상관 < 0.5
q07q03_ok <- FALSE; q07d29_ok <- FALSE; q03d29_ok <- FALSE
q07q03_v  <- NA_real_; q07d29_v <- NA_real_; q03d29_v <- NA_real_

if (all(c("Q07_Earnings_Stability","Q03_ROA","D29_Accounting_Beta") %in% rownames(corr_mat))) {
  q07q03_v <- corr_mat["Q07_Earnings_Stability","Q03_ROA"]
  q07d29_v <- corr_mat["Q07_Earnings_Stability","D29_Accounting_Beta"]
  q03d29_v <- corr_mat["Q03_ROA","D29_Accounting_Beta"]
  q07q03_ok <- abs(q07q03_v) < 0.5
  q07d29_ok <- abs(q07d29_v) < 0.5
  q03d29_ok <- abs(q03d29_v) < 0.5
}

n_ok_internal <- sum(c(q07q03_ok, q07d29_ok, q03d29_ok))
internal_corr_score <- as.integer(round(n_ok_internal / 3 * 5))

cat(sprintf("[internal_corr] Q07-Q03=%+.4f(%s) | Q07-D29=%+.4f(%s) | Q03-D29=%+.4f(%s)\n",
            q07q03_v, if(q07q03_ok)"OK" else "HIGH",
            q07d29_v, if(q07d29_ok)"OK" else "HIGH",
            q03d29_v, if(q03d29_ok)"OK" else "HIGH"))
cat(sprintf("  => internal_corr 점수: %d/5\n\n", internal_corr_score))

# c19_corr (0~5): Q07/Q03/D29 각각의 C19 상관 < 0.2
c19_q07_v <- if (all(c("Q07_Earnings_Stability","C19_Composite_Earnings") %in% rownames(corr_mat)))
  corr_mat["Q07_Earnings_Stability","C19_Composite_Earnings"] else NA_real_
c19_q03_v <- if (all(c("Q03_ROA","C19_Composite_Earnings") %in% rownames(corr_mat)))
  corr_mat["Q03_ROA","C19_Composite_Earnings"] else NA_real_
c19_d29_v <- if (all(c("D29_Accounting_Beta","C19_Composite_Earnings") %in% rownames(corr_mat)))
  corr_mat["D29_Accounting_Beta","C19_Composite_Earnings"] else NA_real_

c19_q07_ok <- !is.na(c19_q07_v) && abs(c19_q07_v) < 0.2
c19_q03_ok <- !is.na(c19_q03_v) && abs(c19_q03_v) < 0.2
c19_d29_ok <- !is.na(c19_d29_v) && abs(c19_d29_v) < 0.2

n_ok_c19 <- sum(c(c19_q07_ok, c19_q03_ok, c19_d29_ok))
c19_corr_score <- as.integer(round(n_ok_c19 / 3 * 5))

cat(sprintf("[c19_corr] Q07-C19=%+.4f(%s) | Q03-C19=%+.4f(%s) | D29-C19=%+.4f(%s)\n",
            c19_q07_v, if(c19_q07_ok)"<0.2 OK" else ">=0.2 WARN",
            c19_q03_v, if(c19_q03_ok)"<0.2 OK" else ">=0.2 WARN",
            c19_d29_v, if(c19_d29_ok)"<0.2 OK" else ">=0.2 WARN"))
cat(sprintf("  => c19_corr 점수: %d/5\n\n", c19_corr_score))

# defense_ic (0~5): D29 양쪽 위기 기준 모두 양수
# L-112: stress ICIR >= 0.5 + 4r CRISIS ICIR > 0
defense_ic_score <- 0L
if (d29_stress_ok && d29_crisis_ok) {
  defense_ic_score <- 5L
  cat(sprintf("[defense_ic] D29 stress_ICIR=%.4f(>=0.5) AND 4r_CRISIS=%.4f(>0) => 5/5\n",
              d29$stress_icir, d29$r4_icir_CRISIS))
} else if (d29_stress_ok) {
  defense_ic_score <- 3L
  cat(sprintf("[defense_ic] D29 stress_ICIR=%.4f(>=0.5) BUT 4r_CRISIS=%.4f(<=0) => 3/5\n",
              d29$stress_icir, ifelse(is.na(d29$r4_icir_CRISIS),NA,d29$r4_icir_CRISIS)))
} else if (d29_crisis_ok) {
  defense_ic_score <- 2L
  cat(sprintf("[defense_ic] D29 stress_ICIR=%.4f(<0.5) BUT 4r_CRISIS=%.4f(>0) => 2/5\n",
              d29$stress_icir, d29$r4_icir_CRISIS))
} else {
  cat(sprintf("[defense_ic] D29 양쪽 기준 모두 미달 => 0/5\n"))
}
cat(sprintf("  => defense_ic 점수: %d/5\n\n", defense_ic_score))

# data_avail (0~5): 데이터 충분성 + C13 준수
# load_month_factors()를 통해 Z_Score_Aligned 사용 → C15/C13 준수
# 36개월 wide 데이터 확인: 완전케이스 수
n_complete  <- nrow(fdb_mat)
data_coverage <- n_complete / (nrow(fdb_wide) + 1)  # 분모 방어
c13_ok   <- TRUE   # Z_Score_Aligned만 사용
c15_ok   <- TRUE   # load_month_factors() 경유
data_avail_score <- 0L
if (c13_ok && c15_ok && n_complete > 10000) {
  data_avail_score <- 5L
} else if (c13_ok && c15_ok && n_complete > 1000) {
  data_avail_score <- 4L
} else if (c13_ok && c15_ok) {
  data_avail_score <- 3L
} else {
  data_avail_score <- 0L
}

cat(sprintf("[data_avail] 완전케이스=%d, C13(Z_Score_Aligned)=%s, C15(load_month_factors)=%s\n",
            n_complete, if(c13_ok)"OK" else "FAIL", if(c15_ok)"OK" else "FAIL"))
cat(sprintf("  => data_avail 점수: %d/5\n\n", data_avail_score))

# ── 5. 최종 집계 ─────────────────────────────────────────────────────
total_score <- icir_pass_score + internal_corr_score + c19_corr_score +
               defense_ic_score + data_avail_score

cat(paste(rep("=", 60), collapse=""), "\n")
cat(sprintf("최종 점수: %d / 25\n", total_score))
cat(paste(rep("=", 60), collapse=""), "\n\n")
cat(sprintf("  icir_pass    : %d/5\n", icir_pass_score))
cat(sprintf("  internal_corr: %d/5\n", internal_corr_score))
cat(sprintf("  c19_corr     : %d/5\n", c19_corr_score))
cat(sprintf("  defense_ic   : %d/5\n", defense_ic_score))
cat(sprintf("  data_avail   : %d/5\n", data_avail_score))

# ── 6. findings 생성 ─────────────────────────────────────────────────
cat("\n=== [Step 6] Findings 요약 ===\n\n")

# 조건부 판단
findings_parts <- c()

# Q07/Q03 ICIR
findings_parts <- c(findings_parts, sprintf(
  "Q07 전체ICIR=%.3f(%s), Q03 전체ICIR=%.3f(%s)",
  q07$r4_icir_all, if(q07_pass)"Pass" else "Fail",
  q03$r4_icir_all, if(q03_pass)"Pass" else "Fail"
))

# D29 defense
findings_parts <- c(findings_parts, sprintf(
  "D29 stress_ICIR=%.3f(L-112기준%s), 4r_CRISIS=%.3f(%s), crisis_ratio=%.2f",
  d29$stress_icir, if(d29_stress_ok)"Pass" else "Fail",
  ifelse(is.na(d29$r4_icir_CRISIS), 0, d29$r4_icir_CRISIS),
  if(d29_crisis_ok)"Pass" else "Fail",
  d29$crisis_ratio
))

# 내부 상관
if (!is.na(q07q03_v)) {
  findings_parts <- c(findings_parts, sprintf(
    "내부상관 Q07-Q03=%.3f, Q07-D29=%.3f, Q03-D29=%.3f (모두<0.5:%s)",
    q07q03_v, q07d29_v, q03d29_v,
    if(all(c(q07q03_ok,q07d29_ok,q03d29_ok)))"OK" else "일부위반"
  ))
}

# C19 상관
if (!is.na(c19_q07_v)) {
  findings_parts <- c(findings_parts, sprintf(
    "C19상관 Q07=%.3f, Q03=%.3f, D29=%.3f (기준<0.2)",
    c19_q07_v, c19_q03_v, c19_d29_v
  ))
}

findings_text <- paste(findings_parts, collapse=". ")
cat(findings_text, "\n\n")

# ── 7. JSON 출력 ─────────────────────────────────────────────────────
cat("\n=== [Step 7] 출력 JSON ===\n\n")

# conditions 생성
conditions <- c()
if (!q07_pass)     conditions <- c(conditions, "Q07 overall ICIR 재확인 필요")
if (!q03_pass)     conditions <- c(conditions, "Q03 overall ICIR 재확인 필요")
if (!d29_stress_ok) conditions <- c(conditions, "D29 stress ICIR 기준치 미달")
if (!d29_crisis_ok) conditions <- c(conditions, "D29 4r CRISIS ICIR 음수")
if (c19_corr_score < 3) conditions <- c(conditions, "C19 상관 일부 0.2 초과 — DFA 구조적 분리 검토")
if (internal_corr_score < 3) conditions <- c(conditions, "내부 팩터 상관 일부 0.5 초과")

out <- list(
  role      = "quant",
  total     = total_score,
  breakdown = list(
    icir_pass     = icir_pass_score,
    internal_corr = internal_corr_score,
    c19_corr      = c19_corr_score,
    defense_ic    = defense_ic_score,
    data_avail    = data_avail_score
  ),
  findings   = substr(findings_text, 1, 500),
  conditions = conditions
)

cat(toJSON(out, auto_unbox = TRUE, pretty = TRUE), "\n")
cat("\n=== 분석 완료 ===\n")
