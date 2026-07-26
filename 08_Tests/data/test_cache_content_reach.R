#==============================================================================
# test_cache_content_reach.R — 캐시 "내용 도달" 감시 위반 주입 테스트 (P2-02 / P2-03)
#
# 대상:
#   02_Infrastructure/data/cache_content_reach.R  (ccr_* 판정부)
#   02_Infrastructure/data/cache_freshness_audit.R (소비처 — 디렉토리형/단일파일 분기)
#   02_Infrastructure/data/cache_registry.json     (도달 축 선언)
#
# 왜 있나:
#   수리 전, 두 감시 장치가 **동시에 침묵**해서 DART FY2025 재무제표 결손(corps 50 vs
#   정상 714 = 7.0%)이 4개월간 무보고로 남았다.
#     P2-02 (B형) 디렉토리형 캐시에 date_col 이 없으면 파일명 YYYYMM 의 **월말**로 lag 을
#            만든다 → max(0, today − 월말) = 그 달 내내 0. 파일 내용을 한 번도 안 읽는다.
#            실사고: factor_db_202607 이 Date=2026-07-03 에 3주 동결된 동안 매일 FRESH.
#     P2-03 (C형) date_col 미선언 단일파일은 **mtime 만으로** 판정 → 내용이 비었든 잘렸든
#            과거만 담았든 구분 못 함. 실사고: fundamental_dart.parquet mtime 26일 → FRESH.
#
#   ★이 파일의 존재 이유: **오탐 0 인 검사와 죽은 검사는 겉보기가 같다.** 수리 후 "경보
#     0건"은 건강의 증거가 아니라 계측 사망의 증거일 수 있다 — 그 둘을 가르는 유일한
#     방법이 일부러 틀린 입력을 넣어 보는 것이다.
#
# 구조 5축:
#   A. 위반 주입 — 결손 상태를 주입해 실제로 잡히는가
#   B. 오탐 0    — 정상 상태를 경보로 만들지 않는가
#   C. 크래시    — 파일 부재/컬럼 부재/0행/파싱불가에서 죽지 않고 UNKNOWN 인가
#   D. 차단 실효 — 판정부를 "못 보는" 형태로 되돌리면 A 가 통과로 뒤집히는가
#                  (뒤집히지 않으면 그 케이스는 애초에 아무것도 재고 있지 않은 것)
#   E. 규약·배선 — 정본 registry 의 도달 축 선언이 실제로 있고 소비처가 살아 있는가
#
# ★정본 불변: D 축은 **사본**을 변조한다. 스크립트 최상위 on.exit() 는 발화하지 않으므로
#   (r-portability 금칙 ②) 정본을 제자리 변조하면 중단 시 복구가 안 된다. 정본은 md5 로
#   불변을 실증하고, 임시 산출물은 함수 종료 시점에 명시적으로 지운다.
#
# 단독 실행: Rscript 08_Tests/data/test_cache_content_reach.R
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite); library(arrow); library(data.table)
})

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  marker <- "02_Infrastructure/data/cache_content_reach.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)
PROJECT_ROOT <- PROJ                     # 소비처가 참조

REACH_SRC <- "02_Infrastructure/data/cache_content_reach.R"
AUDIT_SRC <- "02_Infrastructure/data/cache_freshness_audit.R"
REG_PATH  <- "02_Infrastructure/data/cache_registry.json"

REACH_MD5_BEFORE <- unname(tools::md5sum(REACH_SRC))
AUDIT_MD5_BEFORE <- unname(tools::md5sum(AUDIT_SRC))

suppressMessages(suppressWarnings({
  source(REACH_SRC)
  source(AUDIT_SRC)
}))

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
chk <- function(n, cond, m = "") if (isTRUE(cond)) ok(n) else bad(n, m)

TODAY <- as.Date("2026-07-26")           # 결정성 — 실사고 시점

