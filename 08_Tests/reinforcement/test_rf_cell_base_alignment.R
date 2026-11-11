#!/usr/bin/env Rscript
#==============================================================================
# test_rf_cell_base_alignment.R — 셀 엔진의 기저 신호 정합(판 2 구축 S1 · 2026-11-11) 종단 검사
#
# 무엇을 재는가 (대상 = rf_cell_engine.R 의 .load_one + rf_base_align.R + rf_base_cache.R):
#   A  월말 격자 기저 엔진 = 수정 전후 FACTORS 비트 동일(구판 엔진 git blob 과 대조) — 채택 조건
#   B  60거래일 격자 = 달마다 그 달의 마지막 신호가 월말로 온다(s ≤ d · 직전 월말 뒤) · 구판은 월말과 겹치는 날만 읽었다(결함 재현)
#   C  주간 격자 = 달마다 신호 하나(그 달의 마지막 주간 신호)
#   D  측정 시작일 전달 — 기저 엔진이 .RP_START_DATE 를 받는다(러너 값이 있으면 그 값 · 없으면 칸 고정 축 시작일) · 구판은 안 넘겼다
#   E  캐시 — 판 v3 · 파일 접두 base_v3_ · 캐시에는 엔진 원산출(스냅 전) · 키의 시작일 = 엔진에 넘긴 값 · 적중 산출 == 미스 산출
#   F  진단 — rf_engine_diag.json 의 base_alignment(규칙 · 신호일 수 · 시작일 · 캐시 적중 여부)
#   G  스냅 뒤 빈 패널 = 멈춘다 · 기저가 mom_12_1 인 칸은 달 스냅 파일을 적재하지 않는다(격리 루트에 없어도 돈다)
#
# 양방향: 구판 엔진(git blob d1555fa0 = 수리 직전)을 같은 절차에 걸어 B · D 가 구판에서 red 임을 보인다(검사가 결함을 잡는다).
# 부작용 없음: 픽스처 · 스펙 · 격리 루트 전부 tempdir. 실자료 · 성과 · 원장 무접촉.
# 실행: Rscript 08_Tests/reinforcement/test_rf_cell_base_alignment.R
#   교체 전 후보판 검사: RF_TEST_REINF_DIR=<후보판 폴더> (그 폴더에 있는 파일이 운영 파일을 대신한다)
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
LIVE <- file.path(ROOT, "02_Infrastructure/reinforcement")
CAND <- Sys.getenv("RF_TEST_REINF_DIR", "")
pick <- function(f) if (nzchar(CAND) && file.exists(file.path(CAND, f))) file.path(CAND, f) else file.path(LIVE, f)
ENGINE <- pick("rf_cell_engine.R")
LEGACY_BLOB <- "d1555fa06952acd6ac842075ae538e82c48471a0"   # 526d72f12:02_Infrastructure/reinforcement/rf_cell_engine.R (달 스냅 · 시작일 주입 전)

PASS <- 0L; FAIL <- 0L; SKIPS <- list()
ok   <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng   <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, "—", d)) }
skip <- function(axis, reason) { SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason); writeLines(paste("  SKIP ", axis, "—", reason)) }
chk  <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
emit <- function() cat(sprintf('{"test":"rf_cell_base_alignment","pass":%d,"fail":%d,"skipped":%d,"total":%d}\n',
                               PASS, FAIL, length(SKIPS), PASS + FAIL))

if (!file.exists(ENGINE)) { ng("전제", paste("엔진 부재:", ENGINE)); emit(); quit(status = 1L) }
writeLines(sprintf("대상 엔진 = %s%s", ENGINE, if (nzchar(CAND)) " (후보판)" else ""))

TMP <- file.path(tempdir(), sprintf("rfbal_%d", Sys.getpid()))
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)

