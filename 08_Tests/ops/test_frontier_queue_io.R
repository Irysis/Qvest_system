#==============================================================================
# test_frontier_queue_io.R — 정본 원장 writer 검사 (위반 주입 포함)
#
# 검사 대상 = 02_Infrastructure/ops/frontier_queue_io.R
# ★설계 원칙: "가드가 있다"가 아니라 **"가드가 진짜 위반에서 발화한다"**를 잰다.
#   오탐 제거와 검사 사망은 겉보기가 같으므로 위반 주입 없이는 초록이 무의미하다.
#   실제 원장은 건드리지 않는다 — 전부 임시 픽스처 위에서 돈다.
#==============================================================================
suppressMessages(library(jsonlite))

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
## 앵커는 self-first (env-first 면 worktree 배터리가 main 을 검사한다 — 2026-08-02 실사고)
self <- tryCatch(normalizePath(sys.frame(1)$ofile), error = function(e) NA_character_)
if (!is.na(self)) {
  cand <- normalizePath(file.path(dirname(self), "..", ".."), mustWork = FALSE)
  if (file.exists(file.path(cand, "02_Infrastructure/ops/frontier_queue_io.R"))) ROOT <- cand
}
setwd(ROOT)
source("02_Infrastructure/ops/frontier_queue_io.R")

PASS <- 0L; FAIL <- 0L
ok <- function(label, cond, note = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", label)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", label, note)) }
}
threw <- function(expr) inherits(tryCatch(expr, error = function(e) e), "error")

TMP <- file.path(tempdir(), "fq_io_fixture.json")
mkfix <- function() list(
  schema_version = "1.0",
  updated = "fixture",
  entries = list(
    list(id = "FQ-001", title = "가", status = "open", status_raw = "frontier_open", score = 0.009541984),
    list(id = "FQ-002", title = "나", status = "open", status_raw = "config_scoped_negative_frontier_open", score = 0.123456789),
    list(id = "FQ-003", title = "다", status = "done", score = 2)
  ))
reset <- function() { Q <- mkfix(); writeLines(.fq_serialize(Q), TMP, useBytes = TRUE); invisible(Q) }

cat("=== frontier_queue_io 검사 ===\n")

## ── A. 기능 프로브: 검사 대상이 실제로 로드되고 동작하는가 (죽은 검사기 차단) ──
ok("A1 writer 함수 존재", is.function(write_frontier_queue) && is.function(read_frontier_queue))
Q0 <- reset()
ok("A2 픽스처 기록·재읽기 성립", identical(read_frontier_queue(TMP)$entries[[1]]$id, "FQ-001"))

## ── B. 정본 형식: 무수정 왕복이 바이트 동일 ──
ok("B1 무수정 왕복 = 바이트 동일", isTRUE(frontier_queue_format_ok(TMP)))
writeLines(toJSON(mkfix(), auto_unbox = TRUE, pretty = TRUE, digits = NA), TMP, useBytes = TRUE)
ok("B2 비정본 형식(pretty=2)을 FALSE 로 판별", isFALSE(frontier_queue_format_ok(TMP)))
reset()

## ── C. 정상 경로: 필드 추가는 통과하고 고정밀 값이 보존된다 ──
Q <- read_frontier_queue(TMP); Q$entries[[1]]$blocked_by <- "x.rds"
suppressMessages(write_frontier_queue(Q, TMP))
txt <- paste(readLines(TMP, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
ok("C1 필드 추가 통과", grepl("blocked_by", txt, fixed = TRUE))
ok("C2 고정밀 값 보존 (0.009541984)", grepl("0.009541984", txt, fixed = TRUE))
ok("C3 항목 수 불변", length(read_frontier_queue(TMP)$entries) == 3L)

## ── D. ★위반 주입 ①: 정밀도 훼손 (digits 반올림) ──
reset()
Q <- read_frontier_queue(TMP)
Q_rounded <- fromJSON(toJSON(Q, auto_unbox = TRUE, digits = 4), simplifyVector = FALSE)  # ← 위반 주입
ok("D1 반올림된 판을 **거부**", threw(write_frontier_queue(Q_rounded, TMP)))
ok("D2 거부 후 디스크는 원본 유지", grepl("0.009541984",
   paste(readLines(TMP, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), fixed = TRUE))

## ── E. ★위반 주입 ②: 항목 소실 (병행 세션 덮어쓰기) ──
reset()
Q <- read_frontier_queue(TMP); Q$entries <- Q$entries[1:2]                               # ← 위반 주입
ok("E1 항목 삭제를 **거부**", threw(write_frontier_queue(Q, TMP)))
ok("E2 거부 후 항목 3건 유지", length(read_frontier_queue(TMP)$entries) == 3L)
ok("E3 사유 명시 시 삭제 허용", !threw(suppressMessages(
     write_frontier_queue(Q, TMP, allow_shrink = "테스트 — 의도된 삭제"))))
ok("E4 허용 후 실제로 2건", length(read_frontier_queue(TMP)$entries) == 2L)

## ── F. ★위반 주입 ③: 스키마 무결성 ──
reset()
Q <- read_frontier_queue(TMP); Q$entries[[2]]$id <- "FQ-001"                              # ← 중복 id
ok("F1 중복 id 거부", threw(write_frontier_queue(Q, TMP)))
Q <- read_frontier_queue(TMP); Q$entries[[2]]$id <- NULL                                  # ← id 결측
ok("F2 id 없는 항목 거부", threw(write_frontier_queue(Q, TMP)))
Q <- read_frontier_queue(TMP); Q$entries <- list()                                        # ← 전멸
ok("F3 빈 entries 거부", threw(write_frontier_queue(Q, TMP)))
ok("F4 세 거부 모두 디스크 무변경", length(read_frontier_queue(TMP)$entries) == 3L)

## ── G. 돌연변이: 가드를 끄면 검사가 실제로 빨개지는가 (검출력 실증) ──
##    D1 이 통과하는 이유가 "가드가 발화해서"인지 "다른 이유로 stop 나서"인지 구별한다.
reset()
Q <- read_frontier_queue(TMP)
Q_r <- fromJSON(toJSON(Q, auto_unbox = TRUE, digits = 4), simplifyVector = FALSE)
msg <- tryCatch({ write_frontier_queue(Q_r, TMP); "" }, error = function(e) conditionMessage(e))
ok("G1 거부 사유가 **정밀도** 가드임을 확인", grepl("고정밀", msg, fixed = TRUE),
   paste0("(실제 사유: ", substr(msg, 1, 60), ")"))
Q_s <- read_frontier_queue(TMP); Q_s$entries <- Q_s$entries[1:2]
msg2 <- tryCatch({ write_frontier_queue(Q_s, TMP); "" }, error = function(e) conditionMessage(e))
ok("G2 거부 사유가 **소실** 가드임을 확인", grepl("사라진다", msg2, fixed = TRUE),
   paste0("(실제 사유: ", substr(msg2, 1, 60), ")"))

unlink(TMP)
cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"frontier_queue_io","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
