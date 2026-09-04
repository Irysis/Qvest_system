## 정본 문서가 실행 코드를 반영하는가 — reinforce SKILL · lean-loop · CLAUDE.md (2026-09-04)
## 도훈: "강화 프로세스 이번에 많이 바꿨잖아? 그게 반영 안돼있는거야?" — 코드는 바뀌었는데 문서는
##   "무인 루프에는 LLM 이 없다 / B1 = 규칙 선정" 그대로였다. 문서는 낙후한다(메모리 카드) — 그러니
##   **켜져 있는 스위치마다** 문서가 그 정본 파일을 가리키는지 재도출한다. 스위치가 꺼지면 요구도 꺼진다.
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
rd <- function(f) paste(readLines(file.path(ROOT, f), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
cfg <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE), error = function(e) list())
sk <- rd(".claude/skills/reinforce/SKILL.md")

cat("=== A. 켜진 스위치 → SKILL 이 정본 파일을 가리킨다 ===\n")
req <- list(
  list(on = isTRUE(cfg$b1_design$enabled),              what = "B1 LLM 설계",      needle = "rf_b1_design"),
  list(on = isTRUE(cfg$lcode_mechanism$enabled),        what = "블록 기전(LLM)",    needle = "rf_lcode_mechanism"),
  list(on = isTRUE(cfg$fidelity_audit$fanout$enabled),  what = "충실도 6축 팬아웃", needle = "rf_fidelity_fanout"),
  list(on = isTRUE(cfg$combination$enabled),            what = "결합 레인",        needle = "rf_combination_launch"),
  list(on = !is.null(cfg$promote_max_depth),            what = "승격 사슬",        needle = "rf_promote"),
  list(on = TRUE,                                       what = "롤링 구제",        needle = "rolling_grade"),
  list(on = TRUE,                                       what = "방어형 풀 경로",   needle = "defensive_score"),
  list(on = TRUE,                                       what = "블록 순서 적응",   needle = "rf_block_order_decide"),
  list(on = TRUE,                                       what = "승계 강등",        needle = "rac_degrade_plan"),
  list(on = TRUE,                                       what = "기전 백필",        needle = "rf_mech_backfill"),
  list(on = TRUE,                                       what = "알게 된 것 생성기", needle = "rf_block_insights"),
  list(on = TRUE,                                       what = "LLM 레인 배분",    needle = "llm.lanes"))
for (r in req) {
  if (!isTRUE(r$on)) { cat(sprintf("  --   %s 스위치 꺼짐 — 요구 없음\n", r$what)); next }
  if (grepl(r$needle, sk, fixed = TRUE)) ok(sprintf("A %s → SKILL 에 `%s`", r$what, r$needle)) else ng(sprintf("A %s 미반영", r$what), r$needle)
}

cat("\n=== B. 낡은 문장이 남아 있지 않은가 ===\n")
stale <- c("무인 루프에는 LLM 이 없다", "규칙 개시이지 LLM 개시가 아니다")
for (s in stale) if (!grepl(s, sk, fixed = TRUE)) ok(sprintf("B '%s' 없음", s)) else ng(sprintf("B 낡은 문장 잔존: %s", s))
if (grepl("§0.3", sk, fixed = TRUE) && grepl("## §0.3", sk, fixed = TRUE)) ok("B §0.3 실행 정본 절 존재") else ng("B §0.3 절 없음")
b1row <- regmatches(sk, regexpr("\\| B1 \\(1~5\\) \\|[^\n]*", sk))
if (length(b1row) && grepl("LLM 설계", b1row) && grepl("규칙 선정 폴백", b1row)) ok("B B1 행 = LLM 설계 + 규칙 폴백") else ng("B B1 행", substr(b1row %||% "", 1, 80))

cat("\n=== C. lean-loop · CLAUDE.md 이음매 ===\n")
ll <- rd(".claude/rules/lean-loop.md")
if (grepl("LLM 설계", ll, fixed = TRUE) && grepl("§0.3", ll, fixed = TRUE)) ok("C lean-loop 강화 분기가 현행을 가리킨다") else ng("C lean-loop 미반영")
cm <- rd("CLAUDE.md")
if (grepl("§0.3", cm, fixed = TRUE) && grepl("LLM설계", cm, fixed = TRUE)) ok("C CLAUDE.md 파이프라인 줄이 §0.3 을 가리킨다") else ng("C CLAUDE.md 미반영")
cl <- rd("02_Infrastructure/docs/CHANGELOG_constitution.md")
if (grepl("## v10.4", cl, fixed = TRUE)) ok("C CHANGELOG v10.4 항목") else ng("C CHANGELOG 항목 없음")

cat("\n=== D. 문서가 가리키는 파일이 실재한다 (사본은 낙후한다) ===\n")
## 06_Registry/ 는 실행이 만드는 데이터(예: grade_a_queue.json 은 첫 A 에서 생긴다) — 코드 경로만 실재를 요구한다
paths <- unique(regmatches(sk, gregexpr("`(02_Infrastructure|08_Tests)/[A-Za-z0-9_./-]+`", sk))[[1]])
paths <- gsub("`", "", paths)
miss <- paths[!file.exists(file.path(ROOT, paths))]
if (!length(miss)) ok(sprintf("D SKILL 이 인용한 경로 %d개 전부 실재", length(paths))) else ng("D 없는 경로 인용", paste(miss, collapse = ", "))

cat(sprintf("\n== test_rf_skill_reflects_runtime: %d pass · %d fail ==\n", P, F))
cat(sprintf('{"test":"rf_skill_reflects_runtime","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
if (F > 0L) quit(status = 1L)
