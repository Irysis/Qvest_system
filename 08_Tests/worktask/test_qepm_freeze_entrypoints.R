# test_qepm_freeze_entrypoints.R — QEPM WT 체인 동결(도훈 결정 QEPM-R0-FREEZE · 2026-09-25) + 같은 날 문서 정정의 양방향 검사
#
# 근거: QEPM 계층 감사(wf_5a0aea67-884) Q01·Q15·Q16·Q07·Q09 + P3 '강화 매 시도 = QEPM' · 결정 QEPM-R0-FREEZE / QEPM-IMMEDIATE-FIXES.
#
#   A. dossier 워크플로(.claude/workflows/qvest-dossier-pipeline.js) — 합성 실행(node · agent/phase/log 모의):
#      실행 즉시 QEPM_FROZEN 반환·에이전트 스폰 0 · 상단 동결 블록을 걷어도 Judge 스폰 0(2차 가드) ·
#      둘 다 걷으면 forge 의 문자열 'A' 로 Judge 가 뜬다(= 감사 Q01 경로 재현 — 모의 하네스가 스폰을 본다는 양성 대조).
#   B. /worktask promote 경로(state_machine.R::sm_validated_advance) — 임시 루트에서 FORGE_DONE→JUDGE_PASSED/FAILED 가
#      waiver 무관 '동결' 로 거부 · 비-JUDGE 전이는 동결 문구 없이 기존 규칙대로 · 가드 줄 삭제 돌연변이 = FAIL 판정서로
#      JUDGE_PASSED 가 다시 열린다(감사 Q01 결함 재현 → red).
#   C. judge.md — 트리거 = 후보별 judge_request_<BID>_<n>.json(pending) ∧ grade_a_queue awaiting_judge(발행 코드와 대조) ·
#      emit_lcode 호출 인자를 lcode_emit.R 형식인자(parse)와 대조(Q16) · C11 도구 명시.
#   D. 동결 표지 + 해제 경로(재상정) 문구 · 결정 레지스터에 QEPM-R0-FREEZE 실재.
#   E. '강화 매 시도 = QEPM' 문언 소거 + 격자 수를 reinforce_program.json·원장 max_attempts 에서 재도출해 문서 수치와 대조.
#   F. Q07/Q09 문서 — C4 토큰을 pit.md C4 행에서 재도출해 대조 · C11 = fred_asof_join(실재 함수) · 폐지 상한(0.20)이
#      constraint_defaults weight_bounds([0,1])와 어긋나게 남아 있지 않음 · 동결 문서 표지.
#   M. 돌연변이(구 문언 재주입 사본) — 각 검사기가 red 를 내는지(검사기 양방향).
#
# 쓰기: tempdir() 아래만. 운영 파일은 읽기만 한다(원장·결정 레지스터·constraint_defaults 포함).
# 실행: Rscript 08_Tests/worktask/test_qepm_freeze_entrypoints.R   (node 없으면 A 절 SKIP — 사유 기록)

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(ROOT, "02_Infrastructure", "config.R")))
  ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QVEST_QF_ROOT", ROOT)   # 수리 전 트리 대조용(선택)
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

P <- 0L; F <- 0L; S <- 0L; SKIPS <- character(0)
ok   <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng   <- function(m, d = "") { d <- paste(as.character(d), collapse = " "); F <<- F + 1L
  cat(sprintf("  NG   %s%s\n", m, if (length(d) && nzchar(d)) paste0(" — ", d) else "")) }
