PROJECT_ROOT <- Sys.getenv("QM_ROOT")
if (nchar(PROJECT_ROOT) == 0) PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent    = "AlphaSearch",
  title    = "리서치 소스 배분 + 팩터 마이닝 (20260820 백로그 + 20260821)",
  relaxed  = TRUE,
  force    = TRUE,
  lock_scope = "paper_router_20260821",
  sections = list(

    list(type = "summary",
         body = "arxiv 33편 라우팅 완료. testable 신규 팩터 2건(VOL_HURST, ARFIMA_TSMOM) 발굴 + AUTORUN 실행 중."),

    list(type = "bullet", emoji = "\U0001f4d6", heading = "쉽은 설명",
         items = c(
           "시도: arxiv에 올라온 금융 논문 33편을 우리 리서치 모드별로 분류했습니다",
           "발굴: route와 무관하게 본문에서 한국 주식에 적용 가능한 신규 팩터 직접 추영",
           "결과: testable 팩터 2건(VOL_HURST, ARFIMA_TSMOM) 발굴 — 팀터 DB 373종에 없는 신규 신호",
           "의미: 2편 자동 백테스팅 에이전트 백그라운드 실행 중 — 결과 도착 시 보고합니다"
         )),

    list(type = "kv", emoji = "\U0001f4ca", heading = "Route 배분 (33편)",
         kv = list(
           "alpha (황단면 종목선택)" = "7편",
           "optimizer (가중/배분 방법론)"  = "4편",
           "risk (공분산/꼬리 모델)"      = "6편",
           "regime (매크로 국면)"                 = "1편",
           "skip (KR 범위 외)"                            = "15편",
           "testable 팩터 발굴"                       = "2건",
           "curated 신규 처리"                        = "0건 (전체 15건 기체리)"
         )),

    list(type = "bullet", emoji = "\U0001f52c", heading = "testable 신규 팩터 (AUTORUN 대상)",
         items = c(
           "[1] VOL_HURST (2608.16749 Rough Volatility Across Assets) | route=risk | 일별 실현변동성의 rolling 252일 Hurst 지수 — 거칠기(rough) vs 지속성 종목 단면 프리미엄 검증. confidence=0.80",
           "[2] ARFIMA_TSMOM (2607.19497 The Science and Practice of Trend-Following) | route=alpha | 분산비(Variance Ratio)>1 조건 안에서만 12-1 MOM 적용 — 양의 자기상관 존재 시 모멘텀 유효. confidence=0.72",
           "AUTORUN: 2 에이전트 병렬 백그라운드 실행 중 — 완료 시 자동 업데이트"
         )),

    list(type = "bullet", emoji = "\U0001f4e6", heading = "optimizer/risk/regime 큐 적재",
         items = c(
           "[optimizer TOP] LLM 불확실성 분해 공분산 주입 (2608.12283): shrinkage_builtin=yes, <=2nd, ⭐⭐ — epistemic 불확실성 → 암묵 축소화. 가장 명시적인 정규화",
           "[risk] Rough Volatility 시간단 상방향 (2608.16749): 실제 리스크 모델로도 자동 분슰 특성 유용 | (6편 서비스 단분위 우선순위는 mode_queue 참조)",
           "[regime] AI-드리븐 다시나리오 금리 예측 (2608.12424) — FRED 매크로 국면 입력 신호 소스",
           "수령 JSON: mode_queue_20260821.json (opt 4 / risk 6 / regime 1)"
         )),

    list(type = "bullet", emoji = "\U0001f6a9", heading = "주의사항",
         items = c(
           "20260820 백로그 동일 33편 — 날짜만 다르고 컨텐츠 동일함 (라우터 반복 없음, MAX_ALPHA=2 합산 기준)",
           "curated 15편 전편 기체리 — 신규 미처리 미존재",
           "AUTORUN 에이전트 복귀 전까지 자본 배정 없음 (auto_alpha_gate.R 권한)"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 액션",
         items = c(
           "AUTORUN 완료 시: auto_verify_*.json 확인 후 L-code 적립 (조건 PASS/의미있는 실패)",
           "optimizer 우선순위 조회: mode_queue ⭐⭐ (LLM Uncertainty Covariance) 리서치 파트 A/B 테스트 후보",
           "VOL_HURST / ARFIMA_TSMOM 실측 결과 도착 시 연락 예정"
         ))
  )
)

cat("Telegram brief sent.\n")
