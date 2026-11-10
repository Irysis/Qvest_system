# paper_recharge_dead_links.R — 기관 논문(curated) 죽은 링크의 '새 소식' 판정 (2026-11-10 감사 레인 C)
#
# 왜: paper_recharge_daily.R 은 죽은 링크가 1개라도 있으면 그날 텔레그램을 보냈다(.tg_has_news). 같은 2개
#   (WINTON 설명서 404 등)가 고쳐지지 않은 채 남아 있어 신규 0편인 날에도 [AlphaSearch] 1통이 매 실행 나갔다
#   (실측: 실행 로그 66일에 발송 줄 · 11-07~11-10 4일 연속 · 감사 원장 J10 '신규 0편 알림 매일').
#   정보량 0 메시지의 반복은 학습된 무시를 만든다(같은 파일 09-02 주석의 원칙 그대로).
# 무엇을: 이번에 죽은 링크 집합에 '지난번 알린 집합에 없던 것'이 있을 때만 새 소식이다. 알린 집합은 상태 파일에
#   남기고, 되살아난 링크는 집합에서 뺀다(다시 죽으면 다시 알린다). 로그 줄(DEAD curated link)은 매 실행 그대로 남는다.
# 검사: 08_Tests/scenarios/test_scn_paper_collect.R

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' @param dead 이번 실행에서 죽은 링크 이름(file_name) 문자 벡터
#' @param state_path 지난번 알린 집합을 담는 JSON 경로
#' @param write FALSE 면 상태 파일을 쓰지 않는다(dry-run)
#' @return list(news = 논리값, new_dead = 새로 죽은 이름, alerted = 저장한 집합)
pr_dead_link_news <- function(dead, state_path, write = TRUE) {
  dead <- sort(unique(as.character(dead[!is.na(dead) & nzchar(dead)])))
  prev <- character(0)
  if (file.exists(state_path)) {
    st <- tryCatch(jsonlite::fromJSON(state_path, simplifyVector = TRUE), error = function(e) NULL)
    prev <- as.character(unlist(st$alerted %||% character(0)))
  }
  new_dead <- setdiff(dead, prev)
  # 되살아난 링크는 알린 집합에서 뺀다 — 다시 죽으면 새 소식이 된다
  alerted <- dead
  if (isTRUE(write)) {
    tmp <- paste0(state_path, ".tmp", Sys.getpid())
    writeLines(jsonlite::toJSON(list(alerted = alerted, updated = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
                                auto_unbox = TRUE, pretty = TRUE), tmp, useBytes = TRUE)
    if (!file.rename(tmp, state_path)) { unlink(tmp); warning("dead-link 상태 교체 실패: ", state_path) }
  }
  list(news = length(new_dead) > 0L, new_dead = new_dead, alerted = alerted)
}
