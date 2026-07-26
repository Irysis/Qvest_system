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
      body    = paste0(
        "오늘(2026-07-26) mcp_discovery: 30편 중 29편 어제 20260724에 이미 라우팅 완료 (rolling 180일 창 중복). ",
        "순수 신규 1편(2607.21170) → optimizer 큐 적재. curated 신규 0편(전 15편 처리 완료). ",
        "testable 팩터 0건 · autorun 0건."
      )
    ),
    list(
      type    = "kv",
      heading = "route별 배분 (오늘 순수 신규 1편)",
      kv      = list(
        "optimizer" = "1편 (TDA+FinBERT 포트폴리오 최적화)",
        "alpha"     = "0편",
        "risk"      = "0편",
        "regime"    = "0편",
        "skip"      = "0편",
        "testable 팩터" = "0건",
        "autorun"   = "0건"
      )
    ),
    list(
      type    = "bullet",
      heading = "① alpha-search autorun 결과",
      items   = c(
        "autorun 없음 — 신규 alpha 후보 0건. MAX_ALPHA=2이나 오늘 신규 논문 전부 optimizer/이미처리.",
        "어제(20260724) 처리 2607.14174 10-K 위험요인 감성: alpha 라우팅이나 kr_feasible=FALSE (DART 텍스트 NLP 파이프라인 미구축, FQ-012 참조).",
        "어제(20260724) 처리 2607.13968 FinBERT 뉴스 감성: skip (KR 뉴스 피드 없음)."
      )
    ),
    list(
      type    = "bullet",
      heading = "② route 무관 발굴 testable 팩터",
      items   = c(
        "오늘 신규 1편(2607.21170 TDA 클러스터링): 종목별 alpha 신호 없음 → infeasible.",
        "텍스트 기반 팩터 2종(FinBERT 감성·10-K 위험요인)은 어제 이미 평가 완료 — 공통 병목: KR NLP 파이프라인(FinBERT-KR + DART 텍스트 추출) 미구축. 구축 시 FQ-012 발굴 재개 가능."
      )
    ),
    list(
      type    = "bullet",
      heading = "③ optimizer/risk/regime 큐 후보",
      items   = c(
        "[optimizer] 2607.21170 — TDA 기반 자산 클러스터링 + retention 메커니즘. alpha 고정 A/B 대상 (현행 MVO vs TDA 구성 비교).",
        "[optimizer 기존 큐] 어제 배분된 7편 포함 (BAVAR-BLED·SciPhyRL·MV 모호성 등) — mode_queue_20260726 참조."
      )
    )
  )
)
