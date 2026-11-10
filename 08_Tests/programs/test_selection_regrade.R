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
  EX4 <- list(n_trials = 4L, ids = c("cand", "var1", "var2", "var3"))   # 기대 시행 집합(G1) — 후보 + 변형 3
  ap <- file.path(cand, "authoritative_remeasure.json"); m0 <- md5(ap)
  A0 <- fromJSON(ap, simplifyVector = FALSE)

  r_dry <- E$sr_regrade(cand, vars, root = ROOT, write = FALSE, expected = EX4)
  chk("T01 드라이런: 판정은 내고 아무것도 쓰지 않는다(권위 기록 md5 불변 · 점검 파일 없음)",
      identical(r_dry$status, "ok") && !isTRUE(r_dry$written) && identical(md5(ap), m0) && !file.exists(file.path(cand, "selection_reality_check.json")))
  r <- E$sr_regrade(cand, vars, root = ROOT, write = TRUE, expected = EX4)
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
  r2 <- E$sr_regrade(cand, vars, root = ROOT, write = TRUE, expected = EX4)
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
  ## (G1 · 11-10) 기대 시행 집합 — 후보 1칸만 넘기거나 기대 없이 부르면 관문이 아니다(fail-closed · 드라이런으로 판정만)
  c1 <- mk("one")
  r1 <- E$sr_regrade(c1, character(0), root = ROOT, write = FALSE, expected = EX4)
  chk(sprintf("T12 등록 시행 4 인데 후보 1칸만 넘긴 재채점 → 관문 미통과 · 사유 = 등록 시행(%s) · A 아님", r1$reason),
      identical(r1$status, "ok") && identical(r1$gate_ok, FALSE) && grepl("< 등록 시행 4", r1$reason, fixed = TRUE) && !identical(r1$grade_after, "A"))
  r0 <- E$sr_regrade(cand, vars, root = ROOT, write = FALSE)
  chk(sprintf("T13 기대 시행 집합 없이 부르면 관문 미통과(%s)", r0$reason), identical(r0$gate_ok, FALSE) && grepl("기대 시행", r0$reason))
  rid <- E$sr_regrade(cand, vars[1:2], root = ROOT, write = FALSE, expected = list(ids = c("cand", "var1", "var2", "var3")))
  chk(sprintf("T14 등록 시행 id 가 빠진 집합 → 관문 미통과(%s)", rid$reason), identical(rid$gate_ok, FALSE) && grepl("누락", rid$reason))
  r4 <- E$sr_regrade(cand, vars, root = ROOT, write = FALSE, expected = EX4)
  chk(sprintf("T15 대조: 기대와 맞는 집합은 구조 검사를 지나 조정 p 로 판정된다(%s)", r4$reason), grepl("^조정 p", r4$reason))
  ## (R3 · 11-10) 수혜 표식은 끈질기다(measurement-graduation §3b) — 측정 당시 등급(measured_grade)과 비교하고 재실행이 TRUE 를 FALSE 로 내리지 못한다.
  ##   등급이 오르는 사본 = 측정 당시 등급을 재채점 결과보다 낮게 적은 사본(재채점 등급은 CSV 로 나므로 그대로다). 재채점 등급이 F 면 오를 칸이 없어 건너뛴다.
  RK <- c(F = 0L, C = 1L, B = 2L, A = 3L)
  if (identical(r$grade_after, "F")) { skipped <- skipped + 1L; cat("  [skip] T16~T21 — 재채점 등급 F(오를 칸 없음)\n") } else {
    low <- "F"
    up_d <- mk("up", function(A) { A$essence_grade <- low; A })
    apu <- file.path(up_d, "authoritative_remeasure.json")
    u1 <- E$sr_regrade(up_d, vars, root = ROOT, write = TRUE, expected = EX4); U1 <- fromJSON(apu, simplifyVector = FALSE)
    chk(sprintf("T16 발효 전 기록이 재채점으로 오르면(%s → %s) 수혜 표식 TRUE · 측정 당시 등급 = %s", low, u1$grade_after, low),
        RK[[u1$grade_after]] > RK[[low]] && isTRUE(u1$benefits_from_rule_change) && isTRUE(U1$selection_regrade$benefits_from_rule_change) &&
          identical(U1$selection_regrade$measured_grade, low))
    u2 <- E$sr_regrade(up_d, vars, root = ROOT, write = TRUE, expected = EX4); U2 <- fromJSON(apu, simplifyVector = FALSE)
    chk(sprintf("T17 두 번째 재채점(직전 등급 %s = 이미 오른 값)도 표식을 유지한다 · 측정 당시 등급 %s 그대로 · 직전 등급은 사실대로", u2$grade_before, low),
        identical(u2$grade_before, u1$grade_after) && isTRUE(u2$benefits_from_rule_change) && isTRUE(U2$selection_regrade$benefits_from_rule_change) &&
          identical(U2$selection_regrade$measured_grade, low) && identical(U2$selection_regrade$prior_essence_grade, u1$grade_after))
    mu <- md5(apu)
    u3 <- E$sr_regrade(up_d, vars, root = ROOT, write = FALSE, expected = EX4)
    chk("T18 세 번째 드라이런도 표식 TRUE 를 돌려주고 디스크는 그대로다", isTRUE(u3$benefits_from_rule_change) && !isTRUE(u3$written) && identical(md5(apu), mu))
    ## 옛 도구가 두 번 돌아 표식을 이미 FALSE 로 덮은 기록(measured_grade 필드 없음) — 보존 원본(pre_selection_regrade)의 등급으로 되살린다
    lg <- U2; lg$selection_regrade$measured_grade <- NULL; lg$selection_regrade$benefits_from_rule_change <- FALSE
    writeLines(toJSON(lg, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null"), apu, useBytes = TRUE)
    u4 <- E$sr_regrade(up_d, vars, root = ROOT, write = TRUE, expected = EX4); U4 <- fromJSON(apu, simplifyVector = FALSE)
    chk("T19 옛 도구가 FALSE 로 덮은 기록 → 보존 원본의 측정 당시 등급과 비교해 표식 TRUE 로 되돌린다",
        isTRUE(u4$benefits_from_rule_change) && isTRUE(U4$selection_regrade$benefits_from_rule_change) && identical(U4$selection_regrade$measured_grade, low))
    ## 측정 당시 등급을 어디서도 읽을 수 없는 재실행(필드 없음 · 보존 원본 없음) — 수혜 아님을 보일 수 없으니 표식 TRUE(fail-closed)
    lg2 <- U4; lg2$selection_regrade$measured_grade <- NULL; lg2$selection_regrade$benefits_from_rule_change <- FALSE
    writeLines(toJSON(lg2, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null"), apu, useBytes = TRUE)
    file.remove(file.path(up_d, "authoritative_remeasure.pre_selection_regrade.json"))
    u5 <- E$sr_regrade(up_d, vars, root = ROOT, write = FALSE, expected = EX4)
    chk("T20 측정 당시 등급 판독 불가인 발효 전 재실행 → 표식 TRUE(fail-closed)", isTRUE(u5$benefits_from_rule_change))
    ## 대조 — 오르지 않은 사본(cand)은 재실행해도 FALSE 그대로 · 측정 당시 등급 = 원래 등급
    chk("T21 [대조] 오르지 않은 기록은 두 번 돌려도 표식 FALSE · 측정 당시 등급 = 원 기록 등급",
        identical(A2$selection_regrade$benefits_from_rule_change, FALSE) && identical(A2$selection_regrade$measured_grade, as.character(A0$essence_grade)) &&
          !isTRUE(r2$benefits_from_rule_change))
    ## [돌연변이] 수리 전 판정식(직전 등급과 비교 · 끈질김 없음)으로 되돌린 사본 → 두 번째 재채점이 표식을 FALSE 로 덮는다(T17 이 그 차이를 본다)
    SRF <- file.path(ROOT, "02_Infrastructure", "programs", "selection_regrade.R")
    s_txt <- readLines(SRF, warn = FALSE, encoding = "UTF-8")
    nd3 <- "benefit <- isTRUE(prev_benefit) || (seen_before && (is.na(m0) || up))"
    h3 <- which(grepl(nd3, s_txt, fixed = TRUE)); ms <- s_txt
    if (length(h3) == 1L) ms[h3] <- sub(nd3, "benefit <- seen_before && isTRUE(.SR_GRADE_RANK[[new]] > .SR_GRADE_RANK[[old]])", ms[h3], fixed = TRUE)
    MSF <- file.path(TD, "sr_mut.R"); writeLines(enc2utf8(ms), MSF, useBytes = TRUE)
    EM <- new.env(parent = globalenv()); sys.source(MSF, envir = EM, keep.source = FALSE)
    up_m <- mk("up_mut", function(A) { A$essence_grade <- low; A })
    invisible(EM$sr_regrade(up_m, vars, root = ROOT, write = TRUE, expected = EX4))
    um2 <- EM$sr_regrade(up_m, vars, root = ROOT, write = TRUE, expected = EX4)
    chk("T22 [돌연변이] 직전 등급 비교로 되돌린 사본 → 두 번째 재채점이 표식을 FALSE 로 덮는다(치환 1곳 성사)",
        length(h3) == 1L && !identical(ms[h3], s_txt[h3]) && identical(um2$benefits_from_rule_change, FALSE))
  }
  unlink(TD, recursive = TRUE)
}

## (G1 재수리 · 11-10) 배선 — 기대 시행 집합이 마감 경로에서 끊기지 않는다(합성 · 실측 산출물 불요 · 임시 루트만)
##   ① rcg_finalize(round_candidate_gate.R)가 expected 를 재채점 함수에 그대로 넘긴다(주입 대역 · 기본 래퍼 둘 다) · 돌연변이로 그 줄을 끊으면 잡힌다
##   ② rc_p4_close 의 기대 집합(rc_p4_expected_trials) = 기준 칸 1 + 포기 아닌 걸음 · id = 산출 폴더 이름 · 호출부가 그 값을 sr_regrade 에 넘긴다
WD <- tempfile("sr_wire_"); dir.create(file.path(WD, "02_Infrastructure", "programs"), recursive = TRUE)   # 임시 루트(.rcg_root 가 운영 루트로 새지 않게)
RCG <- file.path(ROOT, "02_Infrastructure", "programs", "round_candidate_gate.R")
load_rcg <- function(path) { e <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(path, envir = e, keep.source = FALSE)))); e }
G <- load_rcg(RCG)
EXW <- list(n_trials = 5L, ids = c("base", "k1", "k2", "k3", "k4"))
cap <- new.env(); cap$ex <- "unset"
fake_ex <- function(candidate_dir, trial_dirs, root, write, expected = NULL) { cap$ex <- expected
  list(status = "ok", grade_before = "B", grade_after = "B", gate_ok = FALSE, reason = if (is.null(expected)) "기대 시행 집합 미지정(…)" else "조정 p 0.2000 > alpha 0.05") }
