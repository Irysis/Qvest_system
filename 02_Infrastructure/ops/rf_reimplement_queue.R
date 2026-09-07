#==============================================================================
# rf_reimplement_queue.R — 재구현 대기열 소비 (2026-09-07)
#
# 배경: 사후 충실도 감사 misdeclared 논문의 재구현을 도훈이 승인했는데(2026-09-06) replication_request.json 은
#   슬롯이 하나라 두 번째 논문은 06_Registry/reimplement_queue.json(schema reimplement_queue_v1)에 **예약만** 됐고
#   소비자가 없었다 — 생산자만 있는 계기(이 저장소의 반복 형태).
# 소비자 = reinforce_auto_next_paper.R §1.8 — 활성 entry 0 · 요청 종결 뒤, 큐 상단 논문(rf_next_paper_pick.py)보다
#   **먼저** 집는다. ★selector 의 소비 술어는 그대로다(원장에 있는 논문 = 소비됨). 대기열은 그 술어에 대한 명시적
#   override 다 — 도훈 결정으로 reserved 된 항목만 들어오고, issued 로 바뀌면 다시 집지 않는다.
# 발행 형태 = rf_replication_verify.R 의 reimplement 분기와 같은 키(status=pending · audit_retries · audit_verdict ·
#   audit_feedback · prior_implementation). 레인(rf_replication_auto.sh)은 audit_feedback 로 reimplement_with_audit
#   프롬프트를 만들고 wdir 의 engine.rejected*.R 을 참조하므로 레인은 바뀌지 않는다.
# 실패 계약: 파일 부재·파손·스키마 불일치 → jlog("reimplement_queue_unreadable") 후 issued=FALSE — **절대 죽지 않는다**
#   (호출자는 현행 경로로 폴백). 쓰기 순서 = 대기열(issued) 먼저 · 요청 나중. 반대면 대기열 갱신 실패 시 같은 논문이
#   요청 종결마다 다시 발행된다(무한 재구현). 요청 쓰기가 실패하면 대기열을 reserved 로 되돌린다(best-effort).
# 검사: 08_Tests/ops/test_rf_reimplement_queue.R (함수 단위 + 샌드박스 e2e + 소스 재도출, 양방향)
#==============================================================================
suppressMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

rf_reimplement_queue_path <- function(root) file.path(root, "06_Registry/reimplement_queue.json")

## 원자적 JSON 쓰기 — tmp 에 UTF-8 바이트로 쓰고 rename. 재파싱·rename 실패는 stop (호출자가 잡는다 · 원본 불변).
##   ★선삭제·copy 폴백 없음(Windows 원자적 쓰기 카드 — copy 폴백이 절단원). rename 은 OneDrive 잠금 대비 3회.
.rq_write_json <- function(obj, path) {
  txt <- toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA)
  if (is.null(tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)))
    stop(sprintf("[rf_reimplement_queue] 쓰기 직전 재파싱 실패 — 원본 불변: %s", path))
  tmp <- sprintf("%s.tmp%d", path, Sys.getpid())
  con <- file(tmp, open = "wb")
  wrote <- tryCatch({ writeBin(charToRaw(enc2utf8(paste0(as.character(txt), "\n"))), con); TRUE },
                    error = function(e) FALSE, finally = close(con))
  if (!isTRUE(wrote)) { unlink(tmp); stop(sprintf("[rf_reimplement_queue] tmp 쓰기 실패: %s", tmp)) }
  renamed <- FALSE
  for (i in 1:3) { renamed <- isTRUE(suppressWarnings(file.rename(tmp, path))); if (renamed) break; Sys.sleep(0.2) }
  if (!renamed) { unlink(tmp); stop(sprintf("[rf_reimplement_queue] rename 실패: %s", path)) }
  invisible(path)
}

#' 대기열 읽기. list(ok=TRUE, data=<list>) 또는 list(ok=FALSE, reason=missing|parse_error|schema, err=<chr>)
rf_reimplement_queue_read <- function(path) {
  if (!file.exists(path)) return(list(ok = FALSE, reason = "missing", err = ""))
  d <- tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) e)
  if (inherits(d, "error")) return(list(ok = FALSE, reason = "parse_error", err = conditionMessage(d)))
  sch <- if (is.list(d)) d$schema else NULL
  if (!is.list(d) || !identical(sch, "reimplement_queue_v1") || !is.list(d$entries))
    return(list(ok = FALSE, reason = "schema", err = sprintf("schema=%s", as.character(sch %||% "NA"))))
  list(ok = TRUE, data = d)
}

