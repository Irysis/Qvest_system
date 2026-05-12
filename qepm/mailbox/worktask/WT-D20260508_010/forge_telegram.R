#==============================================================================
# WT-D20260508_010 Forge — Telegram brief (v6 SOT 양식)
#==============================================================================

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Forge",
  title = "WT-D20260508_010 백테 완료 — 4 비율 정량 비교",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "R14_DUVOL 알파 4 비율 백테 완료. 현행 A(미편입) 단조 우위."),

    list(type = "kv", emoji = "📊", heading = "공통 59개월 샤프지수 (2021-07~2026-05)",
         kv = list("비율 가 (영 퍼센트)" = 1.8090,
                   "비율 나 (십 퍼센트)" = 1.7855,
                   "비율 다 (이십 퍼센트)" = 1.7426,
                   "비율 라 (삼십 퍼센트)" = 1.6784)),

    list(type = "kv", emoji = "📊", heading = "공통 59개월 최대낙폭 및 연복리수익률",
         kv = list("비율 가 최대낙폭 및 연복리" = "-15.3 퍼센트 / 30.9 퍼센트",
                   "비율 나 최대낙폭 및 연복리" = "-14.7 퍼센트 / 29.4 퍼센트",
                   "비율 다 최대낙폭 및 연복리" = "-14.3 퍼센트 / 27.9 퍼센트",
                   "비율 라 최대낙폭 및 연복리" = "-14.6 퍼센트 / 26.4 퍼센트")),

    list(type = "kv", emoji = "📈", heading = "256개월 보충 샤프지수 (R14 활성 59개월만)",
         kv = list("비율 가" = 1.7791, "비율 나" = 1.7759,
                   "비율 다" = 1.7670, "비율 라" = 1.7523)),

    list(type = "bullet", emoji = "🔬", heading = "공분산 조건수 표류 검증 (Codex C1)",
         items = c(
           "Forge 독립 재계산 cond_exact = 2165.7551 (Codex C1 정확 확인)",
           "Risk 보충 보고 κ=202.62 대비 1963pp 표류",
           "Pure Function R12 boundary로 covariance.parquet 이진 파일 단일 진실 사용",
           "Q-Lead/Governor 운영 단계 escalate 경로 문서화"
         )),

    list(type = "bullet", emoji = "🚩", heading = "AX-001 v2 조건부 방어 검증 — 실패",
         items = c(
           "위기 알파(crisis_alpha): B -6.08pp / C -5.13pp / D -4.22pp (모두 음수)",
           "최대낙폭 완화는 TSMOM+한국 10년 채권 기여 (R14_DUVOL 기여 아님)",
           "방어 분류 3-of-3 조건 모두 실패 → 다양성 보조(Diversifier) 역할도 실효 없음"
         )),

    list(type = "bullet", emoji = "📉", heading = "최적화 분석 vs Forge 측정 괴리",
         items = c(
           "최적화 분석 투영: B 1.97 / C 2.07 / D 2.13 (분석적 근사)",
           "Forge 워크포워드 측정: B 1.79 / C 1.74 / D 1.68 (실측)",
           "괴리 19~45pp — 위조 의심(FABRICATION_SUSPECTED) 아님",
           "원인: 15bp 비용 + 회전율 28%/기 복리 페널티 + 음의 상관(-0.087) 분산 효과 과대 추정"
         )),

    list(type = "bullet", emoji = "🛡️", heading = "Codex 1라운드 비평 처분 (거절, 거부권 없음)",
         items = c(
           "총 7건 (높음 5 + 중간 2)",
           "수용 2 / 단위주석수용 1 / 시한부수용 1 / 부분수용 1 / 반박 2",
           "수용 4호: 결손 샤프지수 페널티 0.5 적용",
           "수용 5호: 256개월 표 보충 등급 강등",
           "반박 2호: Discovery 단계 범위 (Lockbox 면제)",
           "반박 7호: AX-008 출처 셈법 헌장 v1.4 §10"
         )),

    list(type = "bullet", emoji = "➡️", heading = "Forge 권고 + Q-Lead 결정 사항",
         items = c(
           "Forge 권고: A 비율 (R14_DUVOL 편입 보류) — 측정된 단조 우위",
           "도훈 conviction 콜: A(보류) / B(10%) / C(20%) / D(30%) 중 선택 필요",
           "Backtest Result Contract v1.0 감사 4×11=44 컴포넌트 모두 PASS",
           "Pure Function R12 boundary 무결성: 3-package md5 시작/종료 동일",
           "다음 단계: Judge agent (Gate 0~18 + Harvey 5-spec 회귀)"
         ))
  )
)
