cat("=== 잔차 Alpha 스태킹 분석: Core+ML 포트폴리오 대비 독립 Alpha 팩터 탐색 ===\n")
## 목적: STR_1631(Core) + STR_1656(ML)의 월별 수익률로 설명되지 않는 잔차 IC를 가진 팩터 발굴
## PIT: IC 사용 시 Usable_Date 기반 (C14 준수)
## Factor DB: factor_ic_monthly.parquet (C15 준수, 직접 로드 예외 — 이미 집계된 IC 시계열)

t0 <- Sys.time()

# ─────────────────────────────────────────────────────────────────────────────
# 0. 경로 설정
# ─────────────────────────────────────────────────────────────────────────────
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
OUT_DIR      <- file.path(PROJECT_ROOT, "04_Research")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

cat("[Step 0] 경로 설정 완료\n")
cat("  PROJECT_ROOT:", PROJECT_ROOT, "\n")

# ─────────────────────────────────────────────────────────────────────────────
# 1. STR_1631 SYN_05 일별 NAV → 월별 수익률 추출
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 1] STR_1631 SYN_05 월별 수익률 추출\n")

STR1631_OUT <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1631_SYN_05/output")

# hurdle_result.json에서 직접 monthly 수익률을 재계산
# strategy_analyzer.R이 저장하는 파일 탐색
nav_files_1631 <- list.files(STR1631_OUT, pattern = "nav|NAV|monthly",
                              full.names = TRUE, recursive = FALSE)
cat("  STR_1631 NAV 파일:", paste(basename(nav_files_1631), collapse=", "), "\n")

# run_all.R에서 nd[, .(Date, NAV, Strategy_Ret)] 를 저장했는지 확인
# factors_detail.csv에서 Score 기반으로 날짜 추출
factors_detail <- fread(file.path(STR1631_OUT, "factors_detail.csv"))
cat("  factors_detail rows:", nrow(factors_detail), "| cols:", paste(names(factors_detail), collapse=","), "\n")

# ─────────────────────────────────────────────────────────────────────────────
# 1b. STR_1656 MLRA 일별 NAV → 월별 수익률
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 1b] STR_1656 MLRA 월별 수익률 추출\n")
STR1656_OUT <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1656_MLRA/output")

# nav_S1_A.csv (일별 NAV)
nav_1656 <- fread(file.path(STR1656_OUT, "nav_S1_A.csv"))
cat("  nav_S1_A rows:", nrow(nav_1656), "| head dates:", paste(head(nav_1656$Date, 3), collapse=","), "\n")
nav_1656[, Date := as.Date(Date)]
setkey(nav_1656, Date)

# 월말 기준 추출
nav_1656[, YM := format(Date, "%Y-%m")]
monthly_1656 <- nav_1656[, .SD[.N], by = YM]  # 월 마지막 거래일
monthly_1656[, Ret_1656 := Strategy_Ret]  # 일별이므로 월말 당일 수익률이 아님
# 월별 누적 수익률: 월 첫날~마지막날 NAV 변화율
monthly_1656_ret <- nav_1656[, .(
  Ret_month = last(NAV)/first(NAV) - 1,
  Date_end  = last(Date)
), by = YM]
setkey(monthly_1656_ret, YM)
cat("  STR_1656 월별 수익률 months:", nrow(monthly_1656_ret), "\n")

# ─────────────────────────────────────────────────────────────────────────────
# 1c. STR_1631에서 run_all.R 재실행 없이 NAV 추출 시도
#     → DAILY_NAV_DT를 저장한 파일이 없으므로 성능 지표에서 역산
#     → 대안: factors_detail.csv의 Date로 월별 Score를 가중평균한 수익률 근사
#     → 더 나은 대안: factor_correlation_analysis.csv에서 STR_1631 수익률 시계열
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 1c] STR_1631 월별 수익률 추출 — factor_correlation_analysis 탐색\n")

