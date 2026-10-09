source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "AlphaSearch",
  title = "[1계층] 논문 트리아지",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = "paper_router_20261009",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "arxiv 245건 중 신규 1건(STOCK-JEPA)을 testable 판정. 244건은 중복체인 기판정, 기관시드 미처리 0건."),

    list(type = "kv", emoji = "📊", heading = "판정 집계",
         kv = list(
           "testable" = "1건 (route=replication)",
           "redundant" = "244건 (route=skip)",
           "data_pipeline_required" = "0건",
           "skip(기타)" = "0건",
           "중복 판정 근거" = "paper_registry + queue_done + 직전 57개 route 이력")),

    list(type = "bullet", emoji = "🆕", heading = "신규 testable — STOCK-JEPA (arXiv 2610.07006)",
         items = c(
           "신호: PIT 사전앵커(릿지 lambda=20 로 40차원 기술자 -> 5/21일 수익·변동성·낙폭·초과수익 8표적) + 그 앵커로부터의 예측가능 수정량(revision)을 Transformer 로 학습, 표현 동결 후 MLP 로 21일 누적 로그수익 예측",
           "포트폴리오: 논문 그대로 K=30 동일가중·익일 시가 집행·21일 보유·중첩 배치 단일 NAV·5bps",
           "데이터: 인프라 일별 OHLCV + 패널 자체 동일가중 시장수익으로 전량 파생 — 외부 축 불필요(data_pipeline 적재 없음)",
           "유니버스: K200∪KQ150 PIT 치환이 유일한 허용 변경. 단 논문의 상장폐지 포함 5,669/10,152 종목 폭은 KR 약 350종목으로 재현 불가 — 횡단면 폭 결손은 측정 세션이 명시 보고할 사항")),

    list(type = "bullet", emoji = "⚠️", heading = "충실구현 전 유의 4건",
         items = c(
           "불완전 기술: 40개 기술자(주식 28 + 시장 12)의 개별 목록이 논문 전문에 없습니다. 6개 그룹 라벨만 제시 — 채널 목록은 재구성 선택이며 엔진이 명시 기록해야 합니다(기전·표적·사전·아키텍처·포트폴리오는 전부 명시값이라 날조가 아닌 재구성 범위)",
           "PIT: 표준화 모멘트와 릿지 적합을 반드시 각 예측블록 이전 이력으로만 — 논문의 확장창 설계 자체가 PIT 정합이니 전기간 모멘트로 바꾸지 말 것(C1)",
           "규모: 126x40 패널에 Transformer + EMA 다단 학습은 통상 라운드 예산을 넘습니다 — 측정 타당성 문제이지 트리아지 기각 사유는 아닙니다",
           "선례: ML 을 횡단면 평균·순위 예측기로 쓰는 구성은 과거 KR negative 의 형태입니다 — 착수 전 hypothesis_index.R lookup 권고(AX-000 · 사실 기록이지 금지 아님)")),

    list(type = "bullet", emoji = "📁", heading = "산출물",
         items = c(
           "stage_artifacts/paper_recharge/alpha_search_route_20261009.json (paper_router_v4 · 245건)",
           "논문 전문 추출본: stage_artifacts/paper_recharge/_jepa_20261009.txt",
           "mode_queue 미생산(v10) · registry/BOOK 쓰기 0 · 백테 호출 0 · L-code 발행 0"))
  ),
  footer = "Jina read_url 402(쿼터) — 신규 1건은 arXiv 직접 수신 + pdftotext 로 정독했습니다."
)
