## test_harness_compliance.R — 하네스 준수 게이트 검사 (실사고 재현: 실제 저장소 경로로)
## 2026-08-09: STR_1675 가 4축 적대 검증을 통과한 **뒤에야** 계약 경로 밖임이 드러났다.
## 이 검사는 실제 두 경로(우회 / 준수)를 넣어 게이트가 갈라내는지 확인한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/contracts/harness_compliance.R")
P <- 0L; F <- 0L
ok <- function(c, m) { if (isTRUE(c)) { P <<- P+1L; cat(sprintf("  PASS  %s\n", m)) }
                       else { F <<- F+1L; cat(sprintf("  FAIL  %s\n", m)) } }
cat("=== test_harness_compliance ===\n")

cat("-- 1. ★위반 주입: 실사고 재료 (STR_1675, C15 우회 + 10-c 없음) --\n")
p1 <- "04_Research/strategies/STR_1675_QRebal_Hybrid/output/nav_QRebal_B.csv"
if (file.exists(p1)) {
  r1 <- harness_compliance(p1)
  ok(r1$ten_component < 8, sprintf("1a. 10-component %d/11 (<8)", r1$ten_component))
  ok(identical(r1$c15, "DIRECT_BYPASS"), sprintf("1b. ★C15 = %s · 증거 %s", r1$c15, r1$c15_evidence))
  ok(!isTRUE(r1$compliant), "1c. compliant=FALSE")
  ok(identical(r1$metric_type, "unavailable"), sprintf("1d. metric_type=%s", r1$metric_type))
  ok(inherits(try(assert_harness_compliant(p1, label="STR_1675"), silent=TRUE), "try-error"),
     "1e. ★assert 가 stop 발행 — 성과 측정 전에 차단")
} else { cat("  SKIP  실사고 경로 부재\n") }

cat("-- 2. 양성 대조: 계약 경로를 거친 재료 --\n")
p2 <- "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results/03_period_returns.csv"
if (file.exists(p2)) {
  r2 <- harness_compliance(p2)
  ok(r2$ten_component >= 8, sprintf("2a. ★10-component %d/11 (>=8)", r2$ten_component))
  ok(!is.na(r2$ten_dir), "2b. 산출 디렉토리 식별")
  ok(identical(r2$metric_type, "backtested_candidate"), sprintf("2c. metric_type=%s", r2$metric_type))
} else { cat("  SKIP  PG2 경로 부재\n") }

cat("-- 3. C15 경유 재료 (load_month_factors 사용) --\n")
p3 <- "04_Research/strategies/STR_1698_WT008_M08_Swap"
if (dir.exists(p3)) {
  r3 <- harness_compliance(p3)
  ok(identical(r3$c15, "via_contract"), sprintf("3a. ★C15 = %s (우회 아님)", r3$c15))
  ok(r3$ten_component < 8, sprintf("3b. 다만 10-component %d/11 — 재산출 필요", r3$ten_component))
  ok(!isTRUE(r3$compliant), "3c. compliant=FALSE (두 축 모두 필요)")
} else { cat("  SKIP  STR_1698 경로 부재\n") }

cat("-- 4. screen-tier 허용 모드 --\n")
if (file.exists(p1)) {
  w <- tryCatch({ assert_harness_compliant(p1, allow_screen_tier = TRUE); "warned_ok" },
                warning = function(w) "warned_ok", error = function(e) "errored")
  ok(identical(w, "warned_ok"), "4a. allow_screen_tier=TRUE 면 warning 후 진행")
  ok(inherits(try(assert_harness_compliant(p1), silent=TRUE), "try-error"),
     "4b. 기본은 stop (screen-tier 는 명시 선택)")
}

cat("-- 5. 경계: 조용한 통과 금지 --\n")
r5 <- harness_compliance(tempdir())
ok(!isTRUE(r5$compliant), "5a. 빈 디렉토리 → compliant=FALSE")
ok(r5$ten_component == 0L, sprintf("5b. 10-component %d", r5$ten_component))
ok(inherits(try(assert_harness_compliant(tempdir()), silent=TRUE), "try-error"),
   "5c. 미상도 stop (통과로 내려앉지 않음)")

cat("-- 6. ★순서 규약이 문서화됐는가 --\n")
r6 <- harness_compliance(tempdir())
ok(grepl("성과 측정", r6$note) && grepl("AX-002", r6$note),
   "6. note 가 순서 규약과 AX-002 를 명시")


cat("-- 7. ★대체 검증 기록 인식 (초판 결함 수리) --\n")
## STR_1698: 10-component 0 이지만 performance_summary.json 에 walkforward_integrity·lockbox·subperiods 보유
p7 <- "04_Research/strategies/STR_1698_WT008_M08_Swap"
if (dir.exists(p7)) {
  r7 <- harness_compliance(p7)
  ok(isTRUE(r7$has_alt_validation),
     sprintf("7a. ★대체 검증 인식: %s (파일 %s)",
             paste(r7$alt_validation, collapse=","), paste(head(r7$alt_validation_files,2), collapse=",")))
  ok(identical(r7$tier, "validated_needs_retrofit"),
     sprintf("7b. ★tier = %s (C15 경유 + 검증기록 + 10-c 부재)", r7$tier))
  ok(identical(r7$metric_type, "backtested_retrofit_candidate"),
     sprintf("7c. metric_type = %s", r7$metric_type))
  ok(!isTRUE(r7$compliant), "7d. 그래도 compliant=FALSE (retrofit 은 아직 안 됨)")
} else cat("  SKIP  STR_1698 경로 부재\n")

cat("-- 8. ★등급이 갈리는가 (STR_1675 = C15 우회 + 검증기록) --\n")
p8 <- "04_Research/strategies/STR_1675_QRebal_Hybrid"
if (dir.exists(p8)) {
  r8 <- harness_compliance(p8)
  ok(!identical(r8$tier, "validated_needs_retrofit"),
     sprintf("8a. ★C15 우회는 다른 등급: %s", r8$tier))
  ok(r8$tier %in% c("validated_c15_issue","unvalidated"),
     sprintf("8b. tier=%s (C15 우회가 등급을 낮춘다)", r8$tier))
}

cat("-- 9. 계약 준수 재료의 등급 --\n")
p9 <- "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results"
if (dir.exists(p9)) {
  r9 <- harness_compliance(p9)
  ok(r9$ten_component >= 8, sprintf("9a. 10-component %d/11", r9$ten_component))
  ok(grepl("^contract", r9$tier),
     sprintf("9b. ★tier=%s — 10-c 완비 재료는 contract_* 등급 (초판은 unvalidated 로 오분류했다)", r9$tier))
  ok(!identical(r9$tier, "unvalidated"),
     "9c. ★준수 재료를 미검증으로 찍지 않는다 (게이트가 게이트로서 실패하지 않는다)")
}

cat(sprintf("\n=== 최종: %d PASS / %d FAIL ===\n", P, F))
if (F > 0) quit(status = 1L)