# ─── 임시 작업공간 (PROJECT_ROOT 하위여야 registry 상대경로가 성립) ──────────
# `_` 접두 = ephemeral 컨벤션(hygiene/orphan 필터 대상). 종료 시 명시 삭제.
TMP_REL <- file.path(".cache", sprintf("_test_ccr_%d", Sys.getpid()))
TMP_ABS <- file.path(PROJ, TMP_REL)
# ★기동 시 이전 실행의 잔재부터 지운다 (자기치유). 스크립트 최상위 on.exit() 는 발화하지
#   않으므로(r-portability 금칙 ②) 본문이 중간에 죽으면 끝단 cleanup() 이 실행되지 않는다
#   — 실제로 2026-07-26 C4 가 결함을 잡아 스크립트가 중단됐을 때 _test_ccr_40408 이 남았다.
#   끝단 cleanup 만으로는 "크래시 → 잔재 누적"을 못 막으므로 양쪽에서 지운다.
unlink(Sys.glob(file.path(PROJ, ".cache", "_test_ccr_*")), recursive = TRUE, force = TRUE)
dir.create(TMP_ABS, recursive = TRUE, showWarnings = FALSE)
cleanup <- function() unlink(TMP_ABS, recursive = TRUE, force = TRUE)

.wp <- function(dt, rel) {                # 임시 parquet 쓰기 → 상대경로 반환
  p <- file.path(PROJ, rel)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  write_parquet(dt, p)
  invisible(rel)                          # 최상위 호출 시 자동출력 방지(요약 파싱 노이즈)
}
.entry <- function(path, ...) {
  modifyList(list(path = path, tier = 2L, schedule = "daily",
                  max_lag_days = 14L, producer = "(test)", entry_fn = "(test)"),
             list(...))
}
#' 주입 registry 1건으로 감사를 돌리고 그 항목 결과만 뽑는다.
#' persist=FALSE — 정본 observability/로그/알림상태를 건드리지 않는다.
.audit1 <- function(entry, key = entry$path) {
  a <- suppressMessages(suppressWarnings(utils::capture.output(
    res <- cache_freshness_audit(telegram_alert = FALSE, persist = FALSE,
                                 today = TODAY, caches_override = list(entry)))))
  hit <- Filter(function(r) identical(r$path, key), res$results)
  if (length(hit) == 0L) NULL else hit[[1]]
}

cat("=== A. 위반 주입 (결손을 실제로 잡는가) ===\n")

# ── A1. 디렉토리형: 당월 파일이 월중 스냅샷에서 동결 (P2-02 실사고 재현) ──────
#    factor_db_202607 이 Date=2026-07-03 에 얼어붙은 상태. 수리 전에는 파일명 202607 →
#    월말 07-31 → max(0, 07-26 − 07-31) = 0 → 그 달 내내 FRESH 였다.
FDB_DIR <- file.path(TMP_REL, "fdb")
.wp(data.table(Date = as.Date(rep("2026-07-03", 5)), Ticker = sprintf("A%05d", 1:5)),
    file.path(FDB_DIR, "factor_db_202607.parquet"))
a1 <- .audit1(.entry(paste0(FDB_DIR, "/"), file_pattern = "^factor_db_[0-9]{6}\\.parquet$",
                     date_col = "Date"))
chk("A1 월중 동결 디렉토리 = STALE 검거",
    !is.null(a1) && !identical(a1$severity, "OK") && identical(a1$lag_basis, "content"),
    sprintf("status=%s severity=%s lag=%s basis=%s",
            a1$status %||% "?", a1$severity %||% "?", a1$lag_used %||% "?", a1$lag_basis %||% "?"))
chk("A1b 동결 lag 이 내용 기준 23일로 산출",
    !is.null(a1) && identical(as.integer(a1$data_lag), 23L),
    sprintf("data_lag=%s (기대 23 = 07-26 − 07-03)", a1$data_lag %||% "NA"))

# ── A2. 같은 동결 상태인데 date_col 미선언 → 조용한 OK 가 아니라 WARN 표기 ────
a2 <- .audit1(.entry(paste0(FDB_DIR, "/"), file_pattern = "^factor_db_[0-9]{6}\\.parquet$"))
chk("A2 date_col 미선언 디렉토리 = FILENAME_ESTIMATE_ONLY/WARN (조용한 추정 금지)",
    !is.null(a2) && identical(a2$status, "FILENAME_ESTIMATE_ONLY") &&
      identical(a2$severity, "WARN") && identical(a2$lag_basis, "filename_month_end_estimate"),
    sprintf("status=%s severity=%s basis=%s", a2$status %||% "?", a2$severity %||% "?",
            a2$lag_basis %||% "?"))
