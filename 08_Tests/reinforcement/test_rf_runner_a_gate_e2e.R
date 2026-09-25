#!/usr/bin/env Rscript
#==============================================================================
# test_rf_runner_a_gate_e2e.R — A 자격 관문(P0-12) · 규약 혼합 가드를 **실물 러너·이월 스크립트**로 끝까지 (샌드박스 e2e · 2026-09-24)
#
# 러너(reinforce_auto_parallel.R)와 이월(reinforce_auto_next_paper.R)을 샌드박스 root 에서 실제 Rscript 로 돌린다.
#   워커·텔레그램·팡파레·라운드 리뷰만 스텁(워커는 계획표대로 등급·규약·시작일을 낸 합성 산출물을 쓴다 — 충실구현 러너처럼
#   A 면 산출물에 judge_request.json 도 쓴다). 나머지(원장 writer · 관문 · 큐 · 결정 기록 · 배리어 · claim)는 설치본 그대로.
#   R1  legacy 규약 A → 보류(held:legacy_regime) · mailbox 요청 0 · 산출물 요청 치움 · entry active · 결정 기록 hold
#   R2  다음 tick 이 **같은 entry 의 다음 칸을 소비**한다(보류 A 가 탐색을 멈추지 않는다) · 보류 사유 불변이면 결정 기록 추가 0
#   R3  rebase 표식(원장 measurement_regime.regime = 현행)을 얹으면 tick 시작 재평가가 발행 + 졸업 · 그 tick 은 칸을 더 소비하지 않는다
#   R4  [양성] 현행 규약 A → 수집 즉시 발행(후보별 mailbox 파일 · awaiting_judge · graduated · 산출물 요청 유지)
#   M1  [돌연변이] 관문 우회 enqueue(수집 경로를 발행 직행으로) → legacy A 가 mailbox 에 선다 = R1 이 red
#   M2  [돌연변이] graduate 인자 제거(항상 TRUE) → 보류 A 가 entry 를 닫아 R2 소비가 멈춘다 = R2 가 red
#   N1  이월: 소진 entry 의 칸이 전부 legacy → promote_deferred_regime · 승격 0 · 이월 표식 0(사슬 보존)
#   N2  같은 entry 에 rebase 표식 → 승격 1 · 부모 handed_off
#   N3  부모 기준선 칸이 legacy(비교 불가) → promote_parent_baseline_unavailable · 개선 판정 생략(승격 진행)
# 부작용 없음: 운영 원장·로그·큐·mailbox 무접촉(샌드박스 root 에서만 쓴다 · 전후 md5 대조). 자식 Rscript 는 R_ENVIRON_USER=빈 파일.
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_runner_a_gate_e2e.R   (약 4분 — 러너 대기 루프 20초/tick)
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
cat(sprintf("ROOT = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
TMP <- normalizePath(tempdir(), winslash = "/")
EMPTY_RENV <- file.path(TMP, "empty.Renviron"); writeLines(character(0), EMPTY_RENV)
# 운영 파일 지문(전후 대조) — 이 검사는 운영 쪽 어떤 것도 쓰지 않아야 한다
PROD <- file.path(ROOT, c("06_Registry/reinforce_ledger_l1.json", "06_Registry/grade_a_queue.json", "06_Registry/rf_decisions.jsonl",
                          ".cache/reinforce_auto_log.jsonl"))
md5_prod <- function() vapply(PROD, function(p) if (file.exists(p)) unname(tools::md5sum(p)) else "absent", character(1))
PROD0 <- md5_prod()
MB0 <- sort(list.files(file.path(ROOT, "qepm/mailbox"), pattern = "^judge_request"))

CUR <- local({ j <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)
               as.character(j$execution$exec_price) })
LEG <- setdiff(c("close_d_legacy", "close_t1", "open_t1"), CUR)[1]
cat(sprintf("현행 규약 = %s · legacy 주입 = %s\n", CUR, LEG))

# ── 샌드박스 ──────────────────────────────────────────────────────────────────
mk_sbx <- function(tag) {
  S <- file.path(TMP, sprintf("rfage_%s_%d", tag, Sys.getpid())); unlink(S, recursive = TRUE, force = TRUE)
  for (d in c("02_Infrastructure/reinforcement/overlay_arms", "02_Infrastructure/ops", "02_Infrastructure/contracts",
              "02_Infrastructure/worktask", "06_Registry", ".cache/rf_parallel", "stage_artifacts/replication",
              "stage_artifacts/l_code/reinforcement", "stage_artifacts/paper_recharge", "qepm/mailbox"))
    dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
  cp <- function(from, to) invisible(file.copy(from, file.path(S, to), overwrite = TRUE))
  cp(list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "[.]R$", full.names = TRUE), "02_Infrastructure/reinforcement")
  cp(list.files(file.path(ROOT, "02_Infrastructure/reinforcement/overlay_arms"), full.names = TRUE), "02_Infrastructure/reinforcement/overlay_arms")
  cp(list.files(file.path(ROOT, "02_Infrastructure/ops"), pattern = "[.](R|sh)$", full.names = TRUE), "02_Infrastructure/ops")
  cp(list.files(file.path(ROOT, "02_Infrastructure/contracts"), pattern = "[.]R$", full.names = TRUE), "02_Infrastructure/contracts")
  cp(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), "02_Infrastructure/worktask")
  cp(file.path(ROOT, "02_Infrastructure/config.R"), "02_Infrastructure")
  for (f in c("reinforce_program.json", "overlay_catalog.json", "weight_catalog.json", "rf_arm_compat.json", "a_eligibility_gate.json"))
    if (file.exists(file.path(ROOT, "06_Registry", f))) cp(file.path(ROOT, "06_Registry", f), "06_Registry")
  # 스텁 — 텔레그램·팡파레·라운드 리뷰는 호출 기록만(발송 0)
  writeLines(c('rf_auto_notify <- function(...) { cat("notify\\n", file = file.path(Sys.getenv("QM_ROOT"), "stub_notify.log"), append = TRUE); TRUE }',
               '.rf_target_label <- function(e) as.character(e$base_id %||% "")', '.rf_target_items <- function(e, ...) as.character(e$base_id %||% "")'),
             file.path(S, "02_Infrastructure/ops/rf_auto_notify.R"))
  writeLines('rf_grade_fanfare <- function(...) TRUE', file.path(S, "02_Infrastructure/ops/rf_grade_fanfare.R"))
  writeLines('rf_round_review <- function(...) TRUE', file.path(S, "02_Infrastructure/ops/rf_round_review.R"))
  writeLines(c("#!/usr/bin/env bash", "exit 0"), file.path(S, "02_Infrastructure/ops/rf_lcode_mechanism.sh"))
  # 스텁 워커 — 계획표(stub_plan.json)대로 합성 산출물을 쓴다(충실구현 러너처럼 A 면 산출물 judge_request.json 도)
  writeLines(c(
    'suppressMessages(library(jsonlite)); `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a',
    'a <- commandArgs(trailingOnly = TRUE); S <- Sys.getenv("QM_ROOT")',
    'sp <- fromJSON(a[1], simplifyVector = FALSE); n <- as.integer(a[2]); code <- sp$code',
    'plan <- tryCatch(fromJSON(file.path(S, "stub_plan.json"), simplifyVector = FALSE), error = function(e) list())',
    'p <- plan[[code]] %||% list(); grade <- p$grade %||% "B"; regime <- p$regime %||% plan$.default_regime',
    'art <- file.path(S, "stage_artifacts/replication", sprintf("%s_%d_%d", code, n, Sys.getpid())); dir.create(art, recursive = TRUE, showWarnings = FALSE)',
    'dates <- seq(as.Date(p$start %||% "2005-02-01"), as.Date("2026-08-01"), by = "month")',
    'saveRDS(list(holdings = data.frame(date = dates, ticker = "A005930", weight = 1), period_returns = data.frame(date = dates, ret_net = 0.01)), file.path(art, "bt_result.rds"))',
    'au <- list(status = "OK", essence_grade = grade, selection_type = "sweep", n_trials_cumulative = 20L, dsr = 0.9, essence = list(dsr = 0.9),',
    '           measurement_regime = list(selection_type = "sweep", n_trials_cumulative = 20L, n_trials_basis = "base1+lineage_measured(excl_inherited)+batch_size", exec_price = regime))',
    'writeLines(toJSON(au, auto_unbox = TRUE, null = "null"), file.path(art, "authoritative_remeasure.json"))',
    'if (identical(grade, "A")) writeLines(toJSON(list(strategy_id = code, layer = 1L, grade = "A", artifacts = art), auto_unbox = TRUE), file.path(art, "judge_request.json"))',
    'pt <- if (identical(grade, "A")) 3.5 else 2.0',
    'writeLines(toJSON(list(n = n, code = code, block = sp$block, ok = TRUE, grade = grade, strategy_name = a[3], artifacts = art, spec = a[1],',
    '  essence = list(cell_code = code, block = sp$block, port_t = pt, net_sharpe = 1.2, cagr = 0.2, mdd = 0.25, calmar = 0.8, oos_retention = 0.8,',
    '                 dsr = 0.9, selection_type = "sweep", n_trials_cumulative = 20L, spec = a[1], source = "stub")), auto_unbox = TRUE, null = "null"), a[4])'),
    file.path(S, "02_Infrastructure/ops/rf_cell_worker.R"))
  writeLines(toJSON(list(enabled = TRUE, parallel_cells = 1L, daily_cap = 999L, claim_stale_hours = 6, cell_max_retry = 2L,
                         worker_timeout_sec = 180L, promote_min_grade = "B", promote_max_depth = 3L,
                         lcode_mechanism = list(enabled = FALSE), b1_design = list(enabled = FALSE)), auto_unbox = TRUE),
             file.path(S, "rcfg.json"))
  S
}
mk_b1 <- function(S, bid, k, regime = CUR, pt = 1.0 + k / 10, grade = "B") {
  art <- file.path(S, "stage_artifacts/replication", sprintf("%s_B1_%d", bid, k)); dir.create(art, recursive = TRUE, showWarnings = FALSE)
  dates <- seq(as.Date("2005-02-01"), as.Date("2026-08-01"), by = "month")
  saveRDS(list(holdings = data.frame(date = dates, ticker = "A005930", weight = 1),
               period_returns = data.frame(date = dates, ret_net = 0.01)), file.path(art, "bt_result.rds"))
  writeLines(toJSON(list(status = "OK", essence_grade = grade, selection_type = "sweep", n_trials_cumulative = 6L, dsr = 0.5,
                         measurement_regime = list(selection_type = "sweep", n_trials_cumulative = 6L, exec_price = regime)),
                    auto_unbox = TRUE, null = "null"), file.path(art, "authoritative_remeasure.json"))
  sp <- file.path(S, ".cache/rf_parallel", sprintf("spec_B1_%d__%s.json", k, bid))
  writeLines(toJSON(list(code = sprintf("B1_%d", k), block = "B1", factors = list(list(kind = "db", id = "F0"), list(kind = "db", id = sprintf("F%d", k))),
                         weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"), overlay_cell = list()),
                    auto_unbox = TRUE, null = "null"), sp)
  list(n = as.integer(k), cell_code = sprintf("B1_%d", k), idea = sprintf("stub B1_%d", k), keyword_axis = "multifactor", grade = grade,
       artifacts = art, closed_at = "2026-09-24T00:00:00+0900",
       essence = list(cell_code = sprintf("B1_%d", k), block = "B1", port_t = pt, calmar = 0.3, cagr = 0.1, mdd = 0.4,
                      net_sharpe = 0.6, oos_retention = 0.5, spec = sp))
}
mk_ledger <- function(S, entries)
  writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, entries = entries,
                         combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()),
                         last_updated = ""), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6),
             file.path(S, "06_Registry/reinforce_ledger_l1.json"))
