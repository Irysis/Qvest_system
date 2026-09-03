#!/usr/bin/env Rscript
#==============================================================================
# test_rf_combination_launch.R — 논문 간 결합 착수 **양방향 검사** (2026-08-31)
#
# 왜: 결합 검토기는 2026-08-30 부터 후보를 쌓아 왔지만(4회 · 10쌍) **소비자가 없었다**.
#   검토 note 가 스스로 "착수하지 않는다" 고 적어 두었고 세션도 착수한 적이 없다.
#   생산자만 있고 소비자가 없는 계기 — 이 저장소의 반복 병이다.
#
# 판정 축:
#   ① 착수기가 실제로 호출되는가 (배선 — 없으면 또 소비자 없는 계기다)
#   ② 결합이 열리면 이월을 건너뛰는가 (둘 다 하면 active 중복으로 다음 논문이 막힌다)
#   ③ 후보 풀이 **논문 단위**인가 (entry 단위면 승격 사슬이 별개 논문으로 부풀려진다)
#   ④ 결합 entry 자신이 풀에 다시 들어가지 않는가 (같은 논문이 두 번 든 조합이 생긴다)
#   ⑤ 이미 돌린 쌍을 다시 열지 않는가 (없으면 매 주기 최고 쌍을 반복한다)
#   ⑥ 러너가 entry$base_signal 을 존중하는가 (아니면 결합이 단일 엔진으로 조용히 돈다)
#   ⑦ rf_cell_engine 이 engine_blend 를 rank-Z 로 섞는가 (단순 합이면 분산 큰 쪽이 지배)
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
LA  <- file.path(ROOT, "02_Infrastructure/ops/rf_combination_launch.R")
NP  <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R")
CE  <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R")
PAR <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R")
SEQ <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_run.R")

PASS <- 0L; FAIL <- 0L
ok <- function(m) { cat(sprintf("  OK   %s\n", m)); PASS <<- PASS + 1L }
ng <- function(m, d = "") { cat(sprintf("  FAIL %s — %s\n", m, d)); FAIL <<- FAIL + 1L }
code <- function(f) paste(sub("#.*$", "", readLines(f, warn = FALSE)), collapse = "\n")

cat("=== 1. 착수기 배선 (소비자가 있는가) ===\n")
if (!file.exists(LA)) { ng("착수기 파일 없음"); quit(status = 1) }
np <- code(NP)
if (grepl("rf_combination_launch.R", np, fixed = TRUE))
  ok("이월 러너가 착수기를 호출한다") else
  ng("착수기 호출자 0개", "후보만 쌓이고 아무도 안 쓴다")

cat("=== 2. 결합이 열리면 이월을 건너뛴다 ===\n")
if (grepl("combo_opened", np, fixed = TRUE) && grepl("if (isTRUE(.combo_opened)) return", np, fixed = TRUE))
  ok("결합 개설 시 이월 생략") else
  ng("결합과 이월이 동시에 간다", "active 중복으로 다음 논문 entry 가 안 열린다")

cat("=== 3~5. 후보 풀 규칙 ===\n")
la <- code(LA)
if (grepl("by_paper[[pk]]", la, fixed = TRUE) && grepl("paper_key", la, fixed = TRUE))
  ok("풀 단위 = 논문(paper_key)") else ng("entry 단위 풀", "승격 사슬이 별개 논문으로 세어진다")
if (grepl('identical(e$status, "parked")', la, fixed = TRUE))
  ok("parked/superseded 제외") else ng("무효 판이 후보에 든다")
if (grepl('startsWith(pk, "combo:")', la, fixed = TRUE))
  ok("결합 entry 는 풀에서 제외") else
  ng("결합의 결합이 생긴다", "같은 논문이 두 번 든 조합")
if (grepl(".done_pairs", la, fixed = TRUE) && grepl(".pairkey", la, fixed = TRUE))
  ok("이미 돌린 쌍 제외(순서 무관)") else ng("같은 쌍을 매 주기 반복한다")

cat("=== 6. 러너가 entry$base_signal 을 존중하는가 ===\n")
for (f in c(PAR, SEQ)) {
  b <- code(f)
  if (grepl("if (!is.null(E$base_signal)) E$base_signal", b, fixed = TRUE))
    ok(sprintf("%s — entry base_signal 우선", basename(f))) else
    ng(sprintf("%s — engine_path 로만 만든다", basename(f)), "결합이 단일 엔진으로 조용히 돈다")
}

cat("=== 7. 결합 방식이 rank-Z 평균인가 ===\n")
ce <- code(CE)
if (grepl("engine_blend", ce, fixed = TRUE)) ok("engine_blend 분기 존재") else
  ng("engine_blend 미지원", "결합 기저를 만들 수 없다")
if (grepl("frank(v, ties.method = \"average\")", ce, fixed = TRUE) && grepl("rowMeans", ce, fixed = TRUE))
  ok("월별 rank-Z 후 평균") else
  ng("순위 정규화 없이 합친다", "분산 큰 신호가 결합을 지배한다")
if (grepl("engine_blend 는 엔진 2개 이상 필요", ce, fixed = TRUE))
  ok("엔진 1개면 거부(조용한 단일 회귀 차단)") else ng("엔진 부족을 안 막는다")
if (grepl("공통 (Date,Ticker) 가 없다", ce, fixed = TRUE))
  ok("교집합 0행이면 중단(빈 결합 차단)") else ng("빈 교집합이 조용히 통과한다")

cat("=== 8. 거동 — dry-run 이 현재 원장에서 돌아가는가 ===\n")
out <- tryCatch(system2("Rscript", c(shQuote(LA), "--dry-run"), stdout = TRUE, stderr = TRUE),
                error = function(e) NULL)
if (is.null(out)) ng("착수기 실행 실패") else {
  txt <- paste(out, collapse = "\n")
  # ★가드가 정상 발화한 것을 실패로 세지 않는다 (2026-09-01 수리).
  #   무인 루프가 상시 돌게 되면서 active entry 가 있는 것이 **정상 상태**가 됐다.
  #   구판은 papers_pooled 가 아니면 전부 실패로 셌고, 그러면 이 검사는 **루프가 일할 때마다**
  #   빨간불을 켠다 — 상시 오탐은 상시 침묵과 같다(저장소 반복 교훈).
  #   가드 발화(active entry / 새 쌍 없음)는 착수기가 설계대로 물러난 것이지 결함이 아니다.
  .guards <- c("halt_active_exists", "halt_no_new_pair", "halt_queue_empty", "halt_disabled")
  .fired  <- .guards[vapply(.guards, function(g) grepl(g, txt, fixed = TRUE), logical(1))]
  if (grepl("papers_pooled", txt, fixed = TRUE)) ok("풀 구성까지 도달")
  else if (length(.fired)) ok(sprintf("가드 정상 발화(%s) — 착수기가 설계대로 물러났다", .fired[1]))
  else ng("풀 구성 전에 멈춤(가드 발화도 아님)", substr(txt, 1, 120))
  if (grepl("combo_entry_opened", txt, fixed = TRUE))
    ng("dry-run 인데 entry 를 열었다", "부작용 없음 계약 위반") else
    ok("dry-run 은 entry 를 열지 않는다")
}

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_combination_launch","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
