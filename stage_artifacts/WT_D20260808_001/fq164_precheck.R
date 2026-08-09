## FQ-164 착수 전 사전 확인 — 회전율 축의 **구조적 상한** vs 검출 필요치
## 가설: 부분-리밸(교체 상한)이 staleness 와 다른 축이라 교환이 비대칭일 수 있다.
## ★그런데 회전율 축에서 얻을 수 있는 것의 **상한은 총 비용**이다. 그 상한이 필요치보다 작으면
##   설계가 무엇이든 착수 전 폐기 대상이다(2026-08-08 규약: 필요 > 함의면 착수 전 폐기).
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[164] ",fmt,"\n"),...))
source("02_Infrastructure/contracts/required_effect_size.R")

## ── 승계 수치 (WT-D20260809_001 실측 — 재측정 아님) ─────────────────────────
turnover_yr <- 11.7422          # /yr
cost_oneway <- 0.0015           # 15bps
n_months    <- 283L
say("승계 입력 (WT-D20260809_001):")
say("  회전율 %.4f/yr · 비용 %.0fbps · n=%d개월", turnover_yr, cost_oneway*1e4, n_months)

## ── 회전율 축의 구조적 상한 = 총 비용 (전부 없애도 그 이상 못 얻는다) ──────
max_gain_ann <- turnover_yr * cost_oneway
say("★회전율 축 **구조적 상한** = 총 비용 = %.4f/yr = 연 %.2f%%", max_gain_ann, max_gain_ann*100)
say("  (회계 항등 검증됨: 실측 alpha 차이 1.76%%p 와 일치)")
say("  ⇒ 교체상한·staleness·무엇이든 회전율을 건드려 얻을 수 있는 최대치다.")
say("  ⇒ 게다가 이 상한은 **신호 손실 0** 이라는 비현실적 가정 하의 값이다.")

## ── 같은 프레임의 검출 필요치 ───────────────────────────────────────────────
say("")
say("검출 필요치 (paired 프레임, sd 를 바꿔가며):")
for (sd_m in c(0.010, 0.015, 0.020, 0.026)) {
  r <- required_effect(n = n_months, t_threshold = 2.0, sd_monthly = sd_m, design = "full")
  say("  sd=%.3f -> 필요 연 %.2f%%   %s", sd_m, r$required_annual*100,
      if (r$required_annual > max_gain_ann) "★상한 초과 = 검출 불가" else "검출 가능 구간")
}
say("")
say("승계 실측 필요치 (M26 staleness 11셀): 연 3.01%% ~ 5.55%%")
say("관측 효과 범위:                        연 -2.70%% ~ +2.00%% (최대 |t| 0.858)")

say("")
say("=== 판정 ===")
if (max_gain_ann * 100 < 3.01) {
  say("★상한 %.2f%% < 최소 필요치 3.01%% ⇒ **회전율 축은 이 패널에서 구조적 저검정력**", max_gain_ann*100)
  say("  설계(교체상한/staleness/부분리밸)가 무엇이든 t=2.0 도달이 원리적으로 불가하다.")
  say("  ⇒ FQ-164 를 현 형태로 착수하면 결과는 INCONCLUSIVE_UNDERPOWERED 가 예정돼 있다.")
} else {
  say("상한이 필요치를 넘는다 — 착수 가능. 단 신호 손실 0 가정임을 유의.")
}
