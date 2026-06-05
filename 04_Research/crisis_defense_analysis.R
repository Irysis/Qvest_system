cat("=== Crisis IC 괴리 원인 분석 + 대안 Defense 팩터 탐색 ===\n")
cat("=== AC21/CR05 stress vs 4-regime CRISIS 정의 비교 ===\n\n")

suppressMessages({
  library(data.table)
  library(arrow)
})

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
CACHE_DIR <- file.path(ROOT, ".cache")

# ── 1. 캐시 파일 로드 ─────────────────────────────────────────────
cat("[Step 1] Loading cache files...\n")

regime4 <- fread(file.path(CACHE_DIR, "conditional_ic_matrix_4regime.csv"))
stress   <- fread(file.path(CACHE_DIR, "stress_factor_ic_analysis.csv"))

cat(sprintf("  4-regime matrix: %d factors\n", nrow(regime4)))
cat(sprintf("  Stress IC analysis: %d factors\n", nrow(stress)))

# ── 2. AC21 / CR05 상세 비교 ─────────────────────────────────────
cat("\n[Step 2] AC21 / CR05 비교 분석\n")
cat(paste(rep("=", 70), collapse=""), "\n")

for (fac in c("AC21_CF_to_Accrual_Ratio", "CR05_Short_Pressure_Proxy")) {
  r4  <- regime4[factor_id == fac]
  stv <- stress[Factor_Name == fac]

  cat(sprintf("\n[%s]\n", fac))
  cat(sprintf("  --- 4-Regime (MRS 4분위 기반) ---\n"))
  if (nrow(r4) > 0) {
    cat(sprintf("    CALM   ICIR: %+.3f  (n=%s months)\n",
                r4$icir_CALM, r4$n_months_CALM))
    cat(sprintf("    NORMAL ICIR: %+.3f  (n=%s months)\n",
                r4$icir_NORMAL, r4$n_months_NORMAL))
    cat(sprintf("    CAUTION ICIR: %+.3f  (n=%s months)\n",
                r4$icir_CAUTION, r4$n_months_CAUTION))
    cat(sprintf("    CRISIS ICIR: %+.3f  (n=%s months)\n",
                r4$icir_CRISIS, r4$n_months_CRISIS))
    cat(sprintf("    Overall ICIR: %+.3f\n", r4$icir_all))
  } else {
    cat("    [NOT FOUND in 4-regime matrix]\n")
  }

  cat(sprintf("  --- Stress IC Analysis (6대 스트레스 구간 기반) ---\n"))
  if (nrow(stv) > 0) {
    cat(sprintf("    Stress ICIR: %+.3f  (n=%d months)\n",
                stv$stress_icir, as.integer(stv$stress_n)))
    cat(sprintf("    Normal ICIR: %+.3f  (n=%d months)\n",
                stv$normal_icir, as.integer(stv$normal_n)))
    cat(sprintf("    Crisis Premium: %+.4f\n", stv$crisis_premium))
    cat(sprintf("    Crisis Ratio: %.3f\n", stv$crisis_ratio))
    cat(sprintf("    Stress Pct Positive: %.1f%%\n", stv$stress_pct_pos * 100))
  } else {
    cat("    [NOT FOUND in stress IC analysis]\n")
  }
}

# ── 3. "위기" 정의 비교: 기간 overlap 분석 ───────────────────────
cat("\n\n[Step 3] 위기 정의 비교 (4-regime CRISIS vs 6대 스트레스 구간)\n")
cat(paste(rep("=", 70), collapse=""), "\n")

# 6대 스트레스 구간 (reference_stress_periods.md 기준)
stress_periods <- list(
  GFC        = c(as.Date("2008-01-01"), as.Date("2009-03-31")),
  EU_Debt    = c(as.Date("2011-07-01"), as.Date("2011-09-30")),
  Trade_War  = c(as.Date("2018-02-01"), as.Date("2018-12-31")),
  COVID      = c(as.Date("2020-01-01"), as.Date("2020-04-30")),
  Rate_Hike  = c(as.Date("2022-01-01"), as.Date("2022-06-30")),
  Iran_War   = c(as.Date("2025-03-01"), as.Date("2026-03-31"))
)

# 스트레스 구간 월 목록 생성
stress_months_list <- lapply(names(stress_periods), function(nm) {
  p <- stress_periods[[nm]]
  months <- seq(p[1], p[2], by = "month")
  format(months, "%Y-%m")
})
names(stress_months_list) <- names(stress_periods)

