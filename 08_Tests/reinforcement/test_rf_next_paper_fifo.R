#!/usr/bin/env Rscript
#==============================================================================
# test_rf_next_paper_fifo.R — next_paper 종단(샌드박스 자식 Rscript): P1-08 FIFO · 개설 직전 halt · D-G 세대 하한 · 실험 제외 · 러너 claim
#   (2026-09-25 · 설계 최종판 §1.1 '유기체 밖 사람 규칙' · 감사 D2-12·D8-02 · 정본 rf_lane_rules.R · 최소 차분판 — 호출당 FIFO 머리 1건)
# 판정(양방향 · 운영 원장·설정·요청·로그 무접촉 — 합성 원장 샌드박스 · telegram_notify 미복사 · 지문 계산 끔 QVEST_RF_VINTAGE=0):
#   S1 FIFO — 원장 순서 [오래된 X, 새 Y] 에서 머리 = X(구판 LIFO 면 Y) · 호출당 1건(Y 는 아직) · 반사실(idle_only) active 는 막지 않는다
#   S2 차단 active(신규 논문 normal) — 요약은 선다(halt 위치 = 개설 직전) · 그 뒤 halt_active_exists
#   S3 lanes 설정 없음 — 반사실도 막는다(구판 거동)
#   S4 세대 하한 — 최근 승격 뒤 신규 논문 0 · 요청 대기 → 승격 안 함(부모 미이월) · halt_request_pending
#   S5 세대 하한 면제 — 요청 없음 · 큐 0 → generation_gate_waived_queue_empty · 승격 · 자식 priority=normal · 부모 이월
#   S6 세대 하한 충족 — 승격 뒤 신규 논문 1 → generation_gate_ok · 승격 · FIFO 뒤 entry 는 다음 호출 몫
#   S7 실험 entry(사전등록 arm) 소진 → 요약·승격 대상 아님
#   S8 러너 claim 이 살아 있으면(상속 아님) → halt_runner_busy · 원장 바이트 불변 · 상속이면 진행
#   S9 세대 하한 미룸 + 큐에 논문 있음(가짜 술어) → 신규 논문 요청 발행 · 미룬 부모는 이월 표식 없음(다음 호출도 FIFO 머리)
#   M  돌연변이 5종(LIFO · 전부 차단 · 세대 하한 무력화 · claim 제거 · 미룬 부모 이월) → 해당 시나리오 red
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(c, m, why = "") if (isTRUE(c)) ok(m) else ng(m, why)
.slash <- function(p) sub("/+$", "", gsub("\\\\", "/", p))   # 경로 정규화 함수 대신 구분자만 통일(저장소 규칙 — 한글 경로)
TMPB <- .slash(tempfile("rfnpfifo_")); dir.create(TMPB, recursive = TRUE)
if (startsWith(tolower(TMPB), tolower(paste0(.slash(ROOT), "/")))) stop("tempdir 가 ROOT 안이다")
CFG_LANES <- fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE)$lanes
if (is.null(CFG_LANES)) stop("운영(미러) 설정에 lanes 블록이 없다 — 배포 전 판에서 돌리지 말 것")
REGIME <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$execution$exec_price

