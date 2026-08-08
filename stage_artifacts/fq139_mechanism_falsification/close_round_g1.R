source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "FQ-139-G1",
  verdict_type = "revival_conditional",
  mechanism_diagnosis = "F2 의 검정력 한계(broad 국면 13개월·299 이벤트)를 풀기 위해 국면 변수 mega_spread 를 패널 전 구간으로 재구성하려 했으나, 확장 전에 건 재현 검증에서 세 번 연속 막혔다. ①rawdata 전체시장(1,560종목/월)으로 만든 판은 원본(350종목/월) 대비 cor 0.177·라벨 일치 59.5% — median 산출 범위가 다름 ②us_k200∪us_kq150 로 유니버스를 맞춰도 cor 0.246·라벨 59.5% 로 여전히 미통과 ③원인 특정: grid 의 Ret_1m 은 후행이 아니라 **선행(다음달) 수익**이다(shift 검정에서 +1 이 mean|Δ| 0.0129, 0/−1 은 0.16대). 즉 내가 만든 국면 변수는 원본과 한 달 어긋난 다른 변수였다. 재현되지 않는 변수 위에서 확장 판정을 내면 그 판정은 기준이 없으므로 라운드를 여기서 정지한다. 원본 자체의 PIT 는 정상 — Ret_1m 이 선행이어도 ms_lag1=shift(mega_spread,1) 이라 결정시점에서 쓰는 값은 기지 정보다.",
  next_probes = c(
    "H1: 선행 규약으로 국면 재구성 후 게이트 재시도 — Ret_1m 을 다음달 수익으로 정의해 mega_spread 를 다시 만들고, 겹치는 42개월에서 라벨 일치 ≥85% 를 확인한 뒤에만 확장한다. per-stock cor 0.2684 잔차가 남아 있어 유니버스·필터 조건도 함께 대조할 것(mean|Δ| 0.0129 는 작은데 cor 이 낮은 조합은 이상치 지배를 시사).",
    "H2: 국면 변수 자체를 원본 스크립트에서 재사용 — 재구성 대신 diag_fq125_stage1_regime_robust.R 의 산출을 직접 저장·확장하도록 그 스크립트를 손대는 경로. 오늘 J1 에서 '재구성하지 말고 원장에서 역산하라'가 옳았던 것과 같은 구조이며, 재구성보다 확실하다.",
    "H3: F2 결론을 표본 한정 상태로 소비 — G1 이 미완이어도 F2 의 방향(수급 우위가 알파 약한 국면에서 더 큼)은 42개월 안에서는 실측이다. '국면 설명 실패'를 확정 대신 **표본-한정 잠정**으로 라벨링해 FQ-138 mechanism 서술에 반영하고, 확정은 H1/H2 이후로 미룬다."
  ),
  consumer_surfaces = c(
    "팩터랭킹: F1 의 '계약→외국인 매수'(10/11 강건)는 국면과 무관하게 확인 필터로 소비 가능 — G1 미완과 독립",
    "오버레이/국면 입력: 국면 대리변수를 수급으로 교체하려던 경로는 잠정 실패 — 확정은 H1/H2 후",
    "monitoring: grid 계열 산출물의 Ret_1m 타이밍 규약(선행)을 문서화 — 재사용자가 후행으로 오독하면 한 달 어긋난 분석이 나온다",
    "타 모드 이식: '재구성 전 재현 게이트'를 국면·수급 변수 재사용 시 표준 절차로"
  ),
  frontier_update = "FQ-139 하위 라운드 G1 = 재현 게이트 미통과로 정지(폐기 아님). FQ 등재 예정: H1(선행 규약 재구성) · H2(원본 스크립트 직접 확장 — 우선). F2 결론은 표본-한정 잠정으로 라벨링.",
  live_trigger = "G1 재개 조건 (경로-scoped, 재현 미달로 정지): ① H1 에서 선행 규약 재구성이 라벨 일치 ≥85% 를 통과하면 즉시 확장 재개 ② H2 로 원본 스크립트가 전 구간 산출을 저장하게 되면 재구성 자체가 불필요해져 즉시 재개 ③ grid 산출물의 타이밍 규약이 문서화되면 다른 재사용 분석도 함께 검증 대상.",
  layer = "재료/기전 — 알파 생성층 (국면 변수 재현 배관)",
  evidence_refs = c("stage_artifacts/fq139_mechanism_falsification/run_g1_regime_extend.R",
                    "stage_artifacts/fq139_mechanism_falsification/run_g1b_universe_scoped.R",
                    "memory: project-fq139-contract-mechanism-foreign-not-institutional-20260808")
)
