#!/usr/bin/env Rscript
#==============================================================================
# grade_v3_backfill.R — 저장된 권위 산출물의 등급을 등급 v3 로 소급한다 (MC7 · v10.01 2026-10-13)
#
# 왜: 등급 v3 가 권위 등급이 됐다(decision_register GRADE-V3-PROMOTE). 새 측정은 essence_score 가 v3 를 내지만,
#   저장된 authoritative_remeasure.json 의 essence_grade 는 구 5조건 판정(v921)이다. 소비자(2계층 풀 B+ 하한 ·
#   재채점 일치 검사 · 보고)가 같은 등급 체계를 읽도록 저장분을 v3 로 다시 적는다.
# 무엇을 쓰나(파일당): essence_grade ← v3 · grade_scheme = "grade_v3" · grade_v921 ← 직전 essence_grade ·
#   grade_v3 ← 근거 블록(essence_score 와 같은 형식) · reasons 앞에 v3 요약 · grade_v3_backfill ← 출처(직전 md5 · 시각 · 도구).
# 규칙: 계약 미경유(직전 essence_grade 결측) = 그대로 · judge hard_fail 주입 = F · 스윕형 선정이면 저장된 DSR 로 A 관문(gates) ·
#   이미 grade_scheme = grade_v3 = 건너뜀(멱등) · 동결된 QEPM WT 산출물(stage_artifacts/WT_*) = 제외 · 채점 재료 없는 파일 = 제외.
# 안전: 기본 드라이런 · --write 일 때만 쓴다 · 쓰기 전 원본 전문을 gz JSONL 보관본에 넣는다 · 파일은 임시 파일 → 이름 바꾸기.
#   (저장소가 git 으로 추적하므로 git 이력도 원본을 갖는다 — 보관본은 그 위의 두 번째 사본.)
# 사용: Rscript 02_Infrastructure/programs/grade_v3_backfill.R [--root R] [--workers 6] [--limit N] [--write]
# 산출: s0_grade_v3/backfill_manifest.csv · (쓰기 시) s0_grade_v3/backfill_originals_<날짜>.jsonl.gz
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(parallel) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
#' 규칙 변경 수혜 표식 — 저장분 재채점(규칙 판 올림)이 측정 때 등급보다 등급을 올렸는가.
#'   측정 때 등급 = 표식이 들고 다니는 measured_grade → 없으면 재채점 이력의 가장 이른 등급 → 없으면 직전 등급.
#'   한 번 오른 기록은 다음 재채점에서 '변화 없음'이어도 수혜로 남는다(측정 때 등급 이하로 내려가야 풀린다).
#'   소비 = A 자격 관문 상시 보류 rule_change_beneficiary(reinforcement/rf_runner_gates.R) · 규칙 = measurement-graduation §3b.
gv3b_benefit_mark <- function(A, new, old, old_rv, rules_ver, at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")) {
  rank <- c(F = 0L, C = 1L, B = 2L, A = 3L)
  h0 <- A$grade_v3_backfill$history %||% list()
  m0 <- as.character(A$rule_change_benefit$measured_grade %||% (if (length(h0)) h0[[1]]$essence_grade else old) %||% old)
  list(benefit = isTRUE(unname(rank[new] > rank[m0])), measured_grade = m0, rules_version = rules_ver, prior_rules_version = old_rv,
       prior_essence_grade = old, at = at)
}
#' 저장된 팩터 조정 알파 블록이 낡았는가 — 요인 표(내용 md5)가 바뀌면 규칙 판이 같아도 그 기록은 다시 채점해야 한다
#'   (2026-11-10 요인 빌더 v1.1 — 표본 거르기 미래참조 수리로 2016-07 이후 요인이 바뀐다). 대상 = 저장 fa 블록에 factor_md5 가 있는
#'   기록(= 요인 epoch 와 같은 축에서 노치 평가를 탄 것)이고 그 값이 현행 요인 md5 와 다른 것. 현행 md5 를 모르면(요인 문맥 미가동) 낡음으로 보지 않는다.
#'   (G1 · 11-10) 요인 문맥이 없던 때 채점된 기록 — 요인 파일 다중 쓰기 창 · [5c] 중도 실패 밤에는 gv3_fa_ctx 가 factor_unavailable 을 내고
#'   그 기록의 fa 블록에는 md5 · epoch 가 없다(노치 없이 굳는다). 저장 fa$status = factor_unavailable · md5 없음이고, 지금 요인 문맥이 있으며
#'   (md5 · epoch 를 안다) 기록의 측정 축(measurement_axis.epoch)이 현행 요인 epoch 와 같을 때만 다시 채점한다 — 다른 축 · 축을 모르는 기록은
#'   노치 자격이 없으므로 건드리지 않는다(전 기록 재채점 폭주 방지). fa_epoch_now 를 모르면 이 가지는 쓰지 않는다.
gv3b_fa_stale <- function(A, fa_md5_now, fa_epoch_now = NULL) {
  fa <- A$grade_v3$fa
  now <- as.character(fa_md5_now %||% NA_character_)[1]; old <- as.character(fa$factor_md5 %||% NA_character_)[1]
  st <- as.character(fa$status %||% NA_character_)[1]
  if (identical(st, "factor_unavailable") && (is.na(old) || !nzchar(old))) {
    ra <- tryCatch(as.character(A[["measurement_axis"]][["epoch"]] %||% NA_character_)[1], error = function(e) NA_character_); fe0 <- as.character(fa_epoch_now %||% NA_character_)[1]
    return(!is.na(now) && nzchar(now) && !is.na(fe0) && nzchar(fe0) && !is.na(ra) && nzchar(ra) && identical(ra, fe0))
  }
  ## 요인 표는 한 측정 축(epoch)의 것이다 — 기록의 축이 요인 축과 같을 때만 팩터 조정 알파가 등급에 닿는다(다른 축은 노치 자격이 없다).
  ##   다른 축 기록에도 factor_md5 는 참고로 적히므로, 축을 보지 않으면 요인 표가 바뀔 때마다 전 기록(수천 건)을 다시 채점하게 된다.
  re <- as.character(fa$record_epoch %||% NA_character_)[1]; fe <- as.character(fa$factor_epoch %||% NA_character_)[1]
  same_axis <- !is.na(re) && nzchar(re) && !is.na(fe) && nzchar(fe) && identical(re, fe)
  same_axis && !is.na(now) && nzchar(now) && !is.na(old) && nzchar(old) && !identical(old, now)
}
#' 조건부 호환 판(grade_v3.json::rules_version_compatible_unless · v3.5 · 11-13) — 그 판의 저장 기록은 조건에 걸릴 때만 다시 채점한다.
#'   조건 어휘: cr_notch_strong = 저장 grade_v3.cr_notch_basis 가 strong(CR '강함' 가점이 유지된 기록 — v3.5 가 바꾸는 분기를 지나는 유일한 기록 ·
#'   사전등록 04_Research/01_reports/grade_v35_cr_beta_selection_20261113/PREREG.md §3). 모르는 조건이면 멈춘다(조용히 건너뛰지 않는다).
#' @return TRUE = 건너뛴다(호환 · 판 표식 유지) · FALSE = 다시 채점(그 판이 목록에 없거나 조건에 걸림)
GV3B_UNLESS_VOCAB <- c("cr_notch_strong")
gv3b_compat_unless <- function(A, old_rv, unless) {
  if (is.null(unless) || !length(unless) || is.na(old_rv) || !old_rv %in% names(unless)) return(FALSE)
  cond <- as.character(unless[[old_rv]])[1]
  if (!cond %in% GV3B_UNLESS_VOCAB) stop("[backfill] rules_version_compatible_unless 조건 어휘 밖: ", cond, " (", paste(GV3B_UNLESS_VOCAB, collapse = " | "), ")")
  hit <- switch(cond, cr_notch_strong = identical(as.character(A$grade_v3$cr_notch_basis %||% NA_character_)[1], "strong"))
  !isTRUE(hit)
}
#' 교체를 걸친 측정의 불완전 기록(v3.5 · 11-13 · GRADE-CR-NOTCH-BETA-SELECTION-20261113) — essence_score.R 을 교체 전에 싣고 grade_v3.R 을
#'   교체 뒤에 늦게 실은 프로세스(긴 측정 · 무인 레인 — essence_score.R::.essence_v3 가 첫 채점 때 grade_v3.R 을 싣는다)는 v3.5 등급을 내지만
#'   옛 .essence_v3_record 로 적어 v3.5 기록 필드(selection_control · 시가총액 × β 비율 · 노치 근거)가 빠진다. 판 표식이 현행이어도
#'   그 필드가 없으면 다시 채점한다(원인 record_fields_incomplete · 등급 계산은 같으므로 값은 그대로 · 근거 필드만 채워진다).
#' @param need_sc 현행 설정이 선택 짝 필드를 요구하는가(grade_v3.R::gv3_selection_control(cfg) = size_beta)
#' @return TRUE = 다시 채점
gv3b_record_incomplete <- function(A, old_rv, rules_ver, need_sc) {
  isTRUE(need_sc) && identical(as.character(old_rv)[1], as.character(rules_ver)[1]) &&
    identical(as.character(A$grade_v3$status %||% NA_character_)[1], "ok") && is.null(A$grade_v3$selection_control)
}
#' 선택 현실 점검이 관문이던 기록(selection_gate$mode = reality_check)의 관문 재판정 (G1 · 11-10)
#'   저장 ok 를 그대로 쓰지 않는다 — 저장된 점검 요약(selection_check)을 현행 설정(grade_v3.json::selection_bias · src_cfg())으로 다시 본다:
#'   저장 판정 통과(재계산할 수 없는 시행 집합 검사 · 후보 일치 등을 담는다) ∧ 설정 판 같음 ∧ 조정 p ≤ 현행 alpha ∧ (PBO 가 관문이면 현행 문턱 이하).
#'   설정을 못 읽거나 값이 없으면 통과가 아니다(fail-closed). 조정 p 는 alpha 와 무관하게 계산되므로 현행 alpha 로 다시 재는 것이 정확하다.
#' @param scfg src_cfg() 결과(NULL = 판독 실패)
gv3b_selection_gate <- function(A, scfg) {
  no <- function(why) list(ok = FALSE, reason = why)
  sc <- A$selection_check; sg <- A$selection_gate
  num <- function(x) { v <- suppressWarnings(as.numeric(x %||% NA_real_)[1]); if (length(v) && is.finite(v)) v else NA_real_ }
  if (!is.list(scfg) || is.null(scfg$version) || !is.finite(num(scfg$alpha))) return(no("선택 점검 설정 판독 불가"))
  if (!isTRUE(sg$ok)) return(no(paste0("저장 판정 미통과: ", as.character(sg$reason %||% "")[1])))
  if (!is.list(sc)) return(no("저장 점검 요약 없음"))
  if (!identical(as.character(sc$version %||% NA_character_)[1], as.character(scfg$version)[1]))
    return(no(paste0("설정 판 불일치(", as.character(sc$version %||% "NA")[1], " ≠ ", scfg$version, ") — 새 판으로 다시 점검해야 한다")))
  p <- num(sc$p_adj_candidate)
  if (!(is.finite(p) && p <= scfg$alpha)) return(no(sprintf("조정 p %s > 현행 alpha %.4f", format(p), scfg$alpha)))
  if (identical(as.character(scfg$pbo_role %||% "")[1], "gate")) {
    pv <- num(sc$pbo)
    if (!is.finite(pv) || !is.finite(num(scfg$pbo_flag_above)) || pv > scfg$pbo_flag_above) return(no("PBO 관문 미통과(현행 문턱)"))
  }
  list(ok = TRUE, reason = sprintf("조정 p %.4f <= 현행 alpha %.4f(%s)", p, scfg$alpha, scfg$version))
}
args <- commandArgs(trailingOnly = TRUE)
argv <- function(k, d = NULL) { i <- match(k, args); if (is.na(i) || i == length(args)) d else args[i + 1L] }
WRITE <- "--write" %in% args
ROOT0 <- argv("--root", NULL)
for (p in c(ROOT0, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.null(p) || !nzchar(p)) next
  if (file.exists(file.path(p, "02_Infrastructure/contracts/grade_v3.R"))) { ROOT0 <- gsub("\\\\", "/", p); break }
}
source(file.path(ROOT0, "02_Infrastructure/contracts/grade_v3.R"))
ROOT <- .gv3_root(ROOT0)
OUT <- argv("--out", file.path(ROOT, "04_Research/01_reports/l1_prescription_redesign_20261013/s0_grade_v3"))
WORKERS <- as.integer(argv("--workers", "6")); LIMIT <- as.integer(argv("--limit", "0"))
## (v3.5 · 11-13 · 판단 T4 C-20261113-071) 규칙 판 재채점을 자료 판 변경(요인 md5 · 선택 점검 설정)과 섞지 않는 실행:
##   --dirs <파일> = 그 목록(저장소 상대 산출물 폴더 · 한 줄에 하나)만 대상 · --no-data-triggers = 요인 · 선택 설정 계기를 끈다(규칙 판 경로만).
DIRS_FILE <- argv("--dirs", NULL)
NO_DATA_TRIG <- "--no-data-triggers" %in% args
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ── 1) 대상 ──
all_ar <- list.files(file.path(ROOT, "stage_artifacts"), pattern = "^authoritative_remeasure\\.json$", recursive = TRUE, full.names = TRUE)
all_ar <- gsub("\\\\", "/", all_ar)
rel <- sub(paste0("^", ROOT, "/"), "", all_ar)
keep <- !grepl("^stage_artifacts/WT_", rel)
need <- c("02_nav.csv", "03_period_returns.csv", "05_benchmark_returns.csv", "06_metrics.csv", "07_benchmark_compare.csv")
has <- vapply(dirname(all_ar), function(d) all(file.exists(file.path(d, need))), logical(1))
todo <- all_ar[keep & has]
if (!is.null(DIRS_FILE)) {                                                # 목록 제한 — 목록의 폴더가 대상에 없으면 멈춘다(조용히 줄지 않게)
  want <- trimws(readLines(DIRS_FILE, warn = FALSE, encoding = "UTF-8")); want <- sub("/+$", "", gsub("\\\\", "/", want[nzchar(want)]))
  have <- sub("/authoritative_remeasure\\.json$", "", sub(paste0("^", ROOT, "/"), "", todo))
  miss <- setdiff(want, have)
  if (length(miss)) stop("[backfill] --dirs 목록 중 대상에 없는 폴더(WT · 재료 없음 · 경로 오기): ", paste(miss, collapse = ", "))
  todo <- todo[have %in% want]
}
cat(sprintf("[backfill] 권위 산출물 %d · WT 제외 %d · 재료 없음 %d · 대상 %d%s · 모드 %s%s\n", length(all_ar), sum(!keep),
            sum(keep & !has), length(todo), if (!is.null(DIRS_FILE)) paste0("(목록 ", basename(DIRS_FILE), ")") else "",
            if (WRITE) "쓰기" else "드라이런", if (NO_DATA_TRIG) " · 자료 계기 끔" else ""))
