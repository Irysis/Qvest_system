#!/usr/bin/env Rscript
#==============================================================================
# test_rf_cell_factor_direction.R — 셀 엔진의 팩터 방향 선택(v10.2 · 2026-11-10 팩터 DB 배선)
#   대상: 02_Infrastructure/reinforcement/rf_cell_engine.R 의 .load_factor(kind = "db")
#   본다: 방향 필드가 없으면 접근자 호출 모양이 종전과 같다(direction 인자를 넘기지 않는다) · registry · defensive 는 접근자 인자로 간다 ·
#         방어 방향이 등록부에 없는 팩터의 defensive 요구 · 어휘 밖 값은 멈춘다(조용히 빠지지 않는다).
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

unlink(SB, recursive = TRUE)
cat(sprintf("\n%s\n", toJSON(list(test = "test_rf_cell_factor_direction", pass = pass, fail = fail), auto_unbox = TRUE)))
quit(status = if (fail > 0L) 1L else 0L)
