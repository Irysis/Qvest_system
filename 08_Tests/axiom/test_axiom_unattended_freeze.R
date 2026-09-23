#!/usr/bin/env Rscript
#==============================================================================
# test_axiom_unattended_freeze.R — 판정서 ⑦ 마디 ⓑ '무인 승격 0' + 단계 0/1 이행 계약 (2026-09-23)
#
# 근거: Axiom 엔진 효용 전수감사 wf_d8ee80de-26d 판정서 · 도훈 AX-D1~D5 (06_Registry/decision_register.json)
#
# 축 (각 축 = 양성 대조 + 위반 주입/돌연변이 — 초록이 계측 사망과 구별되게)
#   B0 스위치 정본: promote.R::.unattended_enabled() — 미설정 FALSE · "0" FALSE · "1" TRUE
#   B1 승격 경로(샌드박스): REFINED 스텁 후보 → 기본 env 에서 status=proposed(active 0) · 접두 AX-RF/AX-RP(GEN 폴백 아님)
#        양성 대조: QVEST_AXIOM_UNATTENDED=1 → active (스텁이 실제로 활성화 가능한 입력임을 증명)
#        돌연변이 M-B1: promote.R 기본값 '1' 복원본 → 기본 env 에서 active 발생(검출)
#   B2 월간·주간 증류: monthly/weekly_distill.R 의 promote_to_axiom 호출을 **파스 트리에서 꺼내 그대로 실행**
#        (스위치=1 최악 조건) → 쓰기 0. 돌연변이 M-B2: dry_run 제거 / FALSE → 쓰기 발생(검출)
#   B3 rf_axiom_activate.R(샌드박스 자식 프로세스): 기본 env → halt_unattended_off · 활성 0
#        양성 대조: =1 → 활성화 · 돌연변이 M-B3: 가드 무력화 사본 → 기본 env 에서 활성화(검출)
#        ★텔레그램 격리: 샌드박스에 telegram_notify.R 이 없음을 실행 전에 단정(없으면 발송 경로가 원리적으로 불가)
#   B4 표시 계기: 스위치 기본값을 적은 Sys.getenv("QVEST_AXIOM_UNATTENDED", …) 는 promote.R 1곳뿐(파스 트리) · 그 기본값 "0"
#   R  운영 상태(읽기 전용): mode-local 활성 0 · 19건 deprecated/*_rollback_* + tombstone(사유·미해제) · 역링크 무접촉 ·
#        sot_map 에서 제거 · 메가후보 _retired_20260923 보관(삭제 아님)
#   H  hypothesis_index 보충 스캔 가드: corpus.invalidated_lcodes 가 dedup 키에 먼저 들어가 표식 원천을 재색인하지 않는다
#        돌연변이 M-H: 가드 제거 사본 → 표식 L-code 재색인(검출)
#   I  주입 훅(1-6): 전역 Law 4건 전문 렌더 · len ≤2000 · 마커 3종 생존 · mode-local 0
#        돌연변이 M-I: [:80] 절단 복원 사본 → AX-000 금지절 꼬리 소실(검출)
#   D  D5 문언: AX-001 v3 · AX-008 v2.0 — 승인 필드 · 구판 history 보존 · axioms.md 문서 SOT 일치 · enforcement_hook 의미론 생존
#        (mode 값은 고정하지 않는다 — 'block 오기' 수정 여부는 도훈 결정. 양성 대조 = 고친 사본도 통과 · 돌연변이 M-D1~3)
#        AX-008 최상위 = v2.0 기준만(구판 근거 필드는 history[0]) · 돌연변이 M-D4
#        전파 가드(P): 주입면 문서(agents·skills·workflows·_shared_prefix·charter Axiom 절·artifact_contract·Lawbook INDEX)에
#        구 문언(Triangulation·3-source·2/3 PASS·AX-001 v2·conditional defense 등) 0 — '사료/history' 포인터 줄만 허용 · 돌연변이 M-P
#
# 격리: 쓰기는 tempdir() 샌드박스에만. 운영 트리는 읽기만 한다(R·D·B4).
# 실행: Rscript 08_Tests/axiom/test_axiom_unattended_freeze.R
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, if (nzchar(d)) paste0(" :: ", d) else "", "\n") }
chk <- function(m, cond, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)

ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
PROMOTE <- file.path(ROOT, "02_Infrastructure/axiom/promote.R")
SB0 <- gsub("\\", "/", tempfile("axfreeze_"), fixed = TRUE)
dir.create(SB0, recursive = TRUE)
invisible(reg.finalizer(globalenv(), function(e) unlink(SB0, recursive = TRUE, force = TRUE), onexit = TRUE))

# 환경변수 격리 — 설정·해제 후 반드시 원복(r-portability ①: system2(env=) 대신 setenv + 복원)
.env_keep <- c("QVEST_AXIOM_UNATTENDED", "CLAUDE_PROJECT_DIR", "QM_ROOT", "PROMOTE_SOURCED")
.env_orig <- Sys.getenv(.env_keep, unset = NA_character_)
.env_restore <- function() for (k in .env_keep) {
  v <- .env_orig[[k]]; if (is.na(v)) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(v), k)) }
.with_unatt <- function(val, expr) {
  if (is.null(val)) Sys.unsetenv("QVEST_AXIOM_UNATTENDED") else Sys.setenv(QVEST_AXIOM_UNATTENDED = val)
  on.exit(.env_restore(), add = TRUE)
  force(expr)
}

