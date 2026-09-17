#==============================================================================
# test_rf_engine_overlay_stack.R — rf_cell_engine.R 오버레이 **층 합성** 양방향 검사 (v10.5 2026-09-17)
#
# 왜 (코드 조사로 확인된 결함 넷 — 전부 "합성 결과만 본다" 에서 나왔다):
#   D1 스칼라 층이 벡터 층의 표에 **있는 행만** 곱했다 — 표 밖 보유 종목·빈 표 달·비유한 행은 노출 1 로 끝나
#      스칼라 층의 현금 축소가 조용히 사라졌다.
#   D2 커버리지를 벡터 표들의 합집합에 한 번 재서 실패에 층 이름이 안 남았다('+' 라벨).
#   D3 처치 가드가 합성값만 봐서 항상 1 인 층이 산 층 뒤에 숨어 유령 처치로 통과했다.
#   D4 n_min 이 층 중 최댓값 하나라 한 층의 거동이 이웃 층에 따라 달라졌다.
#
# 재는 것 (양방향 · 합성 픽스처 · 스텁 arm 은 임시 QM_ROOT 에만 — 실제 overlay_arms/ 무접촉):
#   1 스칼라×벡터(부분 표)  — 미지목 보유에도 스칼라 축소가 닿는다        (구판 빨강 · 신판 초록)
#   2 빈 표 달              — 스칼라 축소가 그 달에도 닿는다               (구판 빨강 · 신판 초록)
#   3 죽은 자기 층(항상 1)  — 산 층 위에 얹혀도 층 이름으로 정지           (구판 통과=유령 · 신판 정지)
#     + overlay_cell 로 carry 층은 층별 가드 밖 · 스펙 불일치는 정지
#   4 벡터 층별 커버리지    — 실패 문자열이 **그 층 하나**만 싣는다        (구판 '+' 라벨 · 신판 단일 토큰)
#   5 층별 n_min            — 파일 arm 의 ctx$n_min 은 이웃과 무관하게 자기 것 (구판 48 · 신판 24)
#   6 overlay_shift=1       — 노출 경로 1개월 지연 재현 · 미보유 종목은 스칼라 성분 · 누출 arm 의 t 행 정보가 사라진다
#   7 overlay_strict        — 전 arm 에 ctx$strict 전달
#   8 회귀                  — 단층 스펙 7종의 산출이 기준본(git 985d17aa1)과 비트 동일
#
# ★기준본은 커밋 해시로 고정한다 — HEAD 는 자동 커밋이 몇 분마다 옮기므로 "HEAD 와 같다" 는 곧 자기 자신과의
#   비교가 된다. 블롭 sha(ac084711…)를 함께 대조해 엉뚱한 판본을 기준으로 삼지 않는다.
#   덮어쓰기: QVEST_RF_ENGINE_BASE_REF=<ref>  (기본 985d17aa1)
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_engine_overlay_stack.R
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT   <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ENGINE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R")
writeLines(paste("ROOT =", ROOT))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }

# ── 기준본(구판) 엔진 — git 블롭을 임시 파일로 ────────────────────────────────
BASE_REF <- Sys.getenv("QVEST_RF_ENGINE_BASE_REF", "985d17aa1")
BASE_SHA <- "ac084711c375a024d87dfcdeb7eaf4aa4fec0f26"        # 985d17aa1:02_Infrastructure/reinforcement/rf_cell_engine.R
OLD <- file.path(tempdir(), sprintf("rf_cell_engine_base_%d.R", Sys.getpid()))
.gitq <- function(...) tryCatch(system2("git", c("-C", shQuote(ROOT), ...), stdout = TRUE, stderr = FALSE), error = function(e) character(0))
.sha <- .gitq("rev-parse", paste0(BASE_REF, ":02_Infrastructure/reinforcement/rf_cell_engine.R"))
.st <- tryCatch(system2("git", c("-C", shQuote(ROOT), "show", paste0(BASE_REF, ":02_Infrastructure/reinforcement/rf_cell_engine.R")),
                        stdout = OLD, stderr = FALSE), error = function(e) 1L)
HAVE_OLD <- identical(.st, 0L) && file.exists(OLD) && file.info(OLD)$size > 1000
if (HAVE_OLD && identical(as.character(.sha)[1], BASE_SHA)) ok(sprintf("기준본 확보 — %s 블롭 %s", BASE_REF, substr(BASE_SHA, 1, 9))) else
  ng("기준본 확보", sprintf("git show %s 실패 또는 블롭 불일치(%s) — 구판 대조·회귀 항목은 전부 실패로 센다", BASE_REF, as.character(.sha)[1] %||% "?"))