chk  <- function(m, cond, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
skip <- function(m) { S <<- S + 1L; SKIPS <<- c(SKIPS, m); cat(sprintf("  SKIP %s\n", m)) }
rd   <- function(rel) paste(readLines(file.path(ROOT, rel), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
rl   <- function(rel) readLines(file.path(ROOT, rel), warn = FALSE, encoding = "UTF-8")
has  <- function(txt, s) grepl(s, txt, fixed = TRUE)
TMP  <- file.path(tempdir(), sprintf("qf_%d", Sys.getpid())); dir.create(TMP, recursive = TRUE, showWarnings = FALSE)

# ═════════════════════════════ A. dossier 워크플로 합성 실행 ═════════════════════════════
cat("=== A. dossier 워크플로 — 실행 시 동결 · Judge 스폰 0 ===\n")
DOS <- file.path(ROOT, ".claude/workflows/qvest-dossier-pipeline.js")
MT  <- file.path(ROOT, ".claude/workflows/qvest-multi-track.js")
node <- Sys.which("node"); if (!nzchar(node) && file.exists("C:/Program Files/nodejs/node.exe")) node <- "C:/Program Files/nodejs/node.exe"
HARN <- file.path(TMP, "wf_harness.mjs")
writeLines(c(
  "import { readFileSync } from 'node:fs'",
  "const scriptPath = process.argv[2]",
  "let src = readFileSync(scriptPath, 'utf8')",
  "src = src.replace(/^export\\s+const\\s+meta\\s*=/m, 'const meta = __box.meta =')",
  "const calls = [], logs = [], phases = []",
  "const agent = async (prompt, opts) => { const t = (opts && opts.agentType) || '?'; calls.push(t)",
  "  if (t === 'risk-research') return { recommended_estimator: 'LW', condition_number: 1, tail_tdc: 0.1, blocking: false, summary: 'r', escalations: [] }",
  "  if (t === 'optimizer-research') return { method_selected: 'EW', n_names: 25, turnover_yr: 3, net_sharpe: 1, constraints_ok: true, blocking: false, summary: 'o', infeasibility: [] }",
  "  if (t === 'forge') return { sharpe: 1, cagr: 0.2, mdd: 0.2, bt_audit_status: 'PASS', essence_grade: 'A', summary: 'f' }",
  "  if (t === 'judge') return { pit_pass: true, violations: [], summary: 'j' }",
  "  if (t === 'alpha-research') return { tag: 't1', icir: 1, dsr: 0.5, net_sr: 1, verdict: 'PASS' }",
  "  return {} }",
  "const phase = (p) => { phases.push(String(p)) }",
  "const log = (m) => { logs.push(String(m)) }",
  "const parallel = async (fns) => Promise.all(fns.map((f) => f()))",
  "const args = { wt_id: 'WT-R20990101_001', candidate_tag: 'QF', tracks: [{ tag: 't1', prompt: 'p' }] }",
  "const __box = {}",
  "const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor",
  "let result = null, error = null",
  "try { const fn = new AsyncFunction('args', 'agent', 'phase', 'log', 'parallel', '__box', src)",
  "      result = await fn(args, agent, phase, log, parallel, __box) } catch (e) { error = String(e && e.message || e) }",
  "process.stdout.write(JSON.stringify({ result, error, calls, logs, phases, meta_description: (__box.meta || {}).description || null }))"
), HARN)
run_wf <- function(js_file) {
  out <- tryCatch(suppressWarnings(system2(node, c(shQuote(HARN), shQuote(js_file)), stdout = TRUE, stderr = TRUE)),
                  error = function(e) paste("ERR", conditionMessage(e)))
  j <- tryCatch(fromJSON(paste(out, collapse = "\n"), simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(j)) list(ok = FALSE, raw = paste(out, collapse = " ")) else c(list(ok = TRUE), j)
}
node_check <- function(js_file) {
  rc <- suppressWarnings(system2(node, c("--check", shQuote(js_file)), stdout = FALSE, stderr = FALSE))
  identical(as.integer(rc), 0L)
}
mut_js <- function(lines, drop_top = TRUE, judge_open = FALSE) {
  if (drop_top) {
    i <- grep("^return \\{ wt_id: wt, candidate: tag, status: 'QEPM_FROZEN'", lines)
    if (length(i) != 1L || !grepl("^  note:", lines[i + 1L])) return(NULL)
    lines <- lines[-c(i, i + 1L)]
  }
  if (judge_open) {
    j <- grep("^const JUDGE_FROZEN = true$", lines)
    if (length(j) != 1L) return(NULL)
    lines[j] <- "const JUDGE_FROZEN = false"
  }
  lines
}
if (!nzchar(node) || !file.exists(node)) {
  skip("A node 실행기 없음 — 합성 실행 미측정(정적 검사만 D 절에서)")
} else {
  chk("A1 node --check dossier.js", node_check(DOS))
  chk("A1 node --check multi-track.js", node_check(MT))
  r0 <- run_wf(DOS)
  chk("A2 실행 = QEPM_FROZEN 반환(에러 없이)", r0$ok && is.null(r0$error) && identical(r0$result$status, "QEPM_FROZEN"),
      substr(paste(r0$error, r0$raw), 1, 160))
  chk("A2 에이전트 스폰 0(risk/optimizer/forge/judge 전부)", r0$ok && length(r0$calls) == 0L, paste(r0$calls, collapse = ","))
  chk("A2 로그에 'QEPM 동결(QEPM-R0-FREEZE)' · 해제 = 재상정", r0$ok && any(grepl("QEPM 동결(QEPM-R0-FREEZE)", r0$logs, fixed = TRUE)) &&
        any(grepl("재상정", r0$logs, fixed = TRUE)))
  chk("A2 meta.description 머리 = 동결 표지", r0$ok && isTRUE(grepl("^\\[동결 — QEPM-R0-FREEZE", r0$meta_description)))
  dl <- readLines(DOS, warn = FALSE, encoding = "UTF-8")
  m1 <- mut_js(dl, drop_top = TRUE)
  if (is.null(m1)) ng("A3 돌연변이 대상(상단 return 블록) 부재 — 검사 드리프트") else {
    f1 <- file.path(TMP, "dossier_m1.js"); writeLines(m1, f1, useBytes = TRUE)
    r1 <- run_wf(f1)
    chk("A3 상단 동결 블록 삭제 사본 — 체인은 돌지만 Judge 스폰 0(2차 가드 JUDGE_FROZEN)",
        r1$ok && is.null(r1$error) && "forge" %in% r1$calls && !("judge" %in% r1$calls),
        paste(r1$calls, collapse = ","))
    chk("A3 2차 가드 로그 = 'Judge 미스폰(WT 경로 봉쇄)'", r1$ok && any(grepl("Judge 미스폰", r1$logs, fixed = TRUE)))
  }
  m2 <- mut_js(dl, drop_top = TRUE, judge_open = TRUE)
  if (is.null(m2)) ng("A4 돌연변이 대상(JUDGE_FROZEN) 부재 — 검사 드리프트") else {
    f2 <- file.path(TMP, "dossier_m2.js"); writeLines(m2, f2, useBytes = TRUE)
    r2 <- run_wf(f2)
    chk("A4 두 가드 모두 제거 사본 → forge 문자열 'A' 로 Judge 스폰(감사 Q01 경로 재현 = 하네스가 스폰을 본다)",
        r2$ok && "judge" %in% r2$calls, paste(r2$calls, collapse = ","))
  }
  rm_ <- run_wf(MT)
  chk("A5 multi-track meta.description 머리 = 동결 표지", rm_$ok && isTRUE(grepl("^\\[동결 — QEPM-R0-FREEZE", rm_$meta_description)))
}

# ═════════════════════════════ B. /worktask promote — state_machine 동결 가드 ═════════════════════════════
cat("\n=== B. state_machine.R — JUDGE_* 전이 봉쇄 (임시 루트) ===\n")
SMR <- file.path(TMP, "smroot"); WT <- "WT-R20990101_001"
dir.create(file.path(SMR, "02_Infrastructure/worktask"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(SMR, "02_Infrastructure/hooks/policies"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(SMR, "qepm/mailbox/worktask", WT), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/hooks/policies/state_transitions.json"),
          file.path(SMR, "02_Infrastructure/hooks/policies/state_transitions.json"), overwrite = TRUE))
SM_REAL <- file.path(SMR, "02_Infrastructure/worktask/state_machine.R")
invisible(file.copy(file.path(ROOT, "02_Infrastructure/worktask/state_machine.R"), SM_REAL, overwrite = TRUE))
# FAIL 판정서 + waiver 없는 challenge note — 감사 Q01: 구판은 이것으로 JUDGE_PASSED 를 허용했다
writeLines('{"schema":"judge_verdict_v2","verdict":"FAIL","pit_pass":false,"strategy_id":"OTHER"}',
           file.path(SMR, "qepm/mailbox/worktask", WT, "judge_verdict.json"))
writeLines("# challenge note (waiver 없음)", file.path(SMR, "qepm/mailbox/worktask", WT, "challenge_note.md"))
run_sm <- function(sm_file, from, to, force = FALSE) {
  keys <- c("CLAUDE_PROJECT_DIR", "QM_ROOT"); old <- Sys.getenv(keys, unset = NA)
  Sys.setenv(CLAUDE_PROJECT_DIR = SMR, QM_ROOT = SMR)
  on.exit(for (k in keys) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k)), add = TRUE)
  env <- new.env(parent = globalenv())
  ld <- tryCatch({ invisible(capture.output(sys.source(sm_file, envir = env))); TRUE }, error = function(e) conditionMessage(e))
  if (!isTRUE(ld)) return(list(ok = FALSE, msg = paste("load:", ld)))
  if (!identical(normalizePath(env$PROJ_ROOT, winslash = "/"), normalizePath(SMR, winslash = "/")))
    return(list(ok = FALSE, msg = paste("root 이탈:", env$PROJ_ROOT)))
  tryCatch({ invisible(capture.output(env$sm_validated_advance(WT, from, to, force_waiver = force))); list(ok = TRUE, msg = "advance") },
           error = function(e) list(ok = FALSE, msg = conditionMessage(e)))
}
FRZ <- "QEPM 동결(QEPM-R0-FREEZE)"
frozen_all <- function(sm_file) {
  rs <- list(run_sm(sm_file, "FORGE_DONE", "JUDGE_PASSED"), run_sm(sm_file, "FORGE_DONE", "JUDGE_PASSED", force = TRUE),
             run_sm(sm_file, "FORGE_DONE", "JUDGE_FAILED"))
  all(vapply(rs, function(r) !r$ok && grepl(FRZ, r$msg, fixed = TRUE), logical(1)))
}
chk("B1 FORGE_DONE→JUDGE_PASSED / JUDGE_PASSED(force_waiver) / JUDGE_FAILED 전부 '동결' 거부", frozen_all(SM_REAL))
rC <- run_sm(SM_REAL, "FORGE_DONE", "COMPLETED")
chk("B2 음성 대조: FORGE_DONE→COMPLETED(grade<A 종결)는 가드에 안 걸린다", rC$ok, rC$msg)
rA <- run_sm(SM_REAL, "SPEC_APPROVED", "ALPHA_DONE")
chk("B2 음성 대조: 비-JUDGE 전이는 기존 규칙(산출물 부재)으로 막히고 동결 문구가 없다",
    !rA$ok && !grepl(FRZ, rA$msg, fixed = TRUE) && grepl("missing artifacts", rA$msg, fixed = TRUE), rA$msg)
chk("B3 가드 줄에 해제 경로(재상정) 명시", any(grepl("QEPM-R0-FREEZE", rl("02_Infrastructure/worktask/state_machine.R")) &
                                              grepl("재상정", rl("02_Infrastructure/worktask/state_machine.R"))))
smL <- readLines(SM_REAL, warn = FALSE, encoding = "UTF-8")
gi <- grep(FRZ, smL, fixed = TRUE); gi <- gi[grepl("stop(", smL[gi], fixed = TRUE)]
if (length(gi) != 1L) ng("B4 돌연변이 대상(가드 줄) 부재/중복 — 검사 드리프트", as.character(length(gi))) else {
  SM_MUT <- file.path(SMR, "02_Infrastructure/worktask/state_machine_mut.R"); writeLines(smL[-gi], SM_MUT, useBytes = TRUE)
  chk("B4 돌연변이(가드 줄 삭제) → 동결 검사가 red", !frozen_all(SM_MUT))
  rM <- run_sm(SM_MUT, "FORGE_DONE", "JUDGE_PASSED")
  chk("B4 돌연변이에서 FAIL 판정서(pit_pass=false·다른 전략)로 JUDGE_PASSED 가 열린다 — 감사 Q01 결함 재현", rM$ok, rM$msg)
}

# ═════════════════════════════ C. judge.md — 트리거(Q15) · emit_lcode 인자(Q16) · C11 도구 ═════════════════════════════
cat("\n=== C. judge.md ===\n")
JD <- rd(".claude/agents/judge.md")
spawn_sec <- function(txt) { m <- regmatches(txt, regexpr("(?s)## 스폰 조건[^\n]*\n(.*?)(?=\n## )", txt, perl = TRUE)); if (length(m)) m else "" }
chk_trigger <- function(txt) { s <- spawn_sec(txt)
  nzchar(s) && all(vapply(c("judge_request_<BID>_<n>.json", "status=pending", "grade_a_queue", "awaiting_judge", "트리거가 아니다", "QEPM-R0-FREEZE"),
                          function(k) has(s, k), logical(1))) }
chk("C1 스폰 조건 = 후보별 요청(pending) ∧ grade_a_queue awaiting_judge · 산출물 judge_request.json 은 트리거 아님", chk_trigger(JD))
chk("C1 'Grade A 확정 직후에만' 불변(test_judge_verdict_v2 계약)", has(JD, "Grade A 확정 직후에만"))
EMI <- rd("02_Infrastructure/ops/reinforce_auto_parallel.R")
chk("C2 문서 트리거 = 발행 코드와 일치(judge_request_%s_%d.json · status=\"pending\" · status=\"awaiting_judge\")",
    has(EMI, "judge_request_%s_%d.json") && grepl('status = "pending"', EMI, fixed = TRUE) && grepl('status = "awaiting_judge"', EMI, fixed = TRUE))
SKA <- grep("^현행: A → ", rl(".claude/skills/reinforce/SKILL.md"), value = TRUE)
chk("C2 reinforce SKILL A 분기(:71) = 관문 통과 시 후보별 요청 + awaiting_judge (Q15 문서분)",
    length(SKA) == 1L && has(SKA, "rf_a_eligibility") && has(SKA, "awaiting_judge") && !grepl("적재 + `judge_request.json` 발행", SKA, fixed = TRUE))
ex <- parse(file.path(ROOT, "02_Infrastructure/axiom/lcode_emit.R"), keep.source = FALSE)
fdef <- NULL
for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("emit_lcode"))) fdef <- e[[3]]
if (is.null(fdef)) ng("C3 lcode_emit.R 에서 emit_lcode 정의를 못 찾음") else {
  fm <- formals(eval(fdef, envir = baseenv())); FN <- names(fm)
  REQ <- setdiff(FN[vapply(fm, function(x) is.symbol(x) && !nzchar(as.character(x)), logical(1))], "...")
  call_args <- function(txt) { cs <- regmatches(txt, gregexpr("emit_lcode\\(([^)]*)\\)", txt, perl = TRUE))[[1]]
    lapply(cs, function(cl) { inner <- sub("^emit_lcode\\((.*)\\)$", "\\1", cl)
      gsub("\\s*=$", "", regmatches(inner, gregexpr("[A-Za-z_.][A-Za-z0-9_.]*\\s*=", inner, perl = TRUE))[[1]]) }) }
  chk_formals <- function(txt) { cl <- call_args(txt)
    length(cl) >= 1L && all(vapply(cl, function(a) length(a) > 0L && all(a %in% FN) && all(REQ %in% a), logical(1))) }
  cat(sprintf("       (emit_lcode 형식인자 %d개 · 필수 = %s)\n", length(FN), paste(REQ, collapse = ",")))
  chk("C3 judge.md 의 emit_lcode 호출 인자 ⊆ 형식인자 ∧ 필수 인자 전부(Q16)", chk_formals(JD))
  chk("M-C3 돌연변이(구 research_mode= 재주입) → red",
      !chk_formals(sub("emit_lcode\\(mode=\"judge_gate\"", "emit_lcode(research_mode=\"judge_gate\"", JD)))
}
FA <- rd("02_Infrastructure/data/fred_availability.R")
chk("C4 judge.md 도구에 C11 가용시점 층(fred_availability.R · fred_join_violations) 명시 + 함수 실재",
    has(JD, "02_Infrastructure/data/fred_availability.R") && has(JD, "fred_join_violations") &&
      grepl("\nfred_join_violations <- function", FA, fixed = TRUE))
chk("M-C1 돌연변이(구 트리거 문단 복원) → red",
    !chk_trigger(sub("(?s)## 스폰 조건[^\n]*\n(.*?)(?=\n## )",
                     "## 스폰 조건 (유일)\n- 러너/세션이 산출 디렉터리에 `judge_request.json` 을 남기고 Q-Lead 가 Agent 스폰.\n", JD, perl = TRUE)))

# ═════════════════════════════ D. 동결 표지 + 해제 경로 ═════════════════════════════
cat("\n=== D. 동결 표지 · 해제 경로 ===\n")
fm_desc <- function(rel) { l <- rl(rel); d <- grep("^description:", l, value = TRUE); if (length(d)) d[1] else "" }
chk("D1 qvest-worktask SKILL description 머리 = 동결 표지", grepl("^description: \"\\[동결 — QEPM-R0-FREEZE", fm_desc(".claude/skills/qvest-worktask/SKILL.md")))
chk("D1 /worktask 명령 description = 동결 표지", grepl("QEPM-R0-FREEZE", fm_desc(".claude/commands/worktask.md"), fixed = TRUE))
WK <- rd(".claude/commands/worktask.md"); SK <- rd(".claude/skills/qvest-worktask/SKILL.md")
chk("D2 /worktask promote 줄 = 봉쇄 표기 · 해제 = 재상정", grepl("promote \\{WT_id\\}` — ★\\*\\*봉쇄\\(QEPM-R0-FREEZE\\)", WK) && has(WK, "재상정"))
chk("D2 qvest-worktask 머리 표지 + 해제 = 재상정 + 살아 있는 부품 유지", has(SK, "동결(사료) — 도훈 결정 `QEPM-R0-FREEZE`") && has(SK, "재상정") && has(SK, "BOOK writer"))
chk("D3 CLAUDE.md·qvest.md /worktask 행 = 동결", grepl("\\| `/worktask` \\| QEPM WT 체인 — 동결", rd("CLAUDE.md")) &&
      grepl("\\| `/worktask` \\| QEPM WT 체인 — \\*\\*동결\\*\\*", rd(".claude/commands/qvest.md")))
DR <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/decision_register.json"), simplifyVector = FALSE), error = function(e) NULL)
fr <- if (is.null(DR)) NULL else Filter(function(x) identical(x$id, "QEPM-R0-FREEZE"), DR$items)
chk("D4 결정 레지스터에 QEPM-R0-FREEZE(resolved · 동결) 실재 — 표지가 가리키는 결정", length(fr) == 1L &&
      identical(fr[[1]]$status, "resolved") && grepl("동결", fr[[1]]$decision %||% "", fixed = TRUE))
fa2 <- if (is.null(DR)) NULL else Filter(function(x) identical(x$id, "QEPM-ADVISOR-MODE"), DR$items)
chk("D4 결정 레지스터에 QEPM-ADVISOR-MODE(resolved · 진입점 봉쇄 유지) 실재 — 에이전트 표지가 가리키는 결정", length(fa2) == 1L &&
      identical(fa2[[1]]$status, "resolved") && grepl("봉쇄는 유지", fa2[[1]]$decision %||% "", fixed = TRUE))

# ═════════════════════════════ E. '강화 매 시도 = QEPM' 문언 · 격자 재도출 ═════════════════════════════
cat("\n=== E. 강화 문언 · 격자 수 재도출 ===\n")
PROG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
NB <- length(PROG$blocks); PER <- unique(vapply(PROG$blocks, function(b) length(b$cells), integer(1))); TOT <- sum(vapply(PROG$blocks, function(b) length(b$cells), integer(1)))
LMAX <- tryCatch(as.integer(fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)$max_attempts), error = function(e) NA_integer_)
cat(sprintf("       (격자 재도출: %d블록 × %s칸 = %d · 원장 max_attempts = %s)\n", NB, paste(PER, collapse = "/"), TOT, LMAX))
chk("E0 원장 max_attempts = 격자 칸 수(문서의 '현행' 수치가 서는 전제)", length(PER) == 1L && identical(LMAX, TOT))
DOCS <- c(".claude/rules/lean-loop.md", "CLAUDE.md", ".claude/skills/reinforce/SKILL.md", ".claude/commands/qvest.md")
STALE_QEPM <- c("매 시도 = QEPM", "QEPM→등급", "(QEPM 기반)", "**QEPM 실행 (1계층)**", "QEPM(alpha→risk→optimizer→forge→등급)으로 강화",
                "QEPM 체인 수동 관리", "강화 시도는 QEPM 단위", "측정은 QEPM 체인")