chk("A2b 파일명 추정 lag 은 실제로 0 (= 내용을 안 보면 못 잡음의 실증)",
    !is.null(a2) && identical(as.integer(a2$data_lag), 0L),
    sprintf("data_lag=%s", a2$data_lag %||% "NA"))

# ── A3. 단일파일: 내용은 낡고 mtime 만 최신 (P2-03 실사고 형태) ───────────────
STALE_REL <- .wp(data.table(Date = as.Date(c("2026-01-30", "2026-01-31")), v = c(1, 2)),
                 file.path(TMP_REL, "stale_content.parquet"))
a3 <- .audit1(.entry(STALE_REL, date_col = "Date", max_lag_days = 7L))
chk("A3 mtime 최신 + 내용 낡음 = 내용 축이 검거",
    !is.null(a3) && !identical(a3$severity, "OK") && identical(as.integer(a3$mtime_lag), 0L),
    sprintf("status=%s severity=%s mtime_lag=%s data_lag=%s",
            a3$status %||% "?", a3$severity %||% "?", a3$mtime_lag %||% "?", a3$data_lag %||% "?"))

a3b <- .audit1(.entry(STALE_REL, max_lag_days = 7L))
chk("A3b 같은 파일 date_col 미선언 = NO_COVERAGE_CHECK/WARN (mtime 만이면 못 봄)",
    !is.null(a3b) && identical(a3b$status, "NO_COVERAGE_CHECK") &&
      identical(a3b$severity, "WARN") && identical(a3b$lag_basis, "mtime(undeclared)"),
    sprintf("status=%s severity=%s basis=%s", a3b$status %||% "?", a3b$severity %||% "?",
            a3b$lag_basis %||% "?"))

a3c <- .audit1(.entry(STALE_REL, max_lag_days = 7L,
                      no_content_check = list(reason = "테스트 — 명시 면제")))
chk("A3c no_content_check 선언 = MTIME_ONLY (가시화된 면제, undeclared 와 구분)",
    !is.null(a3c) && identical(a3c$status, "MTIME_ONLY") &&
      identical(a3c$lag_basis, "mtime(declared)"),
    sprintf("status=%s basis=%s", a3c$status %||% "?", a3c$lag_basis %||% "?"))

# ── A4/A5. 라벨-코호트 결손 (시간축이 없는 캐시) ──────────────────────────────
mk_cohort <- function(n2025) {
  rbindlist(list(
    data.table(bsns_year = 2023L, corp = sprintf("C%04d", 1:100)),
    data.table(bsns_year = 2024L, corp = sprintf("C%04d", 1:100)),
    if (n2025 > 0) data.table(bsns_year = 2025L, corp = sprintf("C%04d", seq_len(n2025)))
  ))
}
SPEC <- list(label_col = "bsns_year", entity_col = "corp",
             due_rule = list(years = 1L, md = "03-31"),
             grace_days = 45L, min_ratio_vs_prior = 0.8)

a4 <- ccr_coverage_check(SPEC, data = mk_cohort(7), today = TODAY)   # 7% — 실사고 비율
chk("A4 코호트 급감(7%) = COVERAGE_FAIL/CRITICAL",
    identical(a4$status, "COVERAGE_FAIL") && identical(a4$severity, "CRITICAL"),
    sprintf("status=%s note=%s", a4$status, a4$note))
chk("A4b 기대 라벨을 달력에서 산출(2025) — 데이터 최신값이 아니라",
    identical(as.integer(a4$groups[[1]]$expected_label), 2025L),
    sprintf("expected=%s", a4$groups[[1]]$expected_label %||% "NA"))

a5 <- ccr_coverage_check(SPEC, data = mk_cohort(0), today = TODAY)   # 코호트 통째 부재
chk("A5 코호트 자체 부재 = COVERAGE_MISSING (존재하는 것만 보면 안 보이는 결손)",
    identical(a5$status, "COVERAGE_FAIL") &&
      identical(a5$groups[[1]]$status, "COVERAGE_MISSING"),
    sprintf("group status=%s", a5$groups[[1]]$status %||% "NA"))

