#==============================================================================
# test_grade_v3_backfill_mark.R — 등급 일괄 재채점의 '규칙 변경 수혜 표식' (2026-11-10 · v10.2)
#
# 지키는 것: 도훈 결정 GRADE-V33-NOTCH-ASOF-AND-RULE-CHANGE-PROCEDURE-20261110(절차 명문화 — 수혜 기록 표식 · 발효 뒤 등록분부터 적용).
#   저장분에 새 규칙 판을 입혀 등급이 측정 때보다 오른 기록은 수혜 기록으로 표식되고, A 자격 관문이 상시 보류한다
#   (reinforcement/rf_runner_gates.R::rule_change_beneficiary — 그쪽 시험 = test_rf_a_eligibility.R H 절).
#   이 시험은 표식 함수 gv3b_benefit_mark(programs/grade_v3_backfill.R)와 그 배선(채점 함수 안 호출 · 병렬 워커 내보내기)을 본다.
#
# 축:
#   A  표식 판정 — 처음 오름 · 끈질김(다음 재채점에서 변화 없어도 수혜) · 풀림(측정 때 등급 이하) · 이력에서 측정 때 등급 복원 · 내림
#   W  배선(정적) — 채점 함수가 표식 함수를 부르고, 병렬 워커로 내보낸다(주석이 아니라 본문)
#   M  [돌연변이] 오름 판정을 '같거나 오름'으로 바꾼 사본 → 변화 없는 기록이 수혜로 찍힌다(소스 텍스트 치환 · 치환 성사 단정)
#
# 격리: 도구 본문을 실행하지 않는다(함수 정의 식 하나만 평가). 파일 쓰기 없음.
# 실행: Rscript 08_Tests/programs/test_grade_v3_backfill_mark.R
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
# 루트 = 시험 러너 self-first(r-portability ④-b) — 자기 위치 → CLAUDE_PROJECT_DIR → QM_ROOT → 작업 디렉터리 · 후보마다 표지 검증
.self <- tryCatch({ a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) { f <- gsub("\\\\", "/", f[1]); if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(gsub("\\\\", "/", getwd()), f); f } else "" },
  error = function(e) "")
