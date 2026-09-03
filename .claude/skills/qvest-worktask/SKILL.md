---
name: qvest-worktask
description: QEPM WorkTask lifecycle 절차 (v10) — alpha→risk→optimizer→forge + 등급 평가까지. Judge 는 Grade A 한정 PIT 전담, governor 폐지(BOOK 승계). wt_type 5종(reinforcement=WT-R 포함).
---

# Qvest WorkTask Skill

**Active SOT**: `CLAUDE.md`(v10 헌법) + `.claude/rules/lean-loop.md` + 본 문서 (구 `qvest_v8_1_sot.md`·`qvest_modes_sot.md` 2종 = 사료)

## 1. WorkTask Lifecycle

### state machine

```
SPEC_APPROVED
  → ALPHA_DONE
  → RISK_DONE
  → OPTIMIZER_DONE
  → FORGE_DONE ──(등급 평가 = QEPM 종점)──→ COMPLETED     ← ★v10: grade < A (강화 대상)
        └─(essence Grade A 일 때만)→ JUDGE_PASSED | JUDGE_FAILED → COMPLETED | ABORTED
```

임의 phase jump는 waiver 없이 불가 (state machine enforced — `judge_conditional_on_grade_A`).
★v10 (2026-08-29): GOVERNOR_* phases 는 legacy WT 호환으로만 존치 — 신규 WT 진입 금지.
QEPM = alpha→risk→optimizer→forge + 등급 평가까지. Judge = PIT 전담(A등급 후에만).
JUDGE_PASSED 후 BOOK 등록은 원장 밖 수동(`register_book_entry` + 도훈 confirm).

### wt_type 5종 (Charter v1.7 §10 + ★v10 reinforcement)

| wt_type | 용도 | own cert (legacy v1.7 — v10 신규 WT 미발급) | inherit (legacy) |
|---|---|---|---|
| `discovery` | 신규 alpha 탐색 | alpha + sr + sched + forge_pkg | concord (global) |
| `deployment` | 검증 alpha 직접 편성 | sr + sched + forge_pkg + concord | alpha (from discovery) |
| `sizing_only` | weight 변경만 | concord | alpha + sr + sched + forge_pkg |
| `hyperparameter_sweep` | tuning | concord | alpha + sr + sched + forge_pkg |
| `reinforcement` | ★v10 강화 프로세스(WT-R) — 실투형 축(long-only·≤25종·15bps·상한없음), 원장 reinforce_ledger_l1/l2 연동 | — | parent 충실구현/FR |

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

### ★ 2단 게이트 (v9 Lean Loop 2026-08-23 — 구 3단에서 EV-지도 셀 판정 제거. 도훈 승인 D-h)

1. **hypothesis_index lookup** (위 절차 — 중복·기실패 대조)
2. **frontier 큐 확인**: `06_Registry/alpha_frontier_queue.json` (schema 2.0) — 착수 대상 엔트리의 owner/status 갱신 의무. **`status=parked` ∧ `parked_reason=dohoon_decision`(또는 `dohoon_data_work`) → 착수 금지** (구 규약의 "dohoon_decision 항목 임의 착수 금지" 가 enum 으로 보존된 자리다). 착수는 `status=open` 인 항목만, 집으면 `status=claimed` + owner 갱신. 인프라 항목은 이 파일에 없다 — `06_Registry/infra_backlog.json`.
   > 구 3단째("EV-지도 셀 판정", `06_Registry/research_ev_map.json`)는 **폐지**됐다. 그 지도는 07-10 자 256건 코퍼스 기준으로 동결돼 `06_Registry/_archive/research_ev_map_20260710_frozen.json` 으로 이동했다(갱신 의무 없음). 죽은 계급 판정이 필요하면 그 아카이브를 참조는 하되 **착수 조건으로 쓰지 않는다**.

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
- `weight_bounds = [0, 1.0]` (v10: 종목별 상한 폐지)
- `liquidity_min = 2e8` (deployment) / 1e7 (discovery hard mandate floor)
- `cost_model = v2.4_kr_retail_15bps`
- `data_lag_rules` 4종 (fundamental / price / investor_flow / macro)
- `status = SPEC_APPROVED`

## 3. 6-Agent Pipeline (v8.1 active path)

### Step 0: alpha-hypothesis  ★2026-08-08 신설 (모델 라우팅 — 유일한 Fable 구간)

```
Agent(subagent_type="alpha-hypothesis", prompt="WT{id} 가설설계 (Step 0 + ①~④)")
  → hypothesis_index lookup + alpha_frontier_queue 확인·owner 표기 (v8.3 착수 전 의무)
  → 가설 후보 3~5건 → 1건 선택(대안은 challenge_flags)
  → ①메커니즘(주체·마찰·경로) →②가설 서술 →③반증 조건(field_dictionary 내 부수 관측) →④국면 경계
  → alpha_hypothesis.json (verdict: designed | economic_void)
```
- **model 핀 = `fable`** — QEPM 전 구간 중 **여기만** Fable. 나머지 6-agent 전부 `model: opus`(현행 Opus 5). 근거·SOT: `02_Infrastructure/docs/rules/caching.md` "모델 라우팅" 절.
- **⑤ AST 구성·팩터 소싱·실측은 금지** (alpha-research 소관, 설계자≠측정자 firewall).
- `economic_void` 면 Step 1 진행 금지 → Q-Lead escalate (억지 설계 금지).

