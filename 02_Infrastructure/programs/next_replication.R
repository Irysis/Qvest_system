#!/usr/bin/env Rscript
#==============================================================================
# next_replication.R — 다음 충실구현 논문 발행 (v10.01 · 2026-10-13 · 구 reinforce_auto_next_paper.R 의 급지 부분만 승계)
#
# 왜: 구 이월 스크립트는 강화 러너와 얽혀 있었다(소진 요약 · 승격 사슬 · 레인 규칙 · 결합 착수 · 블록 발송기).
#   러너가 퇴역해 그 부분은 의미가 없다. 남는 일은 하나 — 요청 슬롯이 비면 다음 논문 1편의 충실구현 요청을 낸다.
# 순서(구판 §1.7 · §1.8 · §2 · §3 그대로):
#   1) 요청이 pending · in_progress · failed_needs_session 이면 아무것도 안 한다(덮어쓰면 같은 논문이 두 번 뜬다)
#   2) 재구현 대기열(reimplement_queue.json · reserved)이 있으면 그 항목을 먼저 발행한다(rf_reimplement_queue.R 정본)
#   3) 큐(alpha-pending · research_pool_predicates.py 정본 CLI)가 비면 무동작
#   4) 큐 상단 1편(rf_next_paper_pick.py · 재정렬 금지)을 06_Registry/replication_request.json 에 pending 으로 쓴다
# ★논문을 고르지 않는다 — 큐 순서를 그대로 따른다. 텔레그램은 보내지 않는다(완료 보고는 검증기가 1통 — 발송 규칙 v10.01 §0.1).
# 사용: Rscript 02_Infrastructure/programs/next_replication.R --root <dir>
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

args <- commandArgs(trailingOnly = TRUE)
ri <- match("--root", args)
ROOT <- if (!is.na(ri) && length(args) > ri) args[ri + 1L] else Sys.getenv("QM_ROOT", getwd())
PY <- Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"))
LOG_P <- file.path(ROOT, ".cache/programs_log.jsonl")
jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "next_replication"), list(...))
  tryCatch(cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE), error = function(e) NULL)
  cat(sprintf("[next_replication] %s\n", event))
}

main <- function() {
  REQ_P <- file.path(ROOT, "06_Registry/replication_request.json")
  req <- if (file.exists(REQ_P)) tryCatch(fromJSON(REQ_P, simplifyVector = FALSE), error = function(e) NULL) else NULL
  st <- as.character(req$status %||% "")
  if (st %in% c("pending", "in_progress", "failed_needs_session")) {
    jlog("halt_request_pending", status = st, paper_key = req$paper$paper_key %||% "")
    return(0L)
  }
  rq <- tryCatch({
    source(file.path(ROOT, "02_Infrastructure/ops/rf_reimplement_queue.R"), local = TRUE)
    rf_reimplement_queue_take(ROOT, REQ_P, prev = NULL, jlog = jlog)
  }, error = function(e) { jlog("reimplement_queue_failed", err = conditionMessage(e)); list(issued = FALSE) })
  if (isTRUE(rq$issued)) return(0L)

  stage <- file.path(ROOT, "stage_artifacts/paper_recharge")
  ## 큐를 못 읽은 것(파이썬·CLI 부재 · 출력 비숫자)과 빈 큐는 다른 사실이다 — 0 으로 접지 않고 사건을 나눈다.
  ##   system2 는 실행 파일이 없으면 경고가 아니라 오류를 던진다(10-13 검사 실측 — 구판은 fatal 로 죽었다).
  n_pending <- tryCatch(suppressWarnings(as.integer(system2(PY,
    c(shQuote(file.path(ROOT, "02_Infrastructure/ops/research_pool_predicates.py")), "alpha-pending", shQuote(stage)),
    stdout = TRUE, stderr = FALSE)[1])), error = function(e) NA_integer_)
  if (is.na(n_pending)) { jlog("halt_queue_unreadable", py = PY, note = "alpha-pending 판독 불가 — 요청을 쓰지 않는다"); return(0L) }
  if (n_pending <= 0L) { jlog("halt_queue_empty", n_pending = n_pending); return(0L) }
  pick <- tryCatch(fromJSON(system2(PY, c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_next_paper_pick.py")), shQuote(stage)),
                                    stdout = TRUE), simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(pick) || is.null(pick$url) || !nzchar(pick$url)) {
    jlog("halt_pick_failed", n_pending = n_pending, note = "큐 상단 논문에서 원문 링크를 못 얻었다 — 원문 없는 착수 금지")
    return(0L)
  }
  txt <- toJSON(list(requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), source = "next_replication_v10_01",
                     reason = "v10.01 — 큐 다음 논문 충실구현(리서치 프로그램 재료 확보)", paper = pick, status = "pending"),
                auto_unbox = TRUE, pretty = TRUE, null = "null")
  tmp <- paste0(REQ_P, ".tmp"); writeLines(txt, tmp, useBytes = TRUE)
  if (!file.rename(tmp, REQ_P)) stop("요청 파일 교체 실패")
  jlog("replication_requested", paper_key = pick$paper_key %||% "", title = substr(pick$title %||% "", 1, 100))
  0L
}

rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
quit(status = as.integer(rc))