ROOT <- getwd()
for (.c in c(if (nzchar(.self)) dirname(dirname(dirname(.self))) else "", Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""))) {
  if (nzchar(.c) && file.exists(file.path(.c, "02_Infrastructure/programs/grade_v3_backfill.R"))) { ROOT <- .c; break }
}
ROOT <- gsub("\\\\", "/", ROOT)
SRC <- file.path(ROOT, "02_Infrastructure/programs/grade_v3_backfill.R")
PASS <- 0L; FAIL <- 0L
chk <- function(cond, m, why = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") } else { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
}
fin <- function() {
  cat(sprintf('{"test":"grade_v3_backfill_mark","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL) 1L else 0L)
}
if (!file.exists(SRC)) { chk(FALSE, "0 도구 파일", SRC); fin() }
txt <- readLines(SRC, encoding = "UTF-8", warn = FALSE)

# 표식 함수 정의 식만 꺼내 평가한다(도구 본문 = 전체 산출물 순회는 돌리지 않는다)
load_mark <- function(lines) {
  ex <- parse(text = lines, keep.source = FALSE, encoding = "UTF-8")
  e <- new.env(parent = globalenv()); assign("%||%", `%||%`, envir = e)
  hit <- 0L
  for (x in ex) if (is.call(x) && identical(as.character(x[[1]]), "<-") && identical(as.character(x[[2]]), "gv3b_benefit_mark")) { eval(x, e); hit <- hit + 1L }
  # 요인 표 변경 판정(gv3b_fa_stale) · 선택 관문 재판정(gv3b_selection_gate · G1 11-10)도 같은 방식으로 꺼낸다(있으면)
  for (x in ex) if (is.call(x) && identical(as.character(x[[1]]), "<-") &&
                    as.character(x[[2]]) %in% c("gv3b_fa_stale", "gv3b_selection_gate", "GV3B_UNLESS_VOCAB", "gv3b_compat_unless", "gv3b_record_incomplete")) eval(x, e)
  list(env = e, n = hit)
}
L <- load_mark(txt)
chk(L$n == 1L && is.function(L$env$gv3b_benefit_mark), "0 표식 함수 정의 1개를 도구에서 꺼냈다")
if (L$n != 1L) fin()
mk <- L$env$gv3b_benefit_mark

cat("=== A. 표식 판정 ===\n")
a1 <- mk(list(), "A", "B", "v3.2", "v3.3")
chk(isTRUE(a1$benefit) && identical(a1$measured_grade, "B") && identical(a1$rules_version, "v3.3") && identical(a1$prior_essence_grade, "B"),
    "A1 처음 재채점에서 B → A = 수혜(측정 때 등급 B 를 들고 간다)")
a2 <- mk(list(rule_change_benefit = a1, grade_v3_backfill = list(history = list(list(rules_version = "v3.2", essence_grade = "B")))), "A", "A", "v3.3", "v3.5")
chk(isTRUE(a2$benefit) && identical(a2$measured_grade, "B"),
    "A2 끈질김 — 다음 재채점에서 A → A(변화 없음)여도 측정 때 등급 B 보다 높으니 수혜로 남는다")
a3 <- mk(list(rule_change_benefit = a2), "B", "A", "v3.5", "v3.6")
chk(identical(a3$benefit, FALSE) && identical(a3$measured_grade, "B"), "A3 풀림 — 측정 때 등급 이하로 내려오면 수혜 아님")
a4 <- mk(list(grade_v3_backfill = list(history = list(list(rules_version = "v3.0", essence_grade = "C"), list(rules_version = "v3.2", essence_grade = "B")))),
         "B", "B", "v3.3", "v3.5")
chk(isTRUE(a4$benefit) && identical(a4$measured_grade, "C"),
    "A4 표식 없는 옛 기록 — 재채점 이력의 가장 이른 등급(C)을 측정 때 등급으로 복원해 B 를 수혜로 본다")
a5 <- mk(list(), "B", "A", "v3.2", "v3.3")
chk(identical(a5$benefit, FALSE), "A5 내림(A → B) = 수혜 아님")
a6 <- mk(list(), "A", "A", "v3.2", "v3.3")
chk(identical(a6$benefit, FALSE), "A6 처음 재채점에서 변화 없음 = 수혜 아님")
a7 <- mk(list(), "A", "Z", "v3.2", "v3.3")
chk(identical(a7$benefit, FALSE), "A7 알 수 없는 등급 글자 = 수혜로 찍지 않는다(예외 없이 FALSE)")

cat("=== F. 요인 표가 바뀐 기록은 규칙 판이 같아도 다시 채점한다 ===\n")
fs <- L$env$gv3b_fa_stale
rec <- function(md5, re = "E1", fe = "E1") list(grade_v3 = list(rules_version = "v3.4",
  fa = if (is.null(md5)) list(status = "not_run") else list(factor_md5 = md5, record_epoch = re, factor_epoch = fe)))
chk(is.function(fs) && isTRUE(fs(rec("old111"), "new222")), "F1 저장 fa 블록의 factor_md5 ≠ 현행 요인 md5 → 낡음(다시 채점 대상)")
chk(is.function(fs) && identical(fs(rec("old111", re = "E_OLD", fe = "E1"), "new222"), FALSE) &&
      identical(fs(rec("old111", re = NA_character_, fe = "E1"), "new222"), FALSE),
    "F5 기록의 측정 축이 요인 축과 다르거나 모르면 대상 아님(노치가 등급에 닿지 않는 기록 — 요인이 바뀔 때마다 전 기록을 다시 채점하지 않는다)")
chk(is.function(fs) && identical(fs(rec("same"), "same"), FALSE), "F2 같은 md5 → 낡지 않음(건너뜀 유지)")
chk(is.function(fs) && identical(fs(rec(NULL), "new222"), FALSE), "F3 fa 블록에 md5 가 없는 기록(다른 축 · 노치 평가 안 탐) → 대상 아님")
chk(is.function(fs) && identical(fs(rec("old111"), NA_character_), FALSE) && identical(fs(rec("old111"), NULL), FALSE),
    "F4 현행 요인 md5 를 모르면(요인 문맥 미가동) 낡음으로 보지 않는다(전 건 재채점 폭주 방지)")

safe <- function(expr) tryCatch(expr, error = function(e) { cat("     오류:", conditionMessage(e), "\n"); NA })
cat("=== U. 요인 문맥이 없던 때(factor_unavailable · md5 없음) 채점된 기록 — 문맥이 돌아오면 같은 축만 다시 채점 (G1 · 11-10) ===\n")
recu <- function(axis = "E1", status = "factor_unavailable", md5 = NULL) {
  fa <- list(status = status, enabled = TRUE, eligible = FALSE, why_not = list("월간 요인 내용 해시가 meta 와 다르다"))
  if (!is.null(md5)) fa$factor_md5 <- md5
  list(measurement_axis = if (is.null(axis)) NULL else list(epoch = axis), grade_v3 = list(rules_version = "v3.4", fa = fa))
}
chk(is.function(fs) && isTRUE(safe(fs(recu(), "new222", "E1"))),
    "U1 쓰기 창 · [5c] 중도 실패 때 채점(fa = factor_unavailable · md5 없음) + 요인 문맥 복구 + 같은 축 → 다시 채점 대상")
chk(is.function(fs) && identical(safe(fs(recu(axis = "E_OLD"), "new222", "E1")), FALSE) && identical(safe(fs(recu(axis = NULL), "new222", "E1")), FALSE),
    "U2 다른 축 · 축을 모르는 기록은 대상 아님(노치 자격이 없는 수천 건을 다시 채점하지 않는다)")
chk(is.function(fs) && identical(safe(fs(recu(), NA_character_, "E1")), FALSE) && identical(safe(fs(recu(), "new222", NULL)), FALSE),
    "U3 지금도 요인 문맥이 없으면(md5 · epoch 모름) 대상 아님(같은 상태로 다시 굳힐 뿐)")
chk(is.function(fs) && identical(safe(fs(recu(status = "not_configured"), "new222", "E1")), FALSE) &&
      identical(safe(fs(rec(NULL), "new222", "E1")), FALSE),
    "U4 노치 설정이 없던 판 · fa 평가를 안 탄 기록은 이 경로의 대상 아님(규칙 판 재채점이 맡는다)")
chk(is.function(fs) && isTRUE(safe(fs(rec("old111"), "new222", "E1"))) && identical(safe(fs(rec("same"), "same", "E1")), FALSE),
    "U5 세 번째 인자를 받아도 기존 md5 판정(F1 · F2)은 그대로")
## 돌연변이 — factor_unavailable 가지를 뺀 사본은 U1 을 놓친다
ub <- "if (identical(st, \"factor_unavailable\") && (is.na(old) || !nzchar(old)))"
n_ub <- sum(grepl(ub, txt, fixed = TRUE))
LU <- load_mark(sub(ub, "if (FALSE)", txt, fixed = TRUE))
chk(n_ub == 1L && identical(safe(LU$env$gv3b_fa_stale(recu(), "new222", "E1")), FALSE),
    "U6 [돌연변이] factor_unavailable 가지를 끈 사본 → U1 의 기록을 다시 채점하지 않는다(치환 1곳 성사)", sprintf("치환 %d", n_ub))

cat("=== S. 선택 현실 점검 기록의 관문 재판정 — 저장 ok 를 그대로 쓰지 않고 현행 설정(alpha · 판 · PBO 역할)으로 다시 본다 (G1 · 11-10) ===\n")
sg <- L$env$gv3b_selection_gate
okof <- function(r) if (is.list(r)) r$ok else NA
sgk <- function(...) okof(safe(sg(...)))
scfg <- list(version = "sb1", alpha = 0.05, pbo_role = "diagnostic", pbo_flag_above = 0.05)
srec <- function(ok = TRUE, p = 0.03, v = "sb1", pbo = 0.4) list(selection_gate = list(mode = "reality_check", ok = ok, reason = "x"),
  selection_check = list(version = v, p_adj_candidate = p, alpha = 0.05, pbo = pbo, pbo_flagged = isTRUE(pbo > 0.05)))
chk(is.function(sg) && isTRUE(sgk(srec(), scfg)), "S1 저장 통과 · 같은 판 · p 0.03 ≤ alpha 0.05 → 통과 유지")
chk(is.function(sg) && identical(sgk(srec(), modifyList(scfg, list(alpha = 0.01))), FALSE),
    "S2 alpha 를 0.05 → 0.01 로 재보정하면 저장 통과(p 0.03)도 재채점에서 미통과(저장 ok 를 그대로 쓰지 않는다)")
chk(is.function(sg) && identical(sgk(srec(), modifyList(scfg, list(version = "sb2"))), FALSE),
    "S3 설정 판이 바뀌면 미통과(새 판으로 다시 점검해야 한다)")
chk(is.function(sg) && identical(sgk(srec(ok = FALSE, p = 0.001), scfg), FALSE),
    "S4 저장 미통과(집합 검사 등 재계산 못 하는 사유)는 p 가 작아도 미통과 그대로(저장 판정과 AND)")
chk(is.function(sg) && identical(sgk(srec(), NULL), FALSE) && identical(sgk(srec(p = NA), scfg), FALSE),
    "S5 설정을 못 읽거나 조정 p 가 없으면 미통과(fail-closed)")
chk(is.function(sg) && identical(sgk(srec(pbo = 0.4), modifyList(scfg, list(pbo_role = "gate"))), FALSE) &&
      isTRUE(sgk(srec(pbo = 0.01), modifyList(scfg, list(pbo_role = "gate")))),
    "S6 PBO 역할을 관문으로 바꾸면 현행 문턱으로 다시 본다(0.4 미통과 · 0.01 통과)")
sb <- "if (!(is.finite(p) && p <= scfg$alpha)) return(no("
n_sb <- sum(grepl(sb, txt, fixed = TRUE))
LS <- load_mark(sub(sb, "if (FALSE) return(no(", txt, fixed = TRUE))
chk(n_sb == 1L && isTRUE(okof(safe(LS$env$gv3b_selection_gate(srec(), modifyList(scfg, list(alpha = 0.01)))))),
    "S7 [돌연변이] 현행 alpha 재판정을 뺀 사본 → S2 의 기록이 통과로 남는다(치환 1곳 성사)", sprintf("치환 %d", n_sb))

cat("=== V. 조건부 호환 판(v3.5 · 11-13 · rules_version_compatible_unless) — cr_notch strong 저장분만 다시 채점 ===\n")
cu <- L$env$gv3b_compat_unless
UNL <- list(v3.4 = "cr_notch_strong", v3.3 = "cr_notch_strong")
vrec <- function(cn, rv = "v3.4") list(grade_v3 = list(rules_version = rv, cr_notch_basis = cn))
chk(is.function(cu) && identical(safe(cu(vrec("strong"), "v3.4", UNL)), FALSE) && identical(safe(cu(vrec("strong", "v3.3"), "v3.3", UNL)), FALSE),
    "V1 CR '강함' 가점이 유지된 v3.4 · v3.3 기록(cr_notch_basis = strong) → 다시 채점(건너뛰지 않는다)")
chk(is.function(cu) && all(vapply(list("normal", "weak", "insufficient", NA_character_, NULL), function(cn) isTRUE(safe(cu(vrec(cn), "v3.4", UNL))), logical(1))),
    "V2 가점이 없던 기록(보통 · 약함 · 판정 불가 · 기록 없음) → 채점이 같으므로 건너뛴다(판 표식 유지)")
chk(is.function(cu) && identical(safe(cu(vrec("normal", "v3.2"), "v3.2", UNL)), FALSE) && identical(safe(cu(vrec("normal"), "v3.4", list())), FALSE) &&
      identical(safe(cu(vrec("normal"), NA_character_, UNL)), FALSE),
    "V3 목록 밖 판(v3.2) · 빈 목록 · 판 모름 → 건너뛰지 않는다(종전 재채점 규칙 그대로)")
chk(is.function(cu) && inherits(tryCatch(cu(vrec("strong"), "v3.4", list(v3.4 = "cr_strong_any")), error = function(e) e), "error"),
    "V4 [위반 주입] 모르는 조건 어휘 → 멈춘다(조용히 건너뛰지 않는다)")
ut <- "  !isTRUE(hit)"
n_ut <- sum(grepl(ut, txt, fixed = TRUE))
LV <- load_mark(sub(ut, "  TRUE", txt, fixed = TRUE))
chk(n_ut == 1L && isTRUE(safe(LV$env$gv3b_compat_unless(vrec("strong"), "v3.4", UNL))),
    "V5 [돌연변이] 조건 판정을 지운 사본 → V1 의 가점 유지 기록을 건너뛴다(재채점 누락) — V1 이 잡는다(치환 1곳 성사)", sprintf("치환 %d", n_ut))

cat("=== R. 교체를 걸친 측정의 불완전 기록(v3.5 · 11-13) — 판 표식은 현행인데 v3.5 필드가 없으면 다시 채점 ===\n")
ri <- L$env$gv3b_record_incomplete
rrec <- function(sc = NULL, status = "ok", rv = "v3.5") { g <- list(status = status, rules_version = rv); if (!is.null(sc)) g$selection_control <- sc; list(grade_v3 = g) }
chk(is.function(ri) && isTRUE(safe(ri(rrec(), "v3.5", "v3.5", TRUE))),
    "R1 v3.5 판 표식 · 상태 ok · selection_control 없음(옛 .essence_v3_record 로 적힌 교체 걸친 측정) → 다시 채점")
chk(is.function(ri) && identical(safe(ri(rrec("size_beta"), "v3.5", "v3.5", TRUE)), FALSE),
    "R2 v3.5 필드가 있는 기록 → 건너뛴다(멱등)")
chk(is.function(ri) && identical(safe(ri(rrec(rv = "v3.4"), "v3.4", "v3.5", TRUE)), FALSE) &&
      identical(safe(ri(rrec(status = "not_applicable"), "v3.5", "v3.5", TRUE)), FALSE) &&
      identical(safe(ri(rrec(), "v3.5", "v3.5", FALSE)), FALSE),
    "R3 다른 판(종전 규칙이 맡음) · 상태 ok 아님(hard_fail 등) · 필드를 요구하지 않는 설정 → 이 가지로는 다시 채점하지 않는다")
ui <- "is.null(A$grade_v3$selection_control)"
n_ui <- sum(grepl(ui, txt, fixed = TRUE))
LR <- load_mark(sub(ui, "FALSE", txt, fixed = TRUE))
chk(n_ui == 1L && identical(safe(LR$env$gv3b_record_incomplete(rrec(), "v3.5", "v3.5", TRUE)), FALSE),
    "R4 [돌연변이] 필드 없음 판정을 지운 사본 → R1 의 불완전 기록을 건너뛴다 — R1 이 잡는다(치환 1곳 성사)", sprintf("치환 %d", n_ui))

cat("=== W. 배선(정적 · 주석 제외) ===\n")
code <- sub("#.*$", "", txt)
chk(sum(grepl("fa_stale <- rescore && gv3b_fa_stale(A, FA_MD5, FA_EPOCH)", code, fixed = TRUE)) == 1L &&
      sum(grepl("if (rescore && !fa_stale && !sel_stale && !rec_inc && (identical(old_rv, RULES_VER) || old_rv %in% RULES_COMPAT || gv3b_compat_unless(A, old_rv, RULES_UNLESS)))", code, fixed = TRUE)) == 1L,
    "W0 건너뜀 규칙이 요인 표 변경 · 요인 문맥 복구 · 선택 관문 재판정 변화를 먼저 본다(같은 규칙 판이어도 통과시키지 않는다) · 조건부 호환(v3.5)은 그 뒤")
chk(any(grepl("RULES_UNLESS <- CTX$cfg$rules_version_compatible_unless", code, fixed = TRUE)) &&
      any(grepl("clusterExport", code, fixed = TRUE) & grepl("\"gv3b_compat_unless\"", code, fixed = TRUE)),
    "W0d 조건부 호환 목록을 워커가 설정에서 읽고, 판정 함수를 워커로 내보낸다")
chk(sum(grepl("rec_inc <- rescore && gv3b_record_incomplete(A, old_rv, RULES_VER, NEED_SC)", code, fixed = TRUE)) == 1L &&
      any(grepl("NEED_SC <- identical(gv3_selection_control(CTX$cfg), \"size_beta\")", code, fixed = TRUE)) &&
      any(grepl("if (rec_inc) \"record_fields_incomplete\"", code, fixed = TRUE)) &&
      any(grepl("clusterExport", code, fixed = TRUE) & grepl("\"gv3b_record_incomplete\"", code, fixed = TRUE)),
    "W0h 교체를 걸친 불완전 기록 — 채점 함수가 판정해 건너뜀을 막고 · 원인 record_fields_incomplete 를 남기고 · 설정에서 요구 여부를 읽고 · 워커로 내보낸다")
## (v3.5 · 판단 T4 C-20261113-071 · 072) 규칙 판 재채점과 자료 판 재채점을 가르는 선택 · 원인 기록 · 강등 뒤 Judge 트리거 거두기
chk(sum(grepl("if (NO_DATA_TRIG) fa_stale <- FALSE", code, fixed = TRUE)) == 1L && sum(grepl("if (NO_DATA_TRIG) sel_stale <- FALSE", code, fixed = TRUE)) == 1L &&
      any(grepl("clusterExport", code, fixed = TRUE) & grepl("\"NO_DATA_TRIG\"", code, fixed = TRUE)) &&
      any(grepl("DIRS_FILE <- argv(\"--dirs\", NULL)", code, fixed = TRUE)) && any(grepl("--dirs 목록 중 대상에 없는 폴더", code, fixed = TRUE)),
    "W0e --no-data-triggers 가 요인 · 선택 설정 계기를 끄고(워커에도 전달) · --dirs 목록 밖 폴더는 멈춘다(조용히 줄지 않는다)")
chk(sum(grepl("causes = as.list(causes),", code, fixed = TRUE)) == 1L && any(grepl("A$rule_change_benefit$causes <- as.list(causes)", code, fixed = TRUE)),
    "W0f 재채점 원인을 모두 남긴다(요인 판 · 선택 설정 · 규칙 판 — 백필 블록 · 수혜 표식 둘 다)")
chk(sum(grepl("if (!identical(as.character(z$new_grade), \"A\")) {", code, fixed = TRUE)) == 1L &&
      sum(grepl("RCG$rcg_withdraw(dirname(z$path), z$new_grade, write = TRUE)", code, fixed = TRUE)) == 1L &&
      any(grepl("round_candidate_gate.R", code, fixed = TRUE) & grepl("sys.source", code, fixed = TRUE)),
    "W0g 쓰기 뒤 새 등급이 A 가 아니면 Judge 트리거를 정본(rcg_withdraw)으로 거둔다 · 그 함수를 쓰기 전에 싣는다")
chk(any(grepl("FA_MD5 <- as.character(CTX$fa$md5", code, fixed = TRUE)) && any(grepl("FA_EPOCH <- as.character(CTX$fa$epoch", code, fixed = TRUE)) &&
      any(grepl("clusterExport", code, fixed = TRUE) & grepl("\"gv3b_fa_stale\"", code, fixed = TRUE)),
    "W0b 현행 요인 md5 · epoch 를 워커가 문맥에서 읽고, 판정 함수를 워커로 내보낸다")
chk(sum(grepl("gates <- c(selection_rc = isTRUE(SG$ok))", code, fixed = TRUE)) == 1L &&
      !any(grepl("gates <- c(selection_rc = isTRUE(A$selection_gate$ok))", code, fixed = TRUE)) &&
      any(grepl("clusterExport", code, fixed = TRUE) & grepl("\"gv3b_selection_gate\"", code, fixed = TRUE)) &&
      any(grepl("SRC_CFG <- ", code, fixed = TRUE)),
    "W0c 선택 현실 점검 기록의 관문 = 현행 설정 재판정(SG) — 저장 ok 를 그대로 쓰는 줄이 없다 · 워커로 내보낸다")
chk(sum(grepl("A$rule_change_benefit <- gv3b_benefit_mark(A, new, old, old_rv, RULES_VER)", code, fixed = TRUE)) == 1L,
    "W1 채점 함수가 재채점 기록에 표식을 쓴다(본문 1곳)")
chk(any(grepl("clusterExport", code, fixed = TRUE) & grepl("\"gv3b_benefit_mark\"", code, fixed = TRUE)),
    "W2 병렬 워커로 표식 함수를 내보낸다(없으면 워커에서 함수를 못 찾아 전 건 error)")

cat("=== M. [돌연변이] ===\n")
tgt <- "rank[new] > rank[m0]"
n_hit <- sum(grepl(tgt, txt, fixed = TRUE))
LM <- load_mark(sub(tgt, "rank[new] >= rank[m0]", txt, fixed = TRUE))
mm <- if (LM$n == 1L) LM$env$gv3b_benefit_mark(list(), "A", "A", "v3.2", "v3.3") else list(benefit = NA)
chk(n_hit == 1L && isTRUE(mm$benefit), "M1 오름 판정을 '같거나 오름'으로 바꾼 사본 → 변화 없는 기록이 수혜로 찍힌다(치환 1곳 성사) — A6 이 그 차이를 본다",
    sprintf("치환 %d · benefit %s", n_hit, as.character(mm$benefit)))
fin()
