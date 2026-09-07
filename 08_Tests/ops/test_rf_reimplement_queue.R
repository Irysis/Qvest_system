#!/usr/bin/env Rscript
#==============================================================================
# test_rf_reimplement_queue.R — next_paper 가 재구현 대기열을 큐 상단보다 먼저 집는다 (2026-09-07)
#
# 배경: 사후 충실도 감사 misdeclared 재구현을 도훈이 승인(2026-09-06)했는데 요청 슬롯이 하나라 두 번째 논문
#   (2006.04639)은 06_Registry/reimplement_queue.json 에 reserved 로 예약만 되고 소비자가 없었다.
# 판정(양방향 · 격리 픽스처 — 운영 원장·요청·대기열·저널 무접촉 · 샌드박스 root + R_ENVIRON_USER 격리):
#   A. 함수 단위 rf_reimplement_queue_take(root, req_path)
#      A1 양성: reserved 2건(파일 순서 order 2, 1) → order 1 발행 · 요청 키 = verify reimplement 분기와 동일 · 항목 issued · order 2 는 reserved 유지
#      A2 요청 pending → request_busy · 대기열 바이트 불변      A3 요청 종결 후 재호출 → order 2 발행 · 그 다음 → no_reserved
#      A4 파일 부재 → unreadable(missing) 폴백   A5 JSON 파손 → unreadable(parse_error) · 죽지 않음   A6 스키마 불일치 → unreadable(schema)
#      A7 url 없는 예약은 건너뛰고 다음 유효 항목 발행 · 건너뛴 항목은 손대지 않는다
#   B. 샌드박스 e2e (reinforce_auto_next_paper.R 실행)
#      P1 요청 done + reserved → reimplement_queue_issued(저널·stdout) · 새 논문 pick·결합 착수 미호출 · 요청 파일 형태 · 원장 불변
#      P2 소진 entry 가 있으면 handed_off(reason=reimplement_queue) — 승격·다음 논문 경로와 같은 writer
#      V1 요청 pending → halt_request_pending · 대기열·요청 바이트 불변 · 발행 없음
#      V2 항목이 이미 issued → 발행 없음 · 정상 pick 경로(큐 단계) 폴백 · 대기열 바이트 불변
#      V3 대기열 JSON 파손 → reimplement_queue_unreadable · 큐 단계 폴백 · fatal 없음 · rc 0
#   C. 소스 재도출: 러너가 rf_reimplement_queue_take 를 실제로 부르며 그 호출은 §1.7 관문 뒤 · pick · 결합 착수 앞에 선다
#      (좌표 단정 없음 — 주석 제거 코드에서 상대 순서만 본다)
#==============================================================================
suppressMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
tail_of <- function(o, n = 400L) substr(o, max(1L, nchar(o) - n), nchar(o))
fbytes <- function(p) if (file.exists(p)) readBin(p, "raw", file.info(p)$size) else raw(0)
rj <- function(p) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)

suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_reimplement_queue.R")))

# ── 픽스처 ─────────────────────────────────────────────────────────────────────
slug <- function(key) gsub("[^A-Za-z0-9]", "_", key)
mk_entry <- function(order, key, status = "reserved", url = sprintf("https://arxiv.org/abs/%s", key),
                     title = sprintf("Fixture %s", key)) list(
  order = order, paper_key = key, url = url, paper_title = title,
  wdir  = sprintf("04_Research/strategies/RP_AUTO_%s", slug(key)),
  audit = sprintf("04_Research/strategies/RP_AUTO_%s/fidelity_audit.json", slug(key)),
  prior = list(base_id = sprintf("RP_T_%s_prior", slug(key)), grade = "F", port_t = -2.874,
               artifacts = "stage_artifacts/replication/fixture", status = "parked"),
  audit_verdict = "misdeclared", audit_retries = 1L,
  audit_feedback = "- 미신고 변경: [undeclared] 픽스처 — 일별 수익 정의(종가-종가 vs 일중)",
  decided_by = "도훈 2026-09-06 (fixture)", queued_at = "2026-09-06T19:16:27+0900", after = "fixture", status = status)