STALE_GRID <- c("최대 30회", "최대 25회", "≤30회", "≤25회", "30칸(", "새 25칸", "25칸 소진", "25회 소진", "25회 게이트", "reinforce_auto_run.R` 이 강화를")
chk_qepm <- function(txt) !any(vapply(STALE_QEPM, function(s) has(txt, s), logical(1)))
chk_grid <- function(txt) {
  m <- regmatches(txt, gregexpr("([0-9]+)블록\\s*[×x]\\s*([0-9]+)(=([0-9]+))?", txt, perl = TRUE))[[1]]
  okm <- all(vapply(m, function(s) { n <- as.integer(regmatches(s, gregexpr("[0-9]+", s, perl = TRUE))[[1]])
    n[1] == NB && n[2] == PER[1] && (length(n) < 3L || n[3] == TOT) }, logical(1)))
  okm && !any(vapply(STALE_GRID, function(s) has(txt, s), logical(1)))
}
for (d in DOCS) {
  tx <- rd(d)
  chk(sprintf("E1 %s — '매 시도 = QEPM' 계열 문언 0", d), chk_qepm(tx),
      paste(STALE_QEPM[vapply(STALE_QEPM, function(s) has(tx, s), logical(1))], collapse = " | "))
  chk(sprintf("E2 %s — 격자 수치 = 재도출값(%d블록×%d=%d)·낡은 상한 문언 0", d, NB, PER[1], TOT), chk_grid(tx),
      paste(c(regmatches(tx, gregexpr("[0-9]+블록\\s*[×x]\\s*[0-9]+", tx, perl = TRUE))[[1]],
              STALE_GRID[vapply(STALE_GRID, function(s) has(tx, s), logical(1))]), collapse = " | "))
}
LL <- rd(".claude/rules/lean-loop.md"); SKR <- rd(".claude/skills/reinforce/SKILL.md"); CM <- rd("CLAUDE.md")
chk("E3 lean-loop 미달 분기 = 셀 엔진 + run_paper_replication", has(LL, "rf_cell_engine.R") && has(LL, "run_paper_replication") && has(LL, "QEPM-R0-FREEZE"))
st4 <- regmatches(SKR, regexpr("(?s)\n4\\. \\*\\*실행 \\(1계층\\)\\*\\*.*?\n\n", SKR, perl = TRUE))
chk("E3 reinforce SKILL 시도 절차 4 = §0 과 같은 실행(셀 엔진 + run_paper_replication · WT 미사용) + 구 경로 동결",
    length(st4) == 1L && has(st4, "rf_cell_engine.R") && has(st4, "run_paper_replication") && has(st4, "WT 미사용") && has(st4, "QEPM-R0-FREEZE"))
