source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent      = "AlphaSearch",
  title      = "[1계층] 논문 트리아지",
  relaxed    = TRUE,
  force      = TRUE,
  lock_scope = "paper_router_20260926",
  sections   = list(
    list(
      type    = "summary",
      heading = "트리아지 요약 — 20260926 (+백로그 20260925)",
      body    = "testable 0 / dpq 0 / skip 253(전건 redundant) — 신규 0건. 수집기 406 복구했으나 스펙 포화."
    ),
    list(
      type    = "kv",
      heading = "판정 집계",
      kv      = list(
        "testable (route=replication)" = "0건",
        "data_pipeline_required"       = "0건 (data_pipeline_queue append 0)",
        "skip"                         = "253건 — 전건 verdict=redundant",
        "복구 candidates"              = "253건 유니크 (질의 30/30 성공, 실패 0)",
        "20260924 기처리분과 교집합"   = "253/253 = 100% → 신규 0건",
        "curated 시드"                 = "CSV 26건 전건 기처리 (신규 0, append 0)",
        "산출"                         = "alpha_search_route_20260926.json / _20260925.json"
      )
    ),
    list(
      type    = "bullet",
      heading = "① 수집기 406 — 원인 정정(9/24 노트는 오진)",
      items   = c(
        "9/24 노트는 406 을 '무간격 연사 throttle' 로 진단했으나 재현되지 않는다 — 단건·무간격 아님·trivial 질의(all:electron)에서도 0.2~0.5초 내 즉시 406.",
        "통제 실험: UA 유무 · Accept/Accept-Encoding 변형 · http/https · arxiv.org/export.arxiv.org · 질의 형태 8종 전 조합에서 Python(urllib) = 406, curl = HTTP 200(동일 URL).",
        "대조 증거: 본 세션 urllib 판 복구는 30/30 질의 406 실패, curl 판은 30/30 성공. → arXiv 는 정상이고 차단은 이 호스트의 Python 클라이언트 경로 한정. arxiv-mcp-server 가 Python 이라 죽는다.",
        "복구 방법 = 질의 스펙(질의 30건·categories·max_results·sortBy) 바이트 동일 유지 + 전송만 curl, 3.1초 간격. 스크립트 = stage_artifacts/paper_recharge/_recover_arxiv_20260926.py."
      )
    ),
    list(
      type    = "bullet",
      heading = "② 더 큰 문제 — 수집 스펙이 포화다",
      items   = c(
        "406 을 고쳐도 신규 논문은 나오지 않는다. 복구 253건이 9/24 기처리분과 완전 일치했다.",
        "구조적 원인: 30개 고정 질의 · sort_by=relevance · recency_days=0 · date_from=null → 날짜창이 없어 매일 같은 상위 10건/질의를 반환한다.",
        "즉 이 수집기는 설계상 신규 유입이 불가능한 상태다. 9/18~9/26 라우팅이 실질 0건인 진짜 이유.",
        "해소에는 스펙 변경(sortBy=submittedDate 또는 recency_days>0 / date_from 지정 / 질의 집합 확장)이 필요 — 트리아지 소관 밖이므로 착수하지 않았다(도훈 판단 사항)."
      )
    ),
    list(
      type    = "bullet",
      heading = "③ dedup 체인 · 미소비 재고",
      items   = c(
        "대조 = paper_registry(853) + alpha_search_queue_done::processed(77) + route 이력 49종(3,947행) + data_pipeline_queue(49). arXiv 신·구 표기 모두(cond-mat/0410079 꼴 22건 포함).",
        "미소비 재고: 9/24 의 유일한 testable — axv:2603.20271 (KR 투자자유형 Transfer Entropy 중심성)이 processed 에 없어 아직 미소비다.",
        "단 그 논문은 저자 스스로 null 을 보고한다(centrality adds negligible alpha, 일별 MI≈0) — 충실구현의 '논문 기준 성과'가 유의 알파 부재라는 점을 착수 전에 감안할 것.",
        "백로그 20260925 는 스펙이 20260926 과 필드 단위 동일·날짜창 없음이라 복구 결과가 같다 → 253건 전량을 20260926 에 단일 귀속(20260923→24 선례와 동일)."
      )
    )
  )
)