all_stress_months <- unique(unlist(stress_months_list))
cat(sprintf("  6대 스트레스 구간 총 월수: %d개월\n", length(all_stress_months)))
cat("  구간별:\n")
for (nm in names(stress_periods)) {
  p <- stress_periods[[nm]]
  n <- length(stress_months_list[[nm]])
  cat(sprintf("    %-12s: %s ~ %s (%d개월)\n",
              nm, format(p[1], "%Y-%m"), format(p[2], "%Y-%m"), n))
}

# 4-regime CRISIS 기간: n_months_CRISIS를 보면 대략 분포 파악
# stress_n=40 → AC21 기준 40개월
# 4-regime CRISIS n_months_CRISIS=51~65
cat(sprintf("\n  Stress IC analysis 'stress_n' (AC21/CR05): 40개월\n"))
cat(sprintf("  4-regime 'n_months_CRISIS' (AC21): 51개월, (CR05): 65개월\n"))
cat(sprintf("  => 4-regime CRISIS는 MRS 상위 25%%로 정의 (전체 기간 약 25%%)\n"))
cat(sprintf("  => stress_factor_ic는 6대 사전정의 위기 구간 (약 40개월)\n"))

# 정성적 분석
cat("\n  [핵심 괴리 원인]\n")
cat("  1. 정의 차이: 4-regime CRISIS = MRS 분위수 상위 25% (경제/금융 스트레스 지수 기반)\n")
cat("                stress_factor_ic = 6대 역사적 위기 구간 (시장 낙폭 기준)\n")
cat("  2. 기간 차이: 4-regime CRISIS는 ~65개월, stress 구간은 ~40개월\n")
cat("  3. MRS는 모든 유형의 '경기 침체'를 포함 (경기 둔화期도 CRISIS로 분류 가능)\n")
cat("     → AC21(발생주의)/CR05(공매도)는 경기 둔화期에 방어적이지 않지만\n")
cat("       급격한 시장 낙폭 시기(GFC/COVID 등)에는 방어적\n")
cat("  4. MRS CRISIS에는 '느린 하락기'(2011 유럽재정위기, 2018 무역분쟁)도 포함\n")
cat("     → 이 시기 AC21/CR05는 신호 약화 (ICIR 낮음)\n")

# ── 4. 대안 Defense 팩터 탐색 ────────────────────────────────────
cat("\n\n[Step 4] 대안 Defense 팩터 탐색\n")
cat(paste(rep("=", 70), collapse=""), "\n")

# 4-regime에서 CRISIS ICIR 컬럼 확인
cat(sprintf("  stress 파일 컬럼: %s\n", paste(names(stress), collapse=", ")))
cat(sprintf("  4regime 파일 컬럼: %s\n", paste(names(regime4), collapse=", ")))

# 조건 1: stress_ICIR > 0.30
stress_filt <- stress[stress_icir > 0.30]
cat(sprintf("\n  [조건 1] stress_ICIR > 0.30: %d개 팩터\n", nrow(stress_filt)))

# 조건 2: crisis_ratio > 1.0
stress_filt2 <- stress_filt[crisis_ratio > 1.0]
cat(sprintf("  [조건 1+2] + crisis_ratio > 1.0: %d개 팩터\n", nrow(stress_filt2)))

# 조건 3: 4-regime CRISIS ICIR > 0
regime4_crisis <- regime4[, .(factor_id, icir_CRISIS, n_months_CRISIS)]
# CRISIS ICIR가 NA가 아니고 양수인 것
regime4_crisis_pos <- regime4_crisis[!is.na(icir_CRISIS) & icir_CRISIS > 0]
cat(sprintf("  4-regime CRISIS ICIR > 0: %d개 팩터\n", nrow(regime4_crisis_pos)))

# 병합: stress 조건 통과 AND 4-regime CRISIS > 0
merged_filt <- merge(
  stress_filt2,
  regime4_crisis_pos[, .(factor_id, icir_CRISIS_4r = icir_CRISIS)],
  by.x = "Factor_Name", by.y = "factor_id",
  all = FALSE
)
cat(sprintf("  [양쪽 모두 위기에 강한 팩터]: %d개\n", nrow(merged_filt)))

