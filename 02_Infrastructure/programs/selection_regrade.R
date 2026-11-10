#!/usr/bin/env Rscript
#==============================================================================
# selection_regrade.R — 스윕형 선정의 최종 후보를 선택 현실 점검으로 다시 채점한다 (등급 v3.4 · v10.2 2026-11-10)
#
# 왜: 칸을 잴 때는 시행 집합이 아직 다 모이지 않았다 — 그래서 측정 시점의 등급은 종전 DSR 관문(경과 규정)으로 난다.
#   라운드 · 사슬이 끝나 시행 집합이 확정되면, 사전등록한 최종 후보 1칸에 대해 그 집합 전체로 선택 현실 점검을 돌리고
#   (contracts/selection_reality_check.R) 그 결과를 관문으로 권위 등급을 다시 낸다(도훈 11-10 "DSR은 (나) 적용" · DSR-GATE-FORM-20261110).
# 무엇을 쓰나(후보 산출 폴더):
#   selection_reality_check.json                      — 점검 결과 전문
#   authoritative_remeasure.json                      — essence_grade · grade_v3 · reasons 머리 · dsr_gate_applied = FALSE ·
#                                                        selection_gate · selection_check · selection_regrade(출처 · 직전 등급 · 직전 md5 · 수혜 표식)
#   authoritative_remeasure.pre_selection_regrade.json — 첫 재채점 직전 원본(한 번만)
# 규칙: 대상 = 등급 v3 기록 · 스윕형 · judge hard_fail 아님. 그 밖은 건드리지 않고 사유를 돌려준다. 기본 드라이런(write = FALSE).
#   채점식은 계약 그대로다(gv3_score_dir · 관문만 selection_rc). 후보가 아닌 칸에는 쓰지 않는다 — 호출자(라운드 닫기)가 최종 후보만 넘긴다.
#   ★수혜 표식: 규칙이 바뀌기 전에 이미 측정돼 있던 기록이 이 재채점으로 등급이 오르면 benefits_from_rule_change = TRUE 로 남긴다
#     (규칙 변경 뒤 이미 본 결과가 득을 본 사실을 숨기지 않는다 — 설계 README §8-3 ④).
#     비교 기준 = 측정 당시 등급(selection_regrade$measured_grade · 첫 재채점 전 원본) · 한 번 TRUE 면 재실행이 내리지 못한다(R3 · 11-10).
# 사용: Rscript 02_Infrastructure/programs/selection_regrade.R <후보 폴더> <시행 폴더 1> [<시행 폴더 2> ...] --expect-n <등록 시행 수> [--expect-ids a,b] [--write]
#   ★기대 시행 집합(G1 · 11-10): 관문은 등록 시행 수 · id 와 점검 집합을 대조한다 — 기대를 주지 않으면 관문 미통과(fail-closed).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.sr_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.sr_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, "02_Infrastructure", "contracts", "selection_reality_check.R"))) return(p)
  }
  stop("[selection_regrade] 프로젝트 루트 해석 실패", call. = FALSE)
}
.SR_GRADE_RANK <- c(F = 0L, C = 1L, B = 2L, A = 3L)

