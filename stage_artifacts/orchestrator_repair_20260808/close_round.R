source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "CHIP-task_29584825-orchestrator-repair",
  verdict_type = "capability_established",
  mechanism_diagnosis = "일간 forward-weights orchestrator 가 5주 이상 죽어 있던 원인은 PROJECT_ROOT 해석이었다 — normalizePath(dirname(ofile)+'../..') 가 daily_refresh.sh 의 `cd $INFRA` + 상대 source 조합에서 프로젝트 밖(사용자 홈)으로 나갔고, 그래서 3전략 전부 MISSING_WRAPPER 를 반환하며 빈 manifest 를 홈에 적재했다. 은폐 기전의 핵심은 tryCatch 가 삼킨 게 아니라 **정상 종료 + 빈 결과**여서 애초에 발화 지점이 없었다는 것이다(오늘 '빈 결과 = 합격' 계통의 네 번째 사례). 수리: 루트 해석을 CPD → QM_ROOT → fallback 순으로 바꾸고 marker(qvest_hook_router.py) 보유까지 검증해 경로 존재를 루트 정체성으로 착각하지 않게 했으며, 요청 전략이 전부 미산출이면 stop() 하도록 fail-closed 를 승격했다. 위반 주입 2종(전 전략 미산출 / 루트 marker 부재)이 모두 exit 1 로 발화함을 확인했고, 활성화 안전 게이트로 되살아난 산출이 무엇을 덮어쓰는지 먼저 확인해 신규 20260801_* 3파일만 생성되고 기존 파일 mtime 은 전부 보존됨을 실측했다. 되살아난 경로가 같은 세션에서 정렬한 정본 가중(rank-tilt + tophi + CRISIS ub 0.10, w_prev=carrier)으로 산출되는 것도 확인했다.",
  next_probes = c(
    "O1: daily_refresh 실경로 E2E 확인 — 내 검증은 orchestrate_forward_weights 를 직접 호출한 것이다. daily_refresh.sh 가 실제로 도는 조건(cd $INFRA + run_r 래퍼 + QVEST_REFRESH_TG 가드)에서도 루트가 바르게 잡히는지 1회 실행으로 확인해야 한다. 내 호출 방식과 실경로가 다르면 수리가 반쪽이다.",
    "O2: 같은 루트-해석 패턴의 동종 census — `normalizePath(dirname(...ofile...))` 계열이 다른 스크립트에도 있는지 스캔. r-portability.md 금칙 ④(resolver 는 CPD 우선)의 위반 사례가 이 하나뿐일 가능성은 낮다. 발견 시 같은 marker-검증 형태로 통일.",
    "O3: '정상 종료 + 빈 결과' 탐지 일반화 — 이번 은폐는 tryCatch 로 못 잡는 종류였다. 산출물이 있어야 할 배관에서 **빈 산출을 정상으로 기록하는** 다른 지점을 찾는 검사(예: manifest 크기·상태 필드 분포 감시)를 monitoring 축으로 추가."
  ),
  consumer_surfaces = c(
    "일간 파이프라인: forward-weights 산출이 5주 만에 복구 — production_weights 에 20260801_* 신규 생성, 정본 가중 적용 확인",
    "monitoring: manifest 상태 필드(MISSING_WRAPPER 비율)를 관측 축으로 — 빈 산출이 다시 쌓이면 즉시 드러나게",
    "타 배관 이식: marker-검증 루트 해석 패턴을 다른 orchestrator/러너에 확산(O2)",
    "증거 보존: outage_evidence/ 에 사망 기간 manifest 4건 + README(유효 manifest 아님 명시)"
  ),
  frontier_update = "칩 task_29584825 완료. 잔여 칩: task_972fe292(β_R05 z 원천 — fail-closed 완료, 통일 방향은 도훈 판단) · task_deabaca2(C15 우회 — 착수 예정).",
  live_trigger = "재발/재검토 조건 (경로-scoped): ① O1 에서 daily_refresh 실경로 루트가 다르게 잡히면 수리가 미완이므로 즉시 재개 ② manifest 에 MISSING_WRAPPER 가 다시 나타나면(monitoring 축) 배관 재점검 ③ 되살아난 일간 산출이 월간 배포본과 어긋나면(둘 다 정본 가중이어야 함) 규약 정합 재검증 ④ 홈 디렉터리에 manifest 가 다시 생기면 루트 해석이 어딘가에서 되돌아간 것.",
  layer = "배관/관측 — 일간 산출 경로 (수리 완료, 검증 통과)",
  evidence_refs = c("02_Infrastructure/portfolio/forward_weights_orchestrator.R",
                    "stage_artifacts/orchestrator_repair_20260808/outage_evidence/",
                    "memory: project-forward-tilt-convention-divergence-20260808")
)