# 격리 루트 — 엔진이 .RF_ROOT 에서 읽는 도장 파일 + source 하는 형제 파일만.
SIBS <- c("rf_rebalance.R", "rf_sleeve.R", "rf_axes.R", "rf_base_cache.R", "rf_base_align.R")
make_root <- function(tag, sibs = SIBS) {
  r <- file.path(TMP, tag)
  dir.create(file.path(r, ".cache", "factor_db"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "02_Infrastructure", "reinforcement"), recursive = TRUE, showWarnings = FALSE)
  for (f in sibs) file.copy(pick(f), file.path(r, "02_Infrastructure/reinforcement", f), overwrite = TRUE)
  writeBin(as.raw(rep(1L, 1000L)), file.path(r, ".cache", "rawdata.parquet"))
  writeBin(as.raw(rep(2L, 300L)),  file.path(r, ".cache", "benchmark.parquet"))
  writeLines("20261111000000_aaaaaaa", file.path(r, ".cache", "factor_db", "build_hash.txt"))
  r
}

# 픽스처 — 종목 45(지수 멤버 40 > n_max 25) · 평일 2003-06 ~ 2008-12
set.seed(20261111L)
.d <- seq(as.Date("2003-06-02"), as.Date("2008-12-31"), by = "day")
.d <- .d[as.integer(format(.d, "%w")) %in% 1:5]
FIX <- CJ(Ticker = sprintf("T%03d", 1:45), Date = .d)
setorder(FIX, Ticker, Date)
FIX[, .r := rnorm(.N, 0.0003, 0.012)]
FIX[, Close := 10000 * cumprod(1 + .r), by = Ticker][, .r := NULL]
FIX[, Vol := 200000][, Size := Close * 1e6]
FIX[, K200 := as.integer(sub("T", "", Ticker, fixed = TRUE)) <= 40L][, KQ150 := FALSE]
FIX[, Sector_Lv2 := paste0("S", (as.integer(sub("T", "", Ticker, fixed = TRUE)) %% 5L) + 1L)]
BMF <- FIX[, .(BM_Ret = mean(Close / shift(Close) - 1, na.rm = TRUE)), by = Date]
CAL <- sort(unique(FIX$Date))
ME  <- CAL[!duplicated(format(CAL, "%Y%m"), fromLast = TRUE)]            # 월말 거래일(마지막 부분월 포함)
SPEC_START <- as.Date("2005-01-01")
SIG <- ME[ME >= SPEC_START]                                              # 셀의 시그널일

# ── 합성 기저 엔진 ─────────────────────────────────────────────────────────
#   점수 = 신호일 번호 × 1000 + 종목 번호 → 셀 패널의 .base_sig 에서 '어느 신호일의 값인가'를 되읽을 수 있다.
#   RF_BAL_STARTFILE 이 있으면 받은 .RP_START_DATE 를 적는다(못 받으면 MISSING).
eng_head <- c(
  "sf <- Sys.getenv('RF_BAL_STARTFILE')",
  "st <- if (exists('.RP_START_DATE')) as.Date(.RP_START_DATE) else as.Date(NA)",
  "if (nzchar(sf)) writeLines(if (is.na(st)) 'MISSING' else format(st), sf)",
  "cal <- sort(unique(RAWDATA$Date))",
  "mk <- function(dates) { x <- RAWDATA[Date %in% dates, .(Date, Ticker)]",
  "  x[, Score := as.numeric(as.integer(Date)) * 1000 + as.integer(sub('T', '', Ticker, fixed = TRUE))]; x[] }")
write_engine <- function(name, body) {
  d <- file.path(TMP, name); dir.create(d, showWarnings = FALSE)
  p <- file.path(d, "engine.R"); writeLines(c(eng_head, body), p); p
}
E_ME <- write_engine("ENG_ME", c(                                       # 월말 격자 — 시작일을 읽지 않는다
  "me <- cal[!duplicated(format(cal, '%Y%m'), fromLast = TRUE)]",
  "FACTORS <- mk(me[me >= as.Date('2004-06-01')])"))
E_60 <- write_engine("ENG_60", c(                                       # 60거래일 격자 — 기준점 = 받은 시작일(없으면 2004-06-01) 이상 첫 거래일
  "s0 <- if (is.na(st)) as.Date('2004-06-01') else st",
  "g <- cal[cal >= s0]; g <- g[seq(1L, length(g), by = 60L)]",
  "FACTORS <- mk(g)"))
