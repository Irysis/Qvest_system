#!/usr/bin/env Rscript
#==============================================================================
# round_candidate_gate.R — 프로그램 라운드 · 강화 사슬의 사전등록 최종 후보 1칸을 A 자격 관문에 태운다 (v10.2 · 2026-11-10)
#
# 왜: 충실구현 경로는 Grade A 면 A 자격 관문(rf_runner_gates.R::rf_a_eligibility)을 타고 judge_request.eligible.json(Judge 트리거)
#   또는 judge_request.held.json(보류)을 낸다(run_paper_replication.R §11 · P0-13). 프로그램 라운드의 칸(셀 엔진 rf_cell_engine.R)에는
#   그 연결이 없었다 — 칸이 A 여도 구판 이름 judge_request.json(트리거 아님)만 남아, 라운드 · 사슬의 최종 후보가 A 를 받아도
#   Judge 로 갈 길이 없었다(설계 04_Research/01_reports/qvest_v10_2_audit_redesign_20261110/README.md §3 · §8-4 · §9).
#   또 등급 v3.4 부터 스윕형 선정의 최종 후보는 시행 집합이 다 모인 뒤 선택 현실 점검으로 다시 채점돼야 A 를 말할 수 있다
#   (programs/selection_regrade.R::sr_regrade · DSR-GATE-FORM-20261110).
#
# 무엇:
#   rcg_route(candidate_dir, strategy_id, spec_path, root, write)  — 후보 1칸(권위 기록 essence_grade == "A" 일 때만)을 관문에 태워
#     judge_request.eligible.json(status pending) 또는 judge_request.held.json(status held:<코드+…>)을 후보 산출 폴더에 쓴다(write = TRUE 일 때만).
#   rcg_finalize(candidate_dir, trial_dirs, strategy_id, spec_path, root, write) — ① sr_regrade(시행 집합) ② 재채점 뒤 A 면 rcg_route.
#
# 관문 정본 적재(복제 없음): 관문 술어는 rf_runner_gates.R 그대로다. 그 파일을 격리 환경에 싣는 함수(.rp_gate_env)와 오류 판정 모양
#   (.rp_gate_err_verdict)은 충실구현 러너 run_paper_replication.R 에 있다 — 러너를 통째로 source 하지 않고, 그 파일을 구문 트리로 읽어
#   두 정의만 꺼내 쓴다(trial_budget.R::tb_load_dsr 와 같은 방식). 그래서 두 경로의 적재 · 오류 판정은 한 출처다.
#   꺼내기 실패(파일 부재 · 정의 부재 · 파싱 실패)나 관문 적재 실패 = gate_error 보류(fail-closed — 발행하지 않는다).
#
# 칸 어댑터(충실구현 어댑터 .rp_a_gate_inputs 와 다른 점):
#   · 회계 요건 = 관문 설정의 칸 요건(rf_a_gate_config()$required_selection_type — 강화 칸 = sweep). 충실구현 키
#     (replication_required_selection_type)는 쓰지 않는다 — 라운드 칸은 열거된 칸에서 사전등록 규칙으로 고른 스윕이다.
#   · spec = 칸 사양(JSON → list) · engine_path = 칸 사양의 기저 엔진 경로(base_signal.kind == "engine" 의 path)가 있으면.
#   · 선택 관문 확인(이 모듈의 보류 코드 selection_check_missing — 관문 정본 코드 집합에 넣지 않는다): 권위 기록의 selection_type 이
#     sweep 인데 selection_gate$mode 가 reality_check 가 아니면(= 재채점을 거치지 않은 스윕 후보) 발행하지 않는다.
# 등급 · 문턱 불변 — 보류는 발행만 막는다(authoritative_remeasure.json 은 rcg_route 가 손대지 않는다 · 재채점은 sr_regrade 의 일).
# Judge 는 스폰하지 않는다 — 요청 파일만 쓴다(스폰 = 세션 Q-Lead · .claude/agents/judge.md §스폰 조건).
# 사용: Rscript 02_Infrastructure/programs/round_candidate_gate.R <후보 폴더> <strategy_id> [<칸 사양 json>] [--write]
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

