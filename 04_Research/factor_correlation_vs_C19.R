cat("=== Factor Correlation Analysis: C19 vs Candidate Diversifiers ===\n")
## 핵심아이디어: STR_1631 C19 Composite(consensus family) 대비
##              미사용 고ICIR 팩터의 단면 상관, Top-30 overlap, IC 시계열 상관 분석
##              SR 2.0 달성을 위한 독립 alpha source 후보 선별

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ── 0. 경로 설정 ────────────────────────────────────────────────────────────
ROOT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
CONFIG_R  <- file.path(ROOT_DIR, "02_Infrastructure/config.R")
source(CONFIG_R)  # FACTOR_DB_DIR, CACHE_DIR, INFRA_DIR, DATA_DIR 등 설정

CONNECTOR_R <- file.path(INFRA_DIR, "factor_db/factor_db_connector.R")
source(CONNECTOR_R)  # load_month_factors()

HARNESS_R <- file.path(INFRA_DIR, "backtest_harness.R")
source(HARNESS_R)   # load_rawdata()

# ── 1. 대상 팩터 정의 ──────────────────────────────────────────────────────
ANCHOR_FACTORS <- c(
  "C01_SUE",
  "C09_Earnings_Surprise_Sq",
  "C06_TP_Gap",
  "C07_TP_Mom",
  "C19_Composite_Earnings"
)

TIER1_FACTORS <- c(
  "AC17_Accrual_Reversal",
  "AC21_CF_to_Accrual_Ratio",
  "AC22_Accrual_Volatility",
  "CR05_Short_Pressure_Proxy"
)

TIER2_FACTORS <- c(
  "D40_YangZhang_Vol",
  "D27_Beta_Stability",
  "CR08_Volume_Price_Divergence"
)

BENCHMARK_FACTORS <- c(
  "L31_Vol_Concentration",
  "L13_Vol_Variance_Ratio"
)

ALL_FACTORS <- c(ANCHOR_FACTORS, TIER1_FACTORS, TIER2_FACTORS, BENCHMARK_FACTORS)
cat(sprintf("분석 대상 팩터: %d개\n", length(ALL_FACTORS)))
cat(paste(ALL_FACTORS, collapse=", "), "\n\n")

# ── 2. 날짜 범위 설정 (최근 120개월) ──────────────────────────────────────
END_YM   <- as.integer(format(Sys.Date(), "%Y%m"))  # 현재 월
# 120개월 이전 계산
end_year  <- END_YM %/% 100
end_month <- END_YM %% 100
start_year  <- end_year - 10
start_month <- end_month
START_YM <- start_year * 100 + start_month

cat(sprintf("분석 기간: %d ~ %d (최대 120개월)\n\n", START_YM, END_YM))

# ── 3. 사용 가능한 parquet 파일 목록 생성 ─────────────────────────────────
parquet_dir <- file.path(CACHE_DIR, "factor_db")
all_files   <- list.files(parquet_dir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = FALSE)
all_yms     <- as.integer(sub("factor_db_(\\d{6})\\.parquet", "\\1", all_files))
use_yms     <- sort(all_yms[all_yms >= START_YM & all_yms <= END_YM])

cat(sprintf("사용 가능한 월 수: %d개 (목표 120개)\n\n", length(use_yms)))

# ── 4. 월별 팩터 데이터 로드 (C15 준수: load_month_factors() 사용) ────────
cat("월별 팩터 로드 중 (load_month_factors)...\n")

all_monthly <- vector("list", length(use_yms))

for (i in seq_along(use_yms)) {
  ym <- use_yms[i]
  sig_date <- as.Date(sprintf("%d-%02d-01", ym %/% 100, ym %% 100)) + 27  # 월말 근사
  sig_date_str <- format(sig_date, "%Y-%m-%d")

  tryCatch({
    dt <- load_month_factors(sig_date_str, coverage_min = 0.05)
    if (is.null(dt) || nrow(dt) == 0) return(NULL)

    # 대상 팩터만 필터 (C15: load_month_factors 경유, 직접 parquet 로드 아님)
    dt_filtered <- dt[Factor_Name %in% ALL_FACTORS]
    if (nrow(dt_filtered) == 0) return(NULL)

    dt_filtered[, YM := ym]
    all_monthly[[i]] <- dt_filtered

    if (i %% 12 == 0) {
      cat(sprintf("  %d/%d 완료 (ym=%d, 종목수=%d)\n",
                  i, length(use_yms), ym,
                  length(unique(dt_filtered$Ticker))))
    }
  }, error = function(e) {
    # 파일 없거나 에러 시 스킵
  })
}

