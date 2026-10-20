# test_replication_weekly.R — MC4 주간 리밸런싱 경로 검사기 (양방향 · 합성 데이터 · 구판 하네스 비트 대조)
#
# 계약 (MC4 · D16 · 2026-10-13 · 설계 §3.9):
#   W1 월간(월말 신호 · 월 1회)은 구판과 비트 동일 — close_t1 · close_d_legacy 둘 다(기준본 = 주간 경로 이전 판 고정 blob · W0)
#   W2 월중 신호일이라도 월 1회면 월간 경로(구판 비트 동일)
#   W3 주간 신호 → 주간 판정 · 리밸 횟수 = 주 수 · 집행일 = 신호 다음 거래일 · 보유 창 서로소
#   W4 일간 신호 → ISO 주당 마지막 신호만(일간 불허 · 회계 진단)
#   W5 [결함 대조] 같은 일간 신호를 구판은 월 1회로 뭉쳤다 · 신판 rebalance="monthly" 강제는 구판을 비트 재현
#   W6 주간 신호일 거래량 0 종목 제외 + 레그 비중 보존 · 돌연변이 대조: 월간 강제 경로는 제외하지 않는다(월간 무변경)
#   W7 PIT — 신호일 다음 날의 거래량 0 · 수익 섭동은 그 신호일의 제외 · 비중을 바꾸지 않는다 · 신호일 당일 거래량 0 은 바꾼다
#   W8 비용 — 리밸마다 부과(NAV_net < NAV_gross · 비용 행 수 = 회전 > 0 인 리밸 수)
#   W9 rep_next_trading_day — 주말 · 공휴일 · 마지막 날(NA)
# 실행: Rscript 08_Tests/contracts/test_replication_weekly.R
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({ library(data.table); library(xts); library(PerformanceAnalytics)
  library(lubridate) })   # 정본 get_execution_date 의 NA_Date_ 는 lubridate 가 준다(backtest_harness.R:36 이 불러오는 환경과 같게)
pass <- 0L; fail <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { pass <<- pass + 1L; cat(sprintf("  [PASS] %s\n", name)) }
  else { fail <<- fail + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}

## 정본 get_execution_date — backtest_harness.R 에서 그 정의만 파싱해 평가(사본 금지 · 파일 전체 source 의 부작용 회피)
.bh <- parse(file.path(root, "02_Infrastructure/backtest_harness.R"), keep.source = FALSE, encoding = "UTF-8")
.hit <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), "get_execution_date"), as.list(.bh))
if (length(.hit) != 1L) stop("backtest_harness.R 에서 get_execution_date 정의를 찾지 못했다")
eval(.hit[[1]], envir = globalenv())

## 신판(작업 트리) · 구판(고정 blob) 하네스를 각자 환경에
##   구판 = 주간 경로(MC4 · D16) 이전 판 — 8558e06b6(2026-09-25)의 replication_harness.R blob. 이 검사를 쓸 때는 신판이 미커밋이라
##   HEAD 가 구판이었지만, 61095bae1(2026-10-14 auto-commit)이 신판을 커밋한 뒤로 HEAD 는 신판이다 — HEAD 를 기준본으로 두면
##   W0 · W5 가 빨개지고 W1 · W2 의 비트 대조는 아무것도 재지 않는다. blob 은 불변이라 이후 커밋과 무관하게 같은 판본을 가리킨다.
OLD_HARNESS_BLOB <- "369fcb244905edc3bac20572bd38bb0b2a95c079"
NEW <- new.env(); sys.source(file.path(root, "02_Infrastructure/replication/replication_harness.R"), envir = NEW, keep.source = FALSE)
old_src <- tempfile(fileext = ".R")
old_txt <- tryCatch(suppressWarnings(system2("git", c("-C", root, "cat-file", "-p", OLD_HARNESS_BLOB), stdout = TRUE, stderr = FALSE)),
                    error = function(e) character(0))
