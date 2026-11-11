#!/usr/bin/env Rscript
#==============================================================================
# test_scn_data_freshness_session.R — 신선도 감사의 '거래 세션 지연' 축 시나리오 시험 (감사 레인 A · 2026-11-10)
#
# 사고: 11-10(화) RAWDATA 최신 11-06(금) · as_of 11-09(월). 달력 lag 3d ≤ max 3d → FRESH 로 판정돼
#   ① daily_refresh [0c] '전 소스 FRESH' ② ensure_data_current 사후 감사 'refreshed_current'(refresh rc=1 인데도) 로 침묵했다.
#   같은 날 셀 단위 감사(cache_freshness_audit)는 같은 파일을 STALE_CRITICAL. 11-09 세션이 통째로 빠졌다.
# 대상 = 02_Infrastructure/ops/morning_steps/freshness_audit.R (운영 파일 · --audit 로 바꿀 수 있다)
# 방법 = 모래상자 루트(합성 parquet · 휴장일 등록부 사본 · config/telegram 스텁)에서 감사기를 **새 Rscript 프로세스**로 돌린다
#   (R_ENVIRON_USER = 빈 파일 · QM_ROOT = 모래상자 · 첫 줄에서 루트 단정). 오늘 날짜는 래퍼가 globalenv 의 Sys.Date 로 가린다.
# 시나리오:
#   S1 정상 — RAWDATA · 벤치가 as_of 에 도달 → FRESH · sess 0
#   S2 주말 낀 한 세션 누락(11-10 사고 재현) → STALE (구판 = FRESH — 수리 전 동작을 HEAD 판으로 함께 잰다)
#   S3 긴 연휴(2025 추석 · 한글날 — 10-03 · 10-06~10-09 휴장) — today 10-10 · RAWDATA 10-02 → FRESH(거짓 양성 없음)
#   S4 휴장일 등록부 없음 → 세션 축 미측정(NA) · 달력 축 판정 유지(기존 동작)
#   S5 돌연변이 — 세션 비교를 무력화한 사본은 S2 에서 FRESH(검사가 그 줄을 실제로 본다)
#   S6 EDC_RESULT 줄에 rawdata 가 실린다(ensure_data_current.sh 가 읽는 유일한 줄)
# 부작용: 없음 — 쓰기는 tempdir 뿐 · 운영 .cache · 06_Registry 무접촉 · 텔레그램 스텁 · QVEST_FRESHNESS_QUIET=1
# 요약: 마지막 줄 {"test":"scn_data_freshness_session","pass":N,"fail":N,"total":N}
#==============================================================================
suppressPackageStartupMessages({ library(arrow); library(jsonlite) })
T_NAME <- "scn_data_freshness_session"
.MARK <- "02_Infrastructure/hooks/qvest_hook_router.py"
.self <- function() { a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)]); if (!length(f)) return("")
  f <- gsub("\\\\", "/", f[1]); if (grepl("^([A-Za-z]:)?/", f)) f else file.path(gsub("\\\\", "/", getwd()), f) }
