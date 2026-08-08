source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "OVERLAY-K2-L2-20260808",
  verdict_type = "capability_established",
  mechanism_diagnosis = "성분 ablation 결과 MDD 레버는 β_R05 단독으로 확정됐다 — β_R05 만으로 현행과 MDD 동일(23.27%)한데 CAGR 은 1.69%pt 높고 Calmar 1.953→2.026, m4(BOCPD)의 MDD 한계 기여는 −0.00%pt 로 수익만 깎는다. 이어 flag 입력 축을 4개 대안 팩터로 넓혀 동일 2×2 매핑 안의 수정자로 평가했으나 전부 'flag 없음'(Calmar 1.667)보다도 못했다(1.601~1.621) — R05 선택은 사후 정당. 매핑 형태(I1 연속화 열위)·입력 팩터(L2)·m4(K2) 세 축 모두 개선 여지가 닫혔고, 남은 자유도는 z vintage 와 문턱 정의 자체다. 그런데 그 정의가 산출물에 기록돼 있지 않고, 내가 factor DB 에서 재계산한 R05 flag 는 원장 flag 에 Calmar 0.11 뒤진다(1.915 vs 2.026) — 즉 미기록 항목이 성과를 실제로 담지하고 있다. 위생 문제로 분류했던 K3 가 성과 담지 항목으로 승격된다.",
  next_probes = c(
    "N1: z vintage·문턱 정의를 산출물에 기록하고 pin — 현재 backtest 가 쓴 확장 문턱의 시점별 값이 어디에도 없다(§7 pin 대상). 기록 없이는 원장 flag 를 재현할 수 없고, 재현 없이는 이 축의 어떤 개선안도 기준 없이 뜬다. L2 가 이 항목이 Calmar 0.11 을 담지함을 실측했으므로 최우선.",
    "N2: m4 제거 후보의 정식 심사 — K2 가 MDD 한계기여 0·CAGR +1.69%pt 를 보였으나 carrier_recon 이고 paired 유의성 미검정이며 현 배포는 D3 게이트로 규칙이 다르다. forge-authoritative 재측정 + D3 게이트 규칙 하 재현 + book-marginal ΔIR 로 자격 판정.",
    "N3: 이 lane 밖으로 — MDD 축은 세 자유도가 닫혔고 남은 하나(N1)는 재현 배관 작업이다. SR 2.5 목표 기준으로 보면 overlay 최선(Calmar 2.026·SR 1.905)에서 목표까지의 갭은 alpha 층에서 와야 한다. 병목 지도를 'overlay 방어층 수렴 → alpha 생성층'으로 갱신하고 다음 라운드는 FQ 큐(비-return 원천)에서 연다."
  ),
  consumer_surfaces = c(
    "위험모델/베타예산: m4 성분의 MDD 무기여를 기록 — D3 게이트 정교화가 무기여 성분 위의 작업일 가능성",
    "monitoring 신호: 원장 flag vs 재계산 flag 괴리(Calmar 0.11)를 관측 축으로 — 재현 불능이 성과 담지 항목임을 상시 노출",
    "선별 라벨: 대안 팩터 4종의 flag 부적합은 이 base 한정 — 다른 전략/유니버스에선 재측정 대상",
    "타 모드 이식: FR/RAMP 의 regime 조건부 배분도 '성분 ablation + 입력 축 대조' 같은 절차로 레버 소재지를 먼저 특정할 것"
  ),
  frontier_update = "FQ 등재 예정: N1(z vintage·문턱 pin — 성과 담지 확인됨) · N2(m4 제거 정식 심사). N3 는 lane 전환 제안이라 도훈 판단 사항.",
  live_trigger = "이 lane 재개 조건 (config-scoped 수렴, 경로-scoped): ① N1 이 완료돼 원장 flag 가 100% 재현되면 매핑·입력 축 재탐색이 기준 위에서 가능해짐 ② 다른 base 전략/유니버스로 옮기면 입력 팩터 열위(L2)와 연속화 열위(I1) 모두 재측정 대상 ③ 비-return 원천이 확보되면 flag 입력 축이 새로 열림(현 4팩터는 전부 factor DB 내 return/회계 파생).",
  layer = "오버레이 방어층 — 세 자유도 수렴, 잔여는 재현 배관(N1)",
  evidence_refs = c("stage_artifacts/tilt_realign_20260808/p18_k2_ablation.csv",
                    "stage_artifacts/tilt_realign_20260808/p19_l2_flag_input.csv",
                    "stage_artifacts/tilt_realign_20260808/p17_i1_beta_redesign.csv",
                    "memory: project-regime-label-response-depth-20260808")
)
