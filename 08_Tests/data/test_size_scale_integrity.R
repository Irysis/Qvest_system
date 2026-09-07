#==============================================================================
# test_size_scale_integrity.R — RAWDATA `Size` 스케일 정합 + writer 추적성
#
# 신설 계기 (2026-08-09): `naver_data_collector.R:88` 이 시가총액 단위를 억원 대신
#   백만원으로 오해해 `* 1e6` 을 적용, **정확히 100배 축소**된 Size 를 2026-07~08 에
#   43,013 행(시장 전체 ~2,690 티커) 기록했다. 같은 종목이 연속 거래일에 100배 진동했고
#   (삼성 1534.65조 <-> 14.00조, Close 는 3% 내), 시총 기반 팩터·cap-weight·유니버스
#   필터가 전부 틀린 값을 읽는 상태였다.
#
# ★검거 축 = **스케일 불변 정체 검사**, 크기 휴리스틱이 아니다.
#     shares = Size / Close (주식수) 는 writer 가 달라도, 날이 바뀌어도 같아야 한다.
#     `Size > 1e15` 류 크기 문턱은 종목마다 정상 범위가 달라 못 쓴다.
# ★두 번째 축 = **source 스탬프**. 구판 naver 수집기는 source 를 안 찍어 NA 였고,
#     역설적으로 그 NA 가 검거 지문이 됐다(source=NA => DEFLATED 42,342 /
#     krx_api => NORMAL 28,132 로 완전 정렬). 이제는 지문이 아니라 선언으로 강제한다.
#
# 양방향: ①양성 대조(정상 데이터에 오발화 없음) ②위반 주입(100배 축소 주입 -> 검출)
#         ③돌연변이(검사 로직 제거 -> 못 잡음을 실증)
#==============================================================================
suppressWarnings(suppressMessages({library(data.table)}))

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", m)) }
ng <- function(m, e, g) { FAIL <<- FAIL + 1L
  cat(sprintf("  FAIL  %s\n     기대=%s 실제=%s\n", m, e, g)) }
eq <- function(m, e, g) if (identical(e, g)) ok(m) else ng(m, e, g)

#--- 계약 함수: 스케일 이상 검출 -------------------------------------------
#    반환 = 이상 행 index.
#
# ★두 축을 함께 본다 — **크기만으로는 정상 기업행위와 구별되지 않는다**(2026-08-09 실측):
#   ① 중앙값 대비 배율(tol) — 이상의 크기
#   ② **진동(min_jumps)** — 이상의 시간 패턴. 이것이 결함과 기업행위를 가르는 축이다.
#
#   실측 근거: 주식수 3배↑ 변동을 종목별로 분류하니
#     · **일회성**(1회) 205 종목 — 점프 시점이 1997~2026 **분산** = 증자·합병 등 실제 기업행위
#       (⚠액면분할은 아니다 — Close 동반 3배 이동이 **5.9%** 뿐이라 분할 가설은 기각됐다)
#     · **진동**(10회↑) 546 종목 — 점프의 **87%가 2026-07/08 에 집중** = naver 단위 결함
#   ⇒ 크기만 보는 구판은 205 종목의 정상 기업행위를 오발화한다. 진동 조건이 그것을 배제한다.
#
# @param tol       중앙값 대비 몇 배를 이상으로 볼지
# @param min_jumps 같은 종목에서 큰 변동이 몇 회 이상 반복돼야 결함으로 볼지.
#                  1 로 두면 구판 동작(기업행위 오발화 포함) — 픽스처 검증용.
detect_size_scale_break <- function(dt, tol = 5, min_jumps = 1L) {
  stopifnot(all(c("Ticker","Size","Close") %in% names(dt)))
  d <- copy(as.data.table(dt))
  d[, .row := .I]
  d <- d[is.finite(Size) & Size > 0 & is.finite(Close) & Close > 0]
  d[, .shares := Size / Close]
  d[, .sh_med := median(.shares), by = Ticker]
  d[, .odd := .shares > .sh_med * tol | .shares < .sh_med / tol]
  if (min_jumps > 1L) d[, .odd := .odd & sum(.odd) >= min_jumps, by = Ticker]
  d[.odd == TRUE, .row]
}

#--- 픽스처 -----------------------------------------------------------------
mk <- function(n_tick = 5, n_day = 40, shares = 1e8) {
  CJ(Ticker = paste0("A", sprintf("%06d", seq_len(n_tick))), d = seq_len(n_day))[
    , .(Ticker, Close = 1000 + d * 3,
        Size = (1000 + d * 3) * shares)][]
}

cat("── ① 양성 대조: 정상 데이터에 오발화 없는가 ───────────────────────────\n")
clean <- mk()
eq("정상 데이터 -> 이상 0건", 0L, length(detect_size_scale_break(clean)))

