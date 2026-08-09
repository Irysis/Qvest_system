## FQ-143 P14 — close_round (연속성 계약 paved path)
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT, "02_Infrastructure/contracts/close_round.R"))

close_round(
  round_id = "WT-D20260809_002 (tail-targeted regime overlay)",
  verdict_type = "screen_tier_routed",
  mechanism_diagnosis = paste0(
    "국면 라벨은 분산 상태 검출기이지 방향 검출기가 아니다. trailing 실현변동성을 연속 통제해도 ",
    "꼬리(<-10%) 예측력이 살아남지만(z=+2.61, p=0.0090, LR 증분 p=0.0106) 방향 계수는 정확히 소멸한다",
    "(t=+0.01, p=0.990). 선형 노출 스케일 레버는 조건부 '평균'만 수익화하는데 배포창 실측 ",
    "E[ret|라벨ON]=+4.01%/월 > E[OFF]=+3.41%/월 로 부호가 반대다. 따라서 노출 축소는 구조적으로 손해이며 ",
    "깊이(30/50/70%)를 바꿔도 paired t 가 -1.838 로 불변이다(선형 스케일의 수학적 귀결). ",
    "정량 천장: t=+2.0 도달에 필요한 꼬리 정밀도는 적중배수 10.8~16.2 인데 실측은 2.1~2.7 (5~6배 부족). ",
    "오라클(실현 하락 예지)조차 incumbent 위 t=+3.18 / 최대낙폭 -2.09%pt 가 상한이다 — ",
    "현행 연속 스케일러가 이미 최대낙폭 40.7%->23.3% 를 회수해 잔여 여지 자체가 작다. ",
    "라벨 오버레이의 incumbent 최대낙폭 개선은 정확히 0.00%pt — 라벨은 현행 최대낙폭 구간에 켜지지 않는다. ",
    "★기각된 것은 가설이 아니라 레버다: 사전선언 반증 2축(에피소드-군집 강건성, 변동성 통제 증분)이 모두 생존했다."
  ),
  next_probes = c(
    "NP-1 라벨을 무비용 경보(monitoring/tripwire)로 소비 — 상방을 포기하지 않으므로 보험료 0. 꼬리 자격은 확립(적중배수 2.671, p=3.15e-06, 에피소드 제거 4/4 유지)",
    "NP-2 라벨을 위험모델(Sigma) 입력으로 라우팅 — 분산을 재는 신호의 제자리. 노출을 안 줄이고 꼬리를 줄이므로 선형 레버의 부호 제약에 걸리지 않음 (risk-research 소관)",
    "NP-3 노출 대신 집중도를 조이는 변형 — 25종 상한 안쪽 이동이라 INV-7 저촉 없음. 집중도는 꼬리에 비선형으로 걸려 필요-정밀도 역산이 그대로 적용되지 않음 (optimizer-research 소관)",
    "NP-4 E7 unified_regime 저장 패널의 vintage 확보 (production_parity_verified=false) — NP-1/NP-2 양성 승격의 선행 조건",
    "NP-5 반증축 (c) 미측정분: 심한 하락월의 시장 집계 외국인·개인 순매도 강도 (A6_investor_flow_stock_daily) — 경제 기전의 유일한 직접 증거이자 NP-2 설계 입력"
  ),
  consumer_surfaces = c(
    "5 monitoring — NP-1 무비용 경보 (즉시 가능)",
    "4 위험모델 — NP-2 국면조건부 공분산/crowding 입력 (risk-research 라우팅)",
    "1 종목선별/집중도 — NP-3 (optimizer-research 라우팅)",
    "3 오버레이 — 본 라운드에서 config-scoped 미달 (선형 노출 레버)",
    "6 선별라벨 — 라벨 발화월 표본 축적 시 배포창 자격 재판정 대상"
  ),
  frontier_update = paste0(
    "라벨 자격은 (라벨, 사건정의) 쌍에 붙는다는 08-08 발견을 한 단계 더 밀었다: ",
    "자격이 있어도 **소비 레버의 함수 형태**가 맞아야 수익이 된다. ",
    "선형 노출 레버 = 조건부 평균 수확기 / 분산 정보는 비선형 레버(집중도·공분산)로만 소비 가능. ",
    "브리핑 인용 적중배수(1.16/1.97/3.19)는 동월 정렬 산물 — 정본은 0.97/1.61/2.67 로 교체 필요."
  ),
  live_trigger = paste0(
    "부활 조건 4종 (경로-scoped, INV-7): ",
    "(1) 꼬리 정밀도가 적중배수 10.8 이상으로 재구성될 때 — 국면 라벨 계열 개선으로는 도달 근거 없고, ",
    "비-return 신규 원천(DART insider·계약금액·공매도/대차)으로 꼬리 예측을 재구성한 경우에만 재측정. ",
    "(2) base 전략의 연복리수익률이 크게 낮아져 노출 축소의 기회비용이 줄 때 — 현행 base 45.5%/yr 가 ",
    "보험료를 비싸게 만드는 주 원인이므로 incumbent 교체 시 산식이 바뀐다. ",
    "(3) 현행 연속 스케일러(m4 x beta_R05)가 제거·약화되면 잔여 여지가 다시 열린다(현재 오라클 천장 2.09%pt). ",
    "(4) 배포창 라벨 ON 표본이 축적되어(현 n_on=28, 검출력 0.32) 검출력 0.8 에 도달하면 자격 재판정 — ",
    "현 배포창 INELIGIBLE 은 무판별이 아니라 저검정력이다."
  ),
  layer = "overlay / regime-consumption",
  evidence_refs = c(
    "qepm/mailbox/worktask/WT-D20260809_002/alpha_package.json",
    "qepm/mailbox/worktask/WT-D20260809_002/preregistration.json",
    "qepm/mailbox/worktask/WT-D20260809_002/challenge_note.md",
    "stage_artifacts/WT_D20260809_002/alpha_validation.json",
    "stage_artifacts/WT_D20260809_002/alpha_scores.parquet",
    "stage_artifacts/fq143_tail_overlay_20260809/"
  )
)
cat("[P14] close_round done\n")
