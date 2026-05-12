#==============================================================================
# WT-D20260508_004 — Step 10: Telegram Brief (v6.2 SOT)
#
# 4 sections (한글 우선):
#   📚 연구 컨텍스트
#   📊 핵심 결과 (kv)
#   🚩 잔여 위험
#   ➡️ 다음 단계
#
# 표 사용 최소화. kv (한글 4-6자) + bullet 우선.
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))

WT_ID <- "WT-D20260508_004"

# Load final state
val <- fromJSON(file.path(PROJ, "stage_artifacts/WT_D20260508_004/alpha_validation.json"))

result <- tg_agent_brief(
  agent = "Alpha",
  title = sprintf("%s 거시 잔차 알파 — empirical FAIL 정직 보고", WT_ID),
  sections = list(
    list(
      heading = "연구 컨텍스트",
      emoji = "\U0001F4DA",
      type = "text",
      body = paste0(
        "거시 잔차 → 종목 노출 → cross-section alpha 가설. ",
        "한국 ECOS 7 + FRED 6 = 12 거시 변수 AR(1) 잔차 → 24개월 종목별 베타 → ",
        "expanding IC top-4 부호 정렬 합성 + 6개월 EMA. ",
        "Chen-Roll-Ross 1986 + Cooper-Gulen-Schill 2008 + Asness 외 2013."
      )
    ),
    list(
      heading = "핵심 결과",
      emoji = "\U0001F4CA",
      type = "kv",
      kv = list(
        "1개월 IC" = "0.0115 (목표 0.04 미달)",
        "1개월 정보비" = "0.110 (목표 0.20 미달)",
        "Harvey-t 1M" = "1.219 (Bonferroni 2.89 미달)",
        "Harvey-t 12M" = "1.754 (목표 3.0 미달)",
        "섹터중립 IC" = "0.0001 (붕괴 RF-A4)",
        "직교성" = "max 0.162 (mandate 0.25 통과)",
        "DSR 부트스트랩" = "0.0 (fat-tail kurt 4.29)",
        "Codex 판정" = "REJECT 9개 우려",
        "졸업 상태" = "REJECT_GRADUATION"
      )
    ),
    list(
      heading = "잔여 위험",
      emoji = "\U0001F6A9",
      type = "bullet",
      items = c(
        "RF-A4 활성: 신호 대부분 섹터 거시 tilt — 종목 알파 아님",
        "RF-A2 활성: 합성 정보비 0.110 < 단일 최선 0.187 개선 음수",
        "RF-A1 활성: 부분기간 strict 1/3 (p3만 0.209)",
        "예측자 자기상관 0.987 — 6M EMA 의도이나 신선도 희석",
        "AX-008 검증 1/3 (Codex REJECT, Architect/Forge 미실행)"
      )
    ),
    list(
      heading = "다음 단계",
      emoji = "➡️",
      type = "bullet",
      items = c(
        "Q-Lead escalate 권고 (HIGH 4 + MEDIUM 5 누적)",
        "본 가설 archive — graduation NO 정합",
        "Future research 4건 보존 (단일 베타 / PCA / IPCA / 섹터)",
        "challenge_note + alpha_package + 시계열 53502행 정합 보존"
      )
    )
  ),
  as_of = "2026-05-08",
  decode_jargon = TRUE,
  decode_mode = "inline_first"
)

cat("[10] tg_agent_brief result:\n")
print(result)
