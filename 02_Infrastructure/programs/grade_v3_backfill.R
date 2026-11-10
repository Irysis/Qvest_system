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
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ── 1) 대상 ──
all_ar <- list.files(file.path(ROOT, "stage_artifacts"), pattern = "^authoritative_remeasure\\.json$", recursive = TRUE, full.names = TRUE)
all_ar <- gsub("\\\\", "/", all_ar)
rel <- sub(paste0("^", ROOT, "/"), "", all_ar)
keep <- !grepl("^stage_artifacts/WT_", rel)
need <- c("02_nav.csv", "03_period_returns.csv", "05_benchmark_returns.csv", "06_metrics.csv", "07_benchmark_compare.csv")
has <- vapply(dirname(all_ar), function(d) all(file.exists(file.path(d, need))), logical(1))
todo <- all_ar[keep & has]
cat(sprintf("[backfill] 권위 산출물 %d · WT 제외 %d · 재료 없음 %d · 대상 %d · 모드 %s\n", length(all_ar), sum(!keep),
            sum(keep & !has), length(todo), if (WRITE) "쓰기" else "드라이런"))
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
  old_fa_md5 <- as.character(A$grade_v3$fa$factor_md5 %||% NA_character_)[1]   # 재채점 전 값(아래에서 grade_v3 블록을 새로 쓴다)
  ## (G1 · 11-10) 선택 현실 점검 기록 — 현행 설정으로 다시 본 관문이 저장 판정과 다르면(alpha · 판 재보정) 규칙 판이 같아도 다시 채점한다
  is_rc <- identical(as.character(A$selection_gate$mode %||% ""), "reality_check")
  SG <- if (is_rc) gv3b_selection_gate(A, SRC_CFG) else NULL
  sel_stale <- rescore && is_rc && !identical(isTRUE(SG$ok), isTRUE(A$selection_gate$ok))
  if (rescore && !fa_stale && !sel_stale && (identical(old_rv, RULES_VER) || old_rv %in% RULES_COMPAT)) return(c(base, status = "already", new_grade = old))
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
  if (rescore && !hf) A$rule_change_benefit <- gv3b_benefit_mark(A, new, old, old_rv, RULES_VER)
  A$grade_v3_backfill <- list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), tool = "02_Infrastructure/programs/grade_v3_backfill.R",
                              decision = if (rescore) paste0("decision_register ", .gv3_rv_decision(RULES_VER), "(규칙 판 재채점 ", old_rv, " → ", RULES_VER, ")")
                                         else "decision_register GRADE-V3-PROMOTE",
                              rules_version = RULES_VER, prior_rules_version = old_rv,
                              trigger = if (fa_stale && is.na(old_fa_md5)) "factor_ctx_restored" else if (fa_stale) "factor_md5_changed"
                                        else if (sel_stale) "selection_cfg_changed" else if (rescore) "rules_version" else "scheme_promote",
                              prior_factor_md5 = if (fa_stale && !is.na(old_fa_md5)) old_fa_md5 else NULL,   # 재채점 전 md5(G1 · 종전엔 새 블록의 md5 를 읽었다)
                              prior_essence_grade = old, prior_md5 = base$old_md5,
                              history = c(A$grade_v3_backfill$history %||% list(),
                                          if (rescore) list(list(rules_version = old_rv, essence_grade = old)) else list()))
  nt <- toJSON(A, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null")
  chk <- fromJSON(nt, simplifyVector = FALSE)
  if (!identical(as.character(chk$essence_grade), new) || !identical(chk$grade_scheme, "grade_v3"))
    stop("왕복 검증 실패")
  c(base, status = "ok", new_grade = new, S = if (hf) NA_real_ else v3$S, band = if (hf) NA_character_ else v3$band,
    notch = if (hf) 0L else v3$notch, fa_notch = if (hf) 0L else as.integer(v3$fa_notch %||% 0L),
    fa_t_min = if (hf) NA_real_ else as.numeric(v3$fa$t_min %||% NA_real_), old_text = txt, new_text = as.character(nt))
}, error = function(err) list(path = p, status = "error", err = conditionMessage(err)))

init_worker <- quote({
  suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
  source(file.path(ROOT, "02_Infrastructure/contracts/grade_v3.R"))
  .e <- .gv3_deps(ROOT); E <- .e
  CTX <- gv3_ctx(ROOT)
  DSR_MIN <- .e$.graduation_params(refresh = TRUE, root = ROOT)$dsr_min
  RULES_VER <- as.character(CTX$cfg$rules_version %||% "v3.0")      # 현행 규칙 판(grade_v3.json) — 다른 판의 v3 기록은 다시 채점
  RULES_COMPAT <- as.character(unlist(CTX$cfg$rules_version_compatible %||% character(0)))   # 채점이 같은 앞선 판(건너뜀)
  FA_MD5 <- as.character(CTX$fa$md5 %||% NA_character_)[1]          # 현행 요인 표 내용 md5(팩터 조정 알파 문맥 · 미가동이면 NA)
  FA_EPOCH <- as.character(CTX$fa$epoch %||% NA_character_)[1]      # 현행 요인 epoch(미가동이면 NA — 요인 문맥 복구 가지를 끈다)
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
    clusterExport(cl, c("ROOT", "%||%", "init_worker", "gv3b_benefit_mark", "gv3b_fa_stale", "gv3b_selection_gate"))
    invisible(clusterEvalQ(cl, eval(init_worker)))
    parLapplyLB(cl, todo, one)
  }, finally = stopCluster(cl))
} else { eval(init_worker, envir = globalenv()); lapply(todo, one) }
cat(sprintf("[backfill] 채점 %d건 · %.1f분\n", length(res), as.numeric(difftime(Sys.time(), t0, units = "mins"))))

# ── 3) 쓰기(주 프로세스) ──
st <- vapply(res, function(z) as.character(z$status), "")
if (WRITE) {
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
  }
  cat(sprintf("[backfill] 씀 %d · 원본 보관 %s\n", n_w, arc))
}
man <- rbindlist(lapply(res, function(z) data.table(path = sub(paste0("^", ROOT, "/"), "", z$path), status = z$status,
                                                     old_grade = z$old_grade %||% NA_character_, new_grade = z$new_grade %||% NA_character_,
                                                     S = as.numeric(z$S %||% NA), band = as.character(z$band %||% NA), notch = as.integer(z$notch %||% NA),
                                                     fa_notch = as.integer(z$fa_notch %||% NA), fa_t_min = as.numeric(z$fa_t_min %||% NA),
                                                     old_md5 = z$old_md5 %||% NA_character_, new_md5 = z$new_md5 %||% NA_character_,
                                                     err = z$err %||% NA_character_)), fill = TRUE)
fwrite(man, file.path(OUT, if (WRITE) "backfill_manifest.csv" else "backfill_manifest_dryrun.csv"))
cat("[backfill] 상태:", paste(names(table(man$status)), table(man$status), sep = "=", collapse = " · "), "\n")
ok <- man[status %in% c("ok")]
if (nrow(ok)) { cat("[backfill] 전이(구 → v3):\n"); print(dcast(ok[, .N, by = .(old_grade, new_grade)], old_grade ~ new_grade, value.var = "N", fill = 0)) }
