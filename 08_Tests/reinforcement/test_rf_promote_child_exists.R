#!/usr/bin/env Rscript
#==============================================================================
# test_rf_promote_child_exists.R — 승격은 한 번뿐이다 · 이월 표식은 두 경로가 같다 (2026-09-05)
#
# 실사고: promo2 → promo3 승격 때 부모(promo2)에 handed_off 가 안 남았다. promo3 가 소진·큐 이월(handed_off)
#   되자 promo2 가 "마지막 미이월 소진 entry" 로 다시 떠올라 매 tick 승격 판정 ok → rf_open_entry 가 기존
#   promo3 를 조용히 재사용 → 로그 "promoted" + 라운드 리뷰 텔레그램 중복(17:26) + 큐 논문 미착수(3분마다).
# 판정(양방향):
#   D1 자식 base_id 가 원장에 있으면 child_exists   D2 자식 없으면 ok(양성 대조)   D3 existing_ids 생략 = 구 동작
#   D4 handed_off 된 entry 는 already_handed_off
#   W1 rf_mark_handed_off 가 handed_off/handed_off_at/promoted_to 를 남긴다   W2 없는 entry 는 stop
#   E1 (샌드박스 e2e) 부모+자식(handed_off) 원장 → next_paper 가 promoted 를 찍지 않고 큐 단계로 내려간다
#   E2 (샌드박스 e2e) 부모만 있는 원장 → 승격 1회 + 부모 handed_off=TRUE·promoted_to=자식 → 재실행 시 promoted 0
# 부작용 없음: 운영 원장·설정 무접촉(샌드박스 사본 · telegram_notify 미복사 → 발송 경로 부재).
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages(library(jsonlite))
source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_promote.R"))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(label, got, want_ok, want_reason) {
  # ★구판(existing_ids 인자 부재)에서는 호출 자체가 던진다 — 중단이 아니라 FAIL 로 세어 뒤 절(e2e)까지 잰다
  got <- tryCatch(got, error = function(e) list(ok = NA, reason = paste0("error: ", conditionMessage(e))))
  if (identical(isTRUE(got$ok), want_ok) && identical(got$reason, want_reason)) ok(label)
  else ng(label, sprintf("ok=%s reason=%s (기대 ok=%s reason=%s)", got$ok, got$reason, want_ok, want_reason))
}

SPEC <- tempfile(fileext = ".json")
writeLines('{"factors":[{"kind":"value","name":"bm"}],"weighting":{"arm":"ew"},"universe":{"kind":"kq150"},"overlay":null}', SPEC)
CFG  <- list(promote_min_grade = "B", promote_max_depth = 3)
P2   <- list(base_id = "RP_T_promo2", parent = list(base_id = "RP_T_promo1", depth = 2L, best_port_t = 1.0))
bestB <- list(grade = "B", port_t = 2.0, spec = SPEC, cell_code = "B1_3")

cat("=== 판정 함수 ===\n")
chk("D1 자식(promo3)이 원장에 있으면 child_exists", rf_promote_decide(P2, bestB, CFG, existing_ids = c("RP_T_promo2", "RP_T_promo3")), FALSE, "child_exists")
chk("D2 자식 없으면 승격(양성 대조)",           rf_promote_decide(P2, bestB, CFG, existing_ids = c("RP_T_promo1", "RP_T_promo2")), TRUE,  "ok")
chk("D3 existing_ids 생략 = 구 동작(ok)",        rf_promote_decide(P2, bestB, CFG), TRUE, "ok")
chk("D4 handed_off 된 entry 는 already_handed_off", rf_promote_decide(c(P2, list(handed_off = TRUE)), bestB, CFG, existing_ids = "RP_T_promo2"), FALSE, "already_handed_off")

cat("=== writer ===\n")
mk_ledger <- function(entries) list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L,
  entries = entries, combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()), last_updated = "")
att <- list(n = 3L, cell_code = "B1_3", grade = "B",
            essence = list(port_t = 2.0, cell_code = "B1_3", spec = SPEC), artifacts = "")
E_parent <- list(base_id = "RP_T_promo2", status = "exhausted", base_grade = "C", max_attempts = 25L,
                 paper_key = "t", paper_id = "t", engine_path = "", base_artifacts = "",
                 parent = list(base_id = "RP_T_promo1", depth = 2L, best_port_t = 1.0),
                 summarized_at = "2026-09-05T00:00:00+0900", attempts = list(att))
E_child  <- list(base_id = "RP_T_promo3", status = "exhausted", base_grade = "B", max_attempts = 25L,
                 parent = list(base_id = "RP_T_promo2", depth = 3L, best_port_t = 2.0),
                 handed_off = TRUE, summarized_at = "2026-09-05T01:00:00+0900", attempts = list())