chk("E3 SKILL §0 실행 줄(:112-113 정본)과 절차 4 가 같은 계약을 말한다",
    has(SKR, "`run_paper_replication(portfolio_spec=실투형)`") && length(st4) == 1L && has(st4, "`run_paper_replication(portfolio_spec=실투형)`"))
chk("E3 CLAUDE.md 파이프라인 = 셀 엔진+run_paper_replication · §0.3/LLM설계 불변(test_rf_skill_reflects_runtime 계약)",
    has(CM, "셀 엔진+run_paper_replication") && has(CM, "§0.3") && has(CM, "LLM설계"))
blk_rows <- vapply(PROG$blocks, function(b) grepl(sprintf("\n| %s (", b$id), SKR, fixed = TRUE), logical(1))
chk(sprintf("E4 SKILL 구조표에 격자 블록 %d종 전부 행이 있다", NB), all(blk_rows), paste(vapply(PROG$blocks, `[[`, "", "id")[!blk_rows], collapse = ","))
chk("M-E1 돌연변이(lean-loop 에 '매 시도 = QEPM(…)' 재주입) → red", !chk_qepm(paste(LL, "매 시도 = QEPM(alpha→risk→optimizer→forge→등급) + L-code.")))
chk("M-E2 돌연변이(CLAUDE.md 에 '격자 6블록×5' 재주입) → red", !chk_grid(paste(CM, "L1 ≤30회(원장 l1 · 격자 6블록×5)")))

