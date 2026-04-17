## ============================================================
## Forge: Scout 가설 H1/H2/H3 팩트체크 (long-format Factor DB 대응)
## 날짜: 2026-03-29
## ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
CACHE <- file.path(ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE, "factor_db")

# ── STEP 1: conditional_ic_matrix ──────────────────────────
cat("=== STEP 1: conditional_ic_matrix 로드 ===\n")
ic_mat <- fread(file.path(CACHE, "conditional_ic_matrix.csv"))
setnames(ic_mat, colnames(ic_mat)[1], "Factor_Name")

TARGET_FACTORS <- c("D43_Skewness", "Q07_Earnings_Stability",
                    "V14_EBIT_EV", "AC21_CF_to_Accrual_Ratio",
                    "M25_Earnings_Mom_Streak", "AC22_Accrual_Volatility",
                    "M10_Intermediate_Mom", "C19_Composite_Earnings")

tgt <- ic_mat[Factor_Name %in% TARGET_FACTORS]
tgt[, icir     := recent_3y_icir]
tgt[, alg_pass := icir >= 0.20]
tgt[, is_defense_by_ic := ic_bad > ic_good]
tgt[, bad_good_ratio   := ic_bad / ic_good]

cat("\n--- 대상 팩터 ICIR 요약 ---\n")
print(tgt[order(-icir), .(Factor_Name, icir, alg_pass, ic_bad, ic_good, bad_good_ratio, is_defense_by_ic, n_months, category)])

# ── STEP 2: Factor DB 구조 확인 ────────────────────────────
cat("\n=== STEP 2: Factor DB 구조 확인 ===\n")
all_files <- sort(list.files(FACTOR_DB_DIR, pattern="^factor_db_2[0-9]{5}\\.parquet$", full.names=TRUE))
sample_dt <- as.data.table(read_parquet(all_files[1]))
cat("컬럼:", paste(colnames(sample_dt), collapse=", "), "\n")
cat("고유 Factor_Name 수:", length(unique(sample_dt$Factor_Name)), "\n")
cat("Factor_Name 예시:", paste(head(unique(sample_dt$Factor_Name), 5), collapse=", "), "\n")
# Z_Score_Aligned 컬럼 확인
zscore_col <- if("Z_Score_Aligned" %in% colnames(sample_dt)) "Z_Score_Aligned" else
              if("Z_Score" %in% colnames(sample_dt)) "Z_Score" else NULL
cat("사용할 점수 컬럼:", zscore_col, "\n")

# ── STEP 3: 전 기간 로드 + wide pivot ──────────────────────
cat("\n=== STEP 3: 전 기간 Factor DB 로드 (rbindlist once) ===\n")
FACTOR_CODES_SHORT <- c("D43_Skewness","Q07_Earnings_Stability",
                         "V14_EBIT_EV","AC21_CF_to_Accrual_Ratio",
                         "M25_Earnings_Mom_Streak","AC22_Accrual_Volatility",
                         "M10_Intermediate_Mom","C19_Composite_Earnings")

load_cols <- c("Date","Ticker","Factor_Name", zscore_col)
dt_list <- lapply(all_files, function(f) {
  tryCatch({
    dt <- as.data.table(read_parquet(f, col_select = intersect(load_cols, colnames(read_parquet(f)))))
    dt[Factor_Name %in% FACTOR_CODES_SHORT]
  }, error=function(e) NULL)
})
dt_long <- rbindlist(dt_list, fill=TRUE)
cat("로드 완료: rows =", nrow(dt_long), "\n")
cat("고유 팩터:", paste(unique(dt_long$Factor_Name), collapse=", "), "\n")
cat("기간:", min(dt_long$Date), "~", max(dt_long$Date), "\n")

# wide pivot
setnames(dt_long, zscore_col, "Z")
dt_wide <- dcast(dt_long, Date + Ticker ~ Factor_Name, value.var="Z")
cat("Wide 테이블: rows =", nrow(dt_wide), ", cols =", ncol(dt_wide), "\n")

# ── STEP 4: 상관 행렬 ──────────────────────────────────────
cat("\n=== STEP 4: 팩터 간 상관 행렬 ===\n")
factor_cols <- FACTOR_CODES_SHORT[FACTOR_CODES_SHORT %in% colnames(dt_wide)]
cat("분석 가능 팩터:", paste(factor_cols, collapse=", "), "\n")