mk_queue <- function(entries, schema = "reimplement_queue_v1")
  as.character(toJSON(list(schema = schema, note = "fixture", entries = entries), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"))
mk_req <- function(status) sprintf('{"requested_at":"2026-09-06T00:00:00+0900","source":"fixture","status":"%s","paper":{"paper_key":"2404.08129","url":"https://arxiv.org/abs/2404.08129","title":"fixture"}}', status)
mk_ledger <- function(entries = list()) list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, entries = entries,
  combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()), last_updated = "")
## 소진 entry(F · 요약 완료) — 승격 자격 없음(grade_below_min) → 관문 통과 후 §1.8 에서 handed_off 표식이 남아야 한다
E_exh <- list(base_id = "RP_T_EXH", status = "exhausted", base_grade = "F", max_attempts = 25L, paper_key = "t", paper_id = "t",
              engine_path = "", base_artifacts = "", summarized_at = "2026-09-06T00:00:00+0900",
              attempts = list(list(n = 1L, cell_code = "B1_1", grade = "F", essence = list(port_t = 0.1, cell_code = "B1_1", spec = ""), artifacts = "")))
## 원장에 이미 소비된(parked) 항목 — selector 술어로는 소비됨. 대기열은 그 위의 명시적 override 다(픽스처가 그 상황을 그대로 본뜬다)
E_parked <- list(base_id = "RP_T_2006_04639_prior", status = "parked", base_grade = "F", paper_key = "2006.04639", attempts = list(), attempts_used = 0L)

newdir <- function(tag) { S <- file.path(tempdir(), paste0(tag, "_", Sys.getpid(), "_", as.integer(runif(1, 1, 1e6)))); dir.create(file.path(S, "06_Registry"), recursive = TRUE, showWarnings = FALSE); S }
ev_collect <- function() { env <- new.env(); env$ev <- list(); list(fn = function(event, ...) env$ev[[length(env$ev) + 1L]] <- c(list(event = event), list(...)), env = env) }
evnames <- function(col) vapply(col$env$ev, function(x) x$event, character(1))
REQ_CHECK <- function(r, key, title) {
  c(status = identical(r$status, "pending"), paper_key = identical(r$paper$paper_key, key), source = identical(r$paper$source, "reimplement_queue"),
    url = nzchar(r$paper$url %||% ""), paper_title = identical(r$paper$paper_title, title), title = identical(r$paper$title, title),
    audit_retries = identical(as.integer(r$audit_retries), 1L), audit_verdict = identical(r$audit_verdict, "misdeclared"),
    audit_feedback = grepl("미신고", r$audit_feedback %||% "", fixed = TRUE),
    prior = identical(r$prior_implementation$base_id, sprintf("RP_T_%s_prior", slug(key))),
    src = identical(r$source, "reinforce_auto_next_paper(reimplement_queue)"), reason = nzchar(r$reason %||% ""), requested_at = nzchar(r$requested_at %||% ""))
}

cat("=== A. 함수 단위 (격리 root) ===\n")
S <- newdir("rq_fn"); RQ <- file.path(S, "06_Registry/replication_request.json"); QP <- file.path(S, "06_Registry/reimplement_queue.json")
writeLines(mk_req("done"), RQ)
writeLines(mk_queue(list(mk_entry(2, "9999.00002"), mk_entry(1, "2006.04639"))), QP, useBytes = TRUE)
col <- ev_collect(); r1 <- rf_reimplement_queue_take(S, RQ, prev = NULL, jlog = col$fn)
if (isTRUE(r1$issued) && identical(r1$paper_key, "2006.04639")) ok("A1 order 오름차순 — 파일 순서가 2,1 이어도 order 1 을 집는다") else ng("A1 발행 실패/순서 오류", paste(r1$reason %||% "", r1$paper_key %||% ""))
rq <- rj(RQ); chk <- if (is.null(rq)) c(parse = FALSE) else REQ_CHECK(rq, "2006.04639", "Fixture 2006.04639")
if (all(chk)) ok("A1 요청 키 = verify reimplement 분기와 동일(status/paper/audit_*/prior_implementation/source/reason/requested_at)") else ng("A1 요청 형태", paste(names(chk)[!chk], collapse = ","))
q1 <- rj(QP)
if (!is.null(q1) && identical(q1$entries[[2]]$status, "issued") && nzchar(q1$entries[[2]]$issued_at %||% "") && identical(q1$entries[[1]]$status, "reserved"))
  ok("A1 발행 항목 issued+issued_at · 다른 예약(order 2)은 reserved 유지") else ng("A1 대기열 갱신", if (is.null(q1)) "재파싱 실패" else paste(q1$entries[[1]]$status, q1$entries[[2]]$status))
