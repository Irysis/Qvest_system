source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "CHIP-task_fea61227-tilt-convention-R2",
  verdict_type = "incumbent_confirmed",
  mechanism_diagnosis = "가중 규약 격차의 실축은 tophi φ 단일(모양 Δ0.030·CRISIS cap 은 bare/overlay 양쪽 소수3자리까지 inert). φ 는 결함 스위치가 아니라 단조 다이얼(φ↓ → SR↑MDD↑턴오버↑). bare sleeve 에서는 z|φ=0 이 SR 우세(paired t 3.6)라 정렬이 성과 손실로 보였으나, overlay 결합(MDD 레버) 하에서 MDD 25% 문턱이 판별력을 얻어 정본 23.28%(충족) vs 실배포 29.02%(4pp 위반)로 갈림 — 즉 실배포 우세는 SR 단독 채점 아티팩트였고, 포트폴리오 목표로 채점하면 현직 규약(rank|φ=3)이 확정. 정렬 근거가 거버넌스 단독에서 거버넌스+실증으로 강화됨.",
  next_probes = c(
    "P1': rank|φ=1 을 φ 축 유일 실질 후보로 정식 심사 — overlay SR 1.988 / MDD 23.33%(정본 +0.05pp)로 제약을 지키며 SR +0.083, 단 paired t 1.536 유의 아님. selection_type=sweep(n_trials=12) → DSR 게이트 + holdout 예측구간 사전등록(봉인) 후 forge-authoritative PORT_t 재측정.",
    "P2': φ × overlay 강도 격자 — 현 측정은 overlay 스케줄 고정(캐리어 실측 invested). overlay 가 MDD 레버이므로 더 강한 overlay 하에서 φ=0 의 MDD 29.02% 가 25% 아래로 내려오는지가 z-선형 부활의 유일한 경로. 격자 = φ{0,1,3} × overlay 강도 스케일{현행, ×1.2, ×1.5}.",
    "P3: parity 게이트 4슬롯 월간 배선 — forward 산출 vs 캐리어-엔진 replay 대조. 현행 배포분 39.0%/24.5% 검출로 차단 실효 확인됨. 위반 주입 테스트(정본 함수를 z-선형으로 바꿔치기 시 발화) 포함. 정렬 결정과 무관하게 유효(어느 규약이든 배포-북 일치를 강제).",
    "P4: 동종 결함 census 진행 중 — 정본 계약 함수 존재하는데 인라인 재구현된 지점(normalize_long_only/build_bt_result/canonical_screen_bt/load_month_factors 계열). 본 건 4/4 슬롯 + 08-08 optimizer 캡순서 건이 같은 계통이라 계통성 확인 대상.",
    "P5: CRISIS cap inert 의 기전 규명 — 271m/269m 양쪽에서 소수3자리 동일은 '발화 자체가 희소'(CRISIS 라벨 4개월)일 가능성. 국면 라벨 품질(recall<base 기지)과 얽혀 있어, cap 무효가 규칙 문제인지 라벨 문제인지 미분리. 라벨 자격 관문 연계."
  ),
  consumer_surfaces = c(
    "위험모델/베타예산: MDD 25% 문턱이 overlay 결합 후에만 판별력을 갖는다는 사실 = 모든 가중 규칙 채점을 overlay 결합으로 해야 한다는 규약(bare sleeve 채점은 제약 위반을 은폐)",
    "monitoring 신호: forward-vs-replay parity 를 drift 경보 축으로 편입",
    "선별 라벨: z|φ=0 프로파일(고집중 max_w 0.191·고회전 1.308·MDD 29%)을 screen-tier 성격으로 등재 — 자본 부적격이나 신호는 실재",
    "타 모드 이식: RAMP/FR sleeve 가중의 φ 등가 파라미터도 동일 다이얼인지 확인 대상"
  ),
  frontier_update = "FQ 등재: (a) rank|φ=1 정식 심사 [P1'] (b) φ×overlay 강도 격자 [P2']. owner=Q-Lead. (a)는 정렬 결정과 병행 가능, (b)는 z-선형 부활 경로.",
  live_trigger = "z-선형/φ=0 부활 조건 (경로-scoped, 영구 판결 아님): ① overlay 강화 또는 신규 MDD 레버 편입으로 φ=0 의 overlay-결합 MDD 가 25% 미만으로 내려오면 즉시 재심(현재 29.02%, 갭 4.02pp) ② 거래비용 가정이 15bps 아래로 내려가면 고회전(1.308) 페널티가 줄어 재계산 ③ 도훈이 MDD 제약을 재설정하면 SR 우위(2.108 vs 1.905)가 곧바로 채택 근거가 됨. 세 조건 중 하나라도 발화 시 P2' 격자를 먼저 실행.",
  layer = "구성/가중(weighting rule) — 배포 정합 + 제약 충족 계층",
  evidence_refs = c("stage_artifacts/tilt_realign_20260808/phi_sweep_under_overlay.csv",
                    "stage_artifacts/tilt_realign_20260808/phi_shape_cap_sweep.csv",
                    "stage_artifacts/tilt_realign_20260808/arm_ab_summary.json",
                    "memory: project-forward-tilt-convention-divergence-20260808")
)