if (LIMIT > 0L) todo <- head(todo, LIMIT)

# ── 2) 파일 1개 → 새 JSON 문안(병렬 · 쓰기는 주 프로세스만) ──
one <- function(p) tryCatch({
  txt <- paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  A <- fromJSON(txt, simplifyVector = FALSE)
  old <- if (is.null(A$essence_grade)) NA_character_ else as.character(A$essence_grade)
  base <- list(path = p, old_grade = old, old_md5 = unname(as.character(tools::md5sum(p))))
  # 이미 v3 — 규칙 판이 현행과 같으면 건너뜀(멱등) · 다르면 다시 채점(규칙 개정 소급 · 2026-10-13 GRADE-V3-CR-STRONG-SELECTION · CRISIS-DEF-LT2020)
  rescore <- identical(A$grade_scheme, "grade_v3")
  old_rv <- if (rescore) as.character(A$grade_v3$rules_version %||% "v3.0") else NA_character_
  ## (v3.4 · 11-10) 채점이 같은 판(grade_v3.json::rules_version_compatible)의 저장분도 건너뛴다 — v3.4 는 선택 점검을 제출한 측정의
  ##   관문만 바꾸므로 v3.3 저장분을 다시 채점할 이유가 없다(소급 승격 없음 · 도훈 11-10).
  ## (11-10) 요인 표가 바뀐 기록은 규칙 판이 같아도 다시 채점한다(저장 fa 블록의 factor_md5 ≠ 현행) — gv3b_fa_stale
  ## (G1 · 11-10) 요인 문맥이 없던 때(factor_unavailable · md5 없음) 채점된 같은 축 기록도 문맥이 돌아오면 다시 채점한다(FA_EPOCH)
  fa_stale <- rescore && gv3b_fa_stale(A, FA_MD5, FA_EPOCH)
  if (NO_DATA_TRIG) fa_stale <- FALSE                                 # (v3.5 · T4 C-071) 규칙 판 경로만 — 요인 판 재채점은 따로 돌린다
  old_fa_md5 <- as.character(A$grade_v3$fa$factor_md5 %||% NA_character_)[1]   # 재채점 전 값(아래에서 grade_v3 블록을 새로 쓴다)
  old_cr_notch <- as.character(A$grade_v3$cr_notch_basis %||% NA_character_)[1]  # 재채점 전 노치용 CR(v3.5 보고 · 사전등록 표 T3)
  ## (G1 · 11-10) 선택 현실 점검 기록 — 현행 설정으로 다시 본 관문이 저장 판정과 다르면(alpha · 판 재보정) 규칙 판이 같아도 다시 채점한다
  is_rc <- identical(as.character(A$selection_gate$mode %||% ""), "reality_check")
  SG <- if (is_rc) gv3b_selection_gate(A, SRC_CFG) else NULL
  sel_stale <- rescore && is_rc && !identical(isTRUE(SG$ok), isTRUE(A$selection_gate$ok))
  if (NO_DATA_TRIG) sel_stale <- FALSE
  rec_inc <- rescore && gv3b_record_incomplete(A, old_rv, RULES_VER, NEED_SC)   # (v3.5 · 11-13) 교체를 걸친 측정 — 판 표식은 현행인데 v3.5 필드가 없다
  ## (v3.5 · 11-13) 조건부 호환 판 — 조건(cr_notch_strong)에 걸리지 않는 기록은 채점이 같으므로 건너뛴다(판 표식 유지 · 사전등록 §3)
  if (rescore && !fa_stale && !sel_stale && !rec_inc && (identical(old_rv, RULES_VER) || old_rv %in% RULES_COMPAT || gv3b_compat_unless(A, old_rv, RULES_UNLESS)))
    return(c(base, status = "already", new_grade = old))
  ## (v3.5 · 판단 T4 C-20261113-071) 다시 채점하는 원인을 모두 남긴다 — 요인 판 · 선택 설정 · 규칙 판이 한 번에 걸리면 셋 다(원인을 섞어 읽지 않게)
  rule_trig <- !rescore || !(identical(old_rv, RULES_VER) || old_rv %in% RULES_COMPAT || gv3b_compat_unless(A, old_rv, RULES_UNLESS))
  causes <- c(if (fa_stale) (if (is.na(old_fa_md5)) "factor_ctx_restored" else "factor_md5_changed"), if (sel_stale) "selection_cfg_changed",
              if (rule_trig) (if (rescore) "rules_version" else "scheme_promote"), if (rec_inc) "record_fields_incomplete")
  if (is.na(old)) return(c(base, status = "no_contract", new_grade = NA_character_))
  hf <- isTRUE(A$hard_fail)
  gates <- NULL
  if (is_rc) {
    gates <- c(selection_rc = isTRUE(SG$ok))                          # v3.4: 선택 현실 점검이 관문이던 기록 — 저장 판정 ∧ 현행 설정 재판정(G1)
    A$selection_gate$rejudged <- list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), ok = isTRUE(SG$ok), reason = as.character(SG$reason),
                                      cfg_version = as.character(SRC_CFG$version %||% NA_character_)[1], prior_ok = isTRUE(A$selection_gate$ok))
    A$selection_gate$ok <- isTRUE(SG$ok)
  } else if (isTRUE(A$dsr_gate_applied)) {
    dv <- suppressWarnings(as.numeric(A$dsr %||% NA)[1])
    gates <- c(dsr_sweep = isTRUE(is.finite(dv) && dv >= DSR_MIN))
  }
  v3 <- if (hf) NULL else gv3_score_dir(dirname(p), ROOT, CTX, gates = gates)
  rec <- if (hf) list(status = "not_applicable", reason = "hard_fail 주입(judge)") else
    E$.essence_v3_record(v3, TRUE, FALSE)
  rec$rules_version <- RULES_VER                                     # 판 표식(hard_fail 기록에도 — 없으면 매번 다시 채점된다)
  new <- if (hf) "F" else as.character(v3$grade_v3)
  if (!hf && (length(new) != 1L || is.na(new))) return(c(base, status = "v3_na", new_grade = NA_character_))
  pre <- if (hf) "" else paste0(gv3_reason_head(v3), " | v921 ", old, ": ")   # 머리 문장 단일 출처(grade_v3.R · 새 측정과 같은 함수)
  A$essence_grade <- new
  A$grade_scheme <- "grade_v3"
  if (!rescore) A$grade_v921 <- old                                  # 재채점이면 구 5조건 판정 기록은 그대로 둔다
  A$grade_v3 <- rec
  # 재채점이면 앞선 v3 요약 머리(v3: … | v921 X: )를 걷어내고 새 머리를 단다(머리가 겹겹이 쌓이지 않게)
  rs <- as.character(A$reasons %||% "")
  if (rescore) rs <- sub("^v3: [^|]*\\| v921 [^:]*: ", "", rs)
  pre <- if (rescore && !hf) sub("\\| v921 [^:]*: $", paste0("| v921 ", as.character(A$grade_v921 %||% "NA"), ": "), pre) else pre
  A$reasons <- paste0(pre, rs)
  ## 규칙 변경 수혜 표식(2026-11-10 · 도훈 결정 GRADE-V33-NOTCH-ASOF-AND-RULE-CHANGE-PROCEDURE-20261110 · measurement-graduation §3b):
  ##   규칙 판 재채점은 그 판이 발효되기 전에 잰 기록에 새 규칙을 입히는 일이다. 측정 때 등급(기록된 가장 이른 등급)보다 오르면 수혜 기록 —
  ##   A 자격 관문이 상시 보류한다(rf_runner_gates.R rule_change_beneficiary · 발효 뒤 재측정 전). 표식은 다음 재채점에서 측정 때 등급
  ##   이하로 내려가야 풀린다(한 번 오른 뒤 '변화 없음'으로 지워지지 않게 measured_grade 를 들고 다닌다).
  if (rescore && !hf) { A$rule_change_benefit <- gv3b_benefit_mark(A, new, old, old_rv, RULES_VER); A$rule_change_benefit$causes <- as.list(causes) }
  A$grade_v3_backfill <- list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), tool = "02_Infrastructure/programs/grade_v3_backfill.R",
                              decision = if (rescore) paste0("decision_register ", .gv3_rv_decision(RULES_VER), "(규칙 판 재채점 ", old_rv, " → ", RULES_VER, ")")
                                         else "decision_register GRADE-V3-PROMOTE",
                              rules_version = RULES_VER, prior_rules_version = old_rv,
                              trigger = if (fa_stale && is.na(old_fa_md5)) "factor_ctx_restored" else if (fa_stale) "factor_md5_changed"
                                        else if (sel_stale) "selection_cfg_changed" else if (rescore) "rules_version" else "scheme_promote",
                              causes = as.list(causes),                                  # 원인 전부(trigger = 첫 원인 · 종전 필드 유지)
                              prior_factor_md5 = if (fa_stale && !is.na(old_fa_md5)) old_fa_md5 else NULL,   # 재채점 전 md5(G1 · 종전엔 새 블록의 md5 를 읽었다)
                              ## (v3.5 · T4 C-071) 재채점 시점의 자료 판 — 저장 수익(측정 시점 판)과 대조 · 요인(이 시점 판)이 섞일 수 있음을 기록으로 남긴다
                              inputs = list(factor_md5 = FA_MD5, rawdata = RAW_FP, data_triggers = !NO_DATA_TRIG,
                                            stored_returns = "측정 시점 판(03_period_returns.csv · 재채점은 수익을 다시 재지 않는다)"),
                              prior_essence_grade = old, prior_md5 = base$old_md5,
                              history = c(A$grade_v3_backfill$history %||% list(),
                                          if (rescore) list(list(rules_version = old_rv, essence_grade = old)) else list()))
  nt <- toJSON(A, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null")
  chk <- fromJSON(nt, simplifyVector = FALSE)
  if (!identical(as.character(chk$essence_grade), new) || !identical(chk$grade_scheme, "grade_v3"))
    stop("왕복 검증 실패")
  c(base, status = "ok", new_grade = new, S = if (hf) NA_real_ else v3$S, band = if (hf) NA_character_ else v3$band,
    notch = if (hf) 0L else v3$notch, fa_notch = if (hf) 0L else as.integer(v3$fa_notch %||% 0L),
    fa_t_min = if (hf) NA_real_ else as.numeric(v3$fa$t_min %||% NA_real_),
    causes = paste(causes, collapse = "+"),
    old_cr_notch = old_cr_notch, new_cr_notch = if (hf) NA_character_ else as.character(v3$cr_notch %||% NA_character_)[1],
    notch_basis = if (hf) NA_character_ else as.character(v3$cr_notch_basis %||% NA_character_)[1],
    mc8_share_se = if (hf) NA_real_ else as.numeric(v3$mc8$share_beats_size_exposure %||% NA_real_)[1],
    mc8_share_sb = if (hf) NA_real_ else as.numeric(v3$mc8$share_beats_size_beta %||% NA_real_)[1],
    mc8_share_sb_path = if (hf) NA_real_ else as.numeric(v3$mc8$share_beats_size_beta_path %||% NA_real_)[1],
    exposure_varies = if (hf) NA else as.logical(v3$mc8$exposure_varies %||% NA)[1],
    beta_leg = if (hf) NA_real_ else as.numeric(v3$mc8$beta_leg %||% NA_real_)[1],
    rho_median = if (hf) NA_real_ else as.numeric(v3$mc8$rho_median %||% NA_real_)[1],
    old_text = txt, new_text = as.character(nt))
}, error = function(err) list(path = p, status = "error", err = conditionMessage(err)))