if(length(factor_cols) >= 2) {
  cor_data <- dt_wide[, ..factor_cols]
  cor_mat <- cor(cor_data, use="pairwise.complete.obs")

  # 코드만 남기기
  short <- sapply(strsplit(colnames(cor_mat), "_"), `[`, 1)
  rownames(cor_mat) <- colnames(cor_mat) <- short
  cat("\n[상관 행렬]\n")
  print(round(cor_mat, 3))

  cat("\n[핵심 페어 상관]\n")
  pairs_check <- list(
    H1_D43_Q07   = c("D43","Q07"),
    H2_V14_AC21  = c("V14","AC21"),
    H2_V14_M25   = c("V14","M25"),
    H2_AC21_M25  = c("AC21","M25"),
    H3_AC22_M10  = c("AC22","M10"),
    H3_AC22_Q07  = c("AC22","Q07"),
    H1_D43_C19   = c("D43","C19"),
    H1_Q07_C19   = c("Q07","C19"),
    H3_AC22_C19  = c("AC22","C19"),
    H2_V14_C19   = c("V14","C19")
  )
  for(nm in names(pairs_check)) {
    f1 <- pairs_check[[nm]][1]; f2 <- pairs_check[[nm]][2]
    if(f1 %in% rownames(cor_mat) && f2 %in% rownames(cor_mat)) {
      val <- cor_mat[f1, f2]
      flag <- if(abs(val) > 0.7) "!! HIGH" else if(abs(val) > 0.5) "! MED" else "OK"
      cat(sprintf("  %-20s %s <-> %s: %+.3f  [%s]\n", nm, f1, f2, val, flag))
    }
  }
}

# ── STEP 5: 종합 판정 ──────────────────────────────────────
cat("\n", strrep("=",60), "\n")
cat("=== STEP 5: 가설별 GO/CAUTION/BLOCK 종합 판정 ===\n")
cat(strrep("=",60), "\n\n")

get_f <- function(nm) tgt[Factor_Name == nm]

verdict <- function(icir_pass, is_def_ok, corr_ok, role) {
  # BLOCK 조건: ALG 실패
  if(!icir_pass) return("BLOCK (ICIR<0.20)")
  # CAUTION: defense 역할인데 ic_bad 우위 없음
  if(role == "defense" && !is_def_ok) return("CAUTION (defense 역할 미확인: ic_good>ic_bad)")
  # CAUTION: 상관 문제
  if(!corr_ok) return("CAUTION (상관 과다)")
  return("GO")
}

# H1: D43 + Q07 (defense)
d43 <- get_f("D43_Skewness"); q07 <- get_f("Q07_Earnings_Stability")
h1_cor <- if("D43" %in% rownames(cor_mat) && "Q07" %in% rownames(cor_mat)) cor_mat["D43","Q07"] else NA
h1_cor_c19_d43 <- if("D43" %in% rownames(cor_mat) && "C19" %in% rownames(cor_mat)) cor_mat["D43","C19"] else NA
h1_cor_c19_q07 <- if("Q07" %in% rownames(cor_mat) && "C19" %in% rownames(cor_mat)) cor_mat["Q07","C19"] else NA

cat("[H1: D43 + Q07 — defense 역할]\n")
cat(sprintf("  D43 Skewness     : ICIR=%.3f  ALG=%s  ic_bad=%.4f ic_good=%.4f  is_def=%s\n",
  d43$icir, ifelse(d43$alg_pass,"PASS","FAIL"), d43$ic_bad, d43$ic_good, d43$is_defense_by_ic))
cat(sprintf("  Q07 Earn_Stab    : ICIR=%.3f  ALG=%s  ic_bad=%.4f ic_good=%.4f  is_def=%s\n",
  q07$icir, ifelse(q07$alg_pass,"PASS","FAIL"), q07$ic_bad, q07$ic_good, q07$is_defense_by_ic))
cat(sprintf("  D43-Q07 상관     : %+.3f\n", h1_cor))
cat(sprintf("  D43-C19(STR1555) : %+.3f\n", h1_cor_c19_d43))
cat(sprintf("  Q07-C19(STR1555) : %+.3f\n", h1_cor_c19_q07))
h1_corr_ok <- !is.na(h1_cor) && abs(h1_cor) < 0.7
h1_def_ok  <- d43$is_defense_by_ic | q07$is_defense_by_ic  # 한쪽이라도
h1_v <- verdict(all(c(d43$alg_pass, q07$alg_pass)), h1_def_ok, h1_corr_ok, "defense")
cat(sprintf("  >> H1 판정: %s\n\n", h1_v))

# H2: V14 + AC21 + M25 (core_alpha)
v14 <- get_f("V14_EBIT_EV"); ac21 <- get_f("AC21_CF_to_Accrual_Ratio"); m25 <- get_f("M25_Earnings_Mom_Streak")
h2_v14_ac21 <- if("V14" %in% rownames(cor_mat) && "AC21" %in% rownames(cor_mat)) cor_mat["V14","AC21"] else NA
h2_v14_m25  <- if("V14" %in% rownames(cor_mat) && "M25" %in% rownames(cor_mat))  cor_mat["V14","M25"]  else NA
h2_ac21_m25 <- if("AC21" %in% rownames(cor_mat) && "M25" %in% rownames(cor_mat)) cor_mat["AC21","M25"] else NA
h2_v14_c19  <- if("V14" %in% rownames(cor_mat) && "C19" %in% rownames(cor_mat))  cor_mat["V14","C19"]  else NA

