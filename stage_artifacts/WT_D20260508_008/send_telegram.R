#==============================================================================
# WT-D20260508_008 Alpha — Telegram v6 SOT brief (한국 섹터 모멘텀 알파 검증)
#==============================================================================
suppressPackageStartupMessages({library(jsonlite)})
source("02_Infrastructure/telegram/telegram_notify.R")

sections <- list(
  list(
    heading = "한국 섹터 모멘텀 알파 검증 결과",
    emoji = "📌",
    type = "text",
    body = "Asness 2013 + Moskowitz-Grinblatt 1999 한국 KSI Lv1 27 sectors 12-1 cross-section 실증. 정직한 empirical fail."
  ),
  list(
    heading = "정보계수 + 통계 진단",
    emoji = "📊",
    type = "kv",
    kv = list(
      "정보계수 (Rank IC)" = "0.024 (기준 0.04)",
      "ICIR (안정성)" = "0.074 (기준 0.20)",
      "Harvey-NW t" = "1.66 (기준 3.0)",
      "부기간 안정성" = "0.55 (기준 0.5)",
      "최근3Y/전체 ICIR" = "4.12배",
      "Q5 MDD (36년)" = "-65.8%"
    )
  ),
  list(
    heading = "주요 위험 신호 (Challenge Flags)",
    emoji = "🚩",
    type = "bullet",
    items = c(
      "Codex 비평 7건 (HIGH 5 / MED 1) — REJECT stance",
      "AX-007 메커니즘 단절 직접 트리거 (단일 슬리브 20종 변환 불가)",
      "RF-A3 최근 3년 편향 4.12배 (반도체 사이클 집중)",
      "RF-A4 섹터 베팅 100% 신호 (섹터 중립 시 신호 0)",
      "Discovery 졸업 기준 4/5 미달 (DSR만 marginal pass)"
    )
  ),
  list(
    heading = "다음 단계 권고",
    emoji = "➡️",
    type = "bullet",
    items = c(
      "ARCHIVE_AS_LCODE — STR_055/STR_191/STR_089 saturation 4번째 재실증",
      "Q-Lead 후속 agent (Risk/Optimizer) spawn STOP 권고",
      "변형 경로: 섹터 × 가치 / 섹터 × 국면 / portfolio overlay 형태로만 재시도 의미"
    )
  )
)

result <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260508_008 ALPHA_DONE — 한국 섹터 모멘텀 알파 정직한 empirical fail",
  sections = sections
)
cat("Telegram dispatch result:\n")
str(result)