fake_dots <- function(candidate_dir, trial_dirs, root, write, ...) { cap$ex <- list(...)$expected; list(status = "not_grade_v3", grade_after = NA) }
fake_old <- function(candidate_dir, trial_dirs, root, write) { cap$ex <- "old"; list(status = "not_grade_v3", grade_after = NA) }
cdir <- file.path(WD, "cand"); dir.create(cdir)
f1 <- G$rcg_finalize(cdir, character(0), "x", root = WD, write = FALSE, regrade_fn = fake_ex, expected = EXW)
chk("W1 rcg_finalize: 주입 대역(expected 인자)에 기대 시행 집합을 그대로 넘긴다", identical(cap$ex, EXW))
cap$ex <- "unset"; invisible(G$rcg_finalize(cdir, character(0), "x", root = WD, write = FALSE, regrade_fn = fake_dots, expected = EXW))
chk("W2 rcg_finalize: ... 를 받는 대역에도 넘긴다", identical(cap$ex, EXW))
cap$ex <- "unset"; f3 <- tryCatch(G$rcg_finalize(cdir, character(0), "x", root = WD, write = FALSE, regrade_fn = fake_old, expected = EXW), error = function(e) e)
chk("W3 rcg_finalize: 4인자 옛 대역은 expected 없이 그대로 부른다(호환)", !inherits(f3, "error") && identical(cap$ex, "old"))
f4 <- G$rcg_finalize(cdir, character(0), "x", root = WD, write = FALSE, regrade_fn = fake_ex)
chk(sprintf("W4 기대 집합 없이 부른 마감이 그 사유로 막히면 상태 줄에 드러난다(%s) · 넘기면 붙지 않는다(%s)", f4$status, f1$status),
    grepl("기대 시행 집합 미지정", f4$status, fixed = TRUE) && !grepl("기대 시행 집합 미지정", f1$status, fixed = TRUE))
