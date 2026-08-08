# close_np157c2a.R — NP-157c2a 라운드 계약 마감 (한글 → 파일 source, Rscript -e 금지)
source("02_Infrastructure/contracts/close_round.R")

r <- close_round(
  round_id = "NP157C2A_20260808_ROLLING_CONCENTRATION_RECLASSIFY",
  verdict_type = "capability_established",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "★직전 라운드(NP-157c2)에 사전등록한 부활 조건이 발화해 자기 판정을 철회·재분류한 라운드다.",
    "18개월 롤링 창 150개 실측: 최신 창(2025-01~2026-06)의 d_ann 0.4895 = 99.3 백분위(극단), eff_n 6.85 = 1.3 백분위(극단 집중),",
    "그러나 top2_share 0.950 = 39.0 백분위로 **평범**하다. d>0 창 82개의 top2_share 중앙값이 1.186 이고(음수 기여자 때문에 1 초과 정상), 삼성+하이닉스가 상위-2 인 창이 150 중 50(33.3%)이다.",
    "★철회: '2025+ 는 두 종목이 만든 사건이라 특이하다' — 상위-2 가 d 를 거의 다 설명하는 것은 상시 상태다.",
    "★유지·강화: 2025+ 의 특이성은 지배 구조가 아니라 크기다(d_ann 99.3 백분위). 늘 소수가 지배하는데 이번엔 그 소수가 유난히 크게 벌었다.",
    "실질 함의: '메가캡 지배가 사라지길 기다리는' 재측정 전략은 성립하지 않는다. 기전이 상시 켜져 있으므로 기다릴 수 있는 것은 크기의 정상화(d_ann 이 중앙값 0.0085 부근으로 회귀하는가)뿐이다.",
    "지표 정의 차이 정직 표기: 집중도 6.85(절대기여 HHI 전 종목) vs 직전 4.2(양수기여만) — 같은 현상의 두 척도, 모순 아님."),
  next_probes = c(
    "NP-157c2a1 d_ann 백분위 라벨의 배선 전 검정 — 측정 창이 기록된 항목에 고-핸디캡 라벨(예 75 백분위 0.0429 초과)을 붙여보고 라벨 유무로 기각의 성격이 실제 갈리는지 확인. 갈리지 않으면 이 라벨은 장식이며 그 검정이 배선보다 앞서야 한다",
    "NP-157c2b 이월 승격 — 고정 축([0,0.20]·25종목) 안에서 달성 가능한 최대 벤치 추종도. 상시 기전임이 확인됐으므로 피할 수 없는 조건 안에서의 최선을 알아야 하고 우선순위가 올라간다",
    "NP-157c2c 이월 — 상위-2 제거 후 잔여에서 d 가 음수(k=5 -0.0146)라는 것은 소형·중형 tier 에서 전이 벽이 반대 방향일 가능성. 미탐색 면"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "위험모델", "monitoring"),
  frontier_update = "NP-157c2 의 '에피소드' 판정 철회 → 상시 기전 재분류(사전등록 조건 발화) · 특이성은 크기(99.3 백분위)로 재국소화 · NP-157c2a1 신규",
  live_trigger = "측정 창의 d_ann 이 역사 분포 중앙값(0.0085) 부근으로 회귀하면 그 시점 수집분은 고-핸디캡 라벨 없이 소비 가능",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np157c2a_findings.md",
                    "stage_artifacts/fq141_precheck_20260808/np157c2a_rolling.csv",
                    "stage_artifacts/fq141_precheck_20260808/np157c2_findings.md")
)
cat("[close_np157c2a] RC_OK\n")