if ("reimplement_queue_issued" %in% evnames(col)) ok("A1 저널 이벤트 reimplement_queue_issued") else ng("A1 저널 이벤트 부재", paste(evnames(col), collapse = ","))
b0 <- fbytes(QP); col <- ev_collect(); r2 <- rf_reimplement_queue_take(S, RQ, jlog = col$fn)
if (!isTRUE(r2$issued) && identical(r2$reason, "request_busy") && identical(b0, fbytes(QP))) ok("A2 요청 pending 이면 request_busy · 대기열 바이트 불변") else ng("A2 pending 관문", paste(r2$reason %||% "", identical(b0, fbytes(QP))))
writeLines(mk_req("done_no_reinforce"), RQ)
r3 <- rf_reimplement_queue_take(S, RQ, jlog = col$fn)
if (isTRUE(r3$issued) && identical(r3$paper_key, "9999.00002")) ok("A3 요청 종결 후 재호출 → 다음 예약(order 2) 발행") else ng("A3 두 번째 예약 미발행", r3$reason %||% "")
writeLines(mk_req("done"), RQ)
r4 <- rf_reimplement_queue_take(S, RQ, jlog = col$fn)
if (!isTRUE(r4$issued) && identical(r4$reason, "no_reserved")) ok("A3 예약 소진 → no_reserved(조용한 폴백)") else ng("A3 소진 후 동작", r4$reason %||% "")
unlink(S, recursive = TRUE)

S <- newdir("rq_fn2"); RQ <- file.path(S, "06_Registry/replication_request.json"); QP <- file.path(S, "06_Registry/reimplement_queue.json")
writeLines(mk_req("done"), RQ)
col <- ev_collect(); r5 <- rf_reimplement_queue_take(S, RQ, jlog = col$fn)
e5 <- Filter(function(x) identical(x$event, "reimplement_queue_unreadable"), col$env$ev)
if (!isTRUE(r5$issued) && length(e5) == 1L && identical(e5[[1]]$reason, "missing")) ok("A4 파일 부재 → unreadable(missing) 폴백") else ng("A4 부재 처리", paste(r5$reason %||% "", length(e5)))
writeLines("{not json", QP)
col <- ev_collect(); r6 <- tryCatch(rf_reimplement_queue_take(S, RQ, jlog = col$fn), error = function(e) list(issued = NA, reason = paste0("THREW: ", conditionMessage(e))))
e6 <- Filter(function(x) identical(x$event, "reimplement_queue_unreadable"), col$env$ev)
if (identical(r6$issued, FALSE) && length(e6) == 1L && identical(e6[[1]]$reason, "parse_error")) ok("A5 JSON 파손 → unreadable(parse_error) · 던지지 않는다") else ng("A5 파손 처리", paste(r6$reason %||% "", length(e6)))
writeLines(mk_queue(list(mk_entry(1, "2006.04639")), schema = "something_else"), QP, useBytes = TRUE)
col <- ev_collect(); r7 <- rf_reimplement_queue_take(S, RQ, jlog = col$fn)
e7 <- Filter(function(x) identical(x$event, "reimplement_queue_unreadable"), col$env$ev)
if (!isTRUE(r7$issued) && length(e7) == 1L && identical(e7[[1]]$reason, "schema")) ok("A6 스키마 불일치 → unreadable(schema)") else ng("A6 스키마 처리", paste(r7$reason %||% "", length(e7)))
writeLines(mk_queue(list(mk_entry(1, "0000.00000", url = NULL), mk_entry(2, "2006.04639"))), QP, useBytes = TRUE)
col <- ev_collect(); r8 <- rf_reimplement_queue_take(S, RQ, jlog = col$fn); q8 <- rj(QP)
if (isTRUE(r8$issued) && identical(r8$paper_key, "2006.04639") && "reimplement_queue_entry_invalid" %in% evnames(col) &&
    identical(q8$entries[[1]]$status, "reserved") && identical(q8$entries[[2]]$status, "issued"))
  ok("A7 url 없는 예약은 건너뛰고(저널) 다음 유효 항목 발행 · 무효 항목은 손대지 않는다") else ng("A7 무효 항목 처리", paste(r8$reason %||% "", r8$paper_key %||% "", paste(evnames(col), collapse = ",")))