## 기본 래퍼(regrade_fn 없음) — 임시 루트의 selection_regrade.R 대역이 받은 expected 를 파일로 남긴다
EXF <- gsub("\\\\", "/", file.path(WD, "seen_expected.json"))
writeLines(c("sr_regrade <- function(candidate_dir, trial_dirs, root = NULL, write = FALSE, expected = NULL) {",
             sprintf("  writeLines(jsonlite::toJSON(expected, auto_unbox = TRUE, null = 'null'), '%s')", EXF),
             "  list(status = 'not_grade_v3', grade_after = NA) }"), file.path(WD, "02_Infrastructure", "programs", "selection_regrade.R"))
invisible(G$rcg_finalize(cdir, character(0), "x", root = WD, write = FALSE, expected = EXW))
seen <- tryCatch(fromJSON(EXF), error = function(e) NULL)
chk("W5 rcg_finalize 기본 래퍼: root 의 sr_regrade 에 expected 를 넘긴다", is.list(seen) && identical(as.integer(seen$n_trials), 5L) && identical(as.character(seen$ids), EXW$ids))
## 돌연변이 — 전달 줄의 expected 를 떼면(소스 텍스트 치환 · 1곳 성사) W1 · W5 가 그 차이를 본다
rcg_txt <- readLines(RCG, warn = FALSE, encoding = "UTF-8")
nd <- "fn(candidate_dir, trial_dirs, root, write, expected = expected) else fn(candidate_dir, trial_dirs, root, write)"
h <- which(grepl(nd, rcg_txt, fixed = TRUE))
mt <- rcg_txt; if (length(h) == 1L) mt[h] <- sub(nd, "fn(candidate_dir, trial_dirs, root, write) else fn(candidate_dir, trial_dirs, root, write)", mt[h], fixed = TRUE)
MF <- file.path(WD, "rcg_mut.R"); writeLines(mt, MF, useBytes = TRUE); GM <- load_rcg(MF)
cap$ex <- "unset"; invisible(GM$rcg_finalize(cdir, character(0), "x", root = WD, write = FALSE, regrade_fn = fake_ex, expected = EXW))
chk("W6 돌연변이: rcg_finalize 의 expected 전달을 뗀 사본은 대역에 기대 집합이 닿지 않는다(W1 이 잡는다) — 치환 1곳 성사",
    length(h) == 1L && !identical(mt[h], rcg_txt[h]) && is.null(cap$ex))

