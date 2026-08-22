
# Paper Recharge 20260822 — Telegram 발송
# AUTORUN=0, relaxed=TRUE (영어 논문 제목 고유 콘텐츠 허용)
# 실행: Rscript -e 'source("stage_artifacts/paper_recharge/tg_paper_recharge_20260822.R")'

root <- Sys.getenv("QM_ROOT")
if (nchar(root) == 0) root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(root, "02_Infrastructure/config.R"))
source(file.path(root, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent  = "Q-Lead",
  title  = "논문 라우터 v2 — 2026-08-22 소스 배분 완료",
  relaxed = TRUE,
  glossary = TRUE,

  sections = list(
    list(
      header = "📋 처리 요약",
      easy = "이번 논문 라우터가 오늘 인식한 논문·보고서를 역할별로 분류했습니다.",
      body = list(
        "처리 소스" = "arxiv 33편 + 기관리서치 큐레이션 15편 = 48건",
        "알파 리서치" = "11건 (arxiv 5 + 기관 6)",
        "최적화 리서치" = "6건 (arxiv 4 + 기관 2)",
        "리스크 리서치" = "8건 (arxiv 6 + 기관 2)",
        "국면/레짐" = "5건 (기관 전량)",
        "스킵" = "18건",
        "AUTORUN" = "0 (큐 적재만, 실행 없음)"
      )
    ),
    list(
      header = "🔬 팩터 후보 발굴",
      easy = paste0(
        "논문에서 실제로 우리 시스템에 테스트 가능한 새 신호가 있는지 확인했습니다.\n",
        "1건이 즉시 테스트 가능, 4건은 추가 검토 필요, 2건은 현 인프라로 불가합니다."
      ),
      body = list(
        "✅ 즉시 테스트 가능 [1건]" = "macro_beta_momentum (arxiv:2608.12283) — 종목을 '최근 크게 움직인 거시경제 팩터에 민감한 순서'로 정렬하는 신호. FRED 거시 데이터 이미 적재 중. 기존 MA01~MA07 팩터는 정적 민감도이고, 이 신호는 민감도×최근수익률 곱 = 미등재 조합",
        "❓ 불확실 [4건]" = "mfcf_hnn_composite (아키텍처 구현 필요) · shariah_classification_change (KR ESG 이벤트 유사성 미검증) · first_sec_social_disclosure (DART NLP 필요) · regime_gated_vol_forecast (변동성 예측, 수익 방향 아님)",
        "❌ 인프라 불가 [2건]" = "fundamental_news_drift (KR 뉴스코퍼스 미보유) · human_capital_disruption_ec (KR 실적발표 텍스트 미보유)"
      )
    ),
    list(
      header = "🚀 알파 서칭 큐 (AUTORUN=0)",
      easy = "오늘은 실행 없이 큐만 적재했습니다. 다음 세션에서 /alpha-search 시 아래 1순위부터 실행됩니다.",
      body = list(
        "1순위" = "macro_beta_momentum | arxiv:2608.12283 | 신뢰도 0.72 | Lane D(매크로 조건부) 연계",
        "상태" = "queued — AUTORUN=0"
      )
    ),
    list(
      header = "📐 최적화 큐 우선순위",
      easy = "최적화 방법론 논문을 '즉시 적용 가능 여부'로 등급을 매겼습니다.",
      body = list(
        "⭐⭐ 최우선 [2건]" = "RA 멀티팩터 배합(분산화 = 내장 정규화) · RA 비용-용량 분석(비용 제약 최적화)",
        "⭐ 우선 [2건]" = "Self-Consistent Adjoint(25종목 제약 최적화 검증) · Scalable Pontryagin Adjoint(100종목 확장)",
        "후순위 [2건]" = "EVaR 안정 분포(꼬리 추정) · 동적 CVaR(이론 우수, 이산화 어려움)"
      )
    ),
    list(
      header = "⚡ 리스크 큐 하이라이트",
      easy = "리스크 모델 개선에 쓸 수 있는 논문 목록입니다.",
      body = list(
        "⭐ 우선 [3건]" = "Regime-Gated MoE 변동성(5일 예측 MLP 대비 우위) · Rough Volatility(H~0.13 보편 확인) · Reconfiguration Premium(공동변동 구조 변화율)",
        "⭐ 군집화 [1건]" = "Market Crowding Representation(포지션 쏠림 수학화)",
        "후순위 [2건]" = "비모수 VaR(고차원 꼬리 측정) · RA 숨은 위험(팩터 크래시 진단)",
        "참고 [2건]" = "사회공시 채널(변동성 예측) · GMO 은탄환 없음(리스크 프리미어 배경)"
      )
    ),
    list(
      header = "📁 산출물",
      body = list(
        "라우팅 결과" = "stage_artifacts/paper_recharge/alpha_search_route_20260822.json",
        "비알파 큐" = "stage_artifacts/paper_recharge/mode_queue_20260822.json",
        "큐레이션 등재" = "stage_artifacts/paper_recharge/curated_routed.json (15건 전수)",
        "Axis 감사" = "100% (14/14 axes 표기, 정렬불가 0건)",
        "주의" = "큐레이션 PDF Jina 402 — 메타데이터 기반 라우팅 (factor 추출 불가)"
      )
    )
  ),

  footer = paste0(
    "v8.4 비대칭 알파 · macro_beta_momentum Lane D 연계 후보 · ",
    "다음 액션: /alpha-search 로 1순위 큐 실행"
  )
)

cat("Telegram 발송 완료\n")
