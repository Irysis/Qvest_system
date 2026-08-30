#==============================================================================
# test_rf_cell_engine_smoke.R — rf_cell_engine.R **실행** 스모크 (2026-08-30)
#
# 왜 필요한가 (실사고):
#   2026-08-30 N-ary 팩터 리팩터가 .f2/.f3 를 .flist/.tags 로 바꾸면서 파일 마지막
#   로그 문장만 구 변수를 그대로 남겼다. B1_1~B1_5 다섯 칸이 무거운 계산을 전부
#   끝낸 뒤 마지막 줄에서 "객체 '.f2' 를 찾을 수 없습니다" 로 죽어 등급 0건.
#   그런데 배터리 1번 섹션은 엔진에 parse() 만 건다 — 문법은 멀쩡하고 미정의 변수는
#   런타임 오류라 전 항목이 초록이었다. 계기가 잴 것을 안 재고 재기 쉬운 것을 쟀다.
#
# 그래서 이 검사는 엔진을 **실제로 평가**한다. 양방향:
#   ①양성 대조 — 합성 픽스처 위에서 4경로가 실제로 산출물을 만든다
#   ②위반 주입 — 같은 결함(미정의 변수)을 심은 사본은 반드시 실패한다.
#                 동시에 그 사본이 parse() 는 통과함을 확인한다 = 구 계기의 맹점 실증
#
# 부작용 없음: 픽스처·스펙·변조 사본 전부 tempdir. 원장·산출물·설정 무접촉.
# 실행: Rscript 08_Tests/reinforcement/test_rf_cell_engine_smoke.R
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })

ROOT   <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ENGINE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R")
# R 4.4 이전엔 %||% 가 base 에 없다 — 검사가 그 차이로 죽지 않게 직접 정의한다.
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }

# ── 픽스처 — 종목 30 · 평일 2003-06~2006-12 ──────────────────────────────────
#   mom_12_1 은 252일, sigma60 은 60일 창이 필요하다. start_date(2005-01-01) 앞에
#   1년 반을 둬서 시그널일이 창 부족으로 전멸하지 않게 한다.
#   Close*Vol 은 유동성 하한 2e8 을 항상 넘도록 잡는다 — 이 검사의 대상은 배관이지
#   선별 경제학이 아니다.
make_fixture <- function(idx_n = 20L) {
  set.seed(20260830L)
  d <- seq(as.Date("2003-06-02"), as.Date("2006-12-29"), by = "day")
  d <- d[as.integer(format(d, "%w")) %in% 1:5]
  tk <- sprintf("T%03d", 1:30)
  x <- CJ(Ticker = tk, Date = d)
  setorder(x, Ticker, Date)
  x[, .r := rnorm(.N, 0.0002, 0.012)]
  x[, Close := 10000 * cumprod(1 + .r), by = Ticker]
  x[, .r := NULL]
  x[, Vol  := 200000]
  x[, Size := Close * 1e6]
  # 지수 멤버 idx_n 종 + 비지수 나머지 — all_listed 처치가 실제로 넓히는지 보려면 밖이 있어야 한다
  x[, K200 := as.integer(sub("T", "", Ticker, fixed = TRUE)) <= idx_n]
  x[, KQ150 := FALSE]
  x[, Sector_Lv2 := paste0("S", (as.integer(sub("T", "", Ticker, fixed = TRUE)) %% 5L) + 1L)]
  x[]
}
FIX <- make_fixture(20L)          # 30종 중 20종만 지수 멤버
FIX_ALL <- make_fixture(30L)      # 전 종목이 지수 멤버 = 넓힐 대상 없음

AXES <- list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150",
             start_date = "2005-01-01", commission_bps = 15L, liq_adv20_min = 2e8)
PX <- list(kind = "price", id = "lowvol60")   # 오프라인 자기완결 팩터(DB 미접촉)