#' 재구현 대기열에서 reserved 항목 1건을 집어 충실구현 요청으로 발행한다.
#' @param root 저장소 루트 · req_path 요청 파일(06_Registry/replication_request.json) 경로
#' @param prev 직전 소진 entry 요약(next_paper 의 best · 요청의 prev 필드) — 없으면 NULL
#' @param jlog 저널 함수(event, ...) — next_paper 의 jlog 를 넘긴다. 기본 = 무동작
#' @return list(issued=TRUE, paper_key, entry, request, rejected_engines) 또는 list(issued=FALSE, reason=<chr>)
rf_reimplement_queue_take <- function(root, req_path, prev = NULL, jlog = function(event, ...) NULL,
                                      now = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")) {
  qp <- rf_reimplement_queue_path(root)
  ## 0) 요청 슬롯이 바쁘면 손대지 않는다 — next_paper §1.7 과 같은 관문(함수 단독 호출도 안전하게)
  req <- if (file.exists(req_path)) tryCatch(fromJSON(req_path, simplifyVector = FALSE), error = function(e) NULL) else NULL
  st  <- as.character((if (is.list(req)) req$status else NULL) %||% "")
  if (st %in% c("pending", "in_progress", "failed_needs_session"))
    return(list(issued = FALSE, reason = "request_busy", request_status = st))

  ## 1) 대기열 읽기 — 부재·파손·스키마 불일치는 경고 저널 + 폴백(죽지 않는다)
  rd <- rf_reimplement_queue_read(qp)
  if (!isTRUE(rd$ok)) {
    jlog("reimplement_queue_unreadable", reason = rd$reason %||% "?", err = substr(as.character(rd$err %||% ""), 1, 200),
         path = qp, note = "재구현 대기열을 못 읽었다 — 현행 경로(큐 상단 논문)로 폴백")
    return(list(issued = FALSE, reason = paste0("unreadable_", rd$reason %||% "?")))
  }
  qd  <- rd$data
  ent <- qd$entries

  ## 2) reserved 항목 · order 오름차순(결측·비수치 order 는 뒤로 · 동순위는 파일 순서)
  idx <- which(vapply(ent, function(e) is.list(e) && identical(as.character(e$status %||% ""), "reserved"), logical(1)))
  if (!length(idx)) return(list(issued = FALSE, reason = "no_reserved"))
  ord <- vapply(idx, function(i) tryCatch(suppressWarnings(as.numeric(ent[[i]]$order %||% NA_real_)),
                                          error = function(e) NA_real_), numeric(1))
  ord[!is.finite(ord)] <- Inf
  idx <- idx[order(ord, seq_along(idx))]

  ## 3) 첫 유효 항목(paper_key·url 필수). 무효 항목은 저널만 남기고 건너뛴다 — 마킹하지 않는다(손으로 보완할 수 있게)
  pick_i <- NA_integer_
  for (i in idx) {
    e <- ent[[i]]
    if (nzchar(as.character(e$paper_key %||% "")) && nzchar(as.character(e$url %||% ""))) { pick_i <- i; break }
    jlog("reimplement_queue_entry_invalid", order = e$order %||% NA, paper_key = as.character(e$paper_key %||% ""),
         note = "paper_key·url 없는 예약 — 건너뜀(손으로 보완할 것)")
  }
  if (is.na(pick_i)) return(list(issued = FALSE, reason = "no_valid_reserved"))
  e  <- ent[[pick_i]]
  pk <- as.character(e$paper_key)

  ## 4) 요청 본문 — verify 의 reimplement 분기와 같은 키. ★sprintf 인자는 전부 길이 1 보장(길이 0 이면 문자열 전체가 빈다)
  req_new <- list(
    requested_at = now,
    source = "reinforce_auto_next_paper(reimplement_queue)",
    reason = sprintf("재구현 대기열 order %s — 사후 충실도 감사 %s 재구현(%s). 원장 소비 술어 override: 도훈 예약 항목만 · issued 후 재집기 없음",
                     as.character(e$order %||% "?"), as.character(e$audit_verdict %||% "misdeclared"),
                     as.character(e$decided_by %||% "예약자 미기재")),
    prev = prev,
    paper = list(title = as.character(e$paper_title %||% pk), paper_title = as.character(e$paper_title %||% pk),
                 url = as.character(e$url), paper_key = pk, source = "reimplement_queue"),
    status = "pending",
    prior_implementation = e$prior,
    audit_retries  = as.integer(e$audit_retries %||% 1L),
    audit_verdict  = as.character(e$audit_verdict %||% "misdeclared"),
    audit_feedback = as.character(e$audit_feedback %||% ""),
    audit = e$audit, wdir = e$wdir, decided_by = e$decided_by, queued_at = e$queued_at, queue_order = e$order)

  ## 5) 대기열 먼저 issued 로 — 실패하면 발행하지 않는다(폴백)
  qd$entries[[pick_i]]$status         <- "issued"
  qd$entries[[pick_i]]$issued_at      <- now
  qd$entries[[pick_i]]$issued_request <- "06_Registry/replication_request.json"
  qd$entries[[pick_i]]$issued_by      <- "reinforce_auto_next_paper(rf_reimplement_queue_take)"
  wq <- tryCatch({ .rq_write_json(qd, qp); TRUE },
                 error = function(err) { jlog("reimplement_queue_write_failed", stage = "queue", err = conditionMessage(err)); FALSE })
  if (!isTRUE(wq)) return(list(issued = FALSE, reason = "queue_write_failed"))

  ## 6) 요청 발행 — 실패하면 대기열을 reserved 로 되돌린다(best-effort)
  wr <- tryCatch({ .rq_write_json(req_new, req_path); TRUE },
                 error = function(err) { jlog("reimplement_queue_write_failed", stage = "request", err = conditionMessage(err)); FALSE })
  if (!isTRUE(wr)) {
    qd$entries[[pick_i]]$status <- "reserved"
    qd$entries[[pick_i]]$issued_at <- NULL; qd$entries[[pick_i]]$issued_request <- NULL; qd$entries[[pick_i]]$issued_by <- NULL
    tryCatch(.rq_write_json(qd, qp), error = function(err) jlog("reimplement_queue_revert_failed", err = conditionMessage(err)))
    return(list(issued = FALSE, reason = "request_write_failed"))
  }

  ## 7) 기각 엔진이 engine.R 로도 남아 있으면 치운다 — verify 의 reimplement 분기는 rename 으로 engine.R 을 비우고, 레인은
  ##    "engine.R 부재 = 기각 뒤 정상 경로" 를 전제한다(에이전트 뒤 `-s engine.R` 존재만 본다 · mtime 대조 없음). 세션이 copy 로
  ##    예약한 wdir(2006.04639 실측: engine.R == engine.rejected1.R)엔 기각 엔진이 그대로 있어, 에이전트가 엔진을 못 내는 tick 에
  ##    레인이 낡은 엔진을 재측정·감사 → proceed_suspect 로 논문을 같은 잘못된 구현으로 소비한다(재시도가 아니라 되풀이).
  ##    ★바이트 동일한 rejected 사본이 있을 때만 옮긴다(정보 손실 0) — 다르면 손대지 않고 저널만 남긴다.
  wd  <- as.character(e$wdir %||% "")
  if (nzchar(wd) && !grepl("^([A-Za-z]:|/)", wd)) wd <- file.path(root, wd)
  rej <- if (nzchar(wd) && dir.exists(wd)) list.files(wd, pattern = "^engine[.]rejected[0-9]*[.]R$") else character(0)
  stale <- tryCatch(.rq_stale_engine(wd, rej, now), error = function(err) list(action = "error", err = conditionMessage(err)))
  if (!identical(stale$action, "none"))
    jlog("reimplement_queue_stale_engine", paper_key = pk, action = stale$action, to = stale$to %||% "", err = stale$err %||% "",
         note = "기각 사본과 동일한 engine.R 은 옮긴다(레인 전제 = 기각 뒤 engine.R 부재) · 다르면 보존")
  jlog("reimplement_queue_issued", paper_key = pk, order = e$order %||% NA, audit_retries = req_new$audit_retries,
       audit_verdict = req_new$audit_verdict, wdir = as.character(e$wdir %||% ""), rejected_engines = length(rej),
       stale_engine = stale$action, path = req_path,
       note = "재구현 대기열 항목으로 충실구현 요청 발행 — 큐 상단 논문·결합 착수보다 우선(도훈 예약)")
  list(issued = TRUE, paper_key = pk, entry = e, request = req_new, rejected_engines = rej, stale_engine = stale)
}