# 결합
factor_long <- rbindlist(all_monthly, fill = TRUE)
setkey(factor_long, YM, Ticker)
cat(sprintf("\n로드 완료: %d rows, %d 개월, %d 팩터\n\n",
            nrow(factor_long),
            length(unique(factor_long$YM)),
            length(unique(factor_long$Factor_Name))))

# 유효 팩터 목록 확인
loaded_factors <- unique(factor_long$Factor_Name)
missing_factors <- setdiff(ALL_FACTORS, loaded_factors)
if (length(missing_factors) > 0) {
  cat("WARNING: 로드 안된 팩터:\n")
  cat(paste(missing_factors, collapse=", "), "\n\n")
}

# ── 5. Wide format 변환 ────────────────────────────────────────────────────
factor_wide <- dcast(factor_long, YM + Ticker ~ Factor_Name,
                     value.var = "Z_Score_Aligned",
                     fun.aggregate = mean)
setkey(factor_wide, YM, Ticker)

available_factors <- intersect(ALL_FACTORS, names(factor_wide))
cat(sprintf("Wide format 변환 완료: %d rows, 팩터 %d개\n\n",
            nrow(factor_wide), length(available_factors)))

# ── 6. 분석 1: 월별 Cross-Sectional Spearman 상관 ─────────────────────────
cat("=== 분석 1: 월별 Cross-Sectional Spearman 상관 ===\n")

months <- sort(unique(factor_wide$YM))
n_months <- length(months)

cor_list <- vector("list", n_months)

for (i in seq_along(months)) {
  m  <- months[i]
  dt_m <- factor_wide[YM == m, ..available_factors]

  # 종목 수 최소 30개 이상인 경우만
  n_valid <- sum(complete.cases(dt_m[, c("C19_Composite_Earnings"), drop=FALSE]))
  if (n_valid < 30) next

  # Spearman 상관 (pairwise.complete.obs)
  cor_m <- tryCatch(
    cor(dt_m, method = "spearman", use = "pairwise.complete.obs"),
    error = function(e) NULL
  )
  if (!is.null(cor_m)) {
    cor_list[[i]] <- cor_m
  }
}

cor_list <- Filter(Negate(is.null), cor_list)
n_valid_months <- length(cor_list)
cat(sprintf("유효 월 수: %d / %d\n", n_valid_months, n_months))

# 평균 상관 행렬
fac_names <- available_factors
cor_mean <- matrix(0, nrow=length(fac_names), ncol=length(fac_names),
                   dimnames=list(fac_names, fac_names))
cor_sd   <- matrix(0, nrow=length(fac_names), ncol=length(fac_names),
                   dimnames=list(fac_names, fac_names))

# 각 쌍별 상관의 평균/SD
for (fi in fac_names) {
  for (fj in fac_names) {
    vals <- sapply(cor_list, function(cm) {
      if (fi %in% rownames(cm) && fj %in% colnames(cm)) cm[fi, fj] else NA_real_
    })
    vals <- vals[!is.na(vals)]
    cor_mean[fi, fj] <- if (length(vals) > 0) mean(vals) else NA_real_
    cor_sd[fi, fj]   <- if (length(vals) > 1) sd(vals)   else NA_real_
  }
}

# C19 vs 각 후보 팩터 결과 출력
cat("\n--- C19_Composite_Earnings vs 각 팩터 평균 Spearman 상관 ---\n")
c19_row <- "C19_Composite_Earnings"
if (c19_row %in% fac_names) {
  result_cor <- data.table(
    Factor = fac_names,
    Tier = ifelse(fac_names %in% ANCHOR_FACTORS, "Anchor",
           ifelse(fac_names %in% TIER1_FACTORS, "Tier1_Crisis",
           ifelse(fac_names %in% TIER2_FACTORS, "Tier2_Neutral", "Benchmark"))),
    Avg_Spearman_vs_C19 = round(cor_mean[c19_row, fac_names], 3),
    SD_Spearman_vs_C19  = round(cor_sd[c19_row, fac_names], 3)
  )
  result_cor <- result_cor[Factor != c19_row]
  result_cor <- result_cor[order(abs(Avg_Spearman_vs_C19))]

  cat(sprintf("%-40s %-12s %12s %10s\n",
              "Factor", "Tier", "Avg_rho_C19", "SD_rho"))
  cat(strrep("-", 80), "\n")
  for (r in seq_len(nrow(result_cor))) {
    cat(sprintf("%-40s %-12s %12.3f %10.3f\n",
                result_cor$Factor[r], result_cor$Tier[r],
                result_cor$Avg_Spearman_vs_C19[r],
                result_cor$SD_Spearman_vs_C19[r]))
  }
  cat("\n")
  fwrite(cor_mean |> as.data.frame() |> (\(x) { x$Factor <- rownames(x); x })(),
         file.path(CACHE_DIR, "factor_correlation_analysis.csv"))
  cat("=> .cache/factor_correlation_analysis.csv 저장 완료\n\n")
} else {
  cat("WARNING: C19_Composite_Earnings not loaded\n\n")
}

