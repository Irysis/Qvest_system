source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NP157C2C_20260808_TIER_INTERNAL_WALL_REVERSES",
  verdict_type = "capability_established",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "cap-tier 내부에서 전이 벽의 방향이 뒤집힌다(439개월 tier-내부 d_ann): MEGA(상위10) +0.0556 · MID(11~30) -0.0031 · OTHER(나머지 ~169종목) -0.0210.",
    "즉 MEGA 안에서는 시총가중이 이기고 OTHER 안에서는 동일가중이 이긴다. MID 는 사실상 0.",
    "2025+ 분해: MEGA +0.0394 -> +0.4121 · MID -0.0029 -> -0.0087 · OTHER -0.0245 -> +0.0570 ⇒ 2025+ 극단은 거의 전적으로 MEGA 내부 사건이다.",
    "OTHER 5년 블록: 1990s -0.0662 / 1995s -0.0183 / 2000s +0.0038 / 2005s +0.0079 / 2010s -0.1000 / 2015s -0.0176 / 2020s +0.0191 / 2025s +0.0570 — 대체로 음수.",
    "★전이 벽의 정확한 재규정: 이 저장소 전략은 OTHER tier 에 살고(A_REL_TOP MEGA 2.2% / OTHER 93.8%) 그 tier 안에서는 EW 가 구조적으로 유리하다. 불리함은 EW 라서가 아니라 벤치가 포트폴리오가 담지 않는 tier 를 포함하고 그 tier 가 극단적으로 뛰었기 때문이다.",
    "★이는 고정 축이다(KOSPI200 TR = cap-weighted = MEGA 지배). 고칠 대상이 아니라 조건이며, 제약-안 유일 대응은 MEGA 노출을 담는 것 = NP-c1 의 cap-tilt 이고 그것은 paired 1.307 에서 멈췄다. 전체 그림이 일관된다."),
  next_probes = c(
    "NP-c2c1 OTHER tier 내부 벤치 기준 재측정 — 기존 기각 후보 일부를 OTHER-내부 EW 벤치로 재채점하면 신호 자체의 실력이 tier-beta 없이 드러난다. 단 이것은 진단 basis 이지 자본 게이트가 아니다(HARD 판정은 cap-w 불변, INV-7)",
    "NP-c2c2 MEGA 노출의 최소 필요량 — OTHER 순수 포트에 MEGA 를 몇 % 담아야 tier-beta 노출이 중립화되는지. NP-c1 cap-tilt 가 paired 1.307 에서 멈춘 것이 이 양의 상한을 시사하는지 확인",
    "NP-c2c3 MID tier 의 d≈0 활용 — MID 는 439개월 -0.0031 로 tier-beta 가 거의 없다. MID 집중 구성이 벤치-미스매치를 구조적으로 피하는 경로인지(단 WT-006 R4 의 mid_universe 7변형이 cap-w<1.277 로 이미 미달 — 그 실패가 tier-beta 때문인지 신호 때문인지 분리 필요)"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "위험모델", "타모드이식"),
  frontier_update = "tier 내부 벽 방향 반전 확립(MEGA +0.0556 / OTHER -0.0210) · 2025+ 극단은 MEGA 내부 사건 · 전이 벽 재규정(EW 문제 아니라 미보유 tier 노출) · NP-c2c1/2/3 신규",
  live_trigger = "OTHER tier 내부 d 가 2025s 처럼 양수로 지속되면 소형·중형 구성의 구조적 우위가 사라지는 것이므로 재확인 필요",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np157c2c_tier_d.csv",
                    "stage_artifacts/fq141_precheck_20260808/np157c2a1_d_extended.csv")
)
cat("[close_np157c2c] RC_OK\n")