# ═════════════════════════════ F. Q07/Q09 — C4·C11·폐지 상한 ═════════════════════════════
cat("\n=== F. C4·C11·비중 상한 문서 ===\n")
pitL <- rl(".claude/rules/pit.md"); c4row <- grep("^\\| C4 \\|", pitL, value = TRUE)
C4TOK <- c(regmatches(c4row, regexpr("익년 [0-9]+/[0-9]+", c4row, perl = TRUE)), regmatches(c4row, regexpr("[0-9]+일\\+", c4row, perl = TRUE)),
           regmatches(c4row, regexpr("[0-9]+/15·[0-9]+/15·[0-9]+/15", c4row, perl = TRUE)))
cat(sprintf("       (pit.md C4 재도출 토큰: %s)\n", paste(C4TOK, collapse = " | ")))
chk("F0 pit.md C4 행에서 토큰 3종 재도출", length(C4TOK) == 3L)
line_of <- function(rel, pat) { l <- rl(rel); l[grepl(pat, l, perl = TRUE)] }
c4_ok <- function(lines) length(lines) >= 1L && all(vapply(lines, function(x) all(vapply(C4TOK, function(k) has(x, k), logical(1))), logical(1)))
SPX <- "02_Infrastructure/prompts/_shared_prefix.md"; ARI <- "02_Infrastructure/prompts/alpha_research_init.md"
ORI <- "02_Infrastructure/prompts/optimizer_research_init.md"; CCH <- "02_Infrastructure/worktask/common_charter.md"
chk("F1 _shared_prefix C4 줄 = pit.md 토큰 · 구 '연간→5월' 없음", c4_ok(line_of(SPX, "^- C4:")) && !has(rd(SPX), "연간→5월"))
chk("F1 alpha_research_init data_lag_rules 줄 = 구판 값 무효 + C4 토큰", c4_ok(line_of(ARI, "data_lag_rules / hard_constraints 파악")) && has(paste(line_of(ARI, "data_lag_rules / hard_constraints 파악"), collapse = ""), "무효"))
chk("F1 common_charter 재무제표 가용일 줄 = C4 토큰", c4_ok(line_of(CCH, "^- 재무제표 가용일:")))
fa_ok <- grepl("\nfred_asof_join <- function", FA, fixed = TRUE)
c11_ok <- function(lines) fa_ok && length(lines) >= 1L && all(vapply(lines, function(x) has(x, "fred_asof_join"), logical(1)))
chk("F2 _shared_prefix C11 = fred_asof_join(실재 함수) 경유", c11_ok(line_of(SPX, "C11:")))
chk("F2 alpha_research_init 의 FRED 매크로 줄 전부 fred_asof_join 경유 · macro_fred 직접 결합 금지 명시",
    c11_ok(line_of(ARI, "FRED 매크로")) && has(paste(line_of(ARI, "macro_fred\\.parquet"), collapse = ""), "직접 결합 금지"))
