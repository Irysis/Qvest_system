#!/usr/bin/env Rscript
#==============================================================================
# rf_queue_done.R — 강화 레인의 논문 소비를 **큐 소비 원장에 미러**한다 (도훈 2026-09-04)
#
# 왜: 큐 카운터(alpha-pending)는 `stage_artifacts/paper_recharge/alpha_search_queue_done.json`
#   을 보고 "소비했나"를 판정한다. 그런데 강화 레인의 소비는 **강화 원장**
#   (reinforce_ledger_l1.json)에만 남는다. 두 원장이 안 이어져 있어서, 오늘 5편을 소비했는데
#   부팅 5줄과 텔레그램은 계속 "alpha-pending 75" 였다 — 숫자가 하루 종일 안 움직였다.
#
# 경계 — **판정의 정본은 옮기지 않는다**:
#   선택기(rf_next_paper_pick)는 지금도 강화 원장의 paper_key 로 소비를 판단한다. 그건 그대로 둔다.
#   여기서 쓰는 것은 **표시용 미러**일 뿐이다. 두 곳에서 각자 판정하게 만들면 언젠가 갈리고,
#   갈린 뒤에는 어느 쪽이 맞는지 아무도 모른다(이 저장소가 반복해서 데인 형태).
#   ⇒ 미러는 읽기 전용 소비자(카운터)만 본다. 쓰기 실패는 리서치를 멈추지 않는다.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' @param paper_key 강화 원장이 쓰는 키(arxiv id 또는 "combo:a+b")
#' @param reason    무엇 때문에 소비됐나(등급 미달·소진·스킵리스트 등)
rf_mark_queue_done <- function(paper_key, reason = "", strategy_id = "",
                               root = Sys.getenv("QM_ROOT", getwd())) {
  pk <- as.character(paper_key %||% "")[1]
  if (!nzchar(pk)) return(invisible(FALSE))
  # ★결합은 구성 논문 각각을 소비로 세지 않는다 — 결합은 새 논문 소비가 아니다
  #   (rf_open_entry(count_paper=FALSE) 과 같은 규약). 미러도 같은 규약을 따른다.
  if (startsWith(pk, "combo:")) return(invisible(FALSE))
  p <- file.path(root, "stage_artifacts/paper_recharge/alpha_search_queue_done.json")
  if (!file.exists(p)) return(invisible(FALSE))
  ok <- tryCatch({
    d <- fromJSON(p, simplifyVector = FALSE)
    pr <- as.character(unlist(d$processed %||% list()))
    # ★조기 return 을 tryCatch 안에 두지 않는다 — 동작은 하지만 promise 강제 시점에 의존한다
    if (pk %in% pr) TRUE else {
    d$processed <- as.list(c(pr, pk))
    d$records <- c(d$records %||% list(), list(list(
      paper_id = pk, paper_title = NULL, factor_id = NULL, factor_name = NULL,
      strategy_id = as.character(strategy_id %||% ""),
      source = "reinforcement",
      note = sprintf("강화 레인 소비 미러 — %s", substr(as.character(reason), 1, 160)),
      recorded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))))
    d$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    txt <- toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
    if (is.null(tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)))
      stop("재파싱 검증 실패")
    tmp <- paste0(p, ".tmp"); write(txt, tmp)
    if (!suppressWarnings(file.rename(tmp, p))) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }
    TRUE
    }
  }, error = function(e) FALSE)
  invisible(ok)
}
