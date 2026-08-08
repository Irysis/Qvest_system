## FQ-037 사전확인 2 — 지각제출 축(rcept_dt)이 로컬에 실재하는가 + 교차 표본이 게이트 30을 넘는가
suppressPackageStartupMessages({library(data.table); library(arrow)})
R <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(R)
OUT <- "stage_artifacts/fq037_precheck_20260808"

cand <- c(".cache/dart/dart_raw_quarterly.parquet", ".cache/dart/dart_raw_financials.parquet")
cat("=== [1] rcept_dt 보유 원천 탐색 ===\n")
src <- NULL
for (f in cand) {
  if (!file.exists(f)) next
  nmv <- names(schema(open_dataset(f)))
  has <- "rcept_dt" %in% nmv
  n <- nrow(open_dataset(f))
  cat(sprintf("  %-42s %s행 · rcept_dt %s\n", basename(f), format(n, big.mark=","),
              if (has) "있음 ✓" else "없음"))
  if (has && is.null(src)) src <- f
}
if (is.null(src)) { cat("\n[중단] rcept_dt 보유 원천 없음 — 지각제출 축 구성 불가.\n"); quit(status=0) }

cat(sprintf("\n=== [2] %s 구조 ===\n", basename(src)))
keep <- intersect(c("corp_code","stock_code","rcept_no","rcept_dt","bsns_year","reprt_code"),
                  names(schema(open_dataset(src))))
d <- as.data.table(read_parquet(src, col_select = keep))
cat(sprintf("  열: %s\n  행 %s\n", paste(keep, collapse=", "), format(nrow(d), big.mark=",")))
d <- unique(d)
cat(sprintf("  (중복 제거 후 %s)\n", format(nrow(d), big.mark=",")))
if ("rcept_dt" %in% names(d)) {
  d[, rd := as.Date(as.character(rcept_dt), format="%Y%m%d")]
  cat(sprintf("  rcept_dt 유효 %s행 · %s ~ %s\n", format(sum(!is.na(d$rd)), big.mark=","),
              min(d$rd, na.rm=TRUE), max(d$rd, na.rm=TRUE)))
}
if ("stock_code" %in% names(d)) cat(sprintf("  종목코드 보유 %s행 · 고유 %d\n",
    format(sum(nzchar(as.character(d$stock_code)) & !is.na(d$stock_code)), big.mark=","),
    uniqueN(d[nzchar(as.character(stock_code))]$stock_code)))

## [3] 연간보고서 제출지연 = rcept_dt − 사업연도말(12/31) ; 법정기한 90일(3/31)
if (all(c("bsns_year","reprt_code") %in% names(d))) {
  cat("\n=== [3] 보고서 종류 분포 ===\n"); print(sort(table(d$reprt_code), decreasing=TRUE)[1:5])
  a <- d[reprt_code == "11011" & !is.na(rd)]          # 11011 = 사업보고서(연간)
  if (nrow(a)) {
    a[, fy_end := as.Date(sprintf("%s-12-31", bsns_year))]
    a[, lag_d := as.integer(rd - fy_end)]
    a <- a[lag_d > 0 & lag_d < 400]
    cat(sprintf("\n=== [4] 사업보고서 제출지연(일) — n=%s ===\n", format(nrow(a), big.mark=",")))
    print(round(quantile(a$lag_d, c(.5,.75,.9,.95,.99), na.rm=TRUE), 1))
    thr <- as.numeric(quantile(a$lag_d, 0.90, na.rm=TRUE))
    late <- a[lag_d >= thr]
    cat(sprintf("  극단꼬리(상위10%%, ≥%.0f일): %s건 · 회사 %d\n", thr,
                format(nrow(late), big.mark=","), uniqueN(late$stock_code)))
    fwrite(late[, .(stock_code, bsns_year, rd, lag_d)], file.path(OUT, "late_filers.csv"))

    ## [5] 교차: 지각 회사 ∩ 심각사건 회사
    on <- fread(file.path(OUT, "severe_event_onsets.csv"))
    on[, tk := sprintf("%06s", gsub("[^0-9]", "", as.character(Ticker)))]
    late[, tk := sprintf("%06s", gsub("[^0-9]", "", as.character(stock_code)))]
    cross <- intersect(unique(late$tk), unique(on$tk))
    cat(sprintf("\n=== [5] 교차 표본 ===\n  지각 회사 %d · 사건 회사 %d · **교차 %d개사**\n",
                uniqueN(late$tk), uniqueN(on$tk), length(cross)))
    cat(sprintf("\n[게이트 대비] 사전등록 유효성 게이트 = 독립 에피소드 ≥ 30\n"))
    cat(sprintf("  교차 회사 %d → %s\n", length(cross),
        if (length(cross) >= 30) "★게이트 여유 — 라운드 착수 가치 있음"
        else "★POWER_INSUFFICIENT 가능성 — 착수 전 설계 재검 필요"))
  } else cat("\n[주의] reprt_code 11011(사업보고서) 행 없음 — 지연 축 정의 재검 필요\n")
} else cat("\n[주의] bsns_year/reprt_code 부재 — 지연 산출 불가\n")