# ── A6. 미래 스탬프 함정: date_col 선언이 여기선 '가짜 수리'임을 실증 ──────────
#    fundamental_dart 의 Factor_Date 는 PIT usable date 라 max 가 미래(2027-03-31)다.
#    이걸 date_col 로 선언하면 lag 이 음수 → clamp → 영구 FRESH. 그래서 coverage_check
#    가 따로 필요하다. 이 케이스는 "주입했는데 date_col 축은 못 잡는다"를 고정한다.
FUT_REL <- .wp(data.table(Factor_Date = as.Date(rep("2027-03-31", 3)),
                          bsns_year = c(2023L, 2024L, 2025L),
                          Ticker = c("A1", "A2", "A3")),
               file.path(TMP_REL, "future_stamp.parquet"))
a6 <- .audit1(.entry(FUT_REL, date_col = "Factor_Date", date_semantics = "period_end",
                     schedule = "monthly", max_lag_days = 35L))
chk("A6 미래 스탬프 date_col = FRESH (=이 축으로는 결손을 못 잡음, coverage 필요 근거)",
    !is.null(a6) && identical(a6$status, "FRESH") && identical(as.integer(a6$data_lag), 0L),
    sprintf("status=%s data_lag=%s", a6$status %||% "?", a6$data_lag %||% "?"))

cat("\n=== B. 오탐 0 (정상 상태를 경보로 만들지 않는가) ===\n")

.wp(data.table(Date = as.Date(rep("2026-07-24", 5)), Ticker = sprintf("A%05d", 1:5)),
    file.path(TMP_REL, "fdb_ok", "factor_db_202607.parquet"))
b1 <- .audit1(.entry(paste0(TMP_REL, "/fdb_ok/"),
                     file_pattern = "^factor_db_[0-9]{6}\\.parquet$", date_col = "Date"))
chk("B1 정상 디렉토리(최신 거래일까지) = FRESH/OK",
    !is.null(b1) && identical(b1$status, "FRESH") && identical(b1$severity, "OK"),
    sprintf("status=%s lag=%s", b1$status %||% "?", b1$lag_used %||% "?"))

b2 <- ccr_coverage_check(SPEC, data = mk_cohort(98), today = TODAY)
chk("B2 정상 코호트(98/100) = COVERAGE_PASS/OK",
    identical(b2$status, "COVERAGE_PASS") && identical(b2$severity, "OK"),
    sprintf("status=%s note=%s", b2$status, b2$note))

# period_end: 월말 라벨이 today 를 앞서는 것은 정상 → clamp 0 (오탐 금지)
PE_REL <- .wp(data.table(Date = as.Date(c("2026-06-30", "2026-07-31")), v = c(1, 2)),
              file.path(TMP_REL, "period_end.parquet"))
b3 <- .audit1(.entry(PE_REL, date_col = "Date", date_semantics = "period_end",
                     schedule = "monthly", max_lag_days = 35L))
chk("B3 period_end 미래 월말 라벨 = clamp 0, FRESH (오탐 아님)",
    !is.null(b3) && identical(as.integer(b3$data_lag), 0L) && identical(b3$severity, "OK"),
    sprintf("data_lag=%s status=%s", b3$data_lag %||% "?", b3$status %||% "?"))
chk("B3b period_end 는 '미래 라벨'만 상쇄 — 정체는 그대로 lag (A3 가 잡힌 것이 증거)",
    !is.null(a3) && a3$data_lag > 100L,
    sprintf("A3 data_lag=%s", a3$data_lag %||% "?"))

# ym / ym_compact 문자열 축
chk("B4 kind='ym' → 그 달 말일",
    identical(ccr_to_date(c("2026-05", "2026-06"), "ym"),
              as.Date(c("2026-05-31", "2026-06-30"))))
chk("B4b kind='ym_compact' → 그 달 말일 (윤년 2월 포함)",
    identical(ccr_to_date(c("202402", "202612"), "ym_compact"),
              as.Date(c("2024-02-29", "2026-12-31"))))
YM_REL <- .wp(data.table(data_ym = c("2026-04", "2026-05"), v = c(1, 2)),
              file.path(TMP_REL, "ym_axis.parquet"))
