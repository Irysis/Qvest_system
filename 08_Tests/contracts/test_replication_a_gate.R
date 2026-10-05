# test_replication_a_gate.R — P0-13(2026-09-25) 충실구현 Grade A 자격 관문 경유 양방향 검사
#
# 대상: 02_Infrastructure/alpha_search/run_paper_replication.R §11 + 정의 8종(.RP_JR_LEGACY·.RP_JR_ELIGIBLE·.RP_JR_HELD·
#       .rp_is_cell_run·.rp_gate_env·.rp_a_gate_inputs·.rp_gate_err_verdict·.rp_a_route) · 관문 정본 rf_runner_gates.R::rf_a_eligibility ·
#       설정 06_Registry/a_eligibility_gate.json(holds.accounting_fail.replication_required_selection_type)
# 사고: 구판 §11 은 grade A 면 관문 없이 산출 디렉터리에 judge_request.json 을 썼다(강화 셀은 강화 러너가 뒤에서 관문을 탔지만 충실구현
#   — 단독·무인 충실구현 레인·결합·어드바이저 — 에는 관문이 없었다). 문서 6곳이 "B07 뒤 이관 예정" 이라 적었으나 소유 항목이 없었다.
#
#   A. 합성 A 산출물(authoritative_remeasure.json + bt_result.rds) → 라우터가 **정본 관문**을 태운다:
#      정상 → judge_request.eligible.json(judge_request_v2 · pending · a_eligibility) · 보류 3종(legacy regime · 창 이탈 · 회계 실패)
#      → judge_request.held.json(held:<코드> · 사유) + 발행 없음 · 설정 키 부재 → gate_config · 관문 정본 부재 → gate_error(fail-closed) ·
#      판정 = 정본 술어 직접 호출과 같다(사본 없음) · 권위 산출물 바이트 불변(등급 불변)
#   B. §11 실블록(러너 함수 본문에서 parse 로 떼어 eval) — 무인 충실구현 레인 모양(QVEST_NO_LEDGER_OPEN=1 · RF_CELL_SPEC 없음 · 논문 엔진)은
#      관문을 탄다 · 강화 셀(스위치 ∧ RF_CELL_SPEC ∧ rf_cell_engine.R)은 **구판 그대로**(judge_request.json · 구판 블록 출력과 바이트 대조 ·
#      관문 정본이 없는 루트에서도 같은 출력 = 관문을 부르지 않는다) · 셀 판별 진리표 · 셀 엔진이 셀 러너 밖(스위치 없음 — 수동 셀
#      재실행·Judge 재현 모양)이면 held:cell_outside_runner(적대 검증 2026-09-25 — 수리 전에는 chain/1 로 발행됐다)
#   C. 설정 키 이름 — rf_a_gate_config 의 `$required_selection_type` 부분 일치가 충실구현 키를 집지 않는다(강화 요건 sweep 불변) ·
#      키를 required_selection_type… 로 지으면 부분 일치가 강화 요건을 chain 으로 바꾼다(양성 대조)
#   M. 돌연변이(러너 소스 사본 — 메모리 안) — 관문 우회(셀 분기 무조건) · 판정 무시 · 셀 판별 약화(스위치 하나) · 적재 실패 fail-open ·
#      §11 구판 복원 · 회계 요건을 강화 키로 · 셀 러너 밖 셀 엔진 보류 제거 · 비논리 판정(NA) fail-open — 각각 A/B 배터리가 red
#
# 쓰기: tempdir() 샌드박스만(운영 트리 무접촉 — 루트는 읽기 전용 복사 원천). 환경변수는 끝에 복원한다.
# 수리 전 러너(정의 8종 부재)에서는 L0 이 red 로 멈춘다(수리 전 red 실증).
# 실행: Rscript 08_Tests/contracts/test_replication_a_gate.R   (샌드박스 루트에서 — QM_ROOT/CLAUDE_PROJECT_DIR = 그 루트)

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(ROOT, "02_Infrastructure", "config.R")))
  ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

P <- 0L; F <- 0L; S_ <- 0L; SKIPS <- character(0)
ok   <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng   <- function(m, d = "") { d <- paste(as.character(d), collapse = " "); F <<- F + 1L
  cat(sprintf("  NG   %s%s\n", m, if (length(d) && nzchar(d)) paste0(" — ", d) else "")) }
