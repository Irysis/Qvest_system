---
name: qvest-worktask
description: QEPM v8.1 WorkTask lifecycle 절차 + 6-agent orchestration. /qvest 진입 후 신규 가설부터 admit까지 전 단계.
---

# Qvest WorkTask Skill

**Active SOT**: `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md`

## 1. WorkTask Lifecycle

### state machine

```
SPEC_APPROVED
  → ALPHA_DONE
  → RISK_DONE
  → OPTIMIZER_DONE
  → FORGE_DONE
  → JUDGE_PASSED | JUDGE_FAILED
  → GOVERNOR_ADMITTED | GOVERNOR_REJECTED
  → COMPLETED | ABORTED
```

임의 phase jump는 waiver 없이 불가 (v8.1 state machine enforced).

### wt_type 4종 (Charter v1.7 §10 Role Card)

| wt_type | 용도 | own cert | inherit |
|---|---|---|---|
| `discovery` | 신규 alpha 탐색 | alpha + sr + sched + forge_pkg | concord (global) |
| `deployment` | 검증 alpha 직접 편성 | sr + sched + forge_pkg + concord | alpha (from discovery) |
| `sizing_only` | weight 변경만 | concord | alpha + sr + sched + forge_pkg |
| `hyperparameter_sweep` | tuning | concord | alpha + sr + sched + forge_pkg |

## 2. WT 생성

### ★ 생성 전 — 가설 중복실험 인덱스 조회 의무 (2026-07-04 G-mode-wiring, alpha-search Step 0 문안 이식)

가설 intake **전에** 반드시 `06_Registry/hypothesis_index.json`을 조회한다 ("이미 시도됨" 판정을 LLM 메모리에 맡기지 말 것 — 687회+ 실험 인덱싱됨):

```bash
# lookup 전 build 1회 권장 (stale 방지 — 최근 실험이 미인덱싱일 수 있음)
Rscript 02_Infrastructure/tools/hypothesis_index.R build
Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <keyword> [keyword...]
# 예: Rscript 02_Infrastructure/tools/hypothesis_index.R lookup momentum
```

- **넓게 조회 후 좁힐 것**: 단일 패밀리어(`momentum`·`value`·`quality`)로 먼저 조회한다. 다어(`residual momentum`)는 AND 매칭이라 결과가 과도하게 좁아져 진짜 히트를 놓친다 — 동의어 자동확장(F1: 한영/축약/동의어)이 이미 걸려 있으니 단일어로 넓게 잡고, 필요하면 결과 안에서 좁힌다.
- **동일 서명(`family|signal_group|universe|structure`) 기존 시도가 있으면**: 기존 결과(verdict·grade·key_metrics·source_paths)를 인용하고, **이번 가설의 차별점을 명시해야만 진행 가능**. 차별점 없는 동일 재실험 금지 (단순 재확인은 도훈 지시 시만).
- **verdict가 FAIL/KILL인 히트는 차별점 명시 없인 진행 금지** — 재도전 시 INV-7 재도전 사유(무엇이 달라져 결과가 달라질 것으로 보는지)를 WT `hypothesis_description`에 기록.
- hit 없으면 그대로 진행. 조회 사실(키워드 + hit/miss)을 결과 보고에 1줄 기록.
- 인덱스가 stale하면(새 실험 다수 후) `Rscript 02_Infrastructure/tools/hypothesis_index.R build`로 재빌드.
- 서명 정규화 규칙·원천 3계층(stage_artifacts manifest/hurdle + lcode_corpus + module_catalog)은 `02_Infrastructure/tools/hypothesis_index.R` 헤더 참조.

### ★ Novelty Triage (v8.3.1, 2026-07-10 — WT-D20260710_003 사후 배선. lookup 통과 후 추가 판정)

lookup(중복)·DISTILLED_NEG(경로)는 **검색**이라 "기존 negative들의 기계적 재조합"을 못 거른다 (실사고: 5축 joint packaging이 경로-신규라 통과 → 26 trial 후 4렌즈 패널·실측이 동시 기각 — 기각 근거는 전부 기존 지식이었음, L-AR-20260710_135913). WT 생성 전 `hypothesis_description`에 다음 의무 기재:

1. **신규성 축 선언**: 이 가설이 바꾸는 것이 {**재료**(데이터/신호원), **기전**(경제 메커니즘), **측정 그리드/계기**(시간구조·벤치 basis·paired 구조 등)} 중 무엇인지 명시.
2. **셋 다 기존과 동일(=순수 재조합/packaging)이면**: 착수 전 **기대 상방 선계산 의무** — 조합의 이론 상한(예: translation loss 회수분)이 게이트 요구 수준(전기간 PORT_t 2.95 ≈ 연IR 0.63)에 닿는지. 못 닿으면 **도훈 confirm 없인 착수 금지** (금지가 아니라 명시적 승인으로 격상 — AX-000 정합).
3. **sweep형이면 null max-t 대역 사전 등재**: 계획 n_trials 기준 null 하 max-t 기대범위를 스펙에 기록, 그 대역 내 결과 = 비정보적 near-miss (성공 주장 금지).