chk("F2 common_charter 외부 매크로 = 가용시점 층 · 구 '최소 t-1 lag' 없음", c11_ok(line_of(CCH, "외부 매크로")) && !has(rd(CCH), "최소 **t-1 lag**"))
CD <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = TRUE)
WB <- as.numeric(CD$tier_soft_deployment$weight_bounds)
chk("F3 정본 코드값 재도출: constraint_defaults weight_bounds = [0, 1] (상한 폐지)", identical(WB, c(0, 1)))
CAP_STALE <- list(ORI = c("bounds = c(0, 0.20)", "any(weights > 0.20) (Hook block)"),
                  OR  = c("max_w>0.20, Σw≠1", "(max_names/max_w/Σw/turnover)"),
                  CCH = c("| Weight bounds | [0, 0.20]", "weight [0, 0.20]"))
cap_ok <- function(txt, pats) !any(vapply(pats, function(p) has(txt, p), logical(1)))
chk("F3 optimizer_research_init — 0.20 상한 강제 문언 0", cap_ok(rd(ORI), CAP_STALE$ORI))
chk("F3 optimizer-research.md — max_w>0.20 ACCEPT 의무 0", cap_ok(rd(".claude/agents/optimizer-research.md"), CAP_STALE$OR))
chk("F3 common_charter — [0, 0.20] 0 · Weight bounds 행 = [0, 1.0]", cap_ok(rd(CCH), CAP_STALE$CCH) && has(rd(CCH), "| Weight bounds | [0, 1.0]"))
## 표지 = QEPM-ADVISOR-MODE(09-25 09:23 — R0-FREEZE 보완: 에이전트 문서의 '사료' 표지를 '어드바이저 모드'로 대체, 진입점 봉쇄 유지)
adv_ok <- function(txt) has(txt, "★**어드바이저 모드**") && has(txt, "QEPM-ADVISOR-MODE") && has(txt, "QEPM-R0-FREEZE") &&
  has(txt, "rf_a_eligibility") && !has(txt, "사료 — QEPM-R0-FREEZE")
