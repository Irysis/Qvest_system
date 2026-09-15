# rf_request_guard.R — 충실구현 요청 종결(status=done) 기록의 소유 대조 (2026-09-15 도훈 승인 수리)
#
# 왜: rf_replication_verify.R 은 측정·감사·원장을 **실행 시작 때 받은 논문 키(RP_KEY)** 로 쓰는데,
#   마지막 요청 종결만은 **지금의** replication_request.json 을 읽어 자기 결과로 덮었다.
#   2시간 회수로 살아남은 구 실행이 늦게 끝나면, 그 사이 다음 논문으로 바뀐 요청을 남의 결과로 닫는다.
#   실사고 2026-09-13: 2002.06975 3판 verify(10:28)가 08:48 에 발행된 1806.01743 요청을
#   status=done · grade C 로 덮어, 1806.01743 은 한 번도 측정되지 않았는데 기록상 '완료'가 됐다.
# ⇒ 요청의 논문 키가 이 실행의 키와 다르면 쓰지 않고 사유만 남긴다.
#   키를 판별할 수 없으면(빈 키·구판 요청) 기존 동작(기록)을 유지한다 — 판별 불가를 차단으로
#   바꾸면 정상 종결이 조용히 사라지고, 그러면 요청이 in_progress 로 남아 레인이 같은 논문을 다시 돈다.
# 키 경로: 요청 발행(reinforce_auto_next_paper.R · 결합 런처)과 레인(rf_replication_auto.sh P_KEY)이
#   모두 paper$paper_key 한 곳을 쓴다 — 결합 요청도 같다("combo:..." 키).

suppressWarnings(suppressMessages(library(jsonlite)))

rf_request_paper_key <- function(req) {
  p <- if (is.list(req)) req$paper else NULL
  k <- if (is.list(p)) p$paper_key else NULL
  if (is.null(k) || !length(k) || is.na(k[[1]])) "" else trimws(as.character(k[[1]]))
}

rf_request_owned_by <- function(req, run_key) {
  rk <- if (is.null(run_key) || !length(run_key) || is.na(run_key[[1]])) "" else trimws(as.character(run_key[[1]]))
  qk <- rf_request_paper_key(req)
  if (!nzchar(rk) || !nzchar(qk))
    return(list(owned = TRUE, reason = "key_unknown", req_key = qk, run_key = rk))
  same <- identical(qk, rk)
  list(owned = same, reason = if (same) "match" else "retargeted", req_key = qk, run_key = rk)
}

# 요청 종결의 유일한 writer. fields = 이 실행이 남길 종결 필드(base_id·grade·artifacts·fidelity…).
# 반환 = rf_request_owned_by 결과 + written(TRUE/FALSE).
rf_request_mark_done <- function(req_path, run_key, fields = list()) {
  d <- tryCatch(fromJSON(req_path, simplifyVector = FALSE), error = function(e) list())
  own <- rf_request_owned_by(d, run_key)
  if (!isTRUE(own$owned)) return(c(own, list(written = FALSE)))
  d$status <- "done"
  for (nm in names(fields)) d[[nm]] <- fields[[nm]]
  d$completed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  write(toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null"), req_path)
  c(own, list(written = TRUE))
}
