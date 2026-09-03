# test_judge_verdict_v2.R — v10 Judge 재정의(PIT 전담)의 양방향 검증
#
# 계약 (v10 2026-08-29 도훈 지시):
#   ① Judge 는 PIT 검증 전담 — judge.md 에 verdict v2 필드(pit_pass/violations/
#      reproduction/lag1_stress)가 선언돼 있어야 한다.
#   ② 구 자본 심사(Gate C/D/E/F)·lockbox 의무가 judge.md 에 되살아나면 FAIL (부활 방지).
#   ③ state_transitions.json: FORGE_DONE → COMPLETED 허용(QEPM 종점 = 등급 평가) +
#      judge_conditional_on_grade_A 플래그 + JUDGE_PASSED → COMPLETED 허용.
#
# 실행: Rscript 08_Tests/worktask/test_judge_verdict_v2.R

# 앵커 = self-first (r-portability 금칙 ④-b: 테스트 러너는 자기 위치 1순위 — env 는 폴백)
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages(library(jsonlite))

pass <- 0L; fail <- 0L
ok <- function(msg) { cat(sprintf("  [PASS] %s\n", msg)); pass <<- pass + 1L }
ng <- function(msg) { cat(sprintf("  [FAIL] %s\n", msg)); fail <<- fail + 1L }

jd <- readLines(".claude/agents/judge.md", warn = FALSE, encoding = "UTF-8")
jtxt <- paste(jd, collapse = "\n")

# ① v2 스키마 필드 선언
for (f in c("judge_verdict_v2", "pit_pass", "violations", "reproduction", "lag1_stress")) {
  if (grepl(f, jtxt, fixed = TRUE)) ok(sprintf("judge.md 에 %s 선언", f))
  else ng(sprintf("judge.md 에 %s 부재", f))
}

# ① 스폰 조건: Grade A 한정 명문
if (grepl("Grade A 확정 직후에만", jtxt)) ok("judge.md 스폰 조건 = Grade A 한정 명문") else
  ng("judge.md 스폰 조건(Grade A 한정) 문구 부재")

# ② 부활 방지 — 구 자본 심사·lockbox 의무 부재
revived <- c("Gate A~F", "multi-objective 8지표",
             "judge_lockbox_nav", "Lockbox 성과 측정 강제", "lockbox 접근 유일 허용")
for (f in revived) {
  if (!grepl(f, jtxt, fixed = TRUE)) ok(sprintf("구 의무 '%s' 부재 (부활 없음)", f))
  else ng(sprintf("구 의무 '%s' 가 judge.md 에 되살아남", f))
}
# lockbox 는 폐지 문맥(금지 서술)으로만 등장해야 한다
lb_lines <- grep("lockbox", jd, ignore.case = TRUE, value = TRUE)
bad_lb <- lb_lines[!grepl("폐지|금지|호출 금지", lb_lines)]
if (length(bad_lb) == 0L) ok("judge.md 의 lockbox 언급 전부 폐지/금지 문맥") else
  ng(sprintf("폐지 문맥 아닌 lockbox 언급 %d줄: %s", length(bad_lb), substr(bad_lb[1], 1, 60)))

# ③ 전이 정책
pol <- fromJSON("02_Infrastructure/hooks/policies/state_transitions.json",
                simplifyVector = TRUE)
fd <- pol$transitions$FORGE_DONE
if ("COMPLETED" %in% fd$allowed_next) ok("FORGE_DONE → COMPLETED 허용 (QEPM 종점 = 등급)") else
  ng("FORGE_DONE → COMPLETED 불허")
if (isTRUE(fd$judge_conditional_on_grade_A)) ok("judge_conditional_on_grade_A 플래그 존재") else
  ng("judge_conditional_on_grade_A 플래그 부재")
jp <- pol$transitions$JUDGE_PASSED
if ("COMPLETED" %in% jp$allowed_next) ok("JUDGE_PASSED → COMPLETED 허용 (BOOK 등록은 수동)") else
  ng("JUDGE_PASSED → COMPLETED 불허")

cat(sprintf("결과: PASS=%d FAIL=%d\n", pass, fail))
## ★러너 요약 계약 (v10 2026-09-03) — 없으면 run_all_hooks.sh 가 UNMEASURED 로 계상해 이 스위트의 단언이 총계에 0 으로 들어간다.
cat(sprintf('{"test":"judge_verdict_v2","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