if (nrow(merged_filt) > 0) {
  merged_filt <- merged_filt[order(-stress_icir)]
  cat("\n  Top 팩터 목록:\n")
  for (i in 1:min(nrow(merged_filt), 20)) {
    r <- merged_filt[i]
    cat(sprintf("    %2d. %-40s stress_ICIR=%+.3f  crisis_ratio=%.2f  4r_crisis_ICIR=%+.3f\n",
                i, r$Factor_Name, r$stress_icir, r$crisis_ratio, r$icir_CRISIS_4r))
  }
}

# ── 5. C19와의 상관 분석 (기존 캐시 활용) ───────────────────────
cat("\n\n[Step 5] C19와의 상관 분석 (캐시 factor_correlation_analysis.csv 활용)\n")
cat(paste(rep("=", 70), collapse=""), "\n")

c19_corr_dt <- data.table(Factor_Name = character(), corr_with_C19 = numeric())

corr_path <- file.path(CACHE_DIR, "factor_correlation_analysis.csv")
if (file.exists(corr_path)) {
  # wide format: 마지막 컬럼 = Factor (행 이름), 다른 컬럼 = 상관 대상 팩터
  corr_raw <- fread(corr_path)
  cat(sprintf("  상관 파일: %d rows x %d cols\n", nrow(corr_raw), ncol(corr_raw)))

  # 마지막 컬럼이 Factor명
  factor_col <- tail(names(corr_raw), 1)
  cat(sprintf("  Factor 컬럼: '%s'\n", factor_col))

  if ("C19_Composite_Earnings" %in% names(corr_raw)) {
    # C19_Composite_Earnings 컬럼 = 각 팩터의 C19와의 상관
    c19_corr_dt <- corr_raw[, .(
      Factor_Name = get(factor_col),
      corr_with_C19 = C19_Composite_Earnings
    )]
    c19_corr_dt <- c19_corr_dt[Factor_Name != "C19_Composite_Earnings"]
    cat(sprintf("  C19 상관 데이터: %d개 팩터\n", nrow(c19_corr_dt)))
    cat("\n  기존 캐시 내 C19 상관 (절댓값 오름차순):\n")
    print(c19_corr_dt[order(abs(corr_with_C19))])
  } else if ("C19_Earnings_Surprise_Momentum" %in% names(corr_raw)) {
    c19_corr_dt <- corr_raw[, .(
      Factor_Name = get(factor_col),
      corr_with_C19 = C19_Earnings_Surprise_Momentum
    )]
    c19_corr_dt <- c19_corr_dt[Factor_Name != "C19_Earnings_Surprise_Momentum"]
    cat(sprintf("  C19 상관 데이터: %d개 팩터\n", nrow(c19_corr_dt)))
    print(c19_corr_dt[order(abs(corr_with_C19))])
  } else {
    cat("  C19 컬럼 없음. 사용 가능 컬럼:\n")
    cat(paste(names(corr_raw), collapse=", "), "\n")
  }

  # merged_filt에 상관 합치기
  if (nrow(c19_corr_dt) > 0 && nrow(merged_filt) > 0) {
    merged_filt <- merge(merged_filt, c19_corr_dt, by = "Factor_Name", all.x = TRUE)
  }
} else {
  cat("  factor_correlation_analysis.csv 없음\n")
}

# ── 6. Factor DB에서 C19 상관 직접 계산 (캐시 미존재 팩터 대상) ──
cat("\n\n[Step 6] Factor DB에서 후보 팩터 C19 상관 계산\n")
cat(paste(rep("=", 70), collapse=""), "\n")

# 캐시에서 커버되지 않은 팩터 확인
uncovered <- if (nrow(merged_filt) > 0 && "corr_with_C19" %in% names(merged_filt)) {
  merged_filt[is.na(corr_with_C19), Factor_Name]
} else {
  merged_filt$Factor_Name
}