RCG_JR_ELIGIBLE <- "judge_request.eligible.json"   # 관문 통과 = Judge 트리거(충실구현과 같은 이름)
RCG_JR_HELD     <- "judge_request.held.json"       # 관문 보류(사유 코드) — 트리거 아님
RCG_HOLD_SELECTION <- "selection_check_missing"    # 이 모듈의 보류 코드(재채점을 거치지 않은 스윕 후보) — 관문 정본 코드 집합 밖
RCG_HOLD_NOT_A     <- "grade_not_a"                # 이 모듈의 보류 코드(요청이 나간 뒤 등급이 A 가 아니게 된 후보 — 요청을 거둔다)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.rcg_or <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.rcg_root <- function(root = NULL) {
  # 순서 = 명시 > CLAUDE_PROJECT_DIR > QM_ROOT(금칙 ④ — ~/.Renviron 의 QM_ROOT 는 셸로 덮이지 않는다 · selection_regrade.R .sr_root 와 같은 계열)
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || is.na(p) || !nzchar(p)) next
    p <- sub("/+$", "", gsub("\\\\", "/", p))
    if (dir.exists(file.path(p, "02_Infrastructure"))) return(p)
  }
  stop("[round_candidate_gate] 프로젝트 루트 해석 실패", call. = FALSE)
}
.rcg_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
.rcg_json <- function(p) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)

#' 충실구현 러너에서 관문 적재기 · 오류 판정 정의만 꺼낸다(러너 전체 source 없음). 반환 list(env, err).
.rcg_runner_defs <- function(root) {
  f <- file.path(root, "02_Infrastructure", "alpha_search", "run_paper_replication.R")
  want <- c(".rp_gate_env", ".rp_gate_err_verdict")
  if (!file.exists(f)) return(list(env = NULL, err = paste0("관문 적재기 출처 부재: ", f)))
  ex <- tryCatch(parse(f, keep.source = FALSE, encoding = "UTF-8"), error = function(e) e)
  if (inherits(ex, "error")) return(list(env = NULL, err = paste0("관문 적재기 출처 파싱 실패: ", conditionMessage(ex))))
  e <- new.env(parent = globalenv())
  for (x in ex) if (is.call(x) && identical(x[[1]], as.name("<-")) && is.name(x[[2]]) && as.character(x[[2]]) %in% want) eval(x, envir = e)
  miss <- setdiff(want, ls(e, all.names = TRUE))
  if (length(miss)) return(list(env = NULL, err = paste0("관문 적재기 정의 부재(", paste(miss, collapse = ","), ") — 러너가 바뀌었다(이 모듈도 따라가야 한다)")))
  list(env = e, err = "")
}

# 오류 판정 — 러너 정의가 있으면 그것(한 출처), 없으면 같은 모양의 최소판(정의를 꺼내지 못한 경우에만 — fail-closed 보류용)
.rcg_err_verdict <- function(defs, msg, now) {
  if (is.environment(defs$env) && is.function(defs$env$.rp_gate_err_verdict)) return(defs$env$.rp_gate_err_verdict(msg, now))
  list(eligible = FALSE, codes = "gate_error", inactive = character(0), fired = "gate_error",
       detail = list(gate_error = as.character(msg)[1]), facts = list(), gate_source = "", gate_active = character(0),
       regime_current = NA_character_, self_unverified = FALSE, evaluated_at = now)
}

#' 칸 사양 → 기저 엔진 경로(base_signal.kind == "engine" 의 path) · 없으면 NULL
.rcg_engine_of <- function(sp) {
  bs <- if (is.list(sp)) sp[["base_signal"]] else NULL
  if (is.list(bs) && identical(as.character(.rcg_or(bs$kind, "")), "engine") && nzchar(as.character(.rcg_or(bs$path, ""))))
    gsub("\\\\", "/", as.character(bs$path)[1]) else NULL
}

