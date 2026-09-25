# test_replication_exec_parity.R — 집행 규약 close_t1 ↔ 정본 backtest_harness::run_monthly_simulation 패리티
#   (2026-09-24 · 플랜 P0-04 검증 ② · 결정 EXEC-PRICE "close_t1 = 정본 backtest_harness 와 같은 의미")
#
# 무엇을 재는가: 같은 EW 롱온리 보유를 비용 0 으로 두 하네스에 넣었을 때 **일간 수익 귀속**이 같은가.
#   정본(주식수·현금 기반): (prev,exec] NAV = 옛 보유 · 새 보유는 Close[exec] 매수 · 이후 드리프트.
#   복제 하네스 close_t1: 보유창 (exec, next_exec] · Return.portfolio 드리프트.
#
# ★허용오차 — 결과를 보기 전에 선언한다(critique #12):
#   TOL_RET = 1e-9 : 일간 |r_rep − r_canon|. 정본은 floor(주식수)라 현금 잔차가 생겨 비트 동일이 불가능하다.
#                    initial_cap 1e15 · 가격 ~1e2 · 5종 → 잔차/NAV ≤ 5×1e2/1e15 = 5e-13 → 일간 수익 오차 ≲ 1e-11.
#   TOL_NAV = 1e-8 : 비교 구간 누적 수익 차.
#   비교 구간 = 정본 수익 계열 전체(= exec_1+2 이후). 정본은 첫 NAV 행(exec_1+1)의 수익을 NA 로 버린다
#     (backtest_harness.R:1395-1396) — 구조 차이이지 결함이 아니다. 복제는 exec_1+1 을 1행 더 가진다(단정).
#   비용 0 에서만 비교한다 — 두 비용식은 설계가 다르다(정본 v2.4_delta = 드리프트 명목 |Δ| · 복제 = 목표 비중 |Δw|).
#   가격 결측 없음 — 결측 처리 규약이 다르다(정본 last_price=매수가 · 복제 수익 0). 합성은 완전 패널.
# 음성 대조: 같은 입력의 close_d_legacy 는 집행일마다 어긋나야 한다(패리티 검사의 판별력).
#
# 기준 파일은 **읽기만** 한다 — 필요한 정의 3개(get_execution_date · .compute_daily_nav · run_monthly_simulation)를
#   parse→eval 로 꺼낸다(파일 상단의 config·arrow·Rcpp 적재를 피한다 · .USE_RCPP_NAV_ENGINE=FALSE = R 경로).
# 실행: Rscript 08_Tests/contracts/test_replication_exec_parity.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({ library(data.table); library(xts); library(PerformanceAnalytics) })

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
finish <- function() {
  cat(sprintf("결과: PASS=%d FAIL=%d\n", pass, fail))
  cat(sprintf('{"test":"replication_exec_parity","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
  if (fail > 0L) quit(status = 1L)
}
TOL_RET <- 1e-9
TOL_NAV <- 1e-8

# ── 정본 정의 추출 ──
BH <- "02_Infrastructure/backtest_harness.R"
bex <- tryCatch(parse(BH, encoding = "UTF-8", keep.source = FALSE), error = function(e) e)
if (inherits(bex, "error")) { ng(sprintf("정본 %s parse 실패(편집 중?) — %s", BH, conditionMessage(bex))); finish() }
cenv <- new.env(parent = globalenv())
cenv$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
cenv$.USE_RCPP_NAV_ENGINE <- FALSE
for (nm in c("get_execution_date", ".compute_daily_nav", "run_monthly_simulation")) {
  hit <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), nm), as.list(bex))
  if (length(hit) != 1L) { ng(sprintf("정본 정의 %s %d건", nm, length(hit))); finish() }
  eval(hit[[1]], envir = cenv)
}
get_execution_date <- cenv$get_execution_date          # 복제 하네스도 **같은** 집행일 함수를 쓴다(러너와 동일)
source("02_Infrastructure/replication/replication_harness.R")

# ── 합성 완전 패널 ──
set.seed(424)
dates <- seq(as.Date("2019-01-01"), as.Date("2019-12-31"), by = "day")
dates <- dates[!format(dates, "%u") %in% c("6", "7")]
tick <- sprintf("K%02d", 1:12)
RAW <- CJ(Ticker = tick, Date = dates)
RAW[, r0 := rnorm(.N, 0.0003, 0.02)]
RAW[, Close := 100 * cumprod(1 + r0), by = Ticker]
RAW[, Ret := Close / shift(Close) - 1, by = Ticker]        # build_cache.R 규약: Ret_t = Close_t/Close_{t-1} − 1
RAW[, `:=`(r0 = NULL, Name = Ticker, Sector = "S")]
setcolorder(RAW, c("Date", "Ticker"))
BM <- unique(RAW[, .(Date)])[, BM_Ret := rnorm(.N, 0, 0.01)][]
sig <- as.Date(sapply(unique(format(dates, "%Y-%m"))[1:11],
                      function(m) as.numeric(max(dates[format(dates, "%Y-%m") == m]))))
FAC <- rbindlist(lapply(sig, function(d) data.table(Date = d, Ticker = tick, Score = runif(length(tick)))))
NH <- 5L
W <- FAC[order(Date, -Score)][, head(.SD, NH), by = Date][, .(Date, Ticker, Weight = 1 / NH)]

