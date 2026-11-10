#!/usr/bin/env Rscript
#==============================================================================
# test_rf_cell_factor_direction.R — 셀 엔진의 팩터 방향 선택(v10.2 · 2026-11-10 팩터 DB 배선)
#   대상: 02_Infrastructure/reinforcement/rf_cell_engine.R 의 .load_factor(kind = "db")
#   본다: 방향 필드가 없으면 접근자 호출 모양이 종전과 같다(direction 인자를 넘기지 않는다) · registry · defensive 는 접근자 인자로 간다 ·
#         방어 방향이 등록부에 없는 팩터의 defensive 요구 · 어휘 밖 값은 멈춘다(조용히 빠지지 않는다).
#   (11-10) defensive_only(헌장 빈칸 15 · 방어 쪽이 아닌 달 기여 0) · B7 슬리브 처치 방향 배선 · 돌연변이 2.
#   방법: 엔진 소스에서 .load_factor 정의만 꺼내, 가짜 접근자(호출 기록) · 가짜 등록부가 든 임시 루트에서 부른다(엔진 본체 · 실데이터 무접촉).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)][1])
ROOT <- NA_character_
for (p in c(dirname(dirname(dirname(me))), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.na(p) || !nzchar(p)) next
  p <- gsub("\\\\", "/", p)
  if (file.exists(file.path(p, "02_Infrastructure", "reinforcement", "rf_cell_engine.R"))) { ROOT <- p; break }
}
if (is.na(ROOT)) stop("저장소 루트를 찾지 못했다")
pass <- 0L; fail <- 0L
chk <- function(name, cond) {
  ok <- isTRUE(tryCatch(cond, error = function(e) { cat("     오류:", conditionMessage(e), "\n"); FALSE }))
  if (ok) pass <<- pass + 1L else fail <<- fail + 1L
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", name))
}
src <- parse(file.path(ROOT, "02_Infrastructure", "reinforcement", "rf_cell_engine.R"), keep.source = FALSE)
def <- NULL
for (ex in src) if (is.call(ex) && identical(as.character(ex[[1]]), "<-") && identical(as.character(ex[[2]]), ".load_factor")) def <- ex
chk("T00 엔진 소스에서 .load_factor 정의를 찾았다", !is.null(def))

SB <- tempfile("rfdir_"); dir.create(file.path(SB, "02_Infrastructure/factor_db"), recursive = TRUE)
writeLines(c(
  "load_month_factors <- function(sig_date, coverage_min = 0.05, factor_names = NULL, dedup = FALSE, direction = 'ic_asof') {",
  "  CALLS[[length(CALLS) + 1L]] <<- list(date = as.character(sig_date), id = factor_names, supplied = !missing(direction), direction = direction)",
  "  data.frame(Ticker = c('A', 'B'), Z_Score_Aligned = c(1, -1))",
  "}"), file.path(SB, "02_Infrastructure/factor_db/factor_db_connector.R"))
writeLines(toJSON(list(D01_X = list(direction = "lower_better", direction_defensive = "higher_better"),
                       V01_Y = list(direction = "higher_better")), auto_unbox = TRUE),
           file.path(SB, "02_Infrastructure/factor_db/factor_registry.json"))
CALLS <- list()
W <- new.env(parent = globalenv())
assign(".RF_ROOT", SB, envir = W); assign(".sig_dates", as.Date(c("2020-01-31", "2020-02-28")), envir = W)
eval(def, W)
run <- function(fs) { CALLS <<- list(); W$.load_factor(fs, "f2") }

r0 <- run(list(kind = "db", id = "V01_Y"))
chk("T01 방향 필드가 없으면 접근자를 direction 인자 없이 부른다(종전 호출 모양 그대로) · 날짜마다 1회",
    length(CALLS) == 2L && !any(vapply(CALLS, function(z) z$supplied, logical(1))) && nrow(r0) == 4L && identical(names(r0), c("Date", "Ticker", "f2")))