HAVE_OLD <- is.null(attr(old_txt, "status")) && length(old_txt) > 100L && !any(grepl("rep_rebalance_mode", old_txt, fixed = TRUE))
OLD <- new.env()
if (HAVE_OLD) { writeLines(old_txt, old_src, useBytes = TRUE); sys.source(old_src, envir = OLD, keep.source = FALSE) }
chk(sprintf("W0 기준본 확보 — 주간 경로 이전 구판 하네스 blob %s(rep_rebalance_mode 없음)", substr(OLD_HARNESS_BLOB, 1L, 9L)), HAVE_OLD,
    "(git cat-file 실패 또는 blob 이 신판 — 구판 비트 대조 불가)")

## 합성 세계 — 평일 달력(공휴일 2일 제외) · 30종목 · 결정론 수익 · 거래량
set.seed(20261013)
days <- seq(as.Date("2019-11-01"), as.Date("2020-12-31"), by = "day")
days <- days[!format(days, "%u") %in% c("6", "7")]
days <- setdiff(days, as.Date(c("2020-01-01", "2020-05-05"))); days <- as.Date(days, origin = "1970-01-01")
tk <- sprintf("A%05d", 1:30)
RAW <- CJ(Date = days, Ticker = tk)
RAW[, Ret := round(rnorm(.N, 0.0004, 0.02), 6)]
RAW[, Close := 100 * cumprod(1 + Ret), by = Ticker]
RAW[, Vol := as.numeric(sample(1000:50000, .N, replace = TRUE))]
BM <- data.table(Date = days, BM_Ret = round(rnorm(length(days), 0.0003, 0.012), 6))
last_td <- function(dates, key) { x <- data.table(d = dates, k = key(dates)); x[, list(d = max(d)), by = k]$d }
month_end <- last_td(days, function(d) format(d, "%Y-%m"))
week_end  <- last_td(days, function(d) format(d, "%G-W%V"))
mkW <- function(sig) rbindlist(lapply(sig, function(d) { s <- sort(sample(tk, 10)); data.table(Date = d, Ticker = s, Weight = rep(0.1, 10)) }))
run <- function(env, W, ep = "close_t1", rb = NULL) {
  args <- list(RAWDATA = copy(RAW), BM_DT = BM, WEIGHTS = W, commission = 0.0015, start_date = "2019-11-01", exec_price = ep)
  if (!is.null(rb)) args$rebalance <- rb
  do.call(env$run_replication_simulation, args)
}
same <- function(a, b) isTRUE(all.equal(as.numeric(a$strategy_xts), as.numeric(b$strategy_xts), tolerance = 0)) &&
  identical(index(a$strategy_xts), index(b$strategy_xts)) && isTRUE(all.equal(a$DAILY_NAV_DT, b$DAILY_NAV_DT, tolerance = 0)) &&
  isTRUE(all.equal(a$PORTFOLIO_LOG, b$PORTFOLIO_LOG, tolerance = 0)) && isTRUE(all.equal(a$HOLDINGS_LOG, b$HOLDINGS_LOG, tolerance = 0))

cat("=== W1 · W2 월간 = 구판 비트 동일 ===\n")
WM <- mkW(month_end[month_end >= as.Date("2019-11-01") & month_end < as.Date("2020-12-31")])
for (ep in c("close_t1", "close_d_legacy")) {
  n <- run(NEW, WM, ep)
  chk(sprintf("W1 월말 신호 · %s — 판정 monthly · 구판과 비트 동일", ep),
      identical(n$diagnostics$rebalance$mode, "monthly") && HAVE_OLD && same(n, run(OLD, WM, ep)))   # 기준본 없으면 비트 대조 미측정 = red
}
mid <- last_td(days[as.integer(format(days, "%d")) <= 15], function(d) format(d, "%Y-%m"))   # 월중(15일 이전 마지막 거래일)
WMID <- mkW(mid[mid < as.Date("2020-12-15")])
n2 <- run(NEW, WMID)
chk("W2 월중 신호일 · 월 1회 — 월간 경로 · 구판 비트 동일(집행 = 익월 첫 거래일)",
    identical(n2$diagnostics$rebalance$mode, "monthly") && HAVE_OLD && same(n2, run(OLD, WMID)) &&
      all(format(n2$PORTFOLIO_LOG$Exec_Date, "%Y-%m") > format(n2$PORTFOLIO_LOG$Signal_Date, "%Y-%m")))

