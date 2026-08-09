## test_moment_fragility.R — 위반 주입 테스트
## ★검사기가 진짜 위반을 잡는지 확인한다(일부러 틀린 입력 주입 → 발화 확인).
## "경고 0" 은 합격이 아니라 정지 신호다 — 양성 대조를 반드시 포함한다.
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/contracts/moment_fragility.R")
set.seed(20260809)
PASS <- 0L; FAIL <- 0L
chk <- function(label, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  [PASS] %s\n", label)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s  %s\n", label, detail)) }
}

cat("=== 1. 양성 대조 — 진짜 강건한 비대칭은 ROBUST 로 통과해야 한다 ===\n")
## 왼쪽으로 치우친 분포 vs 오른쪽으로 치우친 분포 (전 분위에 걸친 진짜 비대칭)
off <- -rexp(3000, 1)            # 왼쪽 꼬리
on  <-  rexp(3000, 1)            # 오른쪽 꼬리
r <- assert_moment_robust(on, off, "skew")
chk("진짜 비대칭 -> ROBUST", r$verdict == "ROBUST", paste("verdict =", r$verdict))
chk("강건 측도 부호가 적률과 일치", sign(r$bowley_diff) == sign(r$moment_diff),
    sprintf("bowley %+.3f vs moment %+.3f", r$bowley_diff, r$moment_diff))

cat("=== 2. ★위반 주입 A — 이상치 소수가 만든 가짜 왜도 ===\n")
## 대칭 정규 + 극단 상승 3개만 주입 (FQ-182 실사고 재현)
base <- rnorm(2000, 0, 0.02)
on2  <- c(base, 0.25, 0.30, 0.35)          # 3개 극단 양수
off2 <- rnorm(6000, 0, 0.014)
r2 <- assert_moment_robust(on2, off2, "skew")
chk("이상치 주입 -> OUTLIER_DRIVEN 또는 ROBUST_MEASURE_DISAGREES",
    r2$verdict %in% c("OUTLIER_DRIVEN", "ROBUST_MEASURE_DISAGREES"), paste("verdict =", r2$verdict))
chk("적률 왜도는 크게 양수(속아넘어가는 지표)", r2$moment_diff > 0.3,
    sprintf("moment_diff %+.3f", r2$moment_diff))
chk("강건 왜도는 거의 0(속지 않는 지표)", abs(r2$bowley_diff) < 0.10,
    sprintf("bowley_diff %+.4f", r2$bowley_diff))
chk("drop-k 로 부호 반전 검출", is.finite(r2$first_sign_flip_k),
    sprintf("first_flip_k = %s", r2$first_sign_flip_k))

cat("=== 3. ★위반 주입 B — 강건 측도가 적률과 부호 불일치 ===\n")
## 중앙부는 왼쪽 치우침인데 꼬리에 큰 양수 몇 개
on3 <- c(rnorm(1500, 0.005, 0.01), -rexp(500, 30), 0.4, 0.45)
off3 <- rnorm(6000, 0, 0.014)
r3 <- assert_moment_robust(on3, off3, "skew")
chk("부호 불일치/이상치 계열 검출",
    r3$verdict %in% c("ROBUST_MEASURE_DISAGREES", "OUTLIER_DRIVEN"), paste("verdict =", r3$verdict))

cat("=== 4. 경계 — 표본 부족은 INSUFFICIENT ===\n")
r4 <- assert_moment_robust(rnorm(20), rnorm(20), "skew")
chk("n<50 -> INSUFFICIENT", r4$verdict == "INSUFFICIENT", paste("verdict =", r4$verdict))

cat("=== 5. robust_skew 자체 성질 ===\n")
chk("대칭분포 Bowley ~ 0", abs(robust_skew(rnorm(5000))$bowley) < 0.08)
chk("우편향 Bowley > 0", robust_skew(rexp(5000))$bowley > 0.05)
chk("좌편향 Bowley < 0", robust_skew(-rexp(5000))$bowley < -0.05)
chk("유계 [-1,1]", { b <- robust_skew(rexp(5000))$bowley; b >= -1 && b <= 1 })

cat("=== 6. moment_dropk 성질 ===\n")
d <- moment_dropk(c(rnorm(1000), 5, 6), "skew", 3L)
chk("k=0 이 원판", isTRUE(all.equal(d$value[1], .m3_skew(c(rnorm(0), c(rnorm(1000), 5, 6))), tolerance = 1)))
chk("극단 제거 시 왜도 감소", abs(d$value[3]) < abs(d$value[1]),
    sprintf("k0 %+.3f -> k2 %+.3f", d$value[1], d$value[3]))
chk("행 수 = k_max+1", nrow(d) == 4L)

cat(sprintf("\n=== 결과: PASS %d · FAIL %d ===\n", PASS, FAIL))
if (FAIL > 0) quit(status = 1)

cat("=== 7. ★FQ-182 실사고 재현 — 초판 로직이 놓친 케이스 ===\n")
## 실사고 구조: Bowley diff 가 거의 0 이나 **부호는 일치**(0.032), 적률 diff 0.581
## 초판은 sign_ok=TRUE 로 ROBUST 를 냈다. 수리판은 drop-k 크기 붕괴로 잡아야 한다.
set.seed(4242)
on7  <- c(rnorm(2000, 0, 0.020), 0.22, 0.26)   # 극단 2개
off7 <- rnorm(6700, 0, 0.014)
r7 <- assert_moment_robust(on7, off7, "skew")
chk("FQ-182 형 케이스 -> OUTLIER_DRIVEN", r7$verdict == "OUTLIER_DRIVEN",
    sprintf("verdict=%s · flip_k=%s · collapse_k=%s · moment %+.3f · bowley %+.4f",
            r7$verdict, r7$first_sign_flip_k, r7$first_collapse_k, r7$moment_diff, r7$bowley_diff))
chk("부호 일치인데도 잡혔는가(초판 사각 실증)",
    r7$verdict == "OUTLIER_DRIVEN" && sign(r7$bowley_diff) == sign(r7$moment_diff),
    sprintf("bowley %+.4f · moment %+.3f", r7$bowley_diff, r7$moment_diff))
cat(sprintf("\n=== 최종: PASS %d · FAIL %d ===\n", PASS, FAIL))
if (FAIL > 0) quit(status = 1)