E_WK <- write_engine("ENG_WK", c(                                       # 주간 격자 — 주마다 마지막 거래일
  "wk <- cal[!duplicated(format(cal, '%G%V'), fromLast = TRUE)]",
  "FACTORS <- mk(wk[wk >= as.Date('2004-06-01')])"))
E_LATE <- write_engine("ENG_LATE", "FACTORS <- data.table::data.table(Date = max(cal) + 30L, Ticker = sprintf('T%03d', 1:45), Score = 1)")
E_PF <- write_engine("ENG_PF", c(                                       # 포트폴리오만 내는 엔진(FACTORS 없음) — 비중이 점수로 읽힌다
  "me <- cal[!duplicated(format(cal, '%Y%m'), fromLast = TRUE)]",
  "x <- RAWDATA[Date %in% me[me >= as.Date('2004-06-01')], .(Date, Ticker)]",
  "x[, i := as.integer(sub('T', '', Ticker, fixed = TRUE))]",
  "PORTFOLIO <- x[, .(Ticker, Weight = i / sum(i), Leg = 'long'), by = Date]"))
grid60 <- function(s0) { g <- CAL[CAL >= s0]; g[seq(1L, length(g), by = 60L)] }
WK <- CAL[!duplicated(format(CAL, "%G%V"), fromLast = TRUE)]; WK <- WK[WK >= as.Date("2004-06-01")]

# 기대 사상(독립 재도출) — 월말 d 의 원천 = (직전 월말, d] 안의 가장 늦은 신호일
expect_map <- function(sigs) {
  prev <- c(as.Date("1900-01-01"), ME[-length(ME)])
  rbindlist(lapply(seq_along(ME), function(i) {
    s <- sigs[sigs > prev[i] & sigs <= ME[i]]
    if (length(s)) data.table(d = ME[i], s = max(s)) else NULL
  }))
}

run_cell <- function(engine, root, base, rp_start = NULL, startfile = "", diag_dir = "") {
  spec <- list(code = "BAL", label = "base-alignment", block = "T",
               fixed_axes = list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150",
                                 start_date = format(SPEC_START), commission_bps = 15L, liq_adv20_min = 2e8),
               base_signal = base, factor2 = list(kind = "none"),
               weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"))
  sp <- file.path(TMP, sprintf("spec_%s.json", basename(root)))
  writeLines(toJSON(spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), sp)
  vars <- c("QM_ROOT", "RF_CELL_SPEC", "RF_BAL_STARTFILE", "RF_ENGINE_DIAG_DIR")
  old <- Sys.getenv(vars, unset = NA)
  on.exit(for (nm in names(old)) if (is.na(old[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, setNames(list(old[[nm]]), nm)), add = TRUE)
  Sys.setenv(QM_ROOT = root, RF_CELL_SPEC = sp)
  if (nzchar(startfile)) Sys.setenv(RF_BAL_STARTFILE = startfile) else Sys.unsetenv("RF_BAL_STARTFILE")
  if (nzchar(diag_dir)) Sys.setenv(RF_ENGINE_DIAG_DIR = diag_dir) else Sys.unsetenv("RF_ENGINE_DIAG_DIR")
  env <- new.env()
  assign("RAWDATA", copy(FIX), envir = env); assign("BM_DT", BMF, envir = env)
  if (!is.null(rp_start)) assign(".RP_START_DATE", as.Date(rp_start), envir = env)   # 러너가 넣는 자리(fe_env)
  err <- NULL
  log <- capture.output(suppressWarnings(suppressMessages(
    tryCatch(source(engine, local = env), error = function(e) err <<- conditionMessage(e)))), type = "output")
  P <- if (exists("PANEL", envir = env, inherits = FALSE)) copy(get("PANEL", envir = env)) else NULL
  list(err = err, log = log, panel = P,
       hit = any(grepl("기저 캐시 적중", log, fixed = TRUE)), miss = any(grepl("기저 캐시 미스", log, fixed = TRUE)),
       out = if (exists("FACTORS", envir = env, inherits = FALSE)) copy(get("FACTORS", envir = env)) else NULL)
}
# 셀 패널의 (월말 d → 원천 신호일 s) 되읽기 — .base_sig = 신호일 번호 × 1000 + 종목 번호
panel_map <- function(P) unique(P[, .(d = Date, s = as.Date(floor(.base_sig / 1000), origin = "1970-01-01"))])[order(d)]
same_map <- function(a, b) nrow(a) == nrow(b) && all(a$d == b$d) && all(a$s == b$s)
# 비트 동일 — 열 이름 · 행 수 · 열마다 identical(부동소수 비트까지)
bit_same <- function(a, b) !is.null(a) && !is.null(b) && identical(names(a), names(b)) && nrow(a) == nrow(b) &&
  all(vapply(names(a), function(n) identical(a[[n]], b[[n]]), logical(1)))
eng <- function(p) list(kind = "engine", path = p)

# 구판 엔진(git blob)
LEG <- file.path(TMP, "rf_cell_engine_legacy.R")
gs <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(ROOT), "cat-file", "-p", LEGACY_BLOB), stdout = LEG, stderr = FALSE)),
               error = function(e) 1L)
