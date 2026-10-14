#==============================================================================
# rf_reimplement_queue.R — 재구현 대기열 소비 (2026-09-07)
#
# 배경: 사후 충실도 감사 misdeclared 논문의 재구현을 도훈이 승인했는데(2026-09-06) replication_request.json 은
#   슬롯이 하나라 두 번째 논문은 06_Registry/reimplement_queue.json(schema reimplement_queue_v1)에 **예약만** 됐고
#   소비자가 없었다 — 생산자만 있는 계기(이 저장소의 반복 형태).
# 소비자 = 02_Infrastructure/programs/next_replication.R (v10.01 · 구 reinforce_auto_next_paper.R §1.8 승계) — 활성 entry 0 · 요청 종결 뒤, 큐 상단 논문(rf_next_paper_pick.py)보다
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

#' 예약 항목 검사 — 문제 목록(빈 벡터 = 유효). kind = reimplement(기본) | ruling(감사 상충 수용 판정 · 2026-10-14 리뷰 C5)
rf_reimplement_queue_entry_problems <- function(e) {
  p <- character(0)
  if (!is.list(e)) return("항목이 객체가 아니다")
  if (!nzchar(as.character(e$paper_key %||% "")[1])) p <- c(p, "paper_key 없음")
  if (!nzchar(as.character(e$url %||% "")[1])) p <- c(p, "url 없음")
  kind <- as.character(e$kind %||% "reimplement")[1]
  if (!(kind %in% c("reimplement", "ruling"))) p <- c(p, paste0("kind 어휘 밖: ", kind))
  if (identical(kind, "ruling")) {
    r <- e$audit_ruling
    if (!is.list(r)) p <- c(p, "audit_ruling 없음")
    else {
      if (!(as.character(r$action %||% "")[1] %in% c("proceed", "proceed_suspect"))) p <- c(p, "audit_ruling$action ∉ proceed|proceed_suspect")
      if (!nzchar(as.character(r$engine_md5 %||% "")[1])) p <- c(p, "audit_ruling$engine_md5 없음(판정을 엔진에 묶는다 — audit_conflict.json)")
    }
    if (!nzchar(as.character(e$wdir %||% "")[1])) p <- c(p, "wdir 없음(판정 대상 엔진의 작업 디렉터리)")
  }
  p
}