## ② 사슬 닫기의 기대 집합 — p4.R 에서 rc_p4_expected_trials 정의만 구문 트리로 꺼낸다(round_core 전체 적재 없음)
P4 <- file.path(ROOT, "04_Research", "programs", "_lib", "round_core", "v1", "p4.R")
p4_def <- function(txt) { ex <- parse(text = txt, keep.source = FALSE); e <- new.env(parent = baseenv())
  for (x in ex) if (is.call(x) && identical(as.character(x[[1]]), "<-") && identical(as.character(x[[2]]), "rc_p4_expected_trials")) eval(x, e)
  e$rc_p4_expected_trials }
p4_txt <- readLines(P4, warn = FALSE, encoding = "UTF-8")
XT <- p4_def(p4_txt); if (!is.function(XT)) XT <- function(...) list(n_trials = NA_integer_, ids = character(0))   # 정의가 없으면 P 절이 실패로 남는다
res <- list(list(k = 1L, decision = "accept", artifacts = "C:/s/k1_aaa"), list(k = 2L, decision = "reject", artifacts = list("C:/s/k2_bbb")),
            list(k = 3L, decision = "reject", abandoned = TRUE, artifacts = NULL), list(k = 4L, decision = "reject", artifacts = "C:\\s\\k4_ddd\\"))