HAS_LEG <- identical(as.integer(gs), 0L) && file.exists(LEG) && file.info(LEG)$size > 1000
if (!HAS_LEG) skip("구판 엔진 대조(A2 · B3 · D3)", "git blob 을 꺼낼 수 없다(저장소 밖 실행 또는 gc)")

writeLines("=== A. 월말 격자 — 항등 · 수정 전후 비트 동일 ===")
a1 <- run_cell(ENGINE, make_root("A_new"), eng(E_ME))
if (is.null(a1$err) && !is.null(a1$panel)) {
  m <- panel_map(a1$panel)
  chk(all(m$d == m$s) && all(m$d %in% SIG) && nrow(m) == length(SIG), "A1 월말 격자 = 항등(모든 시그널일이 자기 날짜의 신호를 읽는다)",
      sprintf("달 %d/%d · 옮겨진 달 %d", nrow(m), length(SIG), sum(m$d != m$s)))
} else ng("A1", a1$err %||% "PANEL 없음")
if (HAS_LEG) {
  a2 <- run_cell(LEG, make_root("A_leg"), eng(E_ME))
  chk(is.null(a1$err) && is.null(a2$err) && bit_same(a1$out, a2$out),
      sprintf("A2 구판 엔진과 FACTORS 비트 동일(%d행)", nrow(a1$out %||% data.table())), a2$err %||% a1$err %||% "값이 다르다")
}

writeLines("=== B. 60거래일 격자 — 그 달의 마지막 신호가 월말로 ===")
b1 <- run_cell(ENGINE, make_root("B_new"), eng(E_60))
exB <- expect_map(grid60(SPEC_START)); exB <- exB[d >= SPEC_START]
if (is.null(b1$err) && !is.null(b1$panel)) {
  m <- panel_map(b1$panel)
  chk(same_map(m, exB), sprintf("B1 사상 = 독립 재도출과 일치(신호 달 %d)", nrow(exB)), sprintf("얻은 달 %d", nrow(m)))
  chk(all(m$s <= m$d) && any(m$s < m$d), "B2 방향 = 신호일 ≤ 월말(뒤 날짜의 신호를 당겨 쓰지 않는다) · 옮겨진 달이 실제로 있다")
} else { ng("B1", b1$err %||% "PANEL 없음"); ng("B2", "미실행") }
if (HAS_LEG) {
  b3 <- run_cell(LEG, make_root("B_leg"), eng(E_60))
  n_leg <- if (!is.null(b3$panel)) uniqueN(b3$panel$Date) else 0L          # 겹치는 날이 없으면 구판은 패널 없이 멈춘다 = 0일
  n_ovl <- sum(grid60(as.Date("2004-06-01")) %in% SIG)                 # 구판 = 시작일 미전달(엔진 기본 2004-06-01) · 월말과 정확히 겹치는 날만
  chk(n_leg == n_ovl && n_leg < nrow(exB),
      sprintf("B3 구판은 월말과 겹치는 %d일만 읽는다(신판 %d달) — 결함 재현", n_leg, nrow(exB)), b3$err %||% sprintf("구판 %s일 · 겹침 %d", n_leg, n_ovl))
}

