#!/usr/bin/env Rscript
#==============================================================================
# test_rf_block_accumulate.R — 블록이 전이될수록 누적되는가 (2026-09-04)
#
# 도훈 질문: "현재 강화프로세스는 블록이 전이될수록 발전을 기대할 수 있는 구조인가"
# 실측 답은 **아니오** 였다. 원인 둘:
#   ① 순서는 적응했는데 승계가 안 따라갔다. 교훈 재귀가 B5 를 2번째로 당겼는데(2026-09-04),
#      승계 코드는 구 순서(B1→B2→B3→B5→B4)를 전제로 "B2·B3 는 B1 위에" 로 박혀 있었다.
#      실측: B5_18 이 Calmar 0.405 를 냈는데 뒤이어 돈 B2·B3 는 overlay=none.
#      궤적: 1.454 → 1.163 → 1.472 → 1.147 → 1.167 (34칸 쓰고 첫 블록 대비 +0.018).
#   ② `B3 는 weighting 을 EW 로 되돌린다` 줄이 B2 승자를 매번 버렸다.
#
# 수리: 축 목록을 나열하지 않고 **지금까지 최고 구성**을 바닥으로 깔고 자기 축만 덮는다.
#   순서가 또 바뀌어도 어긋나지 않는다 — 오늘 커서·블록경계를 격자에서 재도출한 것과 같은 원리.
#
# 양방향: 누적이 실제로 일어나는가 + 자기 축은 덮이지 않는가(누적이 탐색을 죽이면 안 된다).
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

code <- paste(sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"),
                                        warn = FALSE)), collapse = "\n")

cat("=== A. 배선 — 누적이 코드에 있는가 (주석 제외) ===\n")
if (grepl("block_accumulate", code, fixed = TRUE)) ok("A1 누적 블록 존재") else ng("A1 누적 블록 부재")
if (grepl('!(CELL$block %in% c("B1", "B4")) && !is.null(.wbest_spec)', code, fixed = TRUE))
  ok("A2 탐색 블록은 지금까지 최고 구성을 바닥으로") else ng("A2 누적 조건")
# ★구판의 EW 리셋이 무조건 줄로 남아 있으면 B2 승자가 매번 버려진다
if (grepl('if (identical(CELL$block, "B3")) SPEC$weighting <- list(kind = "ew")', code, fixed = TRUE))
  ng("A3 B3 EW 무조건 리셋 잔존", "B2 승자를 매번 버린다") else
  ok("A3 B3 EW 무조건 리셋 제거됨")
if (grepl('is.null(.wbest_spec)', code, fixed = TRUE))
  ok("A4 측정이 없을 때만 구판 기본값(폴백 보존)") else ng("A4 폴백 부재")

cat("\n=== B. 로직 재도출 — 자기 축은 덮이지 않는가 ===\n")
# 누적 규칙을 그대로 재현한다: 자기 축만 CELL 값, 나머지는 wbest
acc <- function(block, cell, wbest) {
  own <- switch(block, B2 = "weighting", B3 = "universe", B5 = "overlay", NA_character_)
  S <- list(factors = cell$factors, weighting = cell$weighting, universe = cell$universe, overlay = cell$overlay)
  if (!(block %in% c("B1", "B4")) && !is.null(wbest)) {
    if (is.null(S$factors) || !length(S$factors)) S$factors <- wbest$factors
    if (!identical(own, "weighting") && !is.null(wbest$weighting)) S$weighting <- wbest$weighting
    if (!identical(own, "universe")  && !is.null(wbest$universe))  S$universe  <- wbest$universe
    if (!identical(own, "overlay")   && !is.null(wbest$overlay))   S$overlay   <- wbest$overlay
  }
  S
}
WB <- list(factors = list(list(kind = "db", id = "F1"), list(kind = "db", id = "F2")),
           weighting = list(kind = "catalog", arm = "entropy"),
           universe = list(kind = "k200_kq150"),
           overlay = list(arm_id = "holdlvl_syscrowd_tilt"))

