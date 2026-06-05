cat("=== Regime Dynamic Blend S1: VDplus + MLRA + Q07 Defense ===\n")
## 국면별 동적 배분 시뮬레이션
## STR_1631 VDplus 70% + STR_1656 MLRA 15% + STR_1662a Q07 Defense 15%
## Variant A/B/C vs 정적 기준선
## PIT: C5 - regime_score t-1 lag 적용

library(data.table)
library(zoo)
options(scipen = 999)

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
OUT_DIR <- file.path(ROOT, "04_Research/strategies/regime_dynamic_blend/output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ============================================================
# 1. 데이터 로드 (1회)
# ============================================================
cat("\n[1] 데이터 로드...\n")

## STR_1631 VDplus (일별 → 월별 변환)
pg2 <- fread(file.path(ROOT, "04_Research/strategies/STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv"))
pg2[, Date := as.Date(Date)]
setkey(pg2, Date)
pg2[, YM := format(Date, "%Y-%m")]
# 월말 수익률: 복리 수익률 집계
pg2_m <- pg2[, .(ret_core = prod(1 + Ret_vdp) - 1), by = YM]
pg2_m[, Date := as.Date(paste0(YM, "-01"))]
setkey(pg2_m, Date)
cat(sprintf("  STR_1631 VDplus: %d 개월 | %s ~ %s\n",
            nrow(pg2_m), min(pg2_m$YM), max(pg2_m$YM)))

## STR_1656 MLRA S1_B (일별 → 월별 변환)
ml <- fread(file.path(ROOT, "04_Research/strategies/STR_1656_MLRA/output/nav_S1_B.csv"))
ml[, Date := as.Date(Date)]
setkey(ml, Date)
ml[, YM := format(Date, "%Y-%m")]
ml_m <- ml[, .(ret_ml = prod(1 + Strategy_Ret) - 1), by = YM]
ml_m[, Date := as.Date(paste0(YM, "-01"))]
setkey(ml_m, Date)
cat(sprintf("  STR_1656 MLRA: %d 개월 | %s ~ %s\n",
            nrow(ml_m), min(ml_m$YM), max(ml_m$YM)))

## STR_1662a Q07 Defense (월별, 이미 월별)
def <- fread(file.path(ROOT, "04_Research/strategies/STR_1662_defense_D25_Q07/output/performance_STR_1662a.csv"))
def[, Date := as.Date(Date)]
setkey(def, Date)
def[, YM := format(Date, "%Y-%m")]
# 마지막 행 제거 (불완전 월)
def <- def[order(Date)]
def <- def[1:(.N - 1)]  # 마지막 행 제거
def_m <- def[, .(ret_def = sum(port_ret)), by = YM]  # 이미 월별이므로 sum (단일 obs/월)
def_m[, Date := as.Date(paste0(YM, "-01"))]
setkey(def_m, Date)
cat(sprintf("  STR_1662a Q07: %d 개월 | %s ~ %s\n",
            nrow(def_m), min(def_m$YM), max(def_m$YM)))

## Regime score (macro_regime.parquet)
reg <- arrow::read_parquet(file.path(ROOT, ".cache/macro_regime.parquet"))
setDT(reg)
reg[, Date := as.Date(Date)]
reg[, YM := format(Date, "%Y-%m")]
reg_m <- reg[, .(regime_score = mean(Macro_Risk_Score, na.rm = TRUE)), by = YM]
reg_m[, Date := as.Date(paste0(YM, "-01"))]
setkey(reg_m, Date)
cat(sprintf("  Regime score: %d 개월 | %s ~ %s\n",
            nrow(reg_m), min(reg_m$YM), max(reg_m$YM)))

# ============================================================
# 2. 데이터 병합 (공통 기간)
# ============================================================
cat("\n[2] 데이터 병합 (공통 기간)...\n")

# 공통 기간: 2008-03 ~ 2026-03 (regime 마지막: 2026-03)
dt <- merge(pg2_m[, .(YM, Date, ret_core)],
            ml_m[, .(YM, ret_ml)],
            by = "YM")
dt <- merge(dt, def_m[, .(YM, ret_def)], by = "YM")
dt <- merge(dt, reg_m[, .(YM, regime_score)], by = "YM")
dt <- dt[order(Date)]

cat(sprintf("  병합 후: %d 개월 | %s ~ %s\n",
            nrow(dt), min(dt$YM), max(dt$YM)))
cat(sprintf("  Regime 범위: %.1f ~ %.1f\n",
            min(dt$regime_score), max(dt$regime_score)))

# ============================================================
# 3. C5: regime_score t-1 lag 적용 (PIT 필수)
# ============================================================
cat("\n[3] C5 PIT: regime_score t-1 lag 적용...\n")
n <- nrow(dt)
# t-1 lag: 전월 regime score로 이번 달 가중 결정
dt[, regime_lag := c(NA_real_, regime_score[1:(n-1)])]
# 첫 번째 행(lag NA)은 제거
dt <- dt[!is.na(regime_lag)]
cat(sprintf("  lag 적용 후: %d 개월 | %s ~ %s\n",
            nrow(dt), min(dt$YM), max(dt$YM)))

# ============================================================
# 4. 가중 계산 함수
# ============================================================

## 성과 계산 유틸
calc_perf <- function(rets, label = "") {
  n    <- length(rets)
  cagr <- (prod(1 + rets))^(12/n) - 1
  vol  <- sd(rets) * sqrt(12)
  sr   <- cagr / vol
  nav  <- cumprod(1 + rets)
  dd   <- nav / cummax(nav) - 1
  mdd  <- min(dd)
  list(
    Label  = label,
    N_mon  = n,
    CAGR   = round(cagr * 100, 2),
    Vol    = round(vol * 100, 2),
    SR     = round(sr, 3),
    MDD    = round(mdd * 100, 2),
    Calmar = round(cagr / abs(mdd), 3),
    WinRate = round(mean(rets > 0) * 100, 1)
  )
}

# ============================================================
# 5. 정적 기준선 (Static 70/15/15)
# ============================================================
cat("\n[4] 정적 기준선 계산...\n")
dt[, ret_static := 0.70 * ret_core + 0.15 * ret_ml + 0.15 * ret_def]
perf_static <- calc_perf(dt$ret_static, "Static_70_15_15")

# ============================================================
# 6. Variant A: 2-state 전환 (regime >= 40 → CAUTION/CRISIS)
# ============================================================
cat("[5] Variant A: 2-state 전환...\n")
dt[, `:=`(
  w_core_A = fifelse(regime_lag < 40, 0.60, 0.70),
  w_ml_A   = fifelse(regime_lag < 40, 0.25, 0.10),
  w_def_A  = fifelse(regime_lag < 40, 0.15, 0.20)
)]
dt[, ret_A := w_core_A * ret_core + w_ml_A * ret_ml + w_def_A * ret_def]
perf_A <- calc_perf(dt$ret_A, "Variant_A_2state")

cat("  CALM(r<40):", sum(dt$regime_lag < 40), "개월  /  CAUTION/CRISIS(r>=40):", sum(dt$regime_lag >= 40), "개월\n")

# ============================================================
# 7. Variant B: 3-state 차등 배분
# ============================================================
cat("[6] Variant B: 3-state 차등 배분...\n")
dt[, state_B := fcase(
  regime_lag < 25,                      "CALM",
  regime_lag >= 25 & regime_lag < 60,   "CAUTION",
  regime_lag >= 60,                      "CRISIS"
)]
dt[state_B == "CALM",    `:=`(w_core_B = 0.55, w_ml_B = 0.30, w_def_B = 0.15, w_cash_B = 0.00)]
dt[state_B == "CAUTION", `:=`(w_core_B = 0.70, w_ml_B = 0.15, w_def_B = 0.15, w_cash_B = 0.00)]
dt[state_B == "CRISIS",  `:=`(w_core_B = 0.65, w_ml_B = 0.05, w_def_B = 0.20, w_cash_B = 0.10)]
# Cash = 0% 수익률 (현금 보유)
dt[, ret_B := w_core_B * ret_core + w_ml_B * ret_ml + w_def_B * ret_def + w_cash_B * 0]
perf_B <- calc_perf(dt$ret_B, "Variant_B_3state")

cat("  CALM:", sum(dt$state_B == "CALM"),
    "  CAUTION:", sum(dt$state_B == "CAUTION"),
    "  CRISIS:", sum(dt$state_B == "CRISIS"), "\n")

# ============================================================
# 8. Variant C: 연속 가중 (linear interpolation)
# ============================================================
cat("[7] Variant C: 연속 가중...\n")
dt[, w_ml_C   := pmax(0.05, 0.30 - regime_lag * 0.005)]
dt[, w_def_C  := pmin(0.25, 0.10 + regime_lag * 0.003)]
dt[, w_cash_C := pmax(0.00, (regime_lag - 50) * 0.004)]
dt[, w_core_C := 1 - w_ml_C - w_def_C - w_cash_C]
# Core 최소 0 보장
dt[w_core_C < 0, `:=`(w_core_C = 0, w_ml_C = 0.05, w_def_C = 0.25, w_cash_C = pmax(0, 1 - 0.05 - 0.25))]
dt[, ret_C := w_core_C * ret_core + w_ml_C * ret_ml + w_def_C * ret_def + w_cash_C * 0]
perf_C <- calc_perf(dt$ret_C, "Variant_C_linear")

cat(sprintf("  w_core: %.2f~%.2f  w_ml: %.2f~%.2f  w_def: %.2f~%.2f  w_cash: %.2f~%.2f\n",
            min(dt$w_core_C), max(dt$w_core_C),
            min(dt$w_ml_C), max(dt$w_ml_C),
            min(dt$w_def_C), max(dt$w_def_C),
            min(dt$w_cash_C), max(dt$w_cash_C)))

# ============================================================
# 9. 개별 전략 성과 (참고용)
# ============================================================
perf_core <- calc_perf(dt$ret_core, "STR_1631_VDplus")
perf_ml   <- calc_perf(dt$ret_ml,   "STR_1656_MLRA_S1B")
perf_def  <- calc_perf(dt$ret_def,  "STR_1662a_Q07Def")

# ============================================================
# 10. 결과 테이블
# ============================================================
cat("\n[8] 결과 집계...\n")
results <- rbindlist(list(
  as.data.table(perf_core),
  as.data.table(perf_ml),
  as.data.table(perf_def),
  as.data.table(perf_static),
  as.data.table(perf_A),
  as.data.table(perf_B),
  as.data.table(perf_C)
))

# 출력
cat("\n=====================================================\n")
cat("  국면별 동적 배분 시뮬레이션 결과\n")
cat("=====================================================\n")
print(results, row.names = FALSE)

# ============================================================
# 11. 리스크 분석 (Sharpe 개선 분해)
# ============================================================
cat("\n[9] 핵심 지표 비교 (정적 기준 대비)...\n")
base_sr  <- perf_static$SR
base_mdd <- perf_static$MDD
base_cagr <- perf_static$CAGR

for(v in list(list(perf_A, "A"), list(perf_B, "B"), list(perf_C, "C"))) {
  p <- v[[1]]; nm <- v[[2]]
  d_sr   <- p$SR - base_sr
  d_mdd  <- p$MDD - base_mdd
  d_cagr <- p$CAGR - base_cagr
  cat(sprintf("  Variant %s: SR %+.3f | CAGR %+.2f%% | MDD %+.2f%%\n",
              nm, d_sr, d_cagr, d_mdd))
}

# ============================================================
# 12. 월별 배분 가중 저장
# ============================================================
cat("\n[10] 결과 저장...\n")

# 성과 테이블 저장
fwrite(results, file.path(OUT_DIR, "regime_blend_comparison.csv"))

# 월별 수익률 + 가중 저장
monthly_detail <- dt[, .(
  YM, Date, regime_score, regime_lag, state_B,
  ret_core, ret_ml, ret_def,
  ret_static, ret_A, ret_B, ret_C,
  w_core_B, w_ml_B, w_def_B, w_cash_B,
  w_core_C, w_ml_C, w_def_C, w_cash_C
)]
fwrite(monthly_detail, file.path(OUT_DIR, "regime_blend_monthly.csv"))

# ============================================================
# 13. NAV 곡선 저장 (차트용)
# ============================================================
nav_dt <- dt[, .(
  YM, Date,
  NAV_core   = cumprod(1 + ret_core) * 100,
  NAV_ml     = cumprod(1 + ret_ml) * 100,
  NAV_def    = cumprod(1 + ret_def) * 100,
  NAV_static = cumprod(1 + ret_static) * 100,
  NAV_A      = cumprod(1 + ret_A) * 100,
  NAV_B      = cumprod(1 + ret_B) * 100,
  NAV_C      = cumprod(1 + ret_C) * 100
)]
fwrite(nav_dt, file.path(OUT_DIR, "regime_blend_nav.csv"))

# ============================================================
# 14. 최적 variant 선정
# ============================================================
cat("\n[11] 최적 Variant 선정...\n")
dyn_perfs <- list(A = perf_A, B = perf_B, C = perf_C)
best_nm <- names(which.max(sapply(dyn_perfs, function(x) x$SR)))
best <- dyn_perfs[[best_nm]]

cat(sprintf("\n  최적: Variant %s\n", best_nm))
cat(sprintf("  SR: %.3f (정적 %.3f, 개선 %+.3f)\n",
            best$SR, perf_static$SR, best$SR - perf_static$SR))
cat(sprintf("  CAGR: %.2f%% (정적 %.2f%%)\n", best$CAGR, perf_static$CAGR))
cat(sprintf("  MDD: %.2f%% (정적 %.2f%%)\n", best$MDD, perf_static$MDD))

# ============================================================
# 15. 요약 JSON 저장
# ============================================================
summary_json <- sprintf('{
  "strategy": "Regime_Dynamic_Blend",
  "common_period": "%s ~ %s",
  "n_months": %d,
  "pit_note": "C5: regime_score t-1 lag applied",
  "ml_note": "STR_1656 S1 hard_fail (MDD -75%%). Signal diversification only.",
  "static": {"CAGR": %s, "SR": %s, "MDD": %s},
  "variant_A": {"CAGR": %s, "SR": %s, "MDD": %s, "delta_SR": %s},
  "variant_B": {"CAGR": %s, "SR": %s, "MDD": %s, "delta_SR": %s},
  "variant_C": {"CAGR": %s, "SR": %s, "MDD": %s, "delta_SR": %s},
  "best_variant": "%s",
  "recommendation": "S1 시뮬레이션 완료. 정식 전략 진행 전 S0 가설 수립 필요."
}',
  min(dt$YM), max(dt$YM), nrow(dt),
  perf_static$CAGR, perf_static$SR, perf_static$MDD,
  perf_A$CAGR, perf_A$SR, perf_A$MDD, round(perf_A$SR - perf_static$SR, 3),
  perf_B$CAGR, perf_B$SR, perf_B$MDD, round(perf_B$SR - perf_static$SR, 3),
  perf_C$CAGR, perf_C$SR, perf_C$MDD, round(perf_C$SR - perf_static$SR, 3),
  best_nm
)
writeLines(summary_json, file.path(OUT_DIR, "regime_blend_summary.json"))

cat("\n[완료] 출력 파일:\n")
cat("  - regime_blend_comparison.csv\n")
cat("  - regime_blend_monthly.csv\n")
cat("  - regime_blend_nav.csv\n")
cat("  - regime_blend_summary.json\n")
cat("\n=== 완료 ===\n")
