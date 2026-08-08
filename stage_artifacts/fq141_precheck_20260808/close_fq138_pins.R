source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ138_PINS_20260808_DATA_PRECONDITION",
  verdict_type = "capability_established",
  layer = "1_재료",
  mechanism_diagnosis = paste(
    "FQ-138 측정 전 데이터 전제를 실측해 사전등록에 파일·vintage 를 못박았다 — 기록된 재발 함정을 선제 차단한 것이다.",
    "같은 디렉터리에 파일럿 grid_*(2023-01~2026-06 · 42개월 · returns 105,487행)과 확장본 gridx_*(2019-11~2026-06 · 80개월 · 191,980행)이 나란히 있다. 확장본이 1.9배이며 파일럿 사용 시 표본이 절반 손실된다.",
    "과거 세션이 확장본을 두고 파일럿을 써서 3연속 재구성 실패한 전례가 있으므로(memory: FQ-139 아크), 사전등록에 use/do_not_use 를 명시했다.",
    "★조건부 표본 함의: base rate 42.9% 적용 시 gridx 80개월 -> ~34개월 / grid 42개월 -> ~18개월. 원 보고 n=27 은 그 사이 값이므로 원 측정이 어느 패널을 썼는지 측정 전 확인이 필요하다(가정 금지).",
    "★vintage: gridx_vintage.txt = RAWDATA@20260803_0705+benchmark@20260803_0836 인데 gridx_vintage_compare.json 의 pinned 는 @20260802 계열이고 bench max_abs_diff 0.0039781953972 · n_diff_gt_1e9=1 (size/adv 는 diff 0). §7 Vintage Pinning 상 판정 산출에 핀 태그 기록 + bench 차이 감도 병기를 요구사항으로 넣었다."),
  next_probes = c(
    "FQ-138d 원 측정 패널 확인 — WT-D20260803_008 이 grid 를 썼는지 gridx 를 썼는지 산출물에서 확인. 파일럿이었다면 원 n=27 과 IC 5.17 자체가 42개월 표본 산물이므로 재판정의 기준선이 달라진다",
    "FQ-138e bench vintage 감도 — max_abs_diff 0.00398 이 1개월에만 있으나(n_diff_gt_1e9=1) 조건부 표본이 ~34개월로 작아 1개월 차이의 비중이 크다. 두 vintage 로 각각 산출해 판정이 뒤집히는지 확인",
    "FQ-138a 본 측정 — 4 arm(SIG_ON/SIG_OFF/NEU_ON/NEU_OFF) canonical_screen_bt + DiD paired NW t >= 2.0 + 위약 셔플 주입. alpha/forge 소관이므로 위임 필요"),
  consumer_surfaces = c("팩터랭킹", "오버레이", "선별라벨"),
  frontier_update = "FQ-138 사전등록에 데이터 핀(gridx 사용·grid 금지) + vintage 기록 요구 추가 · 파일럿/확장본 1.9배 차 실측 · FQ-138d/e 신규",
  live_trigger = "원 측정이 파일럿 패널이었던 것으로 확인되면 재판정 기준선(IC 5.17 · n=27 · PORT_t 2.198) 자체를 확장본에서 재산출해야 한다",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/fq138_preregistration.json",
                    "stage_artifacts/fq141_precheck_20260808/probe_grid.R",
                    "04_Research/method_frontier/fq002_contract_magnitude/gridx_vintage_compare.json")
)
cat("[close_fq138_pins] RC_OK\n")
