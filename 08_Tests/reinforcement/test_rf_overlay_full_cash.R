#==============================================================================
# test_rf_overlay_full_cash.R — 오버레이 '전액 현금 달'이 실제 현금으로 집행되는가 (2026-10-17 · 침묵 실패 수리 검사)
#
# 왜: 그 달 노출이 보유 전 종목 0 이면(게이트 0 · 문턱 이상 낙폭/난기류) 엔진이 그 신호일 행을 모두 지워 신호일이 사라졌고,
#   집행 하네스(신호일 집합 = unique(WEIGHTS$Date))는 직전 신호일의 보유창을 그 달까지 늘렸다 — '현금'이 '직전 보유 이월'로 측정됐다.
#   실측: P0R01_E2_C1(ts_mom_gate) 완전현금 95/261개월이 전부 수익 ≠ 0(2008-07~11 포함). 수리 = rf_cell_engine.R 의 표현 하한(.CASH_EPS).
#
# 재는 것 (양방향 · 합성 픽스처 · 스텁 arm 은 임시 루트에만):
#   1 스칼라 0/1 게이트 — 0 달 신호일이 남는다 · 그 달 Σw ≤ 1e-8 · > 0 · 로그 '현금 집행(표현 하한) k신호일' k = 0 달 수
#   2 벡터 arm 전 종목 0 달 — 같은 성질
#   3 하네스 — 0 달 보유창의 일 수익 |Rg| ≤ 1e-7 · 0 달 집행일 회전 ≈ 직전 Σw(전량 매도 비용 기장)
#   4 구판(수리 전 커밋) 빨강 — 0 달 신호일이 사라지고 하네스가 그 달에 직전 보유로 수익을 낸다(검출기가 결함을 잡는다)
#   5 회귀 — 0 달이 없는 오버레이는 구판과 PORTFOLIO 비트 동일
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_overlay_full_cash.R
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT   <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ENGINE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }

# ── 구판 엔진 = 수리 직전 커밋(48b3d3bfd)의 블롭 ─────────────────────────────
BASE_REF <- Sys.getenv("QVEST_RF_CASH_BASE_REF", "48b3d3bfd")
OLD <- file.path(tempdir(), sprintf("rf_cell_engine_precash_%d.R", Sys.getpid()))
.st <- tryCatch(system2("git", c("-C", shQuote(ROOT), "show", paste0(BASE_REF, ":02_Infrastructure/reinforcement/rf_cell_engine.R")),
                        stdout = OLD, stderr = FALSE), error = function(e) 1L)
HAVE_OLD <- identical(.st, 0L) && file.exists(OLD) && file.info(OLD)$size > 1000 && !any(grepl(".CASH_EPS", readLines(OLD, warn = FALSE), fixed = TRUE))
if (HAVE_OLD) ok(sprintf("구판 확보 — %s(표현 하한 없음)", BASE_REF)) else ng("구판 확보", "git show 실패 또는 이미 수리된 판")

# ── 합성 픽스처 — 종목 30 · 평일 2003-06~2012-12 (test_rf_engine_overlay_stack.R 와 같은 생성식) ──
set.seed(20260917L)
d <- seq(as.Date("2003-06-02"), as.Date("2012-12-31"), by = "day"); d <- d[as.integer(format(d, "%w")) %in% 1:5]
FIX <- CJ(Ticker = sprintf("T%03d", 1:30), Date = d); setorder(FIX, Ticker, Date)
FIX[, .r := rnorm(.N, 0.0002, 0.012)][, Close := 10000 * cumprod(1 + .r), by = Ticker][, .r := NULL]
FIX[, Vol := 2e6][, Size := Close * 1e6][, .id := as.integer(sub("T", "", Ticker, fixed = TRUE))]
FIX[, K200 := .id <= 20L][, KQ150 := FALSE][, Sector_Lv2 := paste0("S", (.id %% 5L) + 1L)][, .id := NULL]
BMF <- { .t <- copy(FIX); .t[, r := Close / shift(Close, 1L) - 1, by = Ticker]; .t[is.finite(r), .(BM_Ret = mean(r)), by = Date][order(Date)] }
SIG <- sort(FIX[Date >= as.Date("2005-01-01"), .(d = max(Date)), by = .(ym = format(Date, "%Y%m"))]$d)