cat("\n=== W3 주간 신호 ===\n")
WW <- mkW(week_end[week_end < as.Date("2020-12-24")])
w3 <- run(NEW, WW); pl <- w3$PORTFOLIO_LOG
nxt <- NEW$rep_next_trading_day(pl$Signal_Date, days)
hl <- w3$HOLDINGS_LOG
chk("W3a 판정 weekly · 리밸 횟수 = 신호 주 수", identical(w3$diagnostics$rebalance$mode, "weekly") && nrow(pl) == length(unique(WW$Date)),
    sprintf("(리밸 %d · 주 %d)", nrow(pl), length(unique(WW$Date))))
chk("W3b 집행일 = 신호 다음 거래일(같은 달 안에서도)", identical(as.Date(pl$Exec_Date), as.Date(nxt)) &&
      any(format(pl$Exec_Date, "%Y-%m") == format(pl$Signal_Date, "%Y-%m")))
chk("W3c 보유 창 서로소(중복일 0) · 주간 보유 기록 = 리밸마다", w3$diagnostics$n_overlap_days == 0L && length(unique(hl$Date)) == nrow(pl))

cat("\n=== W4 · W5 일간 신호 → 주간 · 구판 침묵 붕괴 대조 ===\n")
WD <- mkW(days[days >= as.Date("2020-02-03") & days <= as.Date("2020-06-30")])
w4 <- run(NEW, WD); d4 <- w4$diagnostics$rebalance
wk_last <- last_td(unique(WD$Date), function(d) format(d, "%G-W%V"))
chk("W4a 일간 신호 → 주간 판정 · 쓰인 신호 = ISO 주당 마지막 신호", identical(d4$mode, "weekly") &&
      setequal(as.Date(w4$PORTFOLIO_LOG$Signal_Date), wk_last[wk_last < max(days)]))
chk("W4b 회계 — 원 신호 수 · 쓰인 수 · 여러 신호가 든 주 수", d4$n_signal_raw == length(unique(WD$Date)) && d4$n_signal_used == length(wk_last) &&
      d4$n_weeks_multi_signal > 0L)
if (HAVE_OLD) {
  o5 <- run(OLD, WD)
  chk("W5a [결함 대조] 구판은 같은 일간 신호를 월 1회로 뭉쳤다(리밸 = 달 수)", nrow(o5$PORTFOLIO_LOG) == length(unique(format(WD$Date, "%Y-%m"))))
  chk("W5b 신판 rebalance='monthly' 강제 = 구판 비트 재현(재현 전용 경로)", same(run(NEW, WD, rb = "monthly"), o5))
} else { chk("W5a [결함 대조] 기준본 없음", FALSE); chk("W5b 기준본 없음", FALSE) }

cat("\n=== W6 · W7 거래량 0 제외 · PIT ===\n")
d0 <- unique(WW$Date)[5]; x0 <- WW[Date == d0]$Ticker[3]
zero_on <- function(dd, tt) { r <- copy(RAW); r[Date == dd & Ticker == tt, Vol := 0]; r }
run_raw <- function(r, W, rb = NULL) { a <- list(RAWDATA = r, BM_DT = BM, WEIGHTS = W, commission = 0.0015, start_date = "2019-11-01", exec_price = "close_t1")
                                       if (!is.null(rb)) a$rebalance <- rb; do.call(NEW$run_replication_simulation, a) }
