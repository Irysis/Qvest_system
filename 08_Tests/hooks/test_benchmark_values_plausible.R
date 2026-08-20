## ============================================================================
## test_benchmark_values_plausible.R — audit_bt_result Check 17 검사기
##
## 신설 2026-08-09 (도훈 적발 "26년 수익률 이상 — 어제 고쳤는데 또").
##
## ## 왜 필요했나
## benchmark.parquet 스케일 이음매로 2026-07-29 이 -89.38%(참값 -6.185%)가 됐는데,
## Check 5(benchmark_aligned)가 **날짜 겹침만** 세는 탓에 alpha_search 16 run 이 전부
## "alignment PASS" 로 통과하고 Grade B 까지 받았다. 존재 검사가 정체 검사를 대체한 사례.
##
## ## 무엇을 재는가 (양방향)
##  A. 합성 위반 주입 — 이음매/무변동/결손이 critical FAIL 을 **발행**하는가
##  B. 검출력 실증   — 같은 입력에서 Check 5 는 PASS 라는 것(=이 검사가 메우는 구멍)
##  C. ★실데이터 전건 재생 — stage_artifacts/alpha_search 466 run 의 실제 벤치 계열로
##     오염 16건 전건 발화 + 나머지 전건 무발화(오탐률)를 **실측**한다.
##
## 실행: Rscript -e 'source("08_Tests/hooks/test_benchmark_values_plausible.R")'
## ============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/contracts/audit_bt_result.R")

npass <- 0L; fails <- character(0)
ok <- function(nm, cond, note = "") {
  if (isTRUE(cond)) { npass <<- npass + 1L; cat(sprintf("  PASS  %s\n        %s\n", nm, note)) }
  else { fails <<- c(fails, nm); cat(sprintf("  \u2605FAIL %s\n        %s\n", nm, note)) }
}

## ── 최소 bt_result 픽스처 ────────────────────────────────────────────────────
mk <- function(bench_ret, dates = NULL) {
  n <- length(bench_ret)
  if (is.null(dates)) dates <- seq(as.Date("2005-02-03"), by = "1 day", length.out = n)
  set.seed(11); sr <- rnorm(n, 0.0004, 0.012)
  list(
    manifest = data.table(run_id = "TEST", frequency = "daily",
                          risk_free_rate_source = "0", rebalance_rule = "",
                          transaction_cost_bps = 15),
    period_returns = data.table(date = dates, frequency = "daily",
                                ret_gross = sr, cost_ret = 0, ret_net = sr),
    nav = data.table(date = dates, nav_net = cumprod(1 + sr)),
    benchmark_returns = data.table(date = dates, benchmark_ret = bench_ret),
    metrics = data.table(metric_name = "CAGR", metric_type = "backtested",
                         is_official = TRUE, annualization_factor = 252),
    holdings = data.table(), strategy_spec = data.table(),
    benchmark_compare = data.table(), rolling_metrics = data.table(),
    drawdowns = data.table(), audit = data.table()
  )
}
bench_rows <- function(bt) {
  a <- tryCatch(audit_bt_result(bt)$audit, error = function(e) NULL)
  if (is.null(a)) return(NULL)
  a[check_group == "benchmark"]
}
fired <- function(bt, nm) {
  r <- bench_rows(bt); if (is.null(r)) return(FALSE)
  any(r$check_name == nm & r$status == "FAIL" & r$severity == "critical")
}

## ── 실제 벤치 계열 (수리본) ──────────────────────────────────────────────────
bmc <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bmc[, Date := as.Date(Date)]; setorder(bmc, Date)
real <- bmc[Date >= as.Date("2005-02-03") & !is.na(BM_Ret)]

cat("==============================================================================\n")
cat("test_benchmark_values_plausible — audit Check 17\n")
cat("==============================================================================\n")

## A. 합성 위반 주입 ----------------------------------------------------------
bt_clean <- mk(real$BM_Ret, real$Date)
r <- bench_rows(bt_clean)
ok("POS-1  수리된 실제 벤치 → 두 검사 모두 PASS",
   !is.null(r) && all(r[check_name %in% c("benchmark_values_plausible",
                                          "benchmark_series_non_degenerate")]$status == "PASS"),
   paste(sprintf("%s=%s", r$check_name, r$status), collapse = " | "))

