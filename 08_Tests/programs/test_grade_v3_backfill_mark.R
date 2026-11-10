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
ROOT <- Sys.getenv("QM_ROOT", "")
if (!nzchar(ROOT) || !file.exists(file.path(ROOT, "02_Infrastructure/programs/grade_v3_backfill.R"))) ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
if (!nzchar(ROOT) || !file.exists(file.path(ROOT, "02_Infrastructure/programs/grade_v3_backfill.R"))) ROOT <- getwd()
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
  # 요인 표 변경 판정(gv3b_fa_stale)도 같은 방식으로 꺼낸다(있으면)
  for (x in ex) if (is.call(x) && identical(as.character(x[[1]]), "<-") && identical(as.character(x[[2]]), "gv3b_fa_stale")) eval(x, e)
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

cat("=== W. 배선(정적 · 주석 제외) ===\n")
code <- sub("#.*$", "", txt)
chk(sum(grepl("fa_stale <- rescore && gv3b_fa_stale(A, FA_MD5)", code, fixed = TRUE)) == 1L &&
      sum(grepl("if (rescore && !fa_stale && (identical(old_rv, RULES_VER) || old_rv %in% RULES_COMPAT))", code, fixed = TRUE)) == 1L,
    "W0 건너뜀 규칙이 요인 표 변경을 먼저 본다(같은 규칙 판이어도 낡은 fa 블록은 통과시키지 않는다)")
chk(any(grepl("FA_MD5 <- as.character(CTX$fa$md5", code, fixed = TRUE)) &&
      any(grepl("clusterExport", code, fixed = TRUE) & grepl("\"gv3b_fa_stale\"", code, fixed = TRUE)),
    "W0b 현행 요인 md5 를 워커가 문맥에서 읽고, 판정 함수를 워커로 내보낸다")
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