# promote.R 를 격리 env 로 적재 + 정제기 스텁(REFINED) 주입 — 승격 입력을 '활성화 가능'으로 고정해야 스위치만 잰다
.load_promote <- function(src = PROMOTE) {
  e <- new.env(parent = globalenv())
  Sys.setenv(PROMOTE_SOURCED = "1")
  suppressMessages(capture.output(sys.source(src, envir = e)))
  Sys.unsetenv("PROMOTE_SOURCED")
  e$.call_refine_statement <- function(candidate, corpus, root = NULL, peers = NULL)
    list(verdict = "REFINED", failing = list(), statement = "픽스처 정제 문장(테스트)",
         statement_inject = "픽스처 주입 문장", refine_input_sha = "fx_sha", gates = list())
  e
}
.mk_sandbox <- function(tag, mode = "reinforcement", key = "aaaaaaaaaaaa") {
  sb <- file.path(SB0, tag)
  for (d in c(".cache", "qepm/memory/axioms/active/modes", "qepm/memory/axioms/candidates"))
    dir.create(file.path(sb, d), recursive = TRUE, showWarnings = FALSE)
  lc <- function(id, g, ct) list(l_code = id, grade = g, construction_type = ct, metric_type = "backtested",
                                 research_mode = mode, portfolio_alpha_t = 1.5, oos_retention = 0.6)
  write_json(list(lcodes = list(lc("L-FX-1", "A", "momentum"), lc("L-FX-2", "B", "value"),
                                lc("L-FX-3", "A", "quality"))),
             file.path(sb, ".cache/lcode_corpus.json"), auto_unbox = TRUE, pretty = TRUE)
  cand <- list(candidate_id = sprintf("CAND_%s_%s", mode, key), cluster_key = key, research_mode = mode,
               metric_type = "backtested", type = "empirical", polarity = "positive",
               statement_draft = "픽스처 규칙", supporting_l_codes = c("L-FX-1", "L-FX-2", "L-FX-3"),
               mechanism_draft = list(economic_explanation = "픽스처 기전 설명", mechanism_type = "behavioral",
                                      causal_plausibility = "moderate"),
               falsification_draft = list(attempts = list()), oos_validation_draft = list(),
               scope_draft = list(), evidence_draft = list(), promotable = TRUE)
  cp <- file.path(sb, "qepm/memory/axioms/candidates", sprintf("CAND_%s_%s.json", mode, key))
  write_json(cand, cp, auto_unbox = TRUE, pretty = TRUE)
  list(root = sb, cand = cp)
}
.snap <- function(sb) {
  fs <- list.files(file.path(sb, "qepm/memory/axioms"), recursive = TRUE, full.names = TRUE, all.files = TRUE)
  fs <- fs[!grepl("/candidates/", fs, fixed = TRUE)]
  if (!length(fs)) return(character(0))
  stats::setNames(unname(tools::md5sum(fs)), sub(sb, "", fs, fixed = TRUE))
}
.ax_files <- function(sb) list.files(file.path(sb, "qepm/memory/axioms/active/modes"), pattern = "^AX-.*\\.json$",
                                     recursive = TRUE, full.names = TRUE)
.ax_status <- function(sb) vapply(.ax_files(sb), function(f) as.character(fromJSON(f)$status %||% "?"), character(1))

#── B0 ───────────────────────────────────────────────────────────────────────
cat("\n[B0] 스위치 정본 — promote.R::.unattended_enabled()\n")
P0 <- .load_promote()
chk("B0-1 미설정 → FALSE (기본 OFF)", identical(.with_unatt(NULL, P0$.unattended_enabled()), FALSE))
chk("B0-2 '0' → FALSE", identical(.with_unatt("0", P0$.unattended_enabled()), FALSE))
chk("B0-3 '1' → TRUE (명시 활성만)", identical(.with_unatt("1", P0$.unattended_enabled()), TRUE))

#── B1 ───────────────────────────────────────────────────────────────────────
cat("\n[B1] 승격 경로 — REFINED 스텁 후보가 기본 env 에서 active 를 쓰지 않는다 + 접두 RF/RP\n")
.run_promote <- function(pe, sb, unatt) {
  Sys.setenv(CLAUDE_PROJECT_DIR = sb$root)
  on.exit(.env_restore(), add = TRUE)
  .with_unatt(unatt, suppressMessages({ out <- capture.output(r <- pe$promote_to_axiom(sb$cand)); r }))
}
s1 <- .mk_sandbox("b1_default")
r1 <- .run_promote(P0, s1, NULL)
st1 <- .ax_status(s1$root)
chk("B1-1 판정 PASS(스텁 입력이 승격 대상임)", identical(r1$verdict, "PASS"), as.character(r1$verdict))
chk("B1-2 기본 env → 공리 status=proposed · active 0", length(st1) == 1L && all(st1 == "proposed"), paste(st1, collapse = ","))
chk("B1-3 접두 AX-RF (reinforcement — GEN 폴백 아님, 0-3)", identical(basename(names(st1)), "AX-RF-001.json"),
    paste(basename(names(st1)), collapse = ","))
s1p <- .mk_sandbox("b1_rp", mode = "paper_replication", key = "bbbbbbbbbbbb")
invisible(.run_promote(P0, s1p, NULL))
chk("B1-4 접두 AX-RP (paper_replication — 메가후보가 GEN 으로 가던 자리)",
    identical(basename(names(.ax_status(s1p$root))), "AX-RP-001.json"), paste(basename(names(.ax_status(s1p$root))), collapse = ","))
s1c <- .mk_sandbox("b1_pos")
invisible(.run_promote(P0, s1c, "1"))
chk("B1-5 양성 대조: =1 이면 같은 입력이 active (스위치가 유일한 차이)", identical(unname(.ax_status(s1c$root)), "active"),
    paste(.ax_status(s1c$root), collapse = ","))