mk_entry <- function(S, bid) list(base_id = bid, status = "active", base_grade = "C", max_attempts = 25L, attempts_used = 5L,
  paper_key = "t", paper_id = "t", engine_path = "", base_artifacts = "",
  block_order = list("B1", "B2", "B3", "B6", "B5", "B7", "B4"), block_order_reason = "stub",
  attempts = lapply(1:5, function(k) mk_b1(S, bid, k)))
set_plan <- function(S, plan) writeLines(toJSON(c(plan, list(.default_regime = CUR)), auto_unbox = TRUE), file.path(S, "stub_plan.json"))
run_script <- function(S, script, timeout = 240) {
  old <- Sys.getenv(c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER", "QVEST_RF_CONFIG", "QVEST_RF_CLAIM",
                      "QM_REFRESH_LOCKDIR", "QM_RAWDATA_WRITER_LOCKDIR", "QVEST_RF_CLAIM_HELD", "QVEST_CONSTRAINT_DEFAULTS"), unset = NA)
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, as.list(old[k])) }, add = TRUE)
  Sys.unsetenv(c("QVEST_RF_CLAIM_HELD", "QVEST_CONSTRAINT_DEFAULTS"))
  Sys.setenv(QM_ROOT = S, CLAUDE_PROJECT_DIR = S, R_ENVIRON_USER = EMPTY_RENV, QVEST_RF_CONFIG = file.path(S, "rcfg.json"),
             QVEST_RF_CLAIM = file.path(S, ".cache/claim_e2e"), QM_REFRESH_LOCKDIR = file.path(S, "no_refresh.lock"),
             QM_RAWDATA_WRITER_LOCKDIR = file.path(S, "no_writer.lock"))
  out <- suppressWarnings(system2("Rscript", shQuote(file.path(S, "02_Infrastructure/ops", script)), stdout = TRUE, stderr = TRUE))
  paste(out, collapse = "\n")
}
jl <- function(S) { p <- file.path(S, ".cache/reinforce_auto_log.jsonl"); if (!file.exists(p)) return(list())
  Filter(Negate(is.null), lapply(readLines(p, warn = FALSE, encoding = "UTF-8"), function(l) tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL))) }
