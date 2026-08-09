## p9 — 라운드 종료 계약
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "LADDER_SWEEP_20260809",
  verdict_type = "capability_established",
  layer = "measurement",
  mechanism_diagnosis = paste0(
    "PORT_t 사다리 3단(cap-w → EW-유니버스 basis)의 정체를 분해했다. 두 채널의 합성이다: ",
    "①mean 채널 = 재료 무관 상수(8재료 sd 0.000019 · 8/8 동일부호 · d −0.48%/yr). 부호는 창 길이 의존이며 ",
    "08-08 조회표(167m +0.024 / 269m −0.015)의 독립 재현. ",
    "②se 채널 = se_EW/se_capw 0.729 → t 를 부호 무관 x1.371 배율. EW 벤치가 포트(EW top-N)와 구성이 닮아 ",
    "active 변동이 27% 작아지기 때문. ★지문 = 알파가 음수인 5재료가 EW 에서 더 음수(배율기는 부호를 안 가림). ",
    "★항등 = gross 2.363 x1.406 −0.268 = 2.946 = 실측(3자리 일치). ",
    "⇒ 내가 오늘 쓴 '두 채널 제거 시 2.966>2.95 첫 문턱 통과' 는 성립하지 않는다 — 자를 바꾼 것이다. ",
    "정정 회계: 진짜 채널은 비용뿐이고 갭 0.761 중 23%, 나머지 77% 는 신호 부족. ",
    "★★이 오독은 08-08 에 이미 잡히고 금지 규범·메모리 카드까지 있었는데 재발했다 — 규범으로는 안 막혀 ",
    "계약 필드(diag_ew_universe$basis_channels)로 못박고 위반 주입 검사를 붙였다."),
  next_probes = c(
    "FQ-196 ①: dual-basis 를 인용하는 지점(08-08 감사가 목록화)이 basis_channels 를 실제로 읽는지 배선 실측 — '표준은 있는데 소비자 0' 계통 재발 방지. 미배선이면 인용부에 배율 병기 의무화",
    "FQ-196 ②: diag_cap_tier(MEGA/MID 분해)도 basis 를 바꾸므로 동일 배율 오독이 가능하다. 같은 분해를 붙일지 실측으로 판단",
    "FQ-194 선행: 계약 슬리브의 오버레이 라우팅(H3) 실행에 필요한 production PG2 base 확보 가능 여부 확인 — FQ-165 가 같은 벽에서 멈췄다",
    "갭 회계의 77%(신호 부족)를 재료별로 분해 — 비용 23% 는 고정 축이므로 남은 레버는 신호 쪽뿐이다"),
  consumer_surfaces = c(
    "canonical_screen_bt() diag 산출 (basis_channels 발행)",
    "alpha screening 기각 전 재분류 판정",
    "병목지도 갭 귀속 (⑨자본 행: '벤치가 가림' → '신호 미달이 맞음')",
    "FQ wall_check 인용부",
    "challenge_note 자기적대검증"),
  frontier_update = "FQ-196 신규 등재 · FQ-191/M26 라운드 원장 정정 · 병목지도 v56",
  live_trigger = paste0(
    "판정 basis 를 EW 로 옮기자는 제안이 다시 나오면 이 라운드의 배율 실측(se비율 0.729 · x1.371)과 ",
    "음수-재료 지문을 먼저 제시할 것. 또한 basis_channels 가 dominant_channel='se_shrink' 를 보고하는 인용은 ",
    "자본 자격 주장에 쓸 수 없다."),
  evidence_refs = c(
    "stage_artifacts/ladder_sweep/p0_sweep.R", "stage_artifacts/ladder_sweep/p1_decompose.R",
    "stage_artifacts/ladder_sweep/p2_contract_recheck.R", "stage_artifacts/ladder_sweep/decompose.csv",
    "02_Infrastructure/contracts/canonical_screen_bt.R",
    "08_Tests/contract_regression/test_basis_channels.R",
    "stage_artifacts/FQ191/validation.json"))
cat(sprintf("[p9] close_round: %s\n", if (is.list(r)) "OK" else as.character(r)))
