## c1 — 사전등록대로 **착수 전 검정력 선언** (도달 불가 설계면 여기서 밝힌다)
## 오늘 확립: 사전등록 전에 required_effect_size 를 재지 않으면 도달불가 분기를 재도입한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[c1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")

inc <- bm_load_incumbent()
n_all <- nrow(inc); k_is <- floor(n_all*0.6); n_oos <- n_all - k_is
say("=== 창 분할 ===")
say("  전체 %d개월 · IS %d (%s~%s) · **OOS %d** (%s~%s)",
    n_all, k_is, min(inc$date), inc$date[k_is], n_oos, inc$date[k_is+1L], max(inc$date))
oos <- inc[(k_is+1L):n_all]
say("  OOS 구간 incumbent IR = %.4f (전기간 %.4f)", bm_ir(oos$active), bm_ir(inc$active))

say("=== ★검정력: OOS %d개월에서 ΔIR 을 얼마나 정밀하게 재는가 ===", n_oos)
## ΔIR 의 표준오차를 부트스트랩으로 직접 산출 (합성 슬리브: 상관 0.4 · IR 0.5 로 대표)
m_i <- mean(oos$active); s_i <- sd(oos$active)
set.seed(1)
mk_sleeve <- function(rho, ir_s) {
  e <- rnorm(nrow(oos)); e <- e - as.numeric(lm(e ~ oos$active)$fitted.values); e <- e/sd(e)
  a <- (oos$active - m_i)/s_i
  s <- rho*a + sqrt(1-rho^2)*e; s/sd(s)*s_i + ir_s/sqrt(12)*s_i
}
se_of <- function(rho, ir_s, w = 0.20, B = 1000L) {
  sl <- mk_sleeve(rho, ir_s)
  d <- replicate(B, { i <- sample.int(nrow(oos), nrow(oos), TRUE)
    bm_ir((1-w)*oos$active[i] + w*sl[i]) - bm_ir(oos$active[i]) })
  sd(d[is.finite(d)])
}
for (p in list(c(0.4,0.5), c(0.2,0.7), c(0.0,0.4))) {
  s <- se_of(p[1], p[2])
  say("  (rho %.1f · IR_s %.1f) → ΔIR 표준오차 **%.4f** · 유의(2se) 필요 효과 **%.4f**", p[1], p[2], s, 2*s)
}
say("  ★문턱 0.05 와 비교: 표준오차가 0.025 를 넘으면 **0.05 를 잡음과 구분 못 한다**")

say("=== ★셀 수와 다중검정 ===")
say("  설계: 선택규칙 3 x K 5 = **15셀** + 무작위 대조")
say("  15셀 중 하나가 우연히 0.05 를 넘을 확률(독립 가정, 셀당 5%%) = %.1f%%",
    100*(1 - 0.95^15))
say("  ⇒ ★**셀 전수 보고**로 처리한다(argmax 선택 금지 = 사전등록 명시). argmax 를 하면 DSR 게이트 대상.")

say("=== ★도달 가능성 판정 ===")
s_rep <- se_of(0.4, 0.5)
say("  대표 조건 표준오차 %.4f → 문턱 0.05 는 %.1f 표준오차", s_rep, 0.05/s_rep)
say("  ⇒ %s", if (0.05/s_rep >= 2) "검출 가능 설계" else
   "★**검정력 부족** — 문턱이 2 표준오차 미만이다. 결과는 구간추정으로만 읽고 통과/미달 단정 금지")
saveRDS(list(n_oos=n_oos, se=s_rep, is_end=inc$date[k_is]), file.path(OUT,"c1_power.rds"))
say("=== c1 완료 ===")
