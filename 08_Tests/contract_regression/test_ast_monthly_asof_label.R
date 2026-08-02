# ============================================================================
# test_ast_monthly_asof_label.R — AST 컴파일러 factor_db_monthly 리프의
#   "행 라벨 = 커넥터 as-of" 계약 (양성 대조 + 위반 주입)
# ----------------------------------------------------------------------------
# 신설 2026-08-02. 대상 = 02_Infrastructure/ast/ast_compile.R
#                        (ast_leaf_provider_canonical, factor_db_monthly 분기)
#                      + 02_Infrastructure/factor_db/factor_db_connector.R v2.4
#
# ★원 결함(실사고): provider 가 월별 팩터 행을 **캘린더 월말**(각 월 1일−1)로 라벨했다.
#   eval 그리드는 **거래일 월말**(RAWDATA 기준, WT 드라이버 공통)이라, 거래말<캘린더말인
#   달에는 AS_OF 조인(avail_ts <= eval_date)이 그 달 값을 못 보고 **전월 값을 당겼다**.
#   실측 2004-12~2026-06 = 94/259 월(36.3%). lag 방향이라 look-ahead 는 아니지만
#   신호가 한 달 낡아 측정이 감쇠한다. 증거: stage_artifacts/WT_D20260802_009/probe_parity2.R
#   (bad 93/93 이 거래말<캘린더말, 해당 월 값 == 전월 load_month_factors 값 max|diff|=0).
#
# ★왜 8일간 안 잡혔나 = 검사가 잘못된 지점에 서 있었다:
#   기존 parity 검사(02_Infrastructure/ast/tests/parity_factor_db.R)는 EVAL_DATES 를
#   **캘린더 월말**로 잡았다 — provider 의 합성 라벨과 같은 좌표계라 결함이 상쇄돼
#   rho=1.0 이 나왔다. 그래서 본 검사는 eval 그리드를 factor DB 와 무관한 독립 소스
#   (RAWDATA 거래일)에서 만든다.
#
# 축:
#   A 양성 대조(실데이터): eval=거래일 월말에서 컴파일 값 == 그 달 커넥터 값
#   B 위반 주입: as-of 미보고 / 미래 vintage / 월 결손 중복 라벨
#   C 돌연변이(구판 재현): 캘린더 월말 라벨을 되돌리면 A 의 검사가 **실제로 FAIL** 하나
#   D 배선: 커넥터가 attr(factor_db_asof_date) 를 실제로 붙이나 (파일 Date 와 일치)
#   E PIT 창: 캘린더 월말로 요청해도 방향정렬(Usable_Date<=sig_date) 창이 안 넓어지나
#
# 실행: Rscript 08_Tests/contract_regression/test_ast_monthly_asof_label.R
# ============================================================================

suppressPackageStartupMessages({ library(data.table); library(arrow) })

PASS <- 0L; FAIL <- 0L
ok <- function(cond, name, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s %s\n", name, detail)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}
err_of <- function(expr) tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))

