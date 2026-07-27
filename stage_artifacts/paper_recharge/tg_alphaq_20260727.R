source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "alpha-search 큐 가동 (팩터→모드) 20260727",
  relaxed = TRUE,
  sections = list(

    list(type = "summary",
         heading = "오늘 결과",
         body = "처리 2건 / 채택 0건 / 격리 2건. PORT_t 기준치 미달로 L5 게이트 격리."),

    list(type = "bullet",
         heading = "쉬운 설명 — 오늘 뭘 시도했나",
         items = c(
           "팩터 1 — 꼬리 리스크 팩터(hill_tail_index): 주가 급락이 자주 발생하는 종목(꼬리가 두꺼운 주식)이 향후 더 높은 수익을 올린다는 가설을 검증. 결과: 예측력 거의 없음 (IC≈0, 초과수익 -5%p).",
           "팩터 2 — 거래량 서프라이즈(vol_adj_volume_surprise): 변동성으로 설명되지 않는 급격한 거래량 증가가 정보 유입 신호라는 가설. 결과: 예측력 없음 (PORT_t=-1.45, 반대 방향, 회전율 996%).",
           "두 팩터 모두 한국 K200+KOSDAQ150 장기 백테(2005~2026)에서 수익 예측 신호로 작동하지 않음 확인."
         )),

    list(type = "kv",
         heading = "팩터별 핵심 지표",
         kv = list(
           "hill_tail_index 포트폴리오-t" = "0.77 (기준 2.95 — 미달)",
           "hill_tail_index 초과CAGR"     = "-5.01%p (BM 14.9% vs 전략 9.9%)",
           "hill_tail_index OOS 잔존율"   = "0.77 (통과) — 신호 감쇠 없으나 신호 자체 약함",
           "vol_surprise 포트폴리오-t"    = "-1.45 (음수 — 반대 방향)",
           "vol_surprise OOS 잔존율"      = "-0.58 (실패)",
           "vol_surprise 회전율"          = "996%/년 (신호 불안정)"
         )),

    list(type = "bullet",
         heading = "기전 진단 + 다음 탐색",
         items = c(
           "[hill] 꼬리-수익 연결 채널 비성립: KR long-only 25종목에서 꼬리 두께가 위험 프리미엄으로 전환되지 않음. 반대 방향(얇은 꼬리) 또는 위기 구간 조건부 검증이 다음 탐색.",
           "[hill] next_probe-1: Score=+alpha_hill(꼬리 얇은 종목) 역방향 — 저-꼬리 종목의 오버슈팅 회복 수익 가설.",
           "[hill] next_probe-2: 위기 구간(BearProb>0.5) 조건부 발동 — 평상시 0, 위기시 high-tail = 기관 회피 = 반등 포착.",
           "[vol_surp] 충격형 이벤트 채널: COVID(+7.4%p) + EU위기(+14.2%p) 두 극단 구간에서만 우위 — 평시 신호 아닌 충격 검출기로 재설계 필요.",
           "[vol_surp] next_probe-1: 상위 5%ile 극단 거래량 급등 달만 선별 → 이벤트 트리거 구조.",
           "[vol_surp] next_probe-2: 불확실성 충격 × vol-surprise 교집합 — D3 dead class 회피하며 충격 채널로 재해석."
         )),

    list(type = "bullet",
         heading = "계층 병목 + frontier 상태",
         items = c(
           "return-derived 팩터 추가 확증: vol 계열 D3 dead class 재확인(hill 인접, vol-surprise D3 직접 해당).",
           "frontier 현황: FQ-001~005(비-return 원천 — DART insider 등)가 주력. 오늘 2건은 frontier 순위 3~4위 후보 소진.",
           "큐 소비 후 route 우선순위 1~2(vol_rank_stability + spec_lowfreq_mass)는 07-26 autorun에서 이미 spawn됨 — 결과 확인 필요."
         ))
  ),
  charts = NULL
)

cat("[tg_alphaq_20260727] 발송 완료\n")