# 주가가 크게 움직여도(주식수 불변) 발화하면 안 된다 — 크기 휴리스틱과의 차이
vol <- copy(clean); vol[seq(1, .N, by = 7), `:=`(Close = Close * 4, Size = Size * 4)]
eq("주가 4배 급등(주식수 불변) -> 이상 0건 (크기가 아니라 불변량을 본다)",
   0L, length(detect_size_scale_break(vol)))

cat("── ② 위반 주입: 실사고 재현 ───────────────────────────────────────────\n")
inj <- copy(clean)
hit <- c(3L, 4L, 11L)
inj[hit, Size := Size / 100]                       # naver 결함 = 정확히 100배 축소
got <- detect_size_scale_break(inj)
eq("100배 축소 3행 주입 -> 정확히 그 3행 검출", hit, sort(got))

inj2 <- copy(clean); inj2[7L, Size := Size * 100]  # 반대 방향도 잡아야 한다
eq("100배 확대 1행 주입 -> 검출", 7L, detect_size_scale_break(inj2))

# 실사고 규모(과반 오염)에서도 잡히는가 — 중앙값이 오염 쪽으로 끌리는 경계
inj3 <- copy(clean); half <- seq(1, nrow(inj3), by = 2)
inj3[half, Size := Size / 100]
n3 <- length(detect_size_scale_break(inj3))
if (n3 > 0) ok(sprintf("50%% 오염에서도 검출 (%d행) — 중앙값이 아직 정상 쪽", n3)) else
  ng("50% 오염에서도 검출", ">0", "0")

cat("── ②b 진동 축: 일회성 기업행위를 결함으로 오발화하지 않는가 ───────────\n")
#   ★2026-08-09 실측: 일회성 점프 205 종목은 1997~2026 분산 = 증자·합병 등 실제 기업행위.
#     진동 546 종목은 점프의 87%가 2026-07/08 집중 = 단위 결함. 크기만으로는 안 갈린다.
corp <- copy(clean)                       # 한 종목이 중간에 주식수 10배 증가 후 **유지**
tk <- corp[1, Ticker]
idx <- corp[, .I[Ticker == tk]]
half <- idx[(length(idx) %/% 2 + 1):length(idx)]
corp[half, Size := Size * 10]
n_naive <- length(detect_size_scale_break(corp, min_jumps = 1L))
n_osc   <- length(detect_size_scale_break(corp, min_jumps = 30L))
if (n_naive > 0) ok(sprintf("구판(크기만) 은 일회성 기업행위를 발화 (%d행) — 오발화 재현", n_naive)) else
  ng("구판이 일회성을 발화해야 함(오발화 재현)", ">0", "0")
eq("진동 조건(min_jumps=30) 은 일회성을 배제", 0L, n_osc)

## 반대: 진짜 진동(결함)은 진동 조건에서도 잡혀야 한다 — 검사 사망 방지
osc_fx <- copy(clean)
alt <- seq(1, nrow(osc_fx), by = 2)
osc_fx[alt, Size := Size / 100]
if (length(detect_size_scale_break(osc_fx, min_jumps = 10L)) > 0)
  ok("진동 조건에서도 실제 결함(격일 100배 축소)은 검출 — 과잉 배제 아님") else
  ng("진동 조건에서 실제 결함 검출", ">0", "0")

cat("── ③ source 스탬프 계약 ───────────────────────────────────────────────\n")
NAVF <- "02_Infrastructure/data/naver_data_collector.R"
f <- readLines(NAVF, warn = FALSE)
# ★2026-09-07 저녁 표적 이설(두 번째): 구판은 소스에 `source := "naver"` 라는 **문자열이
#   있는가**를 봤다. 갱신이 원천 우선순위를 경유하게 되며 스탬프가 `set(raw, j="source",
#   value = incoming_source)` 로 바뀌자 의도는 그대로인데 검사만 빨개졌다 —
#   바로 아래 주석이 경고하던 그 병(소스 텍스트 단정)을 이 줄이 다시 밟고 있었다.
#   ⇒ 이름이 아니라 **행동**을 잰다: 새 행이 붙을 때 라벨이 찍히는가. (아래 블록에서 함께)