#' 칸 → 관문 입력 어댑터(판독만 · 쓰기 0). 회계 요건 = 관문 설정의 칸 요건(rf_a_gate_config 그대로 — 충실구현 키 아님).
.rcg_gate_inputs <- function(candidate_dir, strategy_id, sp, spec_path, gx, root) {
  G <- gx$rf_a_gate_config(root)
  attempt <- list(n = 0L, cell_code = as.character(.rcg_or(if (is.list(sp)) sp$code else NULL, basename(candidate_dir))), grade = "A",
                  essence = list(grade = "A", lane = "program_round", source = "authoritative_remeasure.json",
                                 spec = if (length(spec_path) && !is.na(spec_path[1])) as.character(spec_path[1]) else NULL),
                  artifacts = candidate_dir, vintage_flags = list())
  ep <- .rcg_engine_of(sp)
  if (!is.null(ep)) attempt$engine_path <- ep
  ctx <- gx$rf_a_ctx(gx$rf_runner_ctx(root), entries = list(), base_id = strategy_id, gate = G)
  list(entry = NULL, attempt = attempt, spec = sp, ctx = ctx, required_selection_type = as.character(.rcg_or(G$required_selection_type, NA_character_)))
}

#' 최종 후보 1칸 → A 자격 관문 → 요청 파일
#' @param candidate_dir 후보 산출 폴더(authoritative_remeasure.json · bt_result.rds)
#' @param strategy_id   요청 파일의 strategy_id · 관문 문맥 base_id
#' @param spec_path     칸 사양 JSON(없으면 NULL — spec 없이 관문을 태우면 재도출 입력이 없어 보류될 수 있다)
#' @param write         TRUE 일 때만 파일을 쓴다(임시 파일 → 이름 바꾸기)
#' @param gate_loader   시험용 주입점(기본 = 러너 정의 .rp_gate_env) — function(root) → list(env, err)
#' @return list(action = "publish"|"hold"|"skip", eligible, codes, path, verdict, request)
rcg_route <- function(candidate_dir, strategy_id, spec_path = NULL, root = NULL, write = FALSE, now = .rcg_now(), gate_loader = NULL) {
  root <- .rcg_root(root)
  candidate_dir <- sub("/+$", "", gsub("\\\\", "/", as.character(candidate_dir)[1]))
  au <- .rcg_json(file.path(candidate_dir, "authoritative_remeasure.json"))
  g0 <- as.character(.rcg_or((au %||% list())[["essence_grade"]], NA_character_))[1]
  if (!identical(g0, "A")) {
    # A 가 아닌데 앞서 나간 Judge 트리거가 폴더에 남아 있으면 거둔다(권위 기록을 읽을 수 있을 때만 — 판독 불가는 손대지 않는다)
    wd <- if (is.null(au)) list(withdrawn = FALSE) else rcg_withdraw(candidate_dir, g0, write = write, now = now)
    return(list(action = "skip", eligible = NA, codes = character(0), path = NA_character_, verdict = NULL, withdrawn = isTRUE(wd$withdrawn),
                why = if (is.null(au)) "권위 기록 판독 불가" else sprintf("essence_grade = %s(A 아님)", g0)))
  }
  sp <- NULL; sp_err <- ""
  if (length(spec_path) && !is.na(spec_path[1]) && nzchar(spec_path[1])) {
    sp <- .rcg_json(spec_path[1]); if (is.null(sp)) sp_err <- paste0("칸 사양 판독 불가: ", spec_path[1])
  }
  defs <- .rcg_runner_defs(root)
  gl <- if (is.function(gate_loader)) tryCatch(gate_loader(root), error = function(e) list(env = NULL, err = conditionMessage(e)))
        else if (is.environment(defs$env)) defs$env$.rp_gate_env(root) else list(env = NULL, err = defs$err)
  gx <- if (is.list(gl) && is.environment(gl$env)) gl$env else NULL
  gate <- if (!is.null(gx) && is.function(gx$rf_a_eligibility)) gx$rf_a_eligibility else NULL
  rq <- NA_character_
  el <- if (is.null(gate)) {
    .rcg_err_verdict(defs, if (nzchar(as.character(.rcg_or(gl$err, "")))) gl$err else "관문 술어 적재 실패(원인 미상)", now)
  } else tryCatch({
    inp <- .rcg_gate_inputs(candidate_dir, strategy_id, sp, spec_path, gx, root)
    rq <- inp$required_selection_type
    gate(inp$entry, inp$attempt, inp$spec, inp$ctx)
  }, error = function(e) .rcg_err_verdict(defs, paste0("관문 평가 오류: ", conditionMessage(e)), now))
  ok <- isTRUE(el$eligible)
  codes <- as.character(.rcg_or(el$codes, character(0)))
  detail <- .rcg_or(el$detail, list())
  if (nzchar(sp_err)) { ok <- FALSE; codes <- unique(c(codes, "gate_error")); detail$gate_error <- paste(c(detail$gate_error, sp_err), collapse = " · ") }
  # 선택 관문 확인 — 스윕 후보는 선택 현실 점검 재채점(selection_regrade.R)을 거쳐야 발행한다(등급 v3.4)
  sel <- as.character(.rcg_or(au$selection_type, .rcg_or((au$measurement_regime %||% list())$selection_type, "")))[1]
  smode <- as.character(.rcg_or((au$selection_gate %||% list())$mode, ""))[1]
  if (identical(sel, "sweep") && !identical(smode, "reality_check")) {
    ok <- FALSE; codes <- unique(c(codes, RCG_HOLD_SELECTION))
    detail[[RCG_HOLD_SELECTION]] <- sprintf("스윕 후보인데 selection_gate$mode = %s — 선택 현실 점검 재채점(selection_regrade.R::sr_regrade)을 거치지 않았다(등급 v3.4)",
                                            if (nzchar(smode)) smode else "(없음)")
  }
  if (!ok && !length(codes)) codes <- "gate_error"            # 부적격인데 코드가 비면 사유 없는 보류 — 그렇게 두지 않는다
  if (ok) codes <- character(0)
  ep <- .rcg_engine_of(sp)
  req <- list(schema = "judge_request_v2",
              status = if (ok) "pending" else paste0("held:", paste(codes, collapse = "+")),
              requested_at = now, source = "round_candidate_gate",
              strategy_id = strategy_id, layer = 1L, grade = "A",
              base_id = strategy_id, attempt = 0L, cell = if (is.list(sp)) .rcg_or(sp$code, NULL) else NULL, artifacts = candidate_dir,
              engine_path = .rcg_or(ep, NA_character_), base_engine_path = .rcg_or(ep, NA_character_),
              spec = if (length(spec_path) && !is.na(spec_path[1])) as.character(spec_path[1]) else "",
              a_eligibility = list(eligible = ok, codes = as.list(codes),
                                   inactive = as.list(as.character(.rcg_or(el$inactive, character(0)))),
                                   detail = detail,
                                   checked_at = .rcg_or(el$evaluated_at, now), regime = .rcg_or(el$regime_current, NA_character_),
                                   gate = .rcg_or(el$gate_source, ""), gate_active = as.list(as.character(.rcg_or(el$gate_active, character(0)))),
                                   lane = "program_round", adapter = "round_candidate_gate.R::rcg_route",
                                   required_selection_type = rq,
                                   selection_gate = list(selection_type = sel, mode = smode),
                                   facts = .rcg_or(el$facts, list())),
              note = if (ok) "v10.2: 프로그램 라운드 · 강화 사슬 최종 후보 Grade A → A 자격 관문 통과분만 발행 — Judge(PIT 전담) 트리거(스폰 = 세션 Q-Lead)."
                     else "v10.2: A 자격 관문 보류 — 등급 불변 · 요청 미발행(트리거 아님). 사유 해소 뒤 재측정 · 재채점 또는 도훈 지시.")
  if (!ok) req$held <- list(codes = as.list(codes), at = now, by = "round_candidate_gate.R::rcg_route · A 자격 관문")
  p <- file.path(candidate_dir, if (ok) RCG_JR_ELIGIBLE else RCG_JR_HELD)
  if (isTRUE(write)) {
    # 반대쪽 파일이 남아 있으면 지운다(재판정 뒤 두 판정이 한 폴더에 공존하지 않게)
    other <- file.path(candidate_dir, if (ok) RCG_JR_HELD else RCG_JR_ELIGIBLE)
    if (file.exists(other)) unlink(other)
    tmp <- paste0(p, ".tmp_", Sys.getpid())
    writeLines(toJSON(req, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), tmp, useBytes = TRUE)
    if (!isTRUE(file.rename(tmp, p))) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }
  }
  list(action = if (ok) "publish" else "hold", eligible = ok, codes = codes, path = if (isTRUE(write)) p else NA_character_,
       verdict = el, request = req)
}