w6 <- run_raw(zero_on(d0, x0), WW); e0 <- NEW$rep_next_trading_day(d0, days)
h6 <- w6$HOLDINGS_LOG[Date == e0]
chk("W6a 신호일 거래량 0 종목 제외 · 레그 비중 합 보존(1.0)", !(x0 %in% h6$Ticker) && nrow(h6) == 9L && abs(sum(h6$Weight) - 1) < 1e-12 &&
      w6$diagnostics$rebalance$n_zero_vol_excluded == 1L)
m6 <- run_raw(zero_on(d0, x0), WW, rb = "monthly")
chk("W6b [돌연변이 대조] 월간 강제 경로는 거래량 0 을 보지 않는다(월간 무변경)", is.null(m6$diagnostics$rebalance$n_zero_vol_excluded))
d1 <- NEW$rep_next_trading_day(d0, days)
w7 <- run_raw(zero_on(d1, x0), WW)
chk("W7a 신호 다음 날 거래량 0 은 그 신호일 제외를 바꾸지 않는다(PIT)", x0 %in% w7$HOLDINGS_LOG[Date == e0]$Ticker)
r7 <- copy(RAW); r7[Date > d0, Ret := Ret * 3]
w7b <- run_raw(r7, WW)
chk("W7b 신호일 뒤 수익 섭동은 그 신호의 보유 · 비중을 바꾸지 않는다", isTRUE(all.equal(w7b$HOLDINGS_LOG[Date == e0], w3$HOLDINGS_LOG[Date == e0])))

cat("\n=== W8 비용 · W9 다음 거래일 ===\n")
nv <- w3$DAILY_NAV_DT
chk("W8 주간 리밸마다 비용 — NAV_net < NAV_gross · 회전 > 0 리밸 수 = 리밸 수",
    tail(nv$NAV, 1) < tail(nv$NAV_gross, 1) && sum(w3$PORTFOLIO_LOG$Turnover > 0) == nrow(w3$PORTFOLIO_LOG))
fri <- as.Date("2020-01-03"); sat <- as.Date("2020-01-04"); hol_eve <- as.Date("2020-05-04")
chk("W9 다음 거래일 — 금→월 · 토→월 · 공휴일 건너뜀 · 마지막 날 NA",
    identical(NEW$rep_next_trading_day(fri, days), as.Date("2020-01-06")) && identical(NEW$rep_next_trading_day(sat, days), as.Date("2020-01-06")) &&
      identical(NEW$rep_next_trading_day(hol_eve, days), as.Date("2020-05-06")) && is.na(NEW$rep_next_trading_day(max(days), days)))

cat("\n=== W10 러너 진술 — 실현 주기 · FIDELITY 자동 신고 ===\n")
rp_exprs <- parse(file.path(root, "02_Infrastructure/alpha_search/run_paper_replication.R"), keep.source = FALSE, encoding = "UTF-8")
.is_def <- function(e, nm) is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), nm)
SP <- new.env(parent = NEW)                                  # rep_exec_statement 등 하네스 함수가 보이게
SP$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
sys.source(file.path(root, "02_Infrastructure/contracts/measurement_axis.R"), envir = SP, keep.source = FALSE)   # ma_fidelity_universe(MC1)
for (nm in c(".rp_abs_path", ".rp_fidelity_text", ".rp_strategy_spec")) {
  hit <- Filter(function(e) .is_def(e, nm), as.list(rp_exprs))
  if (length(hit) == 1L) eval(hit[[1]], envir = SP) else chk(sprintf("W10 %s 정의 1건", nm), FALSE, sprintf("(%d건)", length(hit)))
}
base_txt <- "universe 치환(K200∪KQ150)만 — 그 외 논문 그대로 (v10 완전 충실구현)"
nmon <- run(NEW, WM)
chk("W10a 월간 = 구판 FIDELITY 문구 그대로(비트 동일 manifest)", identical(SP$.rp_fidelity_text(nmon$diagnostics$rebalance), base_txt) &&
      identical(SP$.rp_fidelity_text(NULL), base_txt))