init_worker <- quote({
  suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
  source(file.path(ROOT, "02_Infrastructure/contracts/grade_v3.R"))
  .e <- .gv3_deps(ROOT); E <- .e
  CTX <- gv3_ctx(ROOT)
  DSR_MIN <- .e$.graduation_params(refresh = TRUE, root = ROOT)$dsr_min
  RULES_VER <- as.character(CTX$cfg$rules_version %||% "v3.0")      # 현행 규칙 판(grade_v3.json) — 다른 판의 v3 기록은 다시 채점
  RULES_COMPAT <- as.character(unlist(CTX$cfg$rules_version_compatible %||% character(0)))   # 채점이 같은 앞선 판(건너뜀)
  RULES_UNLESS <- CTX$cfg$rules_version_compatible_unless %||% list()                          # 조건부 호환 판(v3.5 · 조건에 걸릴 때만 재채점)
  NEED_SC <- identical(gv3_selection_control(CTX$cfg), "size_beta")    # v3.5 — 기록에 선택 짝 필드를 요구하는 판(교체를 걸친 불완전 기록 재채점)
  for (.k in names(RULES_UNLESS)) if (!as.character(RULES_UNLESS[[.k]])[1] %in% GV3B_UNLESS_VOCAB)
    stop("[backfill] rules_version_compatible_unless 조건 어휘 밖: ", .k, " = ", RULES_UNLESS[[.k]])
  FA_MD5 <- as.character(CTX$fa$md5 %||% NA_character_)[1]          # 현행 요인 표 내용 md5(팩터 조정 알파 문맥 · 미가동이면 NA)
  FA_EPOCH <- as.character(CTX$fa$epoch %||% NA_character_)[1]      # 현행 요인 epoch(미가동이면 NA — 요인 문맥 복구 가지를 끈다)
  RAW_FP <- local({ fi <- file.info(file.path(ROOT, ".cache/RAWDATA.parquet"))                 # 재채점 시점 RAWDATA 판(크기 · 수정 시각 — MC8 이 읽는 판)
    if (is.na(fi$size)) NA_character_ else paste(fi$size, format(fi$mtime, "%Y-%m-%dT%H:%M:%S%z")) })
  ## 선택 현실 점검 설정(현행) — 판독 실패면 NULL(그 기록들의 선택 관문은 미통과 · fail-closed)
  .se <- new.env(parent = globalenv())
  SRC_CFG <- tryCatch({ sys.source(file.path(ROOT, "02_Infrastructure/contracts/selection_reality_check.R"), envir = .se, keep.source = FALSE)
                        .se$src_cfg(ROOT) }, error = function(e) NULL)
  NULL })
