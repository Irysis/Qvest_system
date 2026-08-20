## test_book_marginal_ci.R — bm_delta_ir() 의 CI-기반 verdict 검사
## 배경(2026-08-09 실사고): verdict 가 **점추정만** 보고 "BEATS_PG2" 를 찍었고 Q-Lead 가 그대로 보고했다.
##   그런데 ΔIR 표준오차는 73개월 0.0935 / 269개월 0.0460 이라 문턱 0.05 는 269개월에서도 1.09se.
##   2se 판별에 ~911개월 필요 = 가용치의 3.4배. ⇒ 점추정 통과 판정은 잡음일 수 있다.
## 이 검사는 ①CI 가 산출되는가 ②verdict_ci 가 CI 로 판정하는가
##   ③**일부러 잡음 슬리브를 주입**했을 때 UNRESOLVED/NO_IMPROVEMENT 로 발화하는가
##   ④명백한 양성은 여전히 BEATS_PG2 인가(양성 대조 보존 — 검사 사망 방지)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")

P <- 0L; F <- 0L
ok <- function(c, m) { if (isTRUE(c)) { P <<- P+1L; cat(sprintf("  PASS  %s\n", m)) }
                       else { F <<- F+1L; cat(sprintf("  FAIL  %s\n", m)) } }
cat("=== test_book_marginal_ci ===\n")

inc <- bm_load_incumbent()
s_i <- sd(inc$active); m_i <- mean(inc$active)
mk <- function(rho, ir_s, seed) {
  set.seed(seed)
  a <- (inc$active - m_i)/s_i
  e <- rnorm(nrow(inc)); e <- e - as.numeric(lm(e ~ a)$fitted.values); e <- e/sd(e)
  s <- rho*a + sqrt(1-rho^2)*e
  data.table(date = inc$date, ret_net = inc$benchmark_ret + (s/sd(s)*s_i + ir_s/sqrt(12)*s_i))
}

## ── 1. CI 산출 ──────────────────────────────────────────────────────────────
r1 <- bm_delta_ir(mk(0.0, 1.416, 1), weight = 0.20)
ci <- r1$delta_ir_ci
ok(is.list(ci) && isTRUE(ci$available), "1a. delta_ir_ci 산출됨")
ok(all(c("se","lo","hi","block","p_above_threshold") %in% names(ci)), "1b. CI 필드 완비")
ok(ci$lo < r1$delta_ir && r1$delta_ir < ci$hi,
   sprintf("1c. 점추정 %.4f 가 CI [%.4f, %.4f] 안", r1$delta_ir, ci$lo, ci$hi))
ok(ci$block >= 2L, sprintf("1d. 블록 부트스트랩 사용 (block=%d) — iid 는 자기상관에서 se 과소추정", ci$block))

## ── 2. ★양성 대조 보존: 압도적 양성은 여전히 BEATS_PG2 ──────────────────────
ok(identical(r1$verdict_ci, "BEATS_PG2"),
   sprintf("2. 무상관+IR동등(ΔIR %.3f, CI 하단 %.3f) → verdict_ci=%s", r1$delta_ir, ci$lo, r1$verdict_ci))

## ── 3. ★위반 주입: 문턱 **근처** 점추정 → UNRESOLVED 여야 (핵심 회귀) ────────
##  이것이 2026-08-09 실사고의 재현이다. 점추정은 0.05 를 넘지만 CI 가 0 을 포함한다.
found <- NULL
for (sd0 in seq(1, 60)) {
  rr <- bm_delta_ir(mk(0.45, 0.55 + sd0*0.02, 100 + sd0), weight = 0.20)
  if (is.finite(rr$delta_ir) && rr$delta_ir >= 0.05 && rr$delta_ir <= 0.13 &&
      isTRUE(rr$delta_ir_ci$available) && rr$delta_ir_ci$lo < 0.05) { found <- rr; break }
}
ok(!is.null(found), "3a. 문턱-근처 케이스 구성 성공 (점추정 통과 ∧ CI 하단 미달)")
if (!is.null(found)) {
  ok(identical(found$verdict, "BEATS_PG2"),
     sprintf("3b. 점추정 verdict 는 여전히 BEATS_PG2 (ΔIR %.4f) — 이것이 낡은 판정", found$delta_ir))
  ok(identical(found$verdict_ci, "UNRESOLVED"),
     sprintf("3c. ★CI verdict 는 UNRESOLVED (CI [%.4f, %.4f]) — 잡음을 통과로 보고하지 않는다",
             found$delta_ir_ci$lo, found$delta_ir_ci$hi))
}