# ── 합성 픽스처 — 종목 30 · 지수 멤버 20 · 평일 2003-06~2012-12 (시그널일 96) ──
make_fixture <- function(idx_n = 20L) {
  set.seed(20260917L)
  d <- seq(as.Date("2003-06-02"), as.Date("2012-12-31"), by = "day")
  d <- d[as.integer(format(d, "%w")) %in% 1:5]
  x <- CJ(Ticker = sprintf("T%03d", 1:30), Date = d)
  setorder(x, Ticker, Date)
  x[, .r := rnorm(.N, 0.0002, 0.012)]
  x[, Close := 10000 * cumprod(1 + .r), by = Ticker]
  x[, .r := NULL]
  x[, Vol := 2e6]                                  # 유동성 하한(2e8) 을 늘 넘긴다 — 대상은 배관이다
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
# 마지막 달(시그널일 N-1 이후)만 섭동한 BM 두 벌 — 누출 arm 의 t=N-1 행 정보가 미래(익월)에서 오는지 가른다
BM_NEG <- copy(BMF)[Date > SIG[N_SIG - 1L], BM_Ret := -0.03]
BM_POS <- copy(BMF)[Date > SIG[N_SIG - 1L], BM_Ret :=  0.03]

# ── 스텁 루트 — overlay_pit_guard 정본 사본 + 스텁 arm 7종 ───────────────────
STUB <- file.path(tempdir(), sprintf("rf_ovstack_%d", Sys.getpid()))
dir.create(file.path(STUB, "02_Infrastructure/validation"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(STUB, "02_Infrastructure/reinforcement/overlay_arms"), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/validation/overlay_pit_guard.R"),
                    file.path(STUB, "02_Infrastructure/validation/overlay_pit_guard.R"), overwrite = TRUE))
.arm <- function(kind, body) writeLines(body, file.path(STUB, "02_Infrastructure/reinforcement/overlay_arms", paste0(kind, ".R")))
.arm("stub_scal", c(
  "# 살아 있는 스칼라 층(결정론 · 시험 전용) — 짝수 달 0.6 · 홀수 달 0.9",
  "overlay_expo_stub_scal <- function(H, t, ctx) if (t %% 2L == 0L) 0.6 else 0.9"))
.arm("stub_vec90", c(
  "# 보유(정렬)의 앞 90% 에만 e=0.5 — 나머지 10% 는 미지목(그 층 무개입)",
  "overlay_expo_stub_vec90 <- function(H, t, ctx) {",
  "  h <- ctx$hold; if (is.null(h) || !nrow(h)) return(1)",
  "  tk <- sort(unique(as.character(h$Ticker)))",
  "  data.table::data.table(Ticker = tk[seq_len(max(1L, floor(0.9 * length(tk))))], e = 0.5)",
  "}"))
.arm("stub_vec_empty_odd", c(
  "# 홀수 달엔 **빈 표** · 짝수 달엔 보유 전부 e=0.5",
  "overlay_expo_stub_vec_empty_odd <- function(H, t, ctx) {",
  "  h <- ctx$hold; if (is.null(h) || !nrow(h)) return(1)",
  "  if (t %% 2L == 1L) return(data.table::data.table(Ticker = character(0), e = numeric(0)))",
  "  data.table::data.table(Ticker = sort(unique(as.character(h$Ticker))), e = 0.5)",
  "}"))
.arm("stub_one", "overlay_expo_stub_one <- function(H, t, ctx) 1   # 죽은 층 — 항상 1")
.arm("stub_partial", c(
  "# 보유 절반만 e=0.5 — 층별 커버리지 0.50 (< 0.80)",
  "overlay_expo_stub_partial <- function(H, t, ctx) {",
  "  h <- ctx$hold; if (is.null(h) || !nrow(h)) return(1)",
  "  tk <- sort(unique(as.character(h$Ticker)))",
  "  data.table::data.table(Ticker = tk[seq_len(max(1L, floor(length(tk) / 2)))], e = 0.5)",
  "}"))
.arm("stub_spy", c(
  "# ctx 기록기 — n_min · strict 를 전역 .RF_SPY 에 남기고 살아 있는 스칼라를 낸다",
  "overlay_expo_stub_spy <- function(H, t, ctx) {",
  "  rec <- get0('.RF_SPY', envir = globalenv(), ifnotfound = list())",
  "  rec[[length(rec) + 1L]] <- list(t = t, n_min = ctx$n_min, strict = ctx$strict)",
  "  assign('.RF_SPY', rec, envir = globalenv())",
  "  if (t %% 3L == 0L) 0.7 else 1",
  "}"))
.arm("stub_leak", c(
  "# ★시험 전용 위반 주입 — H$fwd[t] 는 t 행에서 아직 실현되지 않은 익월 수익이다(미래참조).",
  "#   실제 overlay_arms/ 에 절대 두지 말 것. 여기서는 overlay_shift 가 이 정보를 지우는지 재는 표적이다.",
  "overlay_expo_stub_leak <- function(H, t, ctx) { f <- H$fwd[t]; if (is.finite(f) && f < 0) 0.3 else 1 }"))

AXES <- list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150",
             start_date = "2005-01-01", commission_bps = 15L, liq_adv20_min = 2e8)
