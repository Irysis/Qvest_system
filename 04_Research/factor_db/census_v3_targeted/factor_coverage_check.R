# 팩터별 분석 가능 기간 진단 (coverage scan) — metric_type=diagnostic
# value composite sleeve 검증(WT-D20260611_001 + census v3) 사용 팩터 9종.
# C15 준수: load_month_factors() 경유. 실존 factor_db_YYYYMM.parquet 월만 스캔
# (connector의 closest-month fallback이 가용성 판정을 오염시키지 않도록).
# 기준: 월 비-NA Z_Score_Aligned 단면 n>=30 이면 해당 월 "가용".
suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/factor_db/factor_db_connector.R")
})

targets <- c("V02_EP","V14_EBIT_EV","V07_EV_EBITDA","V20_SP","V13_EV_Sales",
             "V01_BM","R05_Tail_Risk","IN03_RD_to_Market","XF_LL05_WorkingCapital")

avail_files <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
yms <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail_files))
cat(sprintf("[scan] factor DB months on disk: %d (%s..%s)\n", length(yms), yms[1], yms[length(yms)]))

cov <- list()
for (ym in yms) {
  eom <- as.Date(paste0(ym, "01"), "%Y%m%d")
  eom <- seq(eom, by = "month", length.out = 2)[2] - 1  # month end
  dt <- tryCatch(suppressWarnings(load_month_factors(eom, coverage_min = 0)),
                 error = function(e) NULL)
  if (is.null(dt) || nrow(dt) == 0) next
  dt <- data.table::as.data.table(dt)
  sub <- dt[Factor_Name %in% targets & !is.na(Z_Score_Aligned),
            .(n = .N), by = Factor_Name]
  for (k in seq_len(nrow(sub))) {
    f <- sub$Factor_Name[k]; n <- sub$n[k]
    if (n >= 30) {
      if (is.null(cov[[f]])) cov[[f]] <- list(first = ym, last = ym, n_months = 0L, min_n = n, max_n = n)
      cov[[f]]$last <- ym
      cov[[f]]$n_months <- cov[[f]]$n_months + 1L
      cov[[f]]$min_n <- min(cov[[f]]$min_n, n)
      cov[[f]]$max_n <- max(cov[[f]]$max_n, n)
    }
  }
}

cat("factor_id | first_month(n>=30) | last_month | n_months | cross-section n (min~max)\n")
for (f in targets) {
  c0 <- cov[[f]]
  if (is.null(c0)) { cat(sprintf("%s | NEVER>=30\n", f)); next }
  cat(sprintf("%s | %s | %s | %d | %d~%d\n", f, c0$first, c0$last, c0$n_months, c0$min_n, c0$max_n))
}

out <- lapply(cov, function(x) x[c("first","last","n_months","min_n","max_n")])
jsonlite::write_json(out, "04_Research/factor_db/census_v3_targeted/factor_coverage.json",
                     auto_unbox = TRUE, pretty = TRUE)
cat("DONE_COVERAGE_SCAN\n")
