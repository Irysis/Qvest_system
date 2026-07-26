PROJECT_ROOT <- Sys.getenv("QM_ROOT")
if (nchar(PROJECT_ROOT) == 0) PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent = "Q-Lead",
  title = "리서치 소스 배분 + 팩터 마이닝 (20260726)",
  relaxed = TRUE,
  force   = TRUE,
  lock_scope = "paper_router_20260726",
  sections = list(

    list(type  = "summary",
         emoji = "📌",
         body  = "오늘 arxiv 30편 전수 라우팅 + STEP2 팩터 추출 보강. 어제 런 누락 팩터 2건 복구, 알파서칭 2건 자동 스폰 중."),

    list(type    = "bullet",
         emoji   = "📖",
         heading = "쉬운 설명",
         items   = c(
           "시도: 오늘 수집한 금융 논문 30편을 알파/최적화/위험/국면/제외 5개 모드로 분류했습니다",
           "방법: 제목·초록 1차 분류 후, 분류 무관하게 전체 논문에서 종목 선별 가능 신호를 2차 스캔(STEP2 오버레이)했습니다",
           "결과: 추세추종·행렬역학 논문에서 각각 숨은 팩터 1건씩 발굴 — 2건 자동 백테스팅 진행 중",
           "의미: 어제(20260724) 런에서 팩터 없음으로 처리됐던 2편을 오늘 재검토로 복구했습니다"
         )),

    list(type    = "kv",
         emoji   = "📊",
         heading = "배분 결과 (arxiv 30편)",
         kv      = list(
           "알파 후보"     = "4편",
           "최적화 방법론" = "7편",
           "위험 모델"     = "4편",
           "국면/오버레이" = "4편",
           "범위 외 제외"  = "11편",
           "curated 신규"  = "0편 (15/15 기처리)"
         )),

    list(type    = "bullet",
         emoji   = "🔬",
         heading = "발굴 팩터 (testable 4건)",
         items   = c(
           "P1 [AUTORUN] 변동성 순위 안정성 (vol_rank_stability) 2607.19005 Observable Matrix Dynamics",
           "P2 [AUTORUN] 스펙트럼 저주파 질량 (spec_lowfreq_mass) 2607.19497 Trend-Following Systems",
           "P3 [큐] Hill 꼬리 지수 (hill_tail_index) 2607.16450 Heavy Tails ETFs",
           "P4 [큐] 변동성 조정 거래량 서프라이즈 (vol_adj_volume_surprise) 2606.08141 SMAR"
         )),

    list(type    = "bullet",
         emoji   = "📋",
         heading = "모드 큐 (optimizer 7 / risk 4 / regime 4)",
         items   = c(
           "최적화: TDA(2607.21170) / Mixing-Law MVO(2607.18813) / CVaR+Hill(2607.16450) / AlphaZeroBeta(2607.18001) 외 3편",
           "위험: 서명 모델위험(2607.20343) / Bernoulli 상관(2607.16801) / CoHM(2607.16601) / AGCA 극단(2607.13112)",
           "국면: 추세추종 스펙트럼(2607.19497) / 양자 저장소(2607.16281) / Belief-at-Risk(2606.15473) / 현금 오버레이(2606.09025)"
         )),

    list(type    = "bullet",
         emoji   = "➡️",
         heading = "다음 액션",
         items   = c(
           "AUTORUN P1 vol_rank_stability 결과 대기 (canonical 백테스팅 진행 중)",
           "AUTORUN P2 spec_lowfreq_mass 결과 대기 (canonical 백테스팅 진행 중)",
           "P3/P4 팩터 — 다음 /alpha-search 세션 큐 대기",
           "mode_queue_20260726.json 소비 예정 (paper_research_dispatch.R morning_run)"
         ))
  )
)