# 돌연변이 M-B1 — 기본값 '1' 복원
src_txt <- readLines(PROMOTE, warn = FALSE, encoding = "UTF-8")
pat <- 'Sys.getenv("QVEST_AXIOM_UNATTENDED", "0")'
n_hit <- sum(grepl(pat, src_txt, fixed = TRUE))
if (n_hit != 1L) ng("M-B1 돌연변이 대상 줄 수 ≠ 1 — 계기 재설계 필요", as.character(n_hit)) else {
  mut <- file.path(SB0, "promote_mut_default1.R")
  writeLines(sub(pat, 'Sys.getenv("QVEST_AXIOM_UNATTENDED", "1")', src_txt, fixed = TRUE), mut, useBytes = TRUE)
  Pm <- .load_promote(mut)
  s1m <- .mk_sandbox("b1_mut")
  invisible(.run_promote(Pm, s1m, NULL))
  chk("M-B1 기본값 '1' 복원 사본 → 기본 env 에서 active 발생(검출 — B1-2 가 이 변화를 잡는다)",
      identical(unname(.ax_status(s1m$root)), "active"), paste(.ax_status(s1m$root), collapse = ","))
}

#── B2 ───────────────────────────────────────────────────────────────────────
cat("\n[B2] 월간·주간 증류 — promote_to_axiom 호출을 파스 트리에서 꺼내 그대로 실행(스위치=1 최악 조건)\n")
# 파스 트리 재도출(주석·문자열 grep 아님): getParseData 로 함수 호출 토큰을 찾아 그 호출식 전체를 다시 파싱한다.
#   (언어 객체를 재귀로 걸으면 formals 의 빈 인자에서 'argument missing' 으로 죽는다 — 실측)
.find_calls <- function(path, fname) {
  pd <- utils::getParseData(parse(path, keep.source = TRUE), includeText = TRUE)
  fn_expr <- pd$parent[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == fname]
  call_ids <- pd$parent[match(fn_expr, pd$id)]
  lapply(call_ids, function(id) parse(text = pd$text[pd$id == id], keep.source = FALSE)[[1]])
}
.eval_call <- function(cl, pe, sb) {
  env <- new.env(parent = globalenv())
  env$promote_to_axiom <- pe$promote_to_axiom
  env$cp <- sb$cand
  Sys.setenv(CLAUDE_PROJECT_DIR = sb$root)
  on.exit(.env_restore(), add = TRUE)
  before <- .snap(sb$root)
  .with_unatt("1", suppressMessages(capture.output(r <- tryCatch(eval(cl, env), error = function(e) e))))
  list(r = r, before = before, after = .snap(sb$root))
}
for (fn in c("monthly_distill.R", "weekly_distill.R")) {
  pth <- file.path(ROOT, "02_Infrastructure/memory", fn)
  cls <- .find_calls(pth, "promote_to_axiom")
  chk(sprintf("B2 %s — promote_to_axiom 호출 1개 발견", fn), length(cls) == 1L, as.character(length(cls)))
  if (length(cls) != 1L) next
  cl <- cls[[1]]
  chk(sprintf("B2 %s — dry_run 인자 = TRUE 리터럴", fn), identical(cl$dry_run, TRUE), deparse(cl$dry_run))
  sb <- .mk_sandbox(paste0("b2_", fn))
  ev <- .eval_call(cl, P0, sb)
  chk(sprintf("B2 %s — 호출 그대로 실행 시 공리 트리 쓰기 0 (스위치=1 에서도)", fn),
      !inherits(ev$r, "error") && identical(ev$before, ev$after),
      if (inherits(ev$r, "error")) conditionMessage(ev$r) else paste(setdiff(names(ev$after), names(ev$before)), collapse = ","))
  for (mv in list(list(lab = "dry_run 제거", v = NULL, drop = TRUE), list(lab = "dry_run=FALSE", v = FALSE, drop = FALSE))) {
    cm <- cl
    if (isTRUE(mv$drop)) cm$dry_run <- NULL else cm$dry_run <- mv$v
    sbm <- .mk_sandbox(paste0("b2m_", fn, "_", if (isTRUE(mv$drop)) "drop" else "false"))
    evm <- .eval_call(cm, P0, sbm)
    chk(sprintf("M-B2 %s — %s → 쓰기 발생(검출)", fn, mv$lab), !identical(evm$before, evm$after))
  }
}