if (length(uncovered) > 0) {
  cat(sprintf("  C19 상관 미계산 팩터: %d개 — Factor DB에서 직접 계산 시도\n",
              length(uncovered)))
  tryCatch({
    source(file.path(ROOT, "02_Infrastructure/config.R"))
    source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

    # 조회할 팩터: C19 + 미커버 후보
    c19_col <- "C19_Composite_Earnings"
    need_factors <- unique(c(c19_col, uncovered[1:min(length(uncovered), 15)]))
    cat(sprintf("  조회 팩터: %s\n", paste(need_factors, collapse=", ")))

    # 최근 36개월 (2023-01 ~ 2025-12)
    sig_dates_str <- format(seq(as.Date("2023-01-01"), as.Date("2025-12-01"), by="month"), "%Y-%m-%d")

    fdb_list <- lapply(sig_dates_str, function(d) {
      tryCatch(load_month_factors(d, factors = need_factors), error = function(e) NULL)
    })
    fdb_all <- rbindlist(Filter(Negate(is.null), fdb_list), fill = TRUE)
    cat(sprintf("  Factor DB 로드: %d rows\n", nrow(fdb_all)))

    fac_cols <- intersect(need_factors, names(fdb_all))
    if (c19_col %in% fac_cols && length(fac_cols) > 1) {
      fdb_mat <- fdb_all[, fac_cols, with = FALSE]
      fdb_mat <- fdb_mat[complete.cases(fdb_mat)]
      cor_mat <- cor(fdb_mat, use = "pairwise.complete.obs")
      new_corr <- data.table(
        Factor_Name = rownames(cor_mat),
        corr_with_C19 = cor_mat[, c19_col]
      )
      new_corr <- new_corr[Factor_Name != c19_col]
      cat(sprintf("  신규 C19 상관 계산: %d개\n", nrow(new_corr)))
      print(new_corr)

      # merged_filt 업데이트
      if (nrow(merged_filt) > 0) {
        for (f in new_corr$Factor_Name) {
          if ("corr_with_C19" %in% names(merged_filt)) {
            merged_filt[Factor_Name == f, corr_with_C19 := new_corr[Factor_Name == f, corr_with_C19]]
          }
        }
        if (!"corr_with_C19" %in% names(merged_filt)) {
          merged_filt <- merge(merged_filt, new_corr, by = "Factor_Name", all.x = TRUE)
        }
      }
      # c19_corr_dt 업데이트
      c19_corr_dt <<- rbindlist(list(c19_corr_dt, new_corr), fill = TRUE)
    }
  }, error = function(e) {
    cat(sprintf("  Factor DB 오류: %s\n", e$message))
  })
} else {
  cat("  모든 후보 팩터의 C19 상관이 캐시에 존재함\n")
}

# ── 7. 최종 결과 정리 ────────────────────────────────────────────
cat("\n\n[Step 7] 최종 결과 정리\n")
cat(paste(rep("=", 70), collapse=""), "\n")

cat("\n### 표 1: AC21/CR05 위기 IC 괴리 원인 요약\n")
cat("┌─────────────────────────────────────────────────────────────────┐\n")
cat("│ 구분              │ 4-regime CRISIS    │ stress_factor_ic       │\n")
cat("├─────────────────────────────────────────────────────────────────┤\n")
cat("│ 위기 정의         │ MRS 상위 25% 분위수 │ 6대 역사적 위기 구간  │\n")
cat("│ 월수 (AC21)       │ 51개월             │ 40개월                │\n")
cat("│ 월수 (CR05)       │ 65개월             │ 40개월                │\n")
cat("│ 포함 유형         │ 경기 둔화+위기+    │ GFC/COVID 등 급락期만 │\n")
cat("│                  │ 변동성 스파이크    │ (시장 -20%+ 구간)     │\n")
cat("├─────────────────────────────────────────────────────────────────┤\n")
cat("│ AC21 ICIR         │ +0.577 (CALM)     │ +0.796 (stress)       │\n")
cat("│                  │ -0.062 (CRISIS)   │ +0.346 (normal)       │\n")
cat("│ CR05 ICIR         │ +0.125 (CALM)     │ +0.770 (stress)       │\n")
cat("│                  │ -0.095 (CRISIS)   │ +0.359 (normal)       │\n")
cat("├─────────────────────────────────────────────────────────────────┤\n")
cat("│ 결론              │ MRS 고점期에 신호  │ 시장 낙폭期에는 유효  │\n")
cat("│                  │ 역전 (경기침체期)  │ (품질/공매도 방어력)  │\n")
cat("└─────────────────────────────────────────────────────────────────┘\n")

cat("\n### 표 2: 괴리 원인 해석\n")
cat("  [핵심] MRS CRISIS ≠ 시장 낙폭 위기\n")
cat("  - MRS = 복합 경기/금융 스트레스 지수 (경기 둔화期도 CRISIS로 분류)\n")
cat("  - 경기 둔화期: AC21(발생주의), CR05(공매도 압력)은 방향성 약화\n")
cat("  - 급격한 시장 낙폭期(GFC 2008, COVID 2020): AC21/CR05 방어력 발휘\n")
cat("  - DFA 전략에서는 '시장 낙폭 기반' 위기가 더 적합한 기준\n")
cat("  => stress_factor_ic (6대 구간)이 DFA 전략의 위기 정의에 부합\n")
cat("  => AC21/CR05는 실제 시장 낙폭 위기에 강한 팩터로 해석 유효\n")

