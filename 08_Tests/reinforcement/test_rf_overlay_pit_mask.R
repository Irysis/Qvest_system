#==============================================================================
# test_rf_overlay_pit_mask.R — P0-09 오버레이 PIT 가드 실체화 양방향 검사 (2026-09-24)
#
# 왜 (감사 D4-07 · 비평 M8 · 플랜 qvest-1-drifting-eclipse P0-09):
#   ① rf_cell_engine.R 은 H <- .M[seq_len(t)] 의 t 행을 arm 에 그대로 넘겼다. 그 행의 fwd = 익월 BM 수익(미실현)이다.
#      파일 arm 의 '읽지 않는다' 는 약속뿐이었다.
#   ② assert_overlay_pit(.M$Date, .hs) 는 두 입력이 모두 .M$Date 파생 — 무엇을 넘겨도 통과하는 동어반복이었다.
#   ③ overlay_probe.R ④ 는 한 시점(0.8N)·한 방향(+0.5) 섭동이라 fwd[t] 가 극단일 때만 읽는 arm 이 통과했다.
#
# 재는 것 (양방향 — 구판 빨강 · 신판 초록 · 돌연변이 빨강):
#   A1 arm 이 받은 t 행 fwd = NA · 과거 행 fwd 는 온전 (구판: t 행 실값 노출)
#   A2 fwd[t] 를 읽는 arm(대체값 있음) — 마지막 달 BM 섭동에 t=N−1 노출 불변 (구판: 흔들림 = 누출)
#   A3 fwd[t] 를 NA 검사 없이 읽는 arm — 신판은 선다(NA 또는 stop)
#   A4 정직 arm(스텁·정본 벡터·과거 fwd 를 학습하는 정본 arm·빌트인 ml_tail_gate 등) — 신·구 산출 비트 동일
#   A5 assert 입력 실체 — 넘긴 값의 가용일 < 홀딩 시작 · .M(학습 행) fwd 불변 · 홀딩 시작 = 달력(집행일은 그 이후)
#   A5g 집행일 축(get_execution_date) 호출 실패 → 달력 폴백 · 산출 비트 동일 · 돌연변이(폴백 제거) 빨강
#   A6 돌연변이: 마스크 제거 → assert 가 LOOK-AHEAD 로 선다 (cutoff > holding_start 주입) · shift=1 판은 서지 않는다
#   A7 돌연변이: 마스크를 .M 에 걸면 불변식이 선다
#   A8 돌연변이: 마스크 제거 + 구 assert 입력 = 구판 등가 → 아무것도 안 선다(동어반복 실증)
#   A9 assert 엄격 부등호(한계 = 홀딩 시작 전날)
#   B1 구판 probe 는 위반 arm V1(하 꼬리일 때만 fwd[t])·V2(위기 국면에서만 fwd[t])를 통과시킨다(결함 실증)
#   B2 신판 probe 는 V1·V2·직접 읽기·NA 오류 arm 을 ④ future 에서 거부한다
#   B3 정직 arm 은 신·구 probe 판정·처치 통계가 같다
#   B4 섭동 시점 결정론 · 설정 12점 · 위기 구간 포함
#   B5 설정 부재(root·QM_ROOT 둘 다)·schema 불일치·na 없는 perturb = ④ FAIL (fail-closed) · root 무설정 → 정본 폴백 표기
#   B6 돌연변이: 설정을 구판 수준(한 점·한 방향)으로 줄이면 V1 이 다시 통과한다(확장이 하중을 진다)
#   B7 (2026-09-25 보강) 호출자 스코프 통로 — dynGet('.M')·parent.frame() 의 BM_DT 로 마스크를 돌아가는 arm 은 엔진에서 새고(결함 실증)
#      ③c 없는 probe 를 통과한다(돌연변이) · 신판 probe 는 ③c scope 에서 거부 · 스캔 경계(오탐 0) · 정본 arm 전수 0건
#
# 기준본 = 커밋 해시 고정(블롭 sha 대조) — 엔진 d63d5d1f0(8a52cf76…) · probe 466b2a4ea(6aad0603…).
#   덮어쓰기: QVEST_P009_ENGINE_BASE_REF · QVEST_P009_PROBE_BASE_REF (블롭 sha 는 고정 — 엉뚱한 판본 차단)
# 부작용: 전부 tempdir(스텁 루트). 실제 overlay_arms/·원장·설정 무접촉.
# 실행: QM_ROOT=<루트> R_ENVIRON_USER=<빈 파일> Rscript --no-environ 08_Tests/reinforcement/test_rf_overlay_pit_mask.R
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT   <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ENGINE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R")
PROBE  <- file.path(ROOT, "02_Infrastructure/reinforcement/overlay_probe.R")
CFG    <- file.path(ROOT, "06_Registry/overlay_probe_future.json")
writeLines(paste("ROOT =", ROOT))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }

# ── 기준본(구판) — git 블롭 ────────────────────────────────────────────────────
.git_blob <- function(ref, rel, sha, out) {
  s <- tryCatch(system2("git", c("-C", shQuote(ROOT), "rev-parse", paste0(ref, ":", rel)), stdout = TRUE, stderr = FALSE),
                error = function(e) character(0))
  st <- tryCatch(system2("git", c("-C", shQuote(ROOT), "show", paste0(ref, ":", rel)), stdout = out, stderr = FALSE),
                 error = function(e) 1L)
  identical(st, 0L) && identical(as.character(s)[1], sha) && file.exists(out) && file.info(out)$size > 1000
}
TD <- file.path(tempdir(), sprintf("p009_%d", Sys.getpid())); dir.create(TD, recursive = TRUE, showWarnings = FALSE)
OLD_ENGINE <- file.path(TD, "rf_cell_engine_old.R"); OLD_PROBE <- file.path(TD, "overlay_probe_old.R")
ENG_REF <- Sys.getenv("QVEST_P009_ENGINE_BASE_REF", "d63d5d1f0")
PRB_REF <- Sys.getenv("QVEST_P009_PROBE_BASE_REF",  "466b2a4ea")
HAVE_OLD_E <- .git_blob(ENG_REF, "02_Infrastructure/reinforcement/rf_cell_engine.R", "8a52cf766f0d5e6b303adc6b834a8243ec585936", OLD_ENGINE)
HAVE_OLD_P <- .git_blob(PRB_REF, "02_Infrastructure/reinforcement/overlay_probe.R",  "6aad06038a8f5b830d7d42c8c6fed68142d6bc35", OLD_PROBE)
if (HAVE_OLD_E) ok(sprintf("기준본 엔진 확보 — %s 블롭 8a52cf76", ENG_REF)) else ng("기준본 엔진", "git show 실패 또는 블롭 불일치 — 구판 대조 항목은 실패로 센다")
if (HAVE_OLD_P) ok(sprintf("기준본 probe 확보 — %s 블롭 6aad0603", PRB_REF)) else ng("기준본 probe", "git show 실패 또는 블롭 불일치 — 구판 대조 항목은 실패로 센다")