cat("[H2: V14 + AC21 + M25 — core_alpha 역할]\n")
cat(sprintf("  V14 EBIT_EV      : ICIR=%.3f  ALG=%s  ic_bad=%.4f ic_good=%.4f\n",
  v14$icir, ifelse(v14$alg_pass,"PASS","FAIL"), v14$ic_bad, v14$ic_good))
cat(sprintf("  AC21 CF_Accrual  : ICIR=%.3f  ALG=%s  ic_bad=%.4f ic_good=%.4f\n",
  ac21$icir, ifelse(ac21$alg_pass,"PASS","FAIL"), ac21$ic_bad, ac21$ic_good))
cat(sprintf("  M25 Earn_Streak  : ICIR=%.3f  ALG=%s  ic_bad=%.4f ic_good=%.4f\n",
  m25$icir, ifelse(m25$alg_pass,"PASS","FAIL"), m25$ic_bad, m25$ic_good))
cat(sprintf("  V14-AC21 상관    : %+.3f\n", h2_v14_ac21))
cat(sprintf("  V14-M25 상관     : %+.3f\n", h2_v14_m25))
cat(sprintf("  AC21-M25 상관    : %+.3f\n", h2_ac21_m25))
cat(sprintf("  V14-C19(STR1555) : %+.3f\n", h2_v14_c19))
h2_all_pass <- all(c(v14$alg_pass, ac21$alg_pass, m25$alg_pass))
h2_max_cor  <- max(abs(c(h2_v14_ac21, h2_v14_m25, h2_ac21_m25)), na.rm=TRUE)
h2_corr_ok  <- h2_max_cor < 0.7
h2_v <- verdict(h2_all_pass, TRUE, h2_corr_ok, "core_alpha")
cat(sprintf("  >> H2 판정: %s  (최대 내부 상관 %.3f)\n\n", h2_v, h2_max_cor))

# H3: AC22 + M10 (defense)
ac22 <- get_f("AC22_Accrual_Volatility"); m10 <- get_f("M10_Intermediate_Mom")
h3_cor <- if("AC22" %in% rownames(cor_mat) && "M10" %in% rownames(cor_mat)) cor_mat["AC22","M10"] else NA
h3_ac22_c19 <- if("AC22" %in% rownames(cor_mat) && "C19" %in% rownames(cor_mat)) cor_mat["AC22","C19"] else NA
h3_m10_c19  <- if("M10" %in% rownames(cor_mat) && "C19" %in% rownames(cor_mat))  cor_mat["M10","C19"]  else NA
h3_ac22_ac21 <- if("AC22" %in% rownames(cor_mat) && "AC21" %in% rownames(cor_mat)) cor_mat["AC22","AC21"] else NA

cat("[H3: AC22 + M10 — defense 역할]\n")
cat(sprintf("  AC22 Accr_Vol    : ICIR=%.3f  ALG=%s  ic_bad=%.4f ic_good=%.4f  is_def=%s\n",
  ac22$icir, ifelse(ac22$alg_pass,"PASS","FAIL"), ac22$ic_bad, ac22$ic_good, ac22$is_defense_by_ic))
cat(sprintf("  M10 Interm_Mom   : ICIR=%.3f  ALG=%s  ic_bad=%.4f ic_good=%.4f  is_def=%s\n",
  m10$icir, ifelse(m10$alg_pass,"PASS","FAIL"), m10$ic_bad, m10$ic_good, m10$is_defense_by_ic))
cat(sprintf("  AC22-M10 상관    : %+.3f\n", h3_cor))
cat(sprintf("  AC22-C19 상관    : %+.3f\n", h3_ac22_c19))
cat(sprintf("  M10-C19 상관     : %+.3f\n", h3_m10_c19))
cat(sprintf("  AC22-AC21(H2중복): %+.3f\n", h3_ac22_ac21))
h3_def_ok  <- ac22$is_defense_by_ic | m10$is_defense_by_ic
h3_corr_ok <- !is.na(h3_cor) && abs(h3_cor) < 0.7
h3_v <- verdict(all(c(ac22$alg_pass, m10$alg_pass)), h3_def_ok, h3_corr_ok, "defense")
cat(sprintf("  >> H3 판정: %s\n\n", h3_v))

cat(strrep("=",60), "\n")
cat("팩트체크 완료\n")