b5 <- .audit1(.entry(YM_REL, date_col = "data_ym", date_col_kind = "ym",
                     date_semantics = "period_end", schedule = "monthly",
                     max_lag_days = 75L))
chk("B5 ym 문자열 축이 내용 기준 lag 을 산출 (2026-05 → 05-31 → 56d)",
    !is.null(b5) && identical(as.integer(b5$data_lag), 56L) &&
      identical(b5$lag_basis, "content"),
    sprintf("data_lag=%s basis=%s", b5$data_lag %||% "?", b5$lag_basis %||% "?"))

b6 <- ccr_coverage_check(SPEC, data = data.table(bsns_year = c(2026L, 2026L),
                                                 corp = c("C1", "C2")), today = TODAY)
chk("B6 기대 라벨이 데이터 시작 이전 = NO_EXPECTATION (백필 범위 밖 오탐 금지)",
    identical(b6$status, "COVERAGE_PASS") &&
      identical(b6$groups[[1]]$status, "NO_EXPECTATION"),
    sprintf("status=%s group=%s", b6$status, b6$groups[[1]]$status %||% "NA"))

# label_pattern (fundamental_merged 의 Period='YYYYMM' → 연간 코호트만)
lp_dt <- rbindlist(list(
  data.table(Period = "202312", Ticker = sprintf("T%04d", 1:100)),
  data.table(Period = "202406", Ticker = sprintf("T%04d", 1:900)),   # 분기 — 무시돼야
  data.table(Period = "202412", Ticker = sprintf("T%04d", 1:100)),
  data.table(Period = "202512", Ticker = sprintf("T%04d", 1:99))))
b7 <- ccr_coverage_check(list(label_col = "Period", entity_col = "Ticker",
                              label_pattern = "^([0-9]{4})12$",
                              due_rule = list(years = 1L, md = "03-31"),
                              grace_days = 45L, min_ratio_vs_prior = 0.8),
                         data = lp_dt, today = TODAY)
chk("B7 label_pattern 이 연간 코호트만 집계 (202406 무시, 99/100 PASS)",
    identical(b7$status, "COVERAGE_PASS") &&
      identical(as.integer(b7$groups[[1]]$n_expected), 99L) &&
      identical(as.integer(b7$groups[[1]]$n_reference), 100L),
    sprintf("n_exp=%s n_ref=%s", b7$groups[[1]]$n_expected %||% "NA",
            b7$groups[[1]]$n_reference %||% "NA"))

cat("\n=== C. 크래시 내성 (감시기는 죽으면 안 된다) ===\n")

c1 <- ccr_coverage_check(SPEC, path = file.path(TMP_ABS, "nonexistent.parquet"), today = TODAY)
chk("C1 파일 부재 = COVERAGE_UNKNOWN/WARN (에러 아님)",
    identical(c1$status, "COVERAGE_UNKNOWN") && identical(c1$severity, "WARN"))
c2 <- ccr_coverage_check(SPEC, data = data.table(wrong_col = 1:3), today = TODAY)
chk("C2 컬럼 부재 = COVERAGE_UNKNOWN/WARN",
    identical(c2$status, "COVERAGE_UNKNOWN") && identical(c2$severity, "WARN"))
c3 <- ccr_coverage_check(SPEC, data = data.table(bsns_year = integer(0), corp = character(0)),
                         today = TODAY)
chk("C3 0행 = NO_DATA (판정 제외, 죽지 않음)",
    identical(c3$groups[[1]]$status, "NO_DATA"),
    sprintf("status=%s", c3$status))
# ★C4 는 실제로 결함을 잡아낸 케이스다 (2026-07-26): as.Date(<character>) 는 기본 경로에서
#   잘못된 값에 error 를 던져(warning 아님) 감사 전체를 죽였다 — date_col 문자열 컬럼에
#   이상값 1건이면 감시기 사망. 그래서 "NA 인가"가 아니라 "던지지 않는가"까지 본다.
.no_throw <- function(expr) !inherits(tryCatch(force(expr), error = function(e) e), "error")
chk("C4 kind='ym' 파싱 불가/불가능한 월 = NA, 예외 없음",
    .no_throw(ccr_to_date(c("not-a-date", "2026-13"), "ym")) &&
      all(is.na(ccr_to_date(c("not-a-date", "2026-13"), "ym"))))