#── B3 ───────────────────────────────────────────────────────────────────────
cat("\n[B3] rf_axiom_activate.R — 세 번째 무인 활성 경로(샌드박스 자식 프로세스)\n")
ACT_SRC <- file.path(ROOT, "02_Infrastructure/ops/rf_axiom_activate.R")
RS <- file.path(R.home("bin"), "Rscript")
.mk_act_sb <- function(tag) {
  sb <- file.path(SB0, tag)
  for (d in c(".cache", "06_Registry", "02_Infrastructure/axiom", "02_Infrastructure/utils", "02_Infrastructure/ops",
              "qepm/memory/axioms/active/modes/testmode"))
    dir.create(file.path(sb, d), recursive = TRUE, showWarnings = FALSE)
  file.copy(PROMOTE, file.path(sb, "02_Infrastructure/axiom/promote.R"))
  file.copy(file.path(ROOT, "02_Infrastructure/utils/atomic_json.R"), file.path(sb, "02_Infrastructure/utils/atomic_json.R"))
  write_json(list(enabled = TRUE), file.path(sb, "06_Registry/reinforce_auto_config.json"), auto_unbox = TRUE)
  # ★같은 모드의 기존 active 1건 — rf_axiom_activate.R 은 활성 0건 모드에서 table()[[mode]] 가 'subscript out of bounds'
  #   로 fatal 한다(선행 결함, 퇴역 예정 스크립트라 수리하지 않음·보고). 양성 대조가 그 결함이 아니라 가드 뒤 경로를 재도록 둔다.
  write_json(list(axiom_id = "AX-TST-000", research_mode = "testmode", status = "active", polarity = "positive",
                  needs_refinement = FALSE, refine_verdict = "REFINED", statement_inject = "기존 활성 픽스처",
                  promotion = list(all_hurdles_pass = TRUE, weighted_score = 0.5), supporting_l_codes = list()),
             file.path(sb, "qepm/memory/axioms/active/modes/testmode/AX-TST-000.json"), auto_unbox = TRUE, pretty = TRUE)
  write_json(list(axiom_id = "AX-TST-001", research_mode = "testmode", status = "proposed", polarity = "positive",
                  needs_refinement = FALSE, refine_verdict = "REFINED", statement_inject = "픽스처",
                  promotion = list(all_hurdles_pass = TRUE, weighted_score = 0.9), supporting_l_codes = list()),
             file.path(sb, "qepm/memory/axioms/active/modes/testmode/AX-TST-001.json"), auto_unbox = TRUE, pretty = TRUE)
  sb
}
# ★격리 사고 방지(2026-09-23 초판 실측): 자식 Rscript 는 시작 시 ~/.Renviron 을 읽어 **QM_ROOT 를 운영 루트로 덮어쓴다** —
#   부모의 Sys.setenv(QM_ROOT=샌드박스)가 무시돼 초판은 운영 루트에서 돌았다(당시 운영 mode-local 0건이라 활성화 없이
#   no_candidates 로 끝났고, 운영 .cache/reinforce_auto_log.jsonl 에 3줄만 남았다). 두 겹으로 막는다:
#   ① --no-environ + 래퍼가 **시작 후** QM_ROOT 를 샌드박스로 다시 박고 source 한다
#   ② 실행 후 샌드박스 로그에 이벤트가 있는지로 '자식이 실제로 샌드박스를 봤다'를 단정 — 아니면 이후 실행(양성 대조) 전면 중단
.act_isolated <- TRUE
.run_act <- function(sb, unatt, script = ACT_SRC) {
  if (!isTRUE(.act_isolated)) stop("앞선 실행이 샌드박스를 보지 않았다 — 운영 루트 오염 위험, 실행 중단")
  if (file.exists(file.path(sb, "02_Infrastructure/telegram/telegram_notify.R")))
    stop("샌드박스에 telegram_notify.R 존재 — 발송 경로 격리 실패, 실행 중단")
  wrap <- file.path(sb, "run_act_wrapper.R")
  writeLines(c(sprintf('Sys.setenv(QM_ROOT = "%s")', sb), sprintf('source("%s")', script)), wrap, useBytes = TRUE)
  Sys.setenv(QM_ROOT = sb)
  on.exit(.env_restore(), add = TRUE)
  out <- .with_unatt(unatt, suppressWarnings(system2(RS, c("--no-environ", shQuote(wrap)), stdout = TRUE, stderr = TRUE)))
  lg <- file.path(sb, ".cache/reinforce_auto_log.jsonl")
  log <- if (file.exists(lg)) readLines(lg, warn = FALSE) else character(0)
  if (!any(grepl('"src":"axiom_activate"', log, fixed = TRUE))) {
    .act_isolated <<- FALSE
    ng("B3 격리 단정 — 자식 프로세스가 샌드박스 로그에 기록하지 않았다(운영 루트를 봤을 수 있음)",
       paste(tail(out, 3), collapse = " | "))
  }
  list(out = out, log = log,
       status = as.character(fromJSON(file.path(sb, "qepm/memory/axioms/active/modes/testmode/AX-TST-001.json"))$status))
}
a0 <- .run_act(.mk_act_sb("b3_default"), NULL)
chk("B3-1 기본 env → 활성 0 (status=proposed 유지)", identical(a0$status, "proposed"), a0$status)
chk("B3-2 기본 env → halt_unattended_off 기록", any(grepl("halt_unattended_off", a0$log, fixed = TRUE)),
    paste(tail(c(a0$log, a0$out), 3), collapse = " | "))
a1 <- .run_act(.mk_act_sb("b3_pos"), "1")
chk("B3-3 양성 대조: =1 → 활성화(가드 뒤 경로가 살아 있다)", identical(a1$status, "active"),
    paste(tail(c(a1$log, a1$out), 3), collapse = " | "))
act_txt <- readLines(ACT_SRC, warn = FALSE, encoding = "UTF-8")
gpat <- "  if (!on_) {"
if (sum(act_txt == gpat) != 1L) ng("M-B3 돌연변이 대상 줄 수 ≠ 1 — 계기 재설계 필요", as.character(sum(act_txt == gpat))) else {
  sbm <- .mk_act_sb("b3_mut")
  mut_act <- file.path(sbm, "02_Infrastructure/ops/rf_axiom_activate_mut.R")
  writeLines(ifelse(act_txt == gpat, "  if (FALSE) {", act_txt), mut_act, useBytes = TRUE)
  am <- .run_act(sbm, NULL, mut_act)
  chk("M-B3 가드 무력화 사본 → 기본 env 에서 활성화(검출 — B3-1 이 이 변화를 잡는다)", identical(am$status, "active"), am$status)
}

#── B4 ───────────────────────────────────────────────────────────────────────
cat("\n[B4] 표시 계기 — 스위치 기본값은 promote.R 1곳뿐(두 벌 술어 금지)\n")
.getenv_unatt <- function(path) {
  cls <- .find_calls(path, "Sys.getenv")
  Filter(function(cl) length(cl) >= 2L && identical(cl[[2]], "QVEST_AXIOM_UNATTENDED"), cls)
}
g_p <- .getenv_unatt(PROMOTE)
chk("B4-1 promote.R 정의 1곳 · 기본값 \"0\"", length(g_p) == 1L && identical(g_p[[1]][[3]], "0"),
    paste(vapply(g_p, function(x) paste(deparse(x), collapse = ""), ""), collapse = " ; "))