base_spec <- function(...) modifyList(list(
  code = "OVST", label = "overlay stack", block = "T", fixed_axes = AXES,
  base_signal = list(kind = "mom_12_1"), weighting = list(kind = "ew"),
  universe = list(kind = "k200_kq150"), factor2 = list(kind = "none")), list(...))
L_SCAL  <- list(kind = "stub_scal",          arm_id = "stub_scal_x")
L_VEC90 <- list(kind = "stub_vec90",         arm_id = "stub_vec90_x")
L_VEMP  <- list(kind = "stub_vec_empty_odd", arm_id = "stub_vec_empty_odd_x")
L_ONE   <- list(kind = "stub_one",           arm_id = "stub_one_x")
L_PART  <- list(kind = "stub_partial",       arm_id = "stub_partial_x")
L_SPY   <- list(kind = "stub_spy",           arm_id = "stub_spy_x")
L_LEAK  <- list(kind = "stub_leak",          arm_id = "stub_leak_x")
L_HAR   <- list(kind = "har_vol",            arm_id = "har_vol_q")

# 엔진을 격리 env 에서 평가한다 — QM_ROOT 는 실행 동안만 지정 루트(스텁·정본)로 돌린다.
run_cell <- function(spec, engine = ENGINE, fixture = FIX, bm = BMF, root = STUB) {
  p <- file.path(tempdir(), sprintf("rf_ovstack_spec_%d.json", Sys.getpid()))
  writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), p)
  old_root <- Sys.getenv("QM_ROOT", unset = NA); old_spec <- Sys.getenv("RF_CELL_SPEC", unset = NA)
  Sys.setenv(RF_CELL_SPEC = p, QM_ROOT = root)
  on.exit({ if (is.na(old_root)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = old_root)
            if (is.na(old_spec)) Sys.unsetenv("RF_CELL_SPEC") else Sys.setenv(RF_CELL_SPEC = old_spec) }, add = TRUE)
  env <- new.env()
  assign("RAWDATA", copy(fixture), envir = env)
  assign("BM_DT", bm, envir = env)
  err <- NULL
  lg <- utils::capture.output(suppressWarnings(suppressMessages(
    tryCatch(source(engine, local = env), error = function(e) err <<- conditionMessage(e)))))
  list(err = err, log = lg,
       port = if (exists("PORTFOLIO", envir = env, inherits = FALSE))
                as.data.table(get("PORTFOLIO", envir = env))[order(Date, Ticker)] else NULL,
       fac  = if (exists("FACTORS", envir = env, inherits = FALSE))
                as.data.table(get("FACTORS", envir = env))[order(Date, Ticker)] else NULL)
}
# 보유 종목 = 오버레이 없는 EW 기저(FACTORS 의 (Date,Ticker)). N_d 로 비중을 노출(oe)로 되돌린다.
held_of <- function(r) { h <- r$fac[, .(Date, Ticker)]; h[, N := .N, by = Date]; h[, t := match(Date, SIG)]; h }
oe_of <- function(r, held) {                       # (Date,Ticker,t,oe) — 0 비중으로 빠진 행 = 0
  z <- merge(held, r$port[, .(Date, Ticker, Weight)], by = c("Date", "Ticker"), all.x = TRUE)
  z[is.na(Weight), Weight := 0]; z[, oe := Weight * N]; z[order(Date, Ticker), .(Date, Ticker, t, oe)]
}
scal_of <- function(r, held) oe_of(r, held)[, .(oe = oe[1]), by = .(Date, t)][order(t)]   # 스칼라 층 = 날짜당 한 값
TOL <- 1e-12
maxdiff <- function(a, b) max(abs(a - b))

writeLines("=== 0. 기저 보유 ===")
r0 <- run_cell(base_spec())
if (is.null(r0$err) && !is.null(r0$fac)) { HELD <- held_of(r0); ok(sprintf("0 오버레이 없음 → FACTORS %d행 · 시그널일 %d · 일별 보유 %s종",
                                             nrow(r0$fac), N_SIG, paste(unique(HELD$N), collapse = "/"))) } else { ng("0 기저", r0$err %||% "산출 없음"); quit(status = 1L) }
rS <- run_cell(base_spec(overlay = L_SCAL));  rV <- run_cell(base_spec(overlay = L_VEC90))
if (is.null(rS$err) && is.null(rV$err)) ok("0 단층 스칼라·벡터 스텁 각각 실행") else { ng("0 단층 스텁", paste(rS$err, rV$err)); quit(status = 1L) }
S  <- scal_of(rS, HELD); V <- oe_of(rV, HELD)
if (any(S[t >= 12L]$oe < 1 - 1e-9) && any(V[t >= 12L]$oe < 1 - 1e-9) && any(V[t >= 12L]$oe > 1 - 1e-9))
  ok("0 전제 — 스칼라 층은 개입하고 벡터 층은 보유의 일부만 지목한다(미지목 보유가 존재)") else ng("0 전제", "스텁이 가르는 상태를 못 만든다")