원칙: 본 triage는 INV-7(negative는 경로-scoped, 방향 일반화 금지)과 충돌하지 않는다 — "재조합 금지"가 아니라 "신규성 선언 + 상한 선계산"이다.

### ★ 3단 게이트 (v8.3.1 리서치 레벨 v2, 2026-07-11 — WT 생성 전 순서 고정)

1. **hypothesis_index lookup** (위 절차 — 중복·기실패 대조)
2. **frontier 큐 확인**: `06_Registry/alpha_frontier_queue.json` — 착수 대상 엔트리의 owner/status 갱신 의무, `dohoon_decision`/`dohoon_data_work` 항목은 세션 임의 착수 금지 (consume_rule 준수)
3. **EV-지도 셀 판정**: `06_Registry/research_ev_map.json` 죽은 계급(D1~D7+4, 예산 0)에 해당하면 novelty triage 2항의 **도훈 confirm 없인 착수 금지**. 셀 판정 결과(살아있는 lane / 죽은 계급 / virgin)를 `hypothesis_description`에 1줄 기록.

```r
source("02_Infrastructure/worktask/worktask_manager.R")
wt_id <- wt_create(
  hypothesis_title = "{가설 제목}" or NULL,
  theme = "{theme}",  # alpha agent 자율 발굴 시 hypothesis_title=NULL + theme
  hypothesis_description = "{동기 + 접근}",
  wt_type = "discovery",  # or "deployment" / "sizing_only" / "hyperparameter_sweep"
  discovery_of = NULL,  # deployment 시 parent STR
  universe = "KOSPI200_KOSDAQ150_intersection",
  benchmark = "KOSPI200_total_return"
)
```

자동 주입:
- `task_id = WT-{D|P|S|H}YYYYMMDD_NNN`
- `hard_constraints.max_names = 25` (deployment) / NULL (discovery breadth)
- `weight_bounds = [0, 0.20]` (deployment)
- `liquidity_min = 2e8` (deployment) / 1e7 (discovery hard mandate floor)
- `cost_model = v2.4_kr_retail_15bps`
- `data_lag_rules` 4종 (fundamental / price / investor_flow / macro)
- `status = SPEC_APPROVED`

## 3. 6-Agent Pipeline (v8.1 active path)

### Step 1: alpha-research

```
Agent(subagent_type="alpha-research", prompt="WT{id} Alpha Research...")
  → 자율 hypothesis discovery + factor specs
  → AST v1.1 산출 계약 (2026-07-25): alpha_package에 spec_version="ast_v1.1" + 3층(hypothesis{mechanism 주체·마찰·경로 + falsification + regime_scope} / factors[] AST(𝒪+escape 리프 4종) / combination_rule enum) + verdict(designed|economic_void|blocked_by_capability) + self_pit_check 의무 — schema.json conditional + 프롬프트 <ast_spec_v1_1> 절, SOT qvest_ast_v1_1_sot.md §1
  → alpha_package_draft.json (Write tool, _draft suffix)
  → Self-Adversarial Challenge (v8.2 — Codex Round 제거, Opus 4.8 자체 적대검증)
  → challenge_note.md (self-adversarial record: 5 ACCEPT + REBUTTAL 학술/L-code/정량 3축)
  → alpha_package.json (no _draft, PreToolUse hook 통과)
```

### Step 2: risk-research

(Hook 선행 검증 — alpha_package.json 존재 확인)

```
Agent(subagent_type="risk-research", prompt="WT{id} Risk Research...")
  → Σ + tail + stress + crowding + style 5축 자율 분석
  → risk_package_draft.json → self-adversarial challenge → risk_package.json
  → covariance.parquet
```

### Step 3: optimizer-research

```
Agent(subagent_type="optimizer-research", prompt="WT{id} Optimizer Research...")
  → 10+ 방법론 비교 (MVO/HRP/CVaR/ERC/BL/Genetic/Ensemble/etc)
  → optimization_package_draft.json → self-adversarial challenge → optimization_package.json
  → weights.csv (Date × Ticker × weight)
```

### Step 4: forge

```
Agent(subagent_type="forge", prompt="WT{id} Integrate 3-agent packages → backtest")
  → run_all.R + backtest 통합 (Pure function 강제)
  → forge_package_draft.json → self-adversarial challenge → forge_package.json
  → AX-008 Verification Triangulation: Forge + Self-Adversarial + Architect 2/3 PASS 의무
```

### Step 5: judge

```
Agent(subagent_type="judge", prompt="WT{id} S6 cascade Gate 0~18")
  → judge_verdict_draft.json → self-adversarial challenge → judge_verdict.json
  → L-code 발행(의무): emit_qepm_lcode(source="judge_gate") → judge_verdict.json에 l_code_path 기록
  → JUDGE_PASSED / JUDGE_FAILED
```

**judge→governor 전이 체크**: `judge_verdict.json`에 `l_code_path` 존재 (L-code 발행 의무 — `.claude/agents/judge.md` "L-code 발행" 절). 부재 시 전이 보류·judge에 발행 요청.

