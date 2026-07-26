source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent     = "AlphaSearch",
  title     = "리서치 소스 배분 + 팩터 마이닝 — 20260726",
  relaxed   = TRUE,
  force     = TRUE,
  lock_scope = "paper_router_20260726",
  sections  = list(
    list(
      type    = "summary",
      heading = "배분 요약",
      body    = "신규 1편 optimizer 적재. testable 0건. autorun 0건."
    ),
    list(
      type    = "kv",
      heading = "route별 배분 (순수 신규 1편 기준)",
      kv      = list(
        "optimizer" = "1편 — TDA+FinBERT 포트폴리오 최적화 (2607.21170)",
        "alpha/risk/regime/skip" = "0편 (전일 29편 이미 처리됨)",
        "testable 팩터" = "0건",
        "autorun" = "0건 (MAX_ALPHA=2이나 신규 alpha 후보 없음)"
      )
    ),
    list(
      type    = "bullet",
      heading = "① alpha-search autorun 결과",
      items   = c(
        "autorun 없음 — 오늘 신규 1편 전부 optimizer 라우팅.",
        "어제 처리 2607.14174(10-K 위험요인 감성): alpha 라우팅이나 실행 불가 — DART 텍스트 한국어 변환기(FinBERT-KR) 미구축 (FQ-012 대기).",
        "어제 처리 2607.13968(FinBERT 뉴스 감성): skip — 한국어 뉴스 피드 없음."
      )
    ),
    list(
      type    = "bullet",
      heading = "② route 무관 발굴 testable 팩터",
      items   = c(
        "testable 0건. 신규 1편(TDA 클러스터링): 종목별 알파 신호 없음 → infeasible.",
        "공통 병목: 한국어 NLP 파이프라인(FinBERT-KR + DART 텍스트 추출) 미구축. 구축 시 FQ-012 재개."
      )
    ),
    list(
      type    = "bullet",
      heading = "③ optimizer/risk/regime 큐 후보",
      items   = c(
        "[optimizer] 2607.21170 — TDA 자산 클러스터링 + retention. 알파 고정 A/B 비교 대상(현행 MVO 대비).",
        "[optimizer 누적] 어제 포함 총 8편 큐 (BAVAR-BLED, SciPhyRL, MV 불확실성 등)."
      )
    )
  )
)
