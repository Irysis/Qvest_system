#==============================================================================
# test_rf_arm_coverage_basis.R — 비중 arm 커버리지 **분모** 검사 (2026-09-13)
#
# 실사고 (2002.06975 promo3 B4_21/22/25 · 원장 lessons):
#   "[rf_cell_engine] arm lean:hrp 커버리지 76.6% (<80%) — 침묵 부분측정 금지"
#   KQ150 멤버십 첫 날이 2010-01-29 라 시그널일 261 중 201 만 멤버가 있다 → **지지 상한 77.0%**.
#   구 분모(전 시그널일)는 유니버스가 아직 없는 달을 arm 결손으로 셌고, index:KQ150 위 비중 arm 7종이
#   전부 76.6~77.0% 로 막혔다(같은 arm 은 다른 유니버스에서 전부 통과). 그 기록이 장부를 타고 B4 결합 칸과
#   다른 논문의 B2 칸까지 닫았다.
#
# 이 검사가 재는 것 (양방향 · 합성 픽스처만 · 운영 원장·카탈로그·데이터 무접촉):
#   A 전제      — 픽스처 유니버스의 지지가 80% 미만인지 산출에서 재도출
#   B 오탐 제거 — 지지가 늦은 유니버스 + 정상 arm → 측정된다 · 지지율이 로그에 남는다
#   C 돌연변이  — 분모를 구판(.sig_dates)으로 되돌린 사본은 B 를 반드시 떨어뜨린다(= 이 검사가 방어선이다)
#   D 진짜 결손 — 선정이 있는 달의 25% 를 못 내는 arm 은 지지 완전·지지 늦음 **둘 다에서** 여전히 멈춘다
#   E 무변경    — 지지가 완전한 유니버스에선 신판과 구판 분모의 PORTFOLIO 가 비트 동일
#   F 채널      — 엔진이 실제로 낸 오류 문자열을 장부 파서가 [basis=…] · arm 으로 읽는다(오버레이 가드 포함)
#
# 스텁: 임시 QM_ROOT 에 backtest_harness.R(로드 확인용) · portfolio/weight_catalog.R(스텁 arm 2종) ·
#   validation/overlay_pit_guard.R(정본 사본) · reinforcement/overlay_arms/stub_partial.R 만 둔다.
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_arm_coverage_basis.R
#   (--no-environ: ~/.Renviron 의 QM_ROOT 가 셸 값을 덮어 worktree 검사가 main 코드를 재는 것을 막는다)
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT   <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ENGINE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R")
# ★어느 코드를 재는지 먼저 찍는다 — ~/.Renviron 의 QM_ROOT 는 셸 인라인 값을 덮는다(worktree 검사가 main 을 잰다).
#   worktree 를 재려면: QM_ROOT=<worktree> Rscript --no-environ <이 파일>
writeLines(paste("ROOT =", ROOT))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }

# ── 합성 픽스처 — 종목 30 · 평일 2003-06~2012-12 ────────────────────────────
#   K200 = T001~T020 (전 기간) · KQ150 = T021~T030 **2008-01-01 부터**(그 전엔 멤버 0).
#   시그널일 2005-01~2012-12 = 96, KQ150 멤버가 있는 달 60 → 지지 62.5%.
make_fixture <- function(kq_from = as.Date("2008-01-01")) {
  set.seed(20260913L)
  d <- seq(as.Date("2003-06-02"), as.Date("2012-12-31"), by = "day")
  d <- d[as.integer(format(d, "%w")) %in% 1:5]
  x <- CJ(Ticker = sprintf("T%03d", 1:30), Date = d)
  setorder(x, Ticker, Date)
  x[, .r := rnorm(.N, 0.0002, 0.012)]
  x[, Close := 10000 * cumprod(1 + .r), by = Ticker]
  x[, .r := NULL]
  x[, Vol := 2e6]                                    # 유동성 하한(2e8)을 늘 넘긴다 — 대상은 배관이다
  x[, Size := Close * 1e6]
  x[, .id := as.integer(sub("T", "", Ticker, fixed = TRUE))]
  x[, K200 := .id <= 20L]
  x[, KQ150 := .id > 20L & Date >= kq_from]
  x[, Sector_Lv2 := paste0("S", (.id %% 5L) + 1L)]
  x[, .id := NULL]
  x[]
}
FIX <- make_fixture()
BMF <- { .t <- copy(FIX); setorder(.t, Ticker, Date)
         .t[, r := Close / shift(Close, 1L) - 1, by = Ticker]
         .t[is.finite(r), .(BM_Ret = mean(r)), by = Date][order(Date)] }