unlink(S, recursive = TRUE)

## A8 — 기각 사본과 동일한 engine.R 은 옮기고(레인 전제 = 기각 뒤 engine.R 부재), 다른 engine.R 은 보존한다
mk_wdir <- function(S, key, engine_txt, rejected_txt) { W <- file.path(S, sprintf("04_Research/strategies/RP_AUTO_%s", slug(key)))
  dir.create(W, recursive = TRUE, showWarnings = FALSE); writeLines(rejected_txt, file.path(W, "engine.rejected1.R"))
  if (!is.null(engine_txt)) writeLines(engine_txt, file.path(W, "engine.R")); W }
S <- newdir("rq_fn3"); RQ <- file.path(S, "06_Registry/replication_request.json"); QP <- file.path(S, "06_Registry/reimplement_queue.json")
writeLines(mk_req("done"), RQ); writeLines(mk_queue(list(mk_entry(1, "2006.04639"))), QP, useBytes = TRUE)
W <- mk_wdir(S, "2006.04639", "# rejected engine v1", "# rejected engine v1")
col <- ev_collect(); r9 <- rf_reimplement_queue_take(S, RQ, jlog = col$fn)
cp <- list.files(W, pattern = "^engine[.]rejected_copy_.*[.]R$")
if (isTRUE(r9$issued) && identical(r9$stale_engine$action, "moved") && !file.exists(file.path(W, "engine.R")) && length(cp) == 1L &&
    file.exists(file.path(W, "engine.rejected1.R")) && "reimplement_queue_stale_engine" %in% evnames(col))
  ok("A8 engine.R == engine.rejected1.R → engine.R 을 rejected_copy 로 옮김(정보 손실 0 · 저널) · 기각 사본 보존") else ng("A8 동일 엔진 처리", paste(r9$stale_engine$action %||% "", file.exists(file.path(W, "engine.R")), length(cp)))
unlink(S, recursive = TRUE)
S <- newdir("rq_fn4"); RQ <- file.path(S, "06_Registry/replication_request.json"); QP <- file.path(S, "06_Registry/reimplement_queue.json")
writeLines(mk_req("done"), RQ); writeLines(mk_queue(list(mk_entry(1, "2006.04639"))), QP, useBytes = TRUE)
W <- mk_wdir(S, "2006.04639", "# a NEW engine the agent wrote", "# rejected engine v1"); b_eng <- fbytes(file.path(W, "engine.R"))
col <- ev_collect(); r10 <- rf_reimplement_queue_take(S, RQ, jlog = col$fn)
if (isTRUE(r10$issued) && identical(r10$stale_engine$action, "kept_different") && identical(b_eng, fbytes(file.path(W, "engine.R"))) &&
    !length(list.files(W, pattern = "^engine[.]rejected_copy_")))
  ok("A8 engine.R != 기각 사본 → 손대지 않는다(kept_different · 바이트 불변)") else ng("A8 다른 엔진 보존", r10$stale_engine$action %||% "")
unlink(S, recursive = TRUE)
S <- newdir("rq_fn5"); RQ <- file.path(S, "06_Registry/replication_request.json"); QP <- file.path(S, "06_Registry/reimplement_queue.json")
writeLines(mk_req("done"), RQ); writeLines(mk_queue(list(mk_entry(1, "2006.04639"))), QP, useBytes = TRUE)
W <- mk_wdir(S, "2006.04639", NULL, "# rejected engine v1")
col <- ev_collect(); r11 <- rf_reimplement_queue_take(S, RQ, jlog = col$fn)
if (isTRUE(r11$issued) && identical(r11$stale_engine$action, "none") && !("reimplement_queue_stale_engine" %in% evnames(col)))
  ok("A8 engine.R 부재(정상 기각 상태) → none · 저널 소음 없음") else ng("A8 부재 처리", r11$stale_engine$action %||% "")