# ── 합성 픽스처 (test_rf_engine_overlay_stack.R 과 같은 생성기) — 종목 30 · 지수 멤버 20 · 시그널일 96 ──
make_fixture <- function(idx_n = 20L) {
  set.seed(20260917L)
  d <- seq(as.Date("2003-06-02"), as.Date("2012-12-31"), by = "day")
  d <- d[as.integer(format(d, "%w")) %in% 1:5]
  x <- CJ(Ticker = sprintf("T%03d", 1:30), Date = d)
  setorder(x, Ticker, Date)
  x[, .r := rnorm(.N, 0.0002, 0.012)]
  x[, Close := 10000 * cumprod(1 + .r), by = Ticker]
  x[, .r := NULL]
  x[, Vol := 2e6]
  x[, Size := Close * 1e6]
  x[, .id := as.integer(sub("T", "", Ticker, fixed = TRUE))]
  x[, K200 := .id <= idx_n]
  x[, KQ150 := FALSE]
  x[, Sector_Lv2 := paste0("S", (.id %% 5L) + 1L)]
  x[, .id := NULL]
  x[]
}
FIX <- make_fixture()
BMF <- { .t <- copy(FIX); setorder(.t, Ticker, Date)
         .t[, r := Close / shift(Close, 1L) - 1, by = Ticker]
         .t[is.finite(r), .(BM_Ret = mean(r)), by = Date][order(Date)] }
SIG <- sort(FIX[Date >= as.Date("2005-01-01"), .(d = max(Date)), by = .(ym = format(Date, "%Y%m"))]$d)
N_SIG <- length(SIG)
BM_NEG <- copy(BMF)[Date > SIG[N_SIG - 1L], BM_Ret := -0.03]     # 마지막 달만 섭동 — t=N−1 행의 fwd 만 바뀐다
BM_POS <- copy(BMF)[Date > SIG[N_SIG - 1L], BM_Ret :=  0.03]

# ── 스텁 루트 — 엔진 의존 정본 사본 + 정본 arm 2종 + 스텁·위반 arm ─────────────
STUB <- file.path(TD, "root")
for (dd in c("02_Infrastructure/validation", "02_Infrastructure/reinforcement/overlay_arms", "02_Infrastructure/portfolio", "06_Registry"))
  dir.create(file.path(STUB, dd), recursive = TRUE, showWarnings = FALSE)
for (f in c("02_Infrastructure/validation/overlay_pit_guard.R", "02_Infrastructure/reinforcement/rf_rebalance.R",
            "02_Infrastructure/reinforcement/rf_sleeve.R", "02_Infrastructure/backtest_harness.R",
            "02_Infrastructure/portfolio/weight_catalog.R",
            "02_Infrastructure/reinforcement/overlay_arms/dbeta_tilt.R",
            "02_Infrastructure/reinforcement/overlay_arms/gen_20260906_174032.R",
            "06_Registry/overlay_probe_future.json",
            "06_Registry/overlay_probe_allowlist.json"))   # ★R3R probe ③d 허용 목록(부재 = FAIL)
  if (!file.copy(file.path(ROOT, f), file.path(STUB, f), overwrite = TRUE)) ng("스텁 루트 사본", f)
ADIR <- file.path(STUB, "02_Infrastructure/reinforcement/overlay_arms")
.arm <- function(kind, body) writeLines(body, file.path(ADIR, paste0(kind, ".R")))
.arm("stub_scal", "overlay_expo_stub_scal <- function(H, t, ctx) if (t %% 2L == 0L) 0.6 else 0.9")
.arm("stub_spyna", c(
  "# t 행 fwd 가 NA 인지 · 과거 행(t−1) fwd 가 온전한지 전역 .P009_SPY 에 남긴다 — 산출은 살아 있는 스칼라",
  "overlay_expo_stub_spyna <- function(H, t, ctx) {",
  "  rec <- get0('.P009_SPY', envir = globalenv(), ifnotfound = list())",
  "  rec[[length(rec) + 1L]] <- list(t = t, na_t = is.na(H$fwd[t]), fin_prev = if (t >= 2L) is.finite(H$fwd[t - 1L]) else NA, nr = nrow(H))",
  "  assign('.P009_SPY', rec, envir = globalenv())",
  "  if (t %% 3L == 0L) 0.7 else 1",
  "}"))
.arm("stub_leak_fb", c(
  "# ★시험 전용 위반 — fwd[t](익월 수익)가 보이면 읽는다. 안 보이면(NA) 살아 있는 대체 스칼라.",
  "overlay_expo_stub_leak_fb <- function(H, t, ctx) {",
  "  f <- H$fwd[t]",
  "  if (is.finite(f)) { if (f < 0) 0.3 else 1 } else if (t %% 2L == 0L) 0.6 else 0.9",
  "}"))
.arm("stub_leak_hard", "overlay_expo_stub_leak_hard <- function(H, t, ctx) { f <- H$fwd[t]; if (f < 0) 0.3 else 0.9 }")
.arm("zz_v1_tailpeek", c(
  "# ★시험 전용 위반 V1 — fwd[t] 가 과거 하 10% 꼬리 아래일 때만 현금('익월 폭락이면 현금'). 평시 = 정직한 변동성 스케일.",
  "overlay_expo_zz_v1_tailpeek <- function(H, t, ctx) {",
  "  f <- H$fwd[t]",
  "  past <- H$fwd[seq_len(t - 1L)]",
  "  q <- stats::quantile(past[is.finite(past)], probs = 0.1, names = FALSE)",
  "  base <- if (is.finite(ctx$v_now) && ctx$v_now > 0) min(1, ctx$tgt / ctx$v_now) else 1",
  "  if (is.finite(f) && is.finite(q) && f < q) return(0)",
  "  base",
  "}"))
.arm("zz_v2_crisispeek", c(
  "# ★시험 전용 위반 V2 — 낙폭이 자기 이력 최고일 때(위기 국면)만 fwd[t] 를 본다. 평시 = 정직한 변동성 스케일.",
  "overlay_expo_zz_v2_crisispeek <- function(H, t, ctx) {",
  "  base <- if (is.finite(ctx$v_now) && ctx$v_now > 0) min(1, ctx$tgt / ctx$v_now) else 1",
  "  dmax <- max(H$dd[seq_len(t - 1L)], na.rm = TRUE)",
  "  if (is.finite(H$dd[t]) && H$dd[t] >= dmax) {",
  "    f <- H$fwd[t]",
  "    if (is.finite(f) && f < stats::median(H$fwd[seq_len(t - 1L)], na.rm = TRUE)) return(0)",
  "  }",
  "  base",
  "}"))