# ── 7. 분석 2: Top-30 Jaccard Overlap ────────────────────────────────────
cat("=== 분석 2: Top-30 Jaccard Overlap vs C19 ===\n")

TOP_N <- 30
candidate_factors <- setdiff(available_factors, "C19_Composite_Earnings")
candidate_factors <- intersect(candidate_factors, c(TIER1_FACTORS, TIER2_FACTORS, BENCHMARK_FACTORS))

# 월별 Jaccard 계산
jaccard_by_month <- vector("list", length(months))

for (i in seq_along(months)) {
  m  <- months[i]
  dt_m <- factor_wide[YM == m]

  # C19 Top-30
  if (!"C19_Composite_Earnings" %in% names(dt_m)) next
  c19_ranked <- dt_m[!is.na(C19_Composite_Earnings)][order(-C19_Composite_Earnings)]
  if (nrow(c19_ranked) < TOP_N) next
  c19_top30 <- c19_ranked$Ticker[1:TOP_N]

  jac_row <- list(YM = m)
  for (cf in candidate_factors) {
    if (!cf %in% names(dt_m)) {
      jac_row[[cf]] <- NA_real_
      next
    }
    cf_ranked <- dt_m[!is.na(get(cf))][order(-get(cf))]
    if (nrow(cf_ranked) < TOP_N) {
      jac_row[[cf]] <- NA_real_
      next
    }
    cf_top30 <- cf_ranked$Ticker[1:TOP_N]
    intersection <- length(intersect(c19_top30, cf_top30))
    union_n      <- length(union(c19_top30, cf_top30))
    jac_row[[cf]] <- intersection / union_n
  }
  jaccard_by_month[[i]] <- as.data.table(jac_row)
}

jaccard_dt <- rbindlist(Filter(Negate(is.null), jaccard_by_month), fill = TRUE)
n_jac <- nrow(jaccard_dt)

cat(sprintf("유효 월 수: %d\n\n", n_jac))
cat(sprintf("%-40s %12s %10s %14s\n",
            "Factor", "Avg_Jaccard", "SD_Jaccard", "Avg_Overlap(%)"))
cat(strrep("-", 80), "\n")

overlap_summary <- data.table(
  Factor = character(),
  Tier   = character(),
  Avg_Jaccard = numeric(),
  SD_Jaccard  = numeric(),
  Avg_Overlap_pct = numeric()
)

for (cf in candidate_factors) {
  if (!cf %in% names(jaccard_dt)) next
  vals <- jaccard_dt[[cf]]
  vals <- vals[!is.na(vals)]
  avg_j <- mean(vals)
  sd_j  <- sd(vals)
  tier  <- ifelse(cf %in% TIER1_FACTORS, "Tier1_Crisis",
           ifelse(cf %in% TIER2_FACTORS, "Tier2_Neutral", "Benchmark"))
  cat(sprintf("%-40s %12.3f %10.3f %14.1f%%\n",
              cf, avg_j, sd_j, avg_j * 100))
  overlap_summary <- rbind(overlap_summary, data.table(
    Factor = cf, Tier = tier,
    Avg_Jaccard = avg_j, SD_Jaccard = sd_j,
    Avg_Overlap_pct = avg_j * 100
  ))
}
cat("\n")
fwrite(overlap_summary, file.path(CACHE_DIR, "factor_overlap_analysis.csv"))
cat("=> .cache/factor_overlap_analysis.csv 저장 완료\n\n")

# ── 8. 분석 3: IC 시계열 상관 ─────────────────────────────────────────────
cat("=== 분석 3: IC 시계열 상관 ===\n")