ROOT <- ""
.s <- .self()
if (nzchar(.s)) { r <- dirname(dirname(dirname(.s))); if (file.exists(file.path(r, .MARK))) ROOT <- r }
if (!nzchar(ROOT)) for (c in c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"))) if (nzchar(c) && file.exists(file.path(c, .MARK))) { ROOT <- gsub("\\\\", "/", c); break }
emit <- function(p, f) { cat(sprintf('{"test":"%s","pass":%d,"fail":%d,"total":%d}\n', T_NAME, p, f, p + f)); quit(status = if (f > 0) 1 else 0) }
if (!nzchar(ROOT)) { cat("preflight: 루트 없음\n"); emit(0L, 1L) }
args <- commandArgs(TRUE); ia <- match("--audit", args)
AUDIT <- if (!is.na(ia) && ia < length(args)) args[ia + 1] else file.path(ROOT, "02_Infrastructure/ops/morning_steps/freshness_audit.R")
HOL <- file.path(ROOT, "06_Registry/krx_holidays.json")
RS <- file.path(R.home("bin"), "Rscript")

PASS <- 0L; FAIL <- 0L
chk <- function(lbl, cond, det = "") { ok <- isTRUE(cond); if (ok) PASS <<- PASS + 1L else FAIL <<- FAIL + 1L
  cat(sprintf("  %s %s%s\n", if (ok) "ok  " else "FAIL", lbl, if (!ok && nzchar(det)) paste0(" — ", det) else "")) }

TMP <- gsub("\\\\", "/", tempfile("scn_fresh_")); dir.create(TMP)
invisible(reg.finalizer(globalenv(), function(e) unlink(TMP, recursive = TRUE, force = TRUE), onexit = TRUE))   # 최상위 on.exit 은 Rscript 에서 미발화(r-portability ②)
EMPTY_ENV <- file.path(TMP, "empty.Renviron"); writeLines("", EMPTY_ENV)

## 모래상자 하나 — today · 각 소스 최신일 · 달력 끝 · 휴장일 등록부 유무
mk_box <- function(tag, rawdata_last, bench_last, cal_to, with_hol = TRUE, src = AUDIT) {
  b <- file.path(TMP, tag); for (d in c(".cache", "02_Infrastructure/telegram", "02_Infrastructure/hooks", "06_Registry", "qepm/observability",
                                         "02_Infrastructure/ops/morning_steps"))
    dir.create(file.path(b, d), recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(b, .MARK))
  writeLines("invisible(NULL)", file.path(b, "02_Infrastructure/config.R"))
  writeLines(c("tg_send <- function(msg, ...) { cat('TG_STUB_SENT\\n'); TRUE }"), file.path(b, "02_Infrastructure/telegram/telegram_notify.R"))
  if (with_hol) file.copy(HOL, file.path(b, "06_Registry/krx_holidays.json"))
  hol <- as.Date(names(fromJSON(HOL)$holidays))
  days <- seq(as.Date("2025-09-01"), as.Date(cal_to), by = "day")
  sess <- days[!(format(days, "%u") %in% c("6", "7")) & !(days %in% hol)]
  write_parquet(data.frame(Date = sess), file.path(b, ".cache/trading_calendar.parquet"))
  pq <- function(p, last) write_parquet(data.frame(Date = sess[sess <= as.Date(last)], v = 1), file.path(b, p))
  pq(".cache/RAWDATA.parquet", rawdata_last); pq(".cache/benchmark.parquet", bench_last)
  file.copy(src, file.path(b, "02_Infrastructure/ops/morning_steps/freshness_audit.R"), overwrite = TRUE)
  b
}
run_box <- function(b, today) {
  w <- file.path(b, "run.R")
  writeLines(c(sprintf('stopifnot(identical(gsub("\\\\\\\\", "/", Sys.getenv("QM_ROOT")), "%s"))', b),   # 첫 줄 루트 단정
               sprintf('Sys.Date <- function() as.Date("%s")', today),
               sprintf('source("%s/02_Infrastructure/ops/morning_steps/freshness_audit.R", encoding = "UTF-8")', b)), w)   # 절대 경로 — 자식 cwd 는 운영 루트다
  ## Windows 의 system2(env=) 는 적용되지 않는다 — 부모 환경을 잠시 바꿔 자식에 물려주고 되돌린다
  old <- Sys.getenv(c("QM_ROOT", "R_ENVIRON_USER", "QVEST_FRESHNESS_QUIET", "CLAUDE_PROJECT_DIR"), unset = NA)
  Sys.setenv(QM_ROOT = b, R_ENVIRON_USER = EMPTY_ENV, QVEST_FRESHNESS_QUIET = "1", CLAUDE_PROJECT_DIR = b)
  out <- suppressWarnings(system2(RS, c("--no-save", shQuote(w)), stdout = TRUE, stderr = TRUE))
  for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k))
  js <- tryCatch(fromJSON(file.path(b, "qepm/observability/morning_freshness_latest.json"), simplifyVector = FALSE), error = function(e) NULL)
  list(out = out, js = js, edc = grep("^EDC_RESULT", out, value = TRUE))
}
st <- function(r, k) if (is.null(r$js)) "NO_JSON" else r$js$audits[[k]]$status %||% "?"

cat(sprintf("== %s — 대상 %s ==\n", T_NAME, AUDIT))
if (!file.exists(AUDIT) || !file.exists(HOL)) { cat("preflight: 대상 또는 휴장일 등록부 없음\n"); emit(0L, 1L) }