ft <- SP$.rp_fidelity_text(w4$diagnostics$rebalance)
chk("W10b 일간 → 주간 변환을 자동 신고(주간 집행 · ★일간 신호 변환 · 신호 수)", grepl("주간 집행", ft) && grepl("★일간", ft) &&
      grepl(sprintf("신호 %d→%d", d4$n_signal_raw, d4$n_signal_used), ft, fixed = TRUE), ft)
eng0 <- tempfile(fileext = ".R"); writeLines("# 검사용", eng0)
spec_of <- function(sim, decl) SP$.rp_strategy_spec("WK", "idea", list(construction = "engine_direct", rebalance = decl), "K200_KQ150", sim, "https://example.org", eng0)
chk("W10c strategy_spec$rebalance = 실현 주기(선언보다 우선 · 주간 · 월간)", identical(spec_of(w4, "monthly")$rebalance, "weekly") &&
      identical(spec_of(nmon, "quarterly")$rebalance, "monthly"))
rp_txt <- paste(readLines(file.path(root, "02_Infrastructure/alpha_search/run_paper_replication.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chk("W10d 권위 기록이 FIDELITY 를 하네스 실현값에서 만든다(.rp_fidelity_text(sim_grade$diagnostics$rebalance, universe …)) · 주기 진단을 함께 싣는다",
    grepl("fidelity = .rp_fidelity_text(sim_grade$diagnostics$rebalance, universe", rp_txt, fixed = TRUE) &&   # (10-13 MC3) 뒤에 eff 인자가 붙는다 — 접두로 본다
      grepl("rebalance = sim_grade$diagnostics$rebalance,", rp_txt, fixed = TRUE))

fa <- SP$.rp_fidelity_text(nmon$diagnostics$rebalance, "ALL_HYG"); fw <- SP$.rp_fidelity_text(w4$diagnostics$rebalance, "ALL_HYG")
chk("W10e 새 축(ALL_HYG) 문구 — 전 종목 + 위생 명시(월간) · 주간 변환과 함께(주간) · 구 축 문구와 다름",
    grepl("전 종목 + 위생", fa, fixed = TRUE) && grepl("그 외 논문 그대로", fa, fixed = TRUE) && !identical(fa, base_txt) &&
      grepl("전 종목 + 위생", fw, fixed = TRUE) && grepl("주간 집행", fw, fixed = TRUE))
eff_cut <- list(status = "ok", date = "2003-06-30", breadth_mult = 2, n_dates_cut = 41L)
eff_0 <- modifyList(eff_cut, list(n_dates_cut = 0L))
fc <- SP$.rp_fidelity_text(nmon$diagnostics$rebalance, "ALL_HYG", eff = eff_cut)
chk("W10f (MC3 B) 계약이 얇은 초기 신호일을 잘랐으면 FIDELITY 가 자동 신고(실효 시작일 · 배수 · 제외 수) · 자르지 않았으면 문구 그대로 · 구 축은 eff 와 무관하게 구판 문구",
    grepl("실효 시작 2003-06-30", fc, fixed = TRUE) && grepl("41개 제외", fc, fixed = TRUE) &&
      identical(SP$.rp_fidelity_text(nmon$diagnostics$rebalance, "ALL_HYG", eff = eff_0), fa) &&
      identical(SP$.rp_fidelity_text(nmon$diagnostics$rebalance, NULL, eff = NULL), base_txt))
unlink(c(old_src, eng0))
cat(sprintf("\n== replication_weekly: PASS %d · FAIL %d ==\n", pass, fail))
cat(sprintf('{"test":"replication_weekly","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