# ★2026-09-07 표적 이설: 구판은 `rawdata_cols` 열 목록에 '"Ret", "source"' 라는
#   **문자열이 있는가**를 봤다. 수집 경로가 수정주가로 교체되며 그 select 목록 자체가
#   사라졌고(이제 값만 갱신하고 나머지 열은 승계한다) 의도는 오히려 더 잘 지켜지는데
#   검사만 빨개졌다 — 소스 텍스트 단정이 리팩터가 옮기는 좌표를 못박은 것이다.
#   ⇒ 이름 대신 **행동**을 잰다: 갱신을 실제로 돌려 source 열이 살아남고 스탬프되는가.
.pick <- function(path, nm) {
  ex <- parse(path)
  for (i in seq_along(ex)) {
    e <- ex[[i]]
    if (is.call(e) && length(e) >= 3 && as.character(e[[1]])[1] %in% c("<-", "=") &&
        identical(as.character(e[[2]]), nm)) return(e)
  }
  NULL
}
.fd <- .pick(NAVF, ".naver_apply_update")
if (is.null(.fd)) {
  ng("rawdata 갱신이 source 를 보존/스탬프한다", ".naver_apply_update", "AST 에 없음")
} else {
  .e <- new.env(parent = globalenv()); eval(.fd, envir = .e)
  # ★incumbent 를 이 writer 자신의 레인(naver)으로 둔다 — 갱신은 이제 원천 우선순위를
  #   경유하고, 상위 원천(quantiwise*)은 **덮이지 않는 것이 정상**이라 그 위에서는
  #   스탬프 축이 아예 실행되지 않는다(재고 싶은 명제가 안 도는 픽스처는 미측정이다).
  #   T3 는 신규 행 — 라벨이 없던 자리에 찍히는가를 함께 잰다.
  .syn <- data.table(Date = as.Date("2026-08-31"), Ticker = c("T1", "T2"),
                     Close = c(10, 20), Vol = c(1, 2), Open = 1, High = 1, Low = 1,
                     Size = 1e9, Ret = 0, K200 = c(1, 0), source = "naver")
  .vc <- eval(.pick(NAVF, "NAVER_VALUE_COLS")[[3]])     # 값 축도 재도출(목록 재기입 금지)
  .upd <- rbind(.syn[, .(Date, Ticker, Close = c(11, 21), Vol, Open, High, Low, Size, Ret)],
                data.table(Date = as.Date("2026-08-31"), Ticker = "T3", Close = 33, Vol = 3,
                           Open = 3, High = 3, Low = 3, Size = 1e9, Ret = 0))
  .err <- ""
  .ap <- tryCatch(get(".naver_apply_update", envir = .e)(.syn, .upd, value_cols = .vc),
                  error = function(z) { .err <<- conditionMessage(z); NULL })
  .out <- if (is.null(.ap)) NULL else .ap$dt
  if (!is.null(.out) && "source" %in% names(.out) && all(.out$source == "naver") &&
      "K200" %in% names(.out) && identical(.out[Ticker == "T1"]$K200, 1) &&
      identical(.out[Ticker == "T1"]$Close, 11) && identical(.out[Ticker == "T3"]$Close, 33))
    ok("rawdata 갱신이 source 를 보존/스탬프한다(+승계열 K200 생존 · 신규행 라벨)") else
    ng("rawdata 갱신이 source 를 보존/스탬프한다", 'source=="naver" & K200 보존 & 신규행 스탬프',
       if (is.null(.out)) paste("실행 실패:", .err) else paste(names(.out), collapse = ","))
  # 위반 주입 — 상위 원천은 덮이면 안 된다(스탬프 축이 무차별이 아님을 실증)
  .syn2 <- copy(.syn)[Ticker == "T2", source := "quantiwise_update"]
  .ap2 <- tryCatch(get(".naver_apply_update", envir = .e)(
                     .syn2, .upd, value_cols = .vc), error = function(z) NULL)
  if (!is.null(.ap2) && identical(.ap2$n_skipped, 1L) &&
      identical(.ap2$dt[Ticker == "T2"]$source, "quantiwise_update") &&
      identical(.ap2$dt[Ticker == "T2"]$Close, 20))
    ok("스탬프가 무차별이 아니다 — 상위 원천은 값도 라벨도 안 바뀐다") else
    ng("스탬프가 무차별이다", "T2(quantiwise_update) 보존",
       if (is.null(.ap2)) "실행 실패" else sprintf("skip=%s src=%s close=%s", .ap2$n_skipped,
         paste(.ap2$dt[Ticker == "T2"]$source), paste(.ap2$dt[Ticker == "T2"]$Close)))
}
if (any(grepl("* 1e8", f, fixed = TRUE)))
  ok("Size 단위가 1e8 (억원 -> 원)") else
  ng("Size 단위가 1e8", "* 1e8", "부재")
if (any(grepl("* 1e6,", f, fixed = TRUE)))
  ng("구 배율 1e6 이 남아 있지 않다", "부재", "잔존") else
  ok("구 배율 1e6 이 남아 있지 않다")

cat("── ④ 위반 주입(검사 자신): 판정 로직을 죽이면 못 잡는가 ───────────────\n")
mutant <- function(dt, tol = 5) integer(0)          # 항상 '이상 없음'
if (length(mutant(inj)) == 0L)
  ok("돌연변이(항상 통과) -> 주입 위반을 놓침 = 이 검사의 검출력 실증") else
  ng("돌연변이가 놓쳐야 함", "0", as.character(length(mutant(inj))))

cat("\n")
cat(sprintf("════ test_size_scale_integrity: PASS=%d FAIL=%d ════\n", PASS, FAIL))
cat(sprintf('{"test":"size_scale_integrity","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0) 1 else 0)
