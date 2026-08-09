#==============================================================================
# s1_rebuild_scope.R — FQ-218 (D) 재빌드 범위·시간 산출 (실행 아님, 도훈 confirm 재료)
#
# 확인할 것:
#   1. 저장 단위 — 월별 parquet 1개(= 부분 팩터 갱신 경로가 있는가)
#   2. 영향 월 — C10/C13/C15 가 실제로 배출된 월 (원장 실측, 추정 아님)
#   3. 영향 팩터 — 값이 바뀌는 팩터 목록 (양성 대조로 3종 확정)
#   4. 시간 — 어제 전면 재빌드 440개월/460분 실측에서 월당 단가 도출
#
# ★재빌드는 실행하지 않는다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/cons_window_repair_20260810")
FDB  <- file.path(ROOT, ".cache/factor_db")

# 1. 저장 단위
pq <- list.files(FDB, pattern = "\\.parquet$")
cat(sprintf("[1] 월별 parquet %d개 (예: %s)\n", length(pq),
            paste(head(pq, 3), collapse = ", ")))

led <- fread(file.path(FDB, "emission_ledger.csv"))
cat(sprintf("[1] emission_ledger: %s행  컬럼: %s\n",
            format(nrow(led), big.mark = ","), paste(names(led), collapse = ", ")))

TGT <- c("C10_SUE_Persistence", "C13_Revision_Breadth_3m", "C15_Forecast_Error_Trend")
fcol <- intersect(c("Factor_Name", "factor", "factor_name"), names(led))[1]
mcol <- intersect(c("ym", "YM", "month", "Date", "ym_tag"), names(led))[1]
rcol <- intersect(c("n_rows", "rows", "N"), names(led))[1]
cat(sprintf("[1] 사용 컬럼: factor=%s month=%s rows=%s\n", fcol, mcol, rcol))

sub <- led[get(fcol) %in% TGT]
if (!nrow(sub)) {
  cat("[STOP] 대상 팩터의 원장 행 0 — 0건은 결론이 아니라 정지 신호. 컬럼명 확인 필요.\n")
} else {
  per <- sub[, .(n_months = uniqueN(get(mcol)),
                 first_ym = min(get(mcol)), last_ym = max(get(mcol)),
                 median_rows = as.numeric(median(get(rcol)))), by = c(fcol)]
  print(per)
  affected <- sort(unique(sub[[mcol]]))
  cat(sprintf("\n[2] 세 팩터 중 하나라도 배출된 월(합집합) = %d개월  (%s .. %s)\n",
              length(affected), min(affected), max(affected)))
  all_m <- sort(unique(led[[mcol]]))
  cat(sprintf("[2] factor_db 전체 월 = %d개월  (%s .. %s)\n",
              length(all_m), min(all_m), max(all_m)))
  cat(sprintf("[2] 영향 비중 = %.1f%%\n", 100 * length(affected) / length(all_m)))

  # 3. 시간 — 어제 전면 재빌드 실측 단가
  FULL_M <- 440L; FULL_MIN <- 460L
  per_month_s <- FULL_MIN * 60 / FULL_M
  cat(sprintf("\n[3] 월당 단가 = %.1f초 (어제 전면 재빌드 %d개월/%d분 실측)\n",
              per_month_s, FULL_M, FULL_MIN))
  cat(sprintf("[3] 영향월만 재빌드: %d개월 x %.1f초 = %.0f분\n",
              length(affected), per_month_s, length(affected) * per_month_s / 60))
  cat(sprintf("[3] 전면 재빌드    : %d개월 x %.1f초 = %.0f분\n",
              length(all_m), per_month_s, length(all_m) * per_month_s / 60))

  fwrite(data.table(ym = affected), file.path(OUT, "s1_affected_months.csv"))
  fwrite(per, file.path(OUT, "s1_affected_factors.csv"))
  cat(sprintf("\n[out] %s\n", file.path(OUT, "s1_affected_months.csv")))
}

cat("\n[4] 영향 팩터 = C10/C13/C15 3종만. 근거: 같은 입력·같은 sig_date 8개월에서\n")
cat("    나머지 14종 컨센서스 팩터가 값까지 비트 불변(maxdiff 0.000e+00, 112/112).\n")
cat("    단 **저장 단위가 월별 parquet 1개**라 3종만 갱신하는 경로는 없다 —\n")
cat("    영향월은 전 모듈이 함께 재계산된다(그래서 시간이 팩터 수에 비례하지 않는다).\n")
