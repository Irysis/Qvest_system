PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR")
if (nchar(PROJECT_ROOT) == 0) PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent  = "AlphaSearch",
  title  = "팩터 심층 재검 (tier-2) — 2608.04987 확정 기각",
  relaxed = TRUE,
  force   = TRUE,
  sections = list(
    list(
      type = "summary",
      emoji = "📌",
      body = "허스트 지수 횡단면 알파 가설(Hurst_CrossSection) 정밀 재검 — 논문은 포트폴리오 옵티마이저 설계 논문이며 종목 횡단면 신호 제시 전무. 확정 기각."
    ),
    list(
      type = "bullet",
      emoji = "📖",
      heading = "쉬운 설명",
      items = c(
        "시도: 허스트 지수(시계열의 장기 기억 강도)를 종목 선별 신호로 쓸 수 있는지 확인했습니다",
        "방법: 논문 전문(약 64,000자) 정독 + 팩터 레지스트리 373개와 대조",
        "결과: 논문은 허스트 지수를 진단 도구로만 사용하며 '어느 종목이 더 오를지' 예측력 검증이 전혀 없습니다",
        "의미: 이 논문 근거로 종목 신호를 만들면 날조(논문이 기술하지 않은 신호 구성)에 해당 — 실제 자본 투입 불가"
      )
    ),
    list(
      type = "kv",
      emoji = "📊",
      heading = "재검 결과",
      kv = list(
        "입력 후보" = "1건 (2608.04987)",
        "승격(testable)" = "0건",
        "확정 기각" = "1건",
        "still_uncertain" = "0건",
        "기각 사유" = "design_mismatch_optimizer_not_alpha"
      )
    ),
    list(
      type = "bullet",
      emoji = "🔍",
      heading = "판정 근거",
      items = c(
        "논문 분류: q-fin.PM (포트폴리오 운용) — MFCCA 분동함수로 공분산행렬을 대체하는 최적화 설계",
        "허스트 지수 h(q): 다중프랙탈 진단 도구(Fig.3)이며 종목 수익 예측력 IC/t값 0건",
        "경험적 적용: 닛케이·S&P500·WTI·금 지수 4개(개별 종목 아님)",
        "오늘 research_status: optimizer 경로 이미 delta_IR=-0.103 j0 확인 — 이중 확정"
      )
    ),
    list(
      type = "bullet",
      emoji = "➡️",
      heading = "다음 단계",
      items = c(
        "FQ 신규 등재 권고 — FQ-NEW-Hurst_DFA_CrossSection: Lo(1991) R/S 기반 종목별 DFA-Hurst 독립 가설(본 논문 아님)",
        "FQ 신규 등재 권고 — FQ-NEW-MFCCA_Risk_Estimator: optimizer WT에서 Σ 대안 후보",
        "alpha_search_queue 추가 없음 — 팩터 심층 재검 오늘 큐 소진 완료"
      )
    )
  )
)
