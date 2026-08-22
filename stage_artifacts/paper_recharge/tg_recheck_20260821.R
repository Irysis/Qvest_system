## Tier-2 팩터 심층 재검 텔레그램 발송 — 2026-08-21
PROJECT_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "팩터 심층 재검 (tier-2) — 20260821",
  relaxed = TRUE,
  force   = TRUE,
  sections = list(

    list(type = "summary",
         body = "오늘 5편 논문 전문 정독 — 승격 0건, 기각 확정 4건, 보류 1건(변동성 예측 논문, 수익 예측력 미확인)"),

    list(type = "bullet", emoji = "📚", heading = "연구 컨텍스트",
         items = c(
           "[목적] arxiv 신규 5편 전문 정독 — KR long-only 15bps 구현 가능 알파 팩터 선별",
           "[검토] 종속변수·데이터 의존성·레지스트리 중복·v8.4 금지 4종 전수 판정",
           "[결론] 승격 0건 | 확정 기각 4건 | 변동성 예측 논문 보류 1건(수익 예측력 미확인)"
         )),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 이번 주 나온 금융 학술논문 5편을 처음부터 끝까지 읽어 '실제로 써먹을 수 있는 투자 아이디어'인지 판단했습니다",
           "방법: 논문의 신호가 KR 주식시장 데이터(DART·RAWDATA·factor_db)로 재현 가능한지, 기존에 이미 쓰는 신호와 겹치는지 점검했습니다",
           "결과: 5편 모두 자본을 배정할 수준에는 도달하지 못했습니다 — 이유는 편마다 다릅니다",
           "의미: 오늘 라운드에서는 새로운 알파 후보를 큐에 올리지 않지만, 다음 가설 10건을 도출했습니다"
         )),

    list(type = "kv", emoji = "📊", heading = "재검 결과 요약",
         kv = list(
           "입력 논문"  = "5편",
           "승격"       = "0건",
           "확정 기각"  = "4건",
           "보류"       = "1건 (2608.12251)",
           "next probe" = "10건 (FQ 신설)"
         )),

    list(type = "bullet", emoji = "🔍", heading = "논문별 판정",
         items = c(
           "2608.15212 | 기각: 논문 목표=잔차 변동성(alpha 아님) + 미국 3채널 vs KR DART 단일채널 구조 불일치 + Datamaran 독점 ESG DB",
           "2608.14323 | 기각: HNN = 94개 팩터 신경망 결합기(v8.4 INV-7 금지) — 독립 신규 팩터 추출 불가",
           "2608.14014 | 기각: 공시 전 선행 드리프트(PIT C1 위반) + 공시 후 PEAD는 L18_SUE 중복 + 한국어 뉴스 DB 미보유",
           "2608.12283 | 기각: LLM 불확실성 → 공분산 주입은 optimizer 방법론(alpha 아님) + ML 사이징 INV-7 + 뉴스 인프라 미보유",
           "2608.12251 | 보류: 5일 실현변동성 예측 논문 — 수익 예측력 수치 부재, 레짐 조건부 vol 잔차 KR 실측 필요"
         )),

    list(type = "bullet", emoji = "🧭", heading = "다음 가설 (next probe, AX-000 연속성)",
         items = c(
           "FQ-NEW: DART 공시 유형별(실적/배당/M&A) 공시 후 드리프트 기간 차별화 검증 — DART API 구조화 카테고리 활용",
           "FQ-NEW: MFCF 클리크 내 팩터 이격도 신호 — ML 결합기 아닌 수리통계 구조추정(Lane C 후보)",
           "FQ-NEW: DART 신규 공시 vs 반복 공시 IVOL 구분 — risk overlay 후보(AX-001 조건부)",
           "FQ-FR: 시장 vol 20d + 잔차 vol 20d → factor-rotation 레짐 라우팅 변수 활용 (FR 모드 Track1)",
           "2608.12251 보류건: KR RAWDATA로 레짐 조건부 vol 잔차 IC + canonical_screen_bt 실측 (Lane B 일별축 후보)"
         ))
  )
)