## S1 정상
r1 <- run_box(mk_box("s1", "2026-11-09", "2026-11-09", "2026-11-09"), "2026-11-10")
chk("S1 정상 · as_of = 2026-11-09", identical(r1$js$as_of, "2026-11-09"), paste(tail(r1$out, 3), collapse = " | "))
chk("S1 rawdata FRESH · sess 0", st(r1, "rawdata") == "FRESH" && identical(r1$js$audits$rawdata$sess_lag, 0L))
chk("S1 benchmark FRESH", st(r1, "benchmark") == "FRESH")

## S2 11-10 사고 재현 — RAWDATA 11-06 · 벤치 11-09
r2 <- run_box(mk_box("s2", "2026-11-06", "2026-11-09", "2026-11-09"), "2026-11-10")
chk("S2 rawdata STALE(세션 1 누락)", st(r2, "rawdata") == "STALE", st(r2, "rawdata"))
chk("S2 sess_lag = 1 · lag_days = 3", identical(r2$js$audits$rawdata$sess_lag, 1L) && identical(r2$js$audits$rawdata$lag_days, 3L))
chk("S6 EDC_RESULT 에 rawdata", length(r2$edc) == 1 && grepl("rawdata", r2$edc), paste(r2$edc, collapse = ""))
## 수리 전 동작(HEAD 판) — 같은 상자에서 FRESH 였음을 기록(사고 재현의 증거 · HEAD 판을 못 읽으면 건너뜀)
head_src <- file.path(TMP, "head_freshness_audit.R")
g <- suppressWarnings(system2("git", c("-C", shQuote(ROOT), "show", "HEAD:02_Infrastructure/ops/morning_steps/freshness_audit.R"), stdout = TRUE, stderr = FALSE))
if (length(g) > 20 && !any(grepl(".sess_lag <- function", g, fixed = TRUE))) {
  writeLines(g, head_src, useBytes = TRUE)
  r2h <- run_box(mk_box("s2h", "2026-11-06", "2026-11-09", "2026-11-09", src = head_src), "2026-11-10")
  chk("S2(수리 전 HEAD 판) rawdata FRESH — 침묵 재현", st(r2h, "rawdata") == "FRESH", st(r2h, "rawdata"))
} else cat("  skip S2-HEAD (HEAD 판에 이미 세션 축이 있거나 git 판독 불가)\n")

## S3 긴 연휴 — 2025 추석 · 한글날
r3 <- run_box(mk_box("s3", "2025-10-02", "2025-10-02", "2025-10-10"), "2025-10-10")
chk("S3 연휴 as_of = 2025-10-02", identical(r3$js$as_of, "2025-10-02"), r3$js$as_of %||% "?")
chk("S3 rawdata FRESH(연휴 거짓 양성 없음)", st(r3, "rawdata") == "FRESH" && identical(r3$js$audits$rawdata$sess_lag, 0L))
## S3b 연휴 중 달력이 연휴 직전까지만(퀀티 정지) — 직전 세션 2025-10-02 기준 sess 0 이면 FRESH, 하루 전 데이터면 STALE
r3b <- run_box(mk_box("s3b", "2025-10-01", "2025-10-02", "2025-10-10"), "2025-10-10")
chk("S3b 연휴 앞 한 세션 누락 → STALE", st(r3b, "rawdata") == "STALE", st(r3b, "rawdata"))

## S4 휴장일 등록부 없음 → 세션 축 NA · 달력 축만(기존 동작)
r4 <- run_box(mk_box("s4", "2026-11-06", "2026-11-09", "2026-11-09", with_hol = FALSE), "2026-11-10")
chk("S4 sess_lag NA(미측정)", { v <- r4$js$audits$rawdata$sess_lag; is.null(v) || identical(v, "NA") || is.na(unlist(v)[1]) },
    paste(deparse(r4$js$audits$rawdata$sess_lag), collapse = ""))
chk("S4 달력 축 판정 유지(FRESH)", st(r4, "rawdata") == "FRESH")