## ── 4. 음성: 명백한 무개선 ───────────────────────────────────────────────────
r4 <- bm_delta_ir(inc[, .(date, ret_net = benchmark_ret)], weight = 0.20)
ok(r4$verdict_ci %in% c("NO_IMPROVEMENT","BELOW_THRESHOLD"),
   sprintf("4a. 벤치 슬리브 → verdict_ci=%s (ΔIR %.4f)", r4$verdict_ci, r4$delta_ir))
set.seed(9)
r5 <- bm_delta_ir(inc[, .(date, ret_net = benchmark_ret + rnorm(nrow(inc), 0, s_i))], weight = 0.20)
ok(!identical(r5$verdict_ci, "BEATS_PG2"),
   sprintf("4b. ★잡음 슬리브가 BEATS_PG2 를 못 받는다 (verdict_ci=%s · ΔIR %.4f)", r5$verdict_ci, r5$delta_ir))

## ── 5. sweep 이 CI 를 전달하고 beats 를 CI 로 판정 ───────────────────────────
sw <- bm_delta_ir_sweep(mk(0.45, 0.75, 7))
ok(all(c("ci_lo","ci_hi","se","verdict_ci","beats","beats_point","unresolved") %in% names(sw)),
   "5a. sweep 이 CI 컬럼을 전달")
ok(all(sw$beats[is.finite(sw$ci_lo)] == (sw$ci_lo[is.finite(sw$ci_lo)] >= 0.05)),
   "5b. sweep beats 가 **CI 하단** 기준")
ok(any(sw$beats_point) >= any(sw$beats),
   sprintf("5c. 점추정 통과(%d) >= CI 통과(%d) — 보수 방향", sum(sw$beats_point), sum(sw$beats)))

## ── 6. 표본이 짧을수록 CI 가 넓어지는가 (해상도 주장 자체의 검증) ────────────
w1 <- bm_delta_ir(mk(0.4, 0.6, 3)[1:80], weight = 0.20, require_overlap = 60L)
w2 <- bm_delta_ir(mk(0.4, 0.6, 3), weight = 0.20)
ok(isTRUE(w1$delta_ir_ci$available) && isTRUE(w2$delta_ir_ci$available) &&
   w1$delta_ir_ci$se > w2$delta_ir_ci$se,
   sprintf("6. 짧은 표본 se %.4f(n=%d) > 긴 표본 se %.4f(n=%d)",
           w1$delta_ir_ci$se, w1$n_overlap, w2$delta_ir_ci$se, w2$n_overlap))

## ── 7. bootstrap=FALSE 도 죽지 않는가 (성능 경로) ────────────────────────────
r7 <- bm_delta_ir(mk(0.2, 0.8, 5), weight = 0.20, bootstrap = FALSE)
ok(identical(r7$verdict_ci, "UNRESOLVED_NO_CI") && is.finite(r7$delta_ir),
   "7. bootstrap=FALSE 시 UNRESOLVED_NO_CI 로 명시 (조용히 통과시키지 않음)")

cat(sprintf("\n=== 결과: %d PASS / %d FAIL ===\n", P, F))
# 2026-08-20: 배터리는 마지막 줄의 JSON 요약만 읽는다. 이 줄이 없어 이 파일은
#   등재조차 되지 못했다(측정 권위 계약이 회귀 보호 밖에 있었음).
cat(sprintf("{\"test\":\"test_book_marginal_ci\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", P, F, P + F))
if (F > 0) quit(status = 1L)
