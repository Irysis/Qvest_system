#!/usr/bin/env Rscript
#==============================================================================
# rf_organic_cmd.R — 유기체 **사람 명령** 경로 (O0a · 2026-09-25 · 설계 organic_design_final §5 "사람 명령 경로" · §3 G5 · G6)
#
# ★왜: 킬 해제·롤백·휴면 해제·소진 entry 되살리기를 JSON 손편집으로 하면 스키마·전후 md5·write-ahead 를 우회한다. 도훈용 명령은
#   이 파일 한 곳에서만 실행하고, 전부 시행 로그(선행) → 단일 writer(rfo_write) 또는 원장 writer(rf_reopen_entry)를 거친다.
# 사용(QM_ROOT 또는 --root=<저장소>):
#   Rscript 02_Infrastructure/ops/rf_organic_cmd.R status
#   Rscript 02_Infrastructure/ops/rf_organic_cmd.R kill-release <도훈 결정 id>
#   Rscript 02_Infrastructure/ops/rf_organic_cmd.R rollback <유기체 결정 id> <사유>
#   Rscript 02_Infrastructure/ops/rf_organic_cmd.R dormant-release <catalog_id> <사유>
#   Rscript 02_Infrastructure/ops/rf_organic_cmd.R reopen-entry <base_id> <결정 id> <사유>
# 봉쇄: QVEST_ORGANIC_CTX=1 · QVEST_UNATTENDED_LANE=1 문맥에서는 실행을 거부한다(기계·무인 레인이 사람 명령을 대신하지 못한다).
#   킬 해제는 도훈 결정 id(dr_evidence_ok — owner·decided_by dohoon · resolved · evidence 또는 레거시 note)가 **킬 시각 뒤**에 결정됐을 때만.
#   킬 해제 토큰은 state.kill_release_seen 에 적는다 — config(reinforce_auto_config.json)는 사람 소유라 이 명령도 쓰지 않는다.
# 종료 코드: 0 성공 · 1 거부/실패 · 2 사용법.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.args <- commandArgs(trailingOnly = TRUE)
.ra <- grep("^--root=", .args, value = TRUE); .args <- setdiff(.args, .ra)
ROOT <- if (length(.ra)) sub("^--root=", "", .ra[1]) else Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- normalizePath(ROOT, winslash = "/", mustWork = TRUE)
die <- function(msg, rc = 1L) { cat(sprintf("[rf_organic_cmd] 거부 — %s\n", msg)); quit(status = rc) }
for (.v in c("QVEST_ORGANIC_CTX", "QVEST_UNATTENDED_LANE"))
  if (identical(Sys.getenv(.v, ""), "1")) die(sprintf("기계·무인 문맥(%s=1)에서는 사람 명령을 실행하지 않는다", .v))
if (!length(.args)) die("사용법: status | kill-release <결정id> | rollback <결정id> <사유> | dormant-release <catalog_id> <사유> | reopen-entry <base_id> <결정id> <사유>", 2L)
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))))
source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_organic_write.R"))
cmd <- .args[1]; a <- .args[-1]
HUMAN_POLICY <- list(policy_id = "human_cmd", policy_sha = "rf_organic_cmd.R", mode = "human")
.trial <- function(kind, layer, scope) {
  did <- .rf_uid("H-ORG-", payload = c(kind, cmd, a))   # 사람 명령 결정 id(H-ORG-) — 기계 네임스페이스(M-ORG-)와 가른다 · 시행 로그·actions 조인 키
  rf_trial_log_append(kind, "program", decision_id = did, policy = HUMAN_POLICY, organic = list(layer = layer),
                      src = "ops/rf_organic_cmd.R", scope = c(list(command = cmd), scope), root = ROOT)
  did
}
.register_ptr <- function(kind, summary, did) tryCatch({
  dr_record_machine(kind, summary, sprintf("06_Registry/organic/actions.jsonl#%s", did),
                    sprintf("Rscript 02_Infrastructure/ops/rf_organic_cmd.R status  (되돌림 이력: %s)", did), root = ROOT)
  TRUE }, error = function(e) { cat(sprintf("[rf_organic_cmd] 레지스터 포인터 행 실패(비치명 · jsonl 이 정본): %s\n", conditionMessage(e))); FALSE })