for (d in c(ARI, ORI, CCH, ".claude/agents/alpha-research.md", ".claude/agents/optimizer-research.md"))
  chk(sprintf("F4 어드바이저 모드 표지(자문만 · 측정 = 정본 계약 · A = rf_a_eligibility) — %s", basename(d)), adv_ok(rd(d)))
FG <- rd(".claude/agents/forge.md")
chk("F4 forge.md = 동결 표지(자문 역할 밖 · 등급을 내지 않는다)", has(FG, "★**동결 — QEPM-R0-FREEZE**") && has(FG, "등급을 내지 않는다"))
chk("M-F4 돌연변이(구 '사료' 표지 사본) → red", !adv_ok("> ★**사료 — QEPM-R0-FREEZE**(도훈 2026-09-25): QEPM WT 체인 동결"))
chk("F4 forge.md 모범 경로(_017, 부재) = 사료·따르지 말 것 표기", has(rd(".claude/agents/forge.md"), "Reference 구현**(★사료 — 따르지 말 것)"))
chk("M-F1 돌연변이(구 C4 '연간→5월' 줄) → red", !c4_ok("- C4: 재무제표 lag (연간→5월, 분기→45일)"))
chk("M-F2 돌연변이(구 C11 '데이터 시간축 검증' 줄) → red", !c11_ok("- C5: overlay t-1, C9: VT/DD lag, C11: 데이터 시간축 검증"))
chk("M-F3 돌연변이(charter 에 [0, 0.20] 재주입) → red", !cap_ok(paste(rd(CCH), "| Weight bounds | [0, 0.20] | same |"), CAP_STALE$CCH))

unlink(TMP, recursive = TRUE)
cat(sprintf("\n== test_qepm_freeze_entrypoints: %d pass · %d fail · %d skip ==\n", P, F, S))
cat(toJSON(list(test = "qepm_freeze_entrypoints", pass = P, fail = F, total = P + F, skipped = S, skips = as.list(SKIPS)), auto_unbox = TRUE), "\n", sep = "")
if (F > 0L) quit(status = 1L)