#' wdir 의 engine.R 이 engine.rejected*.R 중 하나와 바이트 동일하면 engine.rejected_copy_<ts>.R 로 옮긴다.
#' @return list(action = "none"|"moved"|"kept_different"|"rename_failed", to = <chr>)
.rq_stale_engine <- function(wd, rej, now = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")) {
  eng <- if (nzchar(wd)) file.path(wd, "engine.R") else ""
  if (!nzchar(eng) || !file.exists(eng) || !length(rej)) return(list(action = "none"))
  same <- vapply(rej, function(r) {
    p <- file.path(wd, r)
    isTRUE(file.info(p)$size == file.info(eng)$size) && identical(tools::md5sum(p)[[1]], tools::md5sum(eng)[[1]])
  }, logical(1))
  if (!any(same)) return(list(action = "kept_different"))
  ts <- gsub("[^0-9]", "", substr(now, 1, 19))
  to <- file.path(wd, sprintf("engine.rejected_copy_%s.R", ts))
  if (file.exists(to)) to <- file.path(wd, sprintf("engine.rejected_copy_%s_%d.R", ts, Sys.getpid()))
  if (isTRUE(suppressWarnings(file.rename(eng, to)))) list(action = "moved", to = to) else list(action = "rename_failed", to = to)
}
