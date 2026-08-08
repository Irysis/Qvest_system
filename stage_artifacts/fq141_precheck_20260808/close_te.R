source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NPC1_20260808_TE_FLOOR_FROM_UNHOLDABLE_TIER",
  verdict_type = "capability_established", layer = "8_위험모델감시",
  mechanism_diagnosis = paste(
    "'담을 수 없는 tier 가 구조적 TE 하한을 만든다' 는 가정을 실측으로 정량화했다 — 하한은 생각보다 작다.",
    "전 구간 439m: MEGA 10종을 제약 cap 0.20 까지 담으면 평균 미보유비중 0.7% · TE 하한 1.02%/yr. 전혀 안 담으면 46.1% · 16.28%/yr.",
    "2025+ 메가캡 집중기: cap 담기 3.0% · TE 하한 4.63%/yr vs 전혀 안 담기 48.5% · 38.17%/yr.",
    "⇒ 제약 [0,0.20] 안에서 MEGA 를 담기만 하면 미보유가 유발하는 TE 는 대부분 해소된다. '벤치에 담을 수 없는 tier 가 있어 TE 예산이 달성 불가' 라는 우려는 실측상 성립하지 않는다.",
    "★단 이는 TE(추적오차) 축 진단이며 초과수익(알파) 축과 별개다 — 담는 것이 TE 를 줄여도 알파를 만들지는 않는다(NP-156b1b 에서 cap-tilt 증분이 신호와 무관함을 이미 확인)."),
  next_probes = c(
    "NP-c1a TE 하한과 실제 TE 의 간극 — 현행 book 의 실현 TE 가 이 하한 대비 어디에 있는지. 하한 근방이면 TE 는 구조적 한계이고, 크게 위면 구성 선택이 만든 여유분이다",
    "NP-c1b 미보유 tier 의 알파-TE 분리 — MEGA 를 담으면 TE 는 줄지만 알파는 안 늘어난다(실측). 그렇다면 TE 예산을 알파 없이 소진하는 셈이므로, TE 목표 자체가 올바른 제약인지 재검토 대상"),
  consumer_surfaces = c("위험모델", "비중방법", "monitoring"),
  frontier_update = "TE 하한 정량화(cap 담기 시 1.02%/yr, 2025+ 4.63%/yr) — '담을 수 없어 TE 예산 불가' 우려 기각 · NP-c1a/b 신규",
  live_trigger = "현행 book 실현 TE 가 하한 근방으로 수렴하면 구성 여유가 없다는 신호",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_c1_te_floor.R"))
cat("[close_te] RC_OK\n")