r1 <- run(list(kind = "db", id = "V01_Y", direction = "ic_asof"))
chk("T02 direction = ic_asof 를 적어도 같은 호출 모양이다", !any(vapply(CALLS, function(z) z$supplied, logical(1))) && identical(r1, r0))
r2 <- run(list(kind = "db", id = "V01_Y", direction = "registry"))
chk("T03 direction = registry 는 접근자의 direction 인자로 간다", all(vapply(CALLS, function(z) z$supplied && identical(z$direction, "registry"), logical(1))) && nrow(r2) == 4L)
r3 <- run(list(kind = "db", id = "D01_X", direction = "defensive"))
chk("T04 direction = defensive — 등록부에 방어 방향이 있는 팩터는 접근자 인자로 간다", all(vapply(CALLS, function(z) identical(z$direction, "defensive"), logical(1))) && nrow(r3) == 4L)
e4 <- tryCatch({ run(list(kind = "db", id = "V01_Y", direction = "defensive")); "" }, error = function(e) conditionMessage(e))
chk("T05 방어 방향이 등록부에 없는 팩터에 defensive 를 요구하면 멈춘다(접근자 호출 0 — 조용히 빠지지 않는다)", grepl("direction_defensive", e4, fixed = TRUE) && length(CALLS) == 0L)
e5 <- tryCatch({ run(list(kind = "db", id = "V01_Y", direction = "flip")); "" }, error = function(e) conditionMessage(e))
chk("T06 어휘 밖 방향 값은 멈춘다(수동 반전 경로 없음)", grepl("어휘 밖", e5, fixed = TRUE) && length(CALLS) == 0L)
e6 <- tryCatch({ run(list(kind = "db", id = "NOPE", direction = "defensive")); "" }, error = function(e) conditionMessage(e))
chk("T07 등록부에 없는 팩터의 defensive 요구도 멈춘다", nzchar(e6))

## ── 방어 쪽 한정(defensive_only · 헌장 빈칸 15 · 2026-11-10) ─────────────────────────────────────────
##   가짜 접근자: defensive 보기 = (+1, −1) 고정 · ic_asof(기본 호출) = 1월은 같은 부호(+1, −1) · 2월은 반대(−1, +1) = 정렬이 방어 쪽이 아닌 달.
writeLines(c(
  "load_month_factors <- function(sig_date, coverage_min = 0.05, factor_names = NULL, dedup = FALSE, direction = 'ic_asof') {",
  "  CALLS[[length(CALLS) + 1L]] <<- list(date = as.character(sig_date), id = factor_names, supplied = !missing(direction), direction = direction)",
  "  z <- if (identical(direction, 'defensive') || format(as.Date(sig_date), '%m') == '01') c(1, -1) else c(-1, 1)",
  "  data.frame(Ticker = c('A', 'B'), Z_Score_Aligned = z)",
  "}"), file.path(SB, "02_Infrastructure/factor_db/factor_db_connector.R"))
r8 <- run(list(kind = "db", id = "D01_X", direction = "defensive_only"))
off8 <- attr(r8, "def_off_dates")
chk("T08 defensive_only — 값 열은 매달 방어 정렬 값(+1, −1) · 꺼진 달 = 정렬이 방어 쪽이 아닌 2월만(attr def_off_dates)",
    identical(r8$f2, c(1, -1, 1, -1)) && identical(off8, as.Date("2020-02-28")))
chk("T09 defensive_only — 접근자에는 defensive 와 기본(ic_asof) 호출만 간다(defensive_only 를 접근자에 넘기지 않는다 · 날짜마다 2회)",
    length(CALLS) == 4L && all(vapply(CALLS, function(z) (!z$supplied) || identical(z$direction, "defensive"), logical(1))) &&
      sum(vapply(CALLS, function(z) isTRUE(z$supplied), logical(1))) == 2L)
e10 <- tryCatch({ run(list(kind = "db", id = "V01_Y", direction = "defensive_only")); "" }, error = function(e) conditionMessage(e))
chk("T10 defensive_only 도 등록부 방어 방향이 없는 팩터면 멈춘다(접근자 호출 0)", grepl("direction_defensive", e10, fixed = TRUE) && length(CALLS) == 0L)
r11 <- run(list(kind = "db", id = "D01_X", direction = "defensive"))
chk("T11 defensive(한정 아님)는 꺼진 달 표식이 없다 — 종전 모드에 attr 가 새지 않는다", is.null(attr(r11, "def_off_dates")) && is.null(attr(r0, "def_off_dates")))

## 4절 기여 0 — .zero_off 정의를 꺼내 rank-Z 뒤에 적용: 꺼진 달 점수 순위 = 기저 신호 순위 · 켜진 달은 팩터가 순위를 바꾼다
zdef <- NULL; for (ex in src) if (is.call(ex) && identical(as.character(ex[[1]]), "<-") && identical(as.character(ex[[2]]), ".zero_off")) zdef <- ex
chk("T12 엔진 소스에서 .zero_off 정의를 찾았다", !is.null(zdef))
Z <- new.env(parent = globalenv()); eval(zdef, Z)
PN <- data.table(Date = rep(as.Date(c("2020-01-31", "2020-02-28")), each = 4L), Ticker = rep(c("A", "B", "C", "D"), 2L),
                 .zb = rep(c(1.5, 0.5, -0.5, -1.5), 2L), .z1 = rep(c(-3, -1, 1, 3), 2L))