.arm("zz_direct", c(
  "overlay_expo_zz_direct <- function(H, t, ctx) {",
  "  f <- H$fwd[t]",
  "  if (!is.finite(f)) return(1)",
  "  max(0, min(1, 1 - abs(f)))",
  "}"))

AXES <- list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150",
             start_date = "2005-01-01", commission_bps = 15L, liq_adv20_min = 2e8)
base_spec <- function(...) modifyList(list(
  code = "P009", label = "p0-09 mask", block = "T", fixed_axes = AXES,
  base_signal = list(kind = "mom_12_1"), weighting = list(kind = "ew"),
  universe = list(kind = "k200_kq150"), factor2 = list(kind = "none")), list(...))
L <- function(kind, arm = paste0(kind, "_x")) list(kind = kind, arm_id = arm)

# 엔진을 격리 env 에서 평가 — QM_ROOT 는 실행 동안만 스텁 루트로. env 를 돌려줘 내부 상태(.USED_CUT 등)를 읽는다.
run_cell <- function(spec, engine = ENGINE, bm = BMF, root = STUB) {
  p <- file.path(TD, "spec.json")
  writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  old_root <- Sys.getenv("QM_ROOT", unset = NA); old_spec <- Sys.getenv("RF_CELL_SPEC", unset = NA)
  Sys.setenv(RF_CELL_SPEC = p, QM_ROOT = root)
  on.exit({ if (is.na(old_root)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = old_root)
            if (is.na(old_spec)) Sys.unsetenv("RF_CELL_SPEC") else Sys.setenv(RF_CELL_SPEC = old_spec) }, add = TRUE)
  env <- new.env()
  assign("RAWDATA", copy(FIX), envir = env); assign("BM_DT", bm, envir = env)
  err <- NULL
  lg <- utils::capture.output(suppressWarnings(suppressMessages(
    tryCatch(source(engine, local = env), error = function(e) err <<- conditionMessage(e)))))
  list(err = err, log = lg, env = env,
       port = if (exists("PORTFOLIO", envir = env, inherits = FALSE)) as.data.table(get("PORTFOLIO", envir = env))[order(Date, Ticker)] else NULL,
       fac  = if (exists("FACTORS", envir = env, inherits = FALSE)) as.data.table(get("FACTORS", envir = env))[order(Date, Ticker)] else NULL)
}
# 돌연변이 엔진 — 신판 텍스트에서 정확히 한 번 나오는 앵커를 바꾼다(앵커가 없거나 여럿이면 실패로 센다: 좌표가 옮겨졌다는 뜻).
ENG_TXT <- readLines(ENGINE, warn = FALSE, encoding = "UTF-8")
mutant <- function(tag, pairs) {
  x <- ENG_TXT
  for (pr in pairs) {
    hit <- which(grepl(pr[1], x, fixed = TRUE))
    if (length(hit) != 1L) { ng(sprintf("돌연변이 %s 앵커", tag), sprintf("'%s' %d건(1건이어야 한다)", pr[1], length(hit))); return(NULL) }
    x[hit] <- if (identical(pr[2], "")) "" else sub(pr[1], pr[2], x[hit], fixed = TRUE)
  }
  p <- file.path(TD, sprintf("rf_cell_engine_%s.R", tag)); writeLines(x, p, useBytes = TRUE); p
}
held_of <- function(r) { h <- r$fac[, .(Date, Ticker)]; h[, N := .N, by = Date]; h[, t := match(Date, SIG)]; h }
oe_of <- function(r, held) {
  z <- merge(held, r$port[, .(Date, Ticker, Weight)], by = c("Date", "Ticker"), all.x = TRUE)
  z[is.na(Weight), Weight := 0]; z[, oe := Weight * N]; z[order(Date, Ticker), .(Date, Ticker, t, oe)]
}
scal_of <- function(r, held) oe_of(r, held)[, .(oe = oe[1]), by = .(Date, t)][order(t)]
same_port <- function(a, b) !is.null(a) && !is.null(b) && identical(a$Date, b$Date) && identical(a$Ticker, b$Ticker) && identical(a$Weight, b$Weight)

writeLines("=== 0. 기저 ===")
r0 <- run_cell(base_spec())
if (is.null(r0$err) && !is.null(r0$fac)) { HELD <- held_of(r0); ok(sprintf("0 오버레이 없음 → FACTORS %d행 · 시그널일 %d", nrow(r0$fac), N_SIG)) } else {
  ng("0 기저", r0$err %||% "산출 없음"); quit(status = 1L) }

writeLines("=== A1. arm 이 받은 t 행 fwd — 신판 NA · 과거 행 온전 · 구판 실값 ===")
spy <- function() get0(".P009_SPY", envir = globalenv(), ifnotfound = list())
assign(".P009_SPY", list(), envir = globalenv()); r1 <- run_cell(base_spec(overlay = L("stub_spyna"))); s1 <- spy()
if (is.null(r1$err) && length(s1) && all(vapply(s1, `[[`, logical(1), "na_t")))
  ok(sprintf("A1a 신판 — 호출 %d회 전부 H$fwd[t] = NA", length(s1))) else ng("A1a t 행 fwd 가 NA 가 아니다", r1$err %||% sprintf("NA %d/%d", sum(vapply(s1, `[[`, logical(1), "na_t")), length(s1)))
fp1 <- vapply(Filter(function(z) z$t >= 13L && z$t <= N_SIG, s1), `[[`, logical(1), "fin_prev")
if (length(fp1) && all(fp1)) ok(sprintf("A1b 신판 — 과거 행(t−1) fwd 는 %d회 전부 실현값(학습쌍 보존)", length(fp1))) else ng("A1b 과거 행 fwd 소실", sprintf("%d/%d", sum(fp1), length(fp1)))
if (HAVE_OLD_E) {
  assign(".P009_SPY", list(), envir = globalenv()); r1o <- run_cell(base_spec(overlay = L("stub_spyna")), engine = OLD_ENGINE); s1o <- spy()
  na_o <- vapply(Filter(function(z) z$t < N_SIG, s1o), `[[`, logical(1), "na_t")
  if (is.null(r1o$err) && length(na_o) && !any(na_o)) ok(sprintf("A1c 구판 빨강 — t<N 호출 %d회 전부 t 행 fwd 실값 노출(익월 수익)", length(na_o))) else
    ng("A1c 구판이 t 행을 노출하지 않는다", r1o$err %||% "검사가 결함을 못 본다")
}