# ── 스텁 루트 ─────────────────────────────────────────────────────────────────
STUB <- file.path(tempdir(), sprintf("rf_covbasis_%d", Sys.getpid()))
for (dd in c("02_Infrastructure/portfolio", "02_Infrastructure/validation", "02_Infrastructure/reinforcement/overlay_arms"))
  dir.create(file.path(STUB, dd), recursive = TRUE, showWarnings = FALSE)
writeLines("calc_ivol_weights <- function(...) NULL   # 로드 확인용 — 엔진은 존재만 본다",
           file.path(STUB, "02_Infrastructure/backtest_harness.R"))
writeLines(c(
  "weight_catalog_arms <- function(quiet = TRUE) {",
  "  .iv <- function(ctx) { s <- apply(ctx$R, 2, stats::sd); w <- 1 / pmax(s, 1e-8); w / sum(w) }",
  "  # 선정이 있는 달 중 1~3월(25%)에 솔버가 실패하는 arm — 진짜 결손의 합성판",
  "  .flaky <- function(ctx) { if (as.integer(format(ctx$decision_date, '%m')) %in% 1:3) stop('stub solver failure'); .iv(ctx) }",
  "  data.table::data.table(catalog_id = c('stub:ivol', 'stub:flaky'), adapter_fn = list(.iv, .flaky))",
  "}"), file.path(STUB, "02_Infrastructure/portfolio/weight_catalog.R"))
invisible(file.copy(file.path(ROOT, "02_Infrastructure/validation/overlay_pit_guard.R"),
                    file.path(STUB, "02_Infrastructure/validation/overlay_pit_guard.R"), overwrite = TRUE))
writeLines(c(
  "# 보유 종목의 절반만 지목하는 벡터 arm — 오버레이 종목 커버리지 가드(held_rows)를 발화시킨다",
  "overlay_expo_stub_partial <- function(H, t, ctx) {",
  "  h <- ctx$hold; if (is.null(h) || !nrow(h)) return(1)",
  "  tk <- sort(unique(as.character(h$Ticker)))",
  "  data.table::data.table(Ticker = tk[seq_len(max(1L, floor(length(tk) / 2)))], e = 0.5)",
  "}"), file.path(STUB, "02_Infrastructure/reinforcement/overlay_arms/stub_partial.R"))

AXES <- list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150",
             start_date = "2005-01-01", commission_bps = 15L, liq_adv20_min = 2e8)
base_spec <- function(...) modifyList(list(
  code = "COVB", label = "coverage basis", block = "T", fixed_axes = AXES,
  base_signal = list(kind = "mom_12_1"), weighting = list(kind = "ew"),
  universe = list(kind = "k200_kq150")), list(...))
UQ  <- list(kind = "index", flag = "KQ150")
WIV <- list(kind = "catalog", catalog_id = "stub:ivol")
WFL <- list(kind = "catalog", catalog_id = "stub:flaky")

# 엔진을 격리 env 에서 평가한다 — QM_ROOT 는 실행 동안만 스텁으로 돌린다.
run_cell <- function(spec, engine = ENGINE, fixture = FIX, bm = NULL) {
  p <- file.path(tempdir(), "rf_covbasis_spec.json")
  writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  old_root <- Sys.getenv("QM_ROOT", unset = NA); old_spec <- Sys.getenv("RF_CELL_SPEC", unset = NA)
  Sys.setenv(RF_CELL_SPEC = p, QM_ROOT = STUB)
  on.exit({ if (is.na(old_root)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = old_root)
            if (is.na(old_spec)) Sys.unsetenv("RF_CELL_SPEC") else Sys.setenv(RF_CELL_SPEC = old_spec) }, add = TRUE)
  env <- new.env()
  assign("RAWDATA", copy(fixture), envir = env)
  if (!is.null(bm)) assign("BM_DT", bm, envir = env)
  err <- NULL
  lg <- utils::capture.output(suppressWarnings(suppressMessages(
    tryCatch(source(engine, local = env), error = function(e) err <<- conditionMessage(e)))))
  list(err = err, log = lg,
       port = if (exists("PORTFOLIO", envir = env, inherits = FALSE))
                as.data.table(get("PORTFOLIO", envir = env))[order(Date, Ticker)] else NULL)
}