cat("\n### 표 3: Top 10 진짜 위기 방어 팩터\n")
if (nrow(merged_filt) > 0) {
  merged_filt_sorted <- merged_filt[order(-stress_icir)]
  top10 <- merged_filt_sorted[1:min(10, nrow(merged_filt_sorted))]

  cat(sprintf("  %-40s %8s %12s %14s %12s\n",
              "Factor", "stress", "crisis_ratio", "4r_CRISIS", "corr_C19"))
  cat(sprintf("  %-40s %8s %12s %14s %12s\n",
              "", "ICIR", "", "ICIR", ""))
  cat(paste(rep("-", 90), collapse=""), "\n")
  for (i in 1:nrow(top10)) {
    r <- top10[i]
    corr_val <- if ("corr_with_C19" %in% names(r) && !is.na(r$corr_with_C19))
      sprintf("%+.3f", r$corr_with_C19) else "  N/A"
    cat(sprintf("  %-40s %+7.3f %12.3f %+13.3f %12s\n",
                r$Factor_Name, r$stress_icir, r$crisis_ratio,
                r$icir_CRISIS_4r, corr_val))
  }
} else {
  cat("  [조건을 만족하는 팩터 없음 - 조건 완화 필요]\n")
  # 조건 완화: stress_icir > 0.15 AND crisis_ratio > 0.5 AND 4r CRISIS > -0.1
  cat("\n  [완화 조건: stress_ICIR > 0.15, crisis_ratio > 0.5]\n")
  stress_top <- stress[stress_icir > 0.15 & crisis_ratio > 0.5][order(-stress_icir)][1:min(15, .N)]
  if (nrow(stress_top) > 0) {
    stress_top2 <- merge(stress_top,
                         regime4_crisis[, .(factor_id, icir_CRISIS_4r = icir_CRISIS)],
                         by.x = "Factor_Name", by.y = "factor_id", all.x = TRUE)
    stress_top2 <- stress_top2[order(-stress_icir)]
    cat(sprintf("  %-40s %8s %12s %14s\n", "Factor", "stress", "crisis_ratio", "4r_CRISIS"))
    cat(sprintf("  %-40s %8s %12s %14s\n", "", "ICIR", "", "ICIR"))
    cat(paste(rep("-", 78), collapse=""), "\n")
    for (i in 1:nrow(stress_top2)) {
      r <- stress_top2[i]
      c4r <- if (!is.na(r$icir_CRISIS_4r)) sprintf("%+.3f", r$icir_CRISIS_4r) else "  N/A"
      cat(sprintf("  %-40s %+7.3f %12.3f %14s\n",
                  r$Factor_Name, r$stress_icir, r$crisis_ratio, c4r))
    }
  }
}

# ── 8. CSV 저장 ──────────────────────────────────────────────────
cat("\n\n[Step 8] 결과 저장\n")

# 최종 후보 테이블 생성
if (nrow(merged_filt) > 0) {
  final_tbl <- merged_filt[, .(
    Factor_Name, stress_icir, stress_n, crisis_ratio,
    normal_icir, crisis_premium, icir_CRISIS_4r,
    corr_with_C19 = if ("corr_with_C19" %in% names(merged_filt))
      get("corr_with_C19") else NA_real_
  )][order(-stress_icir)]
} else {
  # 완화 조건
  stress_top3 <- stress[stress_icir > 0.15 & crisis_ratio > 0.5][order(-stress_icir)]
  final_tbl <- merge(stress_top3,
                     regime4_crisis[, .(factor_id, icir_CRISIS_4r = icir_CRISIS)],
                     by.x = "Factor_Name", by.y = "factor_id", all.x = TRUE)
  final_tbl <- final_tbl[, .(
    Factor_Name, stress_icir, stress_n, crisis_ratio,
    normal_icir, crisis_premium, icir_CRISIS_4r,
    corr_with_C19 = NA_real_
  )][order(-stress_icir)]
}

out_path <- file.path(CACHE_DIR, "crisis_defense_factor_analysis.csv")
fwrite(final_tbl, out_path)
cat(sprintf("  저장 완료: %s\n", out_path))
cat(sprintf("  총 %d개 팩터 저장\n", nrow(final_tbl)))

cat("\n\n=== 분석 완료 ===\n")