STUB <- file.path(tempdir(), sprintf("rf_ovcash_%d", Sys.getpid()))
dir.create(file.path(STUB, "02_Infrastructure/validation"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(STUB, "02_Infrastructure/reinforcement/overlay_arms"), recursive = TRUE, showWarnings = FALSE)
for (.f in c("02_Infrastructure/validation/overlay_pit_guard.R", "02_Infrastructure/reinforcement/rf_rebalance.R",
             "02_Infrastructure/reinforcement/rf_sleeve.R", "02_Infrastructure/reinforcement/rf_axes.R", "02_Infrastructure/backtest_harness.R"))
  if (!file.copy(file.path(ROOT, .f), file.path(STUB, .f), overwrite = TRUE)) stop("스텁 루트 사본 실패: ", .f)
.arm <- function(kind, body) writeLines(body, file.path(STUB, "02_Infrastructure/reinforcement/overlay_arms", paste0(kind, ".R")))
.arm("stub_zero_even", c("# 짝수 달 0 · 홀수 달 1(축소 뒤 t ≥ n_min 짝수 달 = 정확히 0)",
                         "overlay_expo_stub_zero_even <- function(H, t, ctx) if (t %% 2L == 0L) 0 else 1"))
.arm("stub_vec_zero_even", c("# 짝수 달 보유 전부 e=0 · 홀수 달 앞 절반 0.5 · 나머지 1(횡단면 변동)",
                             "overlay_expo_stub_vec_zero_even <- function(H, t, ctx) {",
                             "  h <- ctx$hold; if (is.null(h) || !nrow(h)) return(1)",
                             "  tk <- sort(unique(as.character(h$Ticker)))",
                             "  if (t %% 2L == 0L) return(data.table::data.table(Ticker = tk, e = 0))",
                             "  data.table::data.table(Ticker = tk, e = ifelse(seq_along(tk) <= length(tk) / 2, 0.5, 1))",
                             "}"))
.arm("stub_scal", c("overlay_expo_stub_scal <- function(H, t, ctx) if (t %% 2L == 0L) 0.6 else 0.9"))

AXES <- list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150", start_date = "2005-01-01", commission_bps = 15L, liq_adv20_min = 2e8)
spec_of <- function(ov) list(code = "OVCASH", label = "overlay full cash", block = "T", fixed_axes = AXES,
                             base_signal = list(kind = "mom_12_1"), weighting = list(kind = "ew"),
                             universe = list(kind = "k200_kq150"), factor2 = list(kind = "none"), overlay = ov)
run_cell <- function(spec, engine = ENGINE, root = STUB) {
  p <- file.path(tempdir(), sprintf("rf_ovcash_spec_%d.json", Sys.getpid()))
  writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  old_root <- Sys.getenv("QM_ROOT", unset = NA); old_spec <- Sys.getenv("RF_CELL_SPEC", unset = NA)
  Sys.setenv(RF_CELL_SPEC = p, QM_ROOT = root)
  on.exit({ if (is.na(old_root)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = old_root)
            if (is.na(old_spec)) Sys.unsetenv("RF_CELL_SPEC") else Sys.setenv(RF_CELL_SPEC = old_spec) }, add = TRUE)
  env <- new.env(); assign("RAWDATA", copy(FIX), envir = env); assign("BM_DT", BMF, envir = env)
  err <- NULL
  lg <- utils::capture.output(suppressWarnings(suppressMessages(
    tryCatch(source(engine, local = env), error = function(e) err <<- conditionMessage(e)))))
  list(err = err, log = lg, port = if (exists("PORTFOLIO", envir = env, inherits = FALSE)) as.data.table(get("PORTFOLIO", envir = env))[order(Date, Ticker)] else NULL)
}
## 하네스 — get_execution_date 는 엔진과 같은 방식으로 backtest_harness.R 에서 정의만 꺼낸다
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/replication/replication_harness.R")))))
.ex <- parse(file.path(ROOT, "02_Infrastructure/backtest_harness.R"), encoding = "UTF-8", keep.source = FALSE)
.hit <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), "get_execution_date"), as.list(.ex))
assign("NA_Date_", as.Date(NA), envir = globalenv()); eval(.hit[[1]], envir = globalenv())
RAW <- copy(FIX)[, Ret := Close / shift(Close, 1L) - 1, by = Ticker]
harness <- function(port) run_replication_simulation(RAW, BMF, port[, .(Date, Ticker, Weight)], commission = 0.0015,
                                                     start_date = "2005-01-01", exec_price = "close_t1")