chk  <- function(m, cond, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
emit <- function() {
  cat(sprintf("\n== test_replication_a_gate: %d pass · %d fail · %d skip ==\n", P, F, S_))
  cat(toJSON(list(test = "replication_a_gate", pass = P, fail = F, total = P + F, skipped = S_, skips = as.list(SKIPS)),
             auto_unbox = TRUE), "\n", sep = "")
}

# ── 환경 격리 — 이 검사가 만지는 환경변수는 끝에 복원한다 ──────────────────────────────────────────────
ENV_KEYS <- c("QM_ROOT", "QVEST_CONSTRAINT_DEFAULTS", "QVEST_NO_LEDGER_OPEN", "RF_CELL_SPEC")
ENV0 <- Sys.getenv(ENV_KEYS, unset = NA_character_, names = TRUE)
env_restore <- function() for (k in ENV_KEYS) if (is.na(ENV0[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(ENV0[[k]]), k))
set_mode <- function(nlo = NA, spec = NA) {
  if (is.na(nlo)) Sys.unsetenv("QVEST_NO_LEDGER_OPEN") else Sys.setenv(QVEST_NO_LEDGER_OPEN = nlo)
  if (is.na(spec)) Sys.unsetenv("RF_CELL_SPEC") else Sys.setenv(RF_CELL_SPEC = spec)
}
Sys.unsetenv("QVEST_CONSTRAINT_DEFAULTS")   # 현행 규약 = 샌드박스 constraint_defaults.json 에서만(명시 레버가 새지 않게)
set_mode()

# ── 0. 샌드박스 (tempdir 만 쓴다) ─────────────────────────────────────────────────────────────────────
S <- file.path(tempdir(), sprintf("rp_agate_%d", Sys.getpid()))
unlink(S, recursive = TRUE); dir.create(S, recursive = TRUE, showWarnings = FALSE)
cat(sprintf("ROOT(읽기) = %s\nSANDBOX(쓰기) = %s\n", ROOT, S))
inside <- function(p, q) startsWith(tolower(normalizePath(p, winslash = "/", mustWork = FALSE)),
                                    tolower(paste0(normalizePath(q, winslash = "/", mustWork = FALSE), "/")))
if (inside(S, ROOT)) { ng("샌드박스가 루트 안에 있다 — 운영 쓰기 위험(중단)", S); emit(); env_restore(); quit(status = 1L) }
NEED <- c("02_Infrastructure/reinforcement/rf_runner_gates.R", "02_Infrastructure/reinforcement/rf_spec_sig.R",
          "02_Infrastructure/reinforcement/rf_block_design.R", "02_Infrastructure/reinforcement/reinforce_ledger.R",
          "02_Infrastructure/contracts/essence_score.R", "02_Infrastructure/worktask/constraint_defaults.json",
          "06_Registry/a_eligibility_gate.json",
          # ★P0-14(2026-09-25): 관문 정본이 계보 표식 술어(rf_lineage_flags.R)를 적재한다 — 없으면 .rp_gate_env 가 적재 실패(gate_error)
          "02_Infrastructure/reinforcement/rf_lineage_flags.R",
          # ★B4-SIX-AXIS(2026-09-26): 관문 정본이 축 등록부(rf_spec_axes.R)를 적재한다 — 같은 이유(최소 루트에 없으면 적재 실패)
          "02_Infrastructure/reinforcement/rf_spec_axes.R")
# ★관문 정본이 source 하는 파일 = 관문 소스에서 재도출(10-03 최종 통합 러너 경로 · INTEG-TF) — HUMAN(rf_lane_rules.R)처럼 갈래가 관문 의존을
#   늘리면 최소 루트 리터럴이 낡아 .rp_gate_env 가 '적재 실패'로 죽는다(합본 차등 회귀 실측). 관문이 부르는 그대로 따라간다(판정 불변).
NEED <- unique(c(NEED, tryCatch({
  .g <- readLines(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R"), warn = FALSE, encoding = "UTF-8")
  unlist(regmatches(.g, gregexpr('(?<=source\\(file\\.path\\(\\.RFG_ROOT\\(\\), ")02_Infrastructure/[A-Za-z0-9_/]+[.]R', .g, perl = TRUE)))
}, error = function(e) character(0))))
mk_root <- function(dst, drop = character(0)) {
  for (r in setdiff(NEED, drop)) {
    dir.create(dirname(file.path(dst, r)), recursive = TRUE, showWarnings = FALSE)
    if (!isTRUE(file.copy(file.path(ROOT, r), file.path(dst, r), overwrite = TRUE))) return(FALSE)
  }
  TRUE
}
if (!mk_root(S)) { ng("샌드박스 사본 실패(원천 파일 부재)", paste(NEED[!file.exists(file.path(ROOT, NEED))], collapse = ",")); emit(); env_restore(); quit(status = 1L) }

# ── L0. 러너에서 P0-13 정의·§11 블록을 parse 로 떼어 낸다 ─────────────────────────────────────────────
cat("=== L0. 러너 정의 적재(parse → eval · 러너 전체 source 없음) ===\n")
RP_F <- file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")
RP_TXT <- paste(readLines(RP_F, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
WANT <- c(".RP_JR_LEGACY", ".RP_JR_ELIGIBLE", ".RP_JR_HELD", ".rp_is_cell_run", ".rp_gate_env", ".rp_a_gate_inputs",
          ".rp_gate_err_verdict", ".rp_a_route")
find_a11 <- function(ex) {
  fdef <- NULL
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("run_paper_replication"))) fdef <- e[[3]]
  if (is.null(fdef)) return(NULL)
  walk <- function(x) {
    if (!is.call(x)) return(NULL)
    if (identical(x[[1]], as.name("if")) && identical(deparse(x[[2]]), 'identical(grade, "A")')) return(x)
    for (i in seq_along(x)) { if (is.symbol(x[[i]]) && !nzchar(as.character(x[[i]]))) next
      r <- walk(x[[i]]); if (!is.null(r)) return(r) }
    NULL
  }
  walk(fdef[[3]])
}
load_defs <- function(txt) {
  ex <- tryCatch(parse(text = txt, keep.source = FALSE, encoding = "UTF-8"), error = function(e) NULL)
  if (is.null(ex)) return(list(env = NULL, missing = WANT, a11 = NULL, why = "parse 실패"))
  env <- new.env(parent = globalenv())
  for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) && as.character(e[[2]]) %in% WANT)
    eval(e, envir = env)
  list(env = env, missing = setdiff(WANT, ls(env, all.names = TRUE)), a11 = find_a11(ex), why = "")
}
RP <- load_defs(RP_TXT)
chk(sprintf("L0 러너 정의 %d종 실재(P0-13)", length(WANT)), !length(RP$missing), paste(RP$missing, collapse = ","))
chk("L0 러너 함수 본문의 §11 A 분기(if (identical(grade, \"A\")) …) 추출", !is.null(RP$a11))
if (length(RP$missing) || is.null(RP$a11)) {
  cat("  (수리 전 러너 — 관문 경유 정의가 없다 · 이하 생략)\n"); emit(); env_restore(); unlink(S, recursive = TRUE); quit(status = 1L)
}
GX0 <- RP$env$.rp_gate_env(S)
chk("L0 관문 정본 격리 적재(.rp_gate_env) — rf_a_eligibility 실재 · 전역 오염 없음",
    is.environment(GX0$env) && is.function(GX0$env$rf_a_eligibility) && !exists("rf_a_eligibility", envir = globalenv(), inherits = FALSE),
    GX0$err)
GX <- GX0$env
CFG <- fromJSON(file.path(S, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = TRUE)
CUR <- GX$rf_current_regime(S)$regime
LEG <- setdiff(as.character(CFG[["execution"]][["exec_price_allowed"]]), CUR)[1]
ANCHOR <- as.Date(CFG[["diagnostics"]][["window_anchor_date"]]); ALLOW <- as.numeric(CFG[["diagnostics"]][["window_allowance_months"]])
REQ_REPL <- fromJSON(file.path(S, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE)$holds$accounting_fail[["replication_required_selection_type"]]
cat(sprintf("       (설정 재도출: 현행 규약=%s · 다른 규약=%s · 창 기준=%s · 허용=%s개월 · 충실구현 회계 요건=%s)\n",
            CUR, LEG, ANCHOR, ALLOW, as.character(REQ_REPL %||% "(부재)")))
chk("L0 설정 재도출 가능(현행 규약·다른 규약·창 기준·허용·충실구현 회계 요건)",
    is.character(CUR) && !is.na(CUR) && !is.na(LEG) && !is.na(ANCHOR) && is.finite(ALLOW) && is.character(REQ_REPL) && nzchar(REQ_REPL))

# ── 합성 산출물 — authoritative_remeasure.json(권위 모양) + bt_result.rds(창 재도출 재료) ────────────────
PAPER_ENGINE <- file.path(S, "paper_engine", "engine.R")
CELL_ENGINE  <- file.path(S, "02_Infrastructure/reinforcement/rf_cell_engine.R")
dir.create(dirname(PAPER_ENGINE), recursive = TRUE, showWarnings = FALSE); writeLines("FACTORS <- NULL", PAPER_ENGINE)
writeLines("# stub", CELL_ENGINE)
CELL_SPEC <- file.path(S, "cell_spec.json"); writeLines('{"code":"B1_1"}', CELL_SPEC)
mk_art <- function(base, tag, exec = CUR, sel = REQ_REPL, nt = 1L, dsr = NULL, start = ANCHOR, mr = TRUE) {
  d <- file.path(base, "stage_artifacts", "replication", tag); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  au <- list(status = "OK", strategy_id = paste0("RP_T_", tag), essence_grade = "A", metric_type = "backtested",
             selection_type = sel, n_trials_cumulative = nt, dsr = dsr, essence = list(dsr = dsr, cagr = 0.2, calmar = 0.9),
             measurement_regime = if (isTRUE(mr)) list(selection_type = sel, n_trials_cumulative = nt, exec_price = exec,
                                                        exec_price_basis = "argument", cost_model_version = "synthetic") else NULL)
  if (!isTRUE(mr)) au$measurement_regime <- NULL
  write(toJSON(au, auto_unbox = TRUE, null = "null", pretty = TRUE), file.path(d, "authoritative_remeasure.json"))
  dates <- seq(as.Date(start), by = "month", length.out = 24L)
  saveRDS(list(holdings = data.table(date = dates, ticker = "A000001", weight = 1),
               period_returns = data.table(date = dates, ret_net = rep(0.01, 24L))), file.path(d, "bt_result.rds"))
  d
}
sha_of <- function(p) if (file.exists(p)) unname(as.character(tools::md5sum(p))) else NA_character_
jr <- function(d, nm) { p <- file.path(d, nm); if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL }
files_of <- function(d) sort(list.files(d, pattern = "^judge_request"))
route <- function(R, d, root, engine = PAPER_ENGINE, cell = NULL, gx = NULL, gate_err = "") {
  if (is.null(cell)) cell <- R$.rp_is_cell_run(engine)
  gxl <- if (!is.null(gx)) gx else if (isTRUE(cell)) list(env = NULL, err = "") else R$.rp_gate_env(root)
  R$.rp_a_route(d, grade = "A", strategy_id = basename(d), engine_path = engine, cell = cell,
                gate = if (is.environment(gxl$env)) gxl$env$rf_a_eligibility else NULL, gx = gxl$env, root = root,
                gate_err = if (nzchar(gate_err)) gate_err else gxl$err)
}
run_a11 <- function(R, a11, d, engine, root) {
  E <- new.env(parent = R); E$grade <- "A"; E$OUT_DIR <- d; E$strategy_id <- basename(d)
  E$factor_engine_path <- engine; E$PROJECT_ROOT <- root; E$a_gate <- NULL
  invisible(capture.output(eval(a11, envir = E)))
  E$a_gate
}
held_has <- function(d, code) { j <- jr(d, RP$env$.RP_JR_HELD)
  !is.null(j) && startsWith(as.character(j$status %||% ""), "held:") && code %in% unlist(j$a_eligibility$codes) &&
    code %in% unlist(j$held$codes) && !isTRUE(j$a_eligibility$eligible) && nzchar(as.character(j$a_eligibility$detail[[code]] %||% "")) }
only_file <- function(d, nm) identical(files_of(d), nm)

# ── 배터리 — 같은 판정을 실코드·돌연변이에 똑같이 태운다(이름 붙은 논리 벡터) ────────────────────────────
S_NOKEY <- file.path(tempdir(), sprintf("rp_agate_nokey_%d", Sys.getpid())); S_NOGATE <- file.path(tempdir(), sprintf("rp_agate_nogate_%d", Sys.getpid()))
invisible(mk_root(S_NOKEY)); invisible(mk_root(S_NOGATE, drop = "02_Infrastructure/reinforcement/rf_runner_gates.R"))
g <- fromJSON(file.path(S_NOKEY, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE)
g$holds$accounting_fail[["replication_required_selection_type"]] <- NULL
writeLines(toJSON(g, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(S_NOKEY, "06_Registry/a_eligibility_gate.json"))
OLD_A11_TXT <- paste0("if (identical(grade, \"A\")) {\n",
  "    write_json(list(strategy_id = strategy_id, layer = 1L, grade = grade,\n",
  "                    artifacts = OUT_DIR, engine_path = factor_engine_path,\n",
  "                    requested_at = format(Sys.time(), \"%Y-%m-%dT%H:%M:%S%z\"),\n",
  "                    note = \"v10: Grade A → Judge(PIT 전담) 스폰 요청 — 세션(Q-Lead)이 Agent 스폰\"),\n",
  "               file.path(OUT_DIR, \"judge_request.json\"), auto_unbox = TRUE, pretty = TRUE)\n",
  "    cat(\"[replication] ★Grade A — judge_request.json 발행 (Judge 스폰은 세션 소관)\\n\")\n",
  "  }")                         # P0-13 직전 판 §11 A 분기(백업 기준판과 같은 본문) — 셀 모드 불변 대조의 기준
OLD_A11 <- parse(text = OLD_A11_TXT, keep.source = FALSE)[[1]]
battery <- function(R, a11, tag) {
  R <- R$env; B <- file.path(S, paste0("bat_", tag)); r <- list()
  on.exit(set_mode(), add = TRUE)
  set_mode()
  # A1 정상 → 발행
  d <- mk_art(B, "ok"); s0 <- sha_of(file.path(d, "authoritative_remeasure.json"))
  a <- route(R, d, S); j <- jr(d, R$.RP_JR_ELIGIBLE)
  r$A1_publish <- identical(a$action, "publish") && isTRUE(a$eligible) && only_file(d, R$.RP_JR_ELIGIBLE) &&
    identical(j$schema, "judge_request_v2") && identical(j$status, "pending") && isTRUE(j$a_eligibility$eligible) &&
    !length(unlist(j$a_eligibility$codes)) && identical(j$a_eligibility$lane, "replication") && identical(j$layer, 1L) &&
    identical(j$grade, "A") && identical(j$source, "run_paper_replication") && identical(j$artifacts, d)
  r$A1_facts <- !is.null(j) && identical(j$a_eligibility$facts$regime, CUR) && identical(j$a_eligibility$facts$window_source, "derived_bt_result") &&
    identical(as.numeric(j$a_eligibility$facts$window_dev), 0) && identical(j$a_eligibility$required_selection_type, REQ_REPL) &&
    identical(j$a_eligibility$facts$selection_type, REQ_REPL)
  r$A1_grade_untouched <- identical(sha_of(file.path(d, "authoritative_remeasure.json")), s0)
  # A2 legacy regime → 보류
  d <- mk_art(B, "legacy", exec = LEG); a <- route(R, d, S)
  r$A2_legacy_hold <- identical(a$action, "hold") && "legacy_regime" %in% a$codes && only_file(d, R$.RP_JR_HELD) && held_has(d, "legacy_regime")
  # A3 창 이탈(허용 + 24개월 늦은 시작) → 보류
  late <- seq(ANCHOR, by = "month", length.out = ALLOW + 25)[ALLOW + 25]
  d <- mk_art(B, "window", start = late); a <- route(R, d, S)
  r$A3_window_hold <- identical(a$action, "hold") && "window_deviation" %in% a$codes && only_file(d, R$.RP_JR_HELD) &&
    held_has(d, "window_deviation") && identical(as.numeric(jr(d, R$.RP_JR_HELD)$a_eligibility$facts$window_dev), ALLOW + 24)
  # A4 회계 실패(결과를 본 뒤 바꾼 판 = sweep · N=5 · DSR 부재) → 보류
  d <- mk_art(B, "acct", sel = "sweep", nt = 5L, dsr = NULL); a <- route(R, d, S)
  r$A4_acct_hold <- identical(a$action, "hold") && "accounting_fail" %in% a$codes && only_file(d, R$.RP_JR_HELD) && held_has(d, "accounting_fail")
  # A4b 회계 실패(measurement_regime 부재 = P0-01 이전 판) → 보류
  d <- mk_art(B, "acct_pre", mr = FALSE); a <- route(R, d, S)
  r$A4b_acct_pre_hold <- identical(a$action, "hold") && "accounting_fail" %in% a$codes && only_file(d, R$.RP_JR_HELD)
  # A5 설정 키 부재 → gate_config 보류(fail-closed)
  d <- mk_art(B, "nokey"); a <- route(R, d, S_NOKEY)
  r$A5_nokey_gate_config <- identical(a$action, "hold") && "gate_config" %in% a$codes && only_file(d, R$.RP_JR_HELD)
  # A6 관문 정본 부재 → gate_error 보류(fail-closed)
  d <- mk_art(B, "nogate"); a <- route(R, d, S_NOGATE)
  r$A6_nogate_gate_error <- identical(a$action, "hold") && identical(a$codes, "gate_error") && only_file(d, R$.RP_JR_HELD) && held_has(d, "gate_error")
  # A7 판정 = 정본 술어 직접 호출(사본·재구현 없음) — 보류 칸에서 코드 집합 일치
  d <- mk_art(B, "direct", exec = LEG, start = late); a <- route(R, d, S)
  # ★P0-14 수리 2판: 직접 호출도 라우터와 같은 입력(engine_path)을 싣는다 — 관문은 spec·engine_path 가 모두 없으면 '재도출 대상 불명' 으로 보류한다
  gx <- R$.rp_gate_env(S)$env; inp <- if (is.environment(gx)) R$.rp_a_gate_inputs(d, basename(d), gx, S, engine_path = PAPER_ENGINE) else NULL
  dv <- if (!is.null(inp)) gx$rf_a_eligibility(inp$entry, inp$attempt, inp$spec, inp$ctx) else NULL
  r$A7_same_as_canon <- !is.null(dv) && identical(sort(a$codes), sort(as.character(dv$codes))) && all(c("legacy_regime", "window_deviation") %in% a$codes)
  # A8 관문 술어가 비논리 판정(eligible = NA · 코드 없음)을 돌려주면 → gate_error 보류(fail-closed · isTRUE 만 통과) — 적대 검증 2026-09-25 보강
  d <- mk_art(B, "na_verdict")
  a <- R$.rp_a_route(d, grade = "A", strategy_id = basename(d), engine_path = PAPER_ENGINE, cell = FALSE,
                     gate = function(...) list(eligible = NA), gx = GX, root = S)
  r$A8_na_verdict_hold <- identical(a$action, "hold") && identical(as.character(a$codes), "gate_error") && only_file(d, R$.RP_JR_HELD)
  # B1 §11 실블록 — 무인 충실구현 레인 모양(스위치만 · RF_CELL_SPEC 없음 · 논문 엔진) → 관문 경유 발행
  set_mode(nlo = "1"); d <- mk_art(B, "b1_verify_lane"); a <- run_a11(R, a11, d, PAPER_ENGINE, S)
  r$B1_verify_lane_gated <- identical(files_of(d), R$.RP_JR_ELIGIBLE %||% "judge_request.eligible.json") && identical((a %||% list())$mode, "replication")
  # B1b 같은 모양 · 보류 칸 → held 만(발행 없음)
  d <- mk_art(B, "b1_verify_lane_hold", exec = LEG); a <- run_a11(R, a11, d, PAPER_ENGINE, S)
  r$B1b_verify_lane_hold <- identical(files_of(d), R$.RP_JR_HELD %||% "judge_request.held.json")
  # B2 §11 실블록 — 강화 셀(스위치 ∧ RF_CELL_SPEC ∧ rf_cell_engine.R) → 구판 judge_request.json 만 · 관문 정본 없는 루트에서도 같다
  set_mode(nlo = "1", spec = CELL_SPEC); d <- mk_art(B, "b2_cell", exec = LEG); a <- run_a11(R, a11, d, CELL_ENGINE, S_NOGATE)
  new_txt <- if (file.exists(file.path(d, "judge_request.json"))) readLines(file.path(d, "judge_request.json"), warn = FALSE, encoding = "UTF-8") else character(0)
  unlink(file.path(d, "judge_request.json")); invisible(run_a11(R, OLD_A11, d, CELL_ENGINE, S_NOGATE))
  old_txt <- if (file.exists(file.path(d, "judge_request.json"))) readLines(file.path(d, "judge_request.json"), warn = FALSE, encoding = "UTF-8") else character(0)
  strip_ts <- function(x) x[!grepl('"requested_at"', x, fixed = TRUE)]
  r$B2_cell_legacy_unchanged <- length(new_txt) > 0L && identical(strip_ts(new_txt), strip_ts(old_txt)) &&
    identical(files_of(d), "judge_request.json") && identical((a %||% list())$action, "legacy")
  set_mode()
  # B3 셀 판별 진리표 — 스위치 ∧ RF_CELL_SPEC ∧ rf_cell_engine.R 셋 다일 때만 셀
  tt <- function(nlo, spec, eng) { set_mode(nlo, spec); v <- isTRUE(R$.rp_is_cell_run(eng)); set_mode(); v }
  r$B3_cell_truth_table <- tt("1", CELL_SPEC, CELL_ENGINE) && !tt("1", NA, PAPER_ENGINE) && !tt(NA, CELL_SPEC, CELL_ENGINE) &&
    !tt("1", CELL_SPEC, PAPER_ENGINE) && !tt("1", NA, CELL_ENGINE) && !tt("0", CELL_SPEC, CELL_ENGINE)
  # B4 A 아닌 등급 → 라우터는 아무것도 쓰지 않는다
  d <- mk_art(B, "b4_notA"); v <- R$.rp_a_route(d, grade = "B", strategy_id = "x", engine_path = PAPER_ENGINE, cell = FALSE,
                                                gate = NULL, gx = NULL, root = S)
  r$B4_non_a_noop <- is.null(v) && !length(files_of(d))
  # B5 셀 엔진이 셀 러너 밖(스위치 없음 · RF_CELL_SPEC 있음 — 수동 셀 재실행·Judge 재현 모양) → 충실구현 어댑터로 발행하지 않는다
  #   (적대 검증 2026-09-25: 수리 전에는 같은 칸이 chain/1 · 적대검증 없이 judge_request.eligible.json 으로 발행됐다) → held:cell_outside_runner
  set_mode(spec = CELL_SPEC); d <- mk_art(B, "b5_cell_outside"); a <- run_a11(R, a11, d, CELL_ENGINE, S)
  r$B5_cell_outside_runner_hold <- identical(files_of(d), R$.RP_JR_HELD %||% "judge_request.held.json") &&
    identical((a %||% list())$action, "hold") && identical(as.character((a %||% list())$codes), "cell_outside_runner") && held_has(d, "cell_outside_runner")
  set_mode(nlo = "0", spec = CELL_SPEC); d <- mk_art(B, "b5b_cell_outside_nlo0"); a <- run_a11(R, a11, d, CELL_ENGINE, S)
  r$B5b_cell_outside_nlo0_hold <- identical(files_of(d), R$.RP_JR_HELD %||% "judge_request.held.json") &&
    identical(as.character((a %||% list())$codes), "cell_outside_runner")
  set_mode()
  unlist(r)
}

cat("\n=== A·B. 배터리 — 실코드 ===\n")
REAL <- tryCatch(battery(RP, RP$a11, "real"), error = function(e) { ng("배터리 실행 오류(실코드)", conditionMessage(e)); c(error = FALSE) })
LABEL <- c(
  A1_publish = "A1 정상 A → judge_request.eligible.json 만(judge_request_v2 · pending · eligible · lane=replication · 구판·보류 파일 없음)",
  A1_facts = "A1 관문 사실 = 산출물 재도출(규약 = 현행 · 창 = bt_result.rds 재도출 0개월 · 회계 요건 = 설정 충실구현 키)",
  A1_grade_untouched = "A1 권위 산출물 authoritative_remeasure.json 바이트 불변(등급 불변 — 보류·발행은 발행만 다룬다)",
  A2_legacy_hold = "A2 legacy regime(칸 규약 ≠ 현행) → judge_request.held.json 만 · held:legacy_regime · 사유 · 발행 없음",
  A3_window_hold = "A3 창 이탈(허용+24개월 늦은 시작) → held:window_deviation · 재도출 이탈 개월 = 허용+24",
  A4_acct_hold = "A4 회계 실패(sweep·N=5·DSR 부재 — 충실구현 요건 chain 위반) → held:accounting_fail",
  A4b_acct_pre_hold = "A4b 회계 실패(measurement_regime 부재 = P0-01 이전 판) → held:accounting_fail",
  A5_nokey_gate_config = "A5 설정에 충실구현 회계 요건 키 부재 → gate_config 보류(fail-closed · 강화 요건 폴백 없음)",
  A6_nogate_gate_error = "A6 관문 정본 부재(적재 실패) → gate_error 보류(fail-closed)",
  A7_same_as_canon = "A7 라우터 보류 코드 = 정본 rf_a_eligibility 직접 호출 코드(판정 사본 없음 · legacy+window 동시)",
  A8_na_verdict_hold = "A8 관문 술어가 eligible=NA(비논리) → gate_error 보류만(isTRUE 만 발행 — fail-closed)",
  B1_verify_lane_gated = "B1 §11 실블록 · 무인 충실구현 레인 모양(QVEST_NO_LEDGER_OPEN=1 · RF_CELL_SPEC 없음) → 관문 경유 발행",
  B1b_verify_lane_hold = "B1b 같은 모양 · 보류 칸 → held 만(발행 없음)",
  B2_cell_legacy_unchanged = "B2 §11 실블록 · 강화 셀 → 구판 judge_request.json 만 · 구판 블록 출력과 바이트 동일(requested_at 제외) · 관문 정본 없는 루트에서도 같다",
  B3_cell_truth_table = "B3 셀 판별 = 스위치 ∧ RF_CELL_SPEC ∧ rf_cell_engine.R (6행 진리표)",
  B4_non_a_noop = "B4 A 아닌 등급 → 라우터 무동작(파일 0)",
  B5_cell_outside_runner_hold = "B5 §11 실블록 · 셀 엔진이 셀 러너 밖(스위치 없음 · RF_CELL_SPEC 있음) → held:cell_outside_runner 만(충실구현 어댑터 발행 없음)",
  B5b_cell_outside_nlo0_hold = "B5b 같은 모양 · QVEST_NO_LEDGER_OPEN=0 명시 → held:cell_outside_runner")
for (k in names(LABEL)) chk(LABEL[[k]], isTRUE(REAL[[k]]), if (k %in% names(REAL)) "" else "배터리 항목 부재")

# ── C. 설정 키 이름 — 부분 일치 함정 ─────────────────────────────────────────────────────────────────
cat("\n=== C. 설정 키 이름(부분 일치) ===\n")
G_real <- GX$rf_a_gate_config(S)
KEYS_AF <- names(fromJSON(file.path(S, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE)$holds$accounting_fail)
chk("C1 강화 요건 불변 — rf_a_gate_config(S)$required_selection_type = 설정 required_selection_type(충실구현 키가 끼어들지 않는다)",
    isTRUE(G_real$ok) && identical(G_real$required_selection_type,
                                   fromJSON(file.path(S, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE)$holds$accounting_fail$required_selection_type),
    G_real$required_selection_type)
chk("C2 충실구현 키는 required_selection_type 으로 시작하지 않는다(설정의 accounting_fail 키 중 그 접두는 강화 키 하나)",
    identical(KEYS_AF[startsWith(KEYS_AF, "required_selection_type")], "required_selection_type") && "replication_required_selection_type" %in% KEYS_AF)
S_PM <- file.path(tempdir(), sprintf("rp_agate_pm_%d", Sys.getpid())); invisible(mk_root(S_PM))
g <- fromJSON(file.path(S_PM, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE)
g$holds$accounting_fail$required_selection_type <- NULL
g$holds$accounting_fail[["required_selection_type_replication"]] <- REQ_REPL
writeLines(toJSON(g, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(S_PM, "06_Registry/a_eligibility_gate.json"))
chk("C3 양성 대조: 키를 required_selection_type… 로 짓고 강화 키가 빠지면 rf_a_gate_config 의 $ 부분 일치가 강화 요건을 충실구현 값으로 바꾼다(이름 규칙의 근거)",
    identical(GX$rf_a_gate_config(S_PM)$required_selection_type, REQ_REPL))

# ── M. 돌연변이 — 러너 소스 사본(메모리)에서 정의를 다시 떼어 배터리를 태운다 ─────────────────────────
cat("\n=== M. 돌연변이(러너 소스 사본) ===\n")
mut <- function(tag, from, to, want) {
  if (!grepl(from, RP_TXT, fixed = TRUE)) { ng(sprintf("%s 돌연변이 앵커 부재 — 검사 드리프트(옮겨라)", tag), substr(from, 1, 80)); return(invisible()) }
  M <- load_defs(sub(from, to, RP_TXT, fixed = TRUE))
  if (length(M$missing) || is.null(M$a11)) { ng(sprintf("%s 돌연변이 적재 실패", tag), paste(M$missing, collapse = ",")); return(invisible()) }
  res <- tryCatch(battery(M, M$a11, paste0("m_", gsub("[^A-Za-z0-9]", "", sub(" .*$", "", tag)))),   # 디렉터리 이름 = 머리 토큰(M1…)만
                  error = function(e) c(error = FALSE))
  red <- names(res)[!res]
  chk(sprintf("%s → red(%s)", tag, if (length(red)) paste(red, collapse = ",") else "없음"), all(want %in% red) && length(red) > 0L,
      sprintf("기대 red ⊇ {%s}", paste(want, collapse = ",")))
}
mut("M1 관문 우회(라우터 셀 분기 무조건 — 충실구현도 구판 파일)", "if (isTRUE(cell)) {", "if (TRUE) {",
    c("A1_publish", "A2_legacy_hold", "A3_window_hold", "A4_acct_hold", "B1_verify_lane_gated"))
mut("M2 판정 무시(ok <- TRUE)", "ok <- isTRUE(el$eligible)", "ok <- TRUE",
    c("A2_legacy_hold", "A3_window_hold", "A4_acct_hold", "A5_nokey_gate_config", "A6_nogate_gate_error", "B1b_verify_lane_hold"))
mut("M3 셀 판별 약화(QVEST_NO_LEDGER_OPEN 하나 — 무인 충실구현 레인이 셀로 샌다)",
    'identical(Sys.getenv("QVEST_NO_LEDGER_OPEN", "0"), "1") && nzchar(Sys.getenv("RF_CELL_SPEC", "")) &&\n    identical(basename(as.character(engine_path)[1]), "rf_cell_engine.R")',
    'identical(Sys.getenv("QVEST_NO_LEDGER_OPEN", "0"), "1")',
    c("B1_verify_lane_gated", "B1b_verify_lane_hold", "B3_cell_truth_table"))
mut("M4 관문 적재·평가 실패 fail-open(오류 판정을 적격으로)", 'list(eligible = FALSE, codes = "gate_error"', 'list(eligible = TRUE, codes = character(0)',
    c("A6_nogate_gate_error"))
A11_NOW <- regmatches(RP_TXT, regexpr("(?s)  if \\(identical\\(grade, \"A\"\\)\\) \\{\n    \\.a_cell <- .*?\n  \\} else if", RP_TXT, perl = TRUE))
if (length(A11_NOW) == 1L) {
  mut("M5 §11 구판 복원(관문 없이 judge_request.json 무조건)", A11_NOW, paste0("  ", OLD_A11_TXT, " else if"),
      c("B1_verify_lane_gated", "B1b_verify_lane_hold"))
} else ng("M5 돌연변이 앵커(§11 A 분기 본문) 부재 — 검사 드리프트", as.character(length(A11_NOW)))
mut("M6 회계 요건을 강화 키로(충실구현 키 대신 required_selection_type=sweep)",
    'rq <- as.character(unlist(af[["replication_required_selection_type"]]))[1]', 'rq <- as.character(unlist(af[["required_selection_type"]]))[1]',
    c("A1_publish", "B1_verify_lane_gated"))
mut("M7 셀 러너 밖 셀 엔진 보류 제거(충실구현 어댑터로 셀 A 판정 — 적대 검증 2026-09-25 우회 재현)",
    'cell_eng <- identical(basename(as.character(engine_path)[1]), "rf_cell_engine.R")', 'cell_eng <- FALSE',
    c("B5_cell_outside_runner_hold", "B5b_cell_outside_nlo0_hold"))
mut("M8 비논리 판정 fail-open(eligible=NA 를 적격으로)", "ok <- isTRUE(el$eligible)", "ok <- !isFALSE(el$eligible)",
    c("A8_na_verdict_hold"))

env_restore()
unlink(c(S, S_NOKEY, S_NOGATE, S_PM), recursive = TRUE)
emit()
if (F > 0L) quit(status = 1L)
