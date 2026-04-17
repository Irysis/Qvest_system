##==============================================================================
## S0 Debate R1 — Quant 실측 검증: L31_Vol_Concentration, L40_VWAP_Spread
## H_1670: Liquidity Diversifier 2팩터 ICIR 교차검증
## PIT: load_month_factors() 경유, Usable_Date 기반
##==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
CACHE_DIR <- file.path(ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")

cat("=== S0 Debate R1: L31/L40 ICIR 실측 검증 ===\n")

## 1. Factor DB 전체 로드 (1회, rbindlist once pattern) ----------------------
cat("[1] Factor DB 로드 중...\n")

parquet_files <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
cat(sprintf("  총 %d개 월간 파일\n", length(parquet_files)))

# 필요 컬럼만 로드: Ticker, Date, Factor_Name, Z_Score_Aligned, Usable_Date, Fwd_Ret_1M
needed_cols <- c("Ticker", "Date", "Factor_Name", "Z_Score_Aligned", "Usable_Date", "Fwd_Ret_1M")

read_one <- function(f) {
  tryCatch({
    dt <- as.data.table(read_parquet(f, col_select = any_of(needed_cols)))
    dt[Factor_Name %in% c("L31_Vol_Concentration", "L40_VWAP_Spread", "C19_Earnings_Quality")]
  }, error = function(e) NULL)
}

chunks <- lapply(parquet_files, read_one)
fdb <- rbindlist(chunks, fill = TRUE)
setkey(fdb, Date, Ticker)
cat(sprintf("  로드 완료: %d행, 팩터=%s\n", nrow(fdb),
            paste(unique(fdb$Factor_Name), collapse=", ")))

## 2. C14 준수: Usable_Date <= sig_date (현재 날짜 2026-04-12) ----------------
if ("Usable_Date" %in% names(fdb)) {
  fdb <- fdb[!is.na(Usable_Date) & Usable_Date <= as.Date("2026-04-12")]
}

## 3. 월별 IC 계산 (스피어만) ------------------------------------------------
cat("[2] 월별 IC 계산 중...\n")

compute_monthly_ic <- function(dt_factor, factor_nm) {
  sub <- dt_factor[Factor_Name == factor_nm & !is.na(Z_Score_Aligned) & !is.na(Fwd_Ret_1M)]
  if (nrow(sub) == 0) return(data.table())
  ic_dt <- sub[, {
    if (.N >= 10) {
      ic_val <- tryCatch(cor(Z_Score_Aligned, Fwd_Ret_1M, method = "spearman", use = "complete.obs"),
                         error = function(e) NA_real_)
    } else {
      ic_val <- NA_real_
    }
    .(IC = ic_val, N = .N)
  }, by = Date]
  ic_dt[, Factor_Name := factor_nm]
  ic_dt
}

ic_L31 <- compute_monthly_ic(fdb, "L31_Vol_Concentration")
ic_L40 <- compute_monthly_ic(fdb, "L40_VWAP_Spread")
ic_C19 <- compute_monthly_ic(fdb, "C19_Earnings_Quality")

## 4. ICIR 전기간 계산 -------------------------------------------------------
cat("[3] 전기간 ICIR 계산...\n")

icir_stat <- function(ic_dt, nm) {
  valid <- ic_dt[!is.na(IC)]
  if (nrow(valid) < 12) return(list(factor=nm, n_months=nrow(valid), mean_ic=NA, sd_ic=NA, icir=NA))
  list(
    factor   = nm,
    n_months = nrow(valid),
    mean_ic  = round(mean(valid$IC), 4),
    sd_ic    = round(sd(valid$IC), 4),
    icir     = round(mean(valid$IC) / sd(valid$IC) * sqrt(12), 4)  # annualized
  )
}

stat_L31 <- icir_stat(ic_L31, "L31_Vol_Concentration")
stat_L40 <- icir_stat(ic_L40, "L40_VWAP_Spread")
stat_C19 <- icir_stat(ic_C19, "C19_Earnings_Quality")

cat("\n--- 전기간 ICIR 실측 ---\n")
cat(sprintf("L31_Vol_Concentration: ICIR=%.3f, IC(mean)=%.4f, IC(sd)=%.4f, N=%d months\n",
    stat_L31$icir, stat_L31$mean_ic, stat_L31$sd_ic, stat_L31$n_months))
cat(sprintf("L40_VWAP_Spread:       ICIR=%.3f, IC(mean)=%.4f, IC(sd)=%.4f, N=%d months\n",
    stat_L40$icir, stat_L40$mean_ic, stat_L40$sd_ic, stat_L40$n_months))
cat(sprintf("C19_Earnings_Quality:  ICIR=%.3f, IC(mean)=%.4f, IC(sd)=%.4f, N=%d months\n",
    stat_C19$icir, stat_C19$mean_ic, stat_C19$sd_ic, stat_C19$n_months))

## 5. L31 x L40 내부 상관 ---------------------------------------------------
cat("\n[4] L31 x L40 내부 상관 계산...\n")

# 월별 IC 시계열 간 상관
ic_both <- merge(ic_L31[!is.na(IC), .(Date, IC_L31=IC)],
                 ic_L40[!is.na(IC), .(Date, IC_L40=IC)], by="Date")
corr_L31_L40_ic <- if(nrow(ic_both) >= 12) round(cor(ic_both$IC_L31, ic_both$IC_L40), 3) else NA

# 팩터 값 수준 상관 (같은 날짜, 같은 종목)
fdb_wide <- dcast(fdb[Factor_Name %in% c("L31_Vol_Concentration","L40_VWAP_Spread") & !is.na(Z_Score_Aligned)],
                  Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
if (all(c("L31_Vol_Concentration","L40_VWAP_Spread") %in% names(fdb_wide))) {
  corr_L31_L40_factor <- round(cor(fdb_wide$L31_Vol_Concentration, fdb_wide$L40_VWAP_Spread,
                                    use="complete.obs", method="spearman"), 3)
} else {
  corr_L31_L40_factor <- NA
}
cat(sprintf("L31 x L40 IC 시계열 상관: %.3f\n", corr_L31_L40_ic))
cat(sprintf("L31 x L40 팩터값 상관(스피어만): %.3f\n", corr_L31_L40_factor))

## 6. C19와 상관 계산 --------------------------------------------------------
cat("\n[5] C19_Earnings_Quality 교차상관...\n")
ic_c19_both_L31 <- merge(ic_L31[!is.na(IC), .(Date, IC_L31=IC)],
                          ic_C19[!is.na(IC), .(Date, IC_C19=IC)], by="Date")
ic_c19_both_L40 <- merge(ic_L40[!is.na(IC), .(Date, IC_L40=IC)],
                          ic_C19[!is.na(IC), .(Date, IC_C19=IC)], by="Date")

corr_L31_C19 <- if(nrow(ic_c19_both_L31)>=12) round(cor(ic_c19_both_L31$IC_L31, ic_c19_both_L31$IC_C19), 3) else NA
corr_L40_C19 <- if(nrow(ic_c19_both_L40)>=12) round(cor(ic_c19_both_L40$IC_L40, ic_c19_both_L40$IC_C19), 3) else NA

cat(sprintf("L31 x C19 IC 시계열 상관: %.3f\n", corr_L31_C19))
cat(sprintf("L40 x C19 IC 시계열 상관: %.3f\n", corr_L40_C19))

## 7. Stress period IC (6대 위기) -------------------------------------------
cat("\n[6] 6대 위기 구간 IC 실측...\n")

stress_periods <- list(
  list(name="GFC (2008-09~2009-02)",  start=as.Date("2008-09-01"), end=as.Date("2009-02-28")),
  list(name="유럽재정위기 (2011-08~2011-12)", start=as.Date("2011-08-01"), end=as.Date("2011-12-31")),
  list(name="차이나쇼크 (2015-08~2015-09)", start=as.Date("2015-08-01"), end=as.Date("2015-09-30")),
  list(name="COVID (2020-02~2020-03)",  start=as.Date("2020-02-01"), end=as.Date("2020-03-31")),
  list(name="금리충격 (2022-01~2022-09)", start=as.Date("2022-01-01"), end=as.Date("2022-09-30")),
  list(name="레고랜드 (2022-10~2022-11)", start=as.Date("2022-10-01"), end=as.Date("2022-11-30"))
)

stress_results <- list()
for (sp in stress_periods) {
  ic_l31_stress <- ic_L31[Date >= sp$start & Date <= sp$end & !is.na(IC)]
  ic_l40_stress <- ic_L40[Date >= sp$start & Date <= sp$end & !is.na(IC)]
  stress_results[[sp$name]] <- list(
    period = sp$name,
    L31_mean_IC = if(nrow(ic_l31_stress)>0) round(mean(ic_l31_stress$IC), 4) else NA,
    L40_mean_IC = if(nrow(ic_l40_stress)>0) round(mean(ic_l40_stress$IC), 4) else NA,
    L31_n = nrow(ic_l31_stress),
    L40_n = nrow(ic_l40_stress)
  )
  cat(sprintf("  %s: L31=%.4f (n=%d), L40=%.4f (n=%d)\n",
      sp$name,
      ifelse(is.na(stress_results[[sp$name]]$L31_mean_IC), NA, stress_results[[sp$name]]$L31_mean_IC),
      stress_results[[sp$name]]$L31_n,
      ifelse(is.na(stress_results[[sp$name]]$L40_mean_IC), NA, stress_results[[sp$name]]$L40_mean_IC),
      stress_results[[sp$name]]$L40_n))
}

## 8. 주장 수치 vs 실측 비교 ------------------------------------------------
cat("\n=== 주장 vs 실측 비교 ===\n")
cat(sprintf("L31 ICIR: 주장=0.990, 실측=%.3f → 차이=%.3f\n",
    stat_L31$icir, 0.990 - stat_L31$icir))
cat(sprintf("L40 ICIR: 주장=0.826, 실측=%.3f → 차이=%.3f\n",
    stat_L40$icir, 0.826 - stat_L40$icir))
cat(sprintf("L31 IC(mean): 주장=0.032, 실측=%.4f\n", stat_L31$mean_ic))
cat(sprintf("L40 IC(mean): 주장=0.057, 실측=%.4f\n", stat_L40$mean_ic))

## 9. 결과 저장 --------------------------------------------------------------
result_list <- list(
  timestamp = as.character(Sys.time()),
  factors = list(
    L31 = stat_L31,
    L40 = stat_L40,
    C19 = stat_C19
  ),
  correlations = list(
    L31_x_L40_IC_series = corr_L31_L40_ic,
    L31_x_L40_factor_level = corr_L31_L40_factor,
    L31_x_C19_IC_series = corr_L31_C19,
    L40_x_C19_IC_series = corr_L40_C19
  ),
  stress_periods = stress_results,
  claim_vs_actual = list(
    L31_claimed_icir = 0.990,
    L31_actual_icir = stat_L31$icir,
    L40_claimed_icir = 0.826,
    L40_actual_icir = stat_L40$icir,
    L31_claimed_ic = 0.032,
    L31_actual_ic = stat_L31$mean_ic,
    L40_claimed_ic = 0.057,
    L40_actual_ic = stat_L40$mean_ic
  )
)

out_path <- file.path(ROOT, "stage_artifacts", "verify_L31_L40_icir_result.json")
write_json(result_list, out_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[완료] 결과 저장: %s\n", out_path))