writeLines("=== A2. fwd[t] 를 읽는 arm — 마지막 달 BM 섭동에 t=N−1 노출 ===")
rLn <- run_cell(base_spec(overlay = L("stub_leak_fb")), bm = BM_NEG); rLp <- run_cell(base_spec(overlay = L("stub_leak_fb")), bm = BM_POS)
if (is.null(rLn$err) && is.null(rLp$err)) {
  Ln <- scal_of(rLn, HELD); Lp <- scal_of(rLp, HELD)
  d_n1 <- abs(Ln[t == N_SIG - 1L]$oe - Lp[t == N_SIG - 1L]$oe)
  if (d_n1 < 1e-12 && max(abs(Ln$oe - Lp$oe)) < 1e-12) ok("A2a 신판 — 섭동 두 판의 노출 경로 전 구간 동일(t 행 익월 정보가 노출에 닿지 않는다)") else
    ng("A2a 신판에 누출이 남았다", sprintf("t=N−1 차 %.3f · 최대 차 %.3e", d_n1, max(abs(Ln$oe - Lp$oe))))
} else ng("A2a 신판 실행", paste(rLn$err, rLp$err))
if (HAVE_OLD_E) {
  rLno <- run_cell(base_spec(overlay = L("stub_leak_fb")), engine = OLD_ENGINE, bm = BM_NEG)
  rLpo <- run_cell(base_spec(overlay = L("stub_leak_fb")), engine = OLD_ENGINE, bm = BM_POS)
  if (is.null(rLno$err) && is.null(rLpo$err)) {
    a <- scal_of(rLno, HELD)[t == N_SIG - 1L]$oe; b <- scal_of(rLpo, HELD)[t == N_SIG - 1L]$oe
    if (abs(a - b) > 0.5) ok(sprintf("A2b 구판 빨강 — 같은 arm·같은 섭동에 t=N−1 노출 %.2f→%.2f (익월 수익으로 노출을 정했다)", a, b)) else
      ng("A2b 구판이 누출을 보이지 않는다", sprintf("%.3f vs %.3f", a, b))
  } else ng("A2b 구판 실행", paste(rLno$err, rLpo$err))
}
rLs <- run_cell(base_spec(overlay = L("stub_leak_fb"), overlay_shift = 1L), bm = BM_NEG)
rLsp <- run_cell(base_spec(overlay = L("stub_leak_fb"), overlay_shift = 1L), bm = BM_POS)
if (is.null(rLs$err) && is.null(rLsp$err) && same_port(rLs$port, rLsp$port)) ok("A2c 신판 shift=1 — 섭동 두 판 PORTFOLIO 비트 동일") else ng("A2c shift 판", paste(rLs$err, rLsp$err))

writeLines("=== A3. fwd[t] 를 NA 검사 없이 읽는 arm — 신판은 선다 ===")
r3 <- run_cell(base_spec(overlay = L("stub_leak_hard")))
if (!is.null(r3$err) && !any(grepl("overlay stub_leak_hard", r3$log, fixed = TRUE)))
  ok(sprintf("A3 신판 정지(오버레이 적용 전) — %s", substr(r3$err, 1, 80))) else ng("A3 NA 를 받은 위반 arm 이 오버레이를 끝까지 적용했다", r3$err %||% "오류 없음")

writeLines("=== A4. 정직 arm — 신·구 산출 비트 동일 (과거 fwd 를 학습하는 arm 포함) ===")
if (HAVE_OLD_E) {
  REG <- list(
    list(nm = "no overlay(FACTORS)",                  spec = base_spec()),
    list(nm = "stub_scal(파일 스칼라)",                spec = base_spec(overlay = L("stub_scal"))),
    list(nm = "dbeta_tilt(정본 벡터)",                 spec = base_spec(overlay = L("dbeta_tilt", "dbeta_tilt_rank"))),
    list(nm = "gen_20260906_174032(정본 · fwd[1..t−1] 학습)", spec = base_spec(overlay = L("gen_20260906_174032"))),
    list(nm = "ml_tail_gate(빌트인 · fwd[1..t−1] 학습)", spec = base_spec(overlay = list(kind = "ml_tail_gate"))),
    list(nm = "har_vol(빌트인)",                       spec = base_spec(overlay = list(kind = "har_vol"))),
    list(nm = "dd_brake(빌트인)",                      spec = base_spec(overlay = list(kind = "dd_brake", arm_id = "dd_brake_q"))),
    list(nm = "stub_scal+dbeta_tilt(중첩)",             spec = base_spec(overlay = list(L("stub_scal"), L("dbeta_tilt", "dbeta_tilt_rank")))),
    list(nm = "stub_scal shift=1",                     spec = base_spec(overlay = L("stub_scal"), overlay_shift = 1L)))
  n_port <- 0L
  for (g in REG) {
    a <- run_cell(g$spec); b <- run_cell(g$spec, engine = OLD_ENGINE)
    if (!is.null(a$err) || !is.null(b$err)) {
      if (identical(a$err, b$err)) ok(sprintf("A4 %s — 신·구 같은 정지 문자열(%s)", g$nm, substr(a$err %||% "", 1, 50))) else
        ng(sprintf("A4 %s 실행", g$nm), sprintf("신 %s / 구 %s", a$err %||% "-", b$err %||% "-"))
      next
    }
    if (!is.null(a$fac) && is.null(a$port)) {
      if (!is.null(b$fac) && identical(a$fac, b$fac)) ok(sprintf("A4 %s — FACTORS %d행 비트 동일", g$nm, nrow(a$fac))) else ng(sprintf("A4 %s FACTORS 상이", g$nm))
    } else if (same_port(a$port, b$port)) { n_port <- n_port + 1L; ok(sprintf("A4 %s — PORTFOLIO %d행 비트 동일", g$nm, nrow(a$port))) } else
      ng(sprintf("A4 %s PORTFOLIO 상이", g$nm), sprintf("신 %d행 / 구 %d행", nrow(a$port %||% data.table()), nrow(b$port %||% data.table())))
  }
  if (n_port >= 6L) ok(sprintf("A4 전제 — 오버레이 산출 %d종이 실제로 PORTFOLIO 를 냈다(정지끼리 같다는 약한 비교만으로 통과하지 않는다)", n_port)) else
    ng("A4 전제", sprintf("PORTFOLIO 비교 %d종 < 6", n_port))
} else ng("A4 회귀", "기준본 엔진 없음")