writeLines("=== 1. 스칼라×벡터(부분 표) — 미지목 보유에도 스칼라 축소가 닿는가 ===")
rSV <- run_cell(base_spec(overlay = list(L_SCAL, L_VEC90)))
if (is.null(rSV$err) && !is.null(rSV$port)) {
  SV <- oe_of(rSV, HELD); X <- merge(merge(SV, V[, .(Date, Ticker, v = oe)], by = c("Date", "Ticker")), S[, .(Date, s = oe)], by = "Date")
  un <- X[t >= 12L & v > 1 - 1e-9]; li <- X[t >= 12L & v < 1 - 1e-9]
  if (nrow(un) && maxdiff(un$oe, un$s) < TOL) ok(sprintf("1a 미지목 보유 %d행 — 노출 = 스칼라 층 값 (최대 오차 %.1e)", nrow(un), maxdiff(un$oe, un$s))) else
    ng("1a 미지목 보유가 스칼라 축소를 안 받는다", sprintf("행 %d · 최대 오차 %.3e", nrow(un), if (nrow(un)) maxdiff(un$oe, un$s) else NA))
  if (nrow(li) && maxdiff(li$oe, li$s * li$v) < TOL) ok(sprintf("1b 지목 보유 %d행 — 노출 = 스칼라 × 벡터 (층별 축소 후 곱)", nrow(li))) else
    ng("1b 지목 보유의 곱 합성", sprintf("최대 오차 %.3e", if (nrow(li)) maxdiff(li$oe, li$s * li$v) else NA))
  sm <- rSV$port[, .(s = sum(Weight)), by = Date]$s
  if (max(sm) <= 1 + 1e-8 && all(rSV$port$Weight >= 0)) ok("1c 고정 축 — Σw ≤ 1 · 롱온리") else ng("1c 고정 축 위반", sprintf("Σw 최대 %.6f", max(sm)))
} else ng("1 스칼라×벡터 실행", rSV$err %||% "PORTFOLIO 없음")
if (HAVE_OLD) {
  rSVo <- run_cell(base_spec(overlay = list(L_SCAL, L_VEC90)), engine = OLD)
  if (is.null(rSVo$err) && !is.null(rSVo$port)) {
    SVo <- oe_of(rSVo, HELD); Xo <- merge(merge(SVo, V[, .(Date, Ticker, v = oe)], by = c("Date", "Ticker")), S[, .(Date, s = oe)], by = "Date")
    uno <- Xo[t >= 12L & v > 1 - 1e-9]
    if (nrow(uno) && maxdiff(uno$oe, uno$s) > 1e-6 && all(abs(uno$oe - 1) < 1e-9))
      ok(sprintf("1d 구판 빨강 — 같은 스펙에서 미지목 보유 %d행의 노출이 전부 1 (스칼라 축소 소실 = D1 재현)", nrow(uno))) else
      ng("1d 구판이 이 결함을 보이지 않는다", "검사가 방어선이 아니다")
  } else ng("1d 구판 실행", rSVo$err %||% "PORTFOLIO 없음")
}

writeLines("=== 2. 빈 표 달 — 스칼라 축소가 그 달에도 닿는가 ===")
rVE <- run_cell(base_spec(overlay = L_VEMP)); rSE <- run_cell(base_spec(overlay = list(L_SCAL, L_VEMP)))
if (is.null(rVE$err) && is.null(rSE$err) && !is.null(rSE$port)) {
  VE <- oe_of(rVE, HELD); SE <- oe_of(rSE, HELD)
  X <- merge(merge(SE, VE[, .(Date, Ticker, v = oe)], by = c("Date", "Ticker")), S[, .(Date, s = oe)], by = "Date")
  em <- X[t >= 12L & t %% 2L == 1L]; fm <- X[t >= 12L & t %% 2L == 0L]
  if (nrow(em) && maxdiff(em$oe, em$s) < TOL && all(abs(em$v - 1) < 1e-9))
    ok(sprintf("2a 빈 표 달 %d행 — 벡터 층 무개입(1)이고 노출 = 스칼라 층 값", nrow(em))) else
    ng("2a 빈 표 달에서 스칼라 축소 소실", sprintf("최대 오차 %.3e", if (nrow(em)) maxdiff(em$oe, em$s) else NA))
  if (nrow(fm) && maxdiff(fm$oe, fm$s * fm$v) < TOL) ok(sprintf("2b 표 있는 달 %d행 — 곱 합성", nrow(fm))) else ng("2b 표 있는 달 곱 합성", "")
} else ng("2 빈 표 실행", paste(rVE$err %||% "", rSE$err %||% ""))
if (HAVE_OLD) {
  rSEo <- run_cell(base_spec(overlay = list(L_SCAL, L_VEMP)), engine = OLD)
  if (is.null(rSEo$err) && !is.null(rSEo$port)) {
    SEo <- oe_of(rSEo, HELD); emo <- merge(SEo[t >= 12L & t %% 2L == 1L], S[, .(Date, s = oe)], by = "Date")
    if (nrow(emo) && all(abs(emo$oe - 1) < 1e-9) && any(emo$s < 1 - 1e-6))
      ok(sprintf("2c 구판 빨강 — 빈 표 달 %d행의 노출이 전부 1 (스칼라 층이 0.6/0.9 인데도)", nrow(emo))) else
      ng("2c 구판이 이 결함을 보이지 않는다", "검사가 방어선이 아니다")
  } else ng("2c 구판 실행", rSEo$err %||% "PORTFOLIO 없음")
}