t0 <- Sys.time()
res <- if (WORKERS > 1L) {
  source(file.path(ROOT, "02_Infrastructure/ops/qv_psock.R"))   # 포트 예약 회피(금칙 ⑧ · 11-09)
  cl <- qv_psock_cluster(WORKERS)
  tryCatch({
    clusterExport(cl, c("ROOT", "%||%", "init_worker", "gv3b_benefit_mark", "gv3b_fa_stale", "gv3b_selection_gate", "gv3b_compat_unless", "GV3B_UNLESS_VOCAB", "gv3b_record_incomplete", "NO_DATA_TRIG"))
    invisible(clusterEvalQ(cl, eval(init_worker)))
    parLapplyLB(cl, todo, one)
  }, finally = stopCluster(cl))
} else { eval(init_worker, envir = globalenv()); lapply(todo, one) }
cat(sprintf("[backfill] 채점 %d건 · %.1f분\n", length(res), as.numeric(difftime(Sys.time(), t0, units = "mins"))))

# ── 3) 쓰기(주 프로세스) ──
st <- vapply(res, function(z) as.character(z$status), "")
if (WRITE) {
  RCG <- new.env(parent = globalenv())                              # Judge 트리거 거두기 정본(rcg_withdraw) — 쓰기 전에 싣는다(실패 = 쓰지 않고 멈춘다)
  sys.source(file.path(ROOT, "02_Infrastructure/programs/round_candidate_gate.R"), envir = RCG, keep.source = FALSE)
  if (!is.function(RCG$rcg_withdraw)) stop("[backfill] round_candidate_gate.R::rcg_withdraw 없음 — 강등 뒤 Judge 트리거를 거둘 수 없어 쓰지 않는다")
  arc <- file.path(OUT, sprintf("backfill_originals_%s.jsonl.gz", format(Sys.time(), "%Y%m%d_%H%M%S")))
  gz <- gzfile(arc, open = "w", encoding = "UTF-8")
  n_w <- 0L
  tryCatch({
    for (z in res[st == "ok"]) {
      writeLines(toJSON(list(path = sub(paste0("^", ROOT, "/"), "", z$path), md5 = z$old_md5, text = z$old_text), auto_unbox = TRUE), gz)
    }
  }, finally = close(gz))
  for (i in which(st == "ok")) {
    z <- res[[i]]
    if (!identical(unname(as.character(tools::md5sum(z$path))), z$old_md5)) { res[[i]]$status <- "changed_since_read"; next }
    tmp <- paste0(z$path, ".tmp_gv3")
    writeLines(z$new_text, tmp, useBytes = TRUE)
    if (!file.rename(tmp, z$path)) { unlink(tmp); res[[i]]$status <- "write_failed"; next }
    res[[i]]$new_md5 <- unname(as.character(tools::md5sum(z$path))); n_w <- n_w + 1L
    ## (v3.5 · 11-13 · 판단 T4 C-20261113-072) 강등 뒤처리 — 새 등급이 A 가 아니면 앞서 나간 Judge 트리거(judge_request.eligible.json)를
    ##   보류 파일로 거둔다(round_candidate_gate.R::rcg_withdraw · 정본 1곳). 'Grade A 전 Judge 금지'(절대 규칙)가 재채점 뒤에도 지켜지게.
    if (!identical(as.character(z$new_grade), "A")) {
      wd <- tryCatch(RCG$rcg_withdraw(dirname(z$path), z$new_grade, write = TRUE), error = function(e) list(withdrawn = FALSE, err = conditionMessage(e)))
      res[[i]]$judge_withdrawn <- isTRUE(wd$withdrawn)
      if (!is.null(wd$err)) cat(sprintf("[backfill] ⚠ Judge 트리거 거두기 실패 %s: %s\n", z$path, wd$err))
    }
  }
  cat(sprintf("[backfill] 씀 %d · 원본 보관 %s\n", n_w, arc))
}
man <- rbindlist(lapply(res, function(z) data.table(path = sub(paste0("^", ROOT, "/"), "", z$path), status = z$status,
                                                     old_grade = z$old_grade %||% NA_character_, new_grade = z$new_grade %||% NA_character_,
                                                     S = as.numeric(z$S %||% NA), band = as.character(z$band %||% NA), notch = as.integer(z$notch %||% NA),
                                                     fa_notch = as.integer(z$fa_notch %||% NA), fa_t_min = as.numeric(z$fa_t_min %||% NA),
                                                     causes = as.character(z$causes %||% NA),
                                                     old_cr_notch = as.character(z$old_cr_notch %||% NA), new_cr_notch = as.character(z$new_cr_notch %||% NA),
                                                     notch_basis = as.character(z$notch_basis %||% NA), mc8_share_se = as.numeric(z$mc8_share_se %||% NA),
                                                     mc8_share_sb = as.numeric(z$mc8_share_sb %||% NA), mc8_share_sb_path = as.numeric(z$mc8_share_sb_path %||% NA),
                                                     exposure_varies = as.logical(z$exposure_varies %||% NA), beta_leg = as.numeric(z$beta_leg %||% NA),
                                                     rho_median = as.numeric(z$rho_median %||% NA), judge_withdrawn = isTRUE(z$judge_withdrawn),
                                                     old_md5 = z$old_md5 %||% NA_character_, new_md5 = z$new_md5 %||% NA_character_,
                                                     err = z$err %||% NA_character_)), fill = TRUE)
fwrite(man, file.path(OUT, if (WRITE) "backfill_manifest.csv" else "backfill_manifest_dryrun.csv"))
cat("[backfill] 상태:", paste(names(table(man$status)), table(man$status), sep = "=", collapse = " · "), "\n")
ok <- man[status %in% c("ok")]
if (nrow(ok)) { cat("[backfill] 전이(구 → v3):\n"); print(dcast(ok[, .N, by = .(old_grade, new_grade)], old_grade ~ new_grade, value.var = "N", fill = 0)) }