# 구 분모 돌연변이 — 분모 한 줄만 되돌린다
src <- readLines(ENGINE, warn = FALSE, encoding = "UTF-8")
hit <- grep(".n_try <- length(.sel_dates)", src, fixed = TRUE)
MUT <- file.path(tempdir(), "rf_cell_engine_oldbasis.R")
if (length(hit) == 1L) {
  m <- src; m[hit] <- sub(".n_try <- length(.sel_dates)", ".n_try <- length(.sig_dates)", m[hit], fixed = TRUE)
  writeLines(m, MUT, useBytes = TRUE)
}

writeLines("=== A. 전제 — 픽스처의 지지구간을 산출에서 재도출 ===")
sig <- FIX[Date >= as.Date("2005-01-01"), .(d = max(Date)), by = .(ym = format(Date, "%Y%m"))]$d
sup <- mean(sig %in% unique(FIX[KQ150 == TRUE]$Date))
if (sup > 0.5 && sup < 0.8) ok(sprintf("A KQ150 지지 %.1f%% (%d/%d) — 구 분모면 어떤 비중 arm 도 80%% 를 못 넘는다",
                                       100 * sup, sum(sig %in% unique(FIX[KQ150 == TRUE]$Date)), length(sig))) else
  ng("A 픽스처 전제", sprintf("지지 %.3f — 검사가 아무것도 가르지 못한다", sup))

writeLines("=== B. 오탐 제거 — 지지가 늦은 유니버스 + 정상 arm 은 측정된다 ===")
rB <- run_cell(base_spec(universe = UQ, weighting = WIV))
if (is.null(rB$err) && !is.null(rB$port) && nrow(rB$port)) {
  nd <- length(unique(rB$port$Date))
  disp <- rB$port[, .(s = stats::sd(Weight)), by = Date]
  ok(sprintf("B1 index:KQ150 × stub:ivol → PORTFOLIO %d개월(선정일 전부)", nd))
  if (max(disp$s, na.rm = TRUE) > 1e-10) ok("B2 처치 전달 — 날짜 안 비중이 EW 가 아니다") else ng("B2 처치 미전달", "전 시점 EW")
  if (any(grepl("유니버스 지지 62.5%", rB$log, fixed = TRUE)) && any(grepl("선정일 60/60", rB$log, fixed = TRUE)))
    ok("B3 조용한 통과 아님 — 로그에 선정일 60/60 · 유니버스 지지 62.5% 가 남는다") else
    ng("B3 지지율 로그 부재", paste(grep("catalog", rB$log, value = TRUE), collapse = " | "))
} else ng("B1 지지 늦은 유니버스가 여전히 막힌다", rB$err %||% "PORTFOLIO 없음")

writeLines("=== C. 돌연변이 — 구 분모 사본은 B 를 떨어뜨려야 한다 ===")
if (length(hit) != 1L) {
  ng("C 위반 주입 지점", sprintf("분모 줄 %d개 — 엔진이 바뀌었으면 이 검사도 옮겨야 한다", length(hit)))
} else {
  if (!inherits(tryCatch(parse(MUT, encoding = "UTF-8"), error = function(e) e), "error")) ok("C1 돌연변이 사본 parse 통과(같은 계열의 결함)") else
    ng("C1 돌연변이가 문법을 깼다")
  rC <- run_cell(base_spec(universe = UQ, weighting = WIV), engine = MUT)
  if (!is.null(rC$err) && grepl("커버리지 62.5%", rC$err, fixed = TRUE))
    ok("C2 구 분모 사본은 같은 칸을 '커버리지 62.5%' 로 끊는다 = B 가 이 결함을 잡는다") else
    ng("C2 돌연변이가 통과했다 — B 는 방어선이 아니다", rC$err %||% "오류 없음")
}

