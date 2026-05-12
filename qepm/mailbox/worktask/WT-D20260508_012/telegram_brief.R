#==============================================================================
# Alpha Agent Telegram Brief — WT-D20260508_012
# v6 SOT compliant. tg_agent_brief() 진입점만 호출.
# Korean semi-formal, 한글 정통 용어 + Hard Validation 표.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ_ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Alpha-Research",
  title = "WT-D20260508_012 G안 옵션 꼬리위험 국면 지표 결과",
  sections = list(
    list(type = "summary",
         body = paste0(
           "옵션 chain 16년 자산 + 학술 4편 (BKM 2003 / Du-Kapadia 2012 / ",
           "BTZ 2009 / AFT 2017) 응용 → 4-pillar two-stage expanding ",
           "percentile composite 국면 지표. m4 (변동성/추세/거시) 직교 4번째 축. ",
           "B안 (독립 overlay) 채택. 발견 단계 종착, 배포 별도 WT 필요."
         )),

    list(type = "kv", emoji = "📊", heading = "Hard Validation 결과",
         kv = list(
           "회상도 (8 stress 中)" = "5/6 = 0.833 (관문 ≥ 0.70 PASS)",
           "오탐률" = "9.7% (관문 ≤ 20% PASS)",
           "평균 선행일수" = "-4.6일 (관문 ≥ 5 FAIL)",
           "상위 절반 평균 선행" = "+4.0일 (slow-burn subset)",
           "엄격 5관문 통과" = "FAIL (선행일수 단일 사유)",
           "완화 3관문 통과" = "PASS (회상 + 오탐 + 지속)"
         )),

    list(type = "kv", emoji = "🔬", heading = "직교성 + 국면별 분포",
         kv = list(
           "m4 종합국면 상관" = "0.536 (변동성 축 일부 공유)",
           "m4 cash비중 상관" = "0.174 (실효 출력 직교)",
           "PEACE 일별 q05" = "-1.42% (n=2137일 / 61.3%)",
           "TAIL_STRESS q05" = "-2.78% (n=464일 / 13.3%)",
           "꼬리사건 빈도비율" = "7.4배 (PEACE 1.26% → STRESS 9.27%)",
           "Welch t (STRESS-PEACE)" = "2.34 (p=0.020, 유의)"
         )),

    list(type = "bullet", emoji = "🚩", heading = "잔여 우려 + 한계",
         items = c(
           "선행일수 -4.6일 — fast-crash (China/VolShock/Inflation)는 일치, slow-burn (COVID +20일 / Mini_Flash +6일) 만 선행. BTZ 2009 RFS Table 5 정합.",
           "EuDebt_II_2011 burn-in 252일 내 1건 누락 (in-window 5/5=1.0 / 6 denominator 5/6=0.833 보고)",
           "TAIL_STRESS 일별 평균 수익률 +0.19% (PEACE 0%) — post-stress rebound. 신호는 동시확인용, 1일 방향 예측 불가",
           "AX-008 1/3 (alpha PASS, Forge/Architect 보류). 배포_상태 = design_only_NOT_admitted",
           "C13 수동 부호 반전 면제: BKM 2003 RFS Eq.(7) 학술 표준 + Factor DB 호출 0건"
         )),

    list(type = "bullet", emoji = "🤔", heading = "Codex Critic Round 1",
         items = c(
           "stance: REVISE / veto_flag: false",
           "9 concerns: ACCEPT 6 + PARTIAL 2 + REBUTTAL 1 (C3 C13 면제)",
           "11 spec 수정 적용 (deliverable_kind 명시 / 5관문 분리 / page-level 인용 / run_all.R 등)",
           "Q-Lead 검토 권고 trigger: HIGH severity ≥ 5"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 단계 권고",
         items = c(
           "도훈 의사결정: m4 4축 conviction → Risk Agent spawn (Layer D 영향 Σ + tail-conditional CVaR)",
           "또는 발견 종착 보존 + Architect 외부 검증 (AX-008 2/3 진입)",
           "또는 별도 deployment WT 생성 (β_tail KR 적합성 백테스트)",
           "PG2 STR_1715 운용 무영향 (Layer D 미장착, 5월 70%/30% 그대로)"
         ))
  )
)