if (identical(cmd, "status")) {
  st <- rfo_state_load(ROOT)
  cat(sprintf("organic state: %s\n", rfo_state_path(ROOT)))
  cat(sprintf("  killed: %s\n", if (is.list(st$killed)) sprintf("%s (%s · %s)", isTRUE(st$killed$flag), st$killed$code %||% "", st$killed$at %||% "") else "없음"))
  cat(sprintf("  kill_release_seen: %s\n", if (is.list(st$kill_release_seen)) st$kill_release_seen$decision_id %||% "" else "없음"))
  cat(sprintf("  arms 관리: %d · plan entry: %d · policies: %d\n", length(st$arms %||% list()), length(st$plan %||% list()), length(st$policies %||% list())))
  quit(status = 0L)
}
if (identical(cmd, "kill-release")) {
  if (length(a) < 1L) die("kill-release <도훈 결정 id>", 2L)
  ev <- dr_evidence_ok(a[1], ROOT)
  if (!isTRUE(ev$ok)) die(sprintf("결정 %s 는 도훈 결정 증거 규칙 불충족(%s)", a[1], ev$why))
  st <- rfo_state_load(ROOT)
  if (!is.list(st$killed) || !isTRUE(st$killed$flag)) die("킬 상태가 아니다 — 해제할 것이 없다")
  it <- Filter(function(x) identical(x$id, a[1]), dr_load(ROOT)$items)[[1]]
  tz <- function(s) as.POSIXct(as.character(s %||% ""), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  if (!isTRUE(tz(it$decided_at) > tz(st$killed$at))) die(sprintf("결정 %s(%s) 가 킬 시각(%s) 뒤가 아니다 — 킬 전에 내린 결정으로 해제하지 않는다", a[1], it$decided_at %||% "?", st$killed$at %||% "?"))
  did <- .trial("organic_kill", "all", list(action = "release", release_decision = a[1]))
  rfo_write("06_Registry/organic/state.json", list(decision_id = a[1], at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), by = "human:rf_organic_cmd"),
            did, pointer = "kill_release_seen", root = ROOT, layer = "all", policy = HUMAN_POLICY, actor = "human", note = "kill-release")
  .register_ptr("organic_kill", sprintf("킬 해제 토큰 — 도훈 결정 %s", a[1]), did)
  cat(sprintf("[rf_organic_cmd] 킬 해제 토큰 기록 — 결정 %s · 시행 %s (다음 tick 이 확인 후 해제)\n", a[1], did)); quit(status = 0L)
}
if (identical(cmd, "rollback")) {
  if (length(a) < 2L || !nzchar(a[2])) die("rollback <유기체 결정 id> <사유>", 2L)
  did <- .trial("organic_rollback", "all", list(target_decision = a[1], reason = a[2]))
  r <- tryCatch(rfo_rollback(a[1], did, ROOT, actor = "human"), error = function(e) e)
  if (inherits(r, "error")) die(conditionMessage(r))
  .register_ptr("organic_rollback", sprintf("롤백 %s — %s (포인터 %d)", a[1], a[2], r$n_restored), did)
  cat(sprintf("[rf_organic_cmd] 롤백 %s — state 포인터 %d 복원 · 시행 %s\n  %s\n", a[1], r$n_restored, did, r$reopen_required)); quit(status = 0L)
}
if (identical(cmd, "dormant-release")) {
  if (length(a) < 2L || !nzchar(a[2])) die("dormant-release <catalog_id> <사유>", 2L)
  st <- rfo_state_load(ROOT); cur <- (st$arms %||% list())[[a[1]]]
  if (!identical(as.character((cur %||% list())$status %||% ""), "organic_dormant")) die(sprintf("%s 는 휴면 상태가 아니다(%s)", a[1], as.character((cur %||% list())$status %||% "관리 안 함")))
  did <- .trial("organic_policy_transition", "space", list(catalog_id = a[1], to = "pi0", reason = a[2]))
  rfo_write("06_Registry/organic/state.json", "pi0", did, pointer = sprintf("arms/%s/status", a[1]), root = ROOT, layer = "space",
            policy = HUMAN_POLICY, actor = "human", note = a[2])
  cat(sprintf("[rf_organic_cmd] 휴면 해제 %s → pi0 · 시행 %s\n", a[1], did)); quit(status = 0L)
}
if (identical(cmd, "reopen-entry")) {
  if (length(a) < 3L || !nzchar(a[3])) die("reopen-entry <base_id> <결정 id> <사유>", 2L)
  r <- tryCatch(rf_reopen_entry(1L, a[1], a[3], a[2], root = ROOT), error = function(e) e)
  if (inherits(r, "error")) die(conditionMessage(r))
  cat(sprintf("[rf_organic_cmd] reopen-entry %s → %s\n", a[1], r$status)); quit(status = 0L)
}
die(sprintf("알 수 없는 명령: %s", cmd), 2L)