sbx <- function(entries, lanes = TRUE, req = NULL, np_src = NULL, fakepy = FALSE) {
  S <- file.path(TMPB, paste0("s", as.integer(runif(1, 1, 1e8))))
  for (d in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "02_Infrastructure/worktask", "06_Registry", ".cache", "stage_artifacts/paper_recharge", "specs"))
    dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(file.path(ROOT, "02_Infrastructure/ops"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/ops"))
  file.copy(list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/reinforcement"))
  if (!is.null(np_src)) file.copy(np_src, file.path(S, "02_Infrastructure/ops/reinforce_auto_next_paper.R"), overwrite = TRUE)
  if (isTRUE(fakepy)) {   # 큐 술어·큐 상단 선택기 가짜(큐 3편 · 상단 1편) — 요청 발행 경로를 태우려고(운영 큐 무접촉)
    writeLines("print(3)", file.path(S, "02_Infrastructure/ops/research_pool_predicates.py"))
    writeLines("import json; print(json.dumps({'url': 'https://arxiv.org/abs/9999.00002', 'title': 'fixture', 'paper_key': '9999.00002'}))",
               file.path(S, "02_Infrastructure/ops/rf_next_paper_pick.py"))
  }
  file.copy(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(S, "02_Infrastructure/worktask"))
  file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(S, "06_Registry"))
  file.copy(file.path(ROOT, "02_Infrastructure/config.R"), file.path(S, "02_Infrastructure"))
  for (e in seq_along(entries)) for (k in seq_along(entries[[e]]$attempts)) {
    sp <- file.path(S, "specs", sprintf("%s_%d.json", entries[[e]]$base_id, k))
    write(toJSON(list(code = entries[[e]]$attempts[[k]]$cell_code, factors = list(list(kind = "db", id = "F1")), weighting = list(kind = "ew")),
                 auto_unbox = TRUE), sp)
    entries[[e]]$attempts[[k]]$essence$spec <- .slash(sp)
  }
  led <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 35L, entries = entries,
              combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()), last_updated = "")
  write(toJSON(led, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
  cfg <- list(enabled = TRUE, promote_min_grade = "B", promote_max_depth = 3L, claim_stale_hours = 6)
  if (lanes) cfg$lanes <- CFG_LANES
  write(toJSON(cfg, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(S, "06_Registry/reinforce_auto_config.json"))
  if (!is.null(req)) write(toJSON(req, auto_unbox = TRUE), file.path(S, "06_Registry/replication_request.json"))
  file.create(file.path(S, "empty.Renviron"))
  S
}
run_np <- function(S, held = FALSE) {
  keys <- c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER", "QVEST_RF_CONFIG", "QVEST_RF_CLAIM", "QVEST_RF_CLAIM_HELD", "QVEST_RF_VINTAGE",
            "QVEST_TG_DRY_RUN", "QVEST_RP_JLOG", "QVEST_PY")
  old <- Sys.getenv(keys, unset = NA)
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k])) }, add = TRUE)
  Sys.setenv(QM_ROOT = S, CLAUDE_PROJECT_DIR = S, R_ENVIRON_USER = file.path(S, "empty.Renviron"),
             QVEST_RF_CONFIG = file.path(S, "06_Registry/reinforce_auto_config.json"), QVEST_RF_CLAIM = file.path(S, ".cache/reinforce_auto.claim"),
             QVEST_RF_VINTAGE = "0", QVEST_TG_DRY_RUN = "1", QVEST_RP_JLOG = file.path(S, ".cache/jlog.jsonl"))
  Sys.unsetenv("QVEST_PY")   # 기본 파이썬 — 샌드박스에 큐 술어 스크립트가 없어 n_pending = NA → halt_queue_empty(큐 단계 도달 표지)
  if (held) Sys.setenv(QVEST_RF_CLAIM_HELD = "1") else Sys.unsetenv("QVEST_RF_CLAIM_HELD")
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c("--no-environ", shQuote(file.path(S, "02_Infrastructure/ops/reinforce_auto_next_paper.R"))),
                                  stdout = TRUE, stderr = TRUE))
  paste(out, collapse = "\n")
}
jl <- function(S) { p <- file.path(S, ".cache/reinforce_auto_log.jsonl")
  if (!file.exists(p)) return(list()); lapply(readLines(p, warn = FALSE, encoding = "UTF-8"), function(l) tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) list())) }