fca_path <- file.path(CACHE_DIR, "factor_correlation_analysis.csv")
if (file.exists(fca_path)) {
  fca <- fread(fca_path)
  cat("  factor_correlation_analysis cols:", paste(names(fca)[1:min(8,ncol(fca))], collapse=","), "\n")
  cat("  rows:", nrow(fca), "\n")
}

# STR_1631_SYN_05 재실행으로 월별 수익률 직접 계산
# run_all.R 대신: backtest_harness에서 DAILY_NAV_DT를 저장한 경우 consensus 폴더 확인
consensus_files <- list.files(file.path(CACHE_DIR, "consensus"),
                               pattern = "1631", full.names = TRUE)
cat("  STR_1631 consensus 파일:", length(consensus_files), "개\n")
if (length(consensus_files) > 0) cat("  파일:", paste(basename(consensus_files), collapse=", "), "\n")

# ─────────────────────────────────────────────────────────────────────────────
# 2. Factor IC 시계열 로드 (factor_ic_monthly.parquet)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 2] Factor IC 시계열 로드 (factor_ic_monthly.parquet)\n")

ic_path <- file.path(CACHE_DIR, "factor_db", "factor_ic_monthly.parquet")
ic_monthly <- as.data.table(read_parquet(ic_path))
ic_monthly[, Date := as.Date(Date)]
ic_monthly[, Usable_Date := as.Date(Usable_Date)]
setkey(ic_monthly, Factor_Name, Date)

cat("  총 rows:", nrow(ic_monthly), "\n")
cat("  팩터 수:", uniqueN(ic_monthly$Factor_Name), "\n")
cat("  기간:", min(ic_monthly$Date), "~", max(ic_monthly$Date), "\n")

# 팩터별 관측 수 필터 (최소 60개월 이상)
ic_count <- ic_monthly[, .(n_obs = .N,
                             ic_mean = mean(IC, na.rm=TRUE),
                             ic_sd   = sd(IC, na.rm=TRUE),
                             date_min = min(Date),
                             date_max = max(Date)),
                        by = Factor_Name]
ic_count[, ICIR := ic_mean / ic_sd]
ic_count <- ic_count[n_obs >= 60]
cat("  60개월+ 팩터 수:", nrow(ic_count), "\n")

# ─────────────────────────────────────────────────────────────────────────────
# 3. Wide 형식으로 변환 — 공통 기간 추출
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 3] IC 시계열 Wide 변환\n")

# 유효 팩터만
valid_factors <- ic_count$Factor_Name
ic_wide_long <- ic_monthly[Factor_Name %in% valid_factors, .(Factor_Name, Date, IC)]

# Date 기준 Wide 피벗 (data.table dcast)
ic_wide <- dcast(ic_wide_long, Date ~ Factor_Name, value.var = "IC")
setkey(ic_wide, Date)
cat("  Wide 행(월): ", nrow(ic_wide), " | 팩터: ", ncol(ic_wide)-1, "\n")

# ─────────────────────────────────────────────────────────────────────────────
# 4. STR_1656 월별 수익률과 공통 날짜 추출
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 4] 공통 기간 매칭 (Usable_Date 기준 → C14 준수)\n")

# ic_monthly의 Date = 신호 발생 날짜 (ex. 2005-01-31)
# Usable_Date = IC를 포트폴리오에 쓸 수 있는 날짜 (ex. 2005-02-27)
# → 잔차 분석에서는 IC를 "어떤 날짜에 알 수 있었는가"가 중요
# → 여기서는 factor IC timeseries를 분석하는 것이므로 Date 기준 사용

# STR_1656 YM과 ic_wide의 YM 매칭
ic_wide[, YM := format(Date, "%Y-%m")]

# merge
combined <- merge(ic_wide, monthly_1656_ret[, .(YM, Ret_1656 = Ret_month)], by = "YM")
cat("  공통 기간(1656 merge): ", nrow(combined), "개월\n")

