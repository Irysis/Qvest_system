source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "alpha-search 큐 가동 (팩터→모드)",
  relaxed = TRUE,
  force   = TRUE,
  sections = list(
    list(
      type = "bullet",
      heading = "큐 상태",
      items = c(
        "미소비 testable 0편 → 자동실행 0편 (자동실행 상한 2 여유)",
        "큐/라우트 전수 스캔: testable 2건 모두 소비완료",
        "2606.08569 하방보험 공정가 p-index (소비완료)",
        "2606.04576 사이즈×꼬리위험 상호작용 ReSGA (소비완료)"
      )
    ),
    list(
      type = "bullet",
      heading = "라우터(오늘)",
      items = c(
        "신규 testable 0, 알파 경로 0 — 신규 5편서 한국 횡단면 신규 팩터 없음",
        "근접 실패 정직기록: 거래량 체계성(비예측)·허스트(한국 실패확정)·몸통꼬리(사이즈 중복)·ESG AI(대체데이터 불가)",
        "날조 가드: 합성 신호 0건"
      )
    ),
    list(
      type = "bullet",
      heading = "결정",
      items = c(
        "채택 0 / 격리 0 / 건너뜀 0 (실행 대상 없음)",
        "학습코드 적립 없음, 자본 장부 무변경",
        "다음: 라우터가 신규 testable 적재 시 재가동"
      )
    )
  )
)
cat("SENT\n")
