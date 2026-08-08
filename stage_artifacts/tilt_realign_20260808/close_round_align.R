source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "CHIP-task_fea61227-ALIGN-EXECUTED",
  verdict_type = "capability_established",
  mechanism_diagnosis = "도훈 승인('정본으로 정렬해') 후 월간 실배포 경로를 정본 가중 규약으로 정렬 완료. 수정 대상은 05_Production 사본이 아니라 핀된 미러 02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R 였다 — 월간 러너 run_nolayer4_monthly.sh [1b] 가 resolve_admitted_slot 을 통해 이 파일을 GEN_SCRIPT 로 실행하기 때문이다. 인라인 z-선형 .tilt/.norm 을 제거하고 strategy_tilt_weights.R 계약 모듈을 source 했으며(재구현 금지 — 재구현 표류가 이 결함의 기전), w_prev 체인을 book_carrier 종점에서 이어받아 공백월을 같은 엔진으로 replay 하고, CRISIS ub 0.10 분기와 정본 선별순서(top-N by score_eff → 유동성 교집합)를 복원했다. 수용 검증: 2026-08 산출이 canonical replay 와 max|dw| 1.8e-16 로 일치(PASS)하고 동일 검사기가 구 배포분은 24.5% 괴리로 여전히 FAIL 시켜 차단 실효가 유지됨을 확인했다. generator_pins.json sha1 을 8af4844b→36c5eb22 로 갱신해(핀 갱신 = 승인 흔적 규약) resolve_admitted_slot 재실행이 통과하는 것까지 확인했다. 오버레이(M4∩AE gate × β_R05)와 저장 포맷은 무변경이며 실측으로 확인했다. 부수: 일간 orchestrator 는 z-선형을 쓰고 있던 게 아니라 PROJECT_ROOT 해석 결함으로 5주 이상 죽어 있었다(3전략 전부 MISSING_WRAPPER, manifest 가 사용자 홈에 적재) — 정상 종료 + 빈 결과라 tryCatch 발화 지점조차 없었다.",
  next_probes = c(
    "A1: 9월 리밸 실측 확인 — 정렬 후 첫 실행(run_pg2_rebalance_full.sh)에서 산출 CSV 가 canonical replay 와 일치하는지 parity 검사기로 확인하고, 전월 대비 실제 비중 변화(턴오버)를 기록. 규약 전환월이라 턴오버가 일시적으로 커질 수 있으므로 비용 실측이 필요하다.",
    "A2: production 2-4 사본 정렬 여부 결정 — 핀 계약상 실행체는 미러라 배포 정합은 이미 확보됐으나, 사본이 미정렬로 남아 있으면 '사본을 읽고 판단하는' 후속 세션이 다시 오해한다. promote_to_production() 경유 반영 또는 사본에 정렬 상태 주석 명시 중 택일.",
    "A3: parity 게이트 월간 배선 — 검사기(8/8 양방향 통과)를 run_nolayer4_monthly.sh [1b] 직후에 걸어 매월 자동 검증. 지금은 수동 실행이라 다음 표류를 못 잡는다. declared_convention 을 canonical 로 고정하고 위반 주입 테스트 포함."
  ),
  consumer_surfaces = c(
    "월간 리밸 실행기: GEN_SCRIPT 경로가 정본 규약 산출 — 9월부터 실배포 비중이 북 기록 체계와 동일 엔진",
    "monitoring: forward-vs-replay parity 를 월간 관측 축으로 편입(A3)",
    "북 성과 기록: 배포-북 규약 일치로 live_book_series 와 실주문이 같은 전략이 됨 — 소급 구간(2026-06~08)은 여전히 z-선형 산물임을 라벨로 유지",
    "타 슬롯(2-1/2-2/2-3): 동일 결함이 남아 있으나 admitted 가 아니므로 자본 영향 없음 — 슬롯 철거/정렬 판단 대기"
  ),
  frontier_update = "칩 task_fea61227 ④ 실행 완료. 신규 칩 등재: task_29584825(일간 orchestrator 경로 사망). 기존 대기 칩 2건(task_deabaca2 C15 우회 · task_972fe292 β_R05 z 동결) 유지.",
  live_trigger = "정렬 재검토 조건 (경로-scoped, 영구 판결 아님): ① 9월 리밸(A1)에서 parity 가 FAIL 하거나 턴오버 비용이 예상을 크게 벗어나면 즉시 재검토 — 전환월 비용은 미측정 축이다 ② m4 제거 심사(S2)가 통과하면 오버레이 구성이 바뀌므로 미러를 다시 손봐야 한다 ③ book_carrier 가 재생성되어 w_prev 체인 시작점이 이동하면 산출이 바뀔 수 있으므로 재검증 ④ z-선형 규약 자체는 폐기가 아니라 보류 — 271m paired 우세(t=-3.607)는 실측이므로, forge-authoritative 재측정 + DSR + book-marginal 을 통과하면 규약 교체를 재심할 수 있다(단 MDD 29.02% 제약 위반 해소가 선결).",
  layer = "구성/가중 — 배포 정합 (실행 완료, 검증 통과)",
  evidence_refs = c("02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R",
                    "02_Infrastructure/ops/generator_pins.json",
                    "stage_artifacts/tilt_realign_20260808/forward_parity_check.R",
                    "memory: project-forward-tilt-convention-divergence-20260808")
)