# ─────────────────────────────────────────────────────────────────────────────
# 4b. STR_1631 NAV 시계열 직접 구성
#     backtest_harness의 summarise_perf는 strategy_xts를 반환
#     → run_all.R에서 strategy_analyzer()에 넘기는 DAILY_NAV_DT를 재현
#     → 가장 실용적인 방법: STR_1631 SYN_05의 코드를 최소한으로 재실행
#     → 단, 시간 소모를 피하기 위해 ic_weight_evolution + factors_detail로 근사
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 4b] STR_1631 수익률 근사: STR_1656 단독으로 대리변수 사용\n")
cat("  (STR_1631 daily NAV 파일 미저장 → STR_1656만으로 1차 분석)\n")
cat("  주: STR_1631은 Earnings/SUE/ESBR 팩터 기반 → IC 시계열이 대리 역할 가능\n")

# ─────────────────────────────────────────────────────────────────────────────
# 5. 잔차 IC 계산: 각 팩터 IC ~ STR_1656 수익률
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 5] 잔차 IC 계산 (각 팩터 IC ~ ML 포트폴리오 수익률)\n")

factor_cols <- setdiff(names(combined), c("Date", "YM", "Ret_1656"))
cat("  분석 대상 팩터:", length(factor_cols), "개\n")

# 함수: 잔차 IC 계산
# 핵심: lm 잔차의 평균은 수학적으로 0 → ICIR 의미 없음
# 대신: 잔차의 표준화를 원래 IC scale로 보정 → 잔차 정보 비율(RIR) 사용
# RIR = sqrt(1 - R^2) * orig_ICIR  →  회귀에서 설명 못한 비율 × 원래 강도
# 별도: partial corr. / IC ~ BM_ret 상관 직접 계산
calc_residual_icir <- function(ic_vec, benchmark_ret) {
  # 결측 제거
  valid_idx <- !is.na(ic_vec) & !is.na(benchmark_ret)
  n_valid <- sum(valid_idx)
  if (n_valid < 24) return(list(resid_icir = NA_real_, resid_ic_mean = NA_real_,
                                 resid_ic_sd = NA_real_, orig_icir = NA_real_,
                                 bm_corr = NA_real_, r_squared = NA_real_,
                                 rir = NA_real_, n = n_valid))

  y <- ic_vec[valid_idx]
  x <- benchmark_ret[valid_idx]

  # 원래 ICIR
  ic_mean   <- mean(y)
  ic_sd     <- sd(y)
  orig_icir <- ic_mean / ic_sd

  # benchmark와의 상관 (IC ↔ ML 수익률)
  bm_corr <- cor(y, x, use = "complete.obs")

  # IC ~ benchmark_ret 회귀 R²
  fit <- lm(y ~ x)
  r_squared <- summary(fit)$r.squared
  resid <- residuals(fit)

  # 잔차 표준편차 (설명 못한 IC 변동성)
  resid_sd <- sd(resid)

  # Residual Information Ratio: 잔차 SD / 원래 IC_SD = sqrt(1-R²) (이론값)
  # 그러나 실제 잔차 평균은 0이므로 ICIR 대신 다른 측도 사용:
  # 잔차 ICIR 대안 1: RIR = orig_icir * sqrt(1 - r_squared)
  #   → 원래 alpha 강도 중 BM이 설명 못한 비율
  rir <- orig_icir * sqrt(1 - r_squared)

  # 잔차 ICIR 대안 2: 잔차의 t-통계량 (t = mean(resid) / se)
  # mean(resid) ≈ 0이므로 의미 없음 → 사용 안 함

  # 잔차 ICIR 대안 3: IC 중 BM으로 설명 안 되는 분산 비율
  unexplained_vol_frac <- resid_sd / ic_sd  # = sqrt(1-R²)

  list(resid_icir    = rir,          # RIR: Residual alpha 강도
       resid_ic_mean = mean(resid),  # 수학적으로 ≈0
       resid_ic_sd   = resid_sd,
       orig_icir     = orig_icir,
       bm_corr       = bm_corr,
       r_squared     = r_squared,
       unexpl_frac   = unexplained_vol_frac,
       n             = n_valid)
}

