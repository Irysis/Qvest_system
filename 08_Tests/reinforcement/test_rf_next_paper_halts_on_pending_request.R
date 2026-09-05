#!/usr/bin/env Rscript
#==============================================================================
# test_rf_next_paper_halts_on_pending_request.R — 대기 중인 충실구현 요청은 한 번만 서 있는다 (2026-09-05)
#
# 실사고: 러너가 active 0 마다 next_paper 를 부르게 되자(no-active 위임) 요청이 pending 인 채로 tick 마다
#   paper_picked → replication_requested 가 다시 찍히고 요청 파일이 덮였다(17:46 → 17:54 requested_at 갱신).
#   텔레그램은 30분 dedup 이 막았을 뿐이고, in_progress 를 pending 으로 덮으면 같은 논문이 두 번 뜬다.
# 판정(양방향, 샌드박스 e2e):
#   P1 status=pending     → halt_request_pending · paper_picked/replication_requested 0 · 요청 파일 바이트 불변
#   P2 status=in_progress → 동일
#   N1 status=done_no_reinforce → 관문 통과(halt_request_pending 없음) → 큐 단계 도달(halt_queue_empty 등)
#   N2 요청 파일 부재 → 관문 통과
# 부작용 없음: 운영 원장·설정·요청 파일 무접촉(샌드박스 사본 · telegram_notify 미복사).
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages(library(jsonlite))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }

LEDGER <- '{"schema_version":"reinforce_ledger_v2","layer":1,"max_attempts":25,"entries":[],"combination_review":{"papers_since_last_review":0,"last_review_date":"","history":[]},"last_updated":""}'
sbx <- function(req_status = NULL) {
  S <- file.path(tempdir(), paste0("rf_req_", Sys.getpid(), "_", as.integer(runif(1, 1, 1e6))))
  for (d in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "06_Registry", ".cache", "stage_artifacts/paper_recharge"))
    dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(file.path(ROOT, "02_Infrastructure/ops"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/ops"))
  file.copy(list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/reinforcement"))
  file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(S, "06_Registry"))
  file.copy(file.path(ROOT, "02_Infrastructure/config.R"), file.path(S, "02_Infrastructure"))
  writeLines(LEDGER, file.path(S, "06_Registry/reinforce_ledger_l1.json"))
  writeLines('{"enabled": true}', file.path(S, "06_Registry/reinforce_auto_config.json"))
  if (!is.null(req_status))
    writeLines(sprintf('{"requested_at":"2026-09-05T17:46:05+0900","source":"fixture","status":"%s","paper":{"paper_key":"2404.08129","url":"https://arxiv.org/abs/2404.08129","title":"fixture"}}', req_status),
               file.path(S, "06_Registry/replication_request.json"))
  file.create(file.path(S, "empty.Renviron"))
  S
}
run_np <- function(S) {
  old <- Sys.getenv(c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER", "QVEST_RF_CONFIG"), unset = NA)
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k])) }, add = TRUE)
  Sys.setenv(QM_ROOT = S, CLAUDE_PROJECT_DIR = S, R_ENVIRON_USER = file.path(S, "empty.Renviron"),
             QVEST_RF_CONFIG = file.path(S, "06_Registry/reinforce_auto_config.json"))
  out <- suppressWarnings(system2("Rscript", shQuote(file.path(S, "02_Infrastructure/ops/reinforce_auto_next_paper.R")), stdout = TRUE, stderr = TRUE))
  paste(out, collapse = "\n")
}
req_bytes <- function(S) { p <- file.path(S, "06_Registry/replication_request.json"); if (file.exists(p)) readBin(p, "raw", file.info(p)$size) else raw(0) }
reached_queue <- function(o) grepl("halt_queue_empty|halt_pick_failed|paper_picked", o)

for (st in c("pending", "in_progress")) {
  S <- sbx(st); b0 <- req_bytes(S); o <- run_np(S); b1 <- req_bytes(S)
  tag <- if (st == "pending") "P1" else "P2"
  if (grepl("halt_request_pending", o, fixed = TRUE)) ok(sprintf("%s status=%s → halt_request_pending", tag, st)) else ng(sprintf("%s status=%s 관문 미발화 ★실사고", tag, st), substr(o, max(1L, nchar(o) - 300L), nchar(o)))
  if (!grepl("paper_picked|replication_requested", o)) ok(sprintf("%s 재발행 0", tag)) else ng(sprintf("%s 재발행됨", tag))
  if (identical(b0, b1)) ok(sprintf("%s 요청 파일 바이트 불변", tag)) else ng(sprintf("%s 요청 파일이 덮였다", tag))
  unlink(S, recursive = TRUE)
}
S <- sbx("done_no_reinforce"); o <- run_np(S)
if (!grepl("halt_request_pending", o, fixed = TRUE) && reached_queue(o)) ok("N1 종결 상태(done_no_reinforce)는 관문 통과 → 큐 단계") else ng("N1 종결 상태에서 막힘/미도달", substr(o, max(1L, nchar(o) - 300L), nchar(o)))
unlink(S, recursive = TRUE)
S <- sbx(NULL); o <- run_np(S)
if (!grepl("halt_request_pending", o, fixed = TRUE) && reached_queue(o)) ok("N2 요청 파일 부재는 관문 통과 → 큐 단계") else ng("N2 파일 부재에서 막힘/미도달", substr(o, max(1L, nchar(o) - 300L), nchar(o)))
unlink(S, recursive = TRUE)

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_next_paper_halts_on_pending_request","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