unlink(S, recursive = TRUE)

cat("\n=== B. 샌드박스 e2e (reinforce_auto_next_paper.R) ===\n")
sbx <- function(req_status = "done", queue = NULL, ledger_entries = list()) {
  S <- newdir("rq_sbx")
  for (d in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", ".cache", "stage_artifacts/paper_recharge", "04_Research/strategies/RP_AUTO_2006_04639"))
    dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(file.path(ROOT, "02_Infrastructure/ops"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/ops"))
  file.copy(list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/reinforcement"))
  file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(S, "06_Registry"))
  file.copy(file.path(ROOT, "02_Infrastructure/config.R"), file.path(S, "02_Infrastructure"))
  writeLines(toJSON(mk_ledger(ledger_entries), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
  writeLines('{"enabled": true}', file.path(S, "06_Registry/reinforce_auto_config.json"))
  if (!is.null(req_status)) writeLines(mk_req(req_status), file.path(S, "06_Registry/replication_request.json"))
  if (!is.null(queue)) writeLines(queue, file.path(S, "06_Registry/reimplement_queue.json"), useBytes = TRUE)
  ## 운영 wdir 상태 그대로 본뜬다(2006.04639 실측): 기각 사본과 **바이트 동일한** engine.R 이 남아 있다(세션이 copy 로 예약)
  writeLines("# fixture — 감사 기각분", file.path(S, "04_Research/strategies/RP_AUTO_2006_04639/engine.rejected1.R"))
  writeLines("# fixture — 감사 기각분", file.path(S, "04_Research/strategies/RP_AUTO_2006_04639/engine.R"))
  file.create(file.path(S, "empty.Renviron"))
  S
}
run_np <- function(S) {
  old <- Sys.getenv(c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER", "QVEST_RF_CONFIG"), unset = NA)
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k])) }, add = TRUE)
  Sys.setenv(QM_ROOT = S, CLAUDE_PROJECT_DIR = S, R_ENVIRON_USER = file.path(S, "empty.Renviron"),
             QVEST_RF_CONFIG = file.path(S, "06_Registry/reinforce_auto_config.json"))
  out <- suppressWarnings(system2("Rscript", shQuote(file.path(S, "02_Infrastructure/ops/reinforce_auto_next_paper.R")), stdout = TRUE, stderr = TRUE))
  list(text = paste(out, collapse = "\n"), rc = as.integer(attr(out, "status") %||% 0L))
}
jl_events <- function(S) { p <- file.path(S, ".cache/reinforce_auto_log.jsonl"); if (!file.exists(p)) return(list())
  Filter(Negate(is.null), lapply(readLines(p, warn = FALSE, encoding = "UTF-8"), function(l) tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL))) }
reached_queue <- function(o) grepl("halt_queue_empty|halt_pick_failed|paper_picked", o)
## ★jlog 줄(`[rf_next] <event>`)에만 앵커 — 원장 로드 배너가 rf_record_combination_review 를 인쇄해 무앵커 패턴은 오탐한다
picked_or_combined <- function(o) grepl("[[]rf_next[]] (paper_picked|halt_queue_empty|halt_pick_failed|combination_[a-z_]+|replication_requested)", o)
QP_S <- function(S) file.path(S, "06_Registry/reimplement_queue.json"); RQ_S <- function(S) file.path(S, "06_Registry/replication_request.json"); LD_S <- function(S) file.path(S, "06_Registry/reinforce_ledger_l1.json")