# 스펙을 파일로 굽고 엔진을 격리 env 에서 평가한다.
#   엔진은 DT <- RAWDATA 로 **참조**를 잡고 열을 추가하므로 매번 copy() 를 넘긴다.
run_cell <- function(spec, engine = ENGINE, fixture = FIX) {
  p <- file.path(tempdir(), "rf_smoke_spec.json")
  writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  Sys.setenv(RF_CELL_SPEC = p)
  env <- new.env()
  assign("RAWDATA", copy(fixture), envir = env)
  err <- NULL
  suppressWarnings(suppressMessages(
    tryCatch(source(engine, local = env), error = function(e) err <<- conditionMessage(e))))
  list(err = err, env = env,
       out = if (exists("PORTFOLIO", envir = env, inherits = FALSE)) "PORTFOLIO"
             else if (exists("FACTORS", envir = env, inherits = FALSE)) "FACTORS" else NA_character_)
}

base_spec <- function(...) modifyList(list(
  code = "SMOKE", label = "smoke", block = "T", fixed_axes = AXES,
  base_signal = list(kind = "mom_12_1"),
  weighting = list(kind = "ew"), universe = list(kind = "k200_kq150")), list(...))

writeLines("=== A. 양성 대조 — 엔진이 실제로 산출물을 만드는가 ===")

# A1. 팩터 없음(kind="none") = 기저 신호 단독 — B4 LOO '팩터 제외' 가 타는 경로
r <- run_cell(base_spec(factor2 = list(kind = "none")))
if (is.null(r$err) && identical(r$out, "FACTORS")) {
  n <- nrow(get("FACTORS", envir = r$env))
  if (n > 0L) ok(paste0("factor none(기저 단독) → FACTORS ", n, "행")) else ng("factor none", "0행")
} else ng("factor none", r$err %||% "산출물 없음")

# A2. 1팩터 — B1 블록이 타는 경로(구 factor2 키 하위호환)
r <- run_cell(base_spec(factor2 = PX))
if (is.null(r$err) && identical(r$out, "FACTORS")) ok("1팩터(factor2 하위호환) → FACTORS") else
  ng("1팩터", r$err %||% "산출물 없음")

# A3. 3팩터 N-ary — 2026-08-30 리팩터가 연 경로(B4_20). 여기가 오늘 결함의 진원지다
r <- run_cell(base_spec(factors = list(PX, PX, PX)))
if (is.null(r$err) && identical(r$out, "FACTORS")) ok("3팩터 N-ary(factors 배열) → FACTORS") else
  ng("3팩터 N-ary", r$err %||% "산출물 없음")

# A4. 비EW 비중 — B2 블록 경로. PORTFOLIO 계약 + Sigma w = 1 까지 본다
r <- run_cell(base_spec(factor2 = PX, weighting = list(kind = "inv_vol", window = 60L)))
if (is.null(r$err) && identical(r$out, "PORTFOLIO")) {
  P <- get("PORTFOLIO", envir = r$env)
  s <- P[, .(s = sum(Weight)), by = Date]
  if (max(abs(s$s - 1)) < 1e-8 && min(P$Weight) >= 0) ok("비EW(inv_vol) → PORTFOLIO · long-only · Sigma w=1")
  else ng("비EW 비중", "Sigma w != 1 또는 음수 비중")
} else ng("비EW 비중", r$err %||% "PORTFOLIO 없음")

# A5. 카탈로그 비중 — B2 블록이 타는 경로. 이 항이 없어서 두 결함이 동시에 살아남았다:
#     ①엔진에 catalog 분기 자체가 없어 B2 5칸 전멸 ②다리를 놔도 lean 빌트인 arm 은
#     calc_*_weights 가 안 보이면 조용히 EW 로 폴백(5종 중 4종 실측). 그래서 산출이
#     **EW 와 다른지**까지 본다 — 도는 것과 처치가 전달되는 것은 다른 사건이다.
r <- run_cell(base_spec(factor2 = PX, weighting = list(kind = "catalog", catalog_id = "lean:ivol")))
if (is.null(r$err) && identical(r$out, "PORTFOLIO")) {
  P <- get("PORTFOLIO", envir = r$env)
  s <- P[, .(s = sum(Weight)), by = Date]
  disp <- P[, .(sd = stats::sd(Weight)), by = Date]
  if (max(abs(s$s - 1)) > 1e-8) ng("카탈로그 비중", "Sigma w != 1")
  else if (max(disp$sd, na.rm = TRUE) < 1e-10) ng("카탈로그 비중", "전 시점 EW — 처치 미전달(조용한 폴백)")
  else ok(sprintf("카탈로그 arm(lean:ivol) → PORTFOLIO · EW 아님(최대 비중 sd %.5f)", max(disp$sd, na.rm = TRUE)))
} else ng("카탈로그 비중", r$err %||% "PORTFOLIO 없음")

