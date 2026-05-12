#==============================================================================
# Telegram brief — WT-D20260508_013 FORGE_DONE (v6 SOT)
#==============================================================================

suppressPackageStartupMessages({library(jsonlite)})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

# 5 비중 실측 결과 표 (max 2 cols)
ratios_dt <- data.frame(
  비중       = c("0%", "5%", "10%", "15%", "20%"),
  실측SR_MDD = c("1.811 / -0.195", "1.818 / -0.189", "1.813 / -0.183", "1.795 / -0.192", "1.762 / -0.217"),
  stringsAsFactors = FALSE
)

# 추정 vs 실측 격차
gap_dt <- data.frame(
  비중      = c("0%", "5%", "10%", "20%"),
  추정대실측SR = c("1.651 / 1.811", "1.685 / 1.818", "1.712 / 1.813", "1.737 / 1.762"),
  stringsAsFactors = FALSE
)

# 위기 6개 분해 (2 cols)
crisis_dt <- data.frame(
  위기구간    = c("2008", "2011", "2018", "2020", "2022"),
  AR핵심대비  = c("-32.2pp", "-23.1pp", "-27.3pp", "+13.6pp", "-14.9pp"),
  stringsAsFactors = FALSE
)

tg_agent_brief(
  agent = "Forge",
  title = "WT-D20260508_013 FORGE_DONE — 좌측 꼬리 모멘텀 알파 5 비중 256개월 실측 — 추정 대 실측 격차 진단",
  as_of = "2026-05-08",
  sections = list(
    list(
      type = "summary",
      body = "5 비중 256m 실측 — 5% 위험조정 우월 / 위기 6개 중 1개만 양수 / 다양화 약화 진단"
    ),
    list(
      type = "table",
      heading = "5 비중 256개월 실측 (포퍼먼스애널리틱스)",
      df = ratios_dt
    ),
    list(
      type = "table",
      heading = "옵티마이저 추정 vs 포지 실측 격차 진단",
      df = gap_dt
    ),
    list(
      type = "table",
      heading = "위기 6개 알파 분해 (AR 핵심 대비)",
      df = crisis_dt
    ),
    list(
      type = "kv",
      heading = "포지 핵심 진단",
      kv = list(
        "독립 슬리브 실측" = "샤프지수 0.366 / 최대낙폭 -57.3% (옵티마이저 추정 0.708 대비 48% 침식)",
        "공분산 조건수" = "축약 1.0 (양정정) / 팩터 1055.4 (양정정, 단일팩터 한계 인정)",
        "다양화 측정" = "상관계수 알파-혼합 250개월 0.145 / 최근 60개월 0.055",
        "AX-001 v2 실측" = "약/정상 비율 -0.106 친순환 (리스크 주장 +17.89과 정반대 부호)",
        "다중슬리브 예외" = "4슬리브 (혼합 3 + WT_013 1) AX-007 정합",
        "AX-008 진척" = "포지 + 코덱스 = 2/3. 아키텍트 3차원 의무 (잠금구간 / 하비 5스펙 / 다중팩터)"
      )
    ),
    list(
      type = "kv",
      heading = "코덱스 라운드 1 — REJECT 6 우려",
      kv = list(
        "비중 상한 위반" = "ACCEPT-PARTIAL (옵티마이저 0.21 드리프트 / 포지 0.20009 허용오차)",
        "잠금구간 마커" = "ACCEPT (마커 누락 — 아키텍트 의무)",
        "하비 5스펙" = "ACCEPT (전략단위 재산출 — 아키텍트 의무)",
        "일자 정합성" = "ACCEPT-PARTIAL (252개월 오타 → 250개월)",
        "팩터 조건수" = "ACCEPT (리스크 패스스루)",
        "5% 약함" = "PARTIAL_ACCEPT (포지 admit 권고 안 함, 도훈 결정)"
      )
    ),
    list(
      type = "kv",
      heading = "포지 1차 권고",
      kv = list(
        "추천 비중" = "A안 (0% 스킵) 또는 B안 (5% 보수적 다양화)",
        "비추천 비중" = "C안 (10% 옵티마이저 1차 — 실측 샤프 차이 무시할 만큼 작음)",
        "권고 근거" = "AX-001 v2 친순환 + 샤프 차이 노이즈 수준 + 다양화 약화 진단",
        "최종 결정" = "도훈/거버너 (포지 정량 데이터 제공만)"
      )
    )
  )
)