## P1 — 요청 done + reserved 2건(파일 순서 2,1) + 원장에 parked 사본(소비됨) → 발행 · pick 미호출
S <- sbx("done", mk_queue(list(mk_entry(2, "9999.00002"), mk_entry(1, "2006.04639"))), list(E_parked)); l0 <- fbytes(LD_S(S)); r <- run_np(S); o <- r$text
if (grepl("reimplement_queue_issued", o, fixed = TRUE)) ok("P1 stdout reimplement_queue_issued") else ng("P1 발행 미발화 ★수리 대상", tail_of(o))
ev <- jl_events(S); ei <- Filter(function(x) identical(x$event, "reimplement_queue_issued"), ev)
if (length(ei) == 1L && identical(ei[[1]]$paper_key, "2006.04639") && identical(as.integer(ei[[1]]$rejected_engines), 1L)) ok("P1 저널: paper_key=2006.04639 · wdir 의 engine.rejected1.R 1건 확인") else ng("P1 저널 이벤트", if (length(ei)) paste(ei[[1]]$paper_key, ei[[1]]$rejected_engines) else "0건")
if (!picked_or_combined(o)) ok("P1 새 논문 pick·결합 검토/착수·replication_requested 미호출 — 대기열이 먼저다") else ng("P1 pick/결합 경로가 돌았다", tail_of(o))
rq <- rj(RQ_S(S)); chk <- if (is.null(rq)) c(parse = FALSE) else REQ_CHECK(rq, "2006.04639", "Fixture 2006.04639")
if (all(chk)) ok("P1 요청 파일 형태 = verify reimplement 분기와 동일 키(레인이 읽는 paper_title/url/paper_key/audit_feedback 포함)") else ng("P1 요청 형태", paste(names(chk)[!chk], collapse = ","))
q <- rj(QP_S(S))
if (!is.null(q) && identical(q$entries[[2]]$status, "issued") && identical(q$entries[[1]]$status, "reserved")) ok("P1 대기열: order 1 issued · order 2 reserved 유지") else ng("P1 대기열 갱신", if (is.null(q)) "재파싱 실패" else paste(q$entries[[1]]$status, q$entries[[2]]$status))
if (identical(l0, fbytes(LD_S(S)))) ok("P1 원장 바이트 불변(entry 개설·소비 표기 없음 — 소비는 레인의 verify 소관)") else ng("P1 원장이 바뀌었다")
W1 <- file.path(S, "04_Research/strategies/RP_AUTO_2006_04639")
if (!file.exists(file.path(W1, "engine.R")) && file.exists(file.path(W1, "engine.rejected1.R")) && length(list.files(W1, pattern = "^engine[.]rejected_copy_")) == 1L &&
    grepl("reimplement_queue_stale_engine", o, fixed = TRUE))
  ok("P1 기각 사본과 동일한 engine.R 을 치웠다(레인이 낡은 엔진을 재측정하지 않게) · 사본 보존 · 저널") else ng("P1 낡은 engine.R 잔존 ★되풀이 위험", paste(file.exists(file.path(W1, "engine.R")), length(list.files(W1))))
if (r$rc == 0L && !grepl('"event":"fatal"', o, fixed = TRUE) && !grepl("[[]rf_next[]] fatal", o)) ok("P1 rc 0 · fatal 없음") else ng("P1 rc/fatal", sprintf("rc=%d", r$rc))
unlink(S, recursive = TRUE)

## P2 — 소진 entry(F) 가 있으면 handed_off 표식(reason=reimplement_queue)
S <- sbx("done", mk_queue(list(mk_entry(1, "2006.04639"))), list(E_exh)); r <- run_np(S); o <- r$text
L2 <- rj(LD_S(S)); e2 <- if (!is.null(L2)) Filter(function(x) identical(x$base_id, "RP_T_EXH"), L2$entries) else list()
if (grepl("reimplement_queue_issued", o, fixed = TRUE) && length(e2) == 1L && isTRUE(e2[[1]]$handed_off) && identical(e2[[1]]$handed_off_reason, "reimplement_queue"))
  ok("P2 소진 entry handed_off=TRUE · reason=reimplement_queue (승격·다음 논문 경로와 같은 writer)") else ng("P2 handed_off 표식", if (length(e2)) paste(e2[[1]]$handed_off, e2[[1]]$handed_off_reason) else tail_of(o))
if (!grepl("[[]rf_next[]] promoted", o)) ok("P2 F 소진은 승격 없음(관문 통과 뒤 §1.8 도달)") else ng("P2 승격 발화")
unlink(S, recursive = TRUE)

