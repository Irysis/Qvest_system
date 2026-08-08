source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "FQ-139",
  verdict_type = "capability_established",
  mechanism_diagnosis = "계약수주 알파의 alpha_package.falsification #1 을 성과가 아닌 부수 관측(투자자 수급)으로 직접 시험했다. 신호 상위분위 종목의 신호월 이후 t+1~t+3 기관 순매수는 하위분위 대비 −0.01075(t=−2.258, p=0.024)로 **증가가 아니라 감소**했고, 반대로 외국인은 +0.01318(t=2.624, p=0.009) 증가했다. 따라서 mechanism.path('기관 후속 매수로 가격 반영')는 기각되고 경로가 외국인 주도로 교체된다. 이는 폐기가 아니라 재서술이며, FQ-138 의 국면 의존(mega_spread<=0)을 수급 구조로 설명할 후보가 생겼다. 단 4개 신호 중 3개는 값 0 이 대량 몰려 하위20 분위가 형성되지 않아 판정이 w_amt 단일 신호 위에 서 있고, 패널도 77개월·140종목으로 좁다.",
  next_probes = c(
    "F1: 분위 형성 실패 수리 후 재확인 — ratio_rev_sum·amt_sum·n_contracts 는 0 동률 블록 때문에 하위20 이 안 잡혔다. '0 초과 vs 0' 이분 또는 동률-인지 분위로 바꿔 4신호 전부에서 부호가 유지되는지 확인. 단일 신호 위의 판정을 4신호로 넓히는 것이 이 결론의 첫 강건성 시험.",
    "F2: 재서술의 파생 예측 시험 — 외국인 주도가 참이면 ①외국인 접근성 낮은 종목에서 알파 약화 ②외국인 매수 강도가 국면 조건과 상호작용 ③기관 매도가 매물 압력이면 초기 반응 지연. 셋 다 수급 데이터로 즉시 측정 가능하며, 특히 ②는 FQ-138 의 국면 의존을 기전으로 설명할 수 있는지를 직접 시험한다.",
    "F3: 정규화 축 강건성 — 순매수를 거래대금으로 정규화했다. 시총·유통주식 기준에서 부호와 유의성이 유지되는지 확인(정규화 선택이 결론을 만들지 않았음을 보이는 통제)."
  ),
  consumer_surfaces = c(
    "팩터랭킹: 계약 신호를 외국인 수급과 결합한 조건부 형태로 평가 — 단독 랭킹이 아니라 수급 상호작용",
    "유니버스 필터: 외국인 접근성(지분율·한도) 이 낮은 종목에서 신호 약화가 확인되면 필터 축으로 소비",
    "오버레이/국면 입력: FQ-138 의 mega_spread 국면 의존이 외국인 수급으로 설명되면 국면 대리변수를 수급으로 교체 가능",
    "monitoring: 외국인/기관 순매수 스프레드를 계약 알파의 건전성 지표로 관측"
  ),
  frontier_update = "FQ-139 = 기전 검증 완료(재서술). FQ 신규 등재 예정: F1(분위 형성 수리·4신호 확인) · F2(파생 예측 3종, 특히 국면×수급 상호작용). FQ-138 사전등록 라운드는 이 재서술을 반영해 mechanism 서술을 갱신한 뒤 진행할 것.",
  live_trigger = "'기관 후속매수' 경로 부활 조건 (경로-scoped, 방향 반증됨): ① F1 에서 4신호로 넓혔을 때 부호가 뒤집히면 w_amt 특이성으로 재분류 ② 정규화 축(F3)에 따라 부호가 바뀌면 정규화 아티팩트로 재분류 ③ era 를 넓힌 패널(2019 이전)에서 다른 구조가 나오면 표본 한정으로 재분류. 셋 중 하나라도 발화하면 기전 판정 재개.",
  layer = "재료/기전 — 알파 생성층 (비-return lane)",
  evidence_refs = c("stage_artifacts/fq139_mechanism_falsification/fq139_verdicts.csv",
                    "stage_artifacts/fq139_mechanism_falsification/run_fq139_v2.R",
                    "memory: project-fq139-contract-mechanism-foreign-not-institutional-20260808")
)
