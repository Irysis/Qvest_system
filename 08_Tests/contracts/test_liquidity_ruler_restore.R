#==============================================================================
# test_liquidity_ruler_restore.R — 헌법 유동성 자 **복원 경로** 계약 검사기 [FQ-232, 2026-08-10]
#
# 계약 (CLAUDE.md Production Constraints · .claude/rules/pit.md C10):
#   유동성 = **20일 평균 거래대금 >= 2e8**, 창이 t-1 에서 끝남(당일 미포함).
#
# 배경:
#   FQ-181 이 자를 이원화했다 — 일간 입력이면 헌법 자(adv20_t1), 월말-slim 입력이면
#   계산 불가라서 월말 1일치로 저하하고 'adv1_sameday_DEGRADED' 라벨을 붙인다.
#   실측(FQ-181 census): 호출부 149건 중 103건(69%)이 slim, 그중 51건이 liq 배선됨.
#   즉 **대다수 canonical 측정이 헌법 자가 아닌 자로 걸리고 있었다**.
#
# FQ-232 가 고친 것 두 가지:
#   ① 복원 경로: build_monthly_forward_returns(..., liq_daily=) 로 slim 입력에서도
#      20일 평균을 쓸 수 있다(호출부는 slim 직전까지 일간 패널을 들고 있으므로 I/O 0).
#   ② 소비 배선: canonical_screen_bt() 가 attr(liq_dt,'liq_ruler') 를 **읽어** 반환값에
#      기록하고 DEGRADED 면 경고한다. FQ-181 은 라벨을 발행만 했고 읽는 소비자가 0 이었다.
#
# ★이 검사기의 본체는 축 B 다. 라벨과 값이 **따로 놀 수 있다**는 것이 이 결함의 본질이므로
#   (주석은 "20d ADV at t-1", 코드는 1일치 — FQ-181 이 잡은 원형), 라벨만 보고 통과시키지
#   않고 **라벨이 주장하는 자로 실제 계산됐는지**를 값으로 검증한다. 돌연변이를 심어
#   그때 정말 FAIL 하는지 확인한다 — 오탐 제거와 검사 사망은 겉보기가 같다.
#
# ★대상 0 = SKIP (PASS 아님). 픽스처를 못 만들면 초록을 내지 않는다.
#
# 실행: Rscript 08_Tests/contracts/test_liquidity_ruler_restore.R
#       또는  Rscript -e 'source("08_Tests/contracts/test_liquidity_ruler_restore.R")'
#==============================================================================

suppressPackageStartupMessages({ library(data.table) })
data.table::setDTthreads(1)

## ── 자기 위치 해석 (r-portability 금칙④: CLAUDE_PROJECT_DIR 우선) ──────────────
.resolve_proj <- function() {
  marker <- "02_Infrastructure/ramp/factor_validation.R"
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a) && nzchar(a[1])) {
    p <- normalizePath(file.path(dirname(sub("^--file=", "", a[1])), "..", ".."),
                       winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(p, marker))) return(p)
  }
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, marker))]
  if (!length(hit)) stop("test_liquidity_ruler_restore: project root 미발견 — ",
                         "★러너 경로 실패이지 계약 실패가 아닙니다.")
  hit[1]
}
PROJ <- .resolve_proj(); setwd(PROJ)

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok   <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad  <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
skip <- function(n, m = "") { SKIP <<- SKIP + 1L; cat(sprintf("  SKIP: %s — %s\n", n, m)) }
eqf  <- function(a, b, tol = 1e-9) isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = tol))
## 경고를 삼키지 않고 **수집**한다 — "조용히 통과하지 않는가"가 계약이므로.
catch_warn <- function(expr) {
  w <- character(0)
  v <- withCallingHandlers(expr, warning = function(cond) {
    w <<- c(w, conditionMessage(cond)); invokeRestart("muffleWarning") })
  list(value = v, warnings = w)
}

suppressMessages(source(file.path(PROJ, "02_Infrastructure/ramp/factor_validation.R")))
suppressMessages(source(file.path(PROJ, "02_Infrastructure/contracts/canonical_screen_bt.R")))

