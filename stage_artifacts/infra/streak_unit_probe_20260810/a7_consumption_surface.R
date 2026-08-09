#==============================================================================
# a7_consumption_surface.R — 후보들이 **실제 저장된 값**에서 어떻게 보이는가
#  (재현 계산이 아니라 factor_db 산출물 실측. 존재가 아니라 정체를 본다)
#
#  T1 C11/M25 : 저장된 Raw/Z 분포가 '일간 스케일'인가 (판별식의 산출물 측 확인)
#  T2 SE02    : Coverage 살아있는가 · modal_frac (준-죽은 배출인가)
#  T3 regime  : Series 컬럼 vs Series_ID 컬럼 불일치로 죽은 블록의 배출 실태
#  ★음성 대조: C01_SUE / C04_ESBR / M26 / C02 는 정상 분포인가
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/streak_unit_probe_20260810")
FDB  <- file.path(ROOT, ".cache/factor_db")

pick <- c("C11_Earnings_Streak", "M25_Earnings_Mom_Streak", "SE02_Consensus_Revision",
          "C01_SUE", "C04_ESBR", "M26_Revenue_Mom", "C02_EPS_Chg_1m")
YMS <- c("202606", "202006", "201403", "200812")

res <- list()
for (ym in YMS) {
  f <- file.path(FDB, paste0("factors_", ym, ".parquet"))
  if (!file.exists(f)) {
    cand <- list.files(FDB, pattern = paste0(ym, ".*\\.parquet$"))
    if (!length(cand)) { cat(sprintf("[skip] %s 파일 부재\n", ym)); next }
    f <- file.path(FDB, cand[1])
  }
  D <- as.data.table(read_parquet(f))
  for (fn in pick) {
    d <- D[Factor_Name == fn]
    if (!nrow(d)) { res[[length(res)+1L]] <- data.table(ym = ym, factor = fn, n = 0L); next }
    rv <- d$Raw_Value
    tb <- sort(table(round(rv, 12)), decreasing = TRUE)
    res[[length(res)+1L]] <- data.table(
      ym = ym, factor = fn, n = nrow(d),
      cov_true = sum(d$Coverage, na.rm = TRUE),
      cov_frac = mean(d$Coverage, na.rm = TRUE),
      raw_med = median(rv, na.rm = TRUE), raw_max = max(rv, na.rm = TRUE),
      raw_p99 = as.numeric(quantile(rv, .99, na.rm = TRUE)),
      n_distinct = uniqueN(round(rv, 12)),
      modal_frac = as.numeric(tb[1]) / sum(!is.na(rv)),
      z_na_frac = mean(is.na(d$Z_Score)))
  }
}
R <- rbindlist(res, fill = TRUE)
print(R[order(factor, -ym)])
fwrite(R, file.path(OUT, "a7_consumption_surface.csv"))

# T3: regime 계열 배출 실태 + Series/Series_ID 불일치 확인
cat("\n== T3 macro Series 컬럼 vs Series_ID 컬럼 ==\n")
M <- as.data.table(read_parquet(file.path(ROOT, ".cache/macro_fred.parquet")))
print(unique(M[, .(Series, Series_ID, Frequency)])[order(Series)])
led <- fread(file.path(FDB, "emission_ledger.csv"))
cat("\n== T3b MA01/MA02 등 macro-beta 팩터 배출 원장 ==\n")
mm <- led[Factor_Name %like% "^MA0"]
if (!nrow(mm)) cat("  [0건] MA0* 배출 없음 — 0은 결론이 아니라 정지 신호. 이름 패턴 확인:\n")
print(unique(led$Factor_Name)[grepl("MA0|RE0|MACRO", unique(led$Factor_Name))])
if (nrow(mm)) print(mm[, .(n_months = uniqueN(ym), med_rows = median(n_rows)), by = Factor_Name])