#' 후보 1칸 재채점
#' @param candidate_dir 후보 산출 폴더(authoritative_remeasure.json + 계약 CSV)
#' @param trial_dirs    시행 집합의 산출 폴더(후보 포함 여부 무관 — 자동 포함)
#' @param write         TRUE 일 때만 파일을 쓴다
#' @param expected      기대 시행 집합 list(n_trials = 등록 시행 수, ids = 등록 시행 id(산출 폴더 basename)) — 호출자(라운드 닫기)가
#'                      등록부 · 사슬 원장에서 낸다(G1 · 11-10). NULL = 기대 집합 미지정 = 관문 미통과(fail-closed · 사유 기록).
#'                      trial_dirs 로 기대를 대신하지 않는다(넘긴 집합으로 넘긴 집합을 검증하는 셈이 된다).
#' @return list(status, grade_before, grade_after, gate_ok, reason, check, written)
sr_regrade <- function(candidate_dir, trial_dirs, root = NULL, write = FALSE, cfg = NULL, ctx = NULL, expected = NULL) {
  root <- .sr_root(root)
  candidate_dir <- gsub("\\\\", "/", as.character(candidate_dir)[1])
  ap <- file.path(candidate_dir, "authoritative_remeasure.json")
  if (!file.exists(ap)) stop("[selection_regrade] 권위 기록 없음: ", ap, call. = FALSE)
  txt <- paste(readLines(ap, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  A <- fromJSON(txt, simplifyVector = FALSE)
  old <- as.character(.sr_or(A$essence_grade, NA_character_))
  skip <- function(st, why) list(status = st, grade_before = old, grade_after = old, gate_ok = NA, reason = why, check = NULL, written = FALSE)
  if (!identical(A$grade_scheme, "grade_v3")) return(skip("not_grade_v3", "등급 v3 기록이 아니다"))
  if (isTRUE(A$hard_fail)) return(skip("hard_fail", "judge hard_fail 주입 기록"))
  if (!identical(as.character(.sr_or(A$selection_type, "")), "sweep")) return(skip("not_sweep", "스윕형 선정이 아니다(선택 관문 없음)"))
  if (is.na(old)) return(skip("no_contract", "계약 미경유 기록"))

  SE <- new.env(parent = globalenv())
  sys.source(file.path(root, "02_Infrastructure", "contracts", "selection_reality_check.R"), envir = SE, keep.source = FALSE)
  GE <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(sys.source(file.path(root, "02_Infrastructure", "contracts", "grade_v3.R"), envir = GE, keep.source = FALSE))))
  if (is.null(cfg)) cfg <- SE$src_cfg(root)
  if (is.null(ctx)) ctx <- GE$gv3_ctx(root)

  chk <- SE$src_check_dirs(trial_dirs, candidate_dir, cfg = cfg, sensitivity = TRUE)
  bc <- fread(file.path(candidate_dir, "07_benchmark_compare.csv"), showProgress = FALSE)
  nc <- intersect(c("metric_name", "name"), names(bc))[1]; vc <- intersect(c("active_value", "value", "metric_value"), names(bc))[1]
  port_t <- suppressWarnings(as.numeric(bc[get(nc) == "Portfolio_Alpha_t_NW_lag3"][[vc]][1]))
  g <- SE$src_gate(chk, port_t, cfg, expected = expected)
  v3 <- GE$gv3_score_dir(candidate_dir, root, ctx, gates = c(selection_rc = isTRUE(g$ok)))
  new <- as.character(v3$grade_v3)
  if (length(new) != 1L || is.na(new)) stop("[selection_regrade] 등급 v3 산출 실패(NA)", call. = FALSE)

  E <- GE$.gv3_deps(root)
  rec <- E$.essence_v3_record(v3, TRUE, FALSE)
  n1 <- function(x) { v <- suppressWarnings(as.numeric(.sr_or(x, NA_real_))[1]); if (is.finite(v)) v else NA_real_ }
  pb <- .sr_or(chk$pbo, list())
  srec <- list(version = chk$version, n_trials = n1(chk$n_trials), n_obs = n1(chk$n_obs), candidate_t = n1(chk$candidate_t),
               p_adj_candidate = n1(chk$p_adj_candidate), alpha = n1(chk$alpha), required_t = n1(chk$required_t),
               effective_independent_trials = n1(chk$effective_independent_trials), pbo = n1(pb$pbo),
               pbo_role = as.character(.sr_or(pb$role, NA)), pbo_flagged = isTRUE(pb$flagged), set_hash = chk$set_hash,
               expected_n_trials = n1(expected$n_trials), expected_n_ids = length(unlist(expected$ids)),
               n_dropped_zero_variance = length(unlist(chk$dropped_zero_variance)))
  measured <- as.character(.sr_or(A$measured_at, .sr_or(A$remeasured_at, .sr_or(A$generated_at, NA_character_))))
  eff <- as.character(fromJSON(cfg$path, simplifyVector = FALSE)$selection_bias$effective_from)
  seen_before <- !is.na(measured) && nzchar(measured) && substr(measured, 1L, 10L) < eff
  ## ★수혜 표식은 끈질기다(R3 · 11-10 · measurement-graduation §3b) — 비교 기준은 '직전 등급'(재실행이면 이미 오른 값)이 아니라
  ##   측정 당시 등급(measured_grade · 첫 재채점 전 원본)이다. 한 번 TRUE 인 표식은 재실행이 FALSE 로 내리지 못한다.
  ##   (grade_v3_backfill.R::gv3b_benefit_mark 의 measured_grade 보존과 같은 원리.) 측정 당시 등급 = 기록이 들고 다니는 measured_grade →
  ##   없으면(옛 도구가 쓴 기록) 보존 원본(pre_selection_regrade)의 등급 → 첫 재채점이면 직전 등급. 재실행인데 어디서도 못 읽으면 NA —
  ##   수혜 아님을 보일 수 없으므로 발효 전 기록이면 표식 TRUE(fail-closed).
  prev <- A[["selection_regrade"]]; first <- is.null(prev)
  prev_benefit <- is.list(prev) && isTRUE(prev[["benefits_from_rule_change"]])
  m0 <- old; m0_src <- "prior_essence_grade(첫 재채점)"
  if (!first) {
    m0 <- if (is.list(prev)) as.character(.sr_or(prev[["measured_grade"]], NA_character_))[1] else NA_character_
    m0_src <- "measured_grade"
    if (is.na(m0) || !(m0 %in% names(.SR_GRADE_RANK))) {
      pp <- file.path(candidate_dir, "authoritative_remeasure.pre_selection_regrade.json")
      m0 <- if (file.exists(pp)) tryCatch(as.character(.sr_or(fromJSON(pp, simplifyVector = FALSE)[["essence_grade"]], NA_character_))[1],
                                          error = function(e) NA_character_) else NA_character_
      m0_src <- "pre_selection_regrade.json"
    }
  }
  if (is.na(m0) || !(m0 %in% names(.SR_GRADE_RANK))) { m0 <- NA_character_; m0_src <- "unreadable" }
  up <- !is.na(m0) && isTRUE(.SR_GRADE_RANK[[new]] > .SR_GRADE_RANK[[m0]])
  benefit <- isTRUE(prev_benefit) || (seen_before && (is.na(m0) || up))
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  A$essence_grade <- new
  A$grade_v3 <- rec
  rs <- sub("^v3: [^|]*\\| v921 [^:]*: ", "", as.character(.sr_or(A$reasons, "")))
  A$reasons <- paste0(GE$gv3_reason_head(v3), " | v921 ", as.character(.sr_or(A$grade_v921, "NA")), ": ", rs)
  A$dsr_gate_applied <- FALSE
  A$selection_gate <- list(mode = "reality_check", ok = isTRUE(g$ok), reason = as.character(g$reason))
  A$selection_check <- srec
  A$selection_regrade <- list(
    at = now, tool = "02_Infrastructure/programs/selection_regrade.R", decision = "decision_register DSR-GATE-FORM-20261110",
    rules_version = as.character(.sr_or(v3$rules_version, NA)), prior_essence_grade = old,
    prior_md5 = unname(as.character(tools::md5sum(ap))), prior_dsr_gate_applied = isTRUE(fromJSON(txt, simplifyVector = FALSE)$dsr_gate_applied),
    measured_at = measured, measured_before_rule_change = seen_before, measured_grade = m0, measured_grade_source = m0_src,
    benefits_from_rule_change = benefit,
    check_file = "selection_reality_check.json",
    history = c(.sr_or(A$selection_regrade$history, list()), if (!first) list(list(at = A$selection_regrade$at, essence_grade = old)) else list()))
  nt <- toJSON(A, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null")
  rt <- fromJSON(nt, simplifyVector = FALSE)
  if (!identical(as.character(rt$essence_grade), new) || !identical(rt$selection_gate$mode, "reality_check")) stop("[selection_regrade] 왕복 검증 실패", call. = FALSE)

  written <- FALSE
  if (isTRUE(write)) {
    SE$src_write(chk, file.path(candidate_dir, "selection_reality_check.json"))
    keep <- file.path(candidate_dir, "authoritative_remeasure.pre_selection_regrade.json")
    if (!file.exists(keep)) writeLines(txt, keep, useBytes = TRUE)
    tmp <- paste0(ap, ".tmp_", Sys.getpid())
    writeLines(as.character(nt), tmp, useBytes = TRUE)
    if (!isTRUE(file.rename(tmp, ap))) { file.copy(tmp, ap, overwrite = TRUE); unlink(tmp) }
    written <- TRUE
  }
  list(status = "ok", grade_before = old, grade_after = new, gate_ok = isTRUE(g$ok), reason = as.character(g$reason),
       benefits_from_rule_change = benefit, measured_grade = m0, check = chk, written = written)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  W <- "--write" %in% a; a <- setdiff(a, "--write")
  ## 기대 시행 집합(G1) — --expect-n <등록 시행 수> · --expect-ids <id1,id2,...> (둘 다 없으면 관문 미통과)
  take <- function(k) { i <- match(k, a); if (is.na(i) || i == length(a)) return(NULL); v <- a[i + 1L]; a <<- a[-c(i, i + 1L)]; v }
  en <- take("--expect-n"); ei <- take("--expect-ids")
  ex <- if (is.null(en) && is.null(ei)) NULL else
    list(n_trials = if (is.null(en)) NULL else as.integer(en), ids = if (is.null(ei)) NULL else strsplit(ei, ",", fixed = TRUE)[[1]])
  if (length(a) >= 2L) {
    r <- sr_regrade(a[1L], a[-1L], write = W, expected = ex)
    cat(sprintf("[selection_regrade] %s · 등급 %s → %s · 관문 %s · %s%s%s\n", r$status, r$grade_before, r$grade_after,
                if (isTRUE(r$gate_ok)) "통과" else if (is.na(r$gate_ok)) "해당 없음" else "미통과", r$reason,
                if (isTRUE(r$benefits_from_rule_change)) " · ★규칙 변경 수혜 기록" else "", if (W) " · 기록함" else " · 드라이런"))
  } else cat("[selection_regrade] 사용: selection_regrade.R <후보 폴더> <시행 폴더 ...> --expect-n <등록 시행 수> [--expect-ids a,b,...] [--write]\n")
}
