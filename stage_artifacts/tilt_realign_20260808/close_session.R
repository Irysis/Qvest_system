source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "SESSION-20260808-tilt-chip-and-lanes",
  verdict_type = "capability_established",
  mechanism_diagnosis = "칩 task_fea61227(실배포 가중 규약 불일치) ①~③ 을 실측 완결하고, 그 과정에서 열린 두 리서치 lane(overlay 방어층·alpha 생성층)을 각각 등록 probe 소진까지 진행했다. 확립된 것: ①실배포 forward 생성기 4/4 슬롯이 admit 정본과 다른 가중 규약을 쓰며 월 24~42% 괴리, overlay 결합 시 정본 MDD 23.28%(제약 충족) vs 실배포 29.02%(위반)로 갈린다 ②MDD 레버는 β_R05 단독이고 m4 는 한계기여 0 — 제거하면 MDD 여유를 쓰지 않고 CAGR +1.69%pt·Calmar 2.026 ③위기월 사전식별은 9종 신호가 분류·경제 이중 채점에서 전건 실패하며 그 이유는 신호 선택이 아니라 -5~-9% 구간에서 위기월과 정상월이 겹치는 표적 난이도 ④계약 알파의 후속 수급은 외국인 단독이고 국면 의존을 설명하지 않는다. 방법 측면에서 반복 확인된 것: 통제를 실제로 돌리면 판정이 바뀐다(자기 정정 12회 — 평균노출 일치 arm·재현 게이트 4회·경제적 재채점·강건성 분할·상호작용 검정·정규화 4축), 그리고 착수 전 사전 확인이 라운드를 없앤다(7/7). 남은 항목은 전부 거버넌스 게이트(production 변경·공유 상태 git 조작·칩 착수)라 세션이 단독으로 진행할 수 없다.",
  next_probes = c(
    "S1: ④ 정렬 방향 confirm 후 수리 — 인프라 미러 + production 사본 + generator_pins sha1 을 동시 갱신하고(미러만 고치면 fail-closed abort) parity 게이트를 월간 배선. 검사기는 8/8 양방향 통과 상태로 대기 중이며 어느 규약을 택하든 declared_convention 파라미터로 동작한다.",
    "S2: m4 제거 정식 심사 — carrier_recon 기준 CAGR +1.69%pt·Calmar 2.026(paired p=0.005)이고 모든 대안 probe 소진으로 비교 우위가 확정됐다. forge-authoritative 재측정 + D3 게이트 규칙 하 재현 + book-marginal ΔIR 로 자격 판정.",
    "S3: 새 재료 수급 — 큐의 즉시착수 후보 3건(FQ-093/094/130)이 전부 precheck_negative 로 정리됐으므로, 다음 알파 라운드는 비-return 원천 census(옵션 IV·대차/공매도·DART 이벤트) 선행이 필요하다. 데이터 가용성 확인이 실질 첫 단계(08-02 '큐 등재 != 측정 가능' 교훈).",
    "S4: 미커밋 산출물 처리 — 산출 90여 파일과 큐 갱신 5건(FQ-138/139/093/094/130)이 main 워킹트리에 untracked/modified 로 남아 있다. 백업은 전부 무결 확인. 커밋 위치 결정이 필요하며, 공유 원장 변경이 커밋 없이 다른 lane 에 노출된 상태를 오래 두지 않는 것이 좋다."
  ),
  consumer_surfaces = c(
    "팩터랭킹: 계약 신호 x 외국인 순매수 확인 필터 — 국면 무관·정규화 4축 통제 통과, 즉시 소비 가능한 유일한 확정 조합",
    "위험모델/베타예산: MDD-CAGR 다이얼 위치가 선호 선택임을 명시(현행 23.27% / m4 제거 23.27%+CAGR / flag 완화 0.05 23.85%)",
    "monitoring: forward-vs-replay parity 와 원장-재계산 flag 괴리를 관측 축으로 편입",
    "타 모드 이식: '재구성 전 재현 게이트'와 '착수 전 사전 확인'을 FR/RAMP 라운드 표준 절차로"
  ),
  frontier_update = "큐 갱신 5건 반영 완료(FQ-138 서술 교체·FQ-139 done·FQ-093/094/130 precheck_negative). L-code 2건 적립 후 harvester n=467 promoted=2, knowledge_index 재빌드 완료. 신규 FQ 등재 대기: 비-return 원천 census(S3).",
  live_trigger = "세션 재개 조건: ①도훈이 ④ 정렬 방향을 지시하면 S1 즉시 착수(검사기·수리 설계 준비 완료) ②칩 2건(C15 우회 task_deabaca2 · β_R05 z 동결 task_972fe292) 중 하나라도 시작되면 그 lane 재개 ③비-return 원천 데이터가 확보되면 S3 로 알파 lane 재개. precheck_negative 3건은 각각 등록된 부활 조건(소비면 전환·정의 변경·표본 확대)에서 재도전.",
  layer = "세션 인계 — 칩 실측 완결 + 두 lane 수렴, 잔여는 거버넌스 결정",
  evidence_refs = c("stage_artifacts/tilt_realign_20260808/",
                    "stage_artifacts/fq139_mechanism_falsification/",
                    "memory: project-forward-tilt-convention-divergence-20260808",
                    "memory: project-regime-label-response-depth-20260808",
                    "memory: project-fq139-contract-mechanism-foreign-not-institutional-20260808",
                    "memory: project-worktree-session-writes-to-main-uncommitted-20260808")
)
