## test_census_helper.R — census 3규약 검사기 (양성 대조 + 위반 주입)
## ★핵심 검사: 이 도구가 **실제 6회 사고를 잡는가** — 각 규약이 그 사고 형태를 재현한 입력에서 발화해야 한다.
suppressPackageStartupMessages({library(data.table)})
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)
source("02_Infrastructure/contracts/census_helper.R")

PASS <- 0L; FAIL <- 0L
chk <- function(nm, ok, d = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", nm)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", nm, d)) }
}

cat("=== A. census_assert_scope — 범위 검증 ===\n")
pop <- paste0("f", 1:100)
r <- census_assert_scope(pop, known = c("f3", "f50"))
chk("기지사례가 모집단에 있으면 ok", isTRUE(r$ok) && length(r$missing) == 0L)

cat("\n[위반 주입] 기지 반례가 모집단 밖 — 실제 사고 ⑥ 재현\n")
e <- tryCatch({ census_assert_scope(pop, known = c("f3", "OUTSIDE"), strict = TRUE); "no_error" },
              error = function(x) "stopped")
chk("★strict=TRUE 면 stop (census 범위 오류를 조용히 넘기지 않음)", e == "stopped")
w <- withCallingHandlers(
  { r2 <- census_assert_scope(pop, known = c("OUTSIDE"), strict = FALSE); "warned_or_not" },
  warning = function(cond) { assign("got_warn", TRUE, envir = parent.frame(3)); invokeRestart("muffleWarning") })
chk("strict=FALSE 면 경고 후 진행 + ok=FALSE", isFALSE(r2$ok) && identical(r2$missing, "OUTSIDE"))

cat("\n=== B. census_draw — 전수/표본 결정 ===\n")
d1 <- census_draw(paste0("g", 1:50), full_below = 200L)
chk("모집단 50 → 전수", d1$mode == "FULL" && d1$n_used == 50L)
d2 <- census_draw(paste0("g", 1:500), full_below = 200L, n_sample = 120L)
chk("모집단 500 → 표본", d2$mode == "SAMPLE" && d2$n_used == 120L)
chk("표본 coverage 기록", abs(d2$coverage - 120/500) < 1e-9)

cat("\n[★핵심] 기지 반례 강제 포함 — 실제 사고 ⑥ 방지\n")
pop2 <- paste0("g", 1:500)
hits <- 0L
for (s in 1:20) {
  dd <- census_draw(pop2, full_below = 200L, n_sample = 30L,
                    must_include = "g499", seed = 1000L + s)
  if ("g499" %in% dd$items) hits <- hits + 1L
}
chk("must_include 는 20/20 표본에 항상 포함", hits == 20L, sprintf("(%d/20)", hits))
## 대조: 강제 포함이 없으면 자주 놓친다(도구의 필요성 실증)
miss <- 0L
for (s in 1:20) {
  dd <- census_draw(pop2, full_below = 200L, n_sample = 30L, seed = 2000L + s)
  if (!("g499" %in% dd$items)) miss <- miss + 1L
}
chk("★대조: 강제 포함 없으면 대부분 놓침(도구 필요성 실증)", miss >= 15L, sprintf("(놓침 %d/20)", miss))

cat("\n=== C. census_zero_bound — '0건'과 '없음'의 구분 ===\n")
z <- census_zero_bound(n_sample = 150L, n_population = 494L)
chk("표본 150 → 상한 약 2.0%", abs(100 * z$p_upper - 1.98) < 0.15, sprintf("(%.2f%%)", 100*z$p_upper))
chk("모집단 494 → 최대 약 10건", z$n_upper_est >= 8 && z$n_upper_est <= 12, sprintf("(%s)", z$n_upper_est))
z2 <- census_zero_bound(n_sample = 10L)
chk("표본이 작으면 상한이 크다(10건 → 25%+)", z2$p_upper > 0.25, sprintf("(%.1f%%)", 100*z2$p_upper))
chk("표본 클수록 상한 감소(단조)", census_zero_bound(1000L)$p_upper < z$p_upper)
chk("텍스트에 '0건' 표기 포함", grepl("0건", z$text))

cat("\n=== D. census_prepare — 통합 ===\n")
p1 <- census_prepare(pop2, known = c("g499"), full_below = 200L, n_sample = 40L)
chk("prepare: 기지사례가 표본에 포함", "g499" %in% p1$draw$items)
chk("prepare: scope PASS 기록", isTRUE(p1$scope$ok) && grepl("PASS", p1$note))
e2 <- tryCatch({ census_prepare(pop2, known = c("NOT_IN_POP"), strict = TRUE); "no_error" },
               error = function(x) "stopped")
chk("★prepare: 범위 오류 시 stop", e2 == "stopped")

cat("\n=== E. 계약 방어 ===\n")
e3 <- tryCatch({ census_zero_bound(n_sample = 0L); "no_error" }, error = function(x) "stopped")
chk("표본 0 이면 stop", e3 == "stopped")
chk("known 비어도 정상 동작", isTRUE(census_assert_scope(pop, known = character(0))$ok))

cat(sprintf("\n=== 결과: PASS %d / FAIL %d ===\n", PASS, FAIL))
cat(sprintf('{"test":"census_helper","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0) quit(status = 1)
