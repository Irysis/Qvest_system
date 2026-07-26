#==============================================================================
# test_cache_freshness_worse_of.R — cache_freshness_audit worse-of lag 위반 주입 테스트
#
# 목적(2026-07-26 CFA-02/CFA-04 수리의 가드): 신선도 판정이 mtime 축을 버리지 않는지,
#   일부러 병리 픽스처를 만들어 확인한다.
#
# 배경: 구현은 주석에 "Pick worse of mtime_lag and data_lag" 라고 써 놓고도
#   `lag <- if (!is.na(data_lag)) data_lag else mtime_lag` 로 **mtime 을 무조건 버렸다**.
#   그 결과 (a) forward-dated 캐시(예측 지평이 미래 날짜 → data_lag 음수)와
#   (b) 파일명-추정 data_lag=0 캐시는 **생성기가 죽어 파일이 동결돼도 FRESH** 로 보고됐다.
#   동결을 보여주는 유일한 축이 mtime 인데 그것이 폐기되는 구조였다.
#   실측 확정(2026-07-26): macro_regime data_lag=-5/mtime 0 · factor_db data_lag=0/mtime 1.
#
# ★위반 주입 방식: registry 를 건드리지 않고 caches_override 로 합성 캐시를 넣고,
#   Sys.setFileTime 으로 mtime 을 과거로 밀어 "내용은 신선한데 파일은 동결" 상태를 만든다.
#   구판 로직(data_lag 단독)이면 OK 로 통과하고, worse-of 면 WARN/CRITICAL 이 된다 —
#   즉 이 테스트는 수리가 살아 있을 때만 통과한다(수리를 되돌리면 T1/T2 가 즉시 깨진다).
#   persist=FALSE 라 정본 산출물(observability/로그/알림상태)을 오염시키지 않는다.
#
# 요약 규약: 마지막 줄 {"test":"cache_freshness_worse_of","pass":N,"fail":N,"total":N}
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite); library(arrow); library(data.table)
})

# ── PROJECT_ROOT: 표지 검증 (r-portability 금칙 ③④ — 존재≠정체, CPD 우선) ──────
.MARKER <- "02_Infrastructure/data/cache_freshness_audit.R"
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m) == 0L) return("")
  dirname(sub("^--file=", "", m[1L]))
}
.sd <- .script_dir()
PROJECT_ROOT <- ""
for (.c in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (nzchar(.sd)) file.path(.sd, "..", "..") else "", getwd())) {
  if (nzchar(.c) && file.exists(file.path(.c, .MARKER))) { PROJECT_ROOT <- .c; break }
}
if (!nzchar(PROJECT_ROOT))
  stop(sprintf("[test_cache_freshness_worse_of] PROJECT_ROOT 해석 실패 — 표지 '%s' 부재", .MARKER))

source(file.path(PROJECT_ROOT, .MARKER))

PASS <- 0L; FAIL <- 0L; out <- character()
ok  <- function(n) { PASS <<- PASS + 1L; out <<- c(out, sprintf("  PASS  %s", n)) }
bad <- function(n, d) { FAIL <<- FAIL + 1L; out <<- c(out, sprintf("  FAIL  %s  (%s)", n, d)) }
chk <- function(n, expect, actual) {
  if (identical(as.character(expect), as.character(actual))) ok(n)
  else bad(n, sprintf("expect=%s actual=%s", expect, actual))
}

TODAY <- as.Date("2026-07-26")            # 결정성: today 주입
FXDIR <- file.path(PROJECT_ROOT, ".cache", "_test_fx_freshness")   # .cache = gitignore
unlink(FXDIR, recursive = TRUE)                        # 이전 실행 잔재 제거(멱등)
dir.create(FXDIR, recursive = TRUE, showWarnings = FALSE)
# ★top-level on.exit() 금지 — r-portability 금칙 ②: 스크립트 최상위 on.exit 는 **발화하지
#   않아** cleanup 이 dead code 가 된다(초판이 정확히 이 함정을 밟아 test_r_portability 가 적발).
#   모든 종료 경로에서 명시 호출한다.
.cleanup <- function() unlink(FXDIR, recursive = TRUE)

# 픽스처 1개 생성: 내용 max(Date) = content_date, 파일 mtime = TODAY - mtime_age_days
mk_fx <- function(name, content_date, mtime_age_days) {
  p <- file.path(FXDIR, name)
  write_parquet(data.table(Date = as.Date(content_date) - c(2, 1, 0),
                           v = c(1, 2, 3)), p)
  tt <- as.POSIXct(TODAY - mtime_age_days, tz = "UTC")
  Sys.setFileTime(p, tt)
  file.path(".cache", "_test_fx_freshness", name)     # PROJECT_ROOT 상대경로
}

# registry 엔트리 (schedule="weekly" → tight-SLA daily 거래일 분기 회피 = 결정성)
entry <- function(rel, max_lag) {
  list(path = rel, tier = "test", schedule = "weekly", max_lag_days = max_lag,
       date_col = "Date", date_col_kind = "date", date_semantics = "observation")
}