for (rel in c("02_Infrastructure/ops/weekly_cleaner_sweep.R", "02_Infrastructure/ops/morning_steps/axiom_approval_queue.R",
              "02_Infrastructure/ops/rf_axiom_activate.R", "02_Infrastructure/memory/monthly_distill.R",
              "02_Infrastructure/memory/weekly_distill.R")) {
  g <- .getenv_unatt(file.path(ROOT, rel))
  chk(sprintf("B4 %s — 기본값 사본 0 (정본 술어 경유)", basename(rel)), length(g) == 0L,
      paste(vapply(g, function(x) paste(deparse(x), collapse = ""), ""), collapse = " ; "))
}

#── R ────────────────────────────────────────────────────────────────────────
cat("\n[R] 운영 상태(읽기 전용) — mode-local 처분 · 메가후보 보관\n")
AXD <- file.path(ROOT, "qepm/memory/axioms")
IDS <- c("AX-AR-001", "AX-AR-002", "AX-AR-003", "AX-AR-004", "AX-AS-001", "AX-AS-002", "AX-AS-003", "AX-JG-001",
         "AX-QPM-001", "AX-QPM-002", "AX-QPM-003", "AX-QPM-004", "AX-QPM-005",
         "AX-RAMP-001", "AX-RAMP-002", "AX-RAMP-003", "AX-RAMP-004", "AX-RAMP-005", "AX-RAMP-006")
IMMEDIATE <- c("AX-AR-004", "AX-AR-002", "AX-RAMP-005", "AX-RAMP-006")   # AS-002 는 이미 proposed 였다
ml_left <- list.files(file.path(AXD, "active/modes"), pattern = "^AX-.*\\.json$", recursive = TRUE)
chk("R1 active/modes 공리 파일 0 (mode-local 층 퇴역)", length(ml_left) == 0L, paste(ml_left, collapse = ","))
P_list <- tryCatch(P0$list_active_axioms(root = ROOT), error = function(e) list(e))
chk("R2 list_active_axioms() = 0", length(P_list) == 0L)
dep <- list.files(file.path(AXD, "deprecated"), pattern = "_rollback_\\d{8}\\.json$", full.names = TRUE)
dep_id <- sub("_rollback_\\d{8}\\.json$", "", basename(dep))
chk("R3 19건 전부 deprecated/*_rollback_* 존재", all(IDS %in% dep_id), paste(setdiff(IDS, dep_id), collapse = ","))
dj <- lapply(dep[dep_id %in% IDS], function(f) fromJSON(f, simplifyVector = FALSE))
chk("R4 rollback 사본 전부 status=rolled_back · 사유 · 역링크 무접촉 표기",
    all(vapply(dj, function(a) identical(a$status, "rolled_back") && nzchar(a$rollback_reason %||% "") &&
                 identical(a$rollback_backlinks_released, FALSE), logical(1))))
chk("R5 즉시 4건(당시 active)은 deactivated_reason 기록(deactivate_axiom 경유)",
    all(vapply(dj[vapply(dj, function(a) a$axiom_id %in% IMMEDIATE, logical(1))],
               function(a) nzchar(a$deactivated_reason %||% ""), logical(1))) &&
      sum(vapply(dj, function(a) a$axiom_id %in% IMMEDIATE, logical(1))) == length(IMMEDIATE))
tb <- fromJSON(file.path(AXD, "tombstones.json"), simplifyVector = FALSE)
tb_ids <- vapply(tb$entries, function(e) as.character(e$axiom_id), "")
chk("R6 tombstone 19건 · 전부 미해제 · 사유/부활조건 기재",
    all(IDS %in% tb_ids) && all(vapply(tb$entries[tb_ids %in% IDS], function(e)
      !isTRUE(e$cleared) && nzchar(e$reason %||% "") && nzchar(e$revive_condition %||% ""), logical(1))))
sot <- fromJSON(file.path(AXD, "axiom_sot_map.json"), simplifyVector = FALSE)
sot_ids <- vapply(sot$axioms, function(a) as.character(a$axiom_id), "")
chk("R7 sot_map 에서 19건 제거 · 전역 4건 존치", !any(IDS %in% sot_ids) && all(c("AX-000", "AX-001", "AX-002", "AX-008") %in% sot_ids))
# 근거 L-code(원장) 무접촉 — 롤백된 AX-RAMP-006 을 가리키는 역링크가 **그대로** 남아 있어야 한다(release_backlinks=FALSE)
bl <- Sys.glob(file.path(ROOT, "stage_artifacts/l_code/ramp/l_code_RAMP_SHUMULVEY_*_20260619.json"))
bl_keep <- vapply(bl, function(f) identical(fromJSON(f)$promoted_to_axiom, "AX-RAMP-006"), logical(1))
chk("R8 근거 L-code 역링크 무접촉(원장 불변) — Shu-Mulvey 4건 promoted_to_axiom=AX-RAMP-006 유지", sum(bl_keep) == 4L,
    as.character(sum(bl_keep)))
mega <- file.path(AXD, "candidates/CAND_paper_replication_96248eb76a9a.json")
mega_r <- file.path(AXD, "candidates/_retired_20260923/CAND_paper_replication_96248eb76a9a.json")
mj <- if (file.exists(mega_r)) fromJSON(mega_r, simplifyVector = FALSE) else list()
chk("R9 메가후보 퇴역 — 후보 큐에서 빠지고 _retired_20260923 에 사유와 보관(삭제 아님)",
    !file.exists(mega) && identical(mj$status, "retired") && nzchar(mj$retired_reason %||% "") &&
      length(mj$supporting_l_codes %||% list()) == 1172L)