# A6/A7. 유니버스 처치 전달 (양방향) — 2026-08-30 실측: B3_11(지수 멤버십 해제)이
#   B1_5 와 보유 777/777 완전 동일한 포트폴리오로 등급 B 를 받았다. 기저 신호가 지수
#   멤버 위에서만 정의돼 있어 '해제' 가 넓힐 대상이 없었다 — 처치 미전달인데 수치는 나온다.
r6 <- run_cell(base_spec(factor2 = list(kind = "none"), universe = list(kind = "all_listed")), fixture = FIX)
r6k <- run_cell(base_spec(factor2 = list(kind = "none")), fixture = FIX)
if (is.null(r6$err) && is.null(r6k$err)) {
  n_all <- length(unique(get("FACTORS", envir = r6$env)$Ticker))
  n_idx <- length(unique(get("FACTORS", envir = r6k$env)$Ticker))
  if (n_all > n_idx) ok(sprintf("all_listed 가 실제로 넓힌다(종목 %d > 지수 %d)", n_all, n_idx))
  else ng("all_listed 처치 미전달", sprintf("종목 %d = 지수 %d", n_all, n_idx))
} else ng("all_listed 정상 경로", r6$err %||% r6k$err)

r7 <- run_cell(base_spec(factor2 = list(kind = "none"), universe = list(kind = "all_listed")), fixture = FIX_ALL)
if (!is.null(r7$err) && grepl("처치 미전달", r7$err)) {
  ok("넓힐 대상이 없으면 실패로 끊는다(위반 주입)")
} else ng("미전달 가드 미작동", "같은 포트폴리오에 다른 이름이 붙는다")

writeLines("=== B. 위반 주입 — 같은 결함을 심으면 반드시 잡히는가 ===")

# 오늘의 결함을 재현한다: 마지막 로그 줄의 .flist 를 미정의 변수로 바꾼다.
src <- readLines(ENGINE, warn = FALSE)
hit <- grep("vapply(.flist", src, fixed = TRUE)
if (!length(hit)) {
  ng("위반 주입 지점", "마지막 로그 줄을 못 찾음 — 엔진이 바뀌었으면 이 검사도 옮겨야 한다")
} else {
  mut <- src
  mut[max(hit)] <- sub(".flist", ".f2ghost", mut[max(hit)], fixed = TRUE)
  mp <- file.path(tempdir(), "rf_cell_engine_mutant.R")
  writeLines(mut, mp)

  # B1. 구 계기(parse)는 이 결함을 못 본다 — 맹점 실증
  if (!inherits(tryCatch(parse(mp), error = function(e) e), "error"))
    ok("변조본이 parse() 는 통과 = 구문 검사만으로는 못 잡는다(맹점 실증)")
  else ng("변조본 parse", "변조가 문법을 깨뜨렸다 — 같은 결함 계열이 아니다")

  # B2. 새 계기는 잡는다
  r <- run_cell(base_spec(factor2 = PX), engine = mp)
  if (!is.null(r$err) && grepl("f2ghost", r$err, fixed = TRUE))
    ok("변조본은 실행에서 실패 = 미정의 변수 결함을 잡는다")
  else ng("위반 주입", "변조본이 통과했다 — 이 검사는 방어선이 아니다")
}

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
if (FAIL > 0L) quit(status = 1L)
