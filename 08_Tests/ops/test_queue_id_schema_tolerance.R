#!/usr/bin/env Rscript
# test_queue_id_schema_tolerance.R — 큐 항목 식별자 관용 읽기 계약 (2026-08-13 신설)
#
# 왜: mode_queue 항목의 논문 식별자 필드가 **두 가지**다 — 구판 `id`, 신판 `arxiv_id`.
#   실측 159건 중 **132건(83%)이 구판** 이고, 스키마가 시간순도 아니다
#   (0618 신판 → 0619~0705 구판 → 0802 신판 → 0803 구판 …) = 두 생산자가 동시에 쓰고 있다.
#   `arxiv_id` 만 읽으면 83%가 **식별자 없이** 에이전트에 도달하고 `paper_pdf()` 로 원문을
#   못 연다. 원문 없이 memo 만 보고 구현하는 것이 이 레인의 **날조 시작점**이다.
#
# ★본체는 T5 다: **실제 큐 전수에서 식별자 결측이 0 이어야 한다.**
#   단위 테스트(T1~T4)는 통과하는데 실데이터에서 새 스키마가 또 등장하는 상황을 잡는 축이 없으면
#   같은 결함이 조용히 재발한다 — 스키마 드리프트는 이 저장소에서 반복 확인된 부류다.
set.seed(20260813)
.root <- (function() {
  for (c in c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"), getwd()))
    if (nzchar(c) && dir.exists(file.path(c, "06_Registry"))) return(c)
  getwd()
})()
setwd(.root)
suppressWarnings(suppressMessages(library(jsonlite)))

PASS <- 0; FAIL <- 0
chk <- function(n, ok, d = "") { if (isTRUE(ok)) { PASS <<- PASS + 1; cat(sprintf("  ok   %s %s\n", n, d)) }
                                 else { FAIL <<- FAIL + 1; cat(sprintf("  FAIL %s %s\n", n, d)) } }
cat("== 큐 식별자 스키마 관용 ==\n")

# ── 원본에서 함수만 추출해 평가한다(사본 정의 금지 — 원본이 죽어도 통과하면 검사가 아니다).
SRC <- "02_Infrastructure/ops/paper_research_dispatch.R"
chk("T0 디스패처가 문법적으로 파싱된다", tryCatch({ invisible(parse(SRC)); TRUE }, error = function(e) FALSE))
ex <- parse(SRC)
env <- new.env(parent = globalenv())
assign("%||%", function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b, envir = env)
got <- FALSE
for (e in ex) {
  if (is.call(e) && length(e) >= 3 && identical(as.character(e[[1]]), "<-") &&
      identical(as.character(e[[2]]), ".pq_paper_id")) { eval(e, envir = env); got <- TRUE }
}
chk("T0b .pq_paper_id 를 원본에서 추출했다", got && is.function(get0(".pq_paper_id", envir = env)))
if (!got) { cat(sprintf('{"test":"queue_id_schema_tolerance","pass":%d,"fail":%d,"total":%d}\n',
                        PASS, FAIL + 1, PASS + FAIL + 1)); quit(status = 1) }
f <- get(".pq_paper_id", envir = env)

chk("T1 신판 arxiv_id 를 읽는다", identical(f(list(arxiv_id = "2606.11962")), "2606.11962"))
chk("T2 ★구판 id 를 읽는다(83% 경로)", identical(f(list(id = "2606.09104", title = "x")), "2606.09104"))
chk("T3 paper_id 도 읽는다", identical(f(list(paper_id = "arxiv:2607.19497")), "arxiv:2607.19497"))
chk("T4 셋 다 없으면 NA (엉뚱한 필드를 집지 않는다)",
    is.na(f(list(title = "제목만", memo = "메모만", source = "arxiv"))))
chk("T4b 빈 문자열은 값으로 치지 않는다", identical(f(list(arxiv_id = "", id = "2606.1")), "2606.1"))
chk("T4c 우선순위: arxiv_id > id", identical(f(list(id = "OLD", arxiv_id = "NEW")), "NEW"))

# ── T5 ★실데이터 전수 — 식별자 결측 0
qs <- Sys.glob("stage_artifacts/paper_recharge/mode_queue_*.json")
tot <- 0L; miss <- character(0); byfield <- c(arxiv_id = 0L, id = 0L, other = 0L)
for (q in qs) {
  j <- tryCatch(fromJSON(q, simplifyVector = FALSE), error = function(e) NULL); if (is.null(j)) next
  src <- if (!is.null(j[["queue"]]) && is.list(j[["queue"]])) j[["queue"]] else j
  for (ln in c("optimizer", "risk", "regime")) for (it in (src[[ln]] %||% list())) {
    if (!is.list(it)) next
    tot <- tot + 1L
    v <- f(it)
    if (is.na(v)) miss <- c(miss, sprintf("%s/%s/%s", basename(q), ln, substr(it$title %||% "?", 1, 26)))
    else if (!is.null(it$arxiv_id)) byfield["arxiv_id"] <- byfield["arxiv_id"] + 1L
    else if (!is.null(it$id)) byfield["id"] <- byfield["id"] + 1L
    else byfield["other"] <- byfield["other"] + 1L
  }
}
chk("T5 ★실제 큐 전수에서 식별자 결측 0", tot > 0L && length(miss) == 0L,
    sprintf("항목 %d (arxiv_id %d · 구판 id %d · 기타 %d)%s", tot, byfield[1], byfield[2], byfield[3],
            if (length(miss)) sprintf(" ★결측 %d: %s", length(miss), paste(head(miss, 3), collapse = "; ")) else ""))
chk("T5b 두 스키마가 실제로 공존한다(검사가 공허하지 않다)",
    byfield["arxiv_id"] > 0L && byfield["id"] > 0L,
    sprintf("신판 %d · 구판 %d", byfield[1], byfield[2]))

# ── T6 해석된 식별자로 **원문에 실제 도달**하는가 (표본)
ps <- "02_Infrastructure/methods/paper_source.R"
if (file.exists(ps)) {
  suppressWarnings(suppressMessages(source(ps)))
  ids <- character(0)
  for (q in qs) {
    j <- tryCatch(fromJSON(q, simplifyVector = FALSE), error = function(e) NULL); if (is.null(j)) next
    src <- if (!is.null(j[["queue"]]) && is.list(j[["queue"]])) j[["queue"]] else j
    for (ln in c("optimizer", "risk", "regime")) for (it in (src[[ln]] %||% list())) {
      if (is.list(it)) { v <- f(it); if (!is.na(v)) ids <- c(ids, v) }
    }
  }
  ids <- unique(ids)
  hit <- sum(vapply(ids, function(v) {
    p <- tryCatch(paper_pdf(v), error = function(e) NULL)
    !is.null(p) && length(p) == 1L && file.exists(p) }, logical(1)))
  chk("T6 해석된 식별자로 원문 도달", length(ids) > 0L && hit == length(ids),
      sprintf("%d/%d", hit, length(ids)))
} else chk("T6 paper_source.R 부재로 건너뜀", TRUE, "(도달 검사 미실행 — 무결성 아님)")

TOTAL <- PASS + FAIL
cat(sprintf("  ── %d/%d pass\n", PASS, TOTAL))
cat(sprintf('{"test":"queue_id_schema_tolerance","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, TOTAL))
quit(status = if (FAIL == 0) 0 else 1)