# RAWDATA 로드 (t+1 수익률 사용)
cat("RAWDATA 로드 중...\n")
rawdata_result <- load_rawdata(use_cache = TRUE)
# load_rawdata()는 list(RAWDATA=..., BM_DT=...) 반환
if (is.list(rawdata_result) && "RAWDATA" %in% names(rawdata_result)) {
  RAWDATA <- rawdata_result$RAWDATA
} else {
  RAWDATA <- rawdata_result
}
if (!is.data.table(RAWDATA)) setDT(RAWDATA)
setkey(RAWDATA, Date, Ticker)
cat(sprintf("RAWDATA: %d rows\n", nrow(RAWDATA)))

# 월별 수익률: 다음달 Ret (t+1 forward return)
# RAWDATA의 Date → 월 추출 후 다음달 Ret
RAWDATA[, YM := as.integer(format(Date, "%Y%m"))]

# 각 종목-월의 마지막 Close 기준 다음달 수익률
# PIT: sig_date의 Z_Score_Aligned → 다음달 Ret
# 월말 Ret: 해당 월의 마지막 거래일 Ret (누적이 아닌 당월 마지막 일의 Ret 컬럼)
# backtest_harness 패턴과 동일: 월별 last Ret를 forward return으로
monthly_ret <- RAWDATA[, .(
  Ret_this_month = last(Ret)  # 해당 월의 마지막 Ret (일별 수익률의 마지막값)
), by = .(Ticker, YM)]

# 다음달 Ret을 signal 월에 붙이기 (t+1 forward)
monthly_ret[, YM_signal := shift(YM, n=1, type="lag"), by=Ticker]
# 정확히 하면: signal_YM의 다음달 Ret
# 즉, YM=202503 팩터 → YM=202504 Ret
# 아래 방식: factor_wide의 YM에 대해 YM+1달의 Ret를 매칭

# 월별 Ret만 (Ticker, YM, Ret)
ret_lookup <- monthly_ret[, .(Ticker, YM, Ret_this_month)]
setkey(ret_lookup, Ticker, YM)

# sig_date YM → 다음달 YM 계산 함수
next_ym <- function(ym) {
  yr <- ym %/% 100; mo <- ym %% 100
  if (mo == 12) (yr + 1) * 100 + 1
  else yr * 100 + mo + 1
}

ic_list <- vector("list", length(available_factors))
names(ic_list) <- available_factors

for (fac in available_factors) {
  ic_by_month <- numeric(length(months))
  for (i in seq_along(months)) {
    m <- months[i]
    m_next <- next_ym(m)
    dt_m <- factor_wide[YM == m, .(Ticker, Score = get(fac))]
    dt_m <- dt_m[!is.na(Score)]
    # 다음달 수익률 매칭
    ret_m <- ret_lookup[YM == m_next]
    dt_m <- merge(dt_m, ret_m[, .(Ticker, Ret_this_month)], by="Ticker")
    if (nrow(dt_m) < 20) { ic_by_month[i] <- NA_real_; next }
    ic_by_month[i] <- tryCatch(
      cor(dt_m$Score, dt_m$Ret_this_month, method="spearman"),
      error = function(e) NA_real_
    )
  }
  ic_list[[fac]] <- ic_by_month
}

# IC 시계열 상관 행렬
ic_dt <- as.data.table(ic_list)
ic_cor <- cor(ic_dt, use="pairwise.complete.obs", method="pearson")

cat("\n--- IC 시계열 상관 (C19 기준 행) ---\n")
if ("C19_Composite_Earnings" %in% rownames(ic_cor)) {
  ic_c19_row <- ic_cor["C19_Composite_Earnings", ]
  ic_c19_dt  <- data.table(
    Factor = names(ic_c19_row),
    IC_Cor_vs_C19 = round(ic_c19_row, 3)
  )
  ic_c19_dt <- ic_c19_dt[Factor != "C19_Composite_Earnings"]
  ic_c19_dt <- ic_c19_dt[order(abs(IC_Cor_vs_C19))]

  cat(sprintf("%-40s %18s\n", "Factor", "IC_Cor_vs_C19"))
  cat(strrep("-", 60), "\n")
  for (r in seq_len(nrow(ic_c19_dt))) {
    cat(sprintf("%-40s %18.3f\n",
                ic_c19_dt$Factor[r], ic_c19_dt$IC_Cor_vs_C19[r]))
  }
  cat("\n")
}

# ── 9. 후보 팩터 간 상관 (Diversifier 내부 분리 확인) ──────────────────
cat("=== 후보 팩터 간 상관 (Diversifier 내부) ===\n")
cand_all <- c(TIER1_FACTORS, TIER2_FACTORS, BENCHMARK_FACTORS)
cand_avail <- intersect(cand_all, available_factors)

