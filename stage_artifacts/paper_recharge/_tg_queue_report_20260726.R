root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
suppressWarnings(suppressMessages({
  source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R"))
}))

tg_agent_brief(
  agent = "AlphaSearch",
  title = "알파 서칭 큐 소비자 런 (2026-07-26) -- 신규 대기 없음",
  relaxed = TRUE,
  force   = TRUE,
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = paste0(
           "오늘 큐 소비 런 완료 -- 미처리 testable 팩터 0건. ",
           "기존 처리 2건 모두 QUARANTINE(모의 운용 t값 음수). 실제 자본 배정 없음."
         )),

    list(type = "bullet", emoji = "\U0001F4D6", heading = "쉬운 설명",
         items = c(
           "시도: 논문에서 추출한 주식 선별 신호를 백테스팅으로 검증합니다",
           "방법: 오늘은 대기 중인 신규 신호가 없어 실제 리서치 실행은 없습니다",
           "결과: 기존 처리 2건 모두 실패(시장 초과수익 t값 음수)로 소비 종료",
           "의미: 실제 자본 배정 없음 -- 다음 논문 주입 대기 상태"
         )),

    list(type = "kv", emoji = "\U0001F4CA", heading = "큐 상태",
         kv = list(
           "대기 testable 건수" = "0 (MAX 2)",
           "이번 런 처리" = "0건",
           "기존 QUARANTINE" = "2건 처리 완료",
           "처리 날짜" = "2026-06-20 / 2026-06-21",
           "done.json 수정" = "배열->dict 형식 정합 복원"
         )),

    list(type = "kv", emoji = "\U0001F4CB", heading = "기존 처리 2건 결과",
         kv = list(
           "p_index (2606.08569)" = "PORT_t -2.76 grade C QUARANTINE",
           "ReSGA 상호작용 (2606.04576)" = "PORT_t -2.81 grade F QUARANTINE",
           "공통 실패 원인" = "KR 실현 알파 t값 음수(hurdle 2.95 미달)"
         )),

    list(type = "bullet", emoji = "\U0001F6A9", heading = "다음 조치",
         items = c(
           "tier-1 라우터: 07-24 이후 2일 공백 -- paper_router_run.sh 재가동 필요",
           "tier-2 심층재검: uncertain 2건 대기 -- price_network_centrality / body_tail_leg",
           "FQ-002 계약수주 크기 / FQ-003 공매도잔고(도훈 QW 익스포트 대기) -- 비-return 주력 후보",
           "실제 자본 배정 없음 -- 신규 testable 논문 등장 대기 중"
         ))
  )
)
