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

AXES <- list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150",
             start_date = "2005-01-01", commission_bps = 15L, liq_adv20_min = 2e8)

# ── 픽스처 — 종목 50 · 평일 2003-06~2016-12 ──────────────────────────────────
#   mom_12_1 은 252일, sigma60 은 60일 창이 필요하다. start_date(2005-01-01) 앞에
#   1년 반을 둬서 시그널일이 창 부족으로 전멸하지 않게 한다.
#   Close*Vol 은 유동성 하한 2e8 을 항상 넘도록 잡는다 — 이 검사의 대상은 배관이지
#   선별 경제학이 아니다.
#   ★지수 멤버 수 > n_max (2026-09-17 수리): 엔진 5a 가드(09-13 a82898255)는 기저 후보 중앙이 n_max 이하인
#   칸에 팩터가 붙으면 멈춘다. 구 픽스처(30종 중 멤버 20)가 그 가드에 걸려 팩터를 붙인 항목(A2~A5·A8·A9·B2)이
#   전부 가드 문자열로 죽었다 — 09-13 이후 이 스모크는 엔진 실행이 아니라 가드 하나만 재고 있었다.
#   가드는 옳다. 고칠 곳은 픽스처이고, 가드는 A10~A12 가 좁은 픽스처로 따로 잰다.
#   추첨 순서가 (Ticker, Date) 라 종목을 늘려도 T001~T030 의 가격 경로는 구판과 같다.
IDX_N <- AXES$n_max + 15L          # 지수 멤버 40 — 랭킹이 시그널일마다 15종을 떨어뜨릴 수 있다
N_TK  <- IDX_N + 10L               # 종목 50 — 비멤버 10 = all_listed 가 넓힐 대상
make_fixture <- function(idx_n, n_tk = N_TK) {
  set.seed(20260830L)
  d <- seq(as.Date("2003-06-02"), as.Date("2016-12-30"), by = "day")   # 오버레이 확장창(60개월) 확보
  d <- d[as.integer(format(d, "%w")) %in% 1:5]
  tk <- sprintf("T%03d", seq_len(n_tk))
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
FIX        <- make_fixture(IDX_N)        # 50종 중 40종만 지수 멤버 — 후보 40 > n_max 25
FIX_ALL    <- make_fixture(N_TK)         # 전 종목이 지수 멤버 = 넓힐 대상 없음
FIX_NARROW <- make_fixture(AXES$n_max)   # 후보 = n_max (경계 — 가드는 <= 라 발화해야 한다) · FIX 와 멤버 수만 다르다
# BM = 횡단면 평균 수익(시장 대용). 오버레이 신호의 입력이다.
BMF <- { .t <- copy(FIX); setorder(.t, Ticker, Date)
         .t[, r := Close / shift(Close, 1L) - 1, by = Ticker]      # ★티커 안에서 shift
         .t[is.finite(r), .(BM_Ret = mean(r)), by = Date][order(Date)] }
# 변동성이 상수인 BM — 오버레이가 개입할 근거가 없는 판(위반 주입용)
BMF_FLAT <- copy(BMF)[, BM_Ret := 0.0003]

PX <- list(kind = "price", id = "lowvol60")   # 오프라인 자기완결 팩터(DB 미접촉)

# 스펙을 파일로 굽고 엔진을 격리 env 에서 평가한다.
#   엔진은 DT <- RAWDATA 로 **참조**를 잡고 열을 추가하므로 매번 copy() 를 넘긴다.
run_cell <- function(spec, engine = ENGINE, fixture = FIX, bm = NULL) {
  p <- file.path(tempdir(), "rf_smoke_spec.json")
  writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  Sys.setenv(RF_CELL_SPEC = p)
  env <- new.env()
  assign("RAWDATA", copy(fixture), envir = env)
  assign("BM_DT", if (is.null(bm)) BMF else bm, envir = env)
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
r1 <- run_cell(base_spec(factor2 = list(kind = "none")))
if (is.null(r1$err) && identical(r1$out, "FACTORS")) {
  n <- nrow(get("FACTORS", envir = r1$env))
  if (n > 0L) ok(paste0("factor none(기저 단독) → FACTORS ", n, "행")) else ng("factor none", "0행")
} else ng("factor none", r1$err %||% "산출물 없음")

# A2. 1팩터 — B1 블록이 타는 경로(구 factor2 키 하위호환). r1·r2 는 A10 이 멤버십 비교에 다시 쓴다
r2 <- run_cell(base_spec(factor2 = PX))
if (is.null(r2$err) && identical(r2$out, "FACTORS")) ok("1팩터(factor2 하위호환) → FACTORS") else
  ng("1팩터", r2$err %||% "산출물 없음")

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

# A8/A9. 리스크 오버레이 (양방향) — 도훈 2026-08-30 "오버레이 계층". 노출 스케일이므로
#   Sigma w <= 1 이고 나머지가 현금이다. ★핵심은 "돌았다" 가 아니라 "개입했다" 이다 —
#   노출이 상시 1이면 오버레이를 쟀다고 말할 수 없다(처치 미전달).
r8 <- run_cell(base_spec(factor2 = PX, overlay = list(kind = "vol_scale")))
if (is.null(r8$err) && identical(r8$out, "PORTFOLIO")) {
  P8 <- get("PORTFOLIO", envir = r8$env)
  s8 <- P8[, .(s = sum(Weight)), by = Date]$s
  if (max(s8) > 1 + 1e-8) {
    ng("오버레이 Sigma w", "1 을 넘었다 — 현금이 아니라 레버리지다")
  } else if (stats::sd(s8) < 1e-12) {
    ng("오버레이 처치 미전달", "노출이 상시 동일")
  } else {
    ok(sprintf("오버레이 vol_scale → 노출 평균 %.3f · 최소 %.3f (Sigma w <= 1)", mean(s8), min(s8)))
  }
} else ng("오버레이 정상 경로", r8$err %||% "PORTFOLIO 없음")

#   ★"overlay" 까지 본다 — 앞선 가드가 같은 토큰으로 먼저 죽이면 오버레이 가드를 안 재고도 초록이 된다
#     (09-13~09-17 이 항목은 5a 가드에 선점당해 죽어 있었다).
r9 <- run_cell(base_spec(factor2 = PX, overlay = list(kind = "vol_scale")), bm = BMF_FLAT)
if (!is.null(r9$err) && grepl("overlay", r9$err, fixed = TRUE) && grepl("처치 미전달", r9$err, fixed = TRUE)) {
  ok("변동성이 상수인 시장에서는 개입 근거가 없어 실패로 끊는다(위반 주입)")
} else ng("오버레이 미전달 가드 미작동", r9$err %||% "상시 노출 1 을 측정으로 기록한다")

# A10~A12. 선정 축 유효성 가드 (양방향) — rf_cell_engine 5a. 기저 후보 중앙이 n_max 이하면 선정이 전수라
#   팩터 랭킹이 보유를 못 바꾼다(2026-09-12 실측: 결합 기저 14종/일 위 B1 9칸 중 6칸이 일별 수익 비트 동일).
#   통제 = FIX 와 FIX_NARROW 는 지수 멤버 수만 다르다(가격 경로·유동성 동일). 후보 수는 픽스처 의도가 아니라
#   엔진이 실제로 잰 값(.cand_med)을 읽는다.
# A10. 양성 — 후보 > n_max 면 팩터가 실제로 멤버십을 바꾼다(A1 기저 단독 vs A2 1팩터)
if (is.null(r1$err) && is.null(r2$err)) {
  cm2 <- get0(".cand_med", envir = r2$env, inherits = FALSE) %||% NA_real_
  mem <- function(env) get("FACTORS", envir = env)[, .(k = paste(sort(Ticker), collapse = ",")), by = Date]
  M <- merge(mem(r1$env), mem(r2$env), by = "Date")
  nd <- sum(M$k.x != M$k.y)
  if (is.finite(cm2) && cm2 > AXES$n_max && nd > 0L)
    ok(sprintf("후보 중앙 %.0f > n_max %d — 팩터가 보유를 바꾼다(시그널일 %d/%d)", cm2, AXES$n_max, nd, nrow(M)))
  else ng("선정 축 양성 대조", sprintf("후보 중앙 %s · 보유 차이 시그널일 %d/%d — 팩터 축 처치 미전달",
                                       format(cm2), nd, nrow(M)))
} else ng("선정 축 양성 대조", "A1/A2 실행 실패 — 위 항목 참조")

# A11. 위반 주입 — 후보 = n_max 인 픽스처에 팩터를 붙이면 반드시 멈춘다
r11 <- run_cell(base_spec(factor2 = PX), fixture = FIX_NARROW)
if (!is.null(r11$err) && grepl("랭킹이 멤버십을 못 바꾼다", r11$err, fixed = TRUE)) {
  ok(sprintf("후보 중앙 %s <= n_max %d 에 팩터를 붙이면 실패로 끊는다(위반 주입)",
             format(get0(".cand_med", envir = r11$env, inherits = FALSE) %||% NA), AXES$n_max))
} else ng("선정 축 가드 미작동", r11$err %||% "선정 전수인데 팩터 칸이 측정을 냈다 — 침묵 무처치")

# A12. 가드 범위 — 같은 좁은 후보라도 팩터가 없으면 멈추지 않는다. 비중·유니버스·오버레이 칸은 선정이 전수여도
#   처치가 전달된다(엔진 5a 의 ⚠) — 거기까지 막으면 과잉 차단이다. 대신 WARN 으로 선정 전수를 알려야 한다.
lg12 <- capture.output(r12 <- run_cell(base_spec(factor2 = list(kind = "none")), fixture = FIX_NARROW))
if (is.null(r12$err) && identical(r12$out, "FACTORS")) {
  n12 <- get("FACTORS", envir = r12$env)[, .N, by = Date]$N
  warned <- any(grepl("WARN", lg12, fixed = TRUE) & grepl("랭킹이 멤버십을 못 바꾼다", lg12, fixed = TRUE))
  if (warned && all(n12 == AXES$n_max))
    ok(sprintf("팩터 없는 좁은 칸은 통과 + WARN (선정 전수 %d종/일)", AXES$n_max))
  else ng("가드 범위", sprintf("WARN %s · 날짜별 보유 %s", warned, paste(range(n12), collapse = "~")))
} else ng("가드 과잉 차단", r12$err %||% "산출물 없음")

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
writeLines("=== C. 오버레이 행동 축 — 스칼라 vs 종목별 (v10.2) ===")

within_sd <- function(env) {
  w <- get("PORTFOLIO", envir = env, inherits = FALSE)
  z <- as.data.table(w)[, .(s = stats::sd(Weight)), by = Date]
  max(z$s[is.finite(z$s)], na.rm = TRUE)
}

# C1. 스칼라 arm(빌트인) — EW 기저에 걸면 날짜 안 비중은 여전히 균등해야 한다
rs <- run_cell(base_spec(factor2 = list(kind = "none"),
                         overlay = list(kind = "dd_brake", arm_id = "dd_brake_q")))
if (is.null(rs$err) && identical(rs$out, "PORTFOLIO")) {
  s <- within_sd(rs$env)
  if (s < 1e-12) ok("C1 스칼라 arm — 날짜 안 비중 균등 유지(대칭 축소)") else
    ng("C1 스칼라 arm 인데 횡단면 분산이 생겼다", sprintf("max sd %.3e", s))
} else ng("C1 스칼라 arm 실행 실패", rs$err %||% "산출물 없음")

# C2. 벡터 arm(파일 디스패치) — 같은 기저에서 날짜 안 비중이 갈려야 한다
rv <- run_cell(base_spec(factor2 = list(kind = "none"),
                         overlay = list(kind = "dbeta_tilt", arm_id = "dbeta_tilt_rank")))
if (is.null(rv$err) && identical(rv$out, "PORTFOLIO")) {
  s <- within_sd(rv$env)
  if (s > 1e-9) ok(sprintf("C2 벡터 arm — 횡단면 비대칭이 비중까지 전달 (max sd %.4f)", s)) else
    ng("C2 벡터 arm 인데 비중이 균등하다 — 비대칭 미전달")
} else ng("C2 벡터 arm 실행 실패", rv$err %||% "산출물 없음")

# C3. 고정 축 불변 — 벡터판도 Sigma w <= 1 을 지켜야 한다(현금은 잔여)
if (is.null(rv$err) && identical(rv$out, "PORTFOLIO")) {
  w <- as.data.table(get("PORTFOLIO", envir = rv$env, inherits = FALSE))
  smax <- max(w[, .(s = sum(Weight)), by = Date]$s)
  if (smax <= 1 + 1e-8 && all(w$Weight >= 0))
    ok(sprintf("C3 고정 축 유지 — Sigma w 최대 %.6f · 롱온리", smax)) else
    ng("C3 고정 축 위반", sprintf("Sigma w 최대 %.6f", smax))
}

# C4. 미지 kind — 파일도 없으면 경로를 알려주며 죽어야 한다(조용한 통과 금지)
ru <- run_cell(base_spec(factor2 = list(kind = "none"),
                         overlay = list(kind = "zz_no_such_arm", arm_id = "x")))
if (!is.null(ru$err) && grepl("zz_no_such_arm", ru$err, fixed = TRUE))
  ok("C4 미지 kind — 파일 부재를 지목하며 정지") else
  ng("C4 미지 kind 가 조용히 통과했다", ru$err %||% "오류 없음")

writeLines("")
writeLines("=== D. 오버레이 중첩 — 곱 합성 (v10.2) ===")

mean_expo <- function(env) {
  w <- as.data.table(get("PORTFOLIO", envir = env, inherits = FALSE))
  mean(w[, .(s = sum(Weight)), by = Date]$s)   # EW 기저라 날짜별 비중합 = 그 달 노출
}
OV_S <- list(kind = "dd_brake",   arm_id = "dd_brake_q")        # 스칼라 층
OV_X <- list(kind = "dbeta_tilt", arm_id = "dbeta_tilt_rank")   # 종목별 층

rA <- run_cell(base_spec(factor2 = list(kind = "none"), overlay = OV_S))
rB <- run_cell(base_spec(factor2 = list(kind = "none"), overlay = OV_X))
rS <- run_cell(base_spec(factor2 = list(kind = "none"), overlay = list(OV_S, OV_X)))

# D1. 리스트 형태를 받는가 (구판은 단수 객체만 받아 여기서 죽었다)
if (is.null(rS$err) && identical(rS$out, "PORTFOLIO"))
  ok("D1 오버레이 리스트 수용 — 두 층이 한 셀에서 돈다") else
  ng("D1 중첩 실행 실패", rS$err %||% "산출물 없음")

if (is.null(rA$err) && is.null(rB$err) && is.null(rS$err)) {
  eA <- mean_expo(rA$env); eB <- mean_expo(rB$env); eS <- mean_expo(rS$env)
  # D2. 곱 합성 — 두 층을 겹치면 각 층 단독보다 노출이 낮아야 한다
  if (eS < eA - 1e-9 && eS < eB - 1e-9)
    ok(sprintf("D2 곱 합성 — 단독 %.3f / %.3f → 중첩 %.3f", eA, eB, eS)) else
    ng(sprintf("D2 중첩이 노출을 안 줄인다 (단독 %.3f/%.3f · 중첩 %.3f)", eA, eB, eS))
  # D3. 종목축 성질 보존 — 스칼라를 겹쳐도 횡단면 비대칭이 살아 있어야 한다
  sS <- within_sd(rS$env)
  if (sS > 1e-9)
    ok(sprintf("D3 횡단면 비대칭 보존 (날짜 안 비중 sd %.4f)", sS)) else
    ng("D3 중첩 후 비중이 균등해졌다 — 종목축 층이 지워졌다")
  # D4. 고정 축 — 층을 겹쳐도 Sigma w <= 1
  w <- as.data.table(get("PORTFOLIO", envir = rS$env, inherits = FALSE))
  smax <- max(w[, .(s = sum(Weight)), by = Date]$s)
  if (smax <= 1 + 1e-8 && all(w$Weight >= 0))
    ok(sprintf("D4 고정 축 유지 — Sigma w 최대 %.6f", smax)) else
    ng("D4 고정 축 위반", sprintf("%.6f", smax))
}

# D5. 단수 객체 하위호환 — 구 스펙이 그대로 돌아야 한다
if (is.null(rA$err) && identical(rA$out, "PORTFOLIO"))
  ok("D5 단수 객체 하위호환 — 구 스펙 무변경") else ng("D5 단수 형태가 깨졌다", rA$err %||% "")

writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
cat(sprintf('{"test":"rf_cell_engine_smoke","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
