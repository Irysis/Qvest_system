## test_bm_park.R — 파킹 구성의 벤치 정렬 (2026-08-09 실사고 재발방지)
## ★실사고: 파킹 OFF 월에 **한 달 어긋난 벤치**를 넣었다(12전략 중 10건). 오류 없음·경고 없음.
##   피해 = 라벨 부호 2건 반전 · 전략-무관 예측 규칙(bm_gap rho 0.815 → 0.156 소멸) ·
##   STR_1698 "문턱 초과"(ΔIR +0.061 → +0.023, 부족분 -0.085 → +0.086) 소멸.
## ★양방향: ①정렬된 입력은 offset 0 을 찾아야 하고 ②일부러 어긋낸 입력은 그 오프셋을 **집어내야** 한다.
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressPackageStartupMessages(library(data.table))
source("02_Infrastructure/contracts/book_marginal.R")
P <- 0L; FA <- 0L
ok <- function(nm, cond) { if (isTRUE(cond)) { P <<- P+1L; cat(sprintf("  PASS  %s\n", nm)) }
                           else { FA <<- FA+1L; cat(sprintf("  FAIL  %s\n", nm)) } }
set.seed(4242)
n <- 240L
d <- seq(as.Date("2004-01-01"), by = "month", length.out = n)
bm <- rnorm(n, 0.006, 0.055)
INC <- data.table(date = d, ret_net = 0.7*bm + rnorm(n, 0.002, 0.02),
                  benchmark_ret = bm)
INC[, active := ret_net - benchmark_ret]
mI <- function(x) as.integer(format(x,"%Y"))*12L + as.integer(format(x,"%m"))
## 진짜 슬리브: 같은 달 벤치에 β=0.9 로 붙어 있다
SL0 <- data.table(m = mI(d), r = 0.9*bm + rnorm(n, 0.004, 0.03))
LAB <- data.table(m = mI(d), on = rep(c(TRUE,TRUE,FALSE,FALSE,FALSE), length.out = n))

cat("=== A. 양성 대조 — 정렬된 입력은 offset 0 ===\n")
a <- bm_park(SL0, LAB, INC)
ok("status MEASURED",        identical(a$alignment$status, "MEASURED"))
ok("inc_minus_sleeve = 0",   a$alignment$offset_inc_minus_sleeve == 0L)
ok("offset_applied = 0",     a$alignment$offset_applied == 0L)
ok("max_cor > 0.7",          a$alignment$max_cor > 0.7)
ok("parked 행수 = n",        nrow(a$parked) == n)
ok("ON 월 = 슬리브 수익",    { z <- a$parked[on == TRUE][2]; abs(z$ret_net - z$sleeve_r) < 1e-12 })
ok("OFF 월 = 벤치 수익",     { z <- a$parked[on == FALSE][2]; abs(z$ret_net - z$benchmark_ret) < 1e-9 })
## ★첫 행은 sw=0 이라 전환이 아니다 — 진짜 전환월(직전 OFF → ON)을 골라야 한다
ok("전환월에만 비용 차감",   { tr <- a$parked[on == TRUE & shift(on, 1L) == FALSE][1]
                               hd <- a$parked[on == TRUE & shift(on, 1L) == TRUE][1]
                               abs(tr$ret_net - (tr$sleeve_r - 15/1e4)) < 1e-12 &&
                               abs(hd$ret_net - hd$sleeve_r) < 1e-12 })

cat("=== B. 위반 주입 — 어긋낸 슬리브의 오프셋을 집어내야 한다 ===\n")
for (k in c(-2L, -1L, 1L, 2L)) {
  SLk <- copy(SL0)[, m := m + k]           ## 슬리브 월 라벨을 k 만큼 밀어 실사고 재현
  b <- bm_park(SLk, data.table(m = SLk$m, on = LAB$on), INC)
  ## ★부호 규약이 이름에 있다: 슬리브 월을 +k 밀면 (inc − 슬리브) = −k 여야 한다
  ok(sprintf("주입 %+d → inc_minus_sleeve %+d", k, -k), b$alignment$offset_inc_minus_sleeve == -k)
}
ok("실사고 판본(+1) OFF 월이 정합", {
  SL1 <- copy(SL0)[, m := m + 1L]
  b <- bm_park(SL1, data.table(m = SL1$m, on = LAB$on), INC)
  z <- b$parked[on == FALSE][2]; abs(z$ret_net - z$benchmark_ret) < 1e-9 })
ok("어긋난 채 offset=0 강제 시 경고", {
  SL1 <- copy(SL0)[, m := m + 1L]
  w <- tryCatch({ bm_park(SL1, data.table(m = SL1$m, on = LAB$on), INC, offset = 0L); FALSE },
                warning = function(w) grepl("실측", conditionMessage(w))); isTRUE(w) })
ok("정렬된 입력에 offset=0 주면 무경고", {
  r <- withCallingHandlers({ bm_park(SL0, LAB, INC, offset = 0L); TRUE },
                           warning = function(w) { invokeRestart("muffleWarning") }); isTRUE(r) })

cat("=== C. 저베타 슬리브 — 조용히 0 을 고르지 않는다 ===\n")
SLz <- data.table(m = mI(d), r = rnorm(n, 0.004, 0.03))   ## 벤치와 무상관
z <- bm_park(SLz, LAB, INC)
ok("status AMBIGUOUS_LOWCOR", identical(z$alignment$status, "AMBIGUOUS_LOWCOR"))
ok("offset_applied 는 0 으로 보수", z$alignment$offset_applied == 0L)
ok("max_cor < 0.15",          z$alignment$max_cor < 0.15)
ok("parked 는 여전히 생성",   !is.null(z$parked) && nrow(z$parked) == n)
ok("note 에 병기 지시",       grepl("병기", z$alignment$note))

cat("=== D. 겹침 부족 — 조용히 통과하지 않는다 ===\n")
SLs <- SL0[1:40]
s <- bm_park(SLs, LAB[1:40], INC)
ok("status INSUFFICIENT_OVERLAP", identical(s$alignment$status, "INSUFFICIENT_OVERLAP"))
ok("parked NULL",                 is.null(s$parked))
ok("n 보고",                      s$alignment$n == 40L)
ok("정렬 필드 보고",              "offset_inc_minus_sleeve" %in% names(s$alignment))

cat(sprintf("\n=== test_bm_park: %d PASS / %d FAIL (총 %d) ===\n", P, FA, P+FA))
# 2026-08-20: 배터리는 마지막 줄의 JSON 요약만 읽는다. 이 줄이 없어 이 파일은
#   등재조차 되지 못했다(측정 권위 계약이 회귀 보호 밖에 있었음).
cat(sprintf("{\"test\":\"test_bm_park\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", P, FA, P + FA))
if (FA > 0L) quit(status = 1L)
