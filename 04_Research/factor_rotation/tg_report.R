source("G:/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")
tg_agent_brief(
  agent = "Q-Lead",
  title = "직교 슬리브(EP) 확보 후 SJM 레짐 배합 재검증 — 직교 가설 기각",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "EP는 momentum과 0.91 상관·OOS alpha 붕괴라 직교 슬리브 아님. SJM 천장 미돌파, 직교 가설 기각."),
    list(type = "kv", emoji = "📊", heading = "EP 직교성",
         kv = list("EP vs STR_1715 상관" = "0.044 (직교)",
                   "EP vs 잔차모멘텀 상관" = "0.911 (비직교)",
                   "EP 풀 상관 중앙값" = "0.795",
                   "EP OOS 유지율" = "-0.26 (alpha 붕괴)")),
    list(type = "kv", emoji = "🔬", heading = "SJM+EP A/B (천장)",
         kv = list("EW 천장 SR" = "0.70 (불변)",
                   "SJM-EW 신규AS 미선택" = "0/0/0회",
                   "SJM 이득 정체" = "EW 희석 착시",
                   "2슬리브 결합 효과" = "결합<단독")),
    list(type = "bullet", emoji = "🚩", heading = "핵심 진단",
         items = c("EP는 STR_1715(멀티팩터)와만 직교 — momentum/value alpha와는 0.6~0.91 상관",
                   "EP standalone IS active SR 1.01 → OOS -0.26 (2018+ KR value decay 실재)",
                   "RCMA가 EP·신규 9모듈 전부 admit 거부(OOS 부호 미지속) — 정확 작동",
                   "제거검증: SJM이 EP를 0회 선택, 이득 증가는 평균 희석 착시뿐")),
    list(type = "bullet", emoji = "➡️", heading = "정직 판정",
         items = c("EP는 '직교 슬리브'가 아님 — 1715 무상관은 1715가 momentum이 아니라서일 뿐",
                   "직교 슬리브 조건 미충족으로 레짐 배합 실익 없음(비로버스트 유지)",
                   "진짜 직교원 = STR_1715류 멀티팩터 source (EP/momentum/value 아님)",
                   "FR_001 grade C 불변(net SR 0.88, OOS retention -0.08)"))
  ),
  footer = "📚 산출: ep_orthogonality.json / ep_multisleeve.json / sjm_ep_ablation.json"
)