#' 예약 쓰기 — 세션 판정(재구현 · 수용)을 대기열에 싣는다(SKILL alpha-search §5 · 2026-10-14 리뷰 C5 · C6).
#'   ★손으로 JSON 을 고치지 않는다: 검사(entry_problems) · 같은 논문 중복 예약 거부 · order · lane_mode 유도 · 원자 기록을 한 자리에서.
#'   수용(kind=ruling)은 지금 engine.R 지문이 audit_ruling$engine_md5 와 같아야 한다(판정 대상 = 그 엔진).
#' @param entry list(paper_key, url, wdir, kind, decided_by, decision, [paper_title, audit_feedback, audit_feedback_mode,
#'   audit_retries, audit_verdict, audit, prior, lane_mode, audit_ruling = list(action, engine_md5, decision, by, feedback)])
#' @return list(ok, order) — 실패면 stop(쓰지 않는다)
rf_reimplement_queue_reserve <- function(root, entry, jlog = function(event, ...) NULL,
                                         now = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")) {
  entry$kind <- as.character(entry$kind %||% "reimplement")[1]
  bad <- rf_reimplement_queue_entry_problems(entry)
  if (!nzchar(as.character(entry$decided_by %||% "")[1])) bad <- c(bad, "decided_by 없음")
  if (identical(entry$kind, "reimplement") && !nzchar(as.character(entry$audit_feedback %||% "")[1]))
    bad <- c(bad, "재구현 예약에 audit_feedback(판정한 지적) 없음")
  wd <- as.character(entry$wdir %||% "")[1]
  wda <- if (nzchar(wd) && !grepl("^([A-Za-z]:|/)", wd)) file.path(root, wd) else wd
  if (identical(entry$kind, "ruling") && nzchar(wda)) {
    ep <- file.path(wda, "engine.R")
    cur <- if (file.exists(ep)) unname(tools::md5sum(ep)) else ""
    if (!identical(cur, as.character(entry$audit_ruling$engine_md5 %||% "")[1]))
      bad <- c(bad, "지금 engine.R 지문 ≠ audit_ruling$engine_md5 — 판정 대상 엔진이 아니다")
  }
  if (length(bad)) stop("[rf_reimplement_queue_reserve] 예약 거부: ", paste(bad, collapse = " · "))
  qp <- rf_reimplement_queue_path(root)
  rd <- rf_reimplement_queue_read(qp)
  qd <- if (isTRUE(rd$ok)) rd$data else if (identical(rd$reason, "missing")) list(schema = "reimplement_queue_v1", entries = list())
        else stop("[rf_reimplement_queue_reserve] 대기열 판독 불가(", rd$reason, ") — 쓰지 않는다")
  dup <- vapply(qd$entries, function(x) is.list(x) && identical(as.character(x$paper_key %||% ""), entry$paper_key) &&
                  identical(as.character(x$status %||% ""), "reserved"), logical(1))
  if (any(dup)) stop("[rf_reimplement_queue_reserve] 같은 논문의 reserved 예약이 이미 있다: ", entry$paper_key)
  ords <- vapply(qd$entries, function(x) suppressWarnings(as.numeric(x$order %||% NA)), numeric(1))
  entry$order <- if (any(is.finite(ords))) max(ords[is.finite(ords)]) + 1 else 1
  entry$status <- "reserved"; entry$queued_at <- now
  if (is.null(entry$source)) entry$source <- "session"
  if (is.null(entry$lane_mode) && nzchar(wd)) entry$lane_mode <- if (grepl("RP_AUTO_CLEAN_", wd, fixed = TRUE)) "clean" else "normal"
  qd$entries <- c(qd$entries, list(entry))
  .rq_write_json(qd, qp)
  jlog("reimplement_queue_reserved", paper_key = entry$paper_key, order = entry$order, kind = entry$kind,
       lane_mode = entry$lane_mode %||% "", decision = as.character(entry$decision %||% "")[1])
  list(ok = TRUE, order = entry$order)
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

  ## 3) 첫 유효 항목(paper_key·url 필수 · kind=ruling 이면 판정 처분 · 엔진 지문 필수). 무효 항목은 저널만 남기고 건너뛴다 — 마킹하지 않는다
  pick_i <- NA_integer_
  for (i in idx) {
    e <- ent[[i]]
    bad <- rf_reimplement_queue_entry_problems(e)
    if (!length(bad)) { pick_i <- i; break }
    jlog("reimplement_queue_entry_invalid", order = e$order %||% NA, paper_key = as.character(e$paper_key %||% ""),
         problems = paste(bad, collapse = " · "), note = "무효 예약 — 건너뜀(손으로 보완할 것)")
  }
  if (is.na(pick_i)) return(list(issued = FALSE, reason = "no_valid_reserved"))
  e  <- ent[[pick_i]]
  pk <- as.character(e$paper_key)
  kind <- as.character(e$kind %||% "reimplement")[1]
  wd_e <- as.character(e$wdir %||% "")[1]; if (is.na(wd_e)) wd_e <- ""
  ## 레인 모드 = 항목 명시 > 작업 디렉터리 접두(RP_AUTO_CLEAN_ = 청정) — 요청에 실어 cmd_mode 가 persisted 로 읽게 한다(리뷰 C2 · C6:
  ##   구판 요청에는 lane_mode 가 없어 legacy_in_flight → normal 로 풀렸고, 청정 논문이 다른 작업 디렉터리에서 재구현됐다)
  lm <- as.character(e$lane_mode %||% "")[1]
  if (is.na(lm) || !(lm %in% c("clean", "normal"))) lm <- if (grepl("RP_AUTO_CLEAN_", wd_e, fixed = TRUE)) "clean" else if (nzchar(wd_e)) "normal" else NA_character_

  ## 3') 스킵리스트 — 감사 상충 보류(held_audit_conflict)는 이 예약이 곧 세션 판정이므로 발행과 함께 푼다(리뷰 U7: 구판은 보류 해제를
  ##   빠뜨리면 레인 착수 관문이 skipped_by_skiplist 로 떨어뜨려 예약이 조용히 사라졌다). 그 밖의 활성 항목(재현 불가 등)이면 발행하지 않는다.
  skp <- file.path(root, "06_Registry/replication_skiplist.json")
  sk <- if (file.exists(skp)) tryCatch(fromJSON(skp, simplifyVector = FALSE), error = function(err) NULL) else NULL
  live <- if (is.list(sk)) which(vapply(sk$entries %||% list(), function(x) is.list(x) &&
            identical(as.character(x$paper_key %||% ""), pk) && !identical(as.character(x$status %||% ""), "revoked"), logical(1))) else integer(0)
  if (length(live)) {
    sts <- vapply(sk$entries[live], function(x) as.character(x$status %||% ""), character(1))
    if (!all(sts == "held_audit_conflict")) {
      jlog("reimplement_queue_blocked_by_skiplist", paper_key = pk, order = e$order %||% NA, status = paste(sts, collapse = ","),
           note = "스킵리스트 활성 항목(감사 상충 보류 외) — 발행하지 않는다(철회 = status=revoked)")
      return(list(issued = FALSE, reason = "blocked_by_skiplist"))
    }
  }

  ## 4) 요청 본문 — verify 의 reimplement 분기와 같은 키. ★sprintf 인자는 전부 길이 1 보장(길이 0 이면 문자열 전체가 빈다)
  req_new <- list(
    requested_at = now,
    source = "next_replication(reimplement_queue)",
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
    audit = e$audit, wdir = e$wdir, decided_by = e$decided_by, queued_at = e$queued_at, queue_order = e$order,
    kind = kind, decision = e$decision)
  if (!is.na(lm)) { req_new$lane_mode <- lm; req_new$lane_mode_source <- "reimplement_queue"; req_new$lane_mode_at <- now }
  ## 청정 레인은 audit_feedback_mode=clean 인 지적만 재구현 프롬프트에 싣는다 — 세션이 원문 판정으로 쓴 피드백이면 예약에 clean 을 적는다
  if (!is.null(e$audit_feedback_mode)) req_new$audit_feedback_mode <- as.character(e$audit_feedback_mode)[1]
  if (identical(kind, "ruling")) {
    ## 수용 판정 운반(리뷰 C5) — 레인은 failure=audit_ruled + 엔진 있음이면 에이전트 없이 검증기만 돌고, 감사 관문은 엔진 지문이 같을 때만 판정을 적용한다
    req_new$failure <- "audit_ruled"
    req_new$audit_ruling <- e$audit_ruling
    req_new$reason <- sprintf("재구현 대기열 order %s — 감사 상충 세션 판정(%s · %s) 반영 · 검증기만 재실행(에이전트 없음)",
                              as.character(e$order %||% "?"), as.character(e$audit_ruling$action %||% "?"),
                              as.character(e$decision %||% e$decided_by %||% "?"))
  }

  ## 5) 대기열 먼저 issued 로 — 실패하면 발행하지 않는다(폴백)
  qd$entries[[pick_i]]$status         <- "issued"
  qd$entries[[pick_i]]$issued_at      <- now
  qd$entries[[pick_i]]$issued_request <- "06_Registry/replication_request.json"
  qd$entries[[pick_i]]$issued_by      <- "next_replication(rf_reimplement_queue_take)"
  wq <- tryCatch({ .rq_write_json(qd, qp); TRUE },
                 error = function(err) { jlog("reimplement_queue_write_failed", stage = "queue", err = conditionMessage(err)); FALSE })
  if (!isTRUE(wq)) return(list(issued = FALSE, reason = "queue_write_failed"))
  .revert_queue <- function() {
    qd$entries[[pick_i]]$status <- "reserved"
    qd$entries[[pick_i]]$issued_at <- NULL; qd$entries[[pick_i]]$issued_request <- NULL; qd$entries[[pick_i]]$issued_by <- NULL
    tryCatch(.rq_write_json(qd, qp), error = function(err) jlog("reimplement_queue_revert_failed", err = conditionMessage(err)))
  }

  ## 5') 감사 상충 보류 해제 — 요청보다 먼저(레인 착수 관문이 보류를 보고 떨어뜨리지 않게). 실패하면 대기열을 되돌리고 발행하지 않는다
  sk0 <- sk
  if (length(live)) {
    for (j in live) {
      sk$entries[[j]]$status <- "revoked"; sk$entries[[j]]$revoked_at <- now
      sk$entries[[j]]$revoked_by <- sprintf("reimplement_queue(order %s · %s)", as.character(e$order %||% "?"), kind)
    }
    ws <- tryCatch({ .rq_write_json(sk, skp); TRUE },
                   error = function(err) { jlog("reimplement_queue_write_failed", stage = "skiplist", err = conditionMessage(err)); FALSE })
    if (!isTRUE(ws)) { .revert_queue(); return(list(issued = FALSE, reason = "skiplist_write_failed")) }
    jlog("reimplement_queue_hold_lifted", paper_key = pk, order = e$order %||% NA, kind = kind,
         note = "감사 상충 보류(held_audit_conflict) → revoked — 이 예약이 세션 판정이다")
  }

  ## 6) 요청 발행 — 실패하면 대기열을 reserved 로 · 스킵리스트를 원래대로 되돌린다(best-effort)
  wr <- tryCatch({ .rq_write_json(req_new, req_path); TRUE },
                 error = function(err) { jlog("reimplement_queue_write_failed", stage = "request", err = conditionMessage(err)); FALSE })
  if (!isTRUE(wr)) {
    .revert_queue()
    if (length(live)) tryCatch(.rq_write_json(sk0, skp), error = function(err) jlog("reimplement_queue_revert_failed", stage = "skiplist", err = conditionMessage(err)))
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
  stale <- if (identical(kind, "ruling")) list(action = "none")      # 수용 판정 = 지금 엔진을 그대로 잰다(옮기면 판정 대상이 사라진다)
           else if (identical(as.character(e$source %||% "")[1], "audit_conflict"))
             ## 감사 상충 뒤 재구현 — 상충 분기는 엔진을 옮기지 않았다(판정 대상 보존). 재구현 판이 시작되기 전에 다음 기각 번호로 옮긴다
             ##   (레인 전제 = 재구현 전 engine.R 부재 · 프롬프트 '앞 판은 engine.rejected*.R' 와 같은 자리 · 정보 손실 0)
             tryCatch({
               ep <- file.path(wd, "engine.R")
               if (!file.exists(ep)) list(action = "none") else {
                 to <- file.path(wd, sprintf("engine.rejected%d.R", length(rej) + 1L))
                 if (file.exists(to)) to <- file.path(wd, sprintf("engine.rejected%d_%d.R", length(rej) + 1L, Sys.getpid()))
                 if (isTRUE(suppressWarnings(file.rename(ep, to)))) list(action = "moved_conflict", to = to) else list(action = "rename_failed", to = to)
               }
             }, error = function(err) list(action = "error", err = conditionMessage(err)))
           else tryCatch(.rq_stale_engine(wd, rej, now), error = function(err) list(action = "error", err = conditionMessage(err)))
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