### Step 6: governor

```
Agent(subagent_type="governor", prompt="WT{id} PG0~PG3 admission")
  → governor_admission_draft.json → self-adversarial challenge → governor_admission.json
  → GOVERNOR_ADMITTED / GOVERNOR_REJECTED
  → book_state.json admit (concord cert auto-issue)
```

## 4. Hard Constraints (Hook 자동 검증)

| 제약 | 값 | 강제 |
|---|---|---|
| max_names | 25 hard | worktask_constraint_enforcer |
| Long-only | weights ≥ 0 | same |
| Weight bounds | [0, 0.20] | same |
| Σw | = 1 (absolute) | same |
| Universe | KOSPI200 ∪ KOSDAQ150 | worktask_spec_validator |
| Liquidity | 20d TV ≥ 2e8 KRW | same + Alpha filter |
| Transaction cost | 15bps one-way | cost_model_version 고정 |
| PIT C1~C15 | 전체 | `.claude/rules/pit.md` |
| 3-agent 역할 경계 | Alpha/Risk/Opt 침범 금지 | agent_role_guard |
| WT 순서 | Alpha→Risk→Optimizer | worktask_sequence_enforcer |

## 5. Common Charter 8원칙

1. Point-in-time Only
2. Research Process First (QEPM 5단계)
3. Factor Family vs Proxy 구분
4. 논문은 출발점, 승인서 아님
5. Data Mining 방지
6. Dynamic Smart Alpha
7. 비용 · 용량 · 군집위험 mandatory
8. **No Silent Override** (challenge_note / infeasibility_report 의무)

전체: `02_Infrastructure/worktask/common_charter.md` v1.7

## 6. Q-Lead 역할 경계 (Level 0)

- ✅ 진단, 지시, 모니터링, 결과 수집, 텔레그램 보고
- ✅ WT 생성 + 6 agent spawn orchestration
- ❌ 직접 Rscript 실행 / 백테 / factor_engine 수정 → Forge / Alpha agent 위임
- ❌ weight 결정 / 공분산 계산 → Optimizer / Risk agent 위임
- ❌ Alpha/Risk/Opt 경계 침범 (Hook L3 자동 차단)

## 7. Multi-Agent 실행 (v8.1+ — Agent tool spawn 단일 패턴)

v53 TeamCreate/teammate 패턴은 **폐지됨** (v8.1 Agent tool spawn 대체 — TeammateIdle/TaskCompleted hook 등록 해제 2026-06-10, 스크립트 FS retain). 6-agent(alpha/risk/optimizer/forge/judge/governor)는 Agent tool로 개별 spawn, 추가 역할(Architect / Blender / Execution / Monitoring)은 ondemand spawn. (v8.2 — Codex Critic 역할 제거, 각 agent가 세션 모델(현행 Fable 5) self-adversarial challenge 내장. 2026-07-24 모델 핀 제거 — 전 에이전트 세션 모델 상속.)

## 8. WT 진행 상태 확인

```r
source("02_Infrastructure/worktask/worktask_manager.R")
wt_list(include_completed = FALSE)
wt_status("WT-D20260501_NNN")
wt_check_graduation("WT-D20260501_NNN")  # cert 발급 상태 검사
```

## 9. WT 간 병렬 / 내부 순차

- **WT 간 병렬 허용** (WT001 + WT002 동시 진행 가능)
- **WT 내부 순차 강제** (`worktask_sequence_enforcer.sh` Hook)

## 지식 절차 (QEPM 모드 — Axiom 엔진 배선, 2026-07-04)

- **조회 의무 (consume)**: WT 생성 전 hypothesis_index lookup (§2 상단 블록). FAIL/KILL 히트 시 차별점 없인 진행 금지 + INV-7 재도전 사유 기록.
- **emit 시점 (1지점)**: judge가 essence Grade 확정 직후 `emit_qepm_lcode(source="judge_gate", metric_type="backtested")` — 상세·필수필드(mechanism 1줄 + port_t/oos_retention/sharpe/mdd + falsification 실기록)는 `.claude/agents/judge.md` "L-code 발행" 절. 산출 경로 = `judge_verdict.json::l_code_path`.
- **governor DEFER/REJECT**: 동일 함수 `source="governor_admission"` 재사용 (코드 0줄).
- 필수필드 결측(mechanism/metric_type/oos/falsification)이 승격 축 도달불가의 주원인 — emit 시점에 채운다 (문턱 완화 아님).

## 참조

- `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md` (active SOT)
- `02_Infrastructure/worktask/worktask_manager.R` (wt_create / wt_advance / wt_check_graduation)
- `02_Infrastructure/worktask/common_charter.md` v1.7
- `02_Infrastructure/worktask/red_flag_rules.md`
- `02_Infrastructure/worktask/role_card_cert_inheritance.R`
- `.claude/rules/pit.md` / `02_Infrastructure/docs/rules/harness.md` (codex-round.md = DEPRECATED 스텁, v8.2 self-adversarial 전환)