writeLines("=== A5. assert 입력 실체 — 넘긴 값의 가용일 · 홀딩 시작 · .M 불변 ===")
rA <- run_cell(base_spec(overlay = list(L("stub_scal"), L("dbeta_tilt", "dbeta_tilt_rank"))))
if (is.null(rA$err)) {
  E <- rA$env; Md <- E$.M$Date; U <- E$.USED_CUT; tt <- seq_along(Md) >= E$.n_floor
  if (all(!is.na(U[tt])) && all(is.na(U[!tt]))) ok(sprintf("A5a 가용일 기록 — arm 을 부른 %d시점 전부 · 부르지 않은 %d시점 NA", sum(tt), sum(!tt))) else ng("A5a 가용일 기록 누락", "")
  if (all(U[tt] <= Md[tt]) && all(U[tt] < E$.hs_eff[tt])) ok("A5b 넘긴 값의 최대 가용일 ≤ 신호일 < 홀딩 시작(마스크 뒤 t 행 fwd 가 빠졌다)") else ng("A5b 가용일이 홀딩 시작을 넘는다", "")
  if (identical(E$.M$fwd, E$.M_FWD0) && sum(is.na(E$.M$fwd)) == 1L) ok("A5c .M(학습 행) fwd 불변 — 마스크는 H 사본에만(원천 NA 는 마지막 행 1개)") else ng("A5c .M fwd 가 바뀌었다", "")
  if (length(E$.hs_eff) == length(E$.hs) && isTRUE(all(E$.hs_eff == E$.hs))) ok("A5d 홀딩 시작 = 달력 익월 1일(집행일 get_execution_date 는 그 이후라 결속하지 않는다)") else
    ng("A5d 홀딩 시작이 달력과 다르다", sprintf("%d행 상이", sum(E$.hs_eff != E$.hs, na.rm = TRUE)))
  if (!is.null(E$.HOLD_AV) && nrow(E$.HOLD_AV) && all(E$.HOLD_AV$av <= E$.HOLD_AV$Date)) ok(sprintf("A5e ctx$hold 실제 관측일 ≤ 신호일 (%d신호일)", nrow(E$.HOLD_AV))) else ng("A5e hold 관측일", "")
  if (!any(grepl("get_execution_date 미적재", rA$log, fixed = TRUE))) ok("A5f 하네스 get_execution_date 적재(정의만 parse) — 집행일 축이 실제로 들어갔다") else ng("A5f 집행일 미적재", "")
} else ng("A5 실행", rA$err)

writeLines("=== A5g. 집행일 축 호출 실패 → 달력 폴백 (서지 않는다 · 느슨해지지 않는다) ===")
# 하네스의 get_execution_date 가 이 파일 밖 도우미를 부르게 바뀐 판을 주입한다(엔진은 정의만 parse 해 격리 env 에서 부른다).
#   신판: 정지 없이 로그 '호출 실패' + 홀딩 시작 = 달력(.hs) · 산출은 정상 하네스 판과 비트 동일(집행일 축은 조이기만 하므로)
#   돌연변이(호출을 tryCatch 밖으로 = 설치 1판 등가): 오버레이 칸 전부가 선다
STUB_BH <- file.path(TD, "root_bh"); dir.create(STUB_BH, showWarnings = FALSE)
invisible(file.copy(list.files(STUB, full.names = TRUE), STUB_BH, recursive = TRUE))
writeLines(c("get_execution_date <- function(signal_date, all_dates) .p009_missing_helper(signal_date, all_dates)"),
           file.path(STUB_BH, "02_Infrastructure/backtest_harness.R"))
rG <- run_cell(base_spec(overlay = L("stub_scal")), root = STUB_BH)
rG0 <- run_cell(base_spec(overlay = L("stub_scal")))
if (is.null(rG$err) && any(grepl("get_execution_date 호출 실패", rG$log, fixed = TRUE)) &&
    isTRUE(all(rG$env$.hs_eff == rG$env$.hs)) && same_port(rG$port, rG0$port))
  ok("A5g 집행일 호출 실패 → 정지 없음 · '호출 실패' 로그 · 홀딩 시작 = 달력 · PORTFOLIO 정상 하네스 판과 비트 동일") else
  ng("A5g 호출 실패 폴백", rG$err %||% sprintf("로그 %s · hs 동일 %s · 산출 동일 %s", any(grepl("호출 실패", rG$log, fixed = TRUE)),
                                              isTRUE(all(rG$env$.hs_eff == rG$env$.hs)), same_port(rG$port, rG0$port)))
mG <- mutant("exec_nocatch", list(c("tryCatch(as.Date(vapply(sig, function(s) as.numeric(.f(s, .ad)), numeric(1)), origin = \"1970-01-01\"),",
                                    "(function(x, error) x)(as.Date(vapply(sig, function(s) as.numeric(.f(s, .ad)), numeric(1)), origin = \"1970-01-01\"),")))
if (!is.null(mG)) {
  rGm <- run_cell(base_spec(overlay = L("stub_scal")), engine = mG, root = STUB_BH)
  if (!is.null(rGm$err) && grepl("p009_missing_helper", rGm$err, fixed = TRUE))
    ok(sprintf("A5g 돌연변이 빨강 — 호출을 tryCatch 밖으로 빼면 오버레이 칸이 선다: %s", substr(rGm$err, 1, 70))) else
    ng("A5g 돌연변이가 서지 않는다 — 폴백 검사가 하중을 안 진다", rGm$err %||% "오류 없음")
}

writeLines("=== A6. 돌연변이 — 마스크 제거 → assert 가 선다 (cutoff > holding_start 주입) ===")
MASK_ANCHOR <- "H[t, fwd := NA_real_]"
m1 <- mutant("nomask", list(c(MASK_ANCHOR, "")))
if (!is.null(m1)) {
  r6 <- run_cell(base_spec(overlay = L("stub_scal")), engine = m1)
  if (!is.null(r6$err) && grepl("LOOK-AHEAD", r6$err, fixed = TRUE) && grepl("P0-09", r6$err, fixed = TRUE))
    ok(sprintf("A6a 마스크 없는 판 — 정직 arm 이어도 assert 정지(넘긴 fwd[t] 의 가용일 > 홀딩 시작): %s", substr(r6$err, 1, 90))) else
    ng("A6a 마스크 제거가 조용히 통과한다 — assert 가 방어선이 아니다", r6$err %||% "오류 없음")
  r6s <- run_cell(base_spec(overlay = L("stub_scal"), overlay_shift = 1L), engine = m1)
  if (is.null(r6s$err)) ok("A6b 같은 돌연변이의 shift=1 판은 서지 않는다(t−1 에 넘긴 fwd 는 t 에 실현 — assert 가 적용 시점을 잰다)") else
    ng("A6b shift 판 과잉 정지", r6s$err)
}

