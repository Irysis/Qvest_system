## 알파서칭 큐 소비자 텔레그램 (AS-20260808)
## run_id: AS-20260808 | MAX_ALPHA=2 | 실행 2건 | 모두 QUARANTINE
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent    = "AlphaSearch",
  title    = "알파서칭 큐 가동 — 오늘 2건 검증, 모두 쿼런틴",
  relaxed  = TRUE,
  force    = TRUE,
  as_of    = "2026-08-08",
  charts   = c(
    "stage_artifacts/alpha_search/20260808_004643_8680/equity_curve.png",
    "stage_artifacts/alpha_search/20260808_004643_8680/annual_returns.png",
    "stage_artifacts/alpha_search/20260808_001913_13752/equity_curve.png",
    "stage_artifacts/alpha_search/20260808_001913_13752/annual_returns.png"
  ),
  sections = list(

    list(type = "bullet", emoji = "🔭", heading = "오늘 실행 요약",
         items = c(
           "큐에서 2건 가동: FQ-110(jump-share 방향A) + SpectralPersistence(허스트 지수)",
           "두 전략 모두 L5 자동 게이트에서 QUARANTINE 판정",
           "판정 결론 — 이번 아이디어들에는 실제 자본을 배정하지 않습니다",
           "핵심 수확: jump-share 역방향 신호 발견 + 허스트 논문 3회 소진 확정"
         )),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: ① 수익이 소수 날에 몰린 종목(점프집중형)이 더 오르는지 확인, ② 수익률의 '추세 지속성(허스트 지수)'으로 좋은 종목을 고를 수 있는지 확인",
           "확인 방법: 2005년~2026년 KR K200·KQ150 전 종목에 신호 적용 → 상위 25종목 월 리밸런싱 가상 운용 → 통계적 유의성(다중검정 t값 2.95 기준) 검사",
           "결과: 두 전략 모두 t값 1.0 미만(기준의 1/3 수준), 최대낙폭 55~64%로 기준 초과",
           "달라진 점: ①에서 '오히려 점프 안 하는 종목이 잘 간다'는 역방향 신호 발견 → 다음 라운드 착수"
         )),

    list(type = "kv", emoji = "🔴", heading = "전략 ① FQ-110 JumpShare (방향A) — QUARANTINE",
         kv = list(
           "전략명" = "FQ110_JumpShare_A",
           "신호" = "12개월 창 상위-5 일간수익 기여 비중",
           "샤프지수" = "0.37",
           "연복리수익률(CAGR)" = "9.5%",
           "최대낙폭(MDD)" = "55.5%",
           "칼마지수" = "0.17 (기준 0.64 미달)",
           "포트폴리오알파 t값" = "0.62 (기준 2.95 미달)",
           "정보계수(IC)" = "-0.028 음수 — 방향 반전 발견",
           "게이트 결과" = "QUARANTINE — 견고성 실패"
         )),

    list(type = "bullet", emoji = "💡", heading = "FQ-110 핵심 발견 — 역방향 가설",
         items = c(
           "IC(정보계수)=-0.028: 점프집중형 종목이 오히려 저성과",
           "frog-in-the-pan 이론 재해석: '서서히 오르는 종목(저 jump-share)'이 지속 상승 후보",
           "방향A는 실패이지만 방향B(점프 안 하는 종목 long) 근거 확보 — 즉시 착수 가능",
           "→ FQ-110B 프론티어 큐 등재 완료"
         )),

    list(type = "kv", emoji = "🔴", heading = "전략 ② SpectralPersistence Hurst — QUARANTINE",
         kv = list(
           "전략명" = "SpectralPersistence_Hurst",
           "신호" = "허스트 지수(R/S) 상위 종목 long",
           "출처 논문" = "arXiv:2607.19497 (Sepp & Lucic)",
           "샤프지수" = "0.53",
           "연복리수익률(CAGR)" = "11.4%",
           "최대낙폭(MDD)" = "63.8%",
           "포트폴리오알파 t값" = "0.98 (기준 2.95 미달)",
           "표본외 안정성" = "0.37 (기준 0.5 미달)",
           "위기 대응 성과" = "5/7 우수(코로나 +3.9%)",
           "게이트 결과" = "QUARANTINE — 견고성+충실도 실패"
         )),

    list(type = "bullet", emoji = "📊", heading = "SpectralPersistence 소비면 발굴",
         items = c(
           "standalone 배포 불가(PORT_t 기준 미달)이나 위기 방어성 5/7 주목",
           "FQ-153: 시장 레벨 허스트 오버레이 — H>0.5 달에만 모멘텀 전략 활성화 시도",
           "동 논문(2607.19497) 3회 시도(spec_mass·RetAutoCorr·Hurst) 모두 standalone 불가 → 논문 소진",
           "FQ-152: 이미 기등재(별개 팩터). FQ-153(오버레이 소비) 신규 등재"
         )),

    list(type = "kv", emoji = "📋", heading = "검증 게이트 성적표 (2건)",
         kv = list(
           "L1 미래참조 검사" = "2/2 통과",
           "L2 백테스트 계약(10요소)" = "2/2 통과",
           "L3 견고성(PORT_t·OOS·칼마)" = "0/2 실패",
           "L4 구현 충실도" = "JumpShare 통과 / Hurst 실패(R/S ≠ DFT)",
           "L5 최종 판정" = "2건 모두 QUARANTINE"
         )),

    list(type = "bullet", emoji = "🚀", heading = "다음 라운드 — 즉시 착수 가능",
         items = c(
           "FQ-110B: jump-share 역방향 (동일 엔진, 부호 반전만) — 1라운드 착수",
           "FQ-153: 시장 허스트 오버레이 — 위기방어 소비면 검증",
           "FQ-110B IC 방향 실증 시 frog-in-the-pan 기전 확증 → 경로효율 계열 이론 근거 확보"
         ))
  )
)
