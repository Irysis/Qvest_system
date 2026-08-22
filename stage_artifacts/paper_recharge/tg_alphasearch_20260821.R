
# tg_alphasearch_20260821.R — alpha-search 큐소비자 텔레그램 보고 (AS-20260821)
# run: cd C:/Users/99922/OneDrive/Quant_Module_Moltbot && Rscript -e 'source("stage_artifacts/paper_recharge/tg_alphasearch_20260821.R")'

source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent    = "AlphaSearch",
  title    = "alpha-search 큐 가동 결과 — 3건 처리 (2026-08-21)",
  relaxed  = TRUE,
  force    = TRUE,
  sections = list(

    list(type = "summary", emoji = "📋",
         body = "논문 팩터 3건 심사 — 전부 격리(QUARANTINE), 자본 투입 없음."),

    list(type = "text", emoji = "📚", heading = "연구 컨텍스트",
         body = paste(
           "[연구 목적] 대기 중이던 논문 팩터 3건을 실행 가능한 알파 신호인지 심사했습니다.",
           "[검토 내용] batch_434 사전검증(논문이 신호를 제안하는지 확인) + 실행된 백테스트 판정 수집.",
           "[결론] 3건 전부 격리(QUARANTINE) — 실제 자본 투입 없음. 레짐 오버레이 후보 1건 별도 등재."
         )),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 새 논문 3건에서 종목 선별 신호를 뽑아 과거 데이터로 수익성을 검증했습니다",
           "방법: 논문이 실제 신호를 제안하는지 먼저 확인(batch_434)하고, 실행된 건은 백테스트 지표로 판정했습니다",
           "결과: 3건 모두 기준 미달 — 이 아이디어들에는 실제 자본을 배정하지 않습니다",
           "의미: 레짐 오버레이(시장 국면 구분) 후보 1건(FQ-240)은 다른 경로로 보존해 추후 재검토합니다"
         )),

    list(type = "bullet", emoji = "📊", heading = "처리 내역 (3건)",
         items = c(
           "[1] ARFIMA_TSMOM (2607.19497) — 백테스트 실행 | grade F | QUARANTINE",
           "     PORT_t 1.21 (기준 2.95), OOS 0.57 (기준 0.70), MDD 64.3%",
           "     판정: 실패 — 이 아이디어에는 자본을 배정하지 않습니다",
           "[2] VOL_HURST (2608.16749) — batch_434 건너뜀 | QUARANTINE",
           "     순수 측정 방법론 논문(q-fin.MF): 크로스섹션 신호 미제안, KR Hurst 계열 3연속 실패",
           "     판정: 코드 생성 없이 격리 — 논문이 제안하지 않은 신호 날조 금지",
           "[3] 2608.09641 TrackB — batch_434 건너뜀 | QUARANTINE",
           "     m-minus는 지수 레벨 동기화 지표 — 개별 종목 횡단면 수익 예측 미제안",
           "     판정: TrackB 격리 / TrackA(레짐 오버레이) -> FQ-240 등재"
         )),

    list(type = "bullet", emoji = "🔬", heading = "ARFIMA_TSMOM 백테 세부",
         items = c(
           "신호: Variance Ratio(3) > 1 조건 종목에만 12-1 모멘텀 적용",
           "PORT_t(NW lag-3): 1.21 << 2.95 HARD 기준",
           "OOS retention: 0.57 < 0.70 HARD 기준",
           "Calmar: 0.242 << 0.64 기준 | MDD: 64.3%",
           "기전: VR>1 필터가 KR 횡단면 대부분 통과 -> 순수 12-1 MOM과 사실상 동등",
           "이 논문(2607.19497) 4번째 시도 전소 (spec_mass/T_RetAutoCorr/SpectralPersistence/ARFIMA)"
         )),

    list(type = "bullet", emoji = "🗂️", heading = "FQ 등재 (레짐 오버레이 후보)",
         items = c(
           "FQ-240: m-minus 하단 스펙트럼 레짐 오버레이 (Lower Spectrum Market Synchronization)",
           "논문 2608.09641: 60d 롤링 k=10 클러스터 상관행렬에서 마르첸코-파스투르 하한",
           "m-minus 상승 = 시장 동기화 강화 = 수익분포 왼쪽 이동",
           "소비 경로: factor-rotation RCMA 후보 (alpha-search 대상 아님)"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 단계",
         items = c(
           "이번 런 자동실행 대상 논문 소진 (MAX_ALPHA=2 미도달 — 가용 testable 3건 전부 batch_434/실패)",
           "FQ-240(m-minus 레짐) -> factor-rotation RCMA 경로로 이관",
           "2607.19497 VR 임계값 강화(VR>1.3/1.5) 재시도 검토 가능 (next_probe A)",
           "alpha_frontier_queue.json FQ-239까지 중 PENDING 소비 계속"
         ))
  ),
  charts = c(
    "stage_artifacts/alpha_search/20260821_074219_6672/equity_curve.png",
    "stage_artifacts/alpha_search/20260821_074219_6672/annual_returns.png"
  )
)
