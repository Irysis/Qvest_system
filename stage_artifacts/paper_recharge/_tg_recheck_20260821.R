source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                 "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "팩터 심층 재검 (tier-2) — 2026-08-21",
  relaxed = TRUE,
  force   = TRUE,
  sections = list(

    list(type = "summary", emoji = "📌",
         body = "오늘 5편 논문을 깊게 검토했습니다. 승격 0건, 확정 기각 4건, 추가 검토 필요 1건."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: tier-1 스크린에서 '판단 유보'로 남은 논문 5편을 전문을 읽어 정밀 재판정했습니다",
           "방법: 논문 전문·초록 정독 후 국내 팩터 데이터베이스(373종)와 1:1 대조하고 KR 구현 가능성을 점검했습니다",
           "결과: 4편은 데이터 부족 또는 기존 팩터와 중복으로 기각, 1편은 아이디어는 신선하나 수익 예측력 미확인",
           "의미: 오늘은 실제 자본 배정 후보로 올라간 전략이 없고, 내일 이후 알파 탐색 큐에 변화 없음"
         )),

    list(type = "kv", emoji = "📊", heading = "재검 결과 요약",
         kv = list(
           "입력 논문" = "5편",
           "승격(testable)" = "0건",
           "확정 기각" = "4건",
           "추가 검토(still_uncertain)" = "1건"
         )),

    list(type = "bullet", emoji = "❌", heading = "확정 기각 4건",
         items = c(
           "2608.15212 DART_DISCL_CHANNEL — ESG 공시채널 분류에 한국어 NLP 필요, 종속변수가 수익 아닌 위험",
           "2608.14323 MFCF_CLUSTER_SIGNAL — 신규 팩터가 아닌 기존 팩터 결합 아키텍처. ML 결합기 실적 0/84",
           "2608.14014 DART_PREDISCL_DRIFT — 공시 전 드리프트 핵심이 LLM 뉴스 분류 의존. 구현 가능 성분은 C01_SUE·C18 등에 이미 중복",
           "2608.12283 UNCERTAINTY_COV_ADJUST — LLM 뉴스 추론 + 공분산 조정 인프라 미보유. 알파 신호 아닌 최적화 방법론"
         )),

    list(type = "bullet", emoji = "🔍", heading = "추가 검토 1건",
         items = c(
           "2608.12251 REGIME_RVOL_RESIDUAL — 레짐 조건부 실현변동성 잔차 팩터",
           "아이디어: 각 시장 국면에서 예상보다 변동성이 낮은 종목을 선별하는 신호",
           "신선한 이유: DB 373종 중 레짐-조건부 변동성 잔차 팩터 전무",
           "문제: 논문 목표가 변동성 예측 정확도이고 수익 예측력 증거는 없음",
           "다음 단계: KRW 일별 수익으로 간단 버전(D34_RealVol_21d − 레짐별 중앙값) 구성 후 정보계수 실측"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 액션",
         items = c(
           "승격 0건 → 알파 탐색 큐(alpha_search_queue_20260821) 변경 없음",
           "REGIME_RVOL_RESIDUAL 간단 버전 실측 → 정보계수 확인 후 큐 등재 여부 결정",
           "기각 4건 factor_recheck_done.json 적립 완료 (재큐 방지)"
         ))
  )
)