## 0 달 = 축소 가중 1(t ≥ n_min = 24) 인 짝수 t 의 신호일 — 엔진의 .M 은 BM 범위 안 신호일이고 SIG 와 같다
ZERO <- SIG[seq_along(SIG) >= 24L & seq_along(SIG) %% 2L == 0L]
cash_log_n <- function(lg) { s <- grep("현금 집행\\(표현 하한\\)", lg, value = TRUE); if (!length(s)) NA_integer_ else as.integer(sub(".*현금 집행\\(표현 하한\\) ([0-9]+)신호일.*", "\\1", s[length(s)])) }
win_ret <- function(sim, sigs) {                    # 신호일 s 의 보유창 (exec(s), exec(next)] 의 일 수익 Rg
  pl <- sim$PORTFOLIO_LOG[order(Signal_Date)]; D <- data.table(Date = as.Date(index(sim$strategy_gross_xts)), Rg = as.numeric(sim$strategy_gross_xts))
  rbindlist(lapply(which(pl$Signal_Date %in% sigs), function(i) {
    lo <- pl$Exec_Date[i]; hi <- if (i < nrow(pl)) pl$Exec_Date[i + 1L] else max(D$Date)
    D[Date > lo & Date <= hi, .(sig = pl$Signal_Date[i], Date, Rg)] }))
}

writeLines("=== 1. 스칼라 0/1 게이트 ===")
r1 <- run_cell(spec_of(list(kind = "stub_zero_even", arm_id = "stub_zero_even_x")))
if (is.null(r1$err) && !is.null(r1$port)) {
  s1 <- r1$port[, .(s = sum(Weight)), by = Date]
  z1 <- s1[Date %in% ZERO]
  if (nrow(z1) == length(ZERO) && all(z1$s > 0 & z1$s <= 1e-8)) ok(sprintf("1a 0 달 신호일 %d개 전부 남음 · Σw ∈ (0, 1e-8]", nrow(z1))) else
    ng("1a 0 달 신호일", sprintf("남은 %d / %d · Σw 최대 %.3e", nrow(z1), length(ZERO), max(c(0, z1$s))))
  if (identical(cash_log_n(r1$log), length(ZERO))) ok(sprintf("1b 로그 현금 집행 %d신호일 = 0 달 수", length(ZERO))) else ng("1b 로그 현금 집행 수", format(cash_log_n(r1$log)))
  if (all(s1[!(Date %in% ZERO) & Date >= SIG[24L]]$s > 0.99)) ok("1c 1 달은 Σw = 1(축소 끝난 뒤)") else ng("1c 1 달 Σw", "")
} else ng("1 실행", r1$err %||% "산출 없음")

writeLines("=== 2. 벡터 arm 전 종목 0 달 ===")
r2 <- run_cell(spec_of(list(kind = "stub_vec_zero_even", arm_id = "stub_vec_zero_even_x")))
if (is.null(r2$err) && !is.null(r2$port)) {
  z2 <- r2$port[, .(s = sum(Weight)), by = Date][Date %in% ZERO]
  if (nrow(z2) == length(ZERO) && all(z2$s > 0 & z2$s <= 1e-8) && identical(cash_log_n(r2$log), length(ZERO)))
    ok(sprintf("2 벡터 0 달 신호일 %d개 전부 남음 · Σw ∈ (0, 1e-8] · 로그 일치", nrow(z2))) else
    ng("2 벡터 0 달", sprintf("남은 %d / %d · 로그 %s", nrow(z2), length(ZERO), format(cash_log_n(r2$log))))
} else ng("2 실행", r2$err %||% "산출 없음")

