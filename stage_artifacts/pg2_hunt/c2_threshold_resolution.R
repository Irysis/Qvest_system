## c2 — ★★문턱 0.05 는 측정 해상도 안에 있는가 (거버넌스 수준 질문)
## c1 발견: OOS 108개월에서 ΔIR 표준오차 0.077 → 문턱 0.05 는 0.6 표준오차.
## ⇒ 만약 전기간 269개월에서도 표준오차가 0.05 를 넘는다면,
##    measurement-graduation 4절의 admission 문턱(ΔIR>=0.05)은 **이 표본 길이에서 판별 불가**다.
##    그건 내 라운드의 문제가 아니라 **게이트 설계의 문제**이므로 정확히 재서 보고해야 한다.
## ★주의: 이건 "문턱을 낮추자"는 제안이 아니다(제약 완화 금지, INV-7).
##    문턱은 그대로 두고 **판정에 신뢰구간을 병기해야 한다**는 측정 규율 문제다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[c2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")

inc <- bm_load_incumbent()
m_i <- mean(inc$active); s_i <- sd(inc$active)
say("=== incumbent === %d개월 · active 평균 %+.6f · sd %.6f · IR %.4f",
    nrow(inc), m_i, s_i, bm_ir(inc$active))

mk <- function(rho, ir_s, N, seed) {
  set.seed(seed)
  a <- (inc$active[1:N] - mean(inc$active[1:N]))/sd(inc$active[1:N])
  e <- rnorm(N); e <- e - as.numeric(lm(e ~ a)$fitted.values); e <- e/sd(e)
  s <- rho*a + sqrt(1-rho^2)*e
  s/sd(s)*s_i + ir_s/sqrt(12)*s_i
}
se_dIR <- function(rho, ir_s, N, w = 0.20, B = 1500L, seed = 11) {
  act <- inc$active[1:N]; sl <- mk(rho, ir_s, N, seed)
  d <- replicate(B, { i <- sample.int(N, N, TRUE)
    bm_ir((1-w)*act[i] + w*sl[i]) - bm_ir(act[i]) })
  d <- d[is.finite(d)]; c(se = sd(d), mean = mean(d))
}

say("=== 1. ★표본 길이별 ΔIR 표준오차 (rho 0.4 · IR_s 0.5 · w 0.20) ===")
say("  %8s %12s %14s %16s", "개월", "표준오차", "문턱/se", "판별 가능?")
for (N in c(60, 73, 108, 150, 200, 269)) {
  r <- se_dIR(0.4, 0.5, N)
  say("  %8d %12.4f %14.2f %16s", N, r["se"], 0.05/r["se"],
      if (0.05/r["se"] >= 2) "예(2se 이상)" else if (0.05/r["se"] >= 1) "경계" else "★아니오")
}

say("=== 2. 조건별 (269개월 고정) ===")
say("  %10s %10s %12s %12s", "rho", "IR_s", "표준오차", "문턱/se")
for (p in list(c(0.0,0.4), c(0.2,0.6), c(0.4,0.5), c(0.4,0.9), c(0.6,1.2))) {
  r <- se_dIR(p[1], p[2], 269L)
  say("  %10.1f %10.1f %12.4f %12.2f", p[1], p[2], r["se"], 0.05/r["se"])
}

say("=== 3. ★2 표준오차로 판별하려면 몇 개월이 필요한가 ===")
## se ~ c/sqrt(N) 가정으로 외삽 후 실측 확인
r269 <- se_dIR(0.4, 0.5, 269L)["se"]
need_N <- ceiling(269 * (r269/(0.05/2))^2)
say("  269개월 se %.4f → 필요 se %.4f (문턱/2) → 필요 표본 ≈ **%d개월 (%.1f년)**",
    r269, 0.05/2, need_N, need_N/12)
say("  ★현재 가용 최대 = 269개월. **부족 배수 %.1fx**", need_N/269)

say("=== 4. ★그래서 무엇이 달라지는가 ===")
say("  (a) 이 문턱은 '넘었다/못 넘었다' 의 이분 판정으로 쓸 수 없다.")
say("      점추정 ΔIR 옆에 **신뢰구간을 병기**해야 판정이 정직하다.")
say("  (b) 오늘 내 보고 재해석:")
inc73 <- inc[1:73]
say("      계약 국면규칙 ΔIR +0.0740 · 73개월 부트스트랩 CI [-0.040, +0.208]")
say("      → CI 가 0 과 0.05 를 **둘 다 포함**한다. '통과' 도 '미달' 도 단정 불가.")
say("      내가 '오버레이 후보 + 증거 누적 대기' 로 라우팅한 것은 결과적으로 맞았으나,")
say("      근거를 '에피소드 부족' 으로만 적었다 — **문턱 자체가 해상도 아래**라는 것이 더 근본이다.")
say("      48재료 ΔIR 중앙 -0.1888 은 se 0.077 대비 2.5se 라 **음수 판정은 유효**하다.")
say("      ⇒ ★비대칭: **탈락 판정은 신뢰할 수 있고 통과 판정은 신뢰할 수 없다**.")
say("  (c) ★제안 아님 주의: 문턱을 낮추자는 게 아니다(제약 완화 금지 INV-7).")
say("      문턱은 그대로 두고 **판정 산출에 CI 를 의무 병기**하는 것이 대응이다.")

say("=== 5. 계약 후보를 이 렌즈로 재판정 ===")
say("  점추정 +0.0740 · 부트 CI 0 포함 · 필요 표본 %d개월 vs 보유 73개월", need_N)
say("  ⇒ 정직한 라벨 = **UNRESOLVED (검정력 부족)**, 'BEATS_PG2' 아님")
say("     내 bm_delta_ir() 의 verdict 필드가 점추정만 보고 'BEATS_PG2' 를 찍는다 — **계약 수리 대상**")
saveRDS(list(se269=r269, need_N=need_N), file.path(OUT,"c2.rds"))
say("=== c2 완료 ===")
