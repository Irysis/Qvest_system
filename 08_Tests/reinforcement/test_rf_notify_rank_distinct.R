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
## ★notify 는 이제 블록당 두 건을 보낸다(본문 + '알게 된 것' 전체판, 2026-09-04) — 마지막 호출만 담으면 본문이 덮인다.
##   순위 줄이 있는 본문(무엇을 강화했나)을 골라 담는다.
tg_agent_brief <- function(agent, title, sections, charts = NULL, ...) {
  .has <- any(vapply(sections, function(z) identical(z$heading %||% "", "무엇을 강화했나"), logical(1)))
  if (.has || is.null(.CAP)) .CAP <<- list(title = title, sections = sections)
  invisible(list(ok = TRUE, bytes = 1L, error = NULL))
}
#' 발송 텍스트에서 "n위 …" 줄만 뽑는다.
rank_lines <- function(base_id, block = "") {
  Sys.setenv(QVEST_RF_FORCE_BLOCK = block)
  on.exit(Sys.setenv(QVEST_RF_FORCE_BLOCK = ""), add = TRUE)
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
# ★entry 하나만 보면 안 된다. rf_auto_notify 는 그 entry 의 **마지막 블록**만 렌더하므로,
#   한 건만 재면 나머지 블록의 붕괴가 안 보인다 — 2026-09-03 3차 적발이 정확히 그렇게 샜다
#   (검사 대상 entry 의 마지막 블록이 B4 라 고쳐진 B4 만 보고 통과했고, B1 은 전부 동문이었다).
act <- tail(Filter(function(e) .meas(e) >= 5L, led$entries), 6L)
if (!length(act)) { cat("  SKIP 측정 5칸 이상 entry 없음\n")
  cat('{"test":"rf_notify_rank_distinct","pass":0,"fail":0,"total":0,"skipped":1}\n'); quit(status = 0) }

cat(sprintf("=== A. 순위 줄이 서로 다른가 — 최근 entry %d건 ===\n", length(act)))
.seen <- character(0)
for (e in act) {
  BID <- e$base_id
  rl <- rank_lines(BID)
  if (length(rl) < 2L) { cat(sprintf("  ---  %s 순위 줄 %d개 — 건너뜀\n", BID, length(rl))); next }
  blk <- sub("_.*$", "", sub("^[0-9]+위 ", "", rl[1])); .seen <- union(.seen, blk)
  d <- desc_only(rl)
  if (!anyDuplicated(d)) ok(sprintf("%s [%s] 서술 %d줄 전부 구분", substr(BID, 1, 30), blk, length(d)))
  else {
    dup <- unique(d[duplicated(d)])
    ng(sprintf("%s [%s] 같은 서술 %d종이 여러 위를 차지한다", substr(BID, 1, 30), blk, length(dup)),
       paste(substr(dup, 1, 44), collapse = " / "))
    for (x in rl) cat(sprintf("       %s\n", substr(x, 1, 74)))
  }
}
if (length(.seen)) ok(sprintf("A-cov 블록 %s 를 덮었다", paste(sort(.seen), collapse = "/"))) else
  ng("A-cov 블록을 하나도 못 덮었다")

cat("=== A2. 전 블록 스윕 — 25칸 완주 entry 의 다섯 블록을 전부 렌더 ===\n")
# ★A 절만으로는 각 entry 의 **마지막 블록**밖에 못 본다. 세 번의 실사고가 모두
#   그때 안 보이던 블록에서 났다(B5 -> B4 -> B1). 이음매로 전 블록을 강제 렌더한다.
full <- Filter(function(e) .meas(e) >= 25L, led$entries)
if (!length(full)) cat("  ---  25칸 완주 entry 없음 — 스윕 건너뜀\n") else {
  FB <- tail(full, 1L)[[1]]$base_id
  for (blk in c("B1", "B2", "B3", "B5", "B4")) {
    rl <- rank_lines(FB, blk)
    if (length(rl) < 2L) { cat(sprintf("  ---  %s 순위 줄 %d개\n", blk, length(rl))); next }
    d <- desc_only(rl)
    if (!anyDuplicated(d)) ok(sprintf("%s 서술 %d줄 전부 구분", blk, length(d)))
    else {
      ng(sprintf("%s 서술 중복 %d종", blk, length(unique(d[duplicated(d)]))),
         paste(substr(unique(d[duplicated(d)]), 1, 44), collapse = " / "))
      for (x in rl) cat(sprintf("       %s\n", substr(x, 1, 74)))
    }
  }
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