seam <- copy(real); seam[Date == as.Date("2026-07-29"), BM_Ret := -0.8938076]
ok("INJ-1  ★실사고 재현: 8.834x 이음매 주입 → critical FAIL",
   fired(mk(seam$BM_Ret, seam$Date), "benchmark_values_plausible"),
   bench_rows(mk(seam$BM_Ret, seam$Date))[check_name == "benchmark_values_plausible"]$details)

mild <- copy(real); mild[Date == as.Date("2026-07-29"), BM_Ret := -1/1.5 + 1 - 1]
mild[Date == as.Date("2026-07-29"), BM_Ret := (1/1.5) - 1]   # 1.5x 스케일 오류 = -33.3%
ok("INJ-2  약한 스케일 오류(1.5x, -33.3%) 도 검출",
   fired(mk(mild$BM_Ret, mild$Date), "benchmark_values_plausible"),
   sprintf("주입 %.4f", mild[Date == as.Date("2026-07-29")]$BM_Ret))

ok("INJ-3  무변동 벤치(sd=0) → critical FAIL",
   fired(mk(rep(0, nrow(real)), real$Date), "benchmark_series_non_degenerate"), "")

na_ret <- real$BM_Ret; na_ret[seq_len(round(0.8 * length(na_ret)))] <- NA_real_
ok("INJ-4  벤치 80% 결손(조인 실패 모사) → critical FAIL",
   fired(mk(na_ret, real$Date), "benchmark_series_non_degenerate"), "")

## B. 검출력 실증 — 같은 입력에서 Check 5 는 PASS -----------------------------
r5 <- bench_rows(mk(seam$BM_Ret, seam$Date))[check_name == "benchmark_aligned"]
ok("MUT-1  ★구멍 실증: 같은 오염 입력에서 Check 5(정렬)는 PASS",
   nrow(r5) == 1L && r5$status == "PASS",
   sprintf("benchmark_aligned=%s — %s", r5$status, r5$details))

## C. 실데이터 전건 재생 ------------------------------------------------------
cat("\n  [C] stage_artifacts/alpha_search 전건 재생 중...\n")
dirs <- list.dirs("stage_artifacts/alpha_search", recursive = FALSE)
rep <- rbindlist(lapply(dirs, function(dd) {
  f <- file.path(dd, "05_benchmark_returns.csv")
  if (!file.exists(f)) return(NULL)
  x <- tryCatch(fread(f, select = c("date", "benchmark_ret")), error = function(e) NULL)
  if (is.null(x) || nrow(x) < 3) return(NULL)
  x[, date := as.Date(date)]
  bt <- mk(x$benchmark_ret, x$date)
  data.table(run = basename(dd),
             seam_truth = as.integer(any(abs(x$benchmark_ret) > 0.5, na.rm = TRUE)),
             fired = as.integer(fired(bt, "benchmark_values_plausible")))
}), fill = TRUE)

tp <- rep[seam_truth == 1 & fired == 1, .N]; fn <- rep[seam_truth == 1 & fired == 0, .N]
fp <- rep[seam_truth == 0 & fired == 1, .N]; tn <- rep[seam_truth == 0 & fired == 0, .N]
cat(sprintf("      run %d건 — 오염(|ret|>0.5) %d건 / 청정 %d건\n",
            nrow(rep), tp + fn, fp + tn))
ok("REAL-1 오염 run 전건 발화 (재현율)",
   fn == 0L && tp > 0L, sprintf("검출 %d / 오염 %d, 미검출 %d", tp, tp + fn, fn))
ok("REAL-2 청정 run 오탐 0 (정밀도)",
   fp == 0L, sprintf("오탐 %d / 청정 %d", fp, fp + tn))
if (fp > 0L) print(head(rep[seam_truth == 0 & fired == 1], 10))

cat("------------------------------------------------------------------------------\n")
cat(sprintf("  %d/%d PASS\n", npass, npass + length(fails)))
if (length(fails)) cat("  \u2605실패:", paste(fails, collapse = ", "), "\n")
# 2026-08-20: 배터리 요약. fail 은 카운터가 아니라 fails 벡터 길이다.
cat(sprintf("{\"test\":\"test_benchmark_values_plausible\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", npass, length(fails), npass + length(fails)))
invisible(if (length(fails)) quit(status = 1L))