writeLines("=== 3. 죽은 자기 층(항상 1) — 산 층 위에 얹혀도 층 이름으로 정지 ===")
MSG_ONE <- "[rf_cell_engine] overlay 층 stub_one_x 처치 미전달(항상 1) — 측정 무효"
r3 <- run_cell(base_spec(overlay = list(L_SCAL, L_ONE)))
if (!is.null(r3$err) && identical(r3$err, MSG_ONE)) ok("3a 정지 문자열이 정확히 계약과 같다(층 이름 = arm_id · 단일 토큰)") else
  ng("3a 죽은 층이 산 층 뒤에 숨는다(유령 처치)", r3$err %||% "오류 없음")
if (!is.null(r3$err) && grepl("측정 무효|처치 미전달", r3$err)) ok("3b 러너의 결정론 실패 패턴(측정 무효|처치 미전달)에 걸린다") else ng("3b 러너 패턴 불일치", r3$err %||% "")
r3s <- run_cell(base_spec(overlay = L_ONE))
if (!is.null(r3s$err) && identical(r3s$err, MSG_ONE)) ok("3c 단층이어도 같은 층별 문자열") else ng("3c 단층 죽은 층", r3s$err %||% "오류 없음")
r3c <- run_cell(base_spec(overlay = list(L_ONE, L_SCAL), overlay_cell = list(L_SCAL)))
if (is.null(r3c$err) && !is.null(r3c$port) && identical(r3c$port$Weight, rS$port$Weight))
  ok("3d overlay_cell — 죽은 층이 carry 면 층별 가드 밖 · 산출은 스칼라 단층과 비트 동일(1 을 곱한 것)") else
  ng("3d overlay_cell 자기 층 한정이 안 된다", r3c$err %||% "산출 불일치")
r3m <- run_cell(base_spec(overlay = list(L_SCAL), overlay_cell = list(L_ONE)))
if (!is.null(r3m$err) && grepl("overlay_cell", r3m$err, fixed = TRUE) && grepl("스펙 불일치", r3m$err, fixed = TRUE))
  ok("3e overlay_cell 의 층이 overlay 에 없으면 스펙 불일치로 정지(자기 층 없이 판정 안 함)") else ng("3e 스펙 불일치 미검출", r3m$err %||% "오류 없음")
if (HAVE_OLD) {
  r3o <- run_cell(base_spec(overlay = list(L_SCAL, L_ONE)), engine = OLD)
  if (is.null(r3o$err) && !is.null(r3o$port)) ok("3f 구판 빨강 — 같은 스펙이 PORTFOLIO 를 내며 통과(항상 1 층이 유령 처치로 측정됨 = D3 재현)") else
    ng("3f 구판이 이 결함을 보이지 않는다", r3o$err %||% "")
}

writeLines("=== 4. 벡터 층별 커버리지 — 실패 문자열이 그 층 하나만 싣는다 ===")
RE_COV <- "^\\[rf_cell_engine\\] overlay stub_partial_x 종목 커버리지 0\\.50 < 0\\.80 \\[basis=held_rows\\] — arm 이 보유를 못 덮었다\\.$"
r4 <- run_cell(base_spec(overlay = list(L_SCAL, L_PART)))
if (!is.null(r4$err) && grepl(RE_COV, r4$err)) ok("4a 스칼라+부분벡터 → 부분벡터 층의 arm_id 만 실린 계약 문자열(0.50 · basis=held_rows)") else
  ng("4a 커버리지 문자열", r4$err %||% "오류 없음")
