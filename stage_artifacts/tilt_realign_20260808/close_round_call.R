source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "CHIP-task_fea61227-tilt-convention",
  verdict_type = "capability_established",
  mechanism_diagnosis = "forward 생성기 4/4 슬롯이 정본 가중함수(strategy_tilt_weights.R)를 source 하지 않고 각자 인라인 재구현(3세대 표류) — 기전은 규약 변경이 아니라 재구현 자유. 전기간 271m paired 실측에서 실배포 z-선형이 net SR 1.718 vs 정본 1.531(t=-3.607, p=0.0004)로 우세 → 정렬 근거는 성과가 아니라 측정-배포 정합(북 IR 1.416/holdout 봉인이 정본 엔진 측정)임이 확정. 내 단월(7월 -1.60%pt) 기반 CRISIS-해악 진술은 전기간 미지지(CRISIS 4m C 근소 우세) = 일화의 구조 승격 오류.",
  next_probes = c(
    "P1: z-선형 가중을 정식 alpha 후보로 WT 라우팅 — 271m paired t=-3.607(p=0.0004)은 기각이 아닌 자격 신호. forge-authoritative PORT_t + oos_retention(v2 3분할 중앙값) + book-marginal dIR 정규 심사. 고MDD(48.7% vs 40.7%)가 MDD<25% 목표와 충돌하므로 overlay 결합 하 재측정이 판정축.",
    "P2: 가중 규칙 축 중간지대 sweep — tophi phi 를 3(정본)~0(z-선형 등가) 사이 스캔해 SR-MDD 프론티어 최적점 실측. 현 두 점은 축의 양 끝단일 뿐, 중간 phi 가 SR 1.718 수익성과 MDD 40% 방어를 동시에 잡는지 미검. selection_type=sweep → DSR 게이트 적용.",
    "P3: parity 게이트 일반화 — forward 산출 vs 캐리어-엔진 replay 대조를 4슬롯 월간 배선. 현행 배포분 39.0%/24.5% 검출로 차단 실효 확인됨. 위반 주입 테스트(정본 함수를 z-선형으로 바꿔치기 시 발화) 포함.",
    "P4: 동종 결함 census — 정본 계약 함수가 있는데 인라인 재구현된 다른 지점 스캔(normalize_long_only/build_bt_result/canonical_screen_bt 계열). 본 건 4/4 + 08-08 optimizer 건(normalize_long_only 캡 순서)이 같은 계통이라 계통성 의심."
  ),
  consumer_surfaces = c(
    "위험모델/베타예산: CRISIS ub 0.10 분기의 실효를 국면 라벨 품질과 함께 재평가(CRISIS 4m 표본으로는 판별 불가 — 라벨 자격 관문 연계)",
    "monitoring 신호: 월간 forward-vs-replay parity 를 drift 경보에 편입(배포-북 괴리 = 신규 감시 축)",
    "선별 라벨: z-선형의 고집중(max_w 0.191)·고회전(1.308) 프로파일을 screen-tier 후보 성격으로 등재",
    "타 모드 이식: RAMP/FR sleeve 가중도 동일 정본 함수 경유 여부 확인 대상"
  ),
  frontier_update = "FQ 신규 등재 예정: (a) z-선형 가중 정식 심사 [P1] (b) tophi phi sweep [P2]. owner=Q-Lead, 착수는 도훈 정렬 결정 후.",
  live_trigger = "정본 정렬 후에도 실배포-북 괴리 재발 시(parity 게이트 발화) 즉시 재개. z-선형 WT 가 게이트 통과하면 규약 교체 재심.",
  layer = "구성/가중(weighting rule) — 배포 정합 계층",
  evidence_refs = c("stage_artifacts/tilt_realign_20260808/arm_ab_summary.json",
                    "stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv",
                    "memory: project-forward-tilt-convention-divergence-20260808")
)
