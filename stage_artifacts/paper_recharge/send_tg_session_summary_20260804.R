source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "AS-20260804 세션 완료 — 2건 실행, 전건 Grade F",
  sections = list(
    list(
      heading = "쉬운 설명",
      body    = "오늘 arXiv에 새 논문이 없어서(주말 공백) 기존 가설 2개를 테스트했습니다. 둘 다 낙폭이 너무 커 실전 투입 불가 판정입니다. 한 신호(CV_Vol)는 최근 3년 개선 중이라 다른 방식으로 활용 가능한지 추가 확인 예정입니다."
    ),
    list(
      heading = "실행 결과",
      body    = "FQ-143 CV_Vol: Grade F | MDD 64.4% | SR 0.195 | 최근3Y SR 0.579↑ OOS 1.087 주목\nFQ-147 FX헤징 proxy: Grade F | MDD 59.0% | SR 0.032 | OOS 역전 -2.53 구조불안"
    ),
    list(
      heading = "판정 평문",
      body    = "CV_Vol: 거래량 안정 종목이 위기 때 더 떨어짐 — 안정 거래량 ≠ 방어 펀더멘털. FX헤징: 파생상품 보유액이 FX헤징인지 금리헤징인지 구분 불가 — 신호 역전."
    ),
    list(
      heading = "큐 상태",
      body    = "오늘 처리(12개) = 기존 10 + 오늘 2건. FQ-143/147 settled. FQ-150/151 신규(CV_Vol 소비면 2종). 즉시 착수 가능: FQ-149 (FX노출 외화자산/총자산, data PASS) + FQ-146 (KOSPI TF overlay)"
    )
  ),
  relaxed = TRUE,
  force   = TRUE
)