chk("C4b kind='date' 문자열 이상값 혼입 = 정상값 보존 + 이상값만 NA, 예외 없음",
    .no_throw(ccr_to_date(c("2026-07-24", "garbage", "2026-02-30"), "date")) &&
      identical(ccr_to_date(c("2026-07-24", "garbage", "2026-02-30"), "date"),
                as.Date(c("2026-07-24", NA, NA))))
chk("C4c ccr_lag_days 도 이상 문자열에 예외 없이 NA",
    .no_throw(ccr_lag_days("garbage", TODAY)) && is.na(ccr_lag_days("garbage", TODAY)))
chk("C5 ccr_lag_days 길이/NA 방어",
    is.na(ccr_lag_days(as.Date(NA), TODAY)) &&
      is.na(ccr_lag_days(as.Date(character(0)), TODAY)))
c6 <- .audit1(.entry(file.path(TMP_REL, "no_such_dir") , file_pattern = "^x_[0-9]{6}\\.parquet$",
                     date_col = "Date"))
chk("C6 디렉토리 부재 = MISSING/CRITICAL",
    !is.null(c6) && identical(c6$status, "MISSING"),
    sprintf("status=%s", c6$status %||% "?"))

cat("\n=== D. 차단 실효 (판정부를 무력화하면 A 가 통과로 뒤집히는가) ===\n")
# 무력화 사본: ccr_lag_days 가 항상 0 을 반환 = "지연을 못 보는" 상태.
# A1/A3 가 이 사본에서 통과(=못 잡음)로 뒤집혀야, 그 케이스들이 실제로 무언가를 재고
# 있다는 뜻이다. 뒤집히지 않으면 케이스가 공허하다는 신호.
mut_src <- readLines(REACH_SRC, warn = FALSE)
mut_path <- file.path(TMP_ABS, "mutated_reach.R")
writeLines(c(mut_src, "ccr_lag_days <- function(last_date, today, semantics = 'observation') 0L"),
           mut_path)
mut_env <- new.env(parent = globalenv())
suppressMessages(suppressWarnings(sys.source(mut_path, envir = mut_env)))

canon_a1 <- ccr_lag_days(as.Date("2026-07-03"), TODAY, "observation")
mut_a1   <- mut_env$ccr_lag_days(as.Date("2026-07-03"), TODAY, "observation")
chk("D1 정본은 A1 동결을 23d 로 잰다",  identical(as.integer(canon_a1), 23L),
    sprintf("canon=%s", canon_a1))
chk("D1b 무력화판은 0d → A1 이 FRESH 로 뒤집힘 (케이스가 공허하지 않음을 실증)",
    identical(as.integer(mut_a1), 0L) && canon_a1 > 14L && mut_a1 <= 14L,
    sprintf("mut=%s", mut_a1))
canon_a3 <- ccr_lag_days(as.Date("2026-01-31"), TODAY, "observation")
chk("D1c A3 도 동일하게 뒤집힘 (177d → 0d)",
    canon_a3 > 7L && mut_env$ccr_lag_days(as.Date("2026-01-31"), TODAY, "observation") <= 7L,
    sprintf("canon=%s", canon_a3))

# min_ratio 무력화 → A4 통과로 뒤집힘
d2 <- ccr_coverage_check(modifyList(SPEC, list(min_ratio_vs_prior = 0)),
                         data = mk_cohort(7), today = TODAY)
chk("D2 min_ratio=0 이면 A4 가 통과 (문턱이 실제로 판정을 가르고 있음)",
    identical(d2$status, "COVERAGE_PASS") && identical(a4$status, "COVERAGE_FAIL"),
    sprintf("neutered=%s canonical=%s", d2$status, a4$status))

# grace 무력화 → 기대 라벨이 뒤로 밀려 결손이 안 보임
d3 <- ccr_coverage_check(modifyList(SPEC, list(grace_days = 400L)),
                         data = mk_cohort(7), today = TODAY)