## V1 — 요청 pending 이면 대기열을 손대지 않는다
S <- sbx("pending", mk_queue(list(mk_entry(1, "2006.04639")))); q0 <- fbytes(QP_S(S)); b0 <- fbytes(RQ_S(S)); r <- run_np(S); o <- r$text
if (grepl("halt_request_pending", o, fixed = TRUE) && !grepl("reimplement_queue_issued", o, fixed = TRUE)) ok("V1 요청 pending → halt_request_pending · 발행 없음") else ng("V1 관문", tail_of(o))
if (identical(q0, fbytes(QP_S(S))) && identical(b0, fbytes(RQ_S(S)))) ok("V1 대기열·요청 바이트 불변") else ng("V1 파일이 덮였다")
unlink(S, recursive = TRUE)

## V2 — 항목이 이미 issued 면 정상 pick 경로로 폴백
S <- sbx("done", mk_queue(list(mk_entry(1, "2006.04639", status = "issued")))); q0 <- fbytes(QP_S(S)); r <- run_np(S); o <- r$text
if (!grepl("reimplement_queue_issued", o, fixed = TRUE) && reached_queue(o)) ok("V2 issued 항목은 안 집는다 → 큐 단계(정상 pick 경로) 폴백") else ng("V2 폴백", tail_of(o))
if (identical(q0, fbytes(QP_S(S)))) ok("V2 대기열 바이트 불변") else ng("V2 대기열이 덮였다")
unlink(S, recursive = TRUE)

## V3 — 대기열 JSON 파손 → 경고 저널 + 폴백 · 죽지 않음
S <- sbx("done", "{not json"); r <- run_np(S); o <- r$text
if (grepl("reimplement_queue_unreadable", o, fixed = TRUE) && reached_queue(o)) ok("V3 파손 → reimplement_queue_unreadable + 큐 단계 폴백") else ng("V3 폴백", tail_of(o))
if (r$rc == 0L && !grepl("[[]rf_next[]] fatal", o) && !grepl("reimplement_queue_failed", o, fixed = TRUE)) ok("V3 rc 0 · fatal/reimplement_queue_failed 없음") else ng("V3 죽었다", sprintf("rc=%d %s", r$rc, tail_of(o)))
unlink(S, recursive = TRUE)

cat("\n=== C. 소스 재도출 — 러너가 실제로 부르는가 · 위치 ===\n")
np <- sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R"), encoding = "UTF-8", warn = FALSE))
i_take <- grep("rf_reimplement_queue_take(", np, fixed = TRUE); i_src <- grep("rf_reimplement_queue.R", np, fixed = TRUE)
i_gate <- grep('jlog("halt_request_pending"', np, fixed = TRUE); i_pick <- grep("rf_next_paper_pick.py", np, fixed = TRUE); i_combo <- grep("rf_combination_launch.R", np, fixed = TRUE)
if (length(i_take) >= 1L && length(i_src) >= 1L) ok("C1 러너가 rf_reimplement_queue.R 을 source 하고 rf_reimplement_queue_take 를 부른다") else ng("C1 호출 부재", sprintf("take=%d src=%d", length(i_take), length(i_src)))
if (length(i_take) && length(i_gate) && length(i_pick) && length(i_combo) && min(i_gate) < min(i_take) && min(i_take) < min(i_pick) && min(i_take) < min(i_combo))
  ok("C2 호출 위치: §1.7 pending 관문 뒤 · 새 논문 pick 앞 · 결합 착수 앞") else ng("C2 호출 순서", sprintf("gate=%s take=%s pick=%s combo=%s", min(i_gate), min(i_take), min(i_pick), min(i_combo)))
sel <- paste(sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/rf_next_paper_pick.py"), warn = FALSE, encoding = "UTF-8")), collapse = "\n")
if (!grepl("reimplement_queue", sel, fixed = TRUE)) ok("C3 selector 의 소비 술어는 대기열을 모른다(override 는 러너 한 곳)") else ng("C3 selector 가 대기열을 읽는다 — 술어 정본 오염")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_reimplement_queue","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