writeLines("=== A7. 돌연변이 — 마스크를 .M 에 걸면 불변식이 선다 ===")
m2 <- mutant("maskM", list(c(MASK_ANCHOR, ".M[t, fwd := NA_real_]")))
if (!is.null(m2)) {
  r7 <- run_cell(base_spec(overlay = list(kind = "ml_tail_gate")), engine = m2)
  if (!is.null(r7$err) && grepl("P0-09 fwd 마스크가 .M", r7$err, fixed = TRUE) && grepl("측정 무효", r7$err, fixed = TRUE))
    ok("A7 .M 오염 돌연변이 → 불변식 정지(러너 결정론 패턴 '측정 무효' 포함)") else ng("A7 .M 오염이 통과한다", r7$err %||% "오류 없음")
}

writeLines("=== A8. 돌연변이 — 마스크 제거 + 구 assert 입력 = 구판 등가 → 아무것도 안 선다 ===")
m3 <- mutant("oldeq", list(c(MASK_ANCHOR, ""), c("assert_overlay_pit(.cut_applied, .hs_eff - 1L,", "assert_overlay_pit(.M$Date, .hs,")))
if (!is.null(m3)) {
  r8 <- run_cell(base_spec(overlay = L("stub_leak_fb")), engine = m3)
  if (is.null(r8$err) && !is.null(r8$port)) ok("A8 구판 등가 — 익월 수익을 읽는 arm 이 구 assert(.M$Date vs .hs)를 그대로 통과(동어반복 실증)") else
    ng("A8 구판 등가 판이 섰다 — 구 assert 가 동어반복이라는 전제가 틀렸다", r8$err %||% "")
}

writeLines("=== A9. assert 엄격 부등호 — 한계 = 홀딩 시작 전날 ===")
gE <- new.env(); suppressMessages(sys.source(file.path(STUB, "02_Infrastructure/validation/overlay_pit_guard.R"), envir = gE))
hs <- as.Date(c("2010-02-01", "2010-03-01"))
e9a <- tryCatch({ gE$assert_overlay_pit(hs, hs - 1L, label = "t"); NULL }, error = function(e) conditionMessage(e))
e9b <- tryCatch({ gE$assert_overlay_pit(hs - 1L, hs - 1L, label = "t"); NULL }, error = function(e) conditionMessage(e))
if (!is.null(e9a) && is.null(e9b)) ok("A9 가용일 = 홀딩 시작일이면 정지 · 전날이면 통과 (pit.md C5 'Date < 컷오프')") else ng("A9 경계", paste(e9a, e9b))

writeLines("=== B. overlay_probe ④ 미래 섭동 확장 ===")
pN <- new.env(); suppressMessages(capture.output(sys.source(PROBE, envir = pN)))
fut_of <- function(r) { z <- r$checks[r$checks$check == "future", ]; if (nrow(z)) z$status[1] else "-" }
fp <- pN$overlay_probe_future_params(STUB)
if (isTRUE(fp$ok) && sum(fp$points) == 12L && "na" %in% fp$perturb) ok(sprintf("B0 설정 적재 — %d시점 · 섭동 %s", sum(fp$points), paste(fp$perturb, collapse = "·"))) else ng("B0 설정", fp$reason %||% "")
if (HAVE_OLD_P) {
  pO <- new.env(); suppressMessages(capture.output(sys.source(OLD_PROBE, envir = pO)))
  for (k in c("zz_v1_tailpeek", "zz_v2_crisispeek")) {
    invisible(capture.output(ro <- pO$overlay_probe_arm(k, STUB)))
    if (isTRUE(ro$ok) && identical(fut_of(ro), "PASS")) ok(sprintf("B1 구판 probe 가 위반 arm %s 를 통과시킨다(④ PASS = 결함 실증)", k)) else
      ng(sprintf("B1 구판이 %s 를 이미 잡는다 — 결함 전제가 틀렸다", k), as.character(ro$reason))
  }
} else ng("B1 구판 probe", "기준본 없음")
for (k in c("zz_v1_tailpeek", "zz_v2_crisispeek", "zz_direct", "stub_leak_hard", "stub_leak_fb")) {
  invisible(capture.output(rn <- pN$overlay_probe_arm(k, STUB)))
  if (!isTRUE(rn$ok) && identical(fut_of(rn), "FAIL") && grepl("미래 참조", rn$reason, fixed = TRUE))
    ok(sprintf("B2 신판 probe 가 %s 를 ④ future 에서 거부 — %s", k, substr(rn$reason, 30, 110))) else
    ng(sprintf("B2 신판이 %s 를 못 잡는다", k), as.character(rn$reason))
}
for (k in c("dbeta_tilt", "gen_20260906_174032", "stub_scal")) {
  invisible(capture.output(rn <- pN$overlay_probe_arm(k, STUB)))
  if (!isTRUE(rn$ok)) { ng(sprintf("B3 정직 arm %s 과잉 차단", k), as.character(rn$reason)); next }
  if (HAVE_OLD_P) {
    invisible(capture.output(ro <- pO$overlay_probe_arm(k, STUB)))
    if (isTRUE(ro$ok) && isTRUE(all.equal(ro$t_var, rn$t_var)) && isTRUE(all.equal(ro$x_var, rn$x_var)) && identical(ro$axis, rn$axis))
      ok(sprintf("B3 정직 arm %s — 신·구 통과 · 처치 통계(t_var·x_var·축) 동일", k)) else ng(sprintf("B3 %s 신·구 상이", k), "")
  } else ok(sprintf("B3 정직 arm %s 통과", k))
}
fx <- pN$overlay_probe_fixture()
P1 <- pN$overlay_probe_future_points(fx$M, fp); P2 <- pN$overlay_probe_future_points(fx$M, fp)
if (identical(P1, P2) && nrow(P1) == 12L && !anyDuplicated(P1$t) && all(P1$t >= fp$t_floor) &&
    setequal(unique(P1$why), c("fwd_low", "fwd_high", "state_dd", "state_rv60", "spread")))
  ok(sprintf("B4a 섭동 시점 결정론 · 12점 · 중복 없음 · 5분기 전부 (%s)", paste(P1$t, collapse = ","))) else ng("B4a 시점 선택", paste(P1$t, collapse = ","))
if (any(P1$t %in% 69:78) && any(P1$why == "fwd_low" & P1$t %in% 69:77)) ok("B4b 위기 1 구간(70:78) 직전·중 시점이 표본에 든다(fwd 하 꼬리 포함)") else ng("B4b 위기 구간 미포함", paste(P1$t, collapse = ","))