if (!is.null(r4$err) && !grepl("+", r4$err, fixed = TRUE) && !grepl("stub_scal", r4$err, fixed = TRUE)) ok("4b '+' 결합 없음 · 이웃 층 이름 없음") else ng("4b 이웃 층이 문자열에 섞인다", r4$err %||% "")
r4v <- run_cell(base_spec(overlay = list(L_VEC90, L_PART)))
if (!is.null(r4v$err) && grepl(RE_COV, r4v$err)) ok("4c 벡터 두 층 중 못 덮은 층(stub_partial_x)만 지목 — vec90(0.90) 은 통과") else ng("4c 두 벡터 층 귀속", r4v$err %||% "오류 없음")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))
pc <- if (is.null(r4$err)) NULL else rac_parse_coverage(r4$err)
if (!is.null(pc) && identical(pc$basis, "held_rows") && identical(pc$kind, "overlay") && identical(pc$id, "stub_partial_x"))
  ok("4d 장부 파서 rac_parse_coverage → basis=held_rows · overlay · id=stub_partial_x") else ng("4d 장부 파서", if (is.null(pc)) "오류 없음" else paste(pc$basis, pc$kind, pc$id))
if (HAVE_OLD) {
  r4o <- run_cell(base_spec(overlay = list(L_SCAL, L_PART)), engine = OLD)
  if (!is.null(r4o$err) && grepl("stub_scal+stub_partial", r4o$err, fixed = TRUE)) ok("4e 구판 빨강 — 같은 스펙의 실패 문자열이 '+' 라벨(stub_scal+stub_partial)을 싣는다(D2 재현)") else
    ng("4e 구판 문자열", r4o$err %||% "오류 없음")
}

writeLines("=== 5. 층별 n_min — 파일 arm 의 ctx$n_min 은 이웃과 무관하게 자기 것 ===")
spy_nmin <- function(r) { z <- get0(".RF_SPY", envir = globalenv(), ifnotfound = list()); unique(vapply(z, function(q) as.integer(q$n_min %||% NA_integer_), integer(1))) }
assign(".RF_SPY", list(), envir = globalenv()); r5s <- run_cell(base_spec(overlay = L_SPY)); n5s <- spy_nmin(r5s)
assign(".RF_SPY", list(), envir = globalenv()); r5  <- run_cell(base_spec(overlay = list(L_HAR, L_SPY), overlay_cell = list(L_SPY))); n5 <- spy_nmin(r5)
if (is.null(r5s$err) && identical(n5s, 24L)) ok("5a 단독 스텁 → ctx$n_min 24") else ng("5a 단독 n_min", paste(r5s$err %||% "", paste(n5s, collapse = ",")))
if (is.null(r5$err) && identical(n5, 24L)) ok("5b har_vol(48) 옆에서도 스텁의 ctx$n_min 은 24 — 이웃 무관") else ng("5b 이웃이 n_min 을 바꾼다", paste(r5$err %||% "", paste(n5, collapse = ",")))
if (HAVE_OLD) {
  assign(".RF_SPY", list(), envir = globalenv()); r5o <- run_cell(base_spec(overlay = list(L_HAR, L_SPY)), engine = OLD); n5o <- spy_nmin(r5o)
  if (identical(n5o, 48L)) ok("5c 구판 빨강 — 같은 스펙에서 스텁이 48 을 받는다(층 중 최댓값 = D4 재현)") else ng("5c 구판 n_min", paste(r5o$err %||% "", paste(n5o, collapse = ",")))
}