#' 요청 거두기 — 후보 폴더에 Judge 트리거(judge_request.eligible.json)가 남아 있는데 권위 등급이 A 가 아니면 보류 파일로 바꾼다.
#'   재채점으로 등급이 내려간 뒤에도 측정 시점의 요청이 남아 Judge 가 A 아닌 후보를 집는 일을 막는다(충실구현 변형은 측정 때 요청이 나간다).
#'   트리거 파일이 없으면 아무 일도 하지 않는다. write = FALSE 면 파일을 건드리지 않는다(거둘 것이 있다는 사실만 돌려준다).
#' @return list(withdrawn, path, pending)
rcg_withdraw <- function(candidate_dir, grade = NA_character_, write = FALSE, now = .rcg_now()) {
  candidate_dir <- sub("/+$", "", gsub("\\\\", "/", as.character(candidate_dir)[1]))
  src <- file.path(candidate_dir, RCG_JR_ELIGIBLE)
  if (!file.exists(src)) return(list(withdrawn = FALSE, path = NA_character_, pending = FALSE))
  if (!isTRUE(write)) return(list(withdrawn = FALSE, path = NA_character_, pending = TRUE))
  old <- .rcg_json(src)
  keep <- if (is.list(old)) old[setdiff(names(old), c("status", "held", "note"))] else list(schema = "judge_request_v2", artifacts = candidate_dir)
  req <- c(keep, list(status = paste0("held:", RCG_HOLD_NOT_A),
                      held = list(codes = list(RCG_HOLD_NOT_A), at = now, by = "round_candidate_gate.R::rcg_withdraw",
                                  why = sprintf("권위 등급 = %s(A 아님) — 앞서 나간 요청(%s)을 거둔다", as.character(grade)[1],
                                                as.character(.rcg_or((old %||% list())[["requested_at"]], "시각 미상"))[1])),
                      note = "v10.2: 요청이 나간 뒤 등급이 A 가 아니게 됐다(재채점) — 트리거 아님."))
  p <- file.path(candidate_dir, RCG_JR_HELD); tmp <- paste0(p, ".tmp_", Sys.getpid())
  writeLines(toJSON(req, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), tmp, useBytes = TRUE)
  if (!isTRUE(file.rename(tmp, p))) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }
  unlink(src)
  list(withdrawn = !file.exists(src), path = p, pending = FALSE)
}

