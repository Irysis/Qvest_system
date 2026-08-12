## 팩터 심층 재검 tier-2 텔레그램 보고 (20260813)
## tg_agent_brief 단일 진입점

Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PROJECT_ROOT <- Sys.getenv("QM_ROOT")
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent = "AlphaSearch",
  title = "팩터 심층 재검 (tier-2) — RMT 하부 스펙트럼 팩터 승격",
  relaxed = TRUE,
  force = TRUE,
  sections = list(
    list(
      type = "summary",
      emoji = "📌",
      body = "uncertain 1건 정밀 검토 — RMT 하부 스펙트럼 팩터 신규 확정, testable 승격."
    ),
    list(
      type = "bullet",
      emoji = "📖",
      heading = "쉬운 설명",
      items = c(
        "시도: 주식 시장이 동시에 움직이는 정도(동조화)를 측정하는 새 지표를 검토했습니다",
        "방법: 상관행렬 고유값이 무작위 기준선 아래로 내려가는 개수를 셉니다 — 많을수록 위기 신호",
        "결과: 기존 373개 팩터 중 이 방식을 쓰는 게 전무 → 신규 팩터로 확정(백테스팅 대기)",
        "의미: 시장 레짐 오버레이(타이밍)와 종목별 동조화 점수(횡단면) 두 경로 모두 실측 예정"
      )
    ),
    list(
      type = "kv",
      emoji = "📊",
      heading = "재검 결과",
      kv = list(
        "입력 후보" = "1건",
        "승격(testable)" = "1건 — min_eigenvalue_loading_60d",
        "확정 기각" = "0건",
        "여전히 불확실" = "0건",
        "논문" = "2608.09641 (q-fin.ST, 2026-08-10)"
      )
    ),
    list(
      type = "bullet",
      emoji = "🔬",
      heading = "팩터 핵심",
      items = c(
        "신호: 60일 롤링 상관행렬 고유값 중 Marchenko-Pastur 하한 미만 개수(m-)",
        "λ_min = (1 - sqrt(k/T))^2; k=클러스터수, T=창 길이",
        "Track A: 시장 레짐 오버레이 신호 (논문 S&P+Nikkei 직접 검증)",
        "Track B: 종목별 최소 고유벡터 적재량 횡단면 팩터 (충실 재구성, 실측 필요)",
        "신규성: RMT 스펙트럼 방법론 레지스트리 전무. 유사 RE02/CR03는 메커니즘 이질"
      )
    ),
    list(
      type = "bullet",
      emoji = "🚩",
      heading = "주의사항",
      items = c(
        "K200+KQ150 ~350종목 > 60일 창 → 클러스터 차원축소(k<T) 필수",
        "Track B(횡단면)는 논문 미검증 — 충실 재구성 범위, 실측에서 방향 확인 필요",
        "부호 양방향: 고동조화 적재 종목이 방어(양성) or 위기노출(음성) 실측으로 판정"
      )
    ),
    list(
      type = "bullet",
      emoji = "➡️",
      heading = "다음 액션",
      items = c(
        "alpha_search_queue_20260813.json → Track A 먼저 착수(required_effect_size.R 사전등록 필수)",
        "클러스터 k=10, 창 T=60일, EWMA 대안(delta=0.7, w=1000) 양쪽 비교",
        "산출 파일: factor_recheck_result_20260813.json / factor_recheck_done.json 갱신 완료"
      )
    )
  )
)
