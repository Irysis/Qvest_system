
# Paper Recharge 20260822 — Telegram 발송
# 실행: Set-Location project_root; Rscript -e "source('stage_artifacts/paper_recharge/tg_paper_recharge_20260822.R')"

root <- Sys.getenv("QM_ROOT")
if (nchar(root) == 0) root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(root, "02_Infrastructure/config.R"))
source(file.path(root, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent   = "Q-Lead",
  title   = "논문 라우터 v2 — 2026-08-22 소스 배분",
  relaxed = TRUE,
  glossary = TRUE,

  sections = list(

    # 쉬운 설명 섹션 (v7 의무)
    list(
      heading = "쉬운 설명",
      type    = "text",
      body    = paste0(
        "오늘 논문 라우터가 arxiv 33편 + 기관리서치 15편을 역할별로 분류했습니다. ",
        "테스트할 수 있는 신규 신호 1건(거시경제 민감도×최근 수익률 조합)을 발굴했으며 ",
        "큐에 적재했습니다. 실행(AUTORUN)은 0으로 설정돼 이번에는 분류만 수행했습니다."
      )
    ),

    # 처리 요약
    list(
      heading = "처리 요약",
      type    = "kv",
      kv      = list(
        "소스 합계"     = "arxiv 33 + 기관리서치 15 = 48건",
        "알파 리서치"   = "11건 (arxiv 5 + 기관 6)",
        "최적화 리서치" = "6건 (arxiv 4 + 기관 2)",
        "리스크 리서치" = "8건 (arxiv 6 + 기관 2)",
        "국면/레짐"     = "5건 (기관 전량)",
        "스킵"          = "18건",
        "AUTORUN"       = "0 — 큐 적재만"
      )
    ),

    # 팩터 후보
    list(
      heading = "팩터 후보 발굴",
      type    = "bullet",
      items   = c(
        "✅ 즉시 테스트 [1건] macro_beta_momentum (2608.12283): 종목을 '최근 크게 움직인 거시 팩터에 민감한 순서'로 정렬. FRED 데이터 이미 적재. 기존 MA01~MA07 정적 민감도와 다른 동적 조합 신호",
        "❓ 불확실 [4건] HNN 아키텍처 복합·ESG 이벤트·DART NLP·변동성 예측 각 1건",
        "❌ 인프라 불가 [2건] 뉴스코퍼스 미보유·KR 실적발표 텍스트 미보유"
      )
    ),

    # 알파 서칭 큐
    list(
      heading = "알파 서칭 큐 (AUTORUN=0)",
      type    = "kv",
      kv      = list(
        "1순위"      = "macro_beta_momentum | arxiv:2608.12283 | 신뢰도 0.72",
        "Lane 연계"  = "Lane D 매크로 조건부 비대칭 — v8.4 주력",
        "다음 액션"  = "/alpha-search 로 1순위 실행"
      )
    ),

    # 최적화 큐
    list(
      heading = "최적화 큐 우선순위",
      type    = "bullet",
      items   = c(
        "⭐⭐ RA 멀티팩터 배합 / RA 비용-용량 (분산화+비용 제약 = 내장 정규화 2건)",
        "⭐ Adjoint 정책 반복 / 폰트랴긴 Adjoint (25종목 제약 최적화 검증 2건)",
        "후순위 EVaR 안정분포 / 동적 CVaR (꼬리 추정 의존 2건)"
      )
    ),

    # 리스크 큐
    list(
      heading = "리스크 큐 하이라이트",
      type    = "bullet",
      items   = c(
        "⭐ Regime-Gated MoE 변동성 예측 — 5일 기준 MLP 대비 우위 실증",
        "⭐ Rough Volatility 보편성 — KR 리스크 모델 보정 근거 (H~0.13)",
        "⭐ Reconfiguration Premium — 공동변동 구조 변화율 신규 측정",
        "⭐ Market Crowding Representation — 전략 쏠림 수학화"
      )
    ),

    # 산출물
    list(
      heading = "산출물",
      type    = "kv",
      kv      = list(
        "라우팅 결과"  = "alpha_search_route_20260822.json",
        "비알파 큐"    = "mode_queue_20260822.json (axis audit 100%)",
        "큐레이션 등재" = "curated_routed.json 15건",
        "주의"         = "PDF Jina 402 — 메타데이터 기반 라우팅"
      )
    )

  ),

  footer = "v8.4 비대칭 알파 · Lane D 연계 후보 macro_beta_momentum 큐 적재 완료"
)

cat("Telegram 발송 완료\n")
