#==============================================================================
# Telegram brief — WT-D20260508_013 RISK_DONE (v6 SOT)
#==============================================================================
suppressPackageStartupMessages({library(jsonlite)})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

# Σ method 비교 (TABLE_NROW>=2, ncol<=2 strict)
sigma_df <- data.frame(
  추정기 = c("표본 공분산", "Ledoit-Wolf 축소", "Gerber RMT", "팩터모형 시장베타"),
  진단   = c("양정치성 위반 조건수 1.4e11",
             "양정치성 통과 조건수 1, 축소율 1.0 정보 0",
             "양정치성 위반 -3e-3",
             "양정치성 통과 조건수 1055 시장베타 21%"),
  stringsAsFactors = FALSE
)

stress_df <- data.frame(
  국면      = c("GFC 2008 18m", "EuDebt 2011 6m", "China 2015 9m",
                "VolShock 2018 11m", "COVID 2020 6m", "Inflation 2022 12m"),
  슬리브vsBM = c("-24.31pp 약화", "-21.27pp 약화", "+12.52pp 우위",
                 "+15.56pp 우위", "-16.59pp 약화", "+30.17pp 우위"),
  stringsAsFactors = FALSE
)

tg_agent_brief(
  agent = "Risk",
  title = "WT-D20260508_013 RISK_DONE — Σ 추정 + 다양화 검증 + 다양화원본 정직",
  as_of = "2026-05-08",
  sections = list(
    list(
      type = "summary",
      body = "방어 분류 철회 → 다양화원본 정직. 8 위기 3/6 우위, σ감소 -9.19% w=10%."
    ),
    list(
      type = "table",
      heading = "공분산행렬 추정기 5종 검증",
      df = sigma_df
    ),
    list(
      type = "kv",
      heading = "직교성 + 다양화 효과",
      kv = list(
        "벤치 KOSPI 상관 전기간"   = "+0.025 (95% 부트구간 [-0.18, +0.16])",
        "벤치 KOSPI 상관 최근60월" = "+0.121",
        "꼬리의존도 하위5%"         = "0.222 약-중간",
        "표준편차 감소 알파10%"   = "-9.19% (혼합 변동성 6.61% → 6.00%)",
        "표준편차 감소 알파15%"   = "-13.30%"
      )
    ),
    list(
      type = "table",
      heading = "8 위기 검증 (롱숏 HML 기준 - 롱온리 변환은 Forge)",
      df = stress_df
    ),
    list(
      type = "bullet",
      heading = "주요 발견",
      items = c(
        "공분산 축소율 1.0 → 단위행렬 수렴, 정당 (관측 268 < 종목 348 고차원)",
        "정보적 공분산은 팩터모형 (시장베타 평균 0.728 산포 0.287)",
        "꼬리위험 모수 ξ=-0.078 가벼운꼬리, 99% 손실위험=13.71%/월, 기대조건부손실=15.84%",
        "Hill 알파=2.32 < 3 = 무거운꼬리 좌측 (롱숏 변동성 vs 벤치 비율 1.008)",
        "조건부 방어 게이트2 미달 비율 신뢰구간 불안정 → 방어 분류 철회"
      )
    ),
    list(
      type = "bullet",
      heading = "Codex Round 1 8 우려 처리",
      items = c(
        "C1 공분산 단위행렬 수용 부분, 팩터모형 조건수 1055 보완",
        "C2 손실위험 위반 부분, 롱숏 측정 vs 롱온리 변환 Forge",
        "C3 위기 표본 5건 수용, 주의+위기 풀링 29건 부트 신뢰구간",
        "C4 군집 스타일 부분, 벤치 한계 + 활성북 Forge 의무",
        "C5 롱숏 → 롱온리 20종 변환 Forge",
        "C6 조건부방어 위기알파 Forge 위임 → 다양화원본 정직",
        "C7 산출물 부재 수용, 신규 도전노트 추가",
        "C8 253일 vs 252일 정정, 5월 8일 신선도락"
      )
    ),
    list(
      type = "bullet",
      heading = "다음 단계 — Optimizer Agent 의무",
      items = c(
        "공분산 선택: 단위행렬 (보수) vs 팩터모형 조건수 1055 (정보적)",
        "슬리브 비중 5-15% 점진 추가, 혼합 70/15/15 → 65/15/15/5 또는 60/15/10/15",
        "롱온리 20종 슬리브 형태로 운용 변환",
        "변동성 감소 -0.5% 목표"
      )
    ),
    list(
      type = "bullet",
      heading = "Q-Lead escalate (HIGH≥5 trigger)",
      items = c(
        "본 risk agent가 자율 처리 8건 분류 + 보완",
        "그러나 admit 결정은 Forge 롱온리 검증 + Architect 3rd source 후",
        "메커니즘 (Atilgan 2020 만성 악재 underreaction) 일관 + 급락 보호 부재",
        "다양화원본 자격: 직교성 + σ감소 + HHI 0.0049 (유효N 205) 우수",
        "최종 입장: APPROVE_CONDITIONAL_DIVERSIFIER (방어 분류 정직 철회)"
      )
    )
  ),
  decode_jargon = TRUE,
  decode_mode = "inline_first"
)

cat("\n[Telegram brief sent]\n")
