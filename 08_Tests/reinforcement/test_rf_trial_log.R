#!/usr/bin/env Rscript
#==============================================================================
# test_rf_trial_log.R — 시행 로그 정본(P1-02) writer · 결정 id 수리 · 생산자 공용 함수 · 조인 (O0a · 2026-09-25)
#
# 계약(reinforce_ledger.R):
#   T1 rf_trial_log_append — 한 줄 append · schema rf_trial_v1 · trial_id 고유 · 재파싱
#   T2 거부 — kind 미등재 · essence/등급 객체 · 유기체 kind 의 decision_id/policy/organic.layer 부재 · design_source 어휘 밖
#   T3 rf_record_trial_decision — 결정 기록 + 시행 로그 같은 decision_id · 기각 = 선택 밖 후보(사유 보존) · 절단 시 n_rejected_total 원래 수
#   T4 조인(rf_trial_log_join) — 생산자 7종 조인 100% · 결정만 있는 주입 → missing_trial · 없는 결정을 가리키는 시행 → orphan_trial
#   T5 decision_id — 같은 초 400연속 결정이 전부 유일 · 돌연변이(구판 초 단위 id) → 중복 발생 = 이 단정이 잡는다
#   T6 reader — 파싱 실패 줄을 세어 돌려준다(n_bad · 조용한 버림 없음) · rf_trial_log_has(write-ahead 관문 판독)
#   T7 rf_append_attempt(design=) — 칸 설계 출처를 attempt 에 박는다 · 어휘 밖 거부 · 인자 없으면 필드 없음(구 호출 비트 동일)
# 격리: 임시 root · 운영 rf_trial_log.jsonl · rf_decisions.jsonl · 원장 md5 전후 동일.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
PROD <- file.path(ROOT, c("06_Registry/rf_trial_log.jsonl", "06_Registry/rf_decisions.jsonl", "06_Registry/reinforce_ledger_l1.json"))
md5p <- function() vapply(PROD, function(p) if (file.exists(p)) unname(tools::md5sum(p)) else "absent", character(1))
P0 <- md5p()
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))))
mk_root <- function(tag) { d <- file.path(tempdir(), sprintf("rftl_%s_%d_%d", tag, Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  dir.create(file.path(d, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(d, "02_Infrastructure"), recursive = TRUE, showWarnings = FALSE)
  writeLines("# marker", file.path(d, "02_Infrastructure/config.R")); normalizePath(d, winslash = "/") }
lines_of <- function(p) if (file.exists(p)) readLines(p, warn = FALSE, encoding = "UTF-8") else character(0)

cat("=== T1 append ===\n")
R <- mk_root("t1"); TL <- rf_trial_log_path(R)
r1 <- rf_trial_log_append("cell_registered", "RP_X", cells = list(list(code = "B2_6", n = 6L, design_source = "rule_catalog", design_lane = "rule_picker")),
                          src = "test", root = R)
L1 <- lines_of(TL); j1 <- fromJSON(L1[1], simplifyVector = FALSE)
chk(length(L1) == 1L && identical(j1$schema, "rf_trial_v1") && identical(j1$kind, "cell_registered") && identical(j1$cells[[1]]$design_source, "rule_catalog") &&
      isTRUE(j1$counted_in$lineage) && identical(j1$policy$policy_id, "pi0"), "T1a 1줄 · schema · 칸 출처 · counted_in.lineage(측정 칸) · policy 기본 pi0")
chk(grepl("^T_cell_registered_[0-9]{8}T[0-9]{9}-[0-9]+-[0-9a-f]{6}$", j1$trial_id), "T1b trial_id 형식(밀리초+순번+해시)", j1$trial_id)

cat("\n=== T2 거부 ===\n")
n0 <- length(lines_of(TL))
e <- c(err_of(rf_trial_log_append("no_such_kind", "x", root = R)),
       err_of(rf_trial_log_append("block_winner", "x", scope = list(essence = list(port_t = 3)), root = R)),
       err_of(rf_trial_log_append("organic_live", "x", root = R)),
       err_of(rf_trial_log_append("organic_live", "x", decision_id = "d1", root = R)),
       err_of(rf_trial_log_append("organic_live", "x", decision_id = "d1", policy = list(policy_id = "p", policy_sha = "s"), root = R)),
       err_of(rf_trial_log_append("cell_registered", "x", cells = list(list(code = "B1_1", design_source = "llm_magic")), root = R)))
chk(all(!is.na(e)) && grepl("kind", e[1]) && grepl("essence", e[2]) && grepl("decision_id", e[3]) && grepl("policy", e[4]) &&
      grepl("organic", e[5]) && grepl("어휘", e[6]) && length(lines_of(TL)) == n0,
    "T2 kind 미등재·essence 객체·유기체 필수 필드 3종·출처 어휘 밖 → 전부 거부 · 파일 불변", paste(substr(e, 1, 40), collapse = " | "))
ok_org <- rf_trial_log_append("organic_shadow", "program", decision_id = "d_org_1", policy = list(policy_id = "pi_dorm", policy_sha = "abc", mode = "shadow"),
                              organic = list(layer = "space", view_md5 = "v", tau_D = "2016-11-21"), root = R)
chk(identical(ok_org$organic$layer, "space") && length(lines_of(TL)) == n0 + 1L, "T2b [양성] 필수 필드를 갖춘 유기체 시행은 기록된다")

cat("\n=== T3 rf_record_trial_decision ===\n")
cands <- list(list(id = "B2_8", rank = 1L, reason = "port_t 최대"), list(id = "B2_6", rank = 2L, reason = "차점"), list(id = "B2_9", rank = 3L, reason = "3위"))
r3 <- rf_record_trial_decision("block_winner", "RP_X", cands, "B2_8", rule = list(src = "러너 .winner_of", by = "port_t"),
                               scope = list(block = "B2", by = "port_t", consumed_by = "B4"), root = R)
D <- rf_read_decisions(R, kind = "block_winner"); Tt <- rf_trial_log_read(R, kind = "block_winner")
chk(length(D) == 1L && length(Tt) == 1L && identical(D[[1]]$decision_id, Tt[[1]]$decision_id) && identical(unlist(Tt[[1]]$chosen), "B2_8") &&
      identical(vapply(Tt[[1]]$rejected, function(z) z$id, character(1)), c("B2_6", "B2_9")) && identical(Tt[[1]]$rejected[[1]]$reason, "차점") &&
      identical(Tt[[1]]$scope$block, "B2"), "T3a 결정·시행 같은 decision_id · 선택 B2_8 · 기각 2(사유 보존) · scope 부기")
many <- lapply(1:55, function(i) list(id = sprintf("c%02d", i), rank = i, reason = "r"))
rf_record_trial_decision("b1_factor_pick", "RP_X", many, "c01", rule = "picker", root = R)
t55 <- rf_trial_log_read(R, kind = "b1_factor_pick")[[1]]
chk(length(t55$rejected) == 40L && identical(as.integer(t55$n_rejected_total), 54L) && identical(as.integer(t55$n_candidates), 55L),
    "T3b 후보 55 → 기각 기록 40(상한) · n_rejected_total 54 · n_candidates 55(원래 수 보존)")
e <- err_of(rf_record_trial_decision("batch", "RP_X", cands, "B2_8", rule = "x", root = R))
chk(!is.na(e) && grepl("생산자", e), "T3c 생산자 kind 밖(batch) → 거부", e)

cat("\n=== T4 조인 ===\n")
for (k in c("floor", "b2_weight_pick", "b5_overlay_pick", "promote", "combination"))
  rf_record_trial_decision(k, "RP_X", cands, "B2_6", rule = "t", root = R)
J <- rf_trial_log_join(R)
chk(identical(J$join_rate, 1) && !length(J$missing_trial) && !length(J$orphan_trial) && J$n_decisions == 7L,
    "T4a 생산자 7종 조인 100%(결정 7 · 시행 7)", sprintf("rate=%s n=%d miss=%d orph=%d", J$join_rate, J$n_decisions, length(J$missing_trial), length(J$orphan_trial)))
dd <- rf_record_decision("floor", "RP_X", cands, "B2_6", rule = "only_decision", root = R)
rf_trial_log_append("floor", "RP_X", decision_id = "floor_RP_X_19990101T000000000-1-000000", root = R)
J2 <- rf_trial_log_join(R)
chk(identical(J2$missing_trial, dd$decision_id) && identical(J2$orphan_trial, "floor_RP_X_19990101T000000000-1-000000") && J2$join_rate < 1,
    "T4b 위반 주입 — 시행 없는 결정 → missing_trial · 없는 결정을 가리키는 시행 → orphan_trial(조인 < 100% 가 드러난다)")

cat("\n=== T5 decision_id 고유성 ===\n")
R5 <- mk_root("t5")
ids <- vapply(1:400, function(i) rf_record_decision("block_winner", "RP_SAME", cands, "B2_8", rule = "t", root = R5)$decision_id, character(1))
chk(!anyDuplicated(ids) && all(grepl("^block_winner_RP_SAME_[0-9]{8}T[0-9]{9}-[0-9]+-[0-9a-f]{6}$", ids)),
    "T5a 400연속(같은 kind·base·후보·선택) decision_id 전부 유일 · 형식 kind_base_<ms>-<순번>-<해시>", sprintf("dup=%d", sum(duplicated(ids))))
# 돌연변이 — id 생성기를 구판(초 단위 · 순번·해시 없음)으로 되돌린다
keep_uid <- .rf_uid
.rf_uid <- function(prefix, payload = "") sprintf("%s_%s", prefix, format(Sys.time(), "%Y%m%dT%H%M%S"))
R5m <- mk_root("t5m")
idm <- vapply(1:50, function(i) rf_record_decision("block_winner", "RP_SAME", cands, "B2_8", rule = "t", root = R5m)$decision_id, character(1))
.rf_uid <- keep_uid
chk(anyDuplicated(idm) > 0L, "T5b [돌연변이] 구판 초 단위 id → 같은 초 결정 중복 = T5a 가 이 결함을 잡는다", sprintf("dup=%d", sum(duplicated(idm))))

cat("\n=== T6 reader · has ===\n")
cat("{broken json\n", file = TL, append = TRUE)
Ra <- rf_trial_log_read(R)
chk(identical(attr(Ra, "n_bad"), 1L) && length(Ra) >= 10L, "T6a 파싱 실패 줄 1 → n_bad=1 로 셈(조용한 버림 없음)", as.character(attr(Ra, "n_bad")))
chk(isTRUE(rf_trial_log_has("d_org_1", R)) && !isTRUE(rf_trial_log_has("d_none", R)) && isTRUE(rf_trial_log_has(r3$decision$decision_id, R, kinds = "block_winner")) &&
      !isTRUE(rf_trial_log_has(r3$decision$decision_id, R, kinds = "floor")),
    "T6b rf_trial_log_has — 있는 id TRUE · 없는 id FALSE · kind 필터")

cat("\n=== T7 rf_append_attempt(design=) ===\n")
R7 <- mk_root("t7")
writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 35L, entries = list(list(base_id = "RP_T7", status = "active",
  attempts_used = 0L, attempts = list())), combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()), last_updated = ""),
  auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(R7, "06_Registry/reinforce_ledger_l1.json"))
