#!/usr/bin/env Rscript
#==============================================================================
# test_round_candidate_gate.R — 라운드 · 사슬 최종 후보의 A 자격 관문 연결 소방 훈련(v10.2 · 2026-11-10)
#   대상: 02_Infrastructure/programs/round_candidate_gate.R(rcg_route · rcg_finalize) · 관문 정본 rf_runner_gates.R::rf_a_eligibility
#         (러너 run_paper_replication.R 의 .rp_gate_env 로 적재 — 구문 트리로 꺼낸 정의)
#   A 소방 훈련(합성 양성 1건 끝까지): 합성 산출 폴더(권위 기록 + bt_result.rds) → 재채점 → 관문 → judge_request.eligible.json(pending)
#      ★재채점 단계는 건식이다 — sr_regrade 자리에 재채점이 남기는 필드(selection_gate.mode = reality_check · essence_grade)만 쓰는 대역을 둔다
#        (합성 산출물로 실측 등급 계약 · 선택 현실 점검을 태우려면 수익 CSV · 벤치 · 요인 파일 · 긴 벤치 이력이 필요하다).
#   B 음성 대조: A 아님 = skip(파일 0) · 팩터 DB 수리 전 실행 id = factor_db_stale 보류 · 재채점 안 거친 스윕 = selection_check_missing 보류 ·
#      관문 적재 실패 = gate_error 보류(fail-closed) · write = FALSE = 파일 0 · 칸 회계 요건 = 강화 칸 요건(sweep · 충실구현 키 아님) ·
#      판정 = 정본 술어 직접 호출과 같다 · 재채점이 A 아님으로 내리면 관문 안 탐
#   C 실측 사슬(가능할 때): 실측 산출물 사본(test_selection_regrade.R 과 같은 원천) → 실제 sr_regrade → 등급이 A 가 아니면 관문 skip · 파일 0
#   M 돌연변이(모듈 소스 사본 · 텍스트 치환 성사 단정): 선택 관문 확인 제거 → 재채점 안 거친 스윕 후보를 발행한다 → B 가 잡는다 ·
#      판정 무시(ok <- TRUE) → 보류 사례가 발행된다
# 쓰기: tempdir() 샌드박스만(운영 등록부 · 원장 · 실측 산출 폴더 무접촉 — 실측 산출물은 사본으로만). Judge 스폰 없음.
# 실행: R_ENVIRON_USER=<빈 파일> QM_ROOT=<저장소> Rscript 08_Tests/programs/test_round_candidate_gate.R
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)][1])
ROOT <- NA_character_
for (p in c(if (!is.na(me)) dirname(dirname(dirname(me))), Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""), getwd())) {
  if (is.null(p) || is.na(p) || !nzchar(p)) next
  p <- gsub("\\\\", "/", p)
  if (!grepl("^([A-Za-z]:|/)", p)) p <- sub("/[.]$", "", file.path(gsub("\\\\", "/", getwd()), p))   # 상대 경로는 작업 디렉터리 접두로만(경로 정규화 함수 금지)
  if (file.exists(file.path(p, "02_Infrastructure", "programs", "round_candidate_gate.R"))) { ROOT <- p; break }
}
if (is.na(ROOT)) stop("저장소 루트를 찾지 못했다(round_candidate_gate.R 없음)")
cat(sprintf("ROOT(읽기) = %s\n", ROOT))
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
chk <- function(name, cond, d = "") {
  ok <- isTRUE(tryCatch(cond, error = function(e) { cat("     오류:", conditionMessage(e), "\n"); FALSE }))
  if (ok) PASS <<- PASS + 1L else FAIL <<- FAIL + 1L
  cat(sprintf("  [%s] %s%s\n", if (ok) "PASS" else "FAIL", name, if (!ok && nzchar(paste(d, collapse = ""))) paste0(" — ", paste(d, collapse = " ")) else ""))
}
ENV_KEYS <- c("QM_ROOT", "QVEST_CONSTRAINT_DEFAULTS")
ENV0 <- Sys.getenv(ENV_KEYS, unset = NA_character_, names = TRUE)
env_restore <- function() for (k in ENV_KEYS) if (is.na(ENV0[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(ENV0[[k]]), k))
Sys.unsetenv("QVEST_CONSTRAINT_DEFAULTS")

# ── 샌드박스 루트(관문 정본 · 의존 · 설정 사본) ────────────────────────────────────────────────
TD <- gsub("\\\\", "/", tempfile("rcg_test_")); dir.create(TD, recursive = TRUE)
if (startsWith(tolower(TD), tolower(paste0(ROOT, "/")))) stop("샌드박스가 저장소 안에 있다 — 중단")
NEED <- c("02_Infrastructure/reinforcement/rf_runner_gates.R", "02_Infrastructure/reinforcement/rf_spec_sig.R",
          "02_Infrastructure/reinforcement/rf_block_design.R", "02_Infrastructure/reinforcement/reinforce_ledger.R",
          "02_Infrastructure/reinforcement/rf_lineage_flags.R", "02_Infrastructure/reinforcement/rf_spec_axes.R",
          "02_Infrastructure/contracts/essence_score.R", "02_Infrastructure/worktask/constraint_defaults.json",
          "06_Registry/a_eligibility_gate.json", "02_Infrastructure/alpha_search/run_paper_replication.R")
NEED <- unique(c(NEED, tryCatch({        # 관문 정본이 source 하는 파일 = 관문 소스에서 재도출(test_replication_a_gate.R 과 같은 방식)
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
S <- file.path(TD, "root"); S_NOGATE <- file.path(TD, "root_nogate"); S_NORUNNER <- file.path(TD, "root_norunner"); S_FDB <- file.path(TD, "root_fdb")
okroots <- c(mk_root(S), mk_root(S_NOGATE, drop = "02_Infrastructure/reinforcement/rf_runner_gates.R"),
             mk_root(S_NORUNNER, drop = "02_Infrastructure/alpha_search/run_paper_replication.R"), mk_root(S_FDB))
chk("S0 샌드박스 루트 4종 사본(관문 정본 · 의존 · 설정 · 러너)", all(okroots), NEED[!file.exists(file.path(ROOT, NEED))])
# 팩터 DB 판 표식 루트 — 계약 사본 + 임시 원장(운영 원장 무접촉)
dir.create(file.path(S_FDB, "02_Infrastructure/contracts"), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/contracts/factor_db_vintage.R"), file.path(S_FDB, "02_Infrastructure/contracts"), overwrite = TRUE))
writeLines(toJSON(list(schema = "factor_db_vintage_v1",
                       entries = list(list(id = "REPAIR-T", completed_at = "2026-11-10T01:00:00+09:00", scope = "all"))), auto_unbox = TRUE),
           file.path(S_FDB, "06_Registry/factor_db_vintage.json"))

E <- new.env(parent = globalenv())
sys.source(file.path(ROOT, "02_Infrastructure/programs/round_candidate_gate.R"), envir = E, keep.source = FALSE)
GX <- E$.rcg_runner_defs(S)$env$.rp_gate_env(S)$env
chk("S1 관문 정본 적재(러너 정의 .rp_gate_env 를 구문 트리로 꺼내 씀) · 전역 오염 없음",
    is.environment(GX) && is.function(GX$rf_a_eligibility) && !exists("rf_a_eligibility", envir = globalenv(), inherits = FALSE))
CFG <- fromJSON(file.path(S, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = TRUE)
CUR <- GX$rf_current_regime(S)$regime
ANCHOR <- as.Date(CFG[["diagnostics"]][["window_anchor_date"]])
REQ_CELL <- GX$rf_a_gate_config(S)$required_selection_type
GJ <- fromJSON(file.path(S, "06_Registry/a_eligibility_gate.json"), simplifyVector = FALSE)
cat(sprintf("       (설정 재도출: 현행 규약=%s · 창 기준=%s · 칸 회계 요건=%s · 충실구현 회계 요건=%s)\n", CUR, ANCHOR, REQ_CELL,
            as.character(GJ$holds$accounting_fail$replication_required_selection_type %||% "(부재)")))

# ── 합성 산출물 · 칸 사양 ─────────────────────────────────────────────────────────────────
ENG <- file.path(TD, "engines", "base_engine.R"); dir.create(dirname(ENG), recursive = TRUE); writeLines("BASE <- NULL", ENG)
SPEC <- file.path(TD, "cell_spec.json")
writeLines(toJSON(list(code = "P4T_K1", factors = list(), weighting = list(kind = "ew"), universe = list(kind = "all_hyg"),
                       base_signal = list(kind = "engine", path = ENG)), auto_unbox = TRUE), SPEC)
mk_art <- function(d, grade = "A", sel = "sweep", nt = 12L, dsr = 0.9, smode = "reality_check", exec = CUR, start = ANCHOR) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE); tag <- basename(d)
  au <- list(status = "OK", strategy_id = paste0("RC_T_", basename(tag)), essence_grade = grade, grade_scheme = "grade_v3", metric_type = "backtested",
             selection_type = sel, n_trials_cumulative = nt, dsr = dsr, essence = list(dsr = dsr),
             measurement_regime = list(selection_type = sel, n_trials_cumulative = nt, n_trials_basis = "round_cells", exec_price = exec,
                                       exec_price_basis = "argument", cost_model_version = "synthetic"))
  if (!is.null(smode)) au$selection_gate <- list(mode = smode, ok = TRUE, reason = "synthetic")
  writeLines(toJSON(au, auto_unbox = TRUE, null = "null", pretty = TRUE), file.path(d, "authoritative_remeasure.json"))
  dates <- seq(as.Date(start), by = "month", length.out = 24L)
  saveRDS(list(holdings = data.table(date = dates, ticker = "A000001", weight = 1),
               period_returns = data.table(date = dates, ret_net = rep(0.01, 24L))), file.path(d, "bt_result.rds"))
  d
}
jfiles <- function(d) sort(list.files(d, pattern = "^judge_request"))
rd <- function(d, nm) { p <- file.path(d, nm); if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL }
md5 <- function(p) unname(as.character(tools::md5sum(p)))
# 건식 재채점 대역 — sr_regrade 가 쓰는 필드만(등급 · 선택 관문 표식) · 시행 집합 기록
dry_regrade <- function(to_grade = "A") function(candidate_dir, trial_dirs, root, write) {
  ap <- file.path(candidate_dir, "authoritative_remeasure.json"); A <- fromJSON(ap, simplifyVector = FALSE); old <- A$essence_grade
  A$essence_grade <- to_grade; A$dsr_gate_applied <- FALSE
  A$selection_gate <- list(mode = "reality_check", ok = identical(to_grade, "A"), reason = "dry")
  A$selection_regrade <- list(tool = "dry_regrade(시험 대역)", n_trials = length(unique(c(candidate_dir, trial_dirs))))
  if (isTRUE(write)) writeLines(toJSON(A, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), ap, useBytes = TRUE)
  list(status = "ok", grade_before = old, grade_after = to_grade, gate_ok = identical(to_grade, "A"), written = isTRUE(write))
}

battery <- function(M, tag) {
  r <- list(); B <- file.path(TD, paste0("bat_", tag))
  # A 소방 훈련 — 재채점 전 스윕 후보(측정 시점 등급 A · 선택 관문 표식 없음) → 재채점(건식) → 관문 → 발행
  cand <- mk_art(file.path(B, "cand"), smode = NULL); trials <- c(cand, mk_art(file.path(B, "t1")), mk_art(file.path(B, "t2")))
  f <- M$rcg_finalize(cand, trials, "RC_T_cand", spec_path = SPEC, root = S, write = TRUE, regrade_fn = dry_regrade("A"))
  j <- rd(cand, "judge_request.eligible.json")
  r$A1_drill_publish <- identical(f$route$action, "publish") && identical(jfiles(cand), "judge_request.eligible.json") &&
    identical(j$schema, "judge_request_v2") && identical(j$status, "pending") && isTRUE(j$a_eligibility$eligible) &&
    identical(j$source, "round_candidate_gate") && identical(j$a_eligibility$lane, "program_round") &&
    identical(j$a_eligibility$adapter, "round_candidate_gate.R::rcg_route") && identical(j$artifacts, cand) && identical(j$layer, 1L)
  r$A2_drill_cell_accounting <- !is.null(j) && identical(j$a_eligibility$required_selection_type, REQ_CELL) && identical(REQ_CELL, "sweep") &&
    identical(j$a_eligibility$facts$selection_type, "sweep") && identical(j$engine_path, ENG) && identical(j$cell, "P4T_K1")
  r$A3_drill_status <- grepl("^regrade ok\\(A→A\\) · gate publish$", f$status)
  # B1 A 아님 = skip(파일 0)
  d <- mk_art(file.path(B, "notA"), grade = "B"); a <- M$rcg_route(d, "x", spec_path = SPEC, root = S, write = TRUE)
  r$B1_notA_skip <- identical(a$action, "skip") && !length(jfiles(d))
  # B2 재채점 안 거친 스윕 후보 → selection_check_missing 보류(관문 자체는 통과하는 칸)
  d <- mk_art(file.path(B, "nosel"), smode = NULL); a <- M$rcg_route(d, "x", spec_path = SPEC, root = S, write = TRUE); h <- rd(d, "judge_request.held.json")
  r$B2_selection_missing_hold <- identical(a$action, "hold") && identical(a$codes, "selection_check_missing") && identical(jfiles(d), "judge_request.held.json") &&
    identical(h$status, "held:selection_check_missing") && isTRUE(nzchar(h$a_eligibility$detail$selection_check_missing)) && isTRUE(a$verdict$eligible)
  # B3 팩터 DB 수리 전 실행 id → factor_db_stale(상시 보류)
  d <- mk_art(file.path(B, "20261105_090000_1")); a <- M$rcg_route(d, "x", spec_path = SPEC, root = S_FDB, write = TRUE)
  d2 <- mk_art(file.path(B, "20261110_090000_2")); a2 <- M$rcg_route(d2, "x", spec_path = SPEC, root = S_FDB, write = TRUE)
  r$B3_factor_db_stale_hold <- identical(a$action, "hold") && "factor_db_stale" %in% a$codes && identical(jfiles(d), "judge_request.held.json") &&
    identical(a2$action, "publish") && identical(jfiles(d2), "judge_request.eligible.json")
  # B4 관문 적재 실패(관문 정본 부재 · 러너 정의 부재 · 적재기 오류) → gate_error 보류(fail-closed)
  d <- mk_art(file.path(B, "nogate")); a <- M$rcg_route(d, "x", spec_path = SPEC, root = S_NOGATE, write = TRUE)
  d2 <- mk_art(file.path(B, "norunner")); a2 <- M$rcg_route(d2, "x", spec_path = SPEC, root = S_NORUNNER, write = TRUE)
  d3 <- mk_art(file.path(B, "loaderr")); a3 <- M$rcg_route(d3, "x", spec_path = SPEC, root = S, write = TRUE, gate_loader = function(root) stop("주입 오류"))
  r$B4_gate_load_fail_hold <- all(vapply(list(list(a, d), list(a2, d2), list(a3, d3)), function(z)
    identical(z[[1]]$action, "hold") && identical(z[[1]]$codes, "gate_error") && identical(jfiles(z[[2]]), "judge_request.held.json"), logical(1)))
  # B5 write = FALSE → 파일 0(통과 · 보류 모두)
  d <- mk_art(file.path(B, "dry_ok")); a <- M$rcg_route(d, "x", spec_path = SPEC, root = S, write = FALSE)
  d2 <- mk_art(file.path(B, "dry_hold"), smode = NULL); a2 <- M$rcg_route(d2, "x", spec_path = SPEC, root = S, write = FALSE)
  r$B5_write_false_no_files <- identical(a$action, "publish") && identical(a2$action, "hold") && !length(jfiles(d)) && !length(jfiles(d2)) &&
    is.na(a$path) && length(list.files(d)) == 2L
  # B6 관문 보류(legacy 규약) — 정본 술어 직접 호출과 같은 코드 · 권위 기록 바이트 불변
  LEG <- setdiff(as.character(CFG[["execution"]][["exec_price_allowed"]]), CUR)[1]
  d <- mk_art(file.path(B, "legacy"), exec = LEG); s0 <- md5(file.path(d, "authoritative_remeasure.json"))
  a <- M$rcg_route(d, "x", spec_path = SPEC, root = S, write = TRUE)
  sp <- fromJSON(SPEC, simplifyVector = FALSE); inp <- M$.rcg_gate_inputs(d, "x", sp, SPEC, GX, S)
  dv <- GX$rf_a_eligibility(inp$entry, inp$attempt, inp$spec, inp$ctx)
  r$B6_same_as_canon <- identical(a$action, "hold") && "legacy_regime" %in% a$codes && identical(sort(a$codes), sort(as.character(dv$codes))) &&
    identical(md5(file.path(d, "authoritative_remeasure.json")), s0)
  # B7 재채점이 A 아님으로 내리면 관문 안 탐(파일 0)
  d <- mk_art(file.path(B, "down"), smode = NULL)
  f <- M$rcg_finalize(d, c(d), "x", spec_path = SPEC, root = S, write = TRUE, regrade_fn = dry_regrade("B"))
  r$B7_regrade_down_no_gate <- is.null(f$route) && !length(jfiles(d)) && grepl("gate skip", f$status)
  # B8 칸 회계 = 강화 칸 요건(sweep) — 같은 칸을 chain 으로 적으면 accounting_fail(충실구현 키 chain 을 빌리지 않는다)
  d <- mk_art(file.path(B, "chain"), sel = "chain", nt = 1L, dsr = NULL); a <- M$rcg_route(d, "x", spec_path = SPEC, root = S, write = TRUE)
  r$B8_cell_accounting_not_replication_key <- identical(a$action, "hold") && "accounting_fail" %in% a$codes
  # B9 재판정 뒤 반대쪽 파일은 지운다(두 판정 공존 금지)
  d <- mk_art(file.path(B, "flip"), smode = NULL); M$rcg_route(d, "x", spec_path = SPEC, root = S, write = TRUE)
  A <- fromJSON(file.path(d, "authoritative_remeasure.json"), simplifyVector = FALSE); A$selection_gate <- list(mode = "reality_check", ok = TRUE)
  writeLines(toJSON(A, auto_unbox = TRUE, null = "null"), file.path(d, "authoritative_remeasure.json"))
  a <- M$rcg_route(d, "x", spec_path = SPEC, root = S, write = TRUE)
  r$B9_flip_single_file <- identical(a$action, "publish") && identical(jfiles(d), "judge_request.eligible.json")
  # B10 요청이 나간 뒤 재채점이 A 아님으로 내리면 그 요청을 거둔다(트리거가 A 아닌 후보를 가리키지 않게) · 건식(write = FALSE)은 그대로 둔다
  d <- mk_art(file.path(B, "withdraw")); M$rcg_route(d, "x", spec_path = SPEC, root = S, write = TRUE)
  pre <- identical(jfiles(d), "judge_request.eligible.json"); rq0 <- rd(d, "judge_request.eligible.json")$requested_at
  f0 <- M$rcg_finalize(d, c(d), "x", spec_path = SPEC, root = S, write = FALSE, regrade_fn = dry_regrade("B"))
  dry_kept <- identical(jfiles(d), "judge_request.eligible.json") && isTRUE(f0$withdraw$pending)
  f <- M$rcg_finalize(d, c(d), "x", spec_path = SPEC, root = S, write = TRUE, regrade_fn = dry_regrade("B")); h <- rd(d, "judge_request.held.json")
  r$B10_withdraw_after_downgrade <- pre && dry_kept && is.null(f$route) && isTRUE(f$withdraw$withdrawn) && identical(jfiles(d), "judge_request.held.json") &&
    identical(h$status, "held:grade_not_a") && identical(h$held$codes[[1]], "grade_not_a") && identical(h$requested_at, rq0) && grepl("앞선 요청 거둠", f$status)
  # B11 단독 호출(rcg_route)도 A 아닌 후보의 남은 요청을 거둔다 · 요청이 없던 폴더는 그대로 파일 0
  d <- mk_art(file.path(B, "withdraw_cli")); M$rcg_route(d, "x", spec_path = SPEC, root = S, write = TRUE)
  A <- fromJSON(file.path(d, "authoritative_remeasure.json"), simplifyVector = FALSE); A$essence_grade <- "C"
  writeLines(toJSON(A, auto_unbox = TRUE, null = "null"), file.path(d, "authoritative_remeasure.json"))
  a <- M$rcg_route(d, "x", spec_path = SPEC, root = S, write = TRUE)
  r$B11_route_withdraws_stale_request <- identical(a$action, "skip") && isTRUE(a$withdrawn) && identical(jfiles(d), "judge_request.held.json")
  unlist(r)
}

cat("\n=== A · B 배터리 — 실코드 ===\n")
REAL <- tryCatch(battery(E, "real"), error = function(e) { cat("     배터리 오류:", conditionMessage(e), "\n"); c(error = FALSE) })
LABEL <- c(
  A1_drill_publish = "A1 소방 훈련: 합성 양성(재채점 전 스윕 A) → 재채점(★건식 대역) → 관문 → judge_request.eligible.json 만(judge_request_v2 · pending · source/lane/adapter)",
  A2_drill_cell_accounting = "A2 요청의 회계 요건 = 관문 설정의 칸 요건(sweep) · 기저 엔진 경로 · 칸 코드 = 칸 사양",
  A3_drill_status = "A3 마감 상태 한 줄 = 'regrade ok(A→A) · gate publish'",
  B1_notA_skip = "B1 essence_grade ≠ A → skip · 파일 0",
  B2_selection_missing_hold = "B2 재채점 안 거친 스윕 후보(관문 자체는 적격) → held:selection_check_missing 만",
  B3_factor_db_stale_hold = "B3 팩터 DB 수리 전 실행 id → factor_db_stale 보류 · [대조] 수리 뒤 실행 id 는 발행",
  B4_gate_load_fail_hold = "B4 관문 적재 실패(정본 부재 · 러너 정의 부재 · 적재기 오류) → gate_error 보류(fail-closed)",
  B5_write_false_no_files = "B5 write = FALSE → 통과 · 보류 모두 파일 0(판정만)",
  B6_same_as_canon = "B6 보류 코드 = 정본 rf_a_eligibility 직접 호출 코드(판정 사본 없음) · 권위 기록 바이트 불변",
  B7_regrade_down_no_gate = "B7 재채점이 A 아님으로 내리면 관문에 태우지 않는다(파일 0)",
  B8_cell_accounting_not_replication_key = "B8 칸 회계 = 강화 칸 요건 — chain/1 칸은 accounting_fail(충실구현 키 chain 을 빌리지 않는다)",
  B9_flip_single_file = "B9 재판정(보류 → 통과) 뒤 폴더에 요청 파일 하나만(반대쪽 파일 삭제)",
  B10_withdraw_after_downgrade = "B10 요청이 나간 뒤 재채점이 A 아님으로 내리면 요청을 거둔다(held:grade_not_a · 원 요청 시각 보존) · 건식은 파일 불변",
  B11_route_withdraws_stale_request = "B11 단독 호출도 A 아닌 후보의 남은 요청을 거둔다")
for (k in names(LABEL)) chk(LABEL[[k]], isTRUE(REAL[[k]]), if (k %in% names(REAL)) "" else "배터리 항목 부재")

cat("\n=== C 실측 사슬(실제 sr_regrade · 실측 산출물 사본) ===\n")
DIR <- file.path(ROOT, "stage_artifacts/replication/20260905_095537_1276/remeasure_close_t1_5562284e")
need <- c("02_nav.csv", "03_period_returns.csv", "05_benchmark_returns.csv", "06_metrics.csv", "07_benchmark_compare.csv", "authoritative_remeasure.json")
if (!all(file.exists(file.path(DIR, need)))) { SKIP <- SKIP + 1L; cat("  [skip] 실측 산출물 없음 —", DIR, "\n") } else {
  cand <- file.path(TD, "live", "cand"); dir.create(cand, recursive = TRUE)
  for (f in need) file.copy(file.path(DIR, f), file.path(cand, f))
  P0 <- fread(file.path(DIR, "03_period_returns.csv")); set.seed(8L)
  vars <- vapply(1:2, function(i) { d <- file.path(TD, "live", paste0("var", i)); dir.create(d)
    Pi <- copy(P0); Pi[, ret_net := ret_net + rnorm(.N, 0, 0.0005)]
    fwrite(Pi, file.path(d, "03_period_returns.csv")); file.copy(file.path(DIR, "05_benchmark_returns.csv"), file.path(d, "05_benchmark_returns.csv")); d }, character(1))
  src_md5 <- md5(file.path(DIR, "authoritative_remeasure.json"))
  lf <- tryCatch(E$rcg_finalize(cand, vars, "RC_T_live", spec_path = NULL, root = ROOT, write = TRUE), error = function(e) e)
  if (inherits(lf, "error")) chk("C1 실측 사슬 실행", FALSE, conditionMessage(lf)) else {
    ga <- as.character(lf$regrade$grade_after)
    chk(sprintf("C1 실제 sr_regrade(시행 3) → 등급 %s → 관문 %s(A 일 때만 관문 · 그 밖은 파일 0)", ga, if (is.null(lf$route)) "skip" else lf$route$action),
        identical(lf$regrade$status, "ok") && (if (identical(ga, "A")) !is.null(lf$route) else is.null(lf$route) && !length(jfiles(cand))))
    chk("C2 재채점이 후보 사본에 선택 관문 표식(reality_check)을 남기고 원 실측 산출물은 바이트 불변",
        identical(fromJSON(file.path(cand, "authoritative_remeasure.json"), simplifyVector = FALSE)$selection_gate$mode, "reality_check") &&
          identical(md5(file.path(DIR, "authoritative_remeasure.json")), src_md5))
  }
}

cat("\n=== M 돌연변이(모듈 소스 사본 — 텍스트 치환 성사 단정) ===\n")
SRC <- paste(readLines(file.path(ROOT, "02_Infrastructure/programs/round_candidate_gate.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
mut <- function(tag, from, to, want) {
  if (!grepl(from, SRC, fixed = TRUE)) { chk(sprintf("%s 돌연변이 앵커 부재 — 검사 드리프트", tag), FALSE); return(invisible()) }
  txt <- sub(from, to, SRC, fixed = TRUE)
  if (identical(txt, SRC)) { chk(sprintf("%s 치환 불성사", tag), FALSE); return(invisible()) }
  M <- new.env(parent = globalenv()); eval(parse(text = txt, keep.source = FALSE, encoding = "UTF-8"), envir = M)
  res <- tryCatch(battery(M, paste0("m_", sub(" .*$", "", tag))), error = function(e) c(error = FALSE))
  red <- names(res)[!res]
  chk(sprintf("%s → red(%s)", tag, if (length(red)) paste(red, collapse = ",") else "없음"), all(want %in% red), sprintf("기대 red ⊇ {%s}", paste(want, collapse = ",")))
}
mut("M1 선택 관문 확인 제거(재채점 안 거친 스윕 후보를 발행)", 'if (identical(sel, "sweep") && !identical(smode, "reality_check")) {',
    'if (FALSE) {', c("B2_selection_missing_hold"))
mut("M2 판정 무시(ok <- TRUE)", "ok <- isTRUE(el$eligible)", "ok <- TRUE",
    c("B3_factor_db_stale_hold", "B4_gate_load_fail_hold", "B6_same_as_canon", "B8_cell_accounting_not_replication_key"))
mut("M3 칸 회계를 충실구현 키로(chain)", "G <- gx$rf_a_gate_config(root)",
    'G <- gx$rf_a_gate_config(root); G$required_selection_type <- "chain"', c("A1_drill_publish", "B8_cell_accounting_not_replication_key"))
mut("M4 요청 거두기 제거(내려간 후보의 트리거가 남는다)", "  unlink(src)\n  list(withdrawn = !file.exists(src), path = p, pending = FALSE)",
    "  list(withdrawn = !file.exists(src), path = p, pending = FALSE)", c("B10_withdraw_after_downgrade", "B11_route_withdraws_stale_request"))

env_restore()
unlink(TD, recursive = TRUE)
cat(sprintf("\n%s\n", toJSON(list(test = "test_round_candidate_gate", pass = PASS, fail = FAIL, skipped = SKIP), auto_unbox = TRUE)))
quit(status = if (FAIL > 0L) 1L else 0L)