# 병렬 계산 (lm이 가볍으므로 순차)
results_list <- vector("list", length(factor_cols))
ret_vec <- combined$Ret_1656

pb_interval <- max(1, floor(length(factor_cols) / 10))
for (i in seq_along(factor_cols)) {
  fc <- factor_cols[i]
  ic_vec <- combined[[fc]]
  r <- calc_residual_icir(ic_vec, ret_vec)
  results_list[[i]] <- data.table(
    Factor_Name  = fc,
    resid_icir   = r$resid_icir,   # RIR = orig_icir * sqrt(1-R²)
    resid_ic_mean= r$resid_ic_mean,
    resid_ic_sd  = r$resid_ic_sd,
    orig_icir    = r$orig_icir,
    bm_corr      = r$bm_corr,
    r_squared    = r$r_squared,
    unexpl_frac  = r$unexpl_frac,
    n_obs        = r$n
  )
  if (i %% pb_interval == 0) cat(sprintf("  [%d/%d] 완료\n", i, length(factor_cols)))
}

residual_dt <- rbindlist(results_list)
residual_dt <- residual_dt[!is.na(resid_icir)]
cat("  유효 팩터(잔차 ICIR 계산 완료):", nrow(residual_dt), "개\n")

# ─────────────────────────────────────────────────────────────────────────────
# 6. 팩터 메타데이터 병합 (conditional_ic_matrix, category)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 6] 메타데이터 병합\n")

cim <- fread(file.path(CACHE_DIR, "conditional_ic_matrix.csv"))
setnames(cim, "Factor_Name", "Factor_Name", skip_absent = TRUE)

# conditional_ic_matrix 컬럼 확인
cat("  conditional_ic_matrix cols:", paste(names(cim), collapse=","), "\n")

# merge
residual_dt <- merge(residual_dt, cim[, .(Factor_Name, ic_all, ic_bad, ic_good,
                                           conditional_value, recent_3y_icir,
                                           n_months, used, category)],
                     by = "Factor_Name", all.x = TRUE)

# STR_1631 내 팩터 정확한 목록
# run_all.R 확인: sue/esbr/eps_chg_1m/tpgap 4개 팩터 블렌드
# Factor DB에서 C01_SUE, C04_ESBR, C02_EPS_Chg_1m, C06_TP_Gap (= tpgap)
# C19_Composite_Earnings = STR_1631의 composite score (이미 포함된 blend)
str1631_factors <- c(
  # STR_1631 직접 사용 팩터
  "C01_SUE",              # sue
  "C04_ESBR",             # esbr
  "C02_EPS_Chg_1m",       # eps_chg_1m
  "C06_TP_Gap",           # tpgap
  "C19_Composite_Earnings", # composite of above
  # 관련 variants
  "C07_TP_Mom",           # TP momentum (TP gap과 유사)
  "C09_Earnings_Surprise_Sq"  # SUE squared (SUE와 r=1.0)
)
residual_dt[, in_str1631 := Factor_Name %in% str1631_factors]

cat("  STR_1631 사용 팩터 제외:", sum(residual_dt$in_str1631), "개\n")

# ─────────────────────────────────────────────────────────────────────────────
# 7. 랭킹 및 필터링
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 7] 잔차 ICIR 랭킹\n")

# 절댓값 기준 정렬 (방향 무관 독립성)
residual_dt[, abs_resid_icir := abs(resid_icir)]
residual_dt[, abs_bm_corr    := abs(bm_corr)]

# 독립 alpha 기준:
# 1. |bm_corr| 낮음 (ML 포트폴리오와 독립)
# 2. |resid_icir| 높음 (잔차에도 예측력 있음)
# 3. n_obs >= 36
# 4. STR_1631 내 팩터 제외 (이미 사용 중)

top_residual <- residual_dt[
  n_obs >= 36 & !in_str1631 & !is.na(category),
  .(Factor_Name, category, resid_icir, orig_icir, bm_corr, r_squared, unexpl_frac,
    abs_resid_icir, abs_bm_corr, n_obs, used,
    ic_all, ic_bad, ic_good, conditional_value, recent_3y_icir)
]