invisible(capture.output(a1 <- rf_append_attempt(1L, "RP_T7", "t7 설계 칸", "weighting", list(), root = R7, cell_code = "B2_6",
                                                  design = list(design_source = "llm_masked", design_lane = "llm_block", exposure = "masked", basis = "rfbd"))))
invisible(capture.output(a2 <- rf_append_attempt(1L, "RP_T7", "t7 구 호출", "weighting", list(), root = R7, cell_code = "B2_7")))
e <- err_of(capture.output(rf_append_attempt(1L, "RP_T7", "t7 bad", "weighting", list(), root = R7, cell_code = "B2_8", design = list(design_source = "llm_magic"))))
L7 <- fromJSON(file.path(R7, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)$entries[[1]]$attempts
chk(identical(L7[[1]]$design$design_source, "llm_masked") && identical(L7[[1]]$design$design_lane, "llm_block") && is.null(L7[[2]]$design) &&
      !is.na(e) && grepl("어휘", e) && length(L7) == 2L,
    "T7 design 인자 → attempt$design 기록 · 인자 없으면 필드 없음(구 호출 동일) · 어휘 밖 거부(등록 0)")

cat("\n=== Z 운영 무접촉 ===\n")
chk(identical(md5p(), P0), "Z1 운영 rf_trial_log.jsonl · rf_decisions.jsonl · 원장 md5 전후 동일")
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_trial_log","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