# ── 정본 (비용 0 · EW = 미등록 이름의 호명 폴백 경로 · 캡 25 미만) ──
Sys.unsetenv("QVEST_WEIGHT_STRICT")
canon <- suppressWarnings(capture.output(
  cs <- cenv$run_monthly_simulation(copy(RAW), copy(BM), copy(FAC), n_holdings = NH, commission = 0,
                                    initial_cap = 1e15, weight_method = "equal_weight_parity_probe")))
rc <- data.table(Date = as.Date(index(cs$strategy_xts)), rc = as.numeric(cs$strategy_xts))
nh_canon <- cs$HOLDINGS_LOG[, .N, by = Exec_Date]$N
if (length(nh_canon) == length(sig) && all(nh_canon == NH) &&
    all(abs(cs$HOLDINGS_LOG$Weight - 1 / NH) < 1e-9))
  ok(sprintf("정본 실행: %d 리밸 · 각 %d종 EW (Rcpp 끔 · R 경로)", length(nh_canon), NH)) else
  ng("정본 실행 조건 불일치(리밸 수·종목수·EW)")

run_rep <- function(ep, env = globalenv()) {
  s <- env$run_replication_simulation(copy(RAW), copy(BM), W, commission = 0, exec_price = ep)
  data.table(Date = as.Date(index(s$strategy_xts)), rr = as.numeric(s$strategy_xts))
}
rt <- run_rep("close_t1")
ex1 <- get_execution_date(sig[1], dates)
m <- merge(rc, rt, by = "Date", all = TRUE)

# ① 날짜 집합: 정본 전체 ⊂ 복제 · 복제의 여분은 exec_1+1 한 행뿐
extra <- setdiff(rt$Date, rc$Date)
if (all(rc$Date %in% rt$Date) && length(extra) == 1L && as.Date(extra) == min(dates[dates > ex1]))
  ok(sprintf("날짜 정합: 정본 %d일 ⊂ 복제 %d일 · 여분 = exec_1+1 한 행(정본이 NA 로 버리는 행)", nrow(rc), nrow(rt))) else
  ng(sprintf("날짜 집합 불일치 — 정본 %d 복제 %d 여분 %s", nrow(rc), nrow(rt), paste(extra, collapse = ",")))

# ② 일간 수익 귀속 (사전 선언 TOL_RET)
mm <- m[!is.na(rc) & !is.na(rr)]
dmax <- max(abs(mm$rc - mm$rr))
exec_days <- as.Date(sapply(sig[-1], function(s) as.numeric(get_execution_date(s, dates))))
dexec <- max(abs(mm[Date %in% exec_days, rc - rr]))
if (dmax <= TOL_RET) ok(sprintf("일간 수익 귀속 일치: max|Δ| %.2e ≤ %.0e (%d일 · 집행일 %d개 max|Δ| %.2e)",
                                dmax, TOL_RET, nrow(mm), length(exec_days), dexec)) else
  ng(sprintf("일간 수익 귀속 불일치: max|Δ| %.3e > %.0e (집행일 max %.3e)", dmax, TOL_RET, dexec))
# ③ 누적 NAV (사전 선언 TOL_NAV)
dnav <- abs(prod(1 + mm$rc) - prod(1 + mm$rr))
if (dnav <= TOL_NAV) ok(sprintf("누적 수익 일치: |Δ| %.2e ≤ %.0e", dnav, TOL_NAV)) else
  ng(sprintf("누적 수익 불일치: |Δ| %.3e", dnav))

# ④ 음성 대조 — legacy 는 집행일마다 정본과 어긋난다(판별력: 패리티 검사가 규약 차이를 본다)
rl <- run_rep("close_d_legacy")
ml <- merge(rc, rl, by = "Date")
dl_exec <- ml[Date %in% exec_days, abs(rc - rr)]
if (length(dl_exec) == length(exec_days) && min(dl_exec) > TOL_RET)
  ok(sprintf("음성 대조: legacy 는 집행일 %d/%d 전부 허용오차 밖(min|Δ| %.2e ≫ %.0e) — 검사가 규약 차이를 가른다",
             sum(dl_exec > TOL_RET), length(exec_days), min(dl_exec), TOL_RET)) else
  ng(sprintf("음성 대조 실패: legacy 가 정본과 구분되지 않는다(집행일 min|Δ| %s)", if (length(dl_exec)) min(dl_exec) else NA))

# ⑤ 음성 대조 — 돌연변이(close_t1 창을 >= 로 되돌린 사본)는 패리티 red
h_txt <- readLines("02_Infrastructure/replication/replication_harness.R", warn = FALSE, encoding = "UTF-8")
mut <- sub("hold_pool <- hold_pool[hold_pool > exec_date]", "hold_pool <- hold_pool[hold_pool >= exec_date]", h_txt, fixed = TRUE)
if (!identical(mut, h_txt)) {
  tf <- tempfile(fileext = ".R"); writeLines(mut, tf, useBytes = TRUE)
  menv <- new.env(parent = globalenv()); suppressMessages(capture.output(sys.source(tf, envir = menv))); unlink(tf)
  rm_ <- tryCatch(run_rep("close_t1", menv), error = function(e) NULL)
  dm <- if (is.null(rm_)) NA_real_ else max(abs(merge(rc, rm_, by = "Date")[, rc - rr]))
  if (is.finite(dm) && dm > TOL_RET) ok(sprintf("돌연변이(창 >=) 사본은 패리티 red (max|Δ| %.2e)", dm)) else
    ng("돌연변이 사본이 패리티를 통과 — 판별력 없음")
} else ng("돌연변이 대상 줄(close_t1 창)을 못 찾음")

finish()
