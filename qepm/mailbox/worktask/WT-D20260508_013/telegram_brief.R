#==============================================================================
# Telegram brief — WT-D20260508_013 ALPHA_DONE (v6 SOT)
#==============================================================================
suppressPackageStartupMessages({library(jsonlite)})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

# Build hard-validation table as data.frame (TABLE_NROW>=2, ncol<=2 strict)
hv_df <- data.frame(
  지표  = c("정보계수", "안정성ICIR", "Harvey-NW t값", "부기간 sign",
            "DSR Bailey", "decile 단조성", "회전율연환산", "방어비율"),
  결과  = c("0.032/0.071", "0.18/0.41", "+2.86/+3.94", "3/3 PASS",
            "0.0 / PSR1.0", "0.71 PASS", "323% PASS", "+17.9 PASS"),
  stringsAsFactors = FALSE
)

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260508_013 ALPHA_DONE — Atilgan 2020 좌측꼬리 모멘텀 한국 단면",
  as_of = "2026-04-30",
  sections = list(
    list(
      type = "summary",
      body = "Atilgan 2020 한국응용 - 엄격 5/5 졸업 4건 미달, 최근60월 3/3 통과, 방어비율+17.9, 다양화후보."
    ),
    list(
      type = "table",
      heading = "엄격검증 (전기간252월 / 최근60월)",
      df = hv_df
    ),
    list(
      type = "kv",
      heading = "직교성 vs 기존 세 알파",
      kv = list(
        "왜도 비대칭성 알파"     = "Pearson -0.059 / Spearman +0.026 강건",
        "저베타 차익거래 알파"   = "Pearson +0.107 / Spearman +0.084 강건",
        "혼합 모멘텀 근사 알파" = "Pearson +0.111 / Spearman +0.161 강건"
      )
    ),
    list(
      type = "bullet",
      heading = "Codex 비판 7건 처리",
      items = c(
        "C1 다중검정 t공식 산술버그 수용, 함수수정 오+44 → 진+2.86",
        "C2 전기간 5/5 졸업미달 수용, 다양화후보 reframe",
        "C3 RF-A3 비율 2.69 부분, 한국 개인투자자 비중확대 정합",
        "C4 decile단조성 반박, C5 정정 후 0.71 통과",
        "C5 same-day 유동성 수용, t-1 strict 정정",
        "C6 직접 parquet read 수용, 신호일 추출 rawdata 기반",
        "C7 검증 1/3 수용, alpha 자명 후속 Risk+Forge"
      )
    ),
    list(
      type = "bullet",
      heading = "5x5 격자 결과 확인",
      items = c(
        "고모멘텀 + 저꼬리위험 코너 평균 월수익 +1.36%",
        "저모멘텀 + 고꼬리위험 코너 평균 월수익 +0.54%",
        "코너 차이 연환산 +5.31% Atilgan 2020 방향 정합",
        "단순 곱셈형 정보계수 -0.030 INVERSE 한국 비작동 substantive 발견"
      )
    ),
    list(
      type = "bullet",
      heading = "다음 단계 — Risk Agent 의무",
      items = c(
        "위기정보계수 8개 스트레스 윈도 측정 ≥ +0.05",
        "최대낙폭 완화 기준 strategy 대비 ≥ 5pp",
        "공분산행렬 추정 + 다양화 비율 혼합 대비 추가 효과",
        "꼬리위험 + 군집위험 + 스타일 진단",
        "조건부 방어 공리 정식 분류 다양화 vs 방어"
      )
    ),
    list(
      type = "bullet",
      heading = "최종 입장",
      items = c(
        "alpha agent stance: APPROVE_CONDITIONAL_DIVERSIFIER",
        "Risk + Forge + Architect downstream 조건부 검증 의무",
        "참조: Atilgan-Bali-Demirtas-Gunaydin 2020 JFE 135"
      )
    )
  ),
  decode_jargon = TRUE,
  decode_mode = "inline_first"
)

cat("\n[Telegram brief sent]\n")