#' 마감 — ① 선택 현실 점검 재채점 ② 재채점 뒤 A 면 관문 · A 가 아니면 앞서 나간 요청을 거둔다
#' @param regrade_fn 시험용 주입점(기본 = root 의 selection_regrade.R::sr_regrade) — function(candidate_dir, trial_dirs, root, write)
#' @return list(regrade = sr_regrade 결과(또는 error), route = rcg_route 결과(또는 NULL), status = 한 줄 상태)
#' @param expected   기대 시행 집합 list(n_trials = 등록 시행 수, ids = 등록 시행 id) — sr_regrade 의 관문이 점검 집합과 대조한다(G1 · 11-10).
#'                   NULL = 기대 집합 미지정 → 관문 미통과(fail-closed). 주입 대역이 expected(또는 ...)를 받으면 그대로 넘긴다.
rcg_finalize <- function(candidate_dir, trial_dirs, strategy_id, spec_path = NULL, root = NULL, write = FALSE,
                         now = .rcg_now(), regrade_fn = NULL, gate_loader = NULL, expected = NULL) {
  root <- .rcg_root(root)
  fn <- regrade_fn
  if (!is.function(fn)) {
    f <- file.path(root, "02_Infrastructure", "programs", "selection_regrade.R")
    if (!file.exists(f)) stop("[round_candidate_gate] 재채점 도구 없음: ", f, call. = FALSE)
    e <- new.env(parent = globalenv()); sys.source(f, envir = e, keep.source = FALSE)
    fn <- function(candidate_dir, trial_dirs, root, write, expected = NULL) e$sr_regrade(candidate_dir, trial_dirs, root = root, write = write, expected = expected)
  }
  fa <- names(formals(fn))
  rg <- if (any(c("expected", "...") %in% fa)) fn(candidate_dir, trial_dirs, root, write, expected = expected) else fn(candidate_dir, trial_dirs, root, write)
  # 드라이런(write = FALSE)이면 디스크 권위 기록은 그대로다 — 관문은 재채점 결과 등급으로만 가른다(드라이런 관문은 파일을 쓰지 않는다)
  after <- as.character(.rcg_or(rg$grade_after, NA_character_))[1]
  #   재채점이 대상 밖(not_grade_v3 · hard_fail · no_contract)이면 관문에 태우지 않는다 — 선택 관문을 거치지 않은 등급으로 발행하지 않는다
  rt <- NULL
  if (rg$status %in% c("ok", "not_sweep") && identical(after, "A"))
    rt <- rcg_route(candidate_dir, strategy_id, spec_path = spec_path, root = root, write = write, now = now, gate_loader = gate_loader)
  # 재채점 뒤 A 가 아니면, 측정 시점에 나간 요청이 남아 있을 수 있다 — 거둔다(쓰기 모드에서만)
  wd <- NULL
  if (rg$status %in% c("ok", "not_sweep") && !identical(after, "A")) wd <- rcg_withdraw(candidate_dir, after, write = write, now = now)
  st <- sprintf("regrade %s(%s→%s) · gate %s%s%s%s",as.character(.rcg_or(rg$status, "?")), as.character(.rcg_or(rg$grade_before, "NA")),
                as.character(.rcg_or(after, "NA")), if (is.null(rt)) "skip" else rt$action,
                if (!is.null(rt) && length(rt$codes)) paste0(":", paste(rt$codes, collapse = "+")) else "",
                if (isTRUE(wd$withdrawn)) " · 앞선 요청 거둠" else "",
                ## (G1 재수리) 기대 집합 없이 부른 마감은 스윕 후보가 늘 관문 미통과다 — 관문이 그 사유로 막았으면 재채점 결과 안에만 묻히지 않게
                ##   상태 줄(등록부 · finalize.json)에도 싣는다. 관문이 다른 사유로 갈렸거나 스윕이 아니면 붙이지 않는다.
                if ((!is.list(expected) || !length(expected)) && grepl("기대 시행 집합 미지정", paste(as.character(unlist(rg$reason)), collapse = " "), fixed = TRUE))
                  " · 기대 시행 집합 미지정(선택 관문 미통과 · 호출부가 expected 를 넘겨야 한다)" else "")
  list(regrade = rg, route = rt, withdraw = wd, status = st)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  W <- "--write" %in% a; a <- setdiff(a, "--write")
  if (length(a) >= 2L) {
    r <- rcg_route(a[1L], a[2L], spec_path = if (length(a) >= 3L) a[3L] else NULL, write = W)
    cat(sprintf("[round_candidate_gate] %s%s%s\n", r$action, if (length(r$codes)) paste0(" · ", paste(r$codes, collapse = "+")) else "",
                if (W && !is.na(r$path)) paste0(" · ", r$path) else " · 드라이런"))
  } else cat("[round_candidate_gate] 사용: round_candidate_gate.R <후보 폴더> <strategy_id> [<칸 사양 json>] [--write]\n")
}