Z$.zero_off(PN, ".z1", as.Date("2020-02-28"))
PN[, Score := rowMeans(as.matrix(.SD)), .SDcols = c(".zb", ".z1")]
o1 <- PN[Date == as.Date("2020-01-31")][order(-Score)]$Ticker; o2 <- PN[Date == as.Date("2020-02-28")][order(-Score)]$Ticker
chk("T13 꺼진 달(2월): 팩터 z = 0 · 점수 순위 = 기저 순위(A>B>C>D · 행 보존) / 켜진 달(1월): 팩터가 순위를 뒤집는다",
    all(PN[Date == as.Date("2020-02-28")]$.z1 == 0) && identical(o2, c("A", "B", "C", "D")) && identical(o1, c("D", "C", "B", "A")) && nrow(PN) == 8L)
Z$.zero_off(PN, ".zb", as.Date(character(0)))
chk("T14 꺼진 달 목록이 비면(다른 모드) 아무것도 바꾸지 않는다", identical(PN$.zb, rep(c(1.5, 0.5, -0.5, -1.5), 2L)))

## 배선(소스 텍스트) — 루프가 attr 를 받아 rank-Z **뒤에** 0 을 두고 · B7 슬리브 적재가 선정 방향을 넘긴다
etxt <- paste(readLines(file.path(ROOT, "02_Infrastructure", "reinforcement", "rf_cell_engine.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
p_rz <- regexpr("PANEL[, (zc) := .rz(get(tg)), by = .grp]", etxt, fixed = TRUE); p_zo <- regexpr(".zero_off(PANEL, zc, .def_off[[tg]])", etxt, fixed = TRUE)
chk("T15 4절: .zero_off 가 rank-Z 계산 바로 뒤에 있다(앞이면 동점 sd 0 → NaN 으로 행이 빠진다)", p_rz > 0 && p_zo > p_rz && (p_zo - p_rz) < 200)
chk("T16 3절: 루프가 .load_factor 결과의 def_off_dates 를 .def_off 에 담는다",
    grepl('if (!is.null(attr(.fl, "def_off_dates"))) .def_off[[tg]] <- attr(.fl, "def_off_dates")', etxt, fixed = TRUE))
chk("T17 B7: 슬리브 처치 적재에 rf_sl_resolve 의 실효 방향(defensive)을 넘긴다(선정 = 처치 방향 기준 · 감사 B7)",
    grepl('direction = if (identical(.sl_res$direction, "defensive")) "defensive" else NULL), ".zdef")', etxt, fixed = TRUE))

## 돌연변이(소스 텍스트 치환) — 판정 부등호 뒤집기 · 꺼진 달 기록 삭제가 각각 T08 을 빨갛게 한다
mut <- function(from, to) {
  stopifnot(lengths(regmatches(etxt, gregexpr(from, etxt, fixed = TRUE))) == 1L)       # 치환 성사 단정(정확히 1곳)
  ex <- parse(text = sub(from, to, etxt, fixed = TRUE), keep.source = FALSE); d <- NULL
  for (e in ex) if (is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), ".load_factor")) d <- e
  M <- new.env(parent = globalenv()); assign(".RF_ROOT", SB, envir = M); assign(".sig_dates", W$.sig_dates, envir = M); eval(d, M)
  CALLS <<- list(); r <- M$.load_factor(list(kind = "db", id = "D01_X", direction = "defensive_only"), "f2")
  identical(attr(r, "def_off_dates"), as.Date("2020-02-28"))
}
m1 <- tryCatch(mut("if (!(is.finite(ag) && ag > 0))", "if (!(is.finite(ag) && ag < 0))"), error = function(e) NA)
m2 <- tryCatch(mut(".off <<- c(.off, as.Date(d))", "invisible(NULL)"), error = function(e) NA)
chk("T18 [돌연변이 red] 부호 일치 판정 뒤집기 · 꺼진 달 기록 삭제 → 둘 다 T08 판정이 깨진다(치환 성사 단정 포함)", identical(m1, FALSE) && identical(m2, FALSE))

unlink(SB, recursive = TRUE)
cat(sprintf("\n%s\n", toJSON(list(test = "test_rf_cell_factor_direction", pass = pass, fail = fail), auto_unbox = TRUE)))
quit(status = if (fail > 0L) 1L else 0L)
