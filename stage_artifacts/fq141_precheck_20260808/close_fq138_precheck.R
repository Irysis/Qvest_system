source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ138_PRECHECK_20260808_REGIME_IS_THE_TAILWIND_AXIS",
  verdict_type = "capability_established",
  layer = "1_재료",
  mechanism_diagnosis = paste(
    "★FQ-138 착수 전 사전 확인 — 국면 변수가 오늘 아크의 d 축과 동일하며, 그로 인해 설계에 교란이 드러났다.",
    "mega_spread = mean(Ret_1m[rk<=10]) - median(Ret_1m) 를 439개월 산출해 d 와 대조: cor +0.896 (t-1 형태 +0.897) · 부호일치 82.7% ⇒ 같은 축이다.",
    "★교란: FQ-138 이 조건으로 쓰는 't-1 mega_spread <= 0' 은 메가캡이 지는 달 = 오늘 확립한 소형 편향 포트폴리오의 **순풍 국면**이다. 계약 신호 포트폴리오도 이 저장소 전략들처럼 OTHER tier 위주일 것이므로, 조건부 canonical PORT_t 2.198 의 상당분이 신호가 아니라 국면 순풍일 수 있다.",
    "⇒ 사전등록은 국면 순풍을 반드시 통제해야 한다. 같은 달들에서 **중립(신호 없는) 포트폴리오의 조건부 알파**를 함께 재지 않으면 순풍을 신호로 승격시키게 된다.",
    "부수 1 — base rate: t-1 mega_spread<=0 은 전 구간 42.9%(188/438). 시대별 1990s 55.9% / 1995s 36.7% / 2000s 45.0% / 2005s 48.3% / 2010s 48.3% / 2015s 33.3% / 2020s 36.7% / 2025s 31.6% (최근 감소).",
    "부수 2 — 표본 크기 함의: FQ-138 조건부 n=27 이고 base rate 42.9% 이면 원 패널이 ~63개월이다. 짧고 최근인 창이므로 오늘 확립한 고-핸디캡 구역(36m ending 2026 d_ann +0.2027)에 정확히 들어간다.",
    "부수 3 — 현재 국면 ON(2026-07, 직전월 mega_spread -0.1248) — 되돌림과 함께 막 켜졌다."),
  next_probes = c(
    "FQ-138a 순풍 통제 사전등록 설계 — 조건부 판정에 반드시 중립 대조군을 포함한다. 최소 형태: 같은 조건 달에서 (a)계약 신호 top-25 (b)무작위/POOL_EW top-25 의 cap-w PORT_t 를 함께 산출해 **차이**를 판정 대상으로. 차이가 사라지면 2.198 은 국면 순풍이다",
    "FQ-138b 창 길이 라벨 부착 — 원 패널 ~63개월은 고-핸디캡 구역이다. 사전등록 시 측정 창의 d_ann 과 역사 백분위를 명시하고, 가능하면 패널을 확장해 창 효과를 희석",
    "FQ-138c 국면 base rate 의 사전등록 반영 — 42.9% 는 동전에 가깝다. '국면 조건부' 가 표본을 절반으로 줄이는 대가를 치르므로, 조건부 개선폭이 표본 축소로 인한 t 손실을 넘는지가 판정의 핵심"),
  consumer_surfaces = c("팩터랭킹", "오버레이", "선별라벨", "monitoring"),
  frontier_update = "FQ-138 국면 변수 = d 축 확인(cor 0.896) · 순풍 교란 적발로 사전등록 설계 변경 필요 · base rate 42.9% · 현재 국면 ON · FQ-138a/b/c 신규",
  live_trigger = "현재 국면 ON 이므로 신규 관측월이 조건부 표본에 즉시 추가된다 — 사전등록을 지금 확정해두면 이후 달이 자동으로 OOS 가 된다(사후 선택 여지 축소)",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_fq138_regime_link.R",
                    "04_Research/method_frontier/fq002_contract_magnitude/diag_fq125_stage1_controls.R",
                    "stage_artifacts/fq141_precheck_20260808/np157c2a1c_findings.md")
)
cat("[close_fq138_precheck] RC_OK\n")