### Step 1: alpha-research

```
Agent(subagent_type="alpha-research", prompt="WT{id} Alpha Research...")
  → alpha_hypothesis.json 승계(재작성 금지) 후 ⑤ AST 구성 + Step 1~7
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

### Step 5: 등급 평가 = QEPM 종점 (★v10)

forge 산출 bt_result → `essence_score` → `authoritative_remeasure.json::essence_grade`.
- **grade < A** → FORGE_DONE → COMPLETED. 강화 대상(원장 `rf_record_result` 기록 → 다음 시도).
- **grade A** → Step 6.

### Step 6: judge — PIT 전담 (★v10, Grade A 한정)

```
Agent(subagent_type="judge", prompt="WT{id} PIT 검증 — judge_request.json 참조")
  → 검증 6축(C1~C15 감사·detect_lookahead 재실행·C5 타이밍·lag-1 스트레스·재현·selection 정직성)
  → L-code 발행(의무): emit_lcode(mode="judge_gate") → judge_verdict.json(v2)에 l_code_path 기록
  → JUDGE_PASSED / JUDGE_FAILED
```

- **PASS** → COMPLETED + BOOK 등록 후보(`register_book_entry` — writer 경유 + **도훈 confirm**. 자동 등록 없음).
- **FAIL** → 결과 무효 — 위반 수리 후 재측정(등급 재산출).
★구 Step 6(governor PG0~PG3 admission·book_state admit)은 v10 폐지 — BOOK 이 승계.

## 4. Hard Constraints (Hook 자동 검증)

| 제약 | 값 | 강제 |
|---|---|---|
| max_names | 25 hard | worktask_constraint_enforcer |
| Long-only | weights ≥ 0 | same |
| Weight bounds | 없음 — v10 폐지 (long-only만) | same |
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

v53 TeamCreate/teammate 패턴은 **폐지됨** (v8.1 Agent tool spawn 대체). ★v10: 체인 = alpha-hypothesis/alpha/risk/optimizer/forge Agent tool 개별 spawn + judge 는 Grade A 한정. governor/execution 퇴역·monitoring→book-tracker(`.claude/agents_retired_v10/`). 추가 역할(Architect/Blender)은 ondemand. (각 agent self-adversarial challenge 내장.)

**모델 라우팅 (2026-08-08 도훈 지시 — 2026-07-24 "핀 제거·상속" 정책 대체)**: QEPM 에이전트는 **전부 `model: opus`(현행 Opus 5) 명시 핀**. **유일 예외 = `alpha-hypothesis`(`model: fable`)** — 가설설계 구간(Step 0 + ①~④)만 Fable. 6-agent 파이프라인 구조는 불변(alpha-hypothesis 는 alpha-research 의 *내부 구간 분리*이지 7번째 심사 단계가 아니다 — 슬림화/확장 재제안 아님). SOT: `02_Infrastructure/docs/rules/caching.md`.

## 8. WT 진행 상태 확인

```r
source("02_Infrastructure/worktask/worktask_manager.R")
wt_list(include_completed = FALSE)
wt_status("WT-D20260501_NNN")
wt_check_graduation("WT-D20260501_NNN")  # legacy cert 파일 존재 검사(file.exists) — v10 신규 WT 는 cert 미발급이 정상.
                                          # 권위 등급 = authoritative_remeasure.json::essence_grade
```

## 9. WT 간 병렬 / 내부 순차

- **WT 간 병렬 허용** (WT001 + WT002 동시 진행 가능)
- **WT 내부 순차 강제** (v9 2026-08-23 훅 등록 해제 — 순차는 `state_machine.R` 전이 규칙이 강제, 훅 파일은 MANIFEST 사료)

## 지식 절차 (QEPM 모드 — Axiom 엔진 배선, 2026-07-04)

- **조회 의무 (consume)**: WT 생성 전 hypothesis_index lookup (§2 상단 블록). FAIL/KILL 히트 시 차별점 없인 진행 금지 + INV-7 재도전 사유 기록.
- **emit 시점 (1지점)**: judge가 essence Grade 확정 직후 `emit_qepm_lcode(source="judge_gate", metric_type="backtested")` — 상세·필수필드(mechanism 1줄 + port_t/oos_retention/sharpe/mdd + falsification 실기록)는 `.claude/agents/judge.md` "L-code 발행" 절. 산출 경로 = `judge_verdict.json::l_code_path`.
- **(legacy WT 한정)** `source="governor_admission"` 은 `lcode_schema.R` 구 원장 호환 enum — **신규 WT 사용 금지**(v10 governor 폐지 · BOOK 등록은 L-code 발행 지점이 아니다).
- 필수필드 결측(mechanism/metric_type/oos/falsification)이 승격 축 도달불가의 주원인 — emit 시점에 채운다 (문턱 완화 아님).

## 참조

- `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md` (active SOT)
- `02_Infrastructure/worktask/worktask_manager.R` (wt_create / wt_advance / wt_check_graduation)
- `02_Infrastructure/worktask/common_charter.md` v1.7
- `02_Infrastructure/worktask/red_flag_rules.md`
- `02_Infrastructure/worktask/role_card_cert_inheritance.R`
- `.claude/rules/pit.md` / `02_Infrastructure/docs/rules/harness.md` (codex-round.md = DEPRECATED 스텁, v8.2 self-adversarial 전환)