ev <- function(S, e) Filter(function(z) identical(z$event, e), jl(S))
led <- function(S) fromJSON(file.path(S, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
ent <- function(S, id) Filter(function(e) identical(e$base_id, id), led(S)$entries)[[1]]
## ── 픽스처 ──
cell <- function(code, pt, grade) list(n = 1L, cell_code = code, grade = grade, measurement_regime = list(exec_price = REGIME, basis = "fixture"),
                                       essence = list(cell_code = code, port_t = pt, calmar = 0.3, window_deviation_months = 0L))
E <- function(id, status, opened, exhausted = NULL, grade = "C", pt = 1, parent = NULL, parent_best = NULL, priority = NULL, experiment = NULL,
              handed = NULL) {
  e <- list(base_id = id, base_grade = "C", paper_key = paste0("pk_", id), paper_id = "", base_artifacts = "", engine_path = "",
            status = status, target_grade = "A", attempts_used = 1L, attempts = list(cell("B1_1", pt, grade)), opened_at = opened)
  if (!is.null(exhausted)) e$exhausted_at <- exhausted
  if (!is.null(parent)) e$parent <- list(base_id = parent, depth = 1L, cell = "B1_1", best_port_t = parent_best, best_calmar = 0.2)
  if (!is.null(priority)) e$priority <- priority
  if (!is.null(experiment)) e$experiment <- experiment
  if (!is.null(handed)) e$handed_off <- handed
  e }
CHAIN <- list(E("P0", "exhausted", "2026-09-10T00:00:00+0900", "2026-09-11T00:00:00+0900", handed = TRUE),
              E("P0_promo1", "exhausted", "2026-09-20T00:00:00+0900", "2026-09-22T00:00:00+0900", grade = "B", pt = 3, parent = "P0", parent_best = 2))
REQ_PENDING <- list(requested_at = "2026-09-24T00:00:00+0900", source = "fixture", status = "pending",
                    paper = list(paper_key = "9999.00001", url = "https://arxiv.org/abs/9999.00001", title = "fixture"))
summ_order <- function(S) vapply(ev(S, "exhausted_summary"), function(z) as.character(z$base_id), character(1))

scen <- list()
scen$S1 <- function(np = NULL) {
  S <- sbx(list(E("X_old", "exhausted", "2026-09-20T00:00:00+0900", "2026-09-21T16:28:05+0900"),
                E("Y_new", "exhausted", "2026-09-21T00:00:00+0900", "2026-09-22T02:47:20+0900"),
                E("CF", "active", "2026-09-21T12:36:58+0900", priority = "idle_only")), np_src = np)
  o <- run_np(S)
  list(order = identical(summ_order(S), "X_old") && nzchar(ent(S, "X_old")$summarized_at %||% ""),
       one = !nzchar(ent(S, "Y_new")$summarized_at %||% ""),
       nohalt = !length(ev(S, "halt_active_exists")) && grepl("halt_queue_empty", o, fixed = TRUE), out = o)
}
scen$S2 <- function(np = NULL) {
  S <- sbx(list(E("X_old", "exhausted", "2026-09-20T00:00:00+0900", "2026-09-21T16:28:05+0900"), E("NEWP", "active", "2026-09-22T00:00:00+0900")), np_src = np)
  o <- run_np(S)
  list(summ = identical(summ_order(S), "X_old") && nzchar(ent(S, "X_old")$summarized_at %||% ""), halt = length(ev(S, "halt_active_exists")) == 1L, out = o)
}
scen$S3 <- function(np = NULL) {
  S <- sbx(list(E("X_old", "exhausted", "2026-09-20T00:00:00+0900", "2026-09-21T16:28:05+0900"), E("CF", "active", "2026-09-21T12:00:00+0900", priority = "idle_only")),
           lanes = FALSE, np_src = np)
  o <- run_np(S)
  list(halt = length(ev(S, "halt_active_exists")) == 1L && length(ev(S, "lane_cfg_unavailable")) == 1L, out = o)
}
scen$S4 <- function(np = NULL) {
  S <- sbx(CHAIN, req = REQ_PENDING, np_src = np)
  o <- run_np(S)
  sk <- ev(S, "promote_skipped")
  list(deferred = !length(ev(S, "promoted")) && grepl("halt_request_pending", o, fixed = TRUE) && !isTRUE(ent(S, "P0_promo1")$handed_off) &&
         length(led(S)$entries) == 2L && length(sk) == 1L && identical(sk[[1]]$reason, "generation_gate_new_paper_first"), out = o)
}
scen$S5 <- function(np = NULL) {
  S <- sbx(CHAIN, np_src = np)
  o <- run_np(S)
  pr <- ev(S, "promoted"); ch <- Filter(function(e) identical(e$base_id, "P0_promo2"), led(S)$entries)
  list(waived = length(pr) == 1L && length(ev(S, "generation_gate_waived_queue_empty")) == 1L,
       child = length(ch) == 1L && identical(ch[[1]]$priority, "normal") && identical(ch[[1]]$parent$base_id, "P0_promo1") && isTRUE(ent(S, "P0_promo1")$handed_off),
       out = o)
}
scen$S6 <- function(np = NULL) {
  S <- sbx(c(CHAIN, list(E("NEWP", "exhausted", "2026-09-23T00:00:00+0900", "2026-09-24T00:00:00+0900"))), req = REQ_PENDING, np_src = np)
  o <- run_np(S)
  list(sat = length(ev(S, "promoted")) == 1L && length(ev(S, "generation_gate_ok")) == 1L && identical(summ_order(S), "P0_promo1") &&
         !isTRUE(ent(S, "NEWP")$handed_off), out = o)
}
scen$S7 <- function(np = NULL) {
  S <- sbx(list(E("ARM1", "exhausted", "2026-09-20T00:00:00+0900", "2026-09-21T00:00:00+0900", grade = "B", pt = 3, priority = "prereg",
                  experiment = list(prereg_id = "PR-T", family_id = "F", arm_id = "T1"))), np_src = np)
  o <- run_np(S)
  list(skip = !length(ev(S, "exhausted_summary")) && !length(ev(S, "promoted")) && !nzchar(ent(S, "ARM1")$summarized_at %||% ""), out = o)
}
scen$S8 <- function(np = NULL) {
  S <- sbx(list(E("X_old", "exhausted", "2026-09-20T00:00:00+0900", "2026-09-21T16:28:05+0900")), np_src = np)
  CL <- new.env(); sys.source(file.path(ROOT, "02_Infrastructure/ops/rf_claim.R"), envir = CL)
  cp <- file.path(S, ".cache/reinforce_auto.claim"); a <- CL$rf_claim_acquire(cp, stale_hours = 6)
  b0 <- tools::md5sum(file.path(S, "06_Registry/reinforce_ledger_l1.json"))
  o <- run_np(S)
  b1 <- tools::md5sum(file.path(S, "06_Registry/reinforce_ledger_l1.json"))
  busy <- isTRUE(a$ok) && length(ev(S, "halt_runner_busy")) == 1L && identical(unname(b0), unname(b1)) && !length(ev(S, "exhausted_summary"))
  o2 <- run_np(S, held = TRUE)   # 상속(러너가 부른 경우) = claim 을 다시 잡지 않고 진행
  CL$rf_claim_release(cp)
  list(busy = busy, held = length(ev(S, "exhausted_summary")) == 1L, out = paste(o, o2))
}
scen$S9 <- function(np = NULL) {
  S <- sbx(CHAIN, np_src = np, fakepy = TRUE)
  o <- run_np(S)
  rq <- tryCatch(fromJSON(file.path(S, "06_Registry/replication_request.json"), simplifyVector = FALSE), error = function(e) NULL)
  list(defer_req = length(ev(S, "promote_deferred_new_paper_first")) == 1L && !length(ev(S, "promoted")) &&
         identical(rq$status, "pending") && identical(rq$paper$paper_key, "9999.00002") && !isTRUE(ent(S, "P0_promo1")$handed_off) &&
         !length(ev(S, "handed_off")), out = o)
}

cat("=== 시나리오 ===\n")
R <- lapply(names(scen), function(k) tryCatch(scen[[k]](), error = function(e) list(.err = conditionMessage(e))))
names(R) <- names(scen)
tail_of <- function(r) { o <- r$out %||% r$.err %||% ""; substr(o, max(1L, nchar(o) - 400L), nchar(o)) }
chk(isTRUE(R$S1$order), "S1a FIFO 머리 = 가장 먼저 소진된 X_old(원장 마지막 Y_new 가 아니다 — 구판 LIFO)", tail_of(R$S1))
chk(isTRUE(R$S1$one), "S1b 호출당 1건 — Y_new 는 머리가 이월된 뒤 다음 호출 몫", tail_of(R$S1))
chk(isTRUE(R$S1$nohalt), "S1c 반사실(idle_only) active 는 개설을 막지 않는다 → 큐 단계 도달(halt_queue_empty)", tail_of(R$S1))
chk(isTRUE(R$S2$summ), "S2a 차단 active 가 있어도 요약은 선다(halt 위치 = 개설 직전)", tail_of(R$S2))
chk(isTRUE(R$S2$halt), "S2b 그 뒤 halt_active_exists", tail_of(R$S2))
chk(isTRUE(R$S3$halt), "S3 lanes 설정 없음 → 반사실도 막는다(구판 거동 · lane_cfg_unavailable 로그)", tail_of(R$S3))
chk(isTRUE(R$S4$deferred), "S4 세대 하한 미달 + 요청 대기 → 승격 안 함(promote_skipped generation_gate_new_paper_first) · 부모 미이월 · halt_request_pending", tail_of(R$S4))
chk(isTRUE(R$S5$waived), "S5a 요청 없음 ∧ 큐 0 → 세대 하한 면제 승격(generation_gate_waived_queue_empty)", tail_of(R$S5))
chk(isTRUE(R$S5$child), "S5b 승격 자식 priority=normal · parent 기록 · 부모 이월 표식", tail_of(R$S5))
chk(isTRUE(R$S6$sat), "S6 승격 뒤 신규 논문 1 → generation_gate_ok · 승격 · NEWP 는 다음 호출 몫(미이월)", tail_of(R$S6))
chk(isTRUE(R$S7$skip), "S7 사전등록 실험 entry 는 요약·승격 대상 아님", tail_of(R$S7))
chk(isTRUE(R$S8$busy), "S8a 러너 claim 이 살아 있으면 halt_runner_busy · 원장 바이트 불변", tail_of(R$S8))
chk(isTRUE(R$S8$held), "S8b 상속(QVEST_RF_CLAIM_HELD) 이면 claim 을 다시 잡지 않고 진행", tail_of(R$S8))
chk(isTRUE(R$S9$defer_req), "S9 세대 하한 미룸 + 큐 3편 → 신규 논문 요청 발행 · 미룬 부모 이월 표식 없음(다음 호출도 FIFO 머리)", tail_of(R$S9))

cat("=== 돌연변이 ===\n")
NP <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R")
mut <- function(from, to, n = 1L) { t <- paste(readLines(NP, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  if (lengths(regmatches(t, gregexpr(from, t, fixed = TRUE))) != n) return(NULL)
  p <- file.path(TMPB, paste0("np_mut_", as.integer(runif(1, 1, 1e8)), ".R")); writeLines(gsub(from, to, t, fixed = TRUE), p, useBytes = TRUE); p }
MU <- list(
  list("M1 LIFO 복귀(ex 역순)", "ex <- .F$entries", "ex <- rev(.F$entries)", function(p) isTRUE(scen$S1(p)$order)),
  list("M2 active 전부 차단(비차단 무시)", ".blk <- rf_blocking_active(led$entries, .LANE)", ".blk <- Filter(function(z) identical(z$status, \"active\"), led$entries)",
       function(p) isTRUE(scen$S1(p)$nohalt)),
  list("M3 세대 하한 무력화", ".gate <- rf_generation_gate(led$entries, .LANE, request = .req)", ".gate <- list(ok = TRUE, applied = FALSE)",
       function(p) isTRUE(scen$S4(p)$deferred)),
  list("M4 러너 claim 제거", 'if (!nzchar(Sys.getenv("QVEST_RF_CLAIM_HELD", ""))) {', "if (FALSE) {", function(p) isTRUE(scen$S8(p)$busy)),
  list("M5 미룬 부모도 이월(재구현·요청 두 경로)", "!is.null(best$base_id) && !isTRUE(.gen_deferred))", "!is.null(best$base_id))",
       function(p) isTRUE(scen$S9(p)$defer_req), 2L))
for (m in MU) {
  p <- mut(m[[2]], m[[3]], if (length(m) >= 5L) m[[5]] else 1L)
  if (is.null(p)) { ng(sprintf("%s — 앵커 불일치(정확히 1회 아님)", m[[1]])); next }
  alive <- tryCatch(m[[4]](p), error = function(e) FALSE)
  chk(!isTRUE(alive), sprintf("%s → red(돌연변이 사살)", m[[1]]), "돌연변이 생존")
}
unlink(TMPB, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_next_paper_fifo","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