writeLines("=== 3. 하네스 — 0 달 보유창이 현금이다 ===")
if (is.null(r1$err) && !is.null(r1$port)) {
  sim <- harness(r1$port); W0 <- win_ret(sim, ZERO)
  if (nrow(W0) && max(abs(W0$Rg)) <= 1e-7) ok(sprintf("3a 0 달 보유창 %d일 |Rg| 최대 %.1e ≤ 1e-7", nrow(W0), max(abs(W0$Rg)))) else
    ng("3a 0 달 보유창 수익", sprintf("%d일 · |Rg| 최대 %.3e", nrow(W0), if (nrow(W0)) max(abs(W0$Rg)) else NA))
  pl <- sim$PORTFOLIO_LOG[order(Signal_Date)]; tz <- pl[Signal_Date %in% ZERO]
  if (nrow(tz) && all(abs(tz$Turnover - 1) < 1e-6)) ok(sprintf("3b 0 달 집행일 회전 = 직전 Σw 1(전량 매도 비용 기장) · %d회", nrow(tz))) else
    ng("3b 0 달 회전", sprintf("%s", paste(head(round(tz$Turnover, 6)), collapse = ",")))
} else ng("3 하네스", "1 의 산출 없음")

writeLines("=== 4. 구판 빨강 — 결함 재현(검출기 양성 대조) ===")
if (HAVE_OLD) {
  r4 <- run_cell(spec_of(list(kind = "stub_zero_even", arm_id = "stub_zero_even_x")), engine = OLD)
  if (is.null(r4$err) && !is.null(r4$port)) {
    lost <- setdiff(ZERO, unique(r4$port$Date))
    if (length(lost) == length(ZERO)) ok(sprintf("4a 구판은 0 달 신호일 %d개를 지운다", length(lost))) else ng("4a 구판 신호일 소실", sprintf("%d / %d", length(lost), length(ZERO)))
    sim4 <- harness(r4$port); D4 <- data.table(Date = as.Date(index(sim4$strategy_gross_xts)), Rg = as.numeric(sim4$strategy_gross_xts))
    ex <- sort(unique(sim4$PORTFOLIO_LOG$Exec_Date)); zm <- format(ZERO, "%Y-%m")
    # 0 달 신호의 보유월(익월)에 해당하는 날 — 구판에선 직전 보유창이 그 달을 덮는다
    hm <- vapply(ZERO, function(z) format(seq(as.Date(format(z, "%Y-%m-01")), by = "month", length.out = 2L)[2L], "%Y-%m"), "")
    inv <- D4[format(Date, "%Y-%m") %in% hm & abs(Rg) > 1e-4]
    if (nrow(inv) > 0L) ok(sprintf("4b 구판 하네스는 0 달 보유월 %d일에 |Rg| > 1e-4 — 현금이 아니라 직전 보유", nrow(inv))) else ng("4b 구판 재현", "0 달 보유월에 수익이 없다")
  } else ng("4 구판 실행", r4$err %||% "산출 없음")
} else ng("4 구판", "구판 없음")

writeLines("=== 5. 회귀 — 0 달이 없는 오버레이는 구판과 비트 동일 ===")
if (HAVE_OLD) {
  a <- run_cell(spec_of(list(kind = "stub_scal", arm_id = "stub_scal_x"))); b <- run_cell(spec_of(list(kind = "stub_scal", arm_id = "stub_scal_x")), engine = OLD)
  if (is.null(a$err) && is.null(b$err) && identical(a$port$Date, b$port$Date) && identical(a$port$Ticker, b$port$Ticker) && identical(a$port$Weight, b$port$Weight) &&
      identical(cash_log_n(a$log), 0L)) ok(sprintf("5 stub_scal(0.6/0.9) PORTFOLIO %d행 비트 동일 · 현금 집행 0", nrow(a$port))) else
    ng("5 회귀", paste(a$err %||% "", b$err %||% ""))
} else ng("5 회귀", "구판 없음")

unlink(STUB, recursive = TRUE, force = TRUE); unlink(OLD, force = TRUE)
writeLines(sprintf("\n합계: 통과 %d · 실패 %d", PASS, FAIL))
cat(sprintf('{"test":"rf_overlay_full_cash","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