writeLines("=== 6. overlay_shift=1 — 노출 경로 지연 · 미보유 종목의 스칼라 성분 · 누출 정보 소거 ===")
rSs <- run_cell(base_spec(overlay = L_SCAL, overlay_shift = 1L))
if (is.null(rSs$err) && !is.null(rSs$port)) {
  Ss <- scal_of(rSs, HELD); S0 <- S
  lag_ok <- maxdiff(Ss[t >= 2L]$oe, S0[t <= N_SIG - 1L]$oe) < 1e-9 && abs(Ss[t == 1L]$oe - 1) < 1e-9
  if (lag_ok) ok("6a 스칼라 경로 — shift 판 t 의 노출 = 무shift 판 t−1 의 노출 · 첫 달 1") else ng("6a 지연 경로 불일치", sprintf("최대 오차 %.3e", maxdiff(Ss[t >= 2L]$oe, S0[t <= N_SIG - 1L]$oe)))
  if (any(grepl("적대검증 옵션 ON", rSs$log, fixed = TRUE)) && any(grepl("overlay_shift=1 적용", rSs$log, fixed = TRUE))) ok("6b 옵션 ON 로그 줄이 남는다") else ng("6b 로그 부재", "")
} else ng("6a shift 실행", rSs$err %||% "PORTFOLIO 없음")
if (HAVE_OLD) {
  rSso <- run_cell(base_spec(overlay = L_SCAL, overlay_shift = 1L), engine = OLD)
  if (is.null(rSso$err) && identical(rSso$port$Weight, rS$port$Weight)) ok("6c 구판 빨강 — overlay_shift 를 무시해 무shift 판과 비트 동일(옵션이 없던 판)") else ng("6c 구판 shift", rSso$err %||% "산출 상이")
}
# 보유 회전 판(n_max 10) — t−1 에 없던 종목이 실제로 생겨 스칼라 성분 분기가 발화한다
AX10 <- modifyList(AXES, list(n_max = 10L))
r10 <- run_cell(base_spec(fixed_axes = AX10)); H10 <- held_of(r10)
r10S <- run_cell(base_spec(fixed_axes = AX10, overlay = L_SCAL))
r10SV <- run_cell(base_spec(fixed_axes = AX10, overlay = list(L_SCAL, L_VEC90)))
r10SVs <- run_cell(base_spec(fixed_axes = AX10, overlay = list(L_SCAL, L_VEC90), overlay_shift = 1L))
if (is.null(r10$err) && is.null(r10S$err) && is.null(r10SV$err) && is.null(r10SVs$err)) {
  S10 <- scal_of(r10S, H10); SV10 <- oe_of(r10SV, H10); SV10s <- oe_of(r10SVs, H10)
  prev <- SV10[, .(Date, Ticker, tp = t + 1L, oe_prev = oe)]                      # t−1 의 종목별 노출을 t 로 끌어온다
  X <- merge(SV10s, prev[, .(Ticker, t = tp, oe_prev)], by = c("Ticker", "t"), all.x = TRUE)
  X <- merge(X, S10[, .(t = t + 1L, s_prev = oe)], by = "t", all.x = TRUE)          # t−1 의 스칼라 성분
  X[, expect := fifelse(t == 1L, 1, fifelse(!is.na(oe_prev), oe_prev, s_prev))]
  n_new <- sum(X$t >= 12L & is.na(X$oe_prev))
  if (n_new > 0L && maxdiff(X$oe, X$expect) < 1e-9)
    ok(sprintf("6d 종목별 경로 — 양쪽 보유 종목은 t−1 의 그 종목 값 · t−1 미보유 %d행은 t−1 의 스칼라 성분 · 첫 달 1", n_new)) else
    ng("6d 종목별 shift 경로", sprintf("미보유 분기 %d행 · 최대 오차 %.3e", n_new, maxdiff(X$oe, X$expect)))
} else ng("6d 회전 판 실행", paste(r10$err, r10S$err, r10SV$err, r10SVs$err))
# 누출 arm: t 행의 fwd(익월 수익)를 읽는다. 무shift 판은 마지막 달 섭동에 t=N−1 노출이 흔들리고, shift 판은 흔들리지 않는다.
rLn <- run_cell(base_spec(overlay = L_LEAK), bm = BM_NEG); rLp <- run_cell(base_spec(overlay = L_LEAK), bm = BM_POS)
rLns <- run_cell(base_spec(overlay = L_LEAK, overlay_shift = 1L), bm = BM_NEG); rLps <- run_cell(base_spec(overlay = L_LEAK, overlay_shift = 1L), bm = BM_POS)
if (is.null(rLn$err) && is.null(rLp$err) && is.null(rLns$err) && is.null(rLps$err)) {
  Ln <- scal_of(rLn, HELD); Lp <- scal_of(rLp, HELD); Lns <- scal_of(rLns, HELD); Lps <- scal_of(rLps, HELD)
  leak_seen <- abs(Ln[t == N_SIG - 1L]$oe - Lp[t == N_SIG - 1L]$oe) > 0.5
  if (leak_seen) ok(sprintf("6e 무shift 판 — 마지막 달 섭동만으로 t=N−1 노출이 %.2f→%.2f (t 행이 익월 정보를 쓴다 = 누출 가시화)", Ln[t == N_SIG - 1L]$oe, Lp[t == N_SIG - 1L]$oe)) else
    ng("6e 누출 표적이 안 보인다", "스텁이 fwd 를 못 읽었다")
  if (maxdiff(Lns[t <= N_SIG - 1L]$oe, Lps[t <= N_SIG - 1L]$oe) < 1e-12 && abs(Lns[t == N_SIG]$oe - Lps[t == N_SIG]$oe) > 0.5)
    ok("6f shift=1 판 — t ≤ N−1 의 노출은 섭동에 불변(익월 정보 소거) · t=N 만 t−1 의 실현값을 따라 움직인다") else
    ng("6f shift 판이 익월 정보를 지우지 못한다", sprintf("최대 차 %.3e", maxdiff(Lns[t <= N_SIG - 1L]$oe, Lps[t <= N_SIG - 1L]$oe)))
} else ng("6e/6f 누출 판 실행", paste(rLn$err, rLp$err, rLns$err, rLps$err))
r6x <- run_cell(base_spec(overlay = L_SCAL, overlay_shift = -1L))
if (!is.null(r6x$err) && grepl("overlay_shift", r6x$err, fixed = TRUE)) ok("6g 음수 shift 는 거부") else ng("6g 음수 shift 통과", r6x$err %||% "")

