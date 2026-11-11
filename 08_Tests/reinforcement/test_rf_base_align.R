#!/usr/bin/env Rscript
# test_rf_base_align.R — 기저 신호 달 스냅(rf_base_align.R) 단위 시험 (2026-11-11 · 판 2 구축 S1)
#   합성 달력 · 합성 패널만 쓴다(실자료 · 성과 없음). 실패 1건이라도 있으면 종료 코드 1.
suppressMessages(library(data.table))
root <- Sys.getenv("QM_TEST_ROOT", "")
if (!nzchar(root)) {
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  root <- if (length(f)) file.path(dirname(f[1]), "..", "..") else "."
}
src <- file.path(root, "02_Infrastructure", "reinforcement", "rf_base_align.R")
stopifnot(file.exists(src))
source(src)

n_ok <- 0L; n_bad <- 0L
ck <- function(cond, msg) { if (isTRUE(cond)) n_ok <<- n_ok + 1L else { n_bad <<- n_bad + 1L; cat("  FAIL:", msg, "\n") } }

## 합성 거래일 달력 — 평일(2000-01-03 ~ 2003-12-31)
all_d <- seq(as.Date("2000-01-03"), as.Date("2003-12-31"), by = "day")
cal <- all_d[!format(all_d, "%u") %in% c("6", "7")]
me <- cal[!duplicated(format(cal, "%Y%m"), fromLast = TRUE)]
mk <- function(dates, n = 5L) rbindlist(lapply(seq_along(dates), function(i)
  data.table(Date = dates[i], Ticker = sprintf("T%02d", seq_len(n)), .base_sig = as.numeric(i * 100 + seq_len(n)))))
key <- function(x) { y <- copy(x); setorder(y, Date, Ticker); y }

## T1 월간 월말 격자 = 항등(비트 동일)
b1 <- mk(me[3:30]); r1 <- rf_base_month_snap(b1, cal)
ck(identical(key(r1$panel), key(b1)), "T1 월간 월말 격자 항등")
ck(r1$diag$n_moved == 0L && r1$diag$n_identity == 28L && r1$diag$n_superseded == 0L, "T1 진단(옮김 0)")

## T2 분기 월말 격자 = 항등 · 사이 달은 비어 있다(이월 없음)
q <- me[seq(3, 45, by = 3)]; b2 <- mk(q); r2 <- rf_base_month_snap(b2, cal)
ck(identical(key(r2$panel), key(b2)), "T2 분기 월말 격자 항등")
ck(uniqueN(r2$panel$Date) == length(q), "T2 사이 달 이월 없음")

## T3 60거래일 격자 — 신호마다 그 달(또는 다음 달) 월말로 · 신호 수 보존 · s <= d
e3 <- cal[seq(5, length(cal), by = 60)]; b3 <- mk(e3); r3 <- rf_base_month_snap(b3, cal)
d3 <- sort(unique(r3$panel$Date))
ck(all(d3 %in% me), "T3 목표는 전부 월말 거래일")
ck(length(d3) + r3$diag$n_dropped_tail + r3$diag$n_superseded == length(e3), "T3 신호 수 회계")
ck(r3$diag$n_cell_dates >= length(e3) - 1L, "T3 신호일 수 회복(월말 겹침 여부와 무관)")
ck(r3$diag$max_lag_td <= 23L, "T3 지연은 한 달 미만")
## 값 보존 — 목표 월말의 패널 값 = 그 달 구간 마지막 신호의 값
src3 <- vapply(d3, function(d) { lo <- max(c(me[me < d], as.Date("1900-01-01"))); max(e3[e3 > lo & e3 <= d]) }, numeric(1))
ok3 <- all(vapply(seq_along(d3), function(i) identical(r3$panel[Date == d3[i], .base_sig], b3[as.integer(Date) == src3[i], .base_sig]), logical(1)))
ck(ok3, "T3 값 = 구간 안 가장 늦은 신호")
ck(all(src3 <= as.integer(d3)), "T3 PIT — s <= d")

## T4 주간 격자 — 달마다 하나 · 그 달 마지막 주간 신호
e4 <- cal[format(cal, "%u") == "5"]; b4 <- mk(e4); r4 <- rf_base_month_snap(b4, cal)
d4 <- sort(unique(r4$panel$Date))
ck(length(d4) == length(me), "T4 달마다 하나")
ck(r4$diag$n_superseded == length(e4) - length(d4), "T4 덮인 신호 수")
last_fri <- vapply(d4, function(d) max(e4[e4 <= d]), numeric(1))
ck(all(vapply(seq_along(d4), function(i) identical(r4$panel[Date == d4[i], .base_sig], b4[as.integer(Date) == last_fri[i], .base_sig]), logical(1))), "T4 값 = 그 달 마지막 주간 신호")
ck(r4$diag$max_lag_td <= 4L, "T4 지연은 닷새 미만")

## T5 거래일이 아닌 신호일(그 달 마지막 거래일 뒤의 토요일) → 다음 달 월말(s <= d 유지)
sat <- as.Date("2001-06-30"); stopifnot(format(sat, "%u") == "6", !(sat %in% cal))
r5 <- rf_base_month_snap(mk(sat), cal)
ck(identical(unique(r5$panel$Date), me[format(me, "%Y%m") == "200107"]), "T5 비거래일 신호는 다음 달 월말로")

## T6 마지막 월말 뒤 신호 = 갈 곳 없음(빠진다)
r6 <- rf_base_month_snap(mk(c(me[10], max(cal) + 10L)), cal)
ck(r6$diag$n_dropped_tail == 1L && uniqueN(r6$panel$Date) == 1L, "T6 꼬리 신호 제외")

## T7 입력 불변
b7 <- mk(e3); h7 <- copy(b7); invisible(rf_base_month_snap(b7, cal)); ck(identical(b7, h7), "T7 입력 패널 불변")

## T8 형식 오류는 멈춘다
ck(inherits(tryCatch(rf_base_month_snap(data.table(Date = "2001-01-31", Ticker = "A", .base_sig = 1), cal), error = function(e) e), "error"), "T8 Date 형 아님 = 멈춤")

## T9 돌연변이(양성 대조) — '가장 늦은 신호' 대신 '가장 이른 신호'를 고르는 사본은 T4 를 통과하지 못해야 한다
txt <- readLines(src, warn = FALSE, encoding = "UTF-8")
hit <- grepl("s = s[.N]", txt, fixed = TRUE)
ck(sum(hit) == 1L, "T9 치환 대상 한 곳")
mut <- sub("s = s[.N]", "s = s[1L]", txt, fixed = TRUE)
tf <- tempfile(fileext = ".R"); writeLines(mut, tf, useBytes = TRUE)
en <- new.env(); sys.source(tf, envir = en)
m4 <- en$rf_base_month_snap(b4, cal)
ck(!all(vapply(seq_along(d4), function(i) identical(m4$panel[Date == d4[i], .base_sig], b4[as.integer(Date) == last_fri[i], .base_sig]), logical(1))), "T9 돌연변이 검출")

cat(sprintf("[test_rf_base_align] 통과 %d · 실패 %d\n", n_ok, n_bad))
if (n_bad > 0L) quit(status = 1L)