s2 <- acc("B2", list(weighting = list(kind = "catalog", arm = "cvar")), WB)
if (identical(s2$weighting$arm, "cvar")) ok("B1 B2 는 자기 축(비중)을 유지 — 탐색이 죽지 않는다") else ng("B1 자기 축 덮임")
if (identical(s2$overlay$arm_id, "holdlvl_syscrowd_tilt"))
  ok("B2 B2 가 오버레이 승자를 물고 간다 ★실사고 지점") else ng("B2 오버레이 미승계", "구판 결함 재현")
if (length(s2$factors) == 2L) ok("B3 팩터 승자 승계") else ng("B3 팩터 미승계")

s3 <- acc("B3", list(universe = list(kind = "index", flag = "KQ150")), WB)
if (identical(s3$universe$flag, "KQ150")) ok("B4 B3 는 자기 축(유니버스) 유지") else ng("B4 자기 축 덮임")
if (identical(s3$weighting$arm, "entropy"))
  ok("B5 B3 가 비중 승자를 물고 간다 ★구판은 EW 로 되돌렸다") else ng("B5 비중 미승계")
if (identical(s3$overlay$arm_id, "holdlvl_syscrowd_tilt")) ok("B6 B3 가 오버레이 승자 승계") else ng("B6 오버레이 미승계")

s5 <- acc("B5", list(overlay = list(arm_id = "new_arm")), WB)
if (identical(s5$overlay$arm_id, "new_arm")) ok("B7 B5 는 자기 축(오버레이) 유지") else ng("B7 자기 축 덮임")
if (identical(s5$weighting$arm, "entropy")) ok("B8 B5 가 비중 승자 승계") else ng("B8 비중 미승계")

s1 <- acc("B1", list(factors = list(list(kind = "db", id = "X"))), WB)
if (length(s1$factors) == 1L && is.null(s1$overlay))
  ok("B9 B1 은 누적 대상 아님(첫 블록 — 설계가 정한다)") else ng("B9 B1 이 누적됐다")
s4 <- acc("B4", list(factors = list(), weighting = list(kind = "ew")), WB)
if (is.null(s4$overlay)) ok("B10 B4 는 누적 아님(부분집합 조립 — LOO 가 깨진다)") else ng("B10 B4 가 누적됐다")

cat("\n=== C. 실사고 재현 — 구판이라면 무엇이 달랐나 (음성 대조) ===\n")
old_acc <- function(block, cell, w1) {   # 구판: B1 승자만, B3 는 EW 리셋
  S <- list(factors = if (length(cell$factors)) cell$factors else w1$factors,
            weighting = cell$weighting %||% list(kind = "ew"),
            universe = cell$universe %||% list(kind = "k200_kq150"), overlay = NULL)
  if (identical(block, "B3")) S$weighting <- list(kind = "ew")
  S
}
o2 <- old_acc("B2", list(weighting = list(kind = "catalog", arm = "cvar")), WB)
if (is.null(o2$overlay)) ok("C1 구판이라면 B2 에 오버레이가 없다 — 검사가 실제 차이를 가른다") else
  ng("C1 구판 재현 실패")
o3 <- old_acc("B3", list(universe = list(kind = "index")), WB)
if (identical(o3$weighting$kind, "ew")) ok("C2 구판이라면 B3 가 비중을 EW 로 되돌린다") else ng("C2 구판 재현 실패")

cat("\n=== D. 실측 원장 — 오늘 entry 에서 승계 단절이 실재했는가 ===\n")
led <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE),
                error = function(e) NULL)
E <- if (is.null(led)) NULL else
  Filter(function(e) identical(e$base_id, "RP_20260904_112446_10544_combo_rulefast"), led$entries)
if (!length(E)) cat("  SKIP 실사고 entry 부재\n") else {
  .sp <- function(cc) { p <- file.path(ROOT, ".cache/rf_parallel",
                          sprintf("spec_%s__%s.json", cc, substr(E[[1]]$base_id, 1, 48)))
                        if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL }
  b5 <- .sp("B5_18"); b2 <- .sp("B2_7")
  if (!is.null(b5) && !is.null(b2)) {
    if (!is.null(b5$overlay) && is.null(b2$overlay))
      ok("D1 실측: B5 는 오버레이가 있고 뒤이어 돈 B2 는 없다 — 승계 단절 확인") else
      ng("D1 승계 단절 미확인", "실사고와 다르다")
  } else cat("  SKIP spec 파일 정리됨\n")
}

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_block_accumulate","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
