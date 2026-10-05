#!/usr/bin/env Rscript
#==============================================================================
# test_rf_consume_hold.R — 소비 보류 표식(B5FIX (c) · 도훈 결정 항목) 양방향 검사
#
# 사실(수리 전 · 2026-09-26 확인): A 관문 ⑤ vintage_flag 는 **발행만** 막는다. 후보 술어(rf_candidate_facts — 블록 승자·누적 바닥·carry 기준선·
#   승격 best 가 전부 지난다)는 vintage_flags 를 보지 않아 possible 표식 B5 칸이 G2 pass 면 소비되고, 그 칸을 소비한 칸(B4 결합 등)은
#   표식을 물려받지 않는다(design_materials_cross_entry_labels 는 계보 재도출 rf_lineage_flags.R 대상이 아니다).
# 수리(선택 · 설정으로 켠다): a_eligibility_gate.json::holds.vintage_flag.consume_hold {flags, verdicts} 에 걸린 표식 칸 = 소비 후보 아님.
#   C1 설정 있음 → 표식 칸(possible) 제외 · 다른 flag(pit_c11) 칸 · 무표식 칸 유지 · 로그 사유 vintage_hold
#   C2 설정 없음(키 부재) → 전부 유지(현행 거동 · 항등)
#   C3 승격 best(rf_promote_best) — 설정 있음: PORT_t 최고인 표식 칸 대신 다음 칸 · 없음: 표식 칸
#   C4 [사실 기록] 표식 칸의 층을 물려받은 칸(무표식)은 어느 설정에서도 후보 술어가 막지 않는다 — 막는 자리는 원천 칸의 소비다
#   M1 [돌연변이] 술어의 표식 검사 삭제 → C1 red
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_consume_hold.R   (약 10초)
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
TMP <- gsub("\\", "/", tempdir(), fixed = TRUE)
mk_root <- function(tag, with_hold, gates_src = file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")) {
  S <- file.path(TMP, sprintf("chold_%s_%d", tag, Sys.getpid())); unlink(S, recursive = TRUE, force = TRUE)
  for (d in c("02_Infrastructure/reinforcement", "02_Infrastructure/worktask", "02_Infrastructure/contracts", "06_Registry", ".cache/rf_parallel"))
    dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files(file.path(ROOT, "02_Infrastructure/reinforcement"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/reinforcement"))
  file.copy(gates_src, file.path(S, "02_Infrastructure/reinforcement/rf_runner_gates.R"), overwrite = TRUE)
  file.copy(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(S, "02_Infrastructure/worktask"))
  file.copy(list.files(file.path(ROOT, "02_Infrastructure/contracts"), pattern = "[.]R$", full.names = TRUE), file.path(S, "02_Infrastructure/contracts"))
  file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(S, "06_Registry"))
  g <- fromJSON(file.path(ROOT, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE)
  if (with_hold) g$holds$vintage_flag$consume_hold <- list(flags = list("design_materials_cross_entry_labels"), verdicts = list("possible", "consumed"))
  else g$holds$vintage_flag$consume_hold <- NULL
  writeLines(toJSON(g, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(S, "06_Registry/a_eligibility_gate.json"))
  S
}
load_env <- function(S) {
  old <- Sys.getenv("QM_ROOT", unset = NA); Sys.setenv(QM_ROOT = S); on.exit(if (is.na(old)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = old))
  e <- new.env()
  invisible(capture.output(suppressMessages({
    sys.source(file.path(S, "02_Infrastructure/reinforcement/reinforce_ledger.R"), envir = e)
    sys.source(file.path(S, "02_Infrastructure/reinforcement/rf_spec_sig.R"), envir = e)
    sys.source(file.path(S, "02_Infrastructure/reinforcement/rf_block_design.R"), envir = e)
    sys.source(file.path(S, "02_Infrastructure/reinforcement/rf_runner_gates.R"), envir = e)
    sys.source(file.path(S, "02_Infrastructure/reinforcement/rf_promote.R"), envir = e) })))
  e
}
CUR <- as.character(fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$execution$exec_price)
att <- function(S, n, code, pt, flags = list(), overlay = NULL) {
  sp <- file.path(S, ".cache/rf_parallel", sprintf("spec_%s__T_CH.json", code))
  spec <- list(code = code, universe = list(kind = "k200_kq150"), overlay_cell = overlay %||% list())
  if (!is.null(overlay)) spec$overlay <- overlay
  writeLines(toJSON(spec, auto_unbox = TRUE, null = "null"), sp)
  list(n = as.integer(n), cell_code = code, grade = "B", measurement_regime = list(exec_price = CUR, regime = CUR), vintage_flags = flags,
       adversary = if (startsWith(code, "B5_")) list(verdict = "pass") else NULL,
       essence = list(cell_code = code, port_t = pt, calmar = 0.4, window_deviation_months = 0, spec = sp))
}
FL_DM <- list(list(flag = "design_materials_cross_entry_labels", verdict = "possible", source = "ORGANIC-DE Q④"))
FL_C11 <- list(list(flag = "pit_c11", verdict = "consumed"))
cases <- function(S) list(att(S, 1, "B5_17", 2.0, FL_DM, overlay = list(kind = "k1", arm_id = "arm1")),
                          att(S, 2, "B2_10", 1.8), att(S, 3, "B1_4", 1.5, FL_C11),
                          att(S, 4, "B4_21", 1.9, overlay = list(kind = "k1", arm_id = "arm1")))
codes <- function(L) vapply(L, function(a) a$cell_code, "")
logs <- list(); lg <- function(ev, ...) logs[[length(logs) + 1L]] <<- c(list(event = ev), list(...))

cat("\n=== C. 소비 보류 표식 ===\n")
S1 <- mk_root("on", TRUE); e1 <- load_env(S1); ctx1 <- e1$rf_runner_ctx(S1); A1 <- cases(S1)
chk(identical(ctx1$consume_hold$flags, "design_materials_cross_entry_labels"), "C0 설정 판독 — consume_hold.flags")
k1 <- e1$rf_candidates_keep(A1, ctx1, role = "floor", log = lg, base_id = "T_CH")
w1 <- e1$rf_candidates_keep(A1, ctx1, role = "winner_B5", log = lg, base_id = "T_CH")
chk(identical(codes(k1), c("B2_10", "B1_4", "B4_21")) && identical(codes(w1), c("B2_10", "B1_4", "B4_21")),
    "C1a 설정 있음 — 표식 칸(B5_17 · possible) 제외(바닥·승자 역할) · pit_c11 칸·무표식 칸 유지", paste(codes(k1), collapse = ","))
chk(any(vapply(logs, function(x) grepl("vintage_hold", as.character(x$by_reason %||% "")), logical(1))), "C1b 제외 사유 = vintage_hold(candidates_excluded 로그)")
E1 <- list(base_id = "T_CH", attempts = A1)
pb1 <- e1$rf_promote_best(E1, ctx1)
chk(identical(A1[[pb1$i]]$cell_code, "B4_21") && "B5_17" %in% names(pb1$excluded), "C3a 설정 있음 — 승격 best = 다음 칸(B4_21) · B5_17 제외 기록", paste(names(pb1$excluded), collapse = ","))
S2 <- mk_root("off", FALSE); e2 <- load_env(S2); ctx2 <- e2$rf_runner_ctx(S2); A2 <- cases(S2)
k2 <- e2$rf_candidates_keep(A2, ctx2, role = "floor")
chk(identical(codes(k2), c("B5_17", "B2_10", "B1_4", "B4_21")) && !length(ctx2$consume_hold$flags), "C2 설정 없음 — 전부 유지(현행 거동 · 항등)")
pb2 <- e2$rf_promote_best(list(base_id = "T_CH", attempts = A2), ctx2)
chk(identical(A2[[pb2$i]]$cell_code, "B5_17"), "C3b 설정 없음 — 승격 best = PORT_t 최고 표식 칸(B5_17 · 현행 = 소비됨)")
chk(!length(e1$rf_candidate_facts(A1[[4]], ctx1)$fail) && !length(e2$rf_candidate_facts(A2[[4]], ctx2)$fail),
    "C4 [사실] 표식 칸의 층을 물려받은 무표식 칸(B4_21)은 어느 설정에서도 술어가 막지 않는다 — 표식은 승계되지 않는다(막는 자리 = 원천 칸의 소비)")

cat("\n=== M. 돌연변이 ===\n")
G <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")
s <- readLines(G, warn = FALSE, encoding = "UTF-8"); h <- grep("  if (length(ch$flags)) {", s, fixed = TRUE)
if (length(h) != 1L) ng("M1 적용 실패(표식 검사 줄 부재)") else {
  s[h] <- "  if (FALSE) {"; mp <- file.path(TMP, sprintf("mut_gates_%d.R", Sys.getpid())); writeLines(s, mp, useBytes = TRUE)
  S3 <- mk_root("mut", TRUE, gates_src = mp); e3 <- load_env(S3); ctx3 <- e3$rf_runner_ctx(S3)
  k3 <- e3$rf_candidates_keep(cases(S3), ctx3, role = "floor")
  chk("B5_17" %in% codes(k3), "M1 [돌연변이] 술어의 표식 검사 삭제 → 설정이 있어도 표식 칸이 바닥 후보로 남는다 = C1a 가 잡는다")
}
unlink(list.files(TMP, pattern = "^chold_", full.names = TRUE), recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_consume_hold","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
