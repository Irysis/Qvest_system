source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                 "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent      = "AlphaSearch",
  title      = "[1계층] 논문 트리아지 — 2026-10-03",
  relaxed    = TRUE,
  force      = TRUE,
  lock_scope = "paper_router_20261003",
  sections = list(

    list(type = "summary", emoji = "📌",
         body = "1계층 논문 트리아지 — arXiv 245편: 충실구현 후보 0 · 중복 243 · 기각 2. 오늘 큐 증분 0건."),

    list(type = "kv", emoji = "🧭", heading = "현재 리서치 상황",
         kv = list(
           "단계"      = "1계층 논문 트리아지 (판정 전용 — 백테 없음)",
           "대상"      = "arXiv 수집 245편 + 기관·고전 시드 미처리 0편",
           "위치"      = "stage_artifacts/paper_recharge/alpha_search_route_20261003.json",
           "직전 판정" = "09-29 트리아지 — 245편 전량 중복, 신규 0건"
         )),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 오늘 수집된 논문 245편이 '논문 그대로 한국 유니버스로 재현할 팩터 전략'인지만 가려냈습니다",
           "방법: 논문 식별키를 논문 등록부·처리완료 목록·과거 트리아지 이력과 대조해 기판정분을 걷어내고, 처음 보는 논문만 PDF 전문을 읽어 판정했습니다",
           "결과: 245편 중 243편은 이미 판정된 논문이었고, 처음 등장한 2편은 재현할 매매 신호가 논문에 없어 기각했습니다",
           "의미: 오늘 1계층 큐에 새 논문이 추가되지 않습니다. 기존 큐 재고로 라운드를 돌립니다"
         )),

    list(type = "kv", emoji = "📊", heading = "판정 집계",
         kv = list(
           "입력(arXiv)"            = "245편",
           "입력(기관·고전 시드)"   = "0편 (CSV 26 = 기처리 26)",
           "testable(충실구현)"     = "0건",
           "data_pipeline_required" = "0건",
           "redundant(기판정)"      = "243건",
           "skip(기각)"             = "2건"
         )),

    list(type = "bullet", emoji = "❌", heading = "신규 2편 — 전문 대조 후 기각",
         items = c(
           "2503.19767 Forecasting U.S. equity market volatility with attention and sentiment — 개별주 실현변동성 예측 정확도 연구(HAR·adaptive-Lasso·CSR·랜덤포레스트, 미국 404종). 종목 선정·비중·리밸 규칙이 논문에 없어 재현할 신호 자체가 없음(포트폴리오·경제적 가치 절 부재). 없는 신호를 지어내는 것은 금지(batch_434)",
           "2503.19767 추가 — 입력이 미국 특화 대체데이터(영문 검색량·위키 조회·애널리스트 관심·소셜·뉴스 감성 × 미국 거시발표 10종)로 한국 대응 패널 없음",
           "2601.08571 Regime Discovery and Intra-Regime Return Dynamics — EMD-힐버트황 변환으로 평온·고변동·극단 국면을 식별하고 수익 5분위 상태의 가변길이 마코프 전이를 분석한 지수 레벨 기술통계. 횡단면 신호·백테·샤프지수 전무 → 1계층 후보 아님",
           "2601.08571 참고 — KOSPI 가 표본에 포함되고 국면식별 방법론으로는 쓸모가 있으나, 2계층(전략 로테이션)은 논문을 온디맨드로 직접 가져가므로 이 트리아지 큐를 경유하지 않음"
         )),

    list(type = "bullet", emoji = "⚠️", heading = "수집 레이어 경고 — 공급이 정체입니다",
         items = c(
           "오늘 245건 중 242건이 전일(09-29)과 동일한 논문입니다. 체인 전체 기준으로도 243/245 가 기판정분",
           "원인 후보: 수집 설정이 최신성 창 없이 관련도 정렬로 같은 질의 30종을 재조회합니다(recency_days=0 · date_from=없음 · sort_by=relevance)",
           "실측 추이: 09-02~09-07 신규 후보 0~1건 · 09-26 0건 · 09-29 0건 — 2주 넘게 사실상 정적 집합",
           "제안(도훈 결정 필요): 질의 세트 교체 또는 최신성 창 도입. 트리아지 판정 규칙은 건드릴 것이 없습니다"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 액션",
         items = c(
           "오늘 큐 증분 0 → 1계층 라운드는 기존 재고로 진행(과거 replication 판정 84건 중 queue_done 미기록 65건)",
           "데이터 파이프라인 필요 0건 → data_pipeline_queue.json 무변경",
           "산출: stage_artifacts/paper_recharge/alpha_search_route_20261003.json (schema paper_router_v4). mode_queue 는 v10 에서 생산하지 않음"
         ))
  )
)
