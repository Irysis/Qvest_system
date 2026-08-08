source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "LABEL-LANE-D3E3-20260808",
  verdict_type = "capability_established",
  mechanism_diagnosis = "overlay 분해에서 평균노출 일치 상수 arm 을 통제로 두자 MDD 개선 17.47%pt 중 타이밍이 83%(14.45%pt)이고 노출축소는 17% 뿐임이 확정됐다. 게다가 타이밍은 CAGR 을 4.10%pt 더 벌면서 MDD 를 낮춘다(Calmar 1.096→1.953) — overlay 는 레버리지 다이얼이 아니라 진짜 타이밍 레버. 이어 그 타이밍의 정체를 조건화 축 대조로 추적한 결과, 내가 D3 에서 'R05_z 포트-조건부 신호의 주효과'로 읽었던 −5.75%pt 는 실제로는 라벨 × z 상호작용이었다: 4팩터 × 2축 8 arm 전부 단독 트리거로는 dSR 음수이고, 최선인 R05[보유종목]도 −0.068. 다만 포트-조건부가 시장전체보다 4/4 일관되게 우월(평균 dSR −0.120 vs −0.153). 확립된 능력 = '라벨이 언제를 정하고 포트-조건부 팩터 z 가 얼마나를 정하는 상호작용 구조'이며, 어느 쪽도 단독으로 방어를 만들지 못한다.",
  next_probes = c(
    "I1: 상호작용 구조를 명시적 설계 변수로 승격 — 현 매핑은 (regime, z<q20) 2×2 이산 표. 라벨 발화월 내부에서 z 를 연속 매핑(β = f(z))하거나 다중 문턱으로 바꿨을 때 MDD/Calmar 가 개선되는지 측정. sweep 이므로 DSR + holdout 사전등록 필수. D3 가 이 축이 MDD 레버임을 확정했으므로 목표(MDD<25%) 관점 최우선.",
    "I2: 수정자 팩터 확장 — 포트-조건부 축의 4/4 일관 우월을 근거로, 라벨 발화월 내부 수정자로 쓸 팩터를 R05 외로 넓혀 상호작용 항으로 평가(단독 스크리닝 아님, 이번 라운드가 단독 평가의 무력함을 실측). 후보는 factor DB 에 이미 있어 즉시 측정 가능.",
    "I3: 라벨 발화 자체의 개선은 별도 축으로 보류 — 9종 시장상태 신호가 분류·경제 이중으로 negative 이고 사각지대는 −5~−9% 중첩 구간이라 순진 문턱으로 도달 불가. 비-return 원천(옵션 IV·대차/공매도) census 가 이 축의 유일한 실질 경로이며 I1/I2 보다 후순위(데이터 확보 선행).",
    "I4: 횡단면 분산 = 기회 신호(발화월 +8.08%, n=13)의 소비면 — de-risk 억제 게이트로 상호작용 구조에 편입 가능한지. 라벨이 발화해도 분산이 높으면 축소를 보류하는 형태."
  ),
  consumer_surfaces = c(
    "위험모델/베타예산: β 매핑을 이산 2×2 표에서 연속 상호작용 함수로 재설계 — MDD 레버의 실증된 소재지",
    "팩터랭킹: 포트-조건부 집계(보유종목 평균 z)를 팩터 평가의 보조 축으로 등재 — 시장 집계 대비 4/4 우월 실측",
    "monitoring 신호: 보유종목 R05_z 를 상시 관측치로 노출(현재 forward 생성기 내부 계산으로만 존재)",
    "타 모드 이식: FR/RAMP 의 regime-조건부 배분도 동일 상호작용 구조로 재검토 대상"
  ),
  frontier_update = "FQ 등재 예정: I1(β 연속 매핑 sweep·MDD 목표 최우선) · I2(수정자 팩터 확장) · I4(분산 억제 게이트). I3 는 데이터 census 선행 조건부.",
  live_trigger = "단독 신호 계열 재도전 조건 (분류·경제 이중 negative, 경로-scoped): ① 비-return 원천이 확보돼 −5~−9% 중첩 구간에 분리력이 생기면 라벨 발화 축 재개 ② 다변량 학습형이 개별 최대를 유의하게 넘으면 단일문턱 표현력 문제로 재분류 ③ 포트-조건부 축의 4/4 우월이 팩터를 넓혀도 유지되면(I2) 축 자체를 주효과로 재평가. 횡단면 분산은 negative 아님 — 방향 반대의 미측정 기회(I4).",
  layer = "국면 라벨 × 포트-조건부 수정자 — 방어 계층(MDD 레버 확정)",
  evidence_refs = c("stage_artifacts/tilt_realign_20260808/p10_overlay_decomposition.csv",
                    "stage_artifacts/tilt_realign_20260808/p11_conditioning_axis.csv",
                    "memory: project-regime-label-response-depth-20260808")
)
