source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ138D_20260808_ORIGINAL_PANEL_CONFIRMED_AND_SELF_CORRECTION",
  verdict_type = "capability_established",
  layer = "1_재료",
  mechanism_diagnosis = paste(
    "FQ-138d 해소 — 원 측정(WT-D20260803_008)은 확장본 gridx_* 를 썼다. artifact_lineage.json 이 gridx_bench/liq/returns/universe_size + panelx_A 를 참조하고, mega_spread 정의 스크립트 diag_fq125_stage1_controls.R 과 run_fq125_stage1.R·emit_wt008.R 이 모두 gridx_ 전용(grid_ 0회)이다. ⇒ 기준선 재산출 불요.",
    "★자기 정정: 직전 라운드에서 사전등록에 '조건부 n=27 · base rate 42.9% ⇒ 원 패널 ~63개월(고-핸디캡 짧은 창)' 이라고 적었는데 **틀렸다**. 전 구간 base rate 를 최근 창에 적용한 오류다.",
    "실측: panelx_A = 80개월(201912~202607 · 월 중앙 81종목)로 gridx 와 일치하고, **그 창의 base rate 는 35.0%(28/80)** 이므로 n=27 이 정확히 설명된다(1개월 차는 말단 forward return 부재 수준).",
    "전 구간 42.9% 대비 낮은 이유는 최근 시대의 국면 희소성(2020s 36.7% · 2025s 31.6%)이다.",
    "⇒ 위험의 성격이 바뀐다: '짧은 패널' 이 아니라 **최근 국면의 희소성**이다. 다만 그 28개월이 전부 2019-12 이후 = 고-핸디캡 구역이라는 점은 유효하다.",
    "★교훈: base rate 를 인용할 때 **어느 창의 base rate 인가**를 함께 적어야 한다. 전 구간 통계를 부분 창에 적용하면 표본 크기로부터 패널 길이를 역산하는 식의 오추론이 나온다."),
  next_probes = c(
    "FQ-138a 본 측정(위임 필요) — 4 arm(SIG_ON/SIG_OFF/NEU_ON/NEU_OFF) canonical_screen_bt + DiD paired NW t >= 2.0 + 위약 셔플 주입. 데이터 핀·vintage 요구 포함 사전등록 완료 상태",
    "FQ-138e bench vintage 감도(이월) — max_abs_diff 0.00398 이 1개월에 있고 조건부 표본이 28개월로 작아 비중이 크다. 두 vintage 각각 산출해 판정 반전 여부 확인",
    "FQ-138f 국면 희소성의 판정 함의 — 조건부 표본이 28개월뿐이면 DiD 의 검정력이 제한된다. 사전등록 문턱 2.0 이 28개월 표본에서 어느 정도 효과크기를 요구하는지 사전 계산해, 미달 시 '검정력 부족'과 '효과 부재'를 구별해 보고할 준비"),
  consumer_surfaces = c("팩터랭킹", "오버레이", "선별라벨"),
  frontier_update = "FQ-138d 해소(원 측정 = gridx 확인) · 사전등록의 window_hazard 오추론 철회·정정 · 위험 성격 재규정(짧은 패널 아니라 국면 희소성) · FQ-138f 신규(검정력 사전계산)",
  live_trigger = "국면이 현재 ON 이므로 조건부 표본이 매월 1 씩 증가한다 — 28 -> 30 대가 되면 검정력이 개선되며, 사전등록이 이미 고정돼 있어 추가분은 clean OOS 다",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/probe_panelx.R",
                    "stage_artifacts/fq141_precheck_20260808/probe_baserate_window.R",
                    "stage_artifacts/fq141_precheck_20260808/fq138_preregistration.json")
)
cat("[close_fq138d] RC_OK\n")
