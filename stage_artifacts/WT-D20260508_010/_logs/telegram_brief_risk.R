#==============================================================================
# Risk Agent Telegram Brief — WT-D20260508_010
# v6.3 SOT compliant
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ_ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Risk",
  title = "왜도 알파 R14_DUVOL 위험 진단 — 분산 source 부분 확인",
  sections = list(
    list(type = "summary",
         body = "R14_DUVOL 알파 단독 진단 완료. 음의 -0.418 표면 상관은 시계열 재산출 시 -0.087로 약함. 분산 효과 부분 확인."),

    list(type = "kv", emoji = "📊", heading = "핵심 결과",
         kv = list(
           "공분산 조건수" = "202.62 (역할 기준 500 미만)",
           "분산 비율" = "3.245 (강한 분산)",
           "워크포워드 상관" = "-0.087 (CI [-0.26, 0.18])",
           "변동성 절감 7대3" = "+3.32% (양의 효과 확인)",
           "샤프지수 개선" = "+0.16 (1.86 → 2.03)"
         )),

    list(type = "kv", emoji = "🛡️", heading = "역할 분류",
         kv = list(
           "위기 정보계수" = "+0.020 (CI 0 포함)",
           "정상 정보계수" = "+0.058 (유의)",
           "위기-정상 비율" = "0.39 (1 미만)",
           "최대낙폭 구제" = "-0.005 (악화)",
           "결과 권고" = "방어형 X / 분산형 O"
         )),

    list(type = "bullet", emoji = "🚩", heading = "잔여 위험",
         items = c(
           "공리 AX-001 v2 위기 알파 약화 — 방어형 분류 거부",
           "단일 슬리브 알파 — Optimizer 단계서 다중 슬리브 결합 필수",
           "10분위 단조성 0.164 (선형 long-short 부적합)",
           "Codex strict 조건수 100 미충족 (Optimizer/Governor 결정)"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 단계",
         items = c(
           "Optimizer 단계 진행 — 분산형 결합 검토",
           "위기 알파 부재로 단독 운용 금지",
           "Hybrid 70 + R14_DUVOL 30 결합 후보"
         ))
  )
)
