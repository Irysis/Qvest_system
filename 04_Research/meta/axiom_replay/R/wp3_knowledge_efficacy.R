# wp3_knowledge_efficacy.R — 엔진 자기평가 (사전등록 §4)
#
# 엔진이 낸 글 지식이 실제로 연구를 바꿨는가. 기록만으로 잰다.
#   ① dead config 조회(preflight)의 변별력
#   ② §5.1 관찰 비교 — 교훈 주입 전후
#   ③ 공리의 행동 도달 여부
# ★어느 항목도 "글 지식을 버리라"는 결론으로 쓰지 않는다. 채널을 옮길 근거로만 쓴다.

source("R/ledger_io.R")

.WP3_LOG <- "C:/qm_cache/reinforce_auto_log.jsonl"

#' preflight 이벤트 — 어느 칸에 죽은 선례 경고가 떴나
wp3_preflight_events <- function(log_path = .WP3_LOG) {
  if (!file.exists(log_path)) return(NULL)
  ln <- grep("preflight_dead_precedent", readLines(log_path, warn = FALSE), fixed = TRUE, value = TRUE)
  out <- lapply(ln, function(x) {
    j <- tryCatch(fromJSON(x, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(j)) return(NULL)
    data.frame(ts = .ar_ts(j$ts), code = as.character(j$code %||% NA),
               kw = as.character(j$kw %||% ""), stringsAsFactors = FALSE)
  })
  do.call(rbind, Filter(Negate(is.null), out))
}

#' 칸 등록 이벤트 — 경고가 안 뜬 칸을 세려면 분모가 필요하다
wp3_cell_events <- function(log_path = .WP3_LOG) {
  if (!file.exists(log_path)) return(NULL)
  ln <- grep('"event":"cell_done"', readLines(log_path, warn = FALSE), fixed = TRUE, value = TRUE)
  out <- lapply(ln, function(x) {
    j <- tryCatch(fromJSON(x, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(j)) return(NULL)
    data.frame(ts = .ar_ts(j$ts), code = as.character(j$code %||% NA),
               grade = as.character(j$grade %||% NA),
               port_t = suppressWarnings(as.numeric(j$port_t %||% NA)),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, Filter(Negate(is.null), out))
}

#' 시각 근접 조인 — 이벤트에 base_id 가 없어 원장 시도와 시각으로 맞춘다
wp3_join_attempts <- function(ev, att, tol_min = 30) {
  if (is.null(ev) || !nrow(ev)) return(NULL)
  att2 <- att[!is.na(att$opened_at) & !is.na(att$cell_code), , drop = FALSE]
  idx <- vapply(seq_len(nrow(ev)), function(i) {
    cand <- which(att2$cell_code == ev$code[i])
    if (!length(cand)) return(NA_integer_)
    dt <- abs(as.numeric(difftime(att2$opened_at[cand], ev$ts[i], units = "mins")))
    j <- which.min(dt)
    if (!length(j) || !is.finite(dt[j]) || dt[j] > tol_min) NA_integer_ else cand[j]
  }, integer(1))
  ev$att_row <- idx
  ev
}