x1 <- if (is.function(XT)) XT("C:/s/base_000", res) else NULL
chk(sprintf("P1 사슬 기대 집합 = 기준 칸 1 + 포기 아닌 걸음 3 = 4 · id = 산출 폴더 이름(%s)", paste(x1$ids, collapse = ",")),
    is.list(x1) && identical(x1$n_trials, 4L) && identical(x1$ids, c("base_000", "k1_aaa", "k2_bbb", "k4_ddd")))
x2 <- XT("C:/s/base_000", list(list(k = 1L, artifacts = "C:/s/same"), list(k = 2L, artifacts = "C:/s/same"), list(k = 3L, artifacts = NULL)))
chk("P2 중복 · 결측 산출은 id 에서만 접히고 수는 남는다(4) — 시행 목록이 줄면 관문이 '점검 < 등록'으로 막는다",
    identical(x2$n_trials, 4L) && identical(x2$ids, c("base_000", "same")))
chk("P3 걸음 없음 = 기준 칸 1", identical(XT("C:/s/base_000", list())$n_trials, 1L) && identical(XT("C:/s/base_000", NULL)$n_trials, 1L))
SRC_E <- new.env(parent = globalenv())
invisible(capture.output(suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/contracts/selection_reality_check.R"), envir = SRC_E, keep.source = FALSE))))
fake_chk <- list(schema = SRC_E$SRC_SCHEMA, method = SRC_E$SRC_METHOD, version = "v", n_trials = 3L, trial_ids = list("base_000", "k1_aaa", "k2_bbb"), candidate = "k1_aaa")
gx <- tryCatch(SRC_E$src_gate(fake_chk, 0, list(version = "v"), expected = x1), error = function(e) list(ok = NA, reason = conditionMessage(e)))
chk(sprintf("P4 그 기대 집합으로 관문: 포기 아닌 걸음 하나(k4)가 점검에 빠지면 막는다(%s)", gx$reason), !isTRUE(gx$ok) && grepl("< 등록 시행 4", gx$reason, fixed = TRUE))
chk("P5 배선: rc_p4_close 가 그 함수로 기대 집합을 만들어 sr_regrade 에 expected 로 넘긴다(정적)",
    sum(grepl("expected <- rc_p4_expected_trials(st$base_meas$artifacts, st$results)", p4_txt, fixed = TRUE)) == 1L &&
      sum(grepl("e$sr_regrade(.rcp4_abs(fin$artifacts, root), trials, root = root, write = isTRUE(regrade_write), expected = expected)", p4_txt, fixed = TRUE)) == 1L)
nd2 <- "kept <- Filter(function(r) !isTRUE(r$abandoned), if (is.null(results)) list() else results)"
h2 <- which(grepl(nd2, p4_txt, fixed = TRUE)); mt2 <- p4_txt
if (length(h2) == 1L) mt2[h2] <- sub(nd2, "kept <- if (is.null(results)) list() else results", mt2[h2], fixed = TRUE)
XM <- p4_def(mt2)
chk("P6 돌연변이: 포기 걸음을 거르지 않는 사본은 기대 수를 부풀린다(P1 이 잡는다) — 치환 1곳 성사",
    length(h2) == 1L && is.function(XM) && identical(XM("C:/s/base_000", res)$n_trials, 5L))
unlink(WD, recursive = TRUE)
cat(sprintf("\n%s\n", toJSON(list(test = "test_selection_regrade", pass = pass, fail = fail, total = pass + fail, skipped = skipped), auto_unbox = TRUE)))
quit(status = if (fail > 0L) 1L else 0L)