W <- file.path(tempdir(), paste0("rf_ho_", Sys.getpid())); dir.create(file.path(W, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(mk_ledger(list(E_parent)), auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(W, "06_Registry/reinforce_ledger_l1.json"))
w_err <- tryCatch({ rf_mark_handed_off(1L, "RP_T_promo2", W, promoted_to = "RP_T_promo3", reason = "unit"); "" }, error = function(e) conditionMessage(e))
if (nzchar(w_err)) ng("W0 rf_mark_handed_off 호출 실패(구판 writer 부재?)", w_err)
e <- rf_load(1L, W)$entries[[1]]
if (isTRUE(e$handed_off) && nzchar(e$handed_off_at %||% "") && identical(e$promoted_to, "RP_T_promo3") && identical(e$handed_off_reason, "unit")) ok("W1 handed_off/at/promoted_to/reason 기록") else ng("W1 표식 누락", toJSON(e[c("handed_off","promoted_to")], auto_unbox = TRUE))
r <- tryCatch({ rf_mark_handed_off(1L, "RP_NOPE", W); "no_error" }, error = function(e) "error")
if (identical(r, "error")) ok("W2 없는 entry 는 stop") else ng("W2 없는 entry 가 조용히 통과")

cat("=== 샌드박스 e2e ===\n")
sbx <- function(entries) {
  S <- file.path(tempdir(), paste0("rf_sbx_", Sys.getpid(), "_", as.integer(runif(1, 1, 1e6))))
  for (d in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "06_Registry", ".cache", "stage_artifacts/paper_recharge"))
    dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(file.path(ROOT, "02_Infrastructure/ops"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/ops"))
  file.copy(list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/reinforcement"))
  file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(S, "06_Registry"))
  file.copy(file.path(ROOT, "02_Infrastructure/config.R"), file.path(S, "02_Infrastructure"))
  writeLines(toJSON(mk_ledger(entries), auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
  writeLines('{"enabled": true, "promote_min_grade": "B", "promote_max_depth": 3}', file.path(S, "06_Registry/reinforce_auto_config.json"))
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
n_promoted <- function(o) length(grep("^[[]rf_next[]] promoted$", strsplit(o, "\n")[[1]]))
# E1 — 부모+자식(handed_off): 재승격 금지, 큐 단계 도달
S1 <- sbx(list(E_parent, E_child)); o1 <- run_np(S1)
if (n_promoted(o1) == 0L) ok("E1 자식이 있으면 promoted 0회 ★실사고") else ng("E1 재승격 반복", sprintf("promoted %d회", n_promoted(o1)))
if (grepl("halt_queue_empty|halt_pick_failed|paper_picked", o1)) ok("E1 큐 단계로 내려감") else ng("E1 큐 단계 미도달", substr(o1, max(1L, nchar(o1) - 400L), nchar(o1)))
L1 <- rf_load(1L, S1)
if (length(L1$entries) == 2L) ok("E1 원장 entry 수 불변(2)") else ng("E1 entry 수 변동", as.character(length(L1$entries)))
# E2 — 부모만: 승격 1회 · 부모 표식 · 재실행 0회
S2 <- sbx(list(E_parent)); o2 <- run_np(S2)
if (n_promoted(o2) == 1L) ok("E2 자식 없으면 승격 1회(양성 대조)") else ng("E2 승격 미발화", sprintf("promoted %d회 / %s", n_promoted(o2), substr(o2, 1, 600)))
L2 <- rf_load(1L, S2)
ids2 <- vapply(L2$entries, function(z) z$base_id, character(1))
if ("RP_T_promo3" %in% ids2) ok("E2 자식 entry 개설") else ng("E2 자식 부재", paste(ids2, collapse = ","))
p2 <- L2$entries[[which(ids2 == "RP_T_promo2")[1]]]
if (isTRUE(p2$handed_off) && identical(p2$promoted_to, "RP_T_promo3")) ok("E2 부모 handed_off=TRUE · promoted_to=자식 ★실사고 뿌리") else ng("E2 부모 표식 누락", toJSON(p2[c("handed_off","promoted_to")], auto_unbox = TRUE, null = "null"))
# 자식을 소진·이월 상태로 만들고 재실행 — 실사고 재현 조건
k3 <- which(ids2 == "RP_T_promo3")[1]
if (!is.na(k3)) {
  L2$entries[[k3]]$status <- "exhausted"; L2$entries[[k3]]$handed_off <- TRUE
  L2$entries[[k3]]$summarized_at <- "2026-09-05T02:00:00+0900"
  writeLines(toJSON(L2, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(S2, "06_Registry/reinforce_ledger_l1.json"))
  o3 <- run_np(S2)
  if (n_promoted(o3) == 0L) ok("E2 재실행(자식 소진·이월) promoted 0회 — 실사고 재현 조건에서 침묵") else ng("E2 재실행에서 재승격", sprintf("promoted %d회", n_promoted(o3)))
} else ng("E2 재실행 생략 — 자식 부재")
unlink(c(S1, S2, W), recursive = TRUE)

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_promote_child_exists","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