writeLines("=== C. 주간 격자 — 달마다 하나 ===")
c1 <- run_cell(ENGINE, make_root("C_new"), eng(E_WK))
exC <- expect_map(WK); exC <- exC[d >= SPEC_START]
if (is.null(c1$err) && !is.null(c1$panel)) {
  m <- panel_map(c1$panel)
  chk(same_map(m, exC) && nrow(m) == length(SIG), sprintf("C1 달마다 그 달의 마지막 주간 신호(%d달)", nrow(m)),
      sprintf("얻은 달 %d · 기대 %d", nrow(m), nrow(exC)))
} else ng("C1", c1$err %||% "PANEL 없음")

writeLines("=== D. 측정 시작일 전달 ===")
sfD <- file.path(TMP, "start_seen.txt")
d1 <- run_cell(ENGINE, make_root("D_spec"), eng(E_60), startfile = sfD)
chk(is.null(d1$err) && file.exists(sfD) && identical(readLines(sfD), format(SPEC_START)),
    "D1 러너 값이 없으면 칸 고정 축 시작일을 넘긴다", d1$err %||% paste(readLines(sfD), collapse = ""))
unlink(sfD)
RD <- make_root("D_rp")
d2 <- run_cell(ENGINE, RD, eng(E_60), rp_start = "2004-03-01", startfile = sfD)
chk(is.null(d2$err) && identical(readLines(sfD), "2004-03-01"), "D2 러너의 .RP_START_DATE 가 있으면 그 값을 넘긴다",
    d2$err %||% paste(readLines(sfD), collapse = ""))
if (is.null(d2$err) && !is.null(d2$panel)) {
  exD <- expect_map(grid60(as.Date("2004-03-01"))); exD <- exD[d >= SPEC_START]
  chk(same_map(panel_map(d2$panel), exD), "D2b 엔진 격자가 넘긴 시작일을 따른다(기준점 2004-03-01)")
} else ng("D2b", "미실행")
if (HAS_LEG) {
  unlink(sfD)
  d3 <- run_cell(LEG, make_root("D_leg"), eng(E_60), rp_start = NULL, startfile = sfD)
  chk(file.exists(sfD) && identical(readLines(sfD), "MISSING"), "D3 구판은 시작일을 넘기지 않는다 — 결함 재현(D1 이 구판에서 red)",
      paste(if (file.exists(sfD)) readLines(sfD) else "파일 없음", collapse = ""))
}

writeLines("=== E. 캐시 ===")
cfD <- list.files(file.path(RD, ".cache", "rf_base_signal"), full.names = TRUE)
if (length(cfD) == 1L) {
  ob <- readRDS(cfD); kk <- attr(ob, "rf_base_cache_key") %||% ""
  chk(grepl("^base_v3_[0-9a-f]{12}_[0-9a-f]{32}\\.rds$", basename(cfD)) && grepl("^rf_base_cache_v3\\|", kk), paste("E1 캐시 판 v3 · 파일 접두 base_v3_ —", basename(cfD)), kk)
  chk(grepl("|start=2004-03-01", kk, fixed = TRUE), "E2 키의 시작일 = 엔진에 넘긴 값(2004-03-01)", sub("^.*\\|nrow=", "nrow=", kk))
  chk(setequal(unique(ob$Date), grid60(as.Date("2004-03-01"))), "E3 캐시에는 엔진 원산출(스냅 전 60거래일 격자 그대로)",
      sprintf("캐시 날짜 %d · 격자 %d", uniqueN(ob$Date), length(grid60(as.Date("2004-03-01")))))
} else { ng("E1", paste("캐시 파일 수", length(cfD))); ng("E2", "미실행"); ng("E3", "미실행") }
d2b <- run_cell(ENGINE, RD, eng(E_60), rp_start = "2004-03-01", startfile = sfD)
chk(is.null(d2b$err) && d2b$hit && !d2b$miss && bit_same(d2b$out, d2$out), "E4 재실행 = 적중 · 산출이 미스 때와 같다(스냅은 적재 뒤에 매번)",
    d2b$err %||% sprintf("hit %s", d2b$hit))