chk("D3 grace 과대(400d)면 기대 라벨이 2024 로 밀려 결손 은폐 — grace 가 판정을 가름",
    identical(as.integer(d3$groups[[1]]$expected_label), 2024L) &&
      !identical(d3$status, "COVERAGE_FAIL"),
    sprintf("expected=%s status=%s", d3$groups[[1]]$expected_label %||% "NA", d3$status))

chk("D4 정본 소스 불변 (사본만 변조했는가)",
    identical(unname(tools::md5sum(REACH_SRC)), REACH_MD5_BEFORE) &&
      identical(unname(tools::md5sum(AUDIT_SRC)), AUDIT_MD5_BEFORE))

cat("\n=== E. 규약·배선 (선언이 실재하고 소비처가 살아 있는가) ===\n")

reg <- jsonlite::fromJSON(REG_PATH, simplifyVector = FALSE)
sched <- Filter(function(c) !identical(c$schedule, "on_demand") && !is.null(c$max_lag_days),
                reg$caches)
undecl <- Filter(function(c) identical(ccr_reach_declaration(c), "undeclared"), sched)
chk("E1 정본 registry: 스케줄 갱신 대상 중 도달 축 미선언 0건",
    length(undecl) == 0L,
    sprintf("미선언 %d건: %s", length(undecl),
            paste(vapply(undecl, function(c) c$path, character(1)), collapse = ", ")))

# P2-02/P2-03 이 지목한 지점들이 실제로 선언됐는지 (회귀 고정)
must <- c(".cache/factor_db/", ".cache/fundamental_dart.parquet",
          ".cache/dart/dart_raw_financials.parquet", ".cache/dart/dart_raw_quarterly.parquet",
          ".cache/fundamental_merged.parquet")
by_path <- setNames(reg$caches, vapply(reg$caches, function(c) c$path, character(1)))
miss <- must[!vapply(must, function(p) {
  e <- by_path[[p]]
  !is.null(e) && ccr_reach_declaration(e) %in% c("date_col", "coverage_check")
}, logical(1))]
chk("E2 P2-02/03 지목 5개 지점이 date_col 또는 coverage_check 보유",
    length(miss) == 0L, sprintf("미충족: %s", paste(miss, collapse = ", ")))

chk("E3 factor_db 는 date_col='Date' (파일명 추정 fallback 이탈)",
    identical(by_path[[".cache/factor_db/"]]$date_col, "Date"))

# coverage_check 스펙 필수 키
cov_entries <- Filter(function(c) !is.null(c$coverage_check), reg$caches)
cov_bad <- Filter(function(c) {
  s <- c$coverage_check
  is.null(s$label_col) || is.null(s$entity_col) || is.null(s$due_rule)
}, cov_entries)
chk("E4 모든 coverage_check 선언이 필수 키(label_col/entity_col/due_rule) 보유",
    length(cov_entries) > 0L && length(cov_bad) == 0L,
    sprintf("cov=%d bad=%d", length(cov_entries), length(cov_bad)))

# 소비처 배선 — audit 이 reach 판정부를 부르고 주입 인자를 노출하는가
au <- paste(readLines(AUDIT_SRC, warn = FALSE), collapse = "\n")
chk("E5 audit 이 cache_content_reach.R 을 source 하고 ccr_* 를 호출",
    grepl("cache_content_reach\\.R", au) && grepl("ccr_coverage_check", au) &&
      grepl("ccr_to_date", au) && grepl("ccr_reach_declaration", au))
fm <- names(formals(cache_freshness_audit))
chk("E6 audit 이 주입 인자(caches_override/today/persist) 노출 — 검사 가능성 자체의 회귀 가드",
    all(c("caches_override", "today", "persist") %in% fm),
    sprintf("formals=%s", paste(fm, collapse = ",")))

cleanup()
chk("E7 임시 산출물 정리 (정본 트리 오염 없음)",
    !dir.exists(TMP_ABS) &&
      length(Sys.glob(file.path(PROJ, ".cache", "_test_ccr_*"))) == 0L,
    sprintf("잔재 %d건", length(Sys.glob(file.path(PROJ, ".cache", "_test_ccr_*")))))

cat(sprintf("\n%s\n", strrep("=", 60)))
cat(sprintf("cache_content_reach: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "cache_content_reach", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n")
if (FAIL > 0L) quit(status = 1L)