writeLines("=== 7. overlay_strict — 전 arm 에 ctx$strict 전달 ===")
spy_strict <- function() { z <- get0(".RF_SPY", envir = globalenv(), ifnotfound = list()); unique(vapply(z, function(q) if (is.null(q$strict)) "NULL" else as.character(q$strict), character(1))) }
assign(".RF_SPY", list(), envir = globalenv()); r7t <- run_cell(base_spec(overlay = L_SPY, overlay_strict = TRUE)); s7t <- spy_strict()
assign(".RF_SPY", list(), envir = globalenv()); r7f <- run_cell(base_spec(overlay = L_SPY)); s7f <- spy_strict()
if (is.null(r7t$err) && identical(s7t, "TRUE")) ok("7a overlay_strict=TRUE → 전 호출 ctx$strict TRUE") else ng("7a strict 전달", paste(r7t$err %||% "", paste(s7t, collapse = ",")))
if (is.null(r7f$err) && identical(s7f, "FALSE")) ok("7b 미지정 → ctx$strict FALSE(기본 OFF)") else ng("7b strict 기본값", paste(r7f$err %||% "", paste(s7f, collapse = ",")))
if (any(grepl("적대검증 옵션 ON", r7t$log, fixed = TRUE)) && !any(grepl("적대검증 옵션 ON", r7f$log, fixed = TRUE))) ok("7c 옵션 ON 로그는 켰을 때만") else ng("7c strict 로그", "")
if (is.null(r7t$err) && is.null(r7f$err) && identical(r7t$port$Weight, r7f$port$Weight)) ok("7d strict 를 안 읽는 arm 은 산출 비트 동일(옵션은 전달일 뿐 측정을 바꾸지 않는다)") else ng("7d strict 부작용", "")
if (HAVE_OLD) {
  assign(".RF_SPY", list(), envir = globalenv()); r7o <- run_cell(base_spec(overlay = L_SPY, overlay_strict = TRUE), engine = OLD); s7o <- spy_strict()
  if (identical(s7o, "NULL")) ok("7e 구판 빨강 — ctx 에 strict 가 없다(NULL)") else ng("7e 구판 strict", paste(s7o, collapse = ","))
}

writeLines("=== 8. 회귀 — 단층 스펙의 산출이 기준본과 비트 동일 ===")
same_port <- function(a, b) !is.null(a) && !is.null(b) && identical(a$Date, b$Date) && identical(a$Ticker, b$Ticker) && identical(a$Weight, b$Weight)
if (HAVE_OLD) {
  REG <- list(
    list(nm = "no overlay(FACTORS)",      spec = base_spec(),                                              root = STUB),
    list(nm = "dd_brake(빌트인 스칼라)",   spec = base_spec(overlay = list(kind = "dd_brake", arm_id = "dd_brake_q")),   root = STUB),
    list(nm = "vol_scale(빌트인 스칼라)",  spec = base_spec(overlay = list(kind = "vol_scale")),                         root = STUB),
    list(nm = "dbeta_tilt(정본 벡터 arm)", spec = base_spec(overlay = list(kind = "dbeta_tilt", arm_id = "dbeta_tilt_rank")), root = ROOT),
    list(nm = "stub_vec90(파일 벡터 arm)", spec = base_spec(overlay = L_VEC90),                                          root = STUB),
    list(nm = "stub_scal(파일 스칼라 arm)", spec = base_spec(overlay = L_SCAL),                                          root = STUB),
    list(nm = "inv_vol × dd_brake(PORTFOLIO 기저)", spec = base_spec(weighting = list(kind = "inv_vol", window = 60L),
                                                                     overlay = list(kind = "dd_brake", arm_id = "dd_brake_q")), root = STUB))
  for (g in REG) {
    a <- run_cell(g$spec, root = g$root); b <- run_cell(g$spec, engine = OLD, root = g$root)
    if (!is.null(a$err) || !is.null(b$err)) { ng(sprintf("8 %s 실행", g$nm), sprintf("신 %s / 구 %s", a$err %||% "-", b$err %||% "-")); next }
    if (!is.null(a$fac) && is.null(a$port)) {
      if (!is.null(b$fac) && identical(a$fac$Date, b$fac$Date) && identical(a$fac$Ticker, b$fac$Ticker) && identical(a$fac$Score, b$fac$Score))
        ok(sprintf("8 %s — FACTORS %d행 비트 동일", g$nm, nrow(a$fac))) else ng(sprintf("8 %s FACTORS 상이", g$nm))
    } else if (same_port(a$port, b$port)) ok(sprintf("8 %s — PORTFOLIO %d행 비트 동일", g$nm, nrow(a$port))) else
      ng(sprintf("8 %s PORTFOLIO 상이", g$nm), sprintf("신 %d행 / 구 %d행", nrow(a$port %||% data.table()), nrow(b$port %||% data.table())))
  }
} else ng("8 회귀", "기준본 없음")

unlink(STUB, recursive = TRUE, force = TRUE); unlink(OLD, force = TRUE)
writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL))
cat(sprintf('{"test":"rf_engine_overlay_stack","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