# ── 코드 루트 = 이 테스트가 실린 트리 (worktree 좌초 방지) ──────────────────────
# 데이터 루트는 config.R 이 QM_ROOT 로 정한다(.cache 는 main 에만 있음). 코드와 데이터
# 루트가 갈릴 수 있으므로 **둘 다 출력**한다 — "어느 트리에서 참인지"가 기록에 남아야 한다.
.MARKER <- "02_Infrastructure/ast/ast_compile.R"
CODE_ROOT <- local({
  a <- commandArgs(trailingOnly = FALSE)
  hit <- grep("^--file=", a, value = TRUE)
  self <- if (length(hit)) sub("^--file=", "", hit[1]) else {
    of <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
    if (is.null(of)) NA_character_ else of
  }
  cands <- character(0)
  if (!is.na(self)) {
    sp <- normalizePath(self, winslash = "/", mustWork = FALSE)
    cands <- c(cands, dirname(dirname(dirname(sp))))   # 08_Tests/contract_regression/x.R → root
  }
  cands <- c(cands, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  hit2 <- cands[file.exists(file.path(cands, .MARKER))]   # 존재가 아니라 **표지**로 확인
  if (!length(hit2)) stop("[test_ast_asof] 코드 루트 해석 실패 — 표지 부재: ", .MARKER)
  hit2[1]
})
cat(sprintf("=== test_ast_monthly_asof_label ===\nCODE_ROOT = %s\n", CODE_ROOT))

source(file.path(CODE_ROOT, "02_Infrastructure/config.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/ast/ast_compile.R"))
cat(sprintf("DATA_ROOT = %s\nFACTOR_DB_DIR = %s\n", PROJECT_ROOT, FACTOR_DB_DIR))

FAC <- "M01_Mom_12_1"
leaf <- list(type = "leaf", class = "FIELD", source = "factor_db_monthly", field = FAC)
cal_end_of <- function(d) {
  ce <- as.Date(format(as.Date(d), "%Y-%m-01")) + 32L
  ce - as.integer(format(ce, "%d"))
}

# ── eval 그리드: factor DB 와 **독립**인 RAWDATA 거래일에서 생성 ────────────────
rawp <- file.path(CACHE_DIR, "RAWDATA.parquet")
if (!file.exists(rawp)) {
  cat("  SKIP-FATAL RAWDATA.parquet 부재 — 실데이터 축 불가\n")
  cat(sprintf('{"test":"ast_monthly_asof_label","pass":0,"fail":1,"total":1}\n'))
  quit(status = 1L)
}
rd <- as.data.table(read_parquet(rawp, col_select = "Date"))
rd[, Date := as.Date(Date)]
mend <- rd[, .(td = max(Date)), by = .(ym = format(Date, "%Y%m"))]
rm(rd); invisible(gc(verbose = FALSE))
mend[, ce := cal_end_of(td)]
mend[, has_db := file.exists(file.path(FACTOR_DB_DIR, paste0("factor_db_", ym, ".parquet")))]
setorder(mend, ym)
# 마지막 2개월은 DB 빌드/증분 상태가 유동적이라 제외 (검사 안정성)
cand <- mend[has_db == TRUE][seq_len(max(0L, .N - 2L))]
prev_ym <- function(y) format(seq(as.Date(paste0(substr(y, 1, 4), "-", substr(y, 5, 6), "-01")),
                                 by = "-1 month", length.out = 2L)[2], "%Y%m")
# 스테일이 실제로 발생하는 월(거래말<캘린더말) 중 **직전월 DB 도 있는** 최근 1건.
# span = {M-1, M} 2개월 고정 — provider 로드를 2회로 묶고, 구판 재현 시 "전월로 미끄러질
# 자리"를 보장한다(전월이 없으면 구판이 NA 가 되어 스테일 지문을 못 본다).
qual <- cand[td < ce][vapply(cand[td < ce]$ym, function(y) prev_ym(y) %in% cand$ym, logical(1))]
if (nrow(qual) < 1L) {
  cat("  SKIP-FATAL 거래말<캘린더말 + 직전월 DB 동시 충족 월 없음 — 판별 불가\n")
  cat(sprintf('{"test":"ast_monthly_asof_label","pass":0,"fail":1,"total":1}\n'))
  quit(status = 1L)
}
M <- tail(qual$ym, 1L)
probe_ym <- c(prev_ym(M), M)
span <- cand[ym %in% probe_ym]
EVAL <- sort(span$td)
cat(sprintf("probe 월: %s | eval(거래일 월말) = %s | 캘린더말 = %s\n",
            paste(probe_ym, collapse = ","), paste(format(EVAL), collapse = ","),
            paste(format(cal_end_of(EVAL)), collapse = ",")))

# 실 커넥터 호출 memo (동일 인자 재호출만 절약 — 좌/우변은 서로 다른 인자라 무관)
.real_lmf <- load_month_factors
.memo <- new.env(parent = emptyenv())
memo_lmf <- function(sig_date, ...) {
  k <- paste(format(as.Date(sig_date)), paste(names(list(...)), unlist(list(...)), collapse = "|"))
  if (!is.null(.memo[[k]])) return(.memo[[k]])
  v <- .real_lmf(sig_date, ...)
  .memo[[k]] <- v
  v
}
load_month_factors <- memo_lmf   # globalenv — provider 가 호출 시점에 여기서 찾는다

# 컴파일 값 vs 그 달 커넥터 값 (Ticker 매칭 후 max|diff|)
cmp_vs_db <- function(panel, d) {
  a <- as.data.table(panel)[Date == d & !is.na(value), .(Ticker, av = value)]
  b <- as.data.table(load_month_factors(d, factor_names = FAC))[, .(Ticker, bv = Z_Score_Aligned)]
  m <- merge(a, b, by = "Ticker")
  list(n = nrow(m), mad = if (nrow(m)) max(abs(m$av - m$bv)) else NA_real_)
}

# ── A. 양성 대조 (실데이터·실 provider) ────────────────────────────────────────
cat("--- A. 양성 대조: eval=거래일 월말에서 그 달 값이 보이나 ---\n")
cmp <- ast_compile(leaf, eval_dates = EVAL)
pan <- cmp$panel
ok(nrow(pan) > 0L && sum(!is.na(pan$value)) > 100L,
   "A1 컴파일 패널 non-NA 존재", sprintf("(rows=%d non-NA=%d)", nrow(pan), sum(!is.na(pan$value))))
ok(setequal(unique(pan$Date), EVAL), "A2 라벨 그리드 = eval 거래일 월말 전건")
for (d in as.list(EVAL)) {
  r <- cmp_vs_db(pan, d)
  ok(!is.na(r$mad) && r$n > 100L && r$mad < 1e-12,
     sprintf("A3 %s 값 == 그 달 커넥터 값", format(d)),
     sprintf("(n=%d max|diff|=%s)", r$n, format(r$mad)))
}
# A4: 전월 값과 실제로 다르다 (같으면 A3 가 공허해진다 — 검사의 판별력 전제)
prev_td <- min(EVAL)   # span = {M-1, M} 고정
a <- as.data.table(pan)[Date == max(EVAL) & !is.na(value), .(Ticker, av = value)]
b <- as.data.table(load_month_factors(prev_td, factor_names = FAC))[, .(Ticker, bv = Z_Score_Aligned)]
m <- merge(a, b, by = "Ticker")
ok(nrow(m) > 100L && max(abs(m$av - m$bv)) > 1e-6,
   "A4 전월 값과 구별됨 (A3 가 공허하지 않음)",
   sprintf("(n=%d max|diff|=%.4f)", nrow(m), if (nrow(m)) max(abs(m$av - m$bv)) else NA_real_))

# ── B. 위반 주입 (스텁 커넥터) ─────────────────────────────────────────────────
cat("--- B. 위반 주입: 결손/미래/중복 as-of 를 provider 가 거부하나 ---\n")
prov <- ast_leaf_provider_canonical()
ctx <- list(eval_dates = EVAL, history_periods = list())
one_month <- as.data.table(load_month_factors(max(EVAL), factor_names = FAC))

# B1: as-of 미보고 → 요청일 라벨로 되돌리지 않고 즉시 중단 (fail-closed)
load_month_factors <- function(sig_date, ...) {
  r <- copy(one_month); attr(r, "factor_db_asof_date") <- NULL; r
}
e1 <- err_of(prov(leaf, ctx))
ok(!is.null(e1) && grepl("as-of", e1, fixed = TRUE), "B1 as-of 미보고 = 하드 중단",
   sprintf("(%s)", substr(e1 %||% "no error", 1, 70)))

# B2: 요청일보다 미래 vintage → look-ahead 거부
load_month_factors <- function(sig_date, ...) {
  r <- copy(one_month); attr(r, "factor_db_asof_date") <- as.Date(sig_date) + 1L; r
}
e2 <- err_of(prov(leaf, ctx))
ok(!is.null(e2) && grepl("미래 vintage", e2, fixed = TRUE), "B2 미래 vintage = 하드 중단",
   sprintf("(%s)", substr(e2 %||% "no error", 1, 70)))

# B3: 월 DB 결손으로 같은 패널이 반복 반환 → 중복 라벨 없이 경고 (값 복제 금지)
fixed_asof <- min(EVAL)
load_month_factors <- function(sig_date, ...) {
  r <- copy(one_month); attr(r, "factor_db_asof_date") <- fixed_asof; r
}
warns <- character(0)
out3 <- withCallingHandlers(prov(leaf, ctx),
  warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
ok(is.data.table(out3) && uniqueN(out3$Date) == 1L && all(out3$Date == fixed_asof),
   "B3 결손 대체분이 중복 라벨로 복제되지 않음",
   sprintf("(unique dates=%d)", if (is.data.table(out3)) uniqueN(out3$Date) else -1L))
ok(any(grepl("결손", warns)), "B3b 결손이 침묵하지 않고 경고로 발화",
   sprintf("(warnings=%d)", length(warns)))

# B4: 로드 예외 = 조용한 스킵 금지 (스킵 월은 LOCF 가 메워 stale 과 증상이 같다)
load_month_factors <- function(sig_date, ...) {
  if (format(as.Date(sig_date), "%Y%m") == format(min(EVAL), "%Y%m"))
    stop("주입된 로드 실패 (테스트)")
  memo_lmf(sig_date, ...)
}
w4 <- character(0)
out4 <- withCallingHandlers(prov(leaf, ctx),
  warning = function(w) { w4 <<- c(w4, conditionMessage(w)); invokeRestart("muffleWarning") })
ok(any(grepl("로드 예외", w4)), "B4 로드 예외 월이 경고로 발화 (조용한 스킵 아님)",
   sprintf("(warnings=%d)", length(w4)))
ok(is.data.table(out4) && uniqueN(out4$Date) == length(EVAL) - 1L,
   "B4b 실패 월만 빠지고 나머지는 정상 산출",
   sprintf("(dates=%d, 기대=%d)", if (is.data.table(out4)) uniqueN(out4$Date) else -1L, length(EVAL)-1L))

# B5: 첫 달 결손 폴백 — 중복이 안 생겨도 '월 불일치'로 잡히나 (초판 술어의 사각)
fake_prev <- as.Date(format(min(EVAL), "%Y-%m-01")) - 1L   # 전월 캘린더 말일 = 다른 월
load_month_factors <- function(sig_date, ...) {
  r <- memo_lmf(sig_date, ...)
  if (format(as.Date(sig_date), "%Y%m") == format(min(EVAL), "%Y%m")) {
    r <- copy(r); attr(r, "factor_db_asof_date") <- fake_prev
  }
  r
}
w5 <- character(0)
out5 <- withCallingHandlers(prov(leaf, ctx),
  warning = function(w) { w5 <<- c(w5, conditionMessage(w)); invokeRestart("muffleWarning") })
ok(any(grepl("결손", w5)), "B5 첫 달 결손 폴백이 중복 없이도 경고로 발화",
   sprintf("(warnings=%d)", length(w5)))
ok(is.data.table(out5) && fake_prev %in% out5$Date,
   "B5b 대체 패널은 보고된 as-of 로 라벨됨(요청일로 되돌리지 않음)")

load_month_factors <- memo_lmf   # 실 커넥터 복귀

# ── C. 돌연변이: 구판(캘린더 월말 라벨)을 되돌리면 A3 가 FAIL 하나 ──────────────
cat("--- C. 돌연변이: 구판 라벨 재현 시 검사가 실제로 발화하나 ---\n")
load_month_factors <- function(sig_date, ...) {
  r <- memo_lmf(sig_date, ...)
  attr(r, "factor_db_asof_date") <- cal_end_of(sig_date)   # ← 구판 = 캘린더 월말 라벨
  r
}
cmp_mut <- ast_compile(leaf, eval_dates = EVAL)
load_month_factors <- memo_lmf
mut_bad <- vapply(as.list(EVAL), function(d) {
  r <- cmp_vs_db(cmp_mut$panel, d); is.na(r$mad) || r$n == 0L || r$mad > 1e-6
}, logical(1))
# 판별 대상 = 거래말<캘린더말 인 eval 일 (동일한 달은 구판/신판 라벨이 같아 무차별)
qual_i <- which(EVAL < cal_end_of(EVAL))
ok(length(qual_i) >= 1L && all(mut_bad[qual_i]),
   "C1 구판 라벨에서 A3 검사가 스테일을 검거",
   sprintf("(판별대상 %d월 중 발화 %d)", length(qual_i), sum(mut_bad[qual_i])))
# C2: 스테일의 지문 = 전월 값과 정확히 일치
d_last <- max(EVAL)
a <- as.data.table(cmp_mut$panel)[Date == d_last & !is.na(value), .(Ticker, av = value)]
b <- as.data.table(load_month_factors(min(EVAL), factor_names = FAC))[, .(Ticker, bv = Z_Score_Aligned)]
m <- merge(a, b, by = "Ticker")
ok(nrow(m) > 100L && max(abs(m$av - m$bv)) < 1e-12,
   "C2 구판 산출 == 전월 커넥터 값 (1개월 stale 지문)",
   sprintf("(n=%d max|diff|=%s)", nrow(m), format(if (nrow(m)) max(abs(m$av - m$bv)) else NA_real_)))

# ── D. 배선: 커넥터가 파일 Date 를 그대로 보고하나 ─────────────────────────────
cat("--- D. 배선: 커넥터 as-of == 월 파일 Date ---\n")
for (i in seq_along(probe_ym)) {
  ymi <- probe_ym[i]
  tdi <- cand[ym == ymi, td]
  fp <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ymi, ".parquet"))
  file_dates <- unique(as.Date(as.data.table(read_parquet(fp, col_select = "Date"))$Date))
  got <- attr(memo_lmf(cal_end_of(tdi), factor_names = FAC), "factor_db_asof_date")
  ok(length(file_dates) == 1L, sprintf("D%da %s 월 파일 Date 단일값", i, ymi),
     sprintf("(n_unique=%d)", length(file_dates)))
  ok(!is.null(got) && !is.na(got) && got == max(file_dates) && got == tdi,
     sprintf("D%db 커넥터 as-of == 파일 Date == RAWDATA 거래말", i),
     sprintf("(attr=%s file=%s raw=%s)", format(got), format(max(file_dates)), format(tdi)))
}