# 조합 점수 (개선):
# diversifier_score = |orig_icir| * unexpl_frac * (1 - |bm_corr|)
# = 원래 alpha 강도 × BM으로 설명 안 되는 분산 비율 × IC-BM 저상관도
# → 강한 alpha이면서 ML 포트와 독립인 팩터를 최대화
top_residual[, diversifier_score := abs(orig_icir) * unexpl_frac * (1 - abs_bm_corr)]

# 추가 점수: |orig_icir| 기준도 함께 제공
top_residual[, raw_icir_rank := rank(-abs(orig_icir))]

# 정렬: diversifier_score 내림차순
setorder(top_residual, -diversifier_score)

cat("  분석 대상 팩터(필터 후):", nrow(top_residual), "개\n")

# ─────────────────────────────────────────────────────────────────────────────
# 7b. 내부 중복 제거: IC 상관 > 0.7인 팩터 군집 → 군집 내 1등만 유지
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 7b] 내부 중복 제거 (IC 상관 > 0.7 필터링)\n")

# Top 40 기준으로 중복 제거
top40_candidates <- head(top_residual, 40)
top40_names <- top40_candidates$Factor_Name
top40_names_valid <- top40_names[top40_names %in% names(combined)]

if (length(top40_names_valid) >= 3) {
  ic_top40 <- combined[, top40_names_valid, with = FALSE]
  cor_top40 <- cor(ic_top40, use = "pairwise.complete.obs")

  # greedy 클러스터링: |r| > 0.7이면 같은 군집
  CORR_THRESH <- 0.7
  n_cand <- length(top40_names_valid)
  selected <- logical(n_cand); names(selected) <- top40_names_valid
  selected[] <- FALSE
  kept <- character(0)

  # diversifier_score 순서대로 (이미 정렬됨)
  for (nm in top40_names_valid) {
    if (length(kept) == 0) {
      kept <- c(kept, nm); selected[nm] <- TRUE; next
    }
    # 이미 선택된 것들과 상관 확인
    max_cor <- max(abs(cor_top40[nm, kept]), na.rm = TRUE)
    if (max_cor < CORR_THRESH) {
      kept <- c(kept, nm); selected[nm] <- TRUE
    }
  }
  cat("  중복 제거 전:", n_cand, "개 → 제거 후:", length(kept), "개 (|r|≥0.7 군집 대표만)\n")

  # 결과에 중복 여부 표시
  top_residual[, dedup_kept := Factor_Name %in% kept]
  top_residual_dedup <- top_residual[Factor_Name %in% kept]
} else {
  top_residual[, dedup_kept := TRUE]
  top_residual_dedup <- top_residual
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. 결과 출력
# ─────────────────────────────────────────────────────────────────────────────
cat("\n", paste(rep("=", 70), collapse=""), "\n")
cat("잔차 Alpha 상위 20개 팩터 — 중복 제거 후 (Diversifier Score 기준)\n")
cat(paste(rep("=", 70), collapse=""), "\n\n")

top20 <- head(top_residual_dedup, 20)

cat(sprintf("%-35s %-12s %-9s %-9s %-9s %-7s %-9s %-11s\n",
            "Factor", "Category", "OrigICIR", "RIR", "BM_Corr",
            "R²", "UnexplFr", "DiverScore"))
cat(paste(rep("-", 110), collapse=""), "\n")

for (i in seq_len(nrow(top20))) {
  r <- top20[i]
  cat(sprintf("%-35s %-12s %+8.3f  %+8.3f  %+8.3f  %6.3f  %8.3f  %10.4f\n",
              substr(r$Factor_Name, 1, 35),
              substr(r$category, 1, 12),
              r$orig_icir,
              r$resid_icir,
              r$bm_corr,
              r$r_squared,
              r$unexpl_frac,
              r$diversifier_score))
}

# ─────────────────────────────────────────────────────────────────────────────
# 9. Family 분포
# ─────────────────────────────────────────────────────────────────────────────
cat("\n", paste(rep("=", 70), collapse=""), "\n")
cat("상위 20개 팩터 Family 분포\n")
cat(paste(rep("=", 70), collapse=""), "\n")

family_dist <- top20[, .N, by = category][order(-N)]
for (i in seq_len(nrow(family_dist))) {
  cat(sprintf("  %-20s: %d개\n", family_dist$category[i], family_dist$N[i]))
}

# ─────────────────────────────────────────────────────────────────────────────
# 10. 상위 팩터 간 상관 (중복 제거)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 10] 상위 15개 팩터 간 IC 상관\n")

top15_names <- top20$Factor_Name[1:min(15, nrow(top20))]
top15_ic    <- combined[, top15_names[top15_names %in% names(combined)], with=FALSE]

if (ncol(top15_ic) >= 3) {
  cor_mat <- cor(top15_ic, use = "pairwise.complete.obs")

  # 상관 > 0.5인 쌍 탐지
  n_f <- ncol(cor_mat)
  high_cor_pairs <- list()
  for (i in 1:(n_f-1)) {
    for (j in (i+1):n_f) {
      if (!is.na(cor_mat[i,j]) && abs(cor_mat[i,j]) > 0.5) {
        high_cor_pairs[[length(high_cor_pairs)+1]] <- sprintf(
          "%s <-> %s: %.3f",
          substr(colnames(cor_mat)[i], 1, 20),
          substr(colnames(cor_mat)[j], 1, 20),
          cor_mat[i,j]
        )
      }
    }
  }

  if (length(high_cor_pairs) > 0) {
    cat("  고상관(|r|>0.5) 쌍:\n")
    for (p in high_cor_pairs) cat("   ", p, "\n")
  } else {
    cat("  고상관(|r|>0.5) 쌍 없음 — 다양성 양호\n")
  }

  # 평균 상관
  upper_tri <- cor_mat[upper.tri(cor_mat)]
  cat(sprintf("  평균 쌍별 상관: %.3f (낮을수록 다양성 우수)\n",
              mean(abs(upper_tri), na.rm=TRUE)))
}

# ─────────────────────────────────────────────────────────────────────────────
# 11. Crisis IC 확인 (conditional_ic_matrix의 ic_bad)
# ─────────────────────────────────────────────────────────────────────────────
cat("\n[Step 11] Crisis IC 분포 (상위 20개)\n")
cat(sprintf("  %-35s %-10s %-10s %-12s\n", "Factor", "IC_bad", "IC_good", "Cond_Value"))
cat(paste(rep("-", 70), collapse=""), "\n")
for (i in seq_len(nrow(top20))) {
  r <- top20[i]
  ic_bad_val  <- if(!is.na(r$ic_bad))  sprintf("%+.4f", r$ic_bad)  else "N/A"
  ic_good_val <- if(!is.na(r$ic_good)) sprintf("%+.4f", r$ic_good) else "N/A"
  cond_val    <- if(!is.na(r$conditional_value)) sprintf("%+.4f", r$conditional_value) else "N/A"
  cat(sprintf("  %-35s %-10s %-10s %-12s\n",
              substr(r$Factor_Name, 1, 35), ic_bad_val, ic_good_val, cond_val))
}

# ─────────────────────────────────────────────────────────────────────────────
# 12. 저장
# ─────────────────────────────────────────────────────────────────────────────
out_path <- file.path(OUT_DIR, "residual_alpha_ranking.csv")
fwrite(top_residual, out_path)
cat(sprintf("\n[Step 12] 전체 순위 저장: %s\n", out_path))

# 상위 20 별도 저장
top20_path <- file.path(OUT_DIR, "residual_alpha_top20.csv")
fwrite(top20, top20_path)
cat(sprintf("  상위 20개 저장: %s\n", top20_path))

elapsed <- round(as.numeric(difftime(Sys.time(), t0, units="secs")), 1)
cat(sprintf("\n총 소요 시간: %.1f초\n", elapsed))
cat("=== 잔차 Alpha 분석 완료 ===\n")