ev <- function(S) vapply(jl(S), function(z) as.character(z$event %||% ""), character(1))
led <- function(S) fromJSON(file.path(S, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
ent <- function(S, bid) Filter(function(e) identical(e$base_id, bid), led(S)$entries)[[1]]
att_n <- function(e, n) { a <- Filter(function(x) identical(as.integer(x$n), as.integer(n)), e$attempts); if (length(a)) a[[1]] else NULL }
gaq <- function(S) { p <- file.path(S, "06_Registry/grade_a_queue.json"); if (!file.exists(p)) return(list()); fromJSON(p, simplifyVector = FALSE)$entries %||% list() }
gaq_status <- function(S, bid, n) { q <- Filter(function(x) identical(x$base_id, bid) && identical(as.integer(x$attempt), as.integer(n)), gaq(S))
  if (length(q)) as.character(q[[1]]$status) else "" }
mbox <- function(S) list.files(file.path(S, "qepm/mailbox"), pattern = "^judge_request")
dec <- function(S) { p <- file.path(S, "06_Registry/rf_decisions.jsonl"); if (!file.exists(p)) return(list())
  Filter(function(r) identical(r$kind, "a_eligibility"), lapply(readLines(p, warn = FALSE, encoding = "UTF-8"), function(l) fromJSON(l, simplifyVector = FALSE))) }

cat("\n=== R. 러너 — 보류 A 는 entry 를 닫지 않는다 · 해제는 tick 시작 재평가 ===\n")
BID <- "T_E2E"
SA <- mk_sbx("a"); mk_ledger(SA, list(mk_entry(SA, BID))); set_plan(SA, list(B2_6 = list(grade = "A", regime = LEG)))
o1 <- run_script(SA, "reinforce_auto_parallel.R"); e1 <- ent(SA, BID); a6 <- att_n(e1, 6)
chk(!is.null(a6) && identical(a6$grade, "A") && isTRUE(a6$graduate_deferred) && identical(e1$status, "active"),
    "R1a legacy 규약 A(B2_6) → 등급 A 기록 · graduate_deferred · entry active 유지",
    sprintf("grade=%s deferred=%s status=%s | %s", a6$grade %||% "NULL", a6$graduate_deferred %||% "NULL", e1$status, substr(o1, max(1, nchar(o1) - 600), nchar(o1))))
chk(identical(gaq_status(SA, BID, 6), "held:legacy_regime"), "R1b grade_a_queue status = held:legacy_regime", gaq_status(SA, BID, 6))
chk(!length(mbox(SA)), "R1c qepm/mailbox judge_request 0건(발행 없음)", paste(mbox(SA), collapse = ","))
chk(!file.exists(file.path(a6$artifacts %||% "", "judge_request.json")) && file.exists(file.path(a6$artifacts %||% "", "judge_request.held.json")),
    "R1d 산출물의 judge_request.json(충실구현 러너가 A 면 쓴다)을 judge_request.held.json 으로 치웠다(관문 우회 차단)")
d1 <- dec(SA)
chk(length(d1) == 1L && identical(unlist(d1[[1]]$chosen$ids), "hold") && "legacy_regime" %in% unlist(d1[[1]]$scope$codes),
    "R1e 결정 기록 a_eligibility 1건(chosen=hold · codes=legacy_regime)", sprintf("%d건", length(d1)))
chk(all(c("grade_a_held", "cell_done") %in% ev(SA)), "R1f 로그 grade_a_held · cell_done")
set_plan(SA, list(B2_6 = list(grade = "A", regime = LEG), B2_7 = list(grade = "B")))
o2 <- run_script(SA, "reinforce_auto_parallel.R"); e2 <- ent(SA, BID); a7 <- att_n(e2, 7)
chk(!is.null(a7) && is.numeric(a7$essence$port_t) && identical(as.integer(e2$attempts_used), 7L) && identical(e2$status, "active"),
    "R2a 다음 tick 이 같은 entry 의 다음 칸(B2_7)을 소비 — 보류 A 가 탐색을 멈추지 않는다",
    sprintf("used=%s status=%s a7=%s | %s", e2$attempts_used, e2$status, !is.null(a7), substr(o2, max(1, nchar(o2) - 600), nchar(o2))))
chk(length(dec(SA)) == 1L && identical(gaq_status(SA, BID, 6), "held:legacy_regime"),
    "R2b tick 시작 재평가 — 보류 사유 불변이면 큐·결정 기록 추가 0(매 tick 소음 금지)", sprintf("dec=%d", length(dec(SA))))
L <- led(SA); k <- which(vapply(L$entries, function(e) identical(e$base_id, BID), logical(1)))
j6 <- which(vapply(L$entries[[k]]$attempts, function(a) identical(as.integer(a$n), 6L), logical(1)))
L$entries[[k]]$attempts[[j6]]$measurement_regime <- list(regime = CUR, basis = "rebase")   # rebase writer(reinforce_ledger.R)가 남기는 표식 모양
writeLines(toJSON(L, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(SA, "06_Registry/reinforce_ledger_l1.json"))
set_plan(SA, list(B2_8 = list(grade = "B")))
o3 <- run_script(SA, "reinforce_auto_parallel.R"); e3 <- ent(SA, BID)
jr6 <- file.path(SA, "qepm/mailbox", sprintf("judge_request_%s_6.json", BID))
chk(file.exists(jr6) && identical(gaq_status(SA, BID, 6), "awaiting_judge") && identical(e3$status, "graduated"),
    "R3a rebase 표식 뒤 tick 시작 재평가 → 후보별 mailbox 요청 · awaiting_judge · graduated",
    sprintf("jr=%s q=%s status=%s | %s", file.exists(jr6), gaq_status(SA, BID, 6), e3$status, substr(o3, max(1, nchar(o3) - 500), nchar(o3))))
chk(identical(as.integer(e3$attempts_used), 7L) && "entry_graduated_on_release" %in% ev(SA), "R3b 해제 tick 은 칸을 더 소비하지 않고 닫는다(entry_graduated_on_release)")
jrq <- tryCatch(fromJSON(jr6, simplifyVector = FALSE), error = function(e) list())
chk(identical(jrq$grade, "A") && identical(as.integer(jrq$layer), 1L) && identical(jrq$cell, "B2_6") && isTRUE(jrq$a_eligibility$eligible) &&
      nzchar(jrq$artifacts %||% "") && nzchar(jrq$strategy_id %||% ""),
    "R3c 요청 파일 = Judge 계약 필드(strategy_id·layer·grade·artifacts·engine_path) + 구 필드(base_id·attempt·cell) + 관문 요약")
a6b <- att_n(e3, 6)
chk(file.exists(file.path(a6b$artifacts, "judge_request.json")) && !file.exists(file.path(a6b$artifacts, "judge_request.held.json")) &&
      nzchar(a6b$graduate_released_at %||% ""), "R3d 발행 때 산출물 요청 복원 · attempt graduate_released_at")
d3 <- dec(SA); chk(length(d3) == 2L && identical(unlist(d3[[2]]$chosen$ids), "publish") && identical(d3[[2]]$scope$phase, "tick_start"),
                   "R3e 결정 기록 publish(phase=tick_start)")

SB <- mk_sbx("b"); mk_ledger(SB, list(mk_entry(SB, BID))); set_plan(SB, list(B2_6 = list(grade = "A", regime = CUR)))
ob <- run_script(SB, "reinforce_auto_parallel.R"); eb <- ent(SB, BID); ab <- att_n(eb, 6)
chk(identical(eb$status, "graduated") && identical(gaq_status(SB, BID, 6), "awaiting_judge") &&
      identical(mbox(SB), sprintf("judge_request_%s_6.json", BID)) && file.exists(file.path(ab$artifacts, "judge_request.json")),
    "R4 [양성] 현행 규약 A → 수집 즉시 발행(후보별 mailbox · awaiting_judge · graduated · 산출물 요청 유지)",
    sprintf("status=%s q=%s mb=%s | %s", eb$status, gaq_status(SB, BID, 6), paste(mbox(SB), collapse = ","), substr(ob, max(1, nchar(ob) - 500), nchar(ob))))
chk(!file.exists(file.path(SB, "qepm/mailbox/judge_request.json")), "R4b 구 단일 파일 qepm/mailbox/judge_request.json 은 쓰지 않는다(덮어쓰기 제거)")

cat("\n=== M. 돌연변이 — 관문이 실제로 가르는가 ===\n")
mutate <- function(S, from, to) {
  p <- file.path(S, "02_Infrastructure/ops/reinforce_auto_parallel.R"); s <- readLines(p, warn = FALSE, encoding = "UTF-8")
  hit <- grep(from, s, fixed = TRUE); if (length(hit) != 1L) return(FALSE)
  s[hit] <- sub(from, to, s[hit], fixed = TRUE); writeLines(s, p, useBytes = TRUE); TRUE
}
SM1 <- mk_sbx("m1"); mk_ledger(SM1, list(mk_entry(SM1, BID))); set_plan(SM1, list(B2_6 = list(grade = "A", regime = LEG)))
if (!mutate(SM1, '.routed <- .a_route(j$n, j$code, R$artifacts, es, .elA, "collect")',
            '.routed <- { .grade_a_enqueue(j$n, j$code, R$artifacts, es, .elA); TRUE }')) ng("M1 돌연변이 적용 실패(수집 경로 줄 부재)") else {
  run_script(SM1, "reinforce_auto_parallel.R")
  chk(length(mbox(SM1)) == 1L && identical(gaq_status(SM1, BID, 6), "awaiting_judge"),
      "M1 [돌연변이] 관문 우회 enqueue → legacy A 가 mailbox·awaiting_judge 에 선다 = R1b·R1c 가 이 결함을 잡는다", paste(mbox(SM1), collapse = ","))
}
SM2 <- mk_sbx("m2"); mk_ledger(SM2, list(mk_entry(SM2, BID))); set_plan(SM2, list(B2_6 = list(grade = "A", regime = LEG), B2_7 = list(grade = "B")))
if (!mutate(SM2, "graduate = is.null(.elA) || isTRUE(.elA$eligible)", "graduate = TRUE")) ng("M2 돌연변이 적용 실패(graduate 인자 줄 부재)") else {
  run_script(SM2, "reinforce_auto_parallel.R"); run_script(SM2, "reinforce_auto_parallel.R"); em <- ent(SM2, BID)
  chk(identical(em$status, "graduated") && is.null(att_n(em, 7)),
      "M2 [돌연변이] graduate 항상 TRUE → 보류 A 가 entry 를 닫아 B2_7 미소비 = R2a 가 이 결함을 잡는다",
      sprintf("status=%s a7=%s", em$status, !is.null(att_n(em, 7))))
}

cat("\n=== N. 이월(next_paper) — 승격 best 자격 · 규약 혼합 시 defer · 부모 기준선 ===\n")
mk_exh <- function(S, bid, regime, parent = NULL, pt = 2.5) {
  e <- mk_entry(S, bid); e$status <- "exhausted"
  e$attempts <- lapply(1:5, function(k) mk_b1(S, bid, k, regime = regime, pt = pt + k / 100))
  if (!is.null(parent)) { e$parent <- parent; e$carry <- list(factors = list(list(kind = "db", id = "F0")), universe = list(kind = "k200_kq150"),
                                                            universe_reset_from = list(kind = "k200_kq150")) }
  e
}
SN <- mk_sbx("n"); mk_ledger(SN, list(mk_exh(SN, "T_NP", LEG)))
on1 <- run_script(SN, "reinforce_auto_next_paper.R"); en <- ent(SN, "T_NP")
chk("promote_deferred_regime" %in% ev(SN) && !("promoted" %in% ev(SN)) && !isTRUE(en$handed_off) && !nzchar(en$summarized_at %||% "") &&
      length(led(SN)$entries) == 1L,
    "N1 칸 전부 legacy → promote_deferred_regime · 승격 0 · 이월·요약 표식 0(rebase 대기 — 사슬 보존)",
    sprintf("ev=%s | %s", paste(ev(SN), collapse = ","), substr(on1, max(1, nchar(on1) - 400), nchar(on1))))
L <- led(SN); for (j in seq_along(L$entries[[1]]$attempts)) L$entries[[1]]$attempts[[j]]$measurement_regime <- list(regime = CUR, basis = "rebase")
writeLines(toJSON(L, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(SN, "06_Registry/reinforce_ledger_l1.json"))
run_script(SN, "reinforce_auto_next_paper.R"); Ln <- led(SN)
ids <- vapply(Ln$entries, function(e) e$base_id, character(1))
chk("T_NP_promo1" %in% ids && isTRUE(Ln$entries[[which(ids == "T_NP")]]$handed_off),
    "N2 rebase 표식 뒤 → 승격 1(자식 entry) · 부모 handed_off", paste(ids, collapse = ","))
SN3 <- mk_sbx("n3")
gp <- mk_exh(SN3, "T_GP", LEG, pt = 9.0); gp$status <- "exhausted"; gp$handed_off <- TRUE; gp$summarized_at <- "2026-09-24T00:00:00+0900"
kid <- mk_exh(SN3, "T_GP_promo1", CUR, parent = list(base_id = "T_GP", depth = 1L, cell = "B1_5", best_port_t = 9.05, best_calmar = 0.3), pt = 2.5)
mk_ledger(SN3, list(gp, kid))
run_script(SN3, "reinforce_auto_next_paper.R"); L3 <- led(SN3); ids3 <- vapply(L3$entries, function(e) e$base_id, character(1))
chk("promote_parent_baseline_unavailable" %in% ev(SN3) && "T_GP_promo2" %in% ids3,
    "N3 부모 기준선 칸이 legacy(비교 불가) → 개선 판정 생략 · 승격 진행(구판이면 9.05 > 2.55 로 no_improvement)",
    sprintf("ev=%s ids=%s", paste(ev(SN3), collapse = ","), paste(ids3, collapse = ",")))

cat("\n=== Y. 러너 무결 — 샌드박스 tick 들에 fatal·기록 실패가 없다 ===\n")
BADEV <- c("fatal", "decision_record_failed", "grade_a_queue_failed", "judge_request_park_failed", "graduate_failed",
           "append_failed", "halt_no_b1_winner", "preflight_failed")
bad_ev <- unlist(lapply(list(SA = SA, SB = SB, SN = SN, SN3 = SN3), function(S) { e <- ev(S); e[e %in% BADEV] }))
chk(!length(bad_ev), "Y1 정상 경로 sandbox(SA·SB·SN·SN3) 로그에 fatal·기록 실패 이벤트 0", paste(bad_ev, collapse = ","))
if (nzchar(Sys.getenv("QVEST_E2E_DUMP"))) for (S in c(SA, SB, SN, SN3)) cat(sprintf("  [dump %s] %s\n", basename(S), paste(ev(S), collapse = ",")))

cat("\n=== Z. 운영 무접촉 ===\n")
chk(identical(md5_prod(), PROD0), "Z1 운영 원장·큐·결정 기록·러너 로그 md5 전후 동일")
chk(identical(sort(list.files(file.path(ROOT, "qepm/mailbox"), pattern = "^judge_request")), MB0), "Z2 운영 qepm/mailbox judge_request* 불변")
unlink(c(SA, SB, SM1, SM2, SN, SN3), recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_runner_a_gate_e2e","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