# ── E. PIT 창: 캘린더 월말 요청이 방향정렬 창을 넓히지 않나 ────────────────────
cat("--- E. PIT 창: 요청일(캘린더말) vs as-of(거래말) 사이 IC 행 부재 ---\n")
ic <- tryCatch(.load_ic_history(), error = function(e) NULL)
if (is.null(ic) || !"Usable_Date" %in% names(ic)) {
  ok(FALSE, "E1 IC 히스토리 로드 실패 — 창 검사 불가")
} else {
  n_in <- sum(vapply(as.list(EVAL), function(d)
    ic[Usable_Date > d & Usable_Date <= cal_end_of(d), .N], integer(1)))
  ok(n_in == 0L,
     "E1 (as-of, 캘린더말] 창에 IC 행 없음 → 방향정렬 동일 (A3 좌/우변 비교 유효)",
     sprintf("(rows=%d)", n_in))
}

# ── F. 히스토리 있는 리프: TS 창이 월 라벨에 올라타는지 ───────────────────────
# 라벨이 틀리면 TS_DELTA(k=1) 는 "이번달-전달"이 아니라 "전달-전전달"이 된다.
# 히스토리 월(eval 그리드 밖)도 같은 as-of 규율로 라벨돼야 성립한다.
cat("--- F. 히스토리 리프(TS_DELTA k=1): 월 정렬이 맞나 ---\n")
ast_d1 <- list(type = "op", op = "TS_DELTA", params = list(k = 1L), args = list(leaf))
cmp_d <- ast_compile(ast_d1, eval_dates = EVAL)
d_last <- max(EVAL)
a <- as.data.table(cmp_d$panel)[Date == d_last & !is.na(value), .(Ticker, av = value)]
cur <- as.data.table(load_month_factors(d_last, factor_names = FAC))[, .(Ticker, cur = Z_Score_Aligned)]
prv <- as.data.table(load_month_factors(min(EVAL), factor_names = FAC))[, .(Ticker, prv = Z_Score_Aligned)]
m <- merge(merge(a, cur, by = "Ticker"), prv, by = "Ticker")
ok(nrow(m) > 100L && max(abs(m$av - (m$cur - m$prv))) < 1e-12,
   "F1 TS_DELTA == 당월 − 전월 (히스토리 월 라벨도 as-of)",
   sprintf("(n=%d max|diff|=%s)", nrow(m),
           format(if (nrow(m)) max(abs(m$av - (m$cur - m$prv))) else NA_real_)))

cat(sprintf("\nPASS=%d FAIL=%d\n", PASS, FAIL))
cat(sprintf('{"test":"ast_monthly_asof_label","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
