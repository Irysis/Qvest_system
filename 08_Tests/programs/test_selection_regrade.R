#!/usr/bin/env Rscript
#==============================================================================
# test_selection_regrade.R — 스윕형 최종 후보의 선택 현실 점검 재채점 도구(등급 v3.4)
#   대상: 02_Infrastructure/programs/selection_regrade.R
#   본다: 드라이런은 아무것도 쓰지 않는다 · 쓰기는 권위 기록의 정해진 필드만 바꾸고 원본을 한 번 보존한다 · 등급 = 계약 재채점과 같다 ·
#         관문 미통과면 A 아님 사유에 gate:selection_rc · 스윕이 아닌 기록 · hard_fail 기록은 건드리지 않는다 · 두 번 돌려도 같다.
#   격리: 실측 산출물 1건을 임시 폴더로 복사해 그 사본만 고친다(운영 산출물 무접촉). 실측 산출물이 없으면 건너뛴다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
args <- commandArgs(trailingOnly = FALSE)
me <- sub("^--file=", "", args[grep("^--file=", args)][1])
ROOT <- NA_character_
for (p in c(dirname(dirname(dirname(me))), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.na(p) || !nzchar(p)) next
  p <- gsub("\\\\", "/", p)
  if (file.exists(file.path(p, "02_Infrastructure", "programs", "selection_regrade.R"))) { ROOT <- p; break }
}
if (is.na(ROOT)) stop("저장소 루트를 찾지 못했다")
pass <- 0L; fail <- 0L; skipped <- 0L
chk <- function(name, cond) {
  ok <- isTRUE(tryCatch(cond, error = function(e) { cat("     오류:", conditionMessage(e), "\n"); FALSE }))
  if (ok) pass <<- pass + 1L else fail <<- fail + 1L
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", name))
}
DIR <- file.path(ROOT, "stage_artifacts/replication/20260905_095537_1276/remeasure_close_t1_5562284e")
need <- c("02_nav.csv", "03_period_returns.csv", "05_benchmark_returns.csv", "06_metrics.csv", "07_benchmark_compare.csv", "authoritative_remeasure.json")
if (!all(file.exists(file.path(DIR, need)))) {
  skipped <- 1L
  cat("  [skip] 실측 산출물 없음 —", DIR, "\n")
} else {
  E <- new.env(parent = globalenv())
  sys.source(file.path(ROOT, "02_Infrastructure", "programs", "selection_regrade.R"), envir = E, keep.source = FALSE)
  TD <- tempfile("sr_test_"); dir.create(TD)
  mk <- function(id, mut = identity) {
    d <- file.path(TD, id); dir.create(d)
    for (f in need) file.copy(file.path(DIR, f), file.path(d, f))
    A <- fromJSON(file.path(d, "authoritative_remeasure.json"), simplifyVector = FALSE)
    A <- mut(A)
    writeLines(toJSON(A, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null"), file.path(d, "authoritative_remeasure.json"), useBytes = TRUE)
    d
  }
  cand <- mk("cand")
  P0 <- fread(file.path(DIR, "03_period_returns.csv"))
  set.seed(8L)
  vars <- vapply(1:3, function(i) {
    d <- file.path(TD, paste0("var", i)); dir.create(d)
    Pi <- copy(P0); Pi[, ret_net := ret_net + rnorm(.N, 0, 0.0005)]
    fwrite(Pi, file.path(d, "03_period_returns.csv")); file.copy(file.path(DIR, "05_benchmark_returns.csv"), file.path(d, "05_benchmark_returns.csv")); d
  }, character(1))
  md5 <- function(p) unname(as.character(tools::md5sum(p)))
  ap <- file.path(cand, "authoritative_remeasure.json"); m0 <- md5(ap)
  A0 <- fromJSON(ap, simplifyVector = FALSE)

  r_dry <- E$sr_regrade(cand, vars, root = ROOT, write = FALSE)
  chk("T01 드라이런: 판정은 내고 아무것도 쓰지 않는다(권위 기록 md5 불변 · 점검 파일 없음)",
      identical(r_dry$status, "ok") && !isTRUE(r_dry$written) && identical(md5(ap), m0) && !file.exists(file.path(cand, "selection_reality_check.json")))
  r <- E$sr_regrade(cand, vars, root = ROOT, write = TRUE)
  A1 <- fromJSON(ap, simplifyVector = FALSE)
  chk("T02 쓰기: 관문 기록이 선택 현실 점검으로 바뀐다(dsr_gate_applied = FALSE · selection_gate · selection_check · 시행 4)",
      isTRUE(r$written) && identical(A1$selection_gate$mode, "reality_check") && identical(A1$dsr_gate_applied, FALSE) &&
        identical(as.integer(A1$selection_check$n_trials), 4L) && identical(A1$selection_gate$ok, r$gate_ok))
  chk("T03 원본은 한 번 보존되고(직전 md5 기록 일치) 점검 전문이 폴더에 남는다",
      file.exists(file.path(cand, "authoritative_remeasure.pre_selection_regrade.json")) &&
        identical(md5(file.path(cand, "authoritative_remeasure.pre_selection_regrade.json")), m0) &&
        identical(A1$selection_regrade$prior_md5, m0) && file.exists(file.path(cand, "selection_reality_check.json")))
  GE <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/contracts/grade_v3.R"), envir = GE, keep.source = FALSE))))
  v3 <- GE$gv3_score_dir(cand, ROOT, GE$gv3_ctx(ROOT), gates = c(selection_rc = isTRUE(r$gate_ok)))
  chk("T04 새 등급 = 계약이 같은 관문으로 다시 낸 등급(재채점 도구는 채점식을 갖지 않는다)",
      identical(r$grade_after, as.character(v3$grade_v3)) && identical(A1$essence_grade, r$grade_after) && identical(A1$grade_v3$grade, r$grade_after))
  chk("T05 관문 미통과 ⇔ A 아님 사유에 gate:selection_rc (그리고 구 관문 gate:dsr_sweep 은 사라진다)",
      (("gate:selection_rc" %in% unlist(A1$grade_v3$blocked_by)) == !isTRUE(r$gate_ok)) && !("gate:dsr_sweep" %in% unlist(A1$grade_v3$blocked_by)))
  chk("T06 바꾸지 않는 필드는 그대로다(전략 id · 측정 규약 · 구 5조건 판정 · 지표 블록 · 시행 수 · DSR 수치)",
      identical(A1$strategy_id, A0$strategy_id) && identical(A1$measurement_regime, A0$measurement_regime) && identical(A1$grade_v921, A0$grade_v921) &&
        identical(A1$essence, A0$essence) && identical(A1$n_trials_cumulative, A0$n_trials_cumulative) && identical(A1$dsr, A0$dsr))
  chk("T07 수혜 표식: 규칙 변경 전에 잰 기록인지 · 등급이 올랐는지를 기록한다(이 사본은 오르지 않았으므로 FALSE)",
      isTRUE(A1$selection_regrade$measured_before_rule_change) && identical(A1$selection_regrade$benefits_from_rule_change, FALSE) &&
        identical(A1$selection_regrade$prior_essence_grade, as.character(A0$essence_grade)))
  m1 <- md5(file.path(cand, "authoritative_remeasure.pre_selection_regrade.json"))
  r2 <- E$sr_regrade(cand, vars, root = ROOT, write = TRUE)
  A2 <- fromJSON(ap, simplifyVector = FALSE)
  chk("T08 두 번 돌려도 등급 · 판정이 같고 보존 원본은 처음 것 그대로다(이력 1건)",
      identical(r2$grade_after, r$grade_after) && identical(r2$gate_ok, r$gate_ok) &&
        identical(md5(file.path(cand, "authoritative_remeasure.pre_selection_regrade.json")), m1) && length(A2$selection_regrade$history) == 1L)
  ch <- mk("chain", function(A) { A$selection_type <- "chain"; A })
  mc <- md5(file.path(ch, "authoritative_remeasure.json"))
  rc <- E$sr_regrade(ch, vars, root = ROOT, write = TRUE)
  chk("T09 스윕이 아닌 기록은 건드리지 않는다(사유 반환 · md5 불변)", identical(rc$status, "not_sweep") && identical(md5(file.path(ch, "authoritative_remeasure.json")), mc))
  hf <- mk("hard", function(A) { A$hard_fail <- TRUE; A })
  chk("T10 judge hard_fail 기록은 건드리지 않는다", identical(E$sr_regrade(hf, vars, root = ROOT, write = TRUE)$status, "hard_fail"))
  chk("T11 권위 기록이 없는 폴더는 멈춘다", inherits(try(E$sr_regrade(vars[1], vars, root = ROOT), silent = TRUE), "try-error"))
  unlink(TD, recursive = TRUE)
}
cat(sprintf("\n%s\n", toJSON(list(test = "test_selection_regrade", pass = pass, fail = fail, skipped = skipped), auto_unbox = TRUE)))
quit(status = if (fail > 0L) 1L else 0L)
