#!/usr/bin/env Rscript
#==============================================================================
# test_rf_notify_rank_distinct.R — 순위 줄이 서로 다른가 (2026-09-03)
#
# 실증: 도훈이 두 번 적발했다. ①B5 블록 — 오버레이가 서술에 없어 네 칸이 같은 문장.
#   ②B4 블록 — 결합 칸의 처치는 **부분집합**인데 축 차집합으로 적어, LOO 로 뺀 축이
#   마침 carry 와 같으면 1·3·4위가 글자까지 동일했다("GR02 (GR02) · 비중").
#   두 병의 공통 기전: 그 블록의 **처치를 구분하는 축**이 서술에서 빠졌다.
#
# 재는 것 = 실제 발송 텍스트. 헬퍼를 따로 부르지 않고 tg_agent_brief 를 가로채
#   메시지 자체를 본다 — 서술 경로가 바뀌어도 이 검사는 낡지 않는다.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R")))))
.orig <- base::source
source <- function(file, ...) {
  if (is.character(file) && grepl("telegram_notify", file)) return(invisible(NULL))
  .orig(file, ...)
}
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

.CAP <- NULL
tg_agent_brief <- function(agent, title, sections, charts = NULL, ...) {
  .CAP <<- list(title = title, sections = sections); invisible(list(ok = TRUE, bytes = 1L, error = NULL))
}
#' 발송 텍스트에서 "n위 …" 줄만 뽑는다.
rank_lines <- function(base_id) {
  .CAP <<- NULL
  invisible(suppressWarnings(rf_auto_notify(base_id, 5L, kind = "block")))
  if (is.null(.CAP)) return(character(0))
  s <- Filter(function(z) identical(z$heading %||% "", "무엇을 강화했나"), .CAP$sections)
  if (!length(s)) return(character(0))
  it <- as.character(unlist(s[[1]]$items %||% list()))
  it[grepl("^[0-9]+위 ", it)]
}
#' 순위 줄에서 코드·수치를 떼고 **서술만** 남긴다 — 코드가 달라서 달라 보이면 안 된다.
desc_only <- function(x) trimws(sub("· t .*$", "", sub("^[0-9]+위 [A-Z0-9_]+ ", "", x)))

# 측정이 끝난 entry (미측정 entry 는 보고할 것이 없어 정상적으로 빈 메시지다)
led <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
.meas <- function(e) sum(vapply(e$attempts, function(a) {
  sp <- a$essence$spec %||% ""; nzchar(sp) && file.exists(sp) }, logical(1)))
act <- Filter(function(e) .meas(e) >= 20L, led$entries)
if (!length(act)) { cat("  SKIP 측정 20칸 이상 entry 없음\n")
  cat('{"test":"rf_notify_rank_distinct","pass":0,"fail":0,"total":0,"skipped":1}\n'); quit(status = 0) }
BID <- act[[length(act)]]$base_id
cat(sprintf("대상 entry: %s\n", BID))

cat("=== A. 순위 줄이 서로 다른가 ===\n")
rl <- rank_lines(BID)
if (length(rl) >= 2L) ok(sprintf("A1 순위 줄 %d개 확보", length(rl))) else
  ng("A1 순위 줄을 못 뽑았다", "발송 텍스트 구조가 바뀌었다")
if (length(rl) >= 2L) {
  d <- desc_only(rl)
  if (!anyDuplicated(d)) ok("A2 서술이 전부 구분된다") else {
    dup <- unique(d[duplicated(d)])
    ng(sprintf("A2 같은 서술 %d종이 여러 위를 차지한다", length(dup)),
       paste(substr(dup, 1, 40), collapse = " / "))
  }
  for (x in rl) cat(sprintf("     %s\n", substr(x, 1, 74)))
}

cat("=== B. 결합 칸은 부분집합을 적는다 ===\n")
z <- vapply(c("B4_21", "B4_22", "B4_23", "B4_24", "B4_25"), function(k)
  as.character(.rf_combo(k)), character(1))
if (!anyNA(z) && !anyDuplicated(z)) ok("B1 B4 다섯 칸 라벨이 전부 다르다") else
  ng("B1 B4 라벨 중복/결측", paste(z, collapse = " | "))
if (all(grepl("+", z, fixed = TRUE))) ok("B2 사용 블록이 이름으로 적힌다") else ng("B2 블록 구성이 안 보인다")

cat("=== C. 양성 대조 — 검사가 중복을 실제로 잡는가 ===\n")
fake <- c("1위 B4_21 같은말 · t 1.00 · C", "2위 B4_22 같은말 · t 0.50 · C")
if (anyDuplicated(desc_only(fake))) ok("C1 위반 주입 적발") else ng("C1 중복을 못 잡는다 — 검사 죽음")
if (!anyDuplicated(desc_only(c("1위 B4_21 갑 · t 1.00 · C", "2위 B4_22 을 · t 0.5 · C"))))
  ok("C2 음성 대조 — 서로 다르면 통과") else ng("C2 오탐")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_notify_rank_distinct","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