cat(sprintf("%-35s", ""))
for (cf in cand_avail) cat(sprintf("%8s", substr(cf, 1, 8)))
cat("\n", strrep("-", 35 + 8*length(cand_avail)), "\n")
for (fi in cand_avail) {
  cat(sprintf("%-35s", substr(fi, 1, 35)))
  for (fj in cand_avail) {
    v <- if (fi %in% rownames(cor_mean) && fj %in% colnames(cor_mean))
           cor_mean[fi, fj] else NA_real_
    cat(sprintf("%8.2f", v))
  }
  cat("\n")
}
cat("\n")

# ── 10. 최종 추천 (ρ < 0.3 AND overlap < 20%) ─────────────────────────────
cat("=== 최종 추천: ρ(C19) < 0.3 AND Overlap < 20% 조건 충족 팩터 ===\n")

THRESHOLD_RHO     <- 0.30
THRESHOLD_OVERLAP <- 0.20

# result_cor, overlap_summary 통합
if (exists("result_cor") && nrow(result_cor) > 0 && nrow(overlap_summary) > 0) {
  merged_result <- merge(
    result_cor[, .(Factor, Tier, Avg_Spearman_vs_C19, SD_Spearman_vs_C19)],
    overlap_summary[, .(Factor, Avg_Jaccard, Avg_Overlap_pct)],
    by = "Factor", all = TRUE
  )

  merged_result[, Pass_Rho     := abs(Avg_Spearman_vs_C19) < THRESHOLD_RHO]
  merged_result[, Pass_Overlap := !is.na(Avg_Jaccard) & Avg_Jaccard < THRESHOLD_OVERLAP]
  merged_result[, PASS_ALL     := Pass_Rho & Pass_Overlap]

  cat(sprintf("\n%-40s %-12s %10s %12s %14s %8s\n",
              "Factor", "Tier", "rho_C19", "Overlap(%)", "Pass_rho", "PASS"))
  cat(strrep("=", 100), "\n")

  merged_result <- merged_result[order(-PASS_ALL, abs(Avg_Spearman_vs_C19))]
  for (r in seq_len(nrow(merged_result))) {
    pass_str <- if (!is.na(merged_result$PASS_ALL[r]) && merged_result$PASS_ALL[r]) "*** PASS ***" else ""
    rho_na   <- if (is.na(merged_result$Avg_Spearman_vs_C19[r])) "  N/A" else sprintf("%10.3f", merged_result$Avg_Spearman_vs_C19[r])
    ovl_na   <- if (is.na(merged_result$Avg_Overlap_pct[r]))     "   N/A" else sprintf("%12.1f%%", merged_result$Avg_Overlap_pct[r])
    cat(sprintf("%-40s %-12s %10s %12s %8s\n",
                merged_result$Factor[r], merged_result$Tier[r],
                rho_na, ovl_na, pass_str))
  }
  cat("\n")

  pass_factors <- merged_result[PASS_ALL == TRUE, Factor]
  if (length(pass_factors) > 0) {
    cat("최종 추천 팩터 (두 조건 동시 충족):\n")
    for (pf in pass_factors) {
      tier_str <- merged_result[Factor == pf, Tier]
      rho_str  <- merged_result[Factor == pf, round(Avg_Spearman_vs_C19, 3)]
      ovl_str  <- merged_result[Factor == pf, round(Avg_Overlap_pct, 1)]
      cat(sprintf("  [%s] %s — rho=%.3f, overlap=%.1f%%\n",
                  tier_str, pf, rho_str, ovl_str))
    }
  } else {
    cat("조건 충족 팩터 없음 (임계값 조정 필요)\n")
    # 완화된 기준으로 후보 표시
    cat("\n참고: |rho| < 0.40 OR overlap < 25% 후보:\n")
    loose <- merged_result[abs(Avg_Spearman_vs_C19) < 0.40 | Avg_Jaccard < 0.25]
    for (r in seq_len(nrow(loose))) {
      cat(sprintf("  [%s] %s — rho=%.3f, overlap=%.1f%%\n",
                  loose$Tier[r], loose$Factor[r],
                  loose$Avg_Spearman_vs_C19[r],
                  loose$Avg_Overlap_pct[r]))
    }
  }
}

cat("\n=== 분석 완료 ===\n")
cat("저장 파일:\n")
cat(sprintf("  %s\n", file.path(CACHE_DIR, "factor_correlation_analysis.csv")))
cat(sprintf("  %s\n", file.path(CACHE_DIR, "factor_overlap_analysis.csv")))
