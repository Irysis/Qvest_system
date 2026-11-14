## 양성 대조(팩터별) — 같은 달을 전 모듈로 지은 값 vs 명세 모듈로 지은 부분 산출, 명세 대상 팩터마다 행 · 값 대조(쓰기 없음)
## 실행: 저장소 루트에서 Rscript …/check_full_by_factor.R <YYYYMM> <명세.json> [명세2.json …] · 출력: 화면 + $SP/check_full_<ym>.csv(SP 없으면 현재 폴더)
## 종료: 0 = 모든 명세의 대상이 전체 산출과 같다 · 1 = 하나라도 다르다(부분 재계산 명세가 빌더의 다른 모듈 단계에 기대고 있다 — 예: XF 채움 = xlsx_fund)
## 11-14 이음매 D2: 201806 에서 D2 명세 254 중 247 같음 · 다른 7 = XF 채움 7팩터 / 수리 명세 7 중 7 같음.
a <- commandArgs(trailingOnly = TRUE); ym <- a[1]; specs <- a[-1]
if (is.na(ym) || !length(specs)) stop("usage: check_full_by_factor.R <YYYYMM> <spec.json> [spec2.json ...]")
SP <- Sys.getenv("SP"); if (!nzchar(SP)) SP <- "."
Sys.unsetenv("QVEST_RFS_SPEC")
sys.source("02_Infrastructure/factor_db/rebuild_factor_subset.R", envir = globalenv())   # 본문 실행 없음(sys.nframe 가드)
.rfs_load(.rfs_root())
fp <- file.path(FACTOR_DB_DIR, sprintf("factor_db_%s.parquet", ym))
sig_d <- as.Date(arrow::read_parquet(fp, col_select = "Date", mmap = FALSE)$Date[1])
t0 <- Sys.time()
invisible(capture.output(full <- as.data.table(build_factor_db(sig_d, save = FALSE, force = TRUE))))
cat(sprintf("[cf %s] 전 모듈 %d행 · %.0fs\n", ym, nrow(full), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
cols <- c("Ticker", "Factor_Name", "Raw_Value", "Z_Score", "Z_Sector", "Rank_Pct", "Coverage")
out <- list()
for (sp in specs) {
  s <- jsonlite::fromJSON(sp, simplifyVector = TRUE)
  t1 <- Sys.time()
  invisible(capture.output(part <- as.data.table(build_factor_db(sig_d, save = FALSE, force = TRUE, modules = as.character(s$modules)))))
  for (f in as.character(s$targets)) {
    A <- full[Factor_Name == f, ..cols][order(Ticker)]; B <- part[Factor_Name == f, ..cols][order(Ticker)]
    eq <- isTRUE(all.equal(A, B, check.attributes = FALSE))
    out[[length(out) + 1L]] <- data.table(spec = basename(sp), factor = f, n_full = nrow(A), n_part = nrow(B),
                                          only_full = length(setdiff(A$Ticker, B$Ticker)), only_part = length(setdiff(B$Ticker, A$Ticker)), equal = eq)
  }
  cat(sprintf("[cf %s] %s 모듈 %s · 대상 %d · %.0fs\n", ym, basename(sp), paste(s$modules, collapse = ","), length(s$targets),
              as.numeric(difftime(Sys.time(), t1, units = "secs"))))
}
O <- rbindlist(out)
fwrite(O, file.path(SP, sprintf("check_full_%s.csv", ym)))
print(O[, .(n_target = .N, n_equal = sum(equal), not_equal = paste(factor[!equal], collapse = " ")), by = spec])
print(O[equal == FALSE])
quit(save = "no", status = if (all(O$equal)) 0L else 1L)