{
## ── 픽스처: 결정론 일간 패널 ────────────────────────────────────────────────
## 240 거래일(약 12개월) x 30 종목. 거래대금 스케일을 문턱 2e8 주변에 걸쳐 놓아
## 자 변경이 통과/탈락을 실제로 가르게 한다(효과 없는 픽스처는 검사 사망과 같다).
set.seed(20260810)
NT <- 30L; ND <- 260L
dates <- seq.Date(as.Date("2020-01-01"), by = "day", length.out = 400)
dates <- dates[format(dates, "%u") %in% c("1","2","3","4","5")][seq_len(ND)]
tk <- sprintf("T%03d", seq_len(NT))
FX <- CJ(Date = dates, Ticker = tk)
FX[, Close := 1000 * (1 + 0.3 * (as.integer(sub("T", "", Ticker)) / NT)) *
       exp(cumsum(rnorm(.N, 0, 0.01))), by = Ticker]
## Vol: 종목별 기저 x 일별 잡음. 일부 종목은 월말 당일 거래 0 (1일치 자의 대표 실패모드)
FX[, Vol := pmax(0, round(rlnorm(.N, meanlog = log(2e5), sdlog = 0.8) *
       (0.2 + 1.8 * as.integer(sub("T", "", Ticker)) / NT))), by = Ticker]
FX[, Size := Close * 1e6]
FX[, `:=`(K200 = TRUE, KQ150 = FALSE)]
ME <- sort(FX[, .(Date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$Date)
## 월말 당일 Vol=0 을 일부 종목에 주입 (1일치 자면 탈락, 20일 자면 통과해야 함)
zero_tk <- tk[seq(1, NT, by = 5)]
FX[Date %in% ME & Ticker %in% zero_tk, Vol := 0]
FXME <- FX[Date %in% ME]
cat(sprintf("[fixture] 일간 %d행 · %d 거래일 · %d 종목 · 월말 %d개 · 월말Vol0 주입 종목 %d\n",
            nrow(FX), uniqueN(FX$Date), NT, length(ME), length(zero_tk)))
if (length(ME) < 4L || nrow(FXME) == 0L) {
  skip("fixture", "월말 앵커 부족 — 대상 0 이므로 SKIP(PASS 아님)")
} else {

## ── A. 복원 경로가 실제로 20일 평균(t-1) 을 쓰는가 ──────────────────────────
cat("\n[A] 복원 경로 정합\n")
ADV20 <- build_adv20_t1(FX[, .(Date, Ticker, Vol, Close)], at_dates = ME)
fwd_inj <- suppressWarnings(build_monthly_forward_returns(FXME, ME, liq_daily = ADV20))
if (identical(fwd_inj$liq_ruler, "adv20_t1")) ok("A1 주입(사전계산) → liq_ruler='adv20_t1'")
else bad("A1", sprintf("liq_ruler='%s'", fwd_inj$liq_ruler))
if (identical(fwd_inj$liq_ruler_source, "injected_adv20")) ok("A1b source='injected_adv20'")
else bad("A1b", sprintf("source='%s'", fwd_inj$liq_ruler_source))

## 손계산 대조 — 라벨이 아니라 **값**으로 검증한다
hand <- function(t_, d_) {
  v <- FX[Ticker == t_ & Date < d_][order(Date)]
  if (!nrow(v)) return(NA_real_)
  w <- utils::tail(v, 20L); mean(w$Vol * w$Close)
}
smp <- fwd_inj$liq_dt[!is.na(adv)][sample(.N, min(60L, .N))]
dv <- vapply(seq_len(nrow(smp)), function(i) hand(smp$Ticker[i], smp$Date[i]), numeric(1))
mx <- max(abs(dv - smp$adv), na.rm = TRUE)
if (is.finite(mx) && mx < 1e-6) ok("A2 손계산 20일평균(t-1) 대조", sprintf("%d 지점 max|Δ|=%.3g", nrow(smp), mx))
else bad("A2", sprintf("max|Δ|=%.3g (%d 지점)", mx, nrow(smp)))

## 당일 미포함 — 앵커 당일 거래대금을 폭파해도 그 앵커의 adv 는 불변이어야 한다.
## ★교란은 **마지막 앵커 하루에만** 준다. 초판은 모든 월말에 줬는데, 20 거래일 창은
##   직전 월말을 포함하므로(월 ≈ 21 거래일) 그건 창 안의 정당한 관측을 함께 바꾼 것이었다
##   — A3 초판 FAIL 은 코드 결함이 아니라 내 픽스처 설계 오류였다(당일 배제는 A2 손계산이
##   이미 확인). 교란일 이후 앵커가 없어야 창 오염이 원천 차단되므로 마지막 앵커를 쓴다.
D_STAR <- max(ME)
FX2 <- copy(FX); FX2[Date == D_STAR, Vol := 1e15]
ADV20b <- build_adv20_t1(FX2[, .(Date, Ticker, Vol, Close)], at_dates = ME)
a_star <- ADV20[Date == D_STAR][order(Ticker)]; b_star <- ADV20b[Date == D_STAR][order(Ticker)]
if (nrow(a_star) && eqf(a_star$adv, b_star$adv))
  ok("A3 당일 미포함(t-1)", sprintf("앵커 %s 당일 Vol=1e15 주입에도 adv 불변 (n=%d)",
                                    D_STAR, nrow(a_star)))
else bad("A3", "앵커 당일 값이 그 앵커의 adv 에 새어들어감 — 창이 t 에서 끝남")

## 일간 패널 직접 주입도 같은 결과여야 한다
fwd_inj2 <- suppressWarnings(build_monthly_forward_returns(
  FXME, ME, liq_daily = FX[, .(Date, Ticker, Vol, Close)]))
if (identical(fwd_inj2$liq_ruler, "adv20_t1") &&
    identical(fwd_inj2$liq_ruler_source, "injected_daily") &&
    eqf(fwd_inj$liq_dt$adv, fwd_inj2$liq_dt$adv))
  ok("A4 일간패널 주입 == 사전계산 주입")
else bad("A4", "두 주입 형태가 다른 값/라벨을 냄")

## FQ-181 경로 보존: 일간 입력 자체를 넘기면 인자 없이도 헌법 자
fwd_daily <- suppressWarnings(build_monthly_forward_returns(FX, ME))
if (identical(fwd_daily$liq_ruler, "adv20_t1") &&
    identical(fwd_daily$liq_ruler_source, "input_daily"))
  ok("A5 FQ-181 경로 보존", "일간 입력 → adv20_t1(input_daily)")
else bad("A5", sprintf("ruler='%s' source='%s'", fwd_daily$liq_ruler, fwd_daily$liq_ruler_source))

## ── B. 기본 동작 무변경 + 저하 자백 ─────────────────────────────────────────
cat("\n[B] 기본 동작 무변경 · 저하 자백\n")
cw <- catch_warn(build_monthly_forward_returns(FXME, ME))
fwd_deg <- cw$value
if (identical(fwd_deg$liq_ruler, "adv1_sameday_DEGRADED")) ok("B1 slim + 무인자 → DEGRADED 유지(기본 무변경)")
else bad("B1", sprintf("liq_ruler='%s'", fwd_deg$liq_ruler))
if (any(grepl("DEGRADED", cw$warnings, fixed = TRUE)))
  ok("B2 저하가 조용하지 않다", sprintf("warning %d건 발행", length(cw$warnings)))
else bad("B2", "저하인데 warning 미발행 — 침묵 저하")
## 값 자구 검증: DEGRADED 는 정확히 월말 1일치 Vol*Close 여야 한다
chk <- merge(fwd_deg$liq_dt, FXME[, .(Date, Ticker, dv1 = Vol * Close)], by = c("Date","Ticker"))
if (nrow(chk) && eqf(chk$adv, chk$dv1)) ok("B3 DEGRADED 값 = 월말 1일치 Vol*Close", sprintf("n=%d", nrow(chk)))
else bad("B3", "DEGRADED 라벨인데 값이 1일치가 아님")
## 자는 수익/벤치를 침범하지 않는다 (무관축 불변 = 양성 대조의 짝)
if (isTRUE(all.equal(fwd_deg$returns_dt, fwd_inj$returns_dt)) &&
    isTRUE(all.equal(fwd_deg$bench_dt, fwd_inj$bench_dt)))
  ok("B4 무관축 불변", "자 변경이 returns_dt/bench_dt 를 바꾸지 않음")
else bad("B4", "자 변경이 수익/벤치를 건드림")

## strict 모드: 경고가 아니라 중단
Sys.setenv(QVEST_LIQ_RULER_STRICT = "1")
e <- tryCatch({ build_monthly_forward_returns(FXME, ME); NULL }, error = function(e) e)
Sys.unsetenv("QVEST_LIQ_RULER_STRICT")
if (!is.null(e)) ok("B5 QVEST_LIQ_RULER_STRICT=1 → stop")
else bad("B5", "strict 인데 통과함")
e2 <- tryCatch({ build_monthly_forward_returns(FXME, ME, liq_strict = TRUE); NULL },
               error = function(e) e)
if (!is.null(e2)) ok("B5b liq_strict=TRUE → stop") else bad("B5b", "strict 인자 무시됨")

## ── C. 위반 주입 (본체) ─────────────────────────────────────────────────────
cat("\n[C] 위반 주입 — 검사가 실제로 FAIL 하는가\n")
## C1: 창폭 20 → 1 돌연변이 (헌법 자를 1일치로 되돌림)
mut_w1 <- function(daily, at_dates = NULL) {
  DV <- as.data.table(daily)[, .(Ticker, Date = as.Date(Date), dval = Vol * Close)]
  setorder(DV, Ticker, Date)
  DV[, adv := shift(frollmean(dval, n = 1L), 1L), by = Ticker]      # 창폭 1
  if (is.null(at_dates)) DV[, .(Date, Ticker, adv)] else DV[Date %in% as.Date(at_dates), .(Date, Ticker, adv)]
}
M1 <- mut_w1(FX[, .(Date, Ticker, Vol, Close)], at_dates = ME)
MM <- merge(M1, ADV20, by = c("Date","Ticker"), suffixes = c("_mut","_ok"))
d1 <- sum(!is.na(MM$adv_mut) & !is.na(MM$adv_ok) & abs(MM$adv_mut - MM$adv_ok) > 1e-6)
if (d1 > 0) ok("C1 위반주입: 창폭 20→1", sprintf("A2 축이 검출 — %d/%d 지점 불일치", d1, nrow(MM)))
else bad("C1", "창폭 1 돌연변이를 A2 축이 못 잡음 — 검사 사망")

## C2: shift(1) 제거 돌연변이 (당일 포함)
mut_ns <- function(daily, at_dates = NULL) {
  DV <- as.data.table(daily)[, .(Ticker, Date = as.Date(Date), dval = Vol * Close)]
  setorder(DV, Ticker, Date)
  DV[, adv := frollmean(dval, n = pmin(seq_len(.N), 20L), adaptive = TRUE, na.rm = TRUE), by = Ticker]
  if (is.null(at_dates)) DV[, .(Date, Ticker, adv)] else DV[Date %in% as.Date(at_dates), .(Date, Ticker, adv)]
}
## A3 와 **동일한 교란**(마지막 앵커 하루)을 써야 축의 검출력을 재는 것이 된다.
Ma <- mut_ns(FX[, .(Date, Ticker, Vol, Close)],  at_dates = ME)[Date == D_STAR][order(Ticker)]
Mb <- mut_ns(FX2[, .(Date, Ticker, Vol, Close)], at_dates = ME)[Date == D_STAR][order(Ticker)]
if (nrow(Ma) && !eqf(Ma$adv, Mb$adv)) ok("C2 위반주입: shift(1) 제거", "A3(당일 미포함) 축이 검출")
else bad("C2", "당일포함 돌연변이를 A3 축이 못 잡음 — 검사 사망")

## C3: ★라벨만 헌법 자로 바꾸고 값은 1일치인 '조용한 통과' 시나리오
##     — 이 결함의 원형(주석은 20d, 코드는 1일치)이므로 라벨-값 정합 검사가 핵심 방어선이다.
fake <- copy(fwd_deg$liq_dt)                       # 값 = 1일치
data.table::setattr(fake, "liq_ruler", "adv20_t1") # 라벨만 헌법 자
lv <- merge(fake, ADV20, by = c("Date","Ticker"), suffixes = c("_claim","_true"))
mis <- sum(!is.na(lv$adv_claim) & !is.na(lv$adv_true) & abs(lv$adv_claim - lv$adv_true) > 1e-6)
if (mis > 0) ok("C3 위반주입: 라벨만 adv20_t1(값은 1일치)",
                sprintf("라벨-값 정합 검사가 검출 — %d/%d 불일치", mis, nrow(lv)))
else bad("C3", "라벨 위조를 못 잡음 — 라벨 신뢰가 무근거")

## C4: liq_daily 컬럼이 어느 갈래도 아닐 때 조용히 통과하지 않는가
e3 <- tryCatch({ build_monthly_forward_returns(FXME, ME,
        liq_daily = data.table(Date = ME, Ticker = tk[1], foo = 1)); NULL }, error = function(e) e)
if (!is.null(e3)) ok("C4 미지 컬럼 liq_daily → stop", "결손을 정상값으로 내려앉히지 않음")
else bad("C4", "알 수 없는 형태를 조용히 수용함")

## C5: 덮개 결손(vintage 불일치)을 경고하는가
half <- ADV20[Date %in% ME[seq_len(max(1L, floor(length(ME)/2)))]]
cw2 <- catch_warn(build_monthly_forward_returns(FXME, ME, liq_daily = half))
if (any(grepl("덮음", cw2$warnings, fixed = TRUE))) ok("C5 앵커 덮개 결손 경고")
else bad("C5", "덮개 절반인데 무경고 — 결손이 통과로 내려앉음")

## ── D. 소비 지점(canonical_screen_bt)이 라벨을 읽는가 ───────────────────────
cat("\n[D] 소비 배선 — 라벨을 읽고 기록하는가\n")
ret <- fwd_deg$returns_dt; bench <- fwd_deg$bench_dt
if (!nrow(ret) || !nrow(bench)) {
  skip("D", "픽스처 returns/bench 0행 — 대상 0 이므로 SKIP")
} else {
  set.seed(11)
  SC <- unique(ret[, .(Date, Ticker)]); SC[, score := runif(.N)]
  cwd <- catch_warn(canonical_screen_bt(SC, ret, bench, top_n = 5L, cost_bps_oneway = 15,
          liq_dt = fwd_deg$liq_dt, liq_min = 2e8, run_id = "t", strategy_id = "t",
          diag_dual_basis = FALSE))
  rd <- cwd$value
  if (identical(rd$liq_ruler, "adv1_sameday_DEGRADED")) ok("D1 반환값에 자 라벨 기록")
  else bad("D1", sprintf("liq_ruler='%s'", rd$liq_ruler %||% "NULL"))
  if (any(grepl("adv1_sameday_DEGRADED", cwd$warnings, fixed = TRUE)))
    ok("D2 소비 지점에서 DEGRADED 경고 발행", "'발행은 하는데 아무도 안 읽는' 상태 해소")
  else bad("D2", "소비 지점이 DEGRADED 를 조용히 통과시킴")
  lf <- rd$liq_filter
  if (!is.null(lf) && isTRUE(lf$applied) && lf$n_before - lf$n_after == lf$n_dropped)
    ok("D3 liq_filter 회계 정합", sprintf("before %d → after %d (drop %d, NA통과 %d)",
        lf$n_before, lf$n_after, lf$n_dropped, lf$n_na_pass))
  else bad("D3", "liq_filter 회계 불일치")

  rr <- suppressWarnings(canonical_screen_bt(SC, ret, bench, top_n = 5L, cost_bps_oneway = 15,
          liq_dt = fwd_inj$liq_dt, liq_min = 2e8, run_id = "t", strategy_id = "t",
          diag_dual_basis = FALSE))
  if (identical(rr$liq_ruler, "adv20_t1")) ok("D4 복원 자 라벨이 소비지점까지 도달")
  else bad("D4", sprintf("liq_ruler='%s'", rr$liq_ruler %||% "NULL"))

  ## 라벨 없는 liq_dt → 'unlabeled' + 경고 (자 불명을 정상으로 취급하지 않음)
  nolab <- data.table(Date = fwd_deg$liq_dt$Date, Ticker = fwd_deg$liq_dt$Ticker,
                      adv = fwd_deg$liq_dt$adv)
  cwn <- catch_warn(canonical_screen_bt(SC, ret, bench, top_n = 5L, liq_dt = nolab,
          liq_min = 2e8, run_id = "t", strategy_id = "t", diag_dual_basis = FALSE))
  if (identical(cwn$value$liq_ruler, "unlabeled") &&
      any(grepl("자 라벨", cwn$warnings, fixed = TRUE))) ok("D5 무라벨 liq_dt → 'unlabeled' + 경고")
  else bad("D5", sprintf("liq_ruler='%s' warn=%d", cwn$value$liq_ruler %||% "NULL", length(cwn$warnings)))

  ## liq_dt=NULL → 무필터도 라벨로 남는다(무필터가 침묵하지 않도록)
  rn <- suppressWarnings(canonical_screen_bt(SC, ret, bench, top_n = 5L, liq_dt = NULL,
          run_id = "t", strategy_id = "t", diag_dual_basis = FALSE))
  if (identical(rn$liq_ruler, "none_no_liquidity_filter") && isFALSE(rn$liq_filter$applied))
    ok("D6 무필터도 라벨로 기록")
  else bad("D6", sprintf("liq_ruler='%s'", rn$liq_ruler %||% "NULL"))

  ## strict 소비: DEGRADED 를 stop 으로 승격
  Sys.setenv(QVEST_LIQ_RULER_STRICT = "1")
  e4 <- tryCatch({ canonical_screen_bt(SC, ret, bench, top_n = 5L, liq_dt = fwd_deg$liq_dt,
          liq_min = 2e8, run_id = "t", strategy_id = "t", diag_dual_basis = FALSE); NULL },
          error = function(e) e)
  Sys.unsetenv("QVEST_LIQ_RULER_STRICT")
  if (!is.null(e4)) ok("D7 strict 소비 → stop") else bad("D7", "strict 인데 소비가 통과")

  ## ── E. 양성 대조 (계측 생존) — 같은 실행에서 ────────────────────────────
  cat("\n[E] 양성 대조 + 무관축 불변\n")
  sel <- function(LIQ, lmin) {
    X <- copy(SC)[!is.na(score)]
    if (!is.null(LIQ)) { X <- merge(X, as.data.table(LIQ)[, .(Date, Ticker, adv)],
                                    by = c("Date","Ticker"), all.x = TRUE)
                         X <- X[is.na(adv) | adv >= lmin]; X[, adv := NULL] }
    setorder(X, Date, -score); X[, .(Ticker = Ticker[seq_len(min(5L, .N))]), by = Date]
  }
  ## 극단 문턱은 **일부만** 남기는 값으로 잡는다 — 0행이 되면 무관축(E3)이 잴 대상을
  ## 잃어 -Inf 가 되고, 그건 "제약 준수"가 아니라 대상 0 이다.
  q_hi <- as.numeric(stats::quantile(fwd_inj$liq_dt$adv, 0.90, na.rm = TRUE))
  s_base <- sel(fwd_inj$liq_dt, 2e8); s_ext <- sel(fwd_inj$liq_dt, q_hi)
  maxn <- function(D) if (!nrow(D)) NA_integer_ else D[, .N, by = Date][, max(N)]
  if (nrow(s_ext) < nrow(s_base)) ok("E1 양성 대조: 문턱 극단화가 멤버십을 바꾼다",
      sprintf("liq_min 2e8 → %.3g: 선정 %d → %d행", q_hi, nrow(s_base), nrow(s_ext)))
  else bad("E1", "문턱을 90분위로 올려도 선정이 그대로 — 유동성 필터가 죽어 있음(계측 사망)")
  s_zero <- sel(fwd_inj$liq_dt, 0); s_nof <- sel(NULL, 0)
  if (nrow(s_zero) == nrow(s_nof)) ok("E2 음성 방향: liq_min=0 == 무필터")
  else bad("E2", sprintf("liq_min=0 %d행 vs 무필터 %d행", nrow(s_zero), nrow(s_nof)))
  ## 무관축(종목수 제약)은 자·문턱과 무관하게 불변이어야 한다
  mxs <- c(maxn(s_base), maxn(s_ext), maxn(sel(fwd_deg$liq_dt, 2e8)))
  if (all(is.na(mxs))) skip("E3", "세 arm 전부 선정 0행 — 대상 0 이므로 SKIP(PASS 아님)")
  else if (max(mxs, na.rm = TRUE) <= 5L)
    ok("E3 무관축 불변: top_n 제약", sprintf("max 선정수 %d <= 5", max(mxs, na.rm = TRUE)))
  else bad("E3", sprintf("top_n 초과 — max %d", max(mxs, na.rm = TRUE)))
}
}

cat(sprintf("\n[test_liquidity_ruler_restore] PASS %d / FAIL %d / SKIP %d\n", PASS, FAIL, SKIP))
# 요약 JSON 계약 — run_all_hooks.sh 는 **마지막 줄**을 JSON 으로 파싱한다. 이 줄이 없으면
# 27/0 로 전부 통과해도 배터리가 "UNREPORTED"로 실패 계상한다(2026-08-16 실측: FINAL 8 fail
# 중 2건이 이 형태 = 초록 스위트의 영구 빨간 줄). 사람용 줄은 위에 남기고 JSON 을 끝에 둔다.
cat(sprintf('{"test":"liquidity_ruler_restore","pass":%d,"fail":%d,"skipped":%d,"total":%d}\n',
            PASS, FAIL, SKIP, PASS + FAIL))
if (FAIL > 0L) {
  if (!interactive() && length(grep("^--file=", commandArgs(FALSE)))) quit(status = 1L)
  stop(sprintf("test_liquidity_ruler_restore: %d FAIL", FAIL))
}
}
