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
# 사용: Rscript 02_Infrastructure/programs/next_replication.R --root <dir> [--req <요청 경로>] [--only-key <논문 키> --slot <슬롯>]
# ★다중 슬롯(2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020):
#   · 슬롯 작업자 환경(RP_SLOT)에서 불리면(레인 셸 · 검증기의 '다음 논문' 호출) 직접 고르지 않고 슬롯 발행기(rf_replication_slots.py issue)에
#     넘긴다 — 발행기가 다른 슬롯이 쥔 논문을 빼고(논문 잠금) 슬롯 등급(gpu/cpu)에 맞는 후보를 큐 순서대로 골라 '--only-key' 로 다시 부른다.
#   · --only-key K = 그 논문만 발행(재구현 대기열 reserved 항목이면 그것 · 아니면 큐 선택기 --only-key) · --req = 그 슬롯의 요청 파일 ·
#     --slot = 요청에 슬롯 이름을 남긴다. 셋 다 없으면 구판 그대로(구판 요청 06_Registry/replication_request.json · QVEST_RP_REQUEST 로 덮기).
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

args <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag) { i <- match(flag, args); if (!is.na(i) && length(args) > i) args[i + 1L] else NA_character_ }
ri <- match("--root", args)
ROOT <- if (!is.na(ri) && length(args) > ri) args[ri + 1L] else Sys.getenv("QM_ROOT", getwd())
PY <- Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"))
ONLY_KEY <- .arg("--only-key")
SLOT_ARG <- .arg("--slot")
REQ_ARG  <- .arg("--req")
LOG_P <- file.path(ROOT, ".cache/programs_log.jsonl")
jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "next_replication"), list(...))
  tryCatch(cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE), error = function(e) NULL)
  cat(sprintf("[next_replication] %s\n", event))
}

## 슬롯 작업자 문맥 → 슬롯 발행기에 위임(재귀 방지: 발행기는 RP_SLOT 을 지우고 RP_SLOT_ISSUING=1 · --only-key 로 다시 부른다)
.slot_delegate <- function() {
  slot <- Sys.getenv("RP_SLOT", "")
  if (!nzchar(slot) || !is.na(ONLY_KEY) || identical(Sys.getenv("RP_SLOT_ISSUING", ""), "1")) return(NA_integer_)
  sp <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_slots.py")
  out <- tryCatch(suppressWarnings(system2(PY, c("-X", "utf8", shQuote(sp), "issue", "--slot", shQuote(slot)), stdout = TRUE, stderr = TRUE)),
                  error = function(e) paste("error:", conditionMessage(e)))
  jlog("slot_issue_delegated", slot = slot, out = substr(paste(out, collapse = " "), 1, 300))
  0L
}

main <- function() {
  dg <- .slot_delegate()
  if (!is.na(dg)) return(dg)
  ## 요청 자리 = --req(슬롯 발행기만 넘긴다) · 없으면 구판 그대로. ★QVEST_RP_REQUEST(검사 격리 변수)는 읽지 않는다 — 읽으면 레인 검사의
  ##   격리 요청(done)이 '빈 자리'로 보여 실제 재구현 대기열(06_Registry/reimplement_queue.json)을 issued 로 바꾼다(10-20 실측 · 구판 동작 보존).
  REQ_P <- if (!is.na(REQ_ARG) && nzchar(REQ_ARG)) REQ_ARG else file.path(ROOT, "06_Registry/replication_request.json")
  dir.create(dirname(REQ_P), recursive = TRUE, showWarnings = FALSE)
  req <- if (file.exists(REQ_P)) tryCatch(fromJSON(REQ_P, simplifyVector = FALSE), error = function(e) NULL) else NULL
  st <- as.character(req$status %||% "")
  if (st %in% c("pending", "in_progress", "failed_needs_session")) {
    jlog("halt_request_pending", status = st, paper_key = req$paper$paper_key %||% "")
    return(0L)
  }
  rq <- tryCatch({
    source(file.path(ROOT, "02_Infrastructure/ops/rf_reimplement_queue.R"), local = TRUE)
    rf_reimplement_queue_take(ROOT, REQ_P, prev = NULL, jlog = jlog, only_key = if (is.na(ONLY_KEY)) NULL else ONLY_KEY,
                              slot = if (is.na(SLOT_ARG)) NULL else SLOT_ARG)
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
  pick_args <- c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_next_paper_pick.py")), shQuote(stage))
  if (!is.na(ONLY_KEY)) pick_args <- c(pick_args, "--only-key", shQuote(ONLY_KEY))
  pick <- tryCatch(fromJSON(system2(PY, pick_args, stdout = TRUE)[1], simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(pick) || is.null(pick$url) || !nzchar(pick$url)) {
    jlog("halt_pick_failed", n_pending = n_pending, only_key = if (is.na(ONLY_KEY)) "" else ONLY_KEY,
         note = "큐 상단 논문에서 원문 링크를 못 얻었다(또는 지정 논문이 착수 불가) — 원문 없는 착수 금지")
    return(0L)
  }
  pick$compute_class <- NULL; pick$compute_basis <- NULL
  body <- list(requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), source = "next_replication_v10_01",
               reason = "v10.01 — 큐 다음 논문 충실구현(리서치 프로그램 재료 확보)", paper = pick, status = "pending")
  if (!is.na(SLOT_ARG)) body$slot <- SLOT_ARG
  txt <- toJSON(body, auto_unbox = TRUE, pretty = TRUE, null = "null")
  tmp <- paste0(REQ_P, ".tmp"); writeLines(txt, tmp, useBytes = TRUE)
  if (!file.rename(tmp, REQ_P)) stop("요청 파일 교체 실패")
  jlog("replication_requested", paper_key = pick$paper_key %||% "", title = substr(pick$title %||% "", 1, 100),
       slot = if (is.na(SLOT_ARG)) "" else SLOT_ARG, req = REQ_P)
  0L
}

rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
quit(status = as.integer(rc))
