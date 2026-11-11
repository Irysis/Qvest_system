# 판 2 구축 S2 — 시드 엔진 스케줄 절(6절)만 떼어 실제 거래일 달력으로 구판 · 후보판을 대조한다(GPU · 학습 없음 · 날짜 · 번호만).
#   사용: Rscript sched_test.R <구판 engine.R> <후보판 engine.R>
suppressMessages(library(data.table))
a <- commandArgs(TRUE); OLD <- a[1]; NEW <- a[2]
root <- "G:/OneDrive/Quant_Module_Moltbot"
cal_all <- sort(unique(as.Date(arrow::read_parquet(file.path(root, ".cache/rawdata.parquet"), col_select = "Date")$Date)))
n_ok <- 0L; n_bad <- 0L
ck <- function(cond, msg) { if (isTRUE(cond)) { n_ok <<- n_ok + 1L; cat("  OK   ", msg, "\n") } else { n_bad <<- n_bad + 1L; cat("  FAIL ", msg, "\n") } }

sched <- function(path, start) {
  L <- readLines(path, warn = FALSE, encoding = "UTF-8")
  const <- L[grepl("^\\.(HORIZON|N_TRAIN|UPD_EVERY|ANCHOR|GRID_FROM|SEED_BASE|K_REF_MI)\\s*<-", L)]
  i <- grep("^\\.CAL\\[, MI := year\\(Date\\)", L)[1]; j <- grep("^\\.PANEL_FROM_I <-", L)[1]
  stopifnot(!is.na(i), !is.na(j), j > i)
  body <- L[i:(j - 1L)]
  body <- body[!grepl("^if \\(nrow\\(\\.SCH\\) < 12L\\)", body)]
  e <- new.env()
  eval(parse(text = const, encoding = "UTF-8"), e)
  e$.TAG <- "[sched_test]"; e$.START <- as.Date(start)
  cal <- cal_all[cal_all >= e$.GRID_FROM]
  e$.CAL <- data.table(Date = cal, di = seq_along(cal))
  r <- tryCatch({ suppressWarnings(eval(parse(text = body, encoding = "UTF-8"), e)); NULL }, error = function(err) conditionMessage(err))
  list(err = r, sch = if (is.null(r)) copy(e$.SCH) else NULL, n_pre = e$.n_pre_anchor)
}
cols <- c("MI", "Date", "pred_i", "u_i", "smax_i", "smin_i", "k", "seed")
same <- function(x, y) nrow(x) == nrow(y) && all(vapply(cols, function(cn) identical(x[[cn]], y[[cn]]), logical(1)))

o05 <- sched(OLD, "2005-01-01"); n05 <- sched(NEW, "2005-01-01")
ck(is.null(o05$err) && is.null(n05$err) && same(o05$sch, n05$sch),
   sprintf("S1 기본 시작(2005-01-01) — 구판과 스케줄 비트 동일(%d개월 · 첫 달 %s · k %d~%d)", nrow(n05$sch), format(min(n05$sch$Date)), min(n05$sch$k), max(n05$sch$k)))
ck(identical(n05$sch$k, seq_len(nrow(n05$sch))), "S2 기본 시작에서 k = 1..N(달력 기준 번호가 종전 순번과 같다 — 빠진 달 없음)")

o00 <- sched(OLD, "2000-01-01"); n00 <- sched(NEW, "2000-01-01")
ck(!is.null(o00$err), sprintf("S3 구판은 시작 2000-01-01 에서 멈춘다 — 결함 재현(%s)", substr(o00$err %||% "오류 없음", 1, 90)))
ck(is.null(n00$err) && nrow(n00$sch) > nrow(n05$sch), sprintf("S4 후보판은 시작 2000-01-01 에서 스케줄을 만든다(%d개월 · 첫 달 %s · 앵커 전 제외 %s)",
                                                         if (is.null(n00$err)) nrow(n00$sch) else 0L, if (is.null(n00$err)) format(min(n00$sch$Date)) else "-", n00$n_pre %||% "?"))
if (is.null(n00$err)) {
  ov <- n00$sch[Date >= as.Date("2005-01-01")]
  ck(same(ov, n05$sch), sprintf("S5 겹치는 달(2005-01 이후 %d개월)은 시작일과 무관하게 창 · 번호 · 시드가 같다", nrow(ov)))
  ear <- n00$sch[Date < as.Date("2005-01-01")]
  ck(nrow(ear) > 0L && all(ear$k <= 0L) && all(ear$smin_i >= 1L) && !anyDuplicated(n00$sch$seed),
     sprintf("S6 앞당겨진 달 %d개(%s ~ %s) = k ≤ 0 · 학습창이 격자 안 · 시드 중복 없음", nrow(ear), format(min(ear$Date)), format(max(ear$Date))))
  ck(all(n00$sch$u_i <= n00$sch$pred_i) && all(n00$sch$smax_i == n00$sch$u_i - 5L) && all(n00$sch$smax_i - n00$sch$smin_i + 1L == 1000L),
     "S7 PIT 창 불변식 — 갱신점 ≤ 신호일 · 학습창 끝 = 갱신점 − 5 · 길이 1,000")
}
cat(sprintf("[sched_test] 통과 %d · 실패 %d\n", n_ok, n_bad))
quit(status = if (n_bad) 1L else 0L)