d2c <- run_cell(ENGINE, RD, eng(E_60), rp_start = "2004-04-01", startfile = sfD)
chk(is.null(d2c$err) && d2c$miss && !d2c$hit, "E5 넘기는 시작일이 바뀌면 미스(다른 시작일의 캐시를 쓰지 않는다)", d2c$err %||% sprintf("hit %s", d2c$hit))

writeLines("=== F. 진단 ===")
DG <- file.path(TMP, "diag"); dir.create(DG, showWarnings = FALSE)
RF <- make_root("F_diag")
f1 <- run_cell(ENGINE, RF, eng(E_60), diag_dir = DG)
dj <- file.path(DG, "rf_engine_diag.json")
if (is.null(f1$err) && file.exists(dj)) {
  ba <- fromJSON(dj, simplifyVector = FALSE)$base_alignment[["ENG_60/engine.R"]]
  g <- grid60(SPEC_START)
  chk(!is.null(ba) && identical(ba$rule, "month_snap_v1") && ba$n_engine_dates == length(g) && ba$n_cell_dates == nrow(expect_map(g)) &&
        isTRUE(ba$start_injected) && identical(ba$start, format(SPEC_START)) && identical(ba$from_cache, FALSE) && identical(ba$base_kind, "factors") &&
        ba$n_offcal == 0L && identical(ba$first_engine_date, format(min(g))) && ba$n_cell_dates_from_start == nrow(expect_map(g)[d >= SPEC_START]),
      sprintf("F1 진단 base_alignment — 엔진 신호일 %d → 월말 %d · 시작 %s · 캐시 미스", length(g), nrow(expect_map(g)), format(SPEC_START)),
      paste(names(ba), collapse = ","))
  f2 <- run_cell(ENGINE, RF, eng(E_60), diag_dir = DG)
  ba2 <- fromJSON(dj, simplifyVector = FALSE)$base_alignment[["ENG_60/engine.R"]]
  chk(is.null(f2$err) && isTRUE(ba2$from_cache), "F2 재실행 진단 = 캐시 적중 표시")
} else { ng("F1", f1$err %||% "진단 파일 없음"); ng("F2", "미실행") }

writeLines("=== G. 경계 ===")
g1 <- run_cell(ENGINE, make_root("G_late"), eng(E_LATE))
chk(!is.null(g1$err) && grepl("달 스냅 뒤 기저 패널이 비었다", g1$err, fixed = TRUE), "G1 신호일이 전부 달력 뒤면 멈춘다(조용한 무신호 금지)", g1$err %||% "오류 없음")
g2 <- run_cell(ENGINE, make_root("G_mom", sibs = setdiff(SIBS, c("rf_base_align.R", "rf_base_cache.R"))), list(kind = "mom_12_1"))
chk(is.null(g2$err) && !is.null(g2$out) && nrow(g2$out) > 0L, "G2 기저 mom_12_1 칸은 달 스냅 · 캐시 파일 없이 돈다(기존 격리 루트 시험 무변화)", g2$err %||% "산출 없음")
DG3 <- file.path(TMP, "diag_blend"); dir.create(DG3, showWarnings = FALSE)
g3 <- run_cell(ENGINE, make_root("G_blend"), list(kind = "engine_blend", paths = list(E_ME, E_60)), diag_dir = DG3)
chk(is.null(g3$err) && !is.null(g3$panel) && setequal(unique(g3$panel$Date), exB$d),
    sprintf("G3 engine_blend(월말 + 60거래일) = 두 엔진이 함께 있는 달(%d)", nrow(exB)), g3$err %||% sprintf("달 %d", uniqueN(g3$panel$Date)))
