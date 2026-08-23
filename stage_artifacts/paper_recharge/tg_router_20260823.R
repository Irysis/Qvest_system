setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent   = "Q-Lead",
  title   = "논문 라우터 v2 — 20260823",
  relaxed = TRUE,
  sections = list(
    list(
      name = "라우팅 결과",
      body = "alpha 1 / optimizer 6 / risk 4 / skip 19 (총 30편)\nmode_queue 신규 10편 등재"
    ),
    list(
      name = "AUTORUN 완료 — 2608.20020",
      body = "comovement_reconfiguration_rate (베타 불안정성)\n판정: QUARANTINE (Grade F)\nIC=-0.028 역방향 | OOS=-0.926 | MDD=76.1%"
    ),
    list(
      name = "AUTORUN 기전",
      body = "미국 VRP x 공동이동 구조 변화 신호 → KR 롱온리에서 방향 반전\n위기 회복 국면 아웃퍼폼(COVID+29%/EuDebt+26%) 조건부 재시도 가능"
    ),
    list(
      name = "QUEUED",
      body = "2608.14323 MFCF 신경망 — 풀텍스트 fetch 후 착수"
    ),
    list(
      name = "mode_queue 우선",
      body = "⭐optimizer: RL adjoint / Pontryagin / 보조태스크\n⭐risk: 공동이동 위험모델(2608.20020)"
    ),
    list(
      name = "다음 라운드",
      body = "NP1: stable_comovement (-beta SD long)\nNP2: 매크로 레짐 조건부 (Lane D)\n2608.14323 MFCF: 풀텍스트 fetch"
    )
  )
)

cat("Telegram sent OK\n")