#── H ────────────────────────────────────────────────────────────────────────
cat("\n[H] hypothesis_index 보충 스캔 가드 — 표식 원천을 재색인하지 않는다\n")
HI <- file.path(ROOT, "02_Infrastructure/tools/hypothesis_index.R")
.hi_build <- function(src, sb) {
  e <- new.env(parent = globalenv())
  suppressMessages(sys.source(src, envir = e))
  o <- file.path(sb, "hi_out.json")
  suppressMessages(capture.output(e$build_hypothesis_index(root = sb, out_path = o, verbose = FALSE)))
  paste(readLines(o, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
.mk_hi_sb <- function(tag) {
  sb <- file.path(SB0, tag); d <- file.path(sb, "stage_artifacts/l_code/ramp")
  dir.create(d, recursive = TRUE); dir.create(file.path(sb, ".cache"), recursive = TRUE)
  fx <- function(id, extra = list()) c(list(l_code = id, strategy_id = paste0("RAMP_", id), grade = "B",
                                           lesson_text = "픽스처 교훈", research_mode = "ramp",
                                           record_type = "performance"), extra)
  write_json(list(lcodes = list(c(fx("L-HI-OK"), list(source_file = "stage_artifacts/l_code/ramp/l_code_ok.json"))),
                  invalidated_lcodes = list(list(l_code = "L-HI-RETR", source_file = "stage_artifacts/l_code/ramp/l_code_retr.json",
                                                 reason = "pit_invalid"))),
             file.path(sb, ".cache/lcode_corpus.json"), auto_unbox = TRUE)
  Sys.setFileTime(file.path(sb, ".cache/lcode_corpus.json"), Sys.time() - 3600)
  write_json(fx("L-HI-OK"), file.path(d, "l_code_ok.json"), auto_unbox = TRUE)
  Sys.setFileTime(file.path(d, "l_code_ok.json"), Sys.time() - 7200)
  # 표식 원천이 수확 **뒤에** 다시 수정된 상황(mtime > corpus) — 보충 스캔 대상이 된다
  write_json(fx("L-HI-RETR", list(pit_invalid = TRUE, retracted_by = "L-FX-CORR")), file.path(d, "l_code_retr.json"),
             auto_unbox = TRUE)
  sb
}
hi_ok <- .hi_build(HI, .mk_hi_sb("hi_ok"))
chk("H1 표식 원천 재색인 없음(가드)", !grepl("L-HI-RETR", hi_ok, fixed = TRUE))
chk("H2 양성 대조: corpus 의 무표식 L-code 는 색인", grepl("L-HI-OK", hi_ok, fixed = TRUE))
hi_txt <- readLines(HI, warn = FALSE, encoding = "UTF-8")
hpat <- "    for (iv in (lc$invalidated_lcodes %||% list())) {"
if (sum(hi_txt == hpat) != 1L) ng("M-H 돌연변이 대상 줄 수 ≠ 1", as.character(sum(hi_txt == hpat))) else {
  mut_hi <- file.path(SB0, "hi_mut.R")
  writeLines(ifelse(hi_txt == hpat, "    for (iv in list()) {", hi_txt), mut_hi, useBytes = TRUE)
  hi_m <- .hi_build(mut_hi, .mk_hi_sb("hi_mut"))
  chk("M-H 가드 제거 사본 → 표식 L-code 재색인(검출 — H1 이 이 변화를 잡는다)", grepl("L-HI-RETR", hi_m, fixed = TRUE))
}

#── I ────────────────────────────────────────────────────────────────────────
cat("\n[I] 주입 훅 — 전역 Law 전문 렌더 · 예산 ≤2000 · 마커 생존\n")
HOOK <- file.path(ROOT, "02_Infrastructure/hooks/axiom_context_inject.sh")
.mk_hook_sb <- function(tag) {
  sb <- file.path(SB0, tag)
  dir.create(file.path(sb, "qepm/memory/axioms"), recursive = TRUE); dir.create(file.path(sb, ".cache"))
  dir.create(file.path(sb, "02_Infrastructure/hooks"), recursive = TRUE)
  file.copy(file.path(AXD, "active"), file.path(sb, "qepm/memory/axioms"), recursive = TRUE)
  file.copy(file.path(AXD, "tombstones.json"), file.path(sb, "qepm/memory/axioms/tombstones.json"))
  file.copy(file.path(ROOT, ".cache/positive_context.json"), file.path(sb, ".cache/positive_context.json"))
  file.copy(file.path(ROOT, "CLAUDE.md"), file.path(sb, "CLAUDE.md"))
  file.copy(file.path(ROOT, "02_Infrastructure/hooks/_shared_parse.sh"), file.path(sb, "02_Infrastructure/hooks/_shared_parse.sh"))
  sb
}
.render <- function(sb, hook) {
  Sys.setenv(CLAUDE_PROJECT_DIR = sb)
  on.exit(.env_restore(), add = TRUE)
  inp <- '{"tool_name":"Agent","tool_input":{"subagent_type":"judge","prompt":"WT-R20260923_001 강화"}}'
  out <- suppressWarnings(system2("bash", shQuote(hook), stdout = TRUE, stderr = FALSE, input = inp))
  ctx <- tryCatch(fromJSON(paste(out, collapse = ""))$hookSpecificOutput$additionalContext, error = function(e) NULL)
  il <- tryCatch(fromJSON(file.path(sb, ".cache/axiom_inject_last.json")), error = function(e) NULL)
  list(ctx = ctx %||% "", il = il)
}
sbh <- .mk_hook_sb("hook_ok")
hk <- file.path(sbh, "02_Infrastructure/hooks/axiom_context_inject.sh"); file.copy(HOOK, hk)
rr <- .render(sbh, hk)
ax <- lapply(c("AX-000", "AX-001", "AX-002", "AX-008"), function(i) fromJSON(file.path(AXD, "active", paste0(i, ".json"))))
full <- vapply(ax, function(a) paste(strsplit(as.character(a$statement %||% a$text), "\\s+")[[1]], collapse = " "), "")
chk("I1 전역 Law 4건 전문(꼬리까지) 렌더", all(vapply(full, function(s) grepl(s, rr$ctx, fixed = TRUE), logical(1))),
    paste(c("AX-000", "AX-001", "AX-002", "AX-008")[!vapply(full, function(s) grepl(s, rr$ctx, fixed = TRUE), logical(1))], collapse = ","))
chk("I2 예산 ≤2000자(최장 헤더 judge × 강화 라운드)", nchar(rr$ctx) > 0L && nchar(rr$ctx) <= 2000L, as.character(nchar(rr$ctx)))
chk("I3 마커 3종 생존(positive·recent·dead) — HARD_10 계약", isTRUE(rr$il$markers$positive) && isTRUE(rr$il$markers$recent) &&
      isTRUE(rr$il$markers$dead), paste(unlist(rr$il$markers), collapse = ","))
chk("I4 mode-local 렌더 0 (퇴역)", identical(as.integer(rr$il$ml_active_total), 0L) && !grepl("[mode-local 공리", rr$ctx, fixed = TRUE))
hk_txt <- readLines(HOOK, warn = FALSE, encoding = "UTF-8")
ipat <- "body_fixed = chr(10).join('  ' + ln.strip() for ln in body.splitlines() if ln.strip())"
if (sum(hk_txt == ipat) != 1L) ng("M-I 돌연변이 대상 줄 수 ≠ 1", as.character(sum(hk_txt == ipat))) else {
  sbm <- .mk_hook_sb("hook_mut")
  hkm <- file.path(sbm, "02_Infrastructure/hooks/axiom_context_inject.sh")
  writeLines(ifelse(hk_txt == ipat, "body_fixed = chr(10).join(('  ' + ln.strip())[:80] for ln in body.splitlines() if ln.strip())", hk_txt),
             hkm, useBytes = TRUE)
  rm_ <- .render(sbm, hkm)
  chk("M-I [:80] 절단 복원 사본 → AX-000 금지절 꼬리 소실(검출 — I1 이 이 변화를 잡는다)",
      nchar(rm_$ctx) > 0L && !grepl(full[1], rm_$ctx, fixed = TRUE))
}

#── D ────────────────────────────────────────────────────────────────────────
cat("\n[D] D5 문언 재정의 — 승인 필드 · 구판 history · 문서 SOT 일치\n")
a1 <- fromJSON(file.path(AXD, "active/AX-001.json"), simplifyVector = FALSE)
a8 <- fromJSON(file.path(AXD, "active/AX-008.json"), simplifyVector = FALSE)
for (a in list(a1, a8)) {
  id <- as.character(a$id %||% a$axiom_id)
  chk(sprintf("D %s 승인 필드(approved_by=dohoon · 2026-09-23 · AX-D5-TEXT)", id),
      identical(a$approved_by, "dohoon") && identical(a$approved_at, "2026-09-23") && grepl("AX-D5-TEXT", a$decision_ref %||% "", fixed = TRUE))
  chk(sprintf("D %s statement = text = canonical_statement", id),
      identical(a$statement, a$text) && identical(a$text, a$canonical_statement))
}
chk("D AX-001 v3 · 구판 v2 문언(bad/normal IC ratio)·v2.1 은 history 사료로 보존",
    identical(a1$version, "v3") && grepl("bad/normal IC ratio", a1$history[[1]]$text %||% "", fixed = TRUE) &&
      any(vapply(a1$history[[1]]$versions %||% list(), function(v) identical(v$version, "v2.1"), logical(1))))
# ★2026-09-23 수리(적대검증): 구 단정은 enforcement_mode == "block" 을 고정해, 판정서 K14 가 지적한 'block 오기'
#   (axioms.md Hook 강제 절 = documented · axiom_enforcement_hook.sh 등록 해제)를 고치면 이 검사가 red 가 되는 구조였다
#   — 오기를 계약으로 못박은 것. 이 축이 지키려던 의미는 'D5 문언 개정이 enforcement_hook 의미론
#   (test_ax001_defense_scope.R [6] 이 소비하는 applies_to_files·regex·require)을 건드리지 않았다' 이다.
#   mode 값은 enum 소속만 본다(오기 수정 여부 = 도훈 결정).
.d_hook_ok <- function(a) {
  eh <- a$enforcement_hook
  modes <- c("documented", "advisory", "block")
  is.list(eh) && length(unlist(eh$regex)) >= 1L && length(unlist(eh$require)) >= 1L &&
    length(unlist(eh$applies_to_files)) >= 1L &&
    isTRUE(as.character(a$enforcement_mode %||% "") %in% modes) &&
    isTRUE(as.character(eh$mode %||% a$enforcement_mode %||% "") %in% modes)
}
chk("D AX-001 enforcement_hook 의미론 필드 생존(applies_to_files·regex·require) · mode ∈ enum — 값은 고정 안 함", .d_hook_ok(a1))
a1_fix <- a1; a1_fix$enforcement_mode <- "documented"; a1_fix$enforcement_hook$mode <- "documented"
chk("D 양성 대조: 'block 오기'를 documented 로 고친 사본도 통과(오기를 계약으로 못박지 않는다)", .d_hook_ok(a1_fix))
a1_m <- a1; a1_m$enforcement_hook$regex <- NULL
chk("M-D1 regex 제거 사본 → 실패(검출)", !.d_hook_ok(a1_m))
a1_m <- a1; a1_m$enforcement_hook$require <- list()
chk("M-D2 require 비움 사본 → 실패(검출)", !.d_hook_ok(a1_m))
a1_m <- a1; a1_m$enforcement_mode <- "blokc"
chk("M-D3 enum 밖 mode 사본 → 실패(검출)", !.d_hook_ok(a1_m))
chk("D AX-008 v2.0 · 구판 3-source 2/3 문언은 history 사료로 보존",
    identical(a8$version, "v2.0") && grepl("2-source", a8$history[[1]]$statement %||% "", fixed = TRUE))
# (2026-09-23 적대검증 후속) 최상위 = v2.0 기준만 — 구판 v1.1 근거 필드는 history[0] 으로 이관(값 보존).
#   최상위에 L-159/167/168·v8.2 주석이 남으면 v2.0 문언의 근거로 오독되고, lcode_harvester._check_promoted 가
#   그 L-code 를 AX-008 승격분으로 표식한다(최상위 supporting_l_codes 를 읽는다).
.A8_LEGACY <- c("note_v8_2", "origin", "supporting_l_codes", "l_code", "evidence_audit_20260704")
.d_a8_top_ok <- function(a) {
  h <- a$history[[1]] %||% list()
  !any(.A8_LEGACY %in% names(a)) && all(.A8_LEGACY %in% names(h)) &&
    all(c("L-159", "L-167", "L-168") %in% unlist(h$supporting_l_codes))
}
chk("D AX-008 최상위 = v2.0 기준만 · 구판 근거 5필드는 history[0] 에 원값 보존(L-159/167/168)", .d_a8_top_ok(a8))
a8_m <- a8; a8_m$supporting_l_codes <- a8$history[[1]]$supporting_l_codes
chk("M-D4 최상위 supporting_l_codes 복원 사본 → 실패(검출)", !.d_a8_top_ok(a8_m))
a8_m <- a8; a8_m$history[[1]]$origin <- NULL
chk("M-D4b history[0] 원값 소실 사본 → 실패(검출)", !.d_a8_top_ok(a8_m))

# ── P 전파 가드: 에이전트·워크플로가 읽는 문서면에 구 문언이 남지 않는다 ──────────────────────────────
#   대상 = 주입면(에이전트 정의·스킬·워크플로 프롬프트·공용 prefix) + 계약 문서의 공리 절.
#   허용 = 같은 줄에 '사료' 또는 'history' 가 있는 포인터 줄(개정 이력 설명). 사료 폴더(_retired·archive)·worktrees 는 대상 아님.
.P_RE <- "Triangulation|3-source|2/3 PASS|crisis 조건부|conditional defense|AX-001 v2|v2\\.1 META"
.p_scan <- function(files, sections = list()) {
  hits <- character(0)
  for (f in files) {
    ln <- readLines(f, warn = FALSE, encoding = "UTF-8")
    rng <- sections[[f]]
    if (!is.null(rng)) {
      s <- grep(rng[1], ln, fixed = TRUE)[1]
      if (is.na(s)) { hits <- c(hits, paste0(basename(f), ": 절 머리 부재 ", rng[1])); next }
      e <- which(seq_along(ln) > s & grepl(rng[2], ln, fixed = TRUE))[1]
      ln <- ln[s:(if (is.na(e)) length(ln) else e)]
    }
    bad <- grepl(.P_RE, ln, perl = TRUE) & !grepl("사료|history", ln, perl = TRUE)
    if (any(bad)) hits <- c(hits, paste0(basename(f), ":", which(bad)))
  }
  hits
}
.P_FILES <- c(Sys.glob(file.path(ROOT, ".claude/agents/*.md")), Sys.glob(file.path(ROOT, ".claude/skills/*/SKILL.md")),
              Sys.glob(file.path(ROOT, ".claude/workflows/*.js")),
              file.path(ROOT, c("02_Infrastructure/prompts/_shared_prefix.md", "02_Infrastructure/worktask/artifact_contract.md",
                                "00_Lawbook/INDEX.md", "02_Infrastructure/worktask/common_charter.md")))
.P_SEC <- stats::setNames(list(c("## Axiom 준수", "---")), file.path(ROOT, "02_Infrastructure/worktask/common_charter.md"))
p_hits <- .p_scan(.P_FILES, .P_SEC)
chk(sprintf("P 주입면 %d 파일 — 구 AX-001 v2/AX-008 v1.1 문언 0 (사료 포인터 줄만 허용)", length(.P_FILES)),
    length(.P_FILES) >= 20L && !length(p_hits), paste(head(p_hits, 8), collapse = " ; "))
.p_sb <- file.path(SB0, "p_guard"); dir.create(.p_sb)
.p_src <- file.path(ROOT, ".claude/agents/alpha-research.md")
.p_mut <- file.path(.p_sb, "alpha-research.md")
writeLines(c(readLines(.p_src, warn = FALSE, encoding = "UTF-8"),
             "**AX-008 Verification Triangulation**: self-adversarial은 Forge·Architect와 함께 3-source 중 1개(2/3 PASS 필수)."),
           .p_mut, useBytes = TRUE)
chk("M-P 구 문언 재주입 사본 → 검출(가드가 살아 있다)", length(.p_scan(.p_mut)) == 1L)
.p_neg <- file.path(.p_sb, "pointer_only.md")
writeLines("- (2026-09-23 개정 — 구 AX-001 v2 · AX-008 v1.1 '3-source 2/3' 는 각 JSON history 사료)", .p_neg, useBytes = TRUE)
chk("P 음성 대조: 사료 포인터 줄은 위반으로 세지 않는다", length(.p_scan(.p_neg)) == 0L)
axmd <- paste(readLines(file.path(ROOT, ".claude/rules/axioms.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chk("D axioms.md(문서 SOT)에 AX-001·AX-008 새 문언이 그대로 실림",
    grepl(a1$statement, axmd, fixed = TRUE) && grepl(a8$statement, axmd, fixed = TRUE))
chk("D sot_map name = JSON name (AX-001·AX-008)",
    identical(sot$axioms[[which(sot_ids == "AX-001")]]$name, a1$name) && identical(sot$axioms[[which(sot_ids == "AX-008")]]$name, a8$name))

.env_restore()
cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"axiom_unattended_freeze","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