ba3 <- if (file.exists(file.path(DG3, "rf_engine_diag.json"))) fromJSON(file.path(DG3, "rf_engine_diag.json"), simplifyVector = FALSE)$base_alignment else NULL
chk(setequal(names(ba3), c("ENG_ME/engine.R", "ENG_60/engine.R")) && ba3[["ENG_ME/engine.R"]]$n_moved == 0L && ba3[["ENG_60/engine.R"]]$n_moved > 0L,
    "G4 결합 기저는 엔진마다 정합 진단을 남긴다(월말 엔진 옮김 0 · 60거래일 엔진 옮김 > 0)", paste(names(ba3), collapse = ","))

writeLines("=== H. 기저의 종류(점수 패널 | 비중) ===")
#   포트폴리오만 내는 엔진은 비중이 점수로 읽힌다(설계 README §2-2) — 셀 엔진은 그대로 돌되 진단에 base_kind 를 남긴다.
#   상설 판(코어 v3)이 이 값으로 '비중을 점수로 읽은 측정'을 판정 전에 막는다.
DGH <- file.path(TMP, "diag_pf"); dir.create(DGH, showWarnings = FALSE)
RH <- make_root("H_pf")
kindH <- function() fromJSON(file.path(DGH, "rf_engine_diag.json"), simplifyVector = FALSE)$base_alignment[["ENG_PF/engine.R"]]
h1 <- run_cell(ENGINE, RH, eng(E_PF), diag_dir = DGH)
chk(is.null(h1$err) && h1$miss && identical(kindH()$base_kind, "portfolio_weights") && identical(kindH()$from_cache, FALSE),
    "H1 포트폴리오만 내는 기저 = base_kind portfolio_weights(엔진 실행)", h1$err %||% paste(unlist(kindH()[c("base_kind", "from_cache")]), collapse = ","))
h2 <- run_cell(ENGINE, RH, eng(E_PF), diag_dir = DGH)
chk(is.null(h2$err) && h2$hit && identical(kindH()$base_kind, "portfolio_weights") && isTRUE(kindH()$from_cache),
    "H2 캐시 적중 때도 base_kind 가 남는다(캐시 객체 속성)", h2$err %||% paste(unlist(kindH()[c("base_kind", "from_cache")]), collapse = ","))
#   레인 시드(rf_base_cache_seed_save)도 같은 속성을 남긴다 — 시드 캐시가 적중해도 종류를 안다
bc <- new.env(); sys.source(pick("rf_base_cache.R"), envir = bc)
RS <- make_root("H_seed"); DTs <- copy(FIX)
seed_kind <- function(FX, PF, engp) {
  ck <- bc$rf_base_cache_seed_key(engp, DTs, root = RS, start = format(SPEC_START))
  sv <- bc$rf_base_cache_seed_save(FX, PF, ck, root = RS, provenance = "test")
  f <- file.path(RS, ".cache", "rf_base_signal", ck$file)
  if (!identical(sv, "saved") || !file.exists(f)) return(paste("저장 실패:", sv))
  attr(readRDS(f), "rf_base_kind", exact = TRUE) %||% "(속성 없음)"
}
FXs <- FIX[Date %in% ME[ME >= SPEC_START], .(Date, Ticker, Score = Close)]
PFs <- FIX[Date %in% ME[ME >= SPEC_START], .(Date, Ticker, Weight = 1 / .N, Leg = "long"), by = Date][, .(Date, Ticker, Weight, Leg)]
chk(identical(seed_kind(FXs, PFs, E_ME), "factors"), "H3 레인 시드 — FACTORS 가 있으면 base_kind factors")
chk(identical(seed_kind(NULL, PFs, E_PF), "portfolio_weights"), "H4 레인 시드 — PORTFOLIO 뿐이면 base_kind portfolio_weights")

unlink(TMP, recursive = TRUE)
emit()
quit(status = if (FAIL > 0L) 1L else 0L)