run_audit <- function(caches) {
  cache_freshness_audit(telegram_alert = FALSE, caches_override = caches,
                        today = TODAY, persist = FALSE)
}
# ★audit$results 는 **무명 리스트**다(2026-07-26 실측 — 이름으로 [[rel]] 조회하면 조용히
#   NULL 이 나오고, 그 NULL 을 비교하면 테스트가 통과/실패 대신 에러로 죽는다).
#   path 필드로 찾는다 — 스키마가 이름 부여로 바뀌어도 안전.
get_res <- function(a, rel) {
  for (r in a$results) if (identical(r$path, rel)) return(r)
  stop(sprintf("get_res: 결과에 '%s' 없음 (results n=%d) — 픽스처/키 규약 확인", rel,
               length(a$results)))
}
# 길이 0/NULL 을 NA 로 정규화 — `if (x < 0)` 가 에러로 죽는 대신 FAIL 로 잡히게
n1 <- function(v) if (length(v) != 1L) NA_real_ else suppressWarnings(as.numeric(v))

cat("=== test_cache_freshness_worse_of (worse-of lag 위반 주입) ===\n")

#──────────────────────────────────────────────────────────────────────────────
# T1 ★위반 주입 — 내용은 신선(1일)인데 파일이 20일 동결. max_lag=7
#    구판(data_lag 단독): lag=1 → OK  /  worse-of: lag=20 → CRITICAL(>2×7)
#──────────────────────────────────────────────────────────────────────────────
r1 <- mk_fx("frozen_fresh_content.parquet", TODAY - 1, 20)
a1 <- run_audit(list(entry(r1, 7)))
x1 <- get_res(a1, r1)
chk("T1 data_lag=1 (내용은 신선)",        1,  x1$data_lag)
chk("T1 mtime_lag=20 (파일 동결)",       20,  x1$mtime_lag)
chk("T1 ★lag_used=20 (mtime 채택)",     20,  x1$lag_used)
chk("T1 ★severity=CRITICAL (구판은 OK)", "CRITICAL", x1$severity)
if (!is.null(x1$lag_note_worse_of)) ok("T1 채택축 note 발행") else
  bad("T1 채택축 note 발행", "lag_note_worse_of 부재")

#──────────────────────────────────────────────────────────────────────────────
# T2 ★위반 주입 — forward-dated(내용 max Date = TODAY+5 → data_lag 음수), 파일 10일 동결
#    구판: lag=-5 → OK  /  worse-of: 음수 0-clamp 후 max(10,0)=10 → WARN(>7, ≤14)
#──────────────────────────────────────────────────────────────────────────────
r2 <- mk_fx("forward_dated.parquet", TODAY + 5, 10)
a2 <- run_audit(list(entry(r2, 7)))
x2 <- get_res(a2, r2)
if (isTRUE(n1(x2$data_lag) < 0)) ok("T2 data_lag 음수(예측 지평 재현)") else
  bad("T2 data_lag 음수(예측 지평 재현)", sprintf("data_lag=%s", format(n1(x2$data_lag))))
chk("T2 ★lag_used=10 (음수 clamp + mtime 채택)", 10, x2$lag_used)
chk("T2 ★severity=WARN (구판은 OK)",     "WARN", x2$severity)

#──────────────────────────────────────────────────────────────────────────────
# T3 회귀 가드 — 정상 케이스(내용 3일 지연, 파일은 오늘 갱신)에서 판정이 바뀌지 않는가.
#    max() 가 정상 케이스를 엄격하게 만들면 전 캐시가 false-WARN 이 된다.
#──────────────────────────────────────────────────────────────────────────────
r3 <- mk_fx("normal.parquet", TODAY - 3, 0)
a3 <- run_audit(list(entry(r3, 7)))
x3 <- get_res(a3, r3)
chk("T3 lag_used=3 (data 축 유지)", 3, x3$lag_used)
chk("T3 severity=OK (false-WARN 없음)", "OK", x3$severity)
if (is.null(x3$lag_note_worse_of)) ok("T3 정상 케이스엔 note 미발행") else
  bad("T3 정상 케이스엔 note 미발행", "note가 붙었다 = 과잉 발화")

#──────────────────────────────────────────────────────────────────────────────
# T4 동률 케이스 — mtime==data 면 note 없이 동일 값 (경계 오프바이원 방어)
#──────────────────────────────────────────────────────────────────────────────
r4 <- mk_fx("tie.parquet", TODAY - 5, 5)
a4 <- run_audit(list(entry(r4, 7)))
x4 <- get_res(a4, r4)
chk("T4 lag_used=5 (동률)", 5, x4$lag_used)
if (is.null(x4$lag_note_worse_of)) ok("T4 동률엔 note 미발행") else
  bad("T4 동률엔 note 미발행", "strict > 비교가 아니다")

#──────────────────────────────────────────────────────────────────────────────
# T5 persist=FALSE 계약 — 검사가 감시 대상(정본 산출물)을 건드리면 증거가 아니다
#──────────────────────────────────────────────────────────────────────────────
lp <- file.path(PROJECT_ROOT, "qepm/observability/cache_freshness_latest.json")
before <- if (file.exists(lp)) file.info(lp)$mtime else NA
invisible(run_audit(list(entry(r3, 7))))
after <- if (file.exists(lp)) file.info(lp)$mtime else NA
chk("T5 persist=FALSE 시 정본 latest 미변경", TRUE, identical(before, after))

.cleanup()

cat(paste(out, collapse = "\n"), "\n\n")
cat(sprintf("PASS=%d FAIL=%d\n", PASS, FAIL))
cat(sprintf('{"test":"cache_freshness_worse_of","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
