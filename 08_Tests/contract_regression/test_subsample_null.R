## test_subsample_null.R — 창-자르기 게이트 + 대조군 갈림 게이트 검사
## 2026-08-09 실사고 재현: 73개월 중 26개월 창에서 rho 가 0.369→0.186 으로 떨어졌는데
## 무작위 26개월 귀무분포에서 백분위 14.8% = 통상 변동이었다. 게이트가 이를 잡는지 확인한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/contracts/subsample_null.R")
P <- 0L; F <- 0L
ok <- function(c, m) { if (isTRUE(c)) { P <<- P+1L; cat(sprintf("  PASS  %s\n", m)) }
                       else { F <<- F+1L; cat(sprintf("  FAIL  %s\n", m)) } }
cat("=== test_subsample_null ===\n")

cat("-- 1. ★위반 주입: 무작위 창 (실사고 재현) --\n")
set.seed(1); n <- 73L
x <- rnorm(n); y <- 0.37*x + sqrt(1-0.37^2)*rnorm(n)   # 전체 rho ~ 0.37
rw <- rep(FALSE, n); rw[sample.int(n, 26)] <- TRUE      # 무작위 26개월 창
r1 <- subsample_null(x, y, rw)
ok(isTRUE(r1$available), "1a. 귀무분포 산출")
ok(isTRUE(r1$inside), sprintf("1b. ★무작위 창 → inside=TRUE (Δ %+.3f · 백분위 %.1f%%)", r1$delta, r1$percentile))
ok(inherits(try(assert_subsample_null(x, y, rw), silent=TRUE), "try-error"),
   "1c. assert 가 stop 발행 — 창 주장 차단")
ok((r1$null_q95 - r1$null_q05) > 0.3,
   sprintf("1d. ★귀무 폭 %.3f — 26/73 부분표본은 rho 가 크게 흔들린다(실사고 근거)",
           r1$null_q95 - r1$null_q05))

cat("-- 2. 양성 대조: 진짜로 다른 창 --\n")
sp <- rep(FALSE, n); sp[1:26] <- TRUE
y2 <- y; y2[1:26] <- -x[1:26] + 0.2*rnorm(26)          # 그 창만 상관 반전
r2 <- subsample_null(x, y2, sp)
ok(!isTRUE(r2$inside), sprintf("2a. ★진짜 다른 창 → inside=FALSE (Δ %+.3f · 백분위 %.1f%%)",
                               r2$delta, r2$percentile))
ok(!inherits(try(assert_subsample_null(x, y2, sp), silent=TRUE), "try-error"),
   "2b. assert 통과 (양성 대조 보존 — 항상 막으면 무정보)")

cat("-- 3. 창 크기 의존성 --\n")
w1 <- subsample_null(x, y, {v <- rep(FALSE,n); v[sample.int(n,12)] <- TRUE; v})
w2 <- subsample_null(x, y, {v <- rep(FALSE,n); v[sample.int(n,50)] <- TRUE; v})
ok((w1$null_q95-w1$null_q05) > (w2$null_q95-w2$null_q05),
   sprintf("3. 작은 창의 귀무 폭이 더 넓다 (k=12: %.3f > k=50: %.3f)",
           w1$null_q95-w1$null_q05, w2$null_q95-w2$null_q05))

cat("-- 4. 경계: 조용한 통과 금지 --\n")
ok(!isTRUE(subsample_null(x[1:20], y[1:20], rw[1:20])$available), "4a. n<24 → available=FALSE")
ok(inherits(try(assert_subsample_null(x[1:20], y[1:20], rw[1:20]), silent=TRUE), "try-error"),
   "4b. 산출 불가 시 stop (통과로 내려앉지 않음)")
ok(!isTRUE(subsample_null(x, y, rep(TRUE, n))$available), "4c. 창=전체 → available=FALSE")

cat("-- 5. ★대조군 갈림 게이트 (실사고 재현) --\n")
ag <- assert_controls_agree(c(random_signal = 0, random_timing = 15), tol = 10, label = "x9")
ok(isFALSE(ag$agree), sprintf("5a. ★갈림 검출 (폭 %.1f%%p)", ag$spread))
ok(identical(ag$conservative, "random_timing") && abs(ag$conservative_pct - 15) < 1e-9,
   sprintf("5b. ★보수적 대조 선택 = %s (%.1f%%) — 낮은 쪽 채택 금지",
           ag$conservative, ag$conservative_pct))
w <- tryCatch({ assert_controls_agree(c(a=0, b=15), tol=10); "nowarn" },
              warning = function(w) "warned")
ok(identical(w, "warned"), "5c. 갈리면 warning 발행")
ok(inherits(try(assert_controls_agree(c(a=0,b=15), tol=10, hard=TRUE), silent=TRUE), "try-error"),
   "5d. hard=TRUE 면 stop")
ok(isTRUE(assert_controls_agree(c(a=12, b=15), tol=10)$agree), "5e. 일치하면 통과 (양성 대조)")

cat("-- 6. ★실사고 수치 재현 --\n")
ok(r1$k == 26L && r1$n == 73L, sprintf("6a. 창 %d/%d (실사고와 동일 형상)", r1$k, r1$n))
ok(r1$percentile > 5 && r1$percentile < 95,
   sprintf("6b. 무작위 창 백분위 %.1f%% 가 [5, 95] 안 (실사고 14.8%%)", r1$percentile))

cat(sprintf("\n=== 결과: %d PASS / %d FAIL ===\n", P, F))
if (F > 0) quit(status = 1L)