# 설정 fail-closed — 별도 스텁 루트(설정만 바꾼다)
cfg_root <- function(tag, cfg) {
  r <- file.path(TD, paste0("cfg_", tag))
  dir.create(file.path(r, "02_Infrastructure/reinforcement/overlay_arms"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  for (k in c("zz_v1_tailpeek", "dbeta_tilt")) file.copy(file.path(ADIR, paste0(k, ".R")), file.path(r, "02_Infrastructure/reinforcement/overlay_arms"), overwrite = TRUE)
  if (!is.null(cfg)) writeLines(toJSON(cfg, auto_unbox = TRUE, pretty = TRUE), file.path(r, "06_Registry/overlay_probe_future.json"))
  # ★R3R — ③d 허용 목록은 ④ 설정과 별개 축이다. B5 는 ④ 설정만 흔든다(QM_ROOT = 이 스텁이라 정본 폴백이 없다) — 목록은 둔다
  file.copy(file.path(ROOT, "06_Registry/overlay_probe_allowlist.json"), file.path(r, "06_Registry"), overwrite = TRUE)
  r
}
C0 <- fromJSON(CFG, simplifyVector = FALSE)
# ★modifyList 는 이름 없는 리스트(perturb)를 병합하지 않고 그대로 둔다 — 원소를 직접 바꾼다.
set_cfg <- function(x, ...) { v <- list(...); for (k in names(v)) x[[k]] <- v[[k]]; x }
for (cs in list(list(tag = "absent", cfg = NULL, why = "설정 부재"),
                list(tag = "schema", cfg = set_cfg(C0, schema = "x"), why = "schema"),
                list(tag = "nona",   cfg = set_cfg(C0, perturb = list("median")), why = "na 필수"))) {
  cr <- cfg_root(cs$tag, cs$cfg)
  # ★probe 는 root 에 설정이 없으면 QM_ROOT(정본) 설정을 읽는다 — 부재 판정은 두 곳 다 없게 만든다(QM_ROOT = 이 스텁)
  old_q <- Sys.getenv("QM_ROOT", unset = NA); Sys.setenv(QM_ROOT = cr)
  invisible(capture.output(rc <- pN$overlay_probe_arm("dbeta_tilt", cr)))
  if (is.na(old_q)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = old_q)
  if (!isTRUE(rc$ok) && identical(fut_of(rc), "FAIL")) ok(sprintf("B5 설정 %s → ④ FAIL(정직 arm 도 통과시키지 않는다 · fail-closed)", cs$why)) else ng(sprintf("B5 설정 %s 가 통과", cs$why), as.character(rc$reason))
}
# 폴백 양성 대조 — root 에 설정이 없고 QM_ROOT(정본)에 있으면 정본 설정으로 재고 그 사실을 ④ 상세에 남긴다
invisible(capture.output(rfb <- pN$overlay_probe_arm("dbeta_tilt", cfg_root("fallback", NULL))))
dfb <- rfb$checks[rfb$checks$check == "future", ]$detail
if (isTRUE(rfb$ok) && length(dfb) && grepl("QM_ROOT 폴백", dfb[1], fixed = TRUE)) ok("B5b root 무설정 → 정본(QM_ROOT) 설정으로 측정 · 상세에 'QM_ROOT 폴백' 표기") else
  ng("B5b 폴백", paste(rfb$reason, dfb))
# 돌연변이 — 설정을 구판 수준(한 점 · 한 방향)으로 줄이면 V1 이 다시 통과한다
weak <- set_cfg(C0, points = list(fwd_low = 0L, fwd_high = 0L, state_dd = 0L, state_rv60 = 0L, spread = 1L), perturb = list("na", "above_max"))
invisible(capture.output(rw <- pN$overlay_probe_arm("zz_v1_tailpeek", cfg_root("weak", weak))))
if (isTRUE(rw$ok)) ok("B6 약화 돌연변이(1점 · na+상방) → V1 통과 = 확장(꼬리 시점·하방 섭동)이 하중을 진다") else ng("B6 약화 설정도 V1 을 잡는다 — 확장의 기여가 안 보인다", as.character(rw$reason))

writeLines("=== B7. 호출자 스코프 통로 — 마스크(H 사본)를 돌아가는 arm · probe ③c (P0-09 보강 2026-09-25) ===")
# 위반 arm 두 종: 엔진 평가 프레임에서 마스크 전 .M 을 dynGet 으로 · 미래 BM_DT 를 parent.frame() 으로 읽는다. 못 찾으면(probe 픽스처) 정직한 대체값.
.arm("zz_dyn", c(
  "overlay_expo_zz_dyn <- function(H, t, ctx) {",
  "  M <- dynGet('.M', ifnotfound = NULL)",
  "  if (!is.null(M) && is.finite(M$fwd[t])) return(if (M$fwd[t] < 0) 0.3 else 1)",
  "  if (t %% 2L == 0L) 0.6 else 0.9",
  "}"))
.arm("zz_pf", c(
  "overlay_expo_zz_pf <- function(H, t, ctx) {",
  "  b <- get0('BM_DT', envir = parent.frame(), ifnotfound = NULL)",
  "  if (!is.null(b)) { f <- b$BM_Ret[b$Date > ctx$date][1:5]; if (all(is.finite(f))) return(if (sum(f) < 0) 0.3 else 1) }",
  "  if (t %% 2L == 0L) 0.6 else 0.9",
  "}"))
for (k in c("zz_dyn", "zz_pf")) {
  rn <- run_cell(base_spec(overlay = L(k)), bm = BM_NEG); rp <- run_cell(base_spec(overlay = L(k)), bm = BM_POS)
  if (is.null(rn$err) && is.null(rp$err)) {
    a <- scal_of(rn, HELD)[t == N_SIG - 1L]$oe; b <- scal_of(rp, HELD)[t == N_SIG - 1L]$oe
    if (abs(a - b) > 0.5) ok(sprintf("B7a 결함 실증 — %s 는 마스크 뒤에도 익월 섭동에 t=N−1 노출 %.2f→%.2f (H 밖 통로 · 마스크로는 못 막는다)", k, a, b)) else
      ng(sprintf("B7a %s 통로가 엔진에서 안 열린다 — 전제 재확인", k), sprintf("%.3f vs %.3f", a, b))
  } else ng(sprintf("B7a %s 실행", k), paste(rn$err, rp$err))
}
PX <- readLines(PROBE, warn = FALSE, encoding = "UTF-8")
SC_ANCHOR <- "  scope <- overlay_probe_scope_scan(src)"
hitc <- which(PX == SC_ANCHOR)
AL_ANCHOR <- "  al_s <- overlay_probe_allowlist_scan(p, kind = kind, root = root)"
hita <- which(PX == AL_ANCHOR)
if (length(hitc) == 1L && length(hita) == 1L) {
  # ★R3R(2026-09-25): 정적 층이 둘이 됐다 — ③c(알려진 통로 열거) · ③d(허용 목록). ③c 만 끄면 ③d 가 잡고(중복 방어),
  #   둘 다 꺼야 ④ 값 섭동까지 통과한다(정적 층이 하중을 진다 — ④ 는 H 만 흔든다).
  PX1 <- PX; PX1[hitc] <- "  scope <- overlay_probe_scope_scan(src)[0]"          # ③c 무력화(0행 = 통과)
  PM1 <- file.path(TD, "overlay_probe_noscope.R"); writeLines(PX1, PM1, useBytes = TRUE)
  pM1 <- new.env(); suppressMessages(capture.output(sys.source(PM1, envir = pM1)))
  PX2 <- PX1; PX2[hita] <- "  al_s <- list(ok = TRUE, grant = \"MUTANT\", al_path = \"-\", fallback = FALSE)"   # ③d 도 무력화
  PM2 <- file.path(TD, "overlay_probe_nostatic.R"); writeLines(PX2, PM2, useBytes = TRUE)
  pM <- new.env(); suppressMessages(capture.output(sys.source(PM2, envir = pM)))
  al_of <- function(r) { z <- r$checks[r$checks$check == "allowlist", ]; if (nrow(z)) z$status[1] else "-" }
  for (k in c("zz_dyn", "zz_pf")) {
    invisible(capture.output(r1_ <- pM1$overlay_probe_arm(k, STUB)))
    if (!isTRUE(r1_$ok) && identical(al_of(r1_), "FAIL")) ok(sprintf("B7b' ③c 만 끈 probe 는 %s 를 ③d allowlist 에서 거부(중복 방어)", k)) else
      ng(sprintf("B7b' ③c 만 끄면 %s 가 샌다 — ③d 가 이 통로를 못 본다", k), as.character(r1_$reason))
    invisible(capture.output(rm_ <- pM$overlay_probe_arm(k, STUB)))
    if (isTRUE(rm_$ok) && identical(fut_of(rm_), "PASS")) ok(sprintf("B7b ③c·③d 없는 probe 는 %s 를 통과시킨다(④ PASS — 값 섭동은 H 만 흔든다 = 정적 층이 하중을 진다)", k)) else
      ng(sprintf("B7b 정적 층 없이도 %s 가 잡힌다 — 전제 재확인", k), as.character(rm_$reason))
  }
} else ng("B7b 돌연변이 앵커", sprintf("'%s' %d건 · '%s' %d건(각 1건이어야 한다)", SC_ANCHOR, length(hitc), AL_ANCHOR, length(hita)))
scope_of <- function(r) { z <- r$checks[r$checks$check == "scope", ]; if (nrow(z)) z$status[1] else "-" }
for (k in c("zz_dyn", "zz_pf")) {
  invisible(capture.output(rs <- pN$overlay_probe_arm(k, STUB)))
  if (!isTRUE(rs$ok) && identical(scope_of(rs), "FAIL") && grepl("호출자 스코프", rs$reason, fixed = TRUE))
    ok(sprintf("B7c 신판 probe 가 %s 를 ③c scope 에서 거부 — %s", k, substr(rs$checks[rs$checks$check == "scope", ]$detail[1], 1, 60))) else
    ng(sprintf("B7c 신판이 %s 를 못 잡는다", k), as.character(rs$reason))
}
# 오탐 경계 — 자기 env 로더(pg2 형태)·지역 DT/.B·H$.M·x.M·주석 언급은 통과 / 프레임 탐색·엔진 원천 이름은 걸린다
NL <- intToUtf8(10L)
fp_cases <- list(
  list(src = "f <- function(H,t,ctx){ e <- new.env(parent = globalenv()); assign('x',1,envir=e); get('x',envir=e); y <<- 2; x.M <- 1; H$.M; 1 }", hit = FALSE),
  list(src = "f <- function(H,t,ctx){ DT <- data.table::data.table(a=1); .B <- 2; DT$a + .B }", hit = FALSE),
  list(src = paste("f <- function(H,t,ctx){ 1 }", "# parent.frame() 과 .M 은 쓰지 않는다", sep = NL), hit = FALSE),
  list(src = "f <- function(H,t,ctx){ sys.function() }", hit = TRUE),
  list(src = "f <- function(H,t,ctx){ .GlobalEnv$a }", hit = TRUE),
  list(src = "f <- function(H,t,ctx){ get('.M')$fwd[t] }", hit = TRUE),
  list(src = "f <- function(H,t,ctx){ nrow(RAWDATA) }", hit = TRUE))
n_ok <- 0L
for (cs in fp_cases) {
  s <- paste(sub("#.*$", "", strsplit(paste0(cs$src, NL), NL, fixed = TRUE)[[1]]), collapse = NL)   # probe 와 같은 주석 걷기
  if ((nrow(pN$overlay_probe_scope_scan(s)) > 0L) == cs$hit) n_ok <- n_ok + 1L else ng("B7d 스캔 경계", cs$src)
}
if (n_ok == length(fp_cases)) ok(sprintf("B7d 스캔 경계 %d종 — 자기 env 로더·지역 DT/.B·H$.M·주석은 통과 · sys.function·.GlobalEnv·get('.M')·RAWDATA 는 걸린다", n_ok))
# 정본 arm 전수(읽기 전용) — ③c 에 걸리는 arm 이 없어야 한다(걸리면 등재 이전 arm 이 통로를 쓴다는 뜻)
RA <- list.files(file.path(ROOT, "02_Infrastructure/reinforcement/overlay_arms"), pattern = "^[A-Za-z].*[.]R$", full.names = TRUE)
rh <- Filter(function(p) nrow(pN$overlay_probe_scope_scan(p)) > 0L, RA)
if (length(RA) && !length(rh)) ok(sprintf("B7e 정본 arm %d종 전부 ③c 0건(현 카탈로그는 통로를 쓰지 않는다)", length(RA))) else
  ng("B7e 정본 arm ③c 검출", if (length(RA)) paste(basename(unlist(rh)), collapse = ",") else "arm 목록 0")

unlink(TD, recursive = TRUE, force = TRUE)
if (!dir.exists(TD)) ok("C 임시 스텁 루트 제거") else ng("C 임시 잔여", TD)
if (exists(".P009_SPY", envir = globalenv())) rm(".P009_SPY", envir = globalenv())
writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
cat(sprintf('{"test":"rf_overlay_pit_mask","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