writeLines("=== D. 진짜 결손은 여전히 멈춘다 (지지 완전 · 지지 늦음) ===")
rD1 <- run_cell(base_spec(weighting = WFL))
if (!is.null(rD1$err) && grepl("커버리지 75.0%", rD1$err, fixed = TRUE) && grepl("[basis=sel_dates 72/96]", rD1$err, fixed = TRUE))
  ok("D1 k200_kq150 × stub:flaky → '커버리지 75.0% [basis=sel_dates 72/96]' 로 정지") else
  ng("D1 지지 완전 유니버스의 진짜 결손을 놓쳤다", rD1$err %||% "오류 없음")
rD2 <- run_cell(base_spec(universe = UQ, weighting = WFL))
if (!is.null(rD2$err) && grepl("[basis=sel_dates 45/60]", rD2$err, fixed = TRUE))
  ok("D2 index:KQ150 × stub:flaky → 선정일 45/60 로 정지 — 새 분모가 늦은 유니버스의 결손을 삼키지 않는다") else
  ng("D2 지지 늦은 유니버스의 진짜 결손을 놓쳤다", rD2$err %||% "오류 없음")

writeLines("=== E. 무변경 — 지지 완전 유니버스에서 신·구 분모의 산출이 비트 동일 ===")
if (length(hit) == 1L) {
  rE  <- run_cell(base_spec(weighting = WIV))
  rEm <- run_cell(base_spec(weighting = WIV), engine = MUT)
  if (is.null(rE$err) && is.null(rEm$err) && !is.null(rE$port) && !is.null(rEm$port) &&
      identical(rE$port$Date, rEm$port$Date) && identical(rE$port$Ticker, rEm$port$Ticker) &&
      identical(rE$port$Weight, rEm$port$Weight))
    ok(sprintf("E k200_kq150 × stub:ivol — PORTFOLIO %d행 신·구 비트 동일", nrow(rE$port))) else
    ng("E 정상 arm 산출이 바뀌었다", sprintf("err=%s / %s", rE$err %||% "-", rEm$err %||% "-"))
}

writeLines("=== F. 채널 — 엔진이 낸 실제 문자열을 장부가 읽는다 ===")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))
for (nm in c("rD1", "rD2")) {
  e <- get(nm)$err
  pc <- if (is.null(e)) NULL else rac_parse_coverage(e)
  if (!is.null(pc) && identical(pc$basis, "sel_dates") && identical(pc$kind, "weight") && identical(pc$id, "stub:flaky"))
    ok(sprintf("F %s 비중 가드 문자열 → basis=sel_dates · weight:stub:flaky", nm)) else
    ng(sprintf("F %s 파싱", nm), if (is.null(pc)) "오류 없음" else sprintf("%s/%s/%s", pc$basis, pc$kind, pc$id))
}
OVS <- base_spec(overlay = list(kind = "stub_partial", arm_id = "stub_partial_x"))
rF <- run_cell(OVS, bm = BMF)
pcF <- if (is.null(rF$err)) NULL else rac_parse_coverage(rF$err)
if (!is.null(pcF) && grepl("종목 커버리지", rF$err, fixed = TRUE) && identical(pcF$basis, "held_rows") &&
    identical(pcF$kind, "overlay") && identical(pcF$id, "stub_partial"))
  ok("F 오버레이 가드 문자열 → basis=held_rows · overlay kind stub_partial") else
  ng("F 오버레이 가드 채널", rF$err %||% "오류 없음(가드 미발화)")
if (!is.null(pcF) && identical(.rac_attribute(OVS, pcF), "overlay:stub_partial_x"))
  ok("F 오버레이 실패는 그 층의 arm_id 로 귀속된다") else ng("F 오버레이 귀속", "arm_id 매핑 실패")

unlink(STUB, recursive = TRUE, force = TRUE)
writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
cat(sprintf('{"test":"rf_arm_coverage_basis","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