## S5 돌연변이 — 소스 텍스트 치환(정확히 1곳)
src <- readLines(AUDIT, encoding = "UTF-8", warn = FALSE)
pat <- "sess > max_sess) status <- \"STALE\""
n_hit <- sum(grepl(pat, src, fixed = TRUE))
chk("S5 치환 대상 정확히 1곳", n_hit == 1L, sprintf("hits=%d", n_hit))
if (n_hit == 1L) {
  mut <- file.path(TMP, "mut_freshness_audit.R")
  writeLines(sub(pat, "sess > max_sess + 99L) status <- \"STALE\"", src, fixed = TRUE), mut, useBytes = TRUE)
  chk("S5 치환 성사", !identical(readLines(mut, warn = FALSE), src))
  r5 <- run_box(mk_box("s5", "2026-11-06", "2026-11-09", "2026-11-09", src = mut), "2026-11-10")
  chk("S5 돌연변이는 S2 를 놓친다(FRESH) — 검사가 그 줄을 본다", st(r5, "rawdata") == "FRESH", st(r5, "rawdata"))
}
chk("텔레그램 스텁 미발화(QUIET)", !any(grepl("TG_STUB_SENT", c(r1$out, r2$out, r3$out, r4$out))))

## C 판정 전용 진입점(--check · 측정 경로 신선도 차단 계약) — 텔레그램 0 · JSON 0 · 종료 코드 0/3/1
run_check <- function(b, today, items, quiet = "0", src_override = NULL) {
  w <- file.path(b, "run_check.R")
  writeLines(c(sprintf('Sys.Date <- function() as.Date("%s")', today),
               sprintf('source("%s/02_Infrastructure/ops/morning_steps/freshness_audit.R", encoding = "UTF-8")', b)), w)
  old <- Sys.getenv(c("QM_ROOT", "R_ENVIRON_USER", "QVEST_FRESHNESS_QUIET", "CLAUDE_PROJECT_DIR"), unset = NA)
  Sys.setenv(QM_ROOT = b, R_ENVIRON_USER = EMPTY_ENV, QVEST_FRESHNESS_QUIET = quiet, CLAUDE_PROJECT_DIR = b)
  out <- suppressWarnings(system2(RS, c("--no-save", shQuote(w), "--check", "--items", items), stdout = TRUE, stderr = TRUE))
  for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k))
  list(rc = as.integer(attr(out, "status") %||% 0L), line = tail(grep("^FA_CHECK", out, value = TRUE), 1), out = out,
       json = file.exists(file.path(b, "qepm/observability/morning_freshness_latest.json")))
}
c1 <- run_check(mk_box("c1", "2026-11-06", "2026-11-09", "2026-11-09"), "2026-11-10", "rawdata,benchmark")
chk("C1 낡은 RAWDATA → 종료 3 · status=STALE · stale=rawdata", c1$rc == 3L && grepl("status=STALE", c1$line) && grepl("stale=rawdata\t", c1$line), paste(c1$rc, c1$line))
chk("C1b 부작용 없음 — JSON 미기록 · 텔레그램 0(QUIET 꺼도)", !c1$json && !any(grepl("TG_STUB_SENT", c1$out)))
c2 <- run_check(mk_box("c2", "2026-11-09", "2026-11-09", "2026-11-09"), "2026-11-10", "rawdata,benchmark")
chk("C2 최신 → 종료 0 · status=FRESH", c2$rc == 0L && grepl("status=FRESH", c2$line), paste(c2$rc, c2$line))
c3 <- run_check(mk_box("c3", "2026-11-09", "2026-11-09", "2026-11-09"), "2026-11-10", "rawdata,nosuch")
chk("C3 모르는 항목 → 종료 1 · ERROR", c3$rc == 1L && grepl("status=ERROR", c3$line) && grepl("nosuch", c3$line), paste(c3$rc, c3$line))
c4 <- run_check(mk_box("c4", "2026-11-09", "2026-11-09", "2026-11-09"), "2026-11-10", "consensus")
chk("C4 고른 항목 파일 없음(MISSING) → 종료 3", c4$rc == 3L, paste(c4$rc, c4$line))
pat2 <- "switch(.v, FRESH = 0L, STALE = 3L, 1L)"
if (sum(grepl(pat2, src, fixed = TRUE)) == 1L) {
  mut2 <- file.path(TMP, "mut2_freshness_audit.R"); writeLines(sub(pat2, "switch(.v, FRESH = 0L, STALE = 0L, 1L)", src, fixed = TRUE), mut2, useBytes = TRUE)
  c5 <- run_check(mk_box("c5", "2026-11-06", "2026-11-09", "2026-11-09", src = mut2), "2026-11-10", "rawdata")
  chk("C5 돌연변이(STALE → 0) 는 차단 신호를 잃는다", c5$rc == 0L, paste(c5$rc))
} else chk("C5 치환 대상 1곳", FALSE)
emit(PASS, FAIL)
