## test_proxy_axis.R — 대리 축 재현 계약 검사 (실사고 3종 재현 포함)
## 2026-08-09 한 아크에서 같은 축으로 3번 틀렸다: ①한 이름만 조회 ②방향 미확인 ③NA 정렬.
## 이 검사는 각각을 **위반 주입**으로 재현하고 계약이 잡는지 확인한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/contracts/proxy_axis.R")
P <- 0L; F <- 0L
ok <- function(c, m) { if (isTRUE(c)) { P <<- P+1L; cat(sprintf("  PASS  %s\n", m)) }
                       else { F <<- F+1L; cat(sprintf("  FAIL  %s\n", m)) } }
cat("=== test_proxy_axis ===\n")

set.seed(42); n <- 269L
score <- rnorm(n)
orig  <- score <= quantile(score, 0.717)     # 원 라벨: 하위 71.7%

cat("-- 1. 무작위 기대 일치율 공식 --\n")
ok(abs(proxy_expected_agreement(0.717) - (0.717^2 + 0.283^2)) < 1e-12, "1a. p^2+(1-p)^2")
ok(abs(proxy_expected_agreement(0.5) - 0.5) < 1e-12, "1b. p=0.5 → 0.5")
ok(proxy_expected_agreement(0.9) > proxy_expected_agreement(0.5),
   sprintf("1c. 극단 발화율일수록 기대 일치율 높다 (%.3f > %.3f)",
           proxy_expected_agreement(0.9), proxy_expected_agreement(0.5)))

cat("-- 2. ★완전 재현 (같은 축·같은 방향) --\n")
r <- proxy_reproduction(orig, score, "low")
ok(abs(r$agree - 1) < 1e-9 && abs(r$phi - 1) < 1e-9,
   sprintf("2a. 일치 %.1f%% · phi %.3f · Jaccard %.3f", 100*r$agree, r$phi, r$jaccard))
ok(isTRUE(r$qualified), "2b. qualified=TRUE")

cat("-- 3. ★위반 주입: 방향 반대 (실사고 ②) --\n")
rw <- proxy_reproduction(orig, score, "high")
ok(rw$phi < 0, sprintf("3a. 방향 뒤집으면 phi 음수 (%.3f)", rw$phi))
ok(rw$agree < rw$expected_agreement,
   sprintf("3b. ★일치율 %.1f%% 이 무작위 기대 %.1f%% **보다 낮다** — 실사고 재현",
           100*rw$agree, 100*rw$expected_agreement))
ok(!isTRUE(rw$qualified), "3c. qualified=FALSE (계약이 거부)")
ok(inherits(try(assert_proxy_reproduces(orig, score, "high"), silent = TRUE), "try-error"),
   "3d. assert 가 stop 발행")

cat("-- 4. ★위반 주입: 발화율만 맞춘 무관 축 (핵심 오독) --\n")
indep <- rnorm(n)                                  # 원 라벨과 무관
ri <- proxy_reproduction(orig, indep, "low")
ok(abs(ri$fire_rate - mean(orig)) < 1e-9,
   sprintf("4a. 발화율은 정확히 일치 (%.3f) — 그래도", ri$fire_rate))
ok(!isTRUE(ri$qualified),
   sprintf("4b. ★qualified=FALSE (일치 %.1f%% vs 기대 %.1f%%, 초과 %+.1f%%p) — **발화율 일치 ≠ 재현**",
           100*ri$agree, 100*ri$expected_agreement, 100*ri$excess))
ok(inherits(try(assert_proxy_reproduces(orig, indep, "low"), silent = TRUE), "try-error"),
   "4c. assert 가 stop 발행")

cat("-- 5. ★위반 주입: NA 가 섞인 축의 정렬 (실사고 ③) --\n")
D <- data.table(good = score, bad_allna = rep(NA_real_, n),
                bad_const = rep(1, n), noise = indep)
sel <- proxy_select_axis(orig, D)
ok(!is.null(sel$best), "5a. 최적 축 선택 성공")
ok(identical(sel$best$axis, "good") && identical(sel$best$direction, "low"),
   sprintf("5b. ★NA/상수 축을 제치고 진짜 축 선택 (%s/%s · phi %.3f)",
           sel$best$axis, sel$best$direction, sel$best$phi))
ok(!any(is.na(sel$table[qualified == TRUE, phi])), "5c. qualified 행에 NA phi 없음")

cat("-- 6. ★한 이름 조회 금지: 축 전수 열거 (실사고 ①) --\n")
ax <- proxy_numeric_axes(D)
ok(all(c("good","noise") %in% ax), sprintf("6a. 유효 축 전수 열거: %s", paste(ax, collapse=", ")))
ok(!("bad_const" %in% ax), "6b. 상수 축(고유값<10) 제외")
ok(!("bad_allna" %in% ax), "6c. 전량 NA 축 제외")

cat("-- 7. 경계 --\n")
ok(!isTRUE(proxy_reproduction(orig[1:8], score[1:8], "low")$qualified), "7a. n<12 → 판정 불가")
e <- proxy_select_axis(orig, data.table(x = rep(1, n)))
ok(is.null(e$best), "7b. 수치 축 0개 → best NULL (조용히 통과 안 함)")

cat("-- 8. ★실사고 수치 재현 --\n")
## Category(RISK_ON, 발화율 71.7%) vs 반대 방향 축 → 일치 43.5% 수준
ok(rw$agree < 0.50 && rw$expected_agreement > 0.55,
   sprintf("8. 방향 오류 시 일치 %.1f%% < 기대 %.1f%% (실사고: 43.5%% vs 59.5%%)",
           100*rw$agree, 100*rw$expected_agreement))

cat(sprintf("\n=== 결과: %d PASS / %d FAIL ===\n", P, F))
# 2026-08-20: 배터리는 마지막 줄의 JSON 요약만 읽는다. 이 줄이 없어 이 파일은
#   등재조차 되지 못했다(측정 권위 계약이 회귀 보호 밖에 있었음).
cat(sprintf("{\"test\":\"test_proxy_axis\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", P, F, P + F))
if (F > 0) quit(status = 1L)
