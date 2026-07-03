---
name: qvest
description: "Qvest 시스템 구동 (QEPM v8.1 6-Agent + 3-Mode) — Work Task 기반 리서치 엔진 부트스트랩"
disable-model-invocation: true
user-invocable: true
---

# Qvest — QEPM v8.1 Work Task System

전천후 포트폴리오 수확을 위한 QEPM 기반 자율 리서치 시스템.

**핵심 철학** (사용자 설계도):
> **"예상 초과수익(α)을 만들고, 공통위험을 계량화하고, 비용과 제약 하에서 최적 비중으로 변환한다."**

- **Alpha Agent**: "무엇이 좋아 보이는가?" (α̂만)
- **Risk Agent**: "무엇이 함께 망가질까?" (Σ만)
- **Optimizer Agent**: "무엇을 얼마나?" (weights만)

섞으면 자기합리화 엔진 전락. **3-agent 분리 = QEPM 내부통제**.

---

## 구동 순서

### 1. 부트스트랩 실행
```bash
bash 02_Infrastructure/ops/bootstrap.sh
```

### 2. 플러그인 리로드
```
/reload-plugins
```

### 3. 시스템 상태 확인 (v8.1 기준)

**Agent Registry** (.claude/agents/ 자동 감지):
- **`alpha-research`** — Alpha Research Agent (신규, Scout 대체)
- **`risk-research`** — Risk Research Agent (격상)
- **`optimizer-research`** — Optimizer Research Agent (신규)
- `forge` — 3-agent 산출물 통합 + backtest
- `judge` — S6 Gate 0~18 검증
- `governor` — PG0~PG3 admission
- `architect` — 아키텍처 진단
- `blender` — (기존, v6에서 Optimizer에 통합 검토)
- `scout` — (archived, Alpha Research로 흡수)

**Skills**:
- 신규 4종: `worktask` / `alpha-research` / `risk-research` / `optimizer-research`
- 통합: `qvest-telegram` v6 SOT (구 `telegram-protocol` deprecate) / `simplify` 3-agent 인식
- 유지: `pit-validation` / `factor-db-access` / `axiom-io` / `kr-inverse-pattern-miner` / `commit-commands` / `codex` 등
- 폐기: `s0-idea-sourcing` / `s0-debate` / `s1~s5` stage skill (archive)

**Hooks 5-Tier 방어선 (v6.31 Charter v1.2 Positive Hook 패러다임)**:
- Tier 1 (전역 hard block — system integrity 위협 영역만): `safety_guard`, `axiom_enforcement_hook`, `sr_provenance_check` (`ProductionSchedule[N]m` fabrication label hard block), `schedule_fidelity_check` (run_all.R fabrication hard block), `governor_concord_certifier` (admission graduation 우회 hard block)
- Tier 2 (Agent): `agent_role_guard` (Alpha/Risk/Opt 경계), `worktask_sequence_enforcer` (WT 순서), `axiom_context_inject` (AX 공리 주입 — v8.0 WS5-3, unified_agent_guard[v52] 폐기 대체)
- Tier 3 (Write/Edit hard mandate): `worktask_constraint_enforcer` (25종/bounds/Σw=1), `worktask_spec_validator`, `milestone_commit`
- Tier 4 (Post artifact validation): `worktask_artifact_validator`, `red_flag_detector`, `pipeline_trigger`, `auto_commit_on_stop`
- **Tier 5 (Positive Certifier — v6.31 신규)**: `alpha_discovery_certifier` (cor<0.95 + mechanism + factor_specs + harvey_t pass), `sr_provenance_check` (forge_package 4-field), `schedule_fidelity_check` (density≥0.95 또는 infeasibility), `worktask_artifact_validator` (forge_package 8-field), `governor_concord_certifier` (book_state↔admission match 또는 waiver 5-row), `sr_provenance_pre_certifier` (PreToolUse 안내)

**Charter v1.2 Certification System** (5 certificate + 1 health score + 4 role card):
- `alpha_discovery_certificate` / `sr_provenance_certificate` / `schedule_fidelity_certificate` / `forge_package_validated_certificate` / `governor_concord_certificate` (or `_with_waiver`)
- `measurement_coherence_health_score` (0-100, Healthy/Warning/Drifted)
- Role Cards by `wt_type`: discovery / deployment / sizing_only / hyperparameter_sweep
- 차단은 *certificate 부재 → admission 자격 박탈* (passive deny). Hard block은 위 2건만.

### 4. Work Task 상태 확인

```bash
cd "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
bash 02_Infrastructure/ops/safe_run.sh Rscript -e 'source("02_Infrastructure/worktask/worktask_manager.R"); wt_list()'
```

또는 `bash 02_Infrastructure/ops/safe_run.sh cat .cache/portfolio_gap_vector.json` (PG0 gap)

(safe_run.sh = utf8_output_guard 경유 실행 — 데이터 파일에 이모지가 섞여도 API 400 surrogate 차단, v8.1.2)

### 5. 리서치 개시 — Work Task 기반

#### 5-A. 신규 Work Task 생성

```r
source("02_Infrastructure/worktask/worktask_manager.R")
wt_id <- wt_create(
  hypothesis_title = "{가설 제목}",
  hypothesis_description = "{동기 + 접근}",
  universe = "KOSPI200_KOSDAQ150_intersection",
  benchmark = "KOSPI200_total_return"
)
```

자동 주입:
- `task_id = WT{YYYYMMDD}_{NNN}`
- `hard_constraints.max_names = 25`
- `weight_bounds = [0, 0.20]`
- `liquidity_min = 2e8`
- `cost_model = v2.4_kr_retail_15bps`
- `data_lag_rules` 4종 (fundamental / price / investor_flow / macro)
- `status = SPEC_APPROVED`

#### 5-B. 6-Agent 순차 실행 (Q-Lead orchestration)

```
Step 1: Agent(subagent_type="alpha-research",
              prompt="WT{id} Alpha Research...")
  → 자율 7-step → alpha_package.json

Step 2: (Hook 선행 검증) Agent(subagent_type="risk-research",
                                prompt="WT{id} Risk Research...")
  → 자율 5-step → risk_package.json + covariance.parquet

Step 3: (Hook 선행 검증) Agent(subagent_type="optimizer-research",
                                prompt="WT{id} Optimizer Research...")
  → 10+ 방법론 비교 → optimization_package.json + weights.csv

Step 4: Agent(subagent_type="forge",
              prompt="WT{id} Integrate 3-agent packages → backtest")
  → run_all_template 기반 통합 → backtest 결과

Step 5: Agent(subagent_type="judge",
              prompt="WT{id} S6 cascade Gate 0~18")
  → JUDGE_PASSED / JUDGE_FAILED

Step 6: Agent(subagent_type="governor",
              prompt="WT{id} PG0~PG3 admission")
  → GOVERNOR_ADMITTED / GOVERNOR_REJECTED
```

**WT 간 병렬 허용** (WT001 + WT002 동시 진행 가능).
**WT 내부 순차 강제** (`worktask_sequence_enforcer.sh` Hook).

#### 5-C. 기존 Legacy 전략 호환

PG2 active (STR_1631_SYN_05_2002 + STR_1656_MLRA_M05) **그대로 유지**.
신규 가설만 Work Task 방식 사용. 점진 마이그레이션.

---

## Hard Constraints (사용자 강제, Hook 자동 검증)

| 제약 | 값 | 강제 Hook |
|---|---|---|
|  **max_names** | **25 hard** | `worktask_constraint_enforcer.sh` |
| **Long-only** | weights ≥ 0 | same |
| **Weight bounds** | **[0, 0.20]** | same |
| **Σw** | = 1 (absolute) / = 0 (active) | same |
| **Universe** | KOSPI200 ∪ KOSDAQ150 | `worktask_spec_validator.sh` |
| **Liquidity** | 20d TV ≥ 2e8원 | same + Alpha Agent filter |
| **Transaction cost** | 15bps one-way | `cost_model_version` 고정 |
| **PIT C1~C15** | 전체 | Common Charter 원칙 1 |
| **3-agent 역할 경계** | Alpha/Risk/Opt 침범 금지 | `agent_role_guard.sh` |
| **WT 순서** | Alpha → Risk → Optimizer | `worktask_sequence_enforcer.sh` |

---

## Common Charter 8원칙 (3-agent 공통)

1. Point-in-time Only
2. Research Process First (QEPM 5단계)
3. Factor Family vs Proxy 구분
4. 논문은 출발점, 승인서 아님
5. Data Mining 방지
6. Dynamic Smart Alpha
7. 비용 · 용량 · 군집위험 mandatory
8. No Silent Override (challenge_note / infeasibility_report 의무)

전체: `02_Infrastructure/worktask/common_charter.md`

---

## Red Flag 자동 감지 (`red_flag_detector.sh`)

**Alpha Red Flags**: RF-A1 논문 단독 근거 / RF-A2 Composite 개선 불명확 / RF-A3 recent 3Y 과적합 / RF-A4 sector-neutral 후 붕괴 / RF-A5 top decile illiquid

**Risk Red Flags**: RF-R1 섹터 집중 / RF-R2 Covariance ill-conditioned / RF-R3 Crowding / RF-R4 Stress 초과 / RF-R5 Style 중복

**Optimizer Red Flags**: RF-O1 Top alpha 미실현 / RF-O2 낮은 순알파 / RF-O3 미세 리밸런싱 / RF-O4 Constraint 민감도 폭발 / RF-O5~7 Hard Constraint 위반 (CRITICAL Hook block)

전체: `02_Infrastructure/worktask/red_flag_rules.md`

---

## Q-Lead 역할 경계 (Level 0)

- ✅ 진단, 지시, 모니터링, 결과 수집, 텔레그램 보고
- ✅ Work Task 생성 + 6-agent spawn orchestration
- ❌ 직접 Rscript 실행 / 백테 / factor_engine 수정 → Forge / Alpha Agent에 위임
- ❌ weight 결정 / 공분산 계산 → Optimizer / Risk Agent에 위임
- ❌ Alpha/Risk/Opt 경계 침범 감독 (Hook 자동 차단)

---

## 시스템 아키텍처 (v8.1)

```
┌─ Q-Lead 세션 ───────────────────────────────────────┐
│  /worktask create → WT{id} 생성                      │
│  Agent(alpha-research) → alpha_package              │
│  Agent(risk-research) → risk_package (순서 강제)    │
│  Agent(optimizer-research) → optimization_package    │
│  Agent(forge) → run_all.R + backtest                │
│  Agent(judge) → S6 Gate 0~18                        │
│  Agent(governor) → PG0~PG3 admission                │
├─ Hooks (6 신규 + 14 유지) ─────────────────────────┤
│  Pre:  safety / axiom / agent_role_guard /           │
│        worktask_sequence_enforcer /                  │
│        worktask_constraint_enforcer /                │
│        worktask_spec_validator                       │
│  Post: worktask_artifact_validator / red_flag /      │
│        pipeline_trigger / milestone_commit           │
├─ Work Task Lifecycle ──────────────────────────────┤
│  SPEC_APPROVED → ALPHA_DONE → RISK_DONE →           │
│  OPTIMIZER_DONE → FORGE_DONE →                       │
│  JUDGE_PASSED → GOVERNOR_ADMITTED → COMPLETED        │
├─ Legacy 유지 ──────────────────────────────────────┤
│  PG2 active: STR_1631 + STR_1656                     │
│  Governor / Judge / Forge 유지 (v8.2 Self-Adversarial)│
│  Axiom 엔진 active 6건 + AX_CAND tracking            │
└────────────────────────────────────────────────────┘
```

---

## 부팅 직후 체크리스트 (v8.1.3 갱신 — 13 + v8.0 5 + v8.1 4 + v8.1.2 1 + v8.1.3 4건)

### v8.1.3 신규 확인 (4건, 2026-06-20)
24. ✅ **페이퍼 적재 리서치풀 인지** 상태 라인 — `ResearchPool: route=<date> [NEW|seen · Nd] papers N · route a/o/r/rg/skip` + `AlphaQueue:`(alpha-search 대기 testable · `처리 N (ADOPT a/QUAR q)` auto_alpha_gate 결과) + `ModeQueue:`(optimizer/risk/regime = QEPM 연료 · dispatch 소비여부 · recheck 잔여). Step 3b `paper_recharge`가 적재한 신규 리서치풀을 부팅이 인지(`02_Infrastructure/ops/research_pool_status.py`, `.cache/research_pool_last_seen.json` 마커로 NEW 판정). `Routing: PENDING — collect>route`는 수집됐으나 라우터 미반영(`paper_router_run.sh _FORCE=1`). 부팅 후 갱신 시 Q-Lead가 reader 직접 재실행 가능. SKIP 시 script/python3 점검.
25. ✅ **데이터 freshness 인지** 상태 라인 — `DataFresh: <audit시각> · OK/WARN/CRITICAL N — crit: <paths>` + 핵심 연구캐시(rawdata/benchmark/regime) FRESH/stale 강조. `cache_freshness_audit.R`(daily_refresh Step 5 백그라운드 산출 `qepm/observability/cache_freshness_latest.json`, mtime+내부 max(Date) lag)를 boot이 읽어 노출 — 06-12 arrow freeze류 silent staleness 조기감지. **advisory(부팅 무중단, BOOT_FAILS 비계상)** — 핵심 캐시 stale 시 "성과수치 산출 전 갱신 의무" 경고([[feedback-performance-real-code-only]]). SKIP 시 daily_refresh 선행. ※ 표시값은 마지막 audit 시각 기준(boot Step 5 백그라운드 갱신 후 차회 부팅 반영).
26. ✅ **모닝 파이프라인 ran-today** 상태 라인 — `MorningRun: <date> 실행됨 (<시각>)` 또는 `미실행 (오늘 lock 부재)`. `/tmp/qm_morning_run_<today>.lock`(morning_run.sh once-per-day 락) 확인 — 스케줄러 silent 무발화([[project-morning-brief-scheduling]] mrs_daily 트랩) 조기감지. 미실행 시 수동 `bash 02_Infrastructure/ops/morning_run.sh manual`.
27. ✅ **4-Mode +RAMP 배너 정합** — 배너/완료배너/`v8.1:` 라인 `4-Mode +RAMP` + `Modes:` 라인(① QEPM ② alpha-search ③ factor-rotation ④ RAMP `/ramp` Gate0~11·CCS 13-score·governor 정지). CLAUDE.md "4-Mode 헌법(RAMP 2026-06-17)"과 사실 정합(구 "3-Mode" 폐기).

### v8.1.2 신규 확인 (1건, 2026-06-11)
23. ✅ **UTF-8 출력 가드** 부트 메시지 — `[boot] utf8_output_guard: ACTIVE`. INACTIVE WARN 시 python3 PATH 점검. 부트 외 이모지 출력 가능 커맨드는 `bash 02_Infrastructure/ops/safe_run.sh <cmd>` 경유 (API 400 invalid high surrogate 방지 — anthropics/claude-code#44230)

### v8.1 신규 확인 (4건, 2026-06-05)
19. ✅ 완료 배너 `Qvest v8.1 — Opus 4.8 Native · 3-Mode · 실측 거버넌스` + `v8.1:` 상태 라인 출력
20. ✅ **데이터 캐시 검증(Step 4e)** 부트 메시지 — `[boot] 데이터 캐시: rawdata.parquet OK + K200/KQ150 멤버십 OK` (없으면 WARN: alpha-search `universe=K200_KQ150` stop 위험) + `kr_factor_returns_v2: OK`
21. ✅ alpha-search 제1원칙 (`.claude/skills/alpha-search/SKILL.md` `## ★ 제1원칙`): 논문 완전 복제 + 유니버스 K200∪KQ150 고정(`run_alpha_search` universe 기본값) + 기간 2005~ 고정(start_date 기본값)
22. ✅ 모듈 자동흐름: `register_module` 계약 floor(`contract_pass + backtested + frozen + hash/build/cost`) + `register_research_outputs`(ML/DPL 다리, 계약 없으면 quarantine) + `run_factor_rotation` allowlist / Axiom r7 복원(`02_Infrastructure/docs/rules/axiom-engine.md` 5축 boolean-AND + INV-1~7)

### v8.0 신규 확인 (5건)
14. ✅ 완료 배너 `Qvest v8.1 — Opus 4.8 Native` + `v8.1:` 상태 라인 출력 확인
15. ✅ PreToolUse[Agent] = `axiom_context_inject` + `worktask_sequence_enforcer` (unified_agent_guard 등록 해제 — `grep -c unified_agent_guard .claude/settings.json` = 0)
16. ✅ agent effort frontmatter (judge/governor xhigh, alpha/risk/optimizer/forge high) — `grep -l 'effort:' .claude/agents/*.md`
17. ✅ qvest-*-style skill 4종 + `skills:` frontmatter 부착 (alpha/risk/opt/judge/gov)
18. ✅ 헌법 R+Python 1급 (`.claude/rules/python-policy.md`) + SR목표 2.5 + AX-000 reframe / 신규 rule `artifact-naming.md` / 측정 `02_Infrastructure/eval/harness_perf_eval.R`

### v6.x 베이스 (9건)

1. ✅ `02_Infrastructure/worktask/` 존재 확인
2. ✅ Agent registry에 `alpha-research`, `risk-research`, `optimizer-research` 등록 확인
3. ✅ Skill 목록에 `worktask`, `alpha-research`, `risk-research`, `optimizer-research` 확인
4. ✅ `qepm/mailbox/{worktask,alpha,risk,optimizer}/` 디렉토리 존재
5. ✅ Hook **신규 9종** `settings.json` 등록 확인 (v6.31: alpha_discovery_certifier / sr_provenance_pre_certifier / governor_concord_certifier 신규 + sr_provenance_check / schedule_fidelity_check 강화)
6. ✅ Charter `v1.2` 인용 확인 (`grep "v1.2" 02_Infrastructure/worktask/common_charter.md`)
7. ✅ **Measurement Coherence Health Score** 부트 메시지 확인 (`[boot] Measurement coherence: ... Tier: HEALTHY/WARNING/DRIFTED`)
8. ✅ `02_Infrastructure/hooks/_archive_v55/` 폐기 Hook 6종 archive 확인
9. ✅ Git tag `pre-qepm-3agent-migration` 존재 (rollback 지점)

### v7.2.1 신규 (4건)

10. ✅ **Memory Knowledge Health** 부트 메시지 확인 (`[boot] Memory health: hard=0 warn=≤6 info=N`). HARD ≥1 이면 즉시 중단. 출력: `qepm/observability/memory_health_latest.json`
11. ✅ **Axiom SOT 3축 동기화** 상태 라인 확인 (`Axioms:` 라인 — `active=N candidates=M (sot_map documented=8: documented=3 / block=1 / advisory=4)`. 상태 보고 블록 출력, `[boot]` prefix 없음). primary (`active/AX-*.json`) ↔ documented (`.claude/rules/axioms.md`) 8:8 일치 = `memory_knowledge_health.R` HARD 3 PASS
12. ✅ **v8 Readiness Gate** 부트 메시지 확인 (`[boot] v8 readiness (--no-write, 16 check incl v8_architecture): PASS — pass=13 fail=0 skip=2`). e2e_kernel + timeline_generation은 no-write 시 SKIP 정상. `memory_health` cached `memory_health_latest.json` read
13. ✅ **Cache_core sync** 상태 라인 확인 (`Cache_core: FULL (8)` 또는 `STALE (n vs 8 — derived cache, WARN only)`. 상태 보고 블록 출력, `[boot]` prefix 없음). STALE은 hard fail 아님 (axiom_sot_map.json sot_definition.hard_fail_basis = primary↔documented만)

체크 실패 시 → `next_session_task.md` 참조 + 복구.

**v6.31 Health Score Tier 의미**:
- **Healthy ≥ 90**: 모든 active book strategy가 5 certificate 보유 + divergence < 0.3pp
- **Warning 70~89**: 일부 certificate 누락 또는 divergence 0.3~0.6pp
- **Drifted < 70**: certificate 다수 부재 또는 fabrication 의심 (Charter §9 SIGNIFICANT_DRAG / FABRICATION_SUSPECTED)

**v7.2.1 Memory Knowledge Health 의미**:
- **HARD 6**: active axiom JSON parse / 필수 metadata 6 fields / sot_map active↔documented 일치 / dep+active duplicate / review --all dry-run 안전 / promote helper selftest
- **WARN 6**: L-code outliers / stale candidate 90+d / review_log schema variants / external memory indexed (INFO 격하) / enforcement claim ↔ hook 강제력 / regime_validation parse + cache_core STALE
- HARD ≥1 = bootstrap 중단 후 Q-Lead 즉시 수정. WARN은 정보 표시만 (현재 baseline: warn=3 정상)

---

## 새 세션 시작 패턴

1. `/qvest` → 이 파일 read + 부트스트랩
2. `next_session_task.md` 확인 → 직전 세션 carry + 현 과제
3. `wt_list()` → 진행 중 WT 목록
4. 신규 가설 → `/worktask create "{hypothesis}"` or 직접 `wt_create()`
5. 3-agent pipeline 순차 실행 (Agent tool spawn)

---

## Legacy v53 요소 (아직 살아있는 부분)

- TeamCreate + SendMessage (teammate 간 자율 peer DM)
- qepm 하이브리드 모드 (hybrid_commit / hybrid_status 등)
- Telegram listener (tmux `rc` 세션)
- Axiom 엔진 (AX-000~008 + candidates)
- L-code 적립 체계

**v6는 v53을 replace가 아니라 확장**. 기존 Governor/Judge/Forge/Codex Critic 역할 그대로 유지, Scout만 Alpha Research Agent로 교체, 새 Work Task layer 추가.

---

## 참조

- Plan: `/home/quant/.claude/plans/ethereal-gliding-dahl.md`
- Common Charter: `02_Infrastructure/worktask/common_charter.md`
- Red Flag: `02_Infrastructure/worktask/red_flag_rules.md`
- Schema: `02_Infrastructure/worktask/schema.json`
- Constraints 기본값: `02_Infrastructure/worktask/constraint_defaults.json`
- Manager: `02_Infrastructure/worktask/worktask_manager.R`
- 3-agent prompt: `02_Infrastructure/prompts/{alpha,risk,optimizer}_research_init.md`
- MVO 정통: `02_Infrastructure/portfolio/mean_variance_optimizer.R`
- Method Registry: `02_Infrastructure/portfolio/weight_method_registry.R`
- Git tag: `pre-qepm-3agent-migration`

---

## Version

- **v8.1.3** — 2026-06-20 — **페이퍼 적재 리서치풀 부팅 인지 + 부팅 가시성 4종 보강**. 부팅이 산출만 하고 안 읽던 상태들을 상태 보고에 노출(도훈 "추가할 거 체크" mandate). **① 리서치풀 인지**: 신규 `02_Infrastructure/ops/research_pool_status.py`(fail-soft 리더) — `stage_artifacts/paper_recharge/`의 최신 `alpha_search_route_*`(route 분포+testable 팩터후보) / `alpha_search_queue_*`(alpha-search 대기, 큐 staleness 명시) / `mode_queue_*`(opt·risk·regime QEPM 연료) / `research_status_*`(dispatch 소비) / `factor_recheck_*`(tier-2 잔여) / `alpha_search_queue_done`+`auto_verify_*`(auto_alpha_gate ADOPT/QUARANTINE) / 수집·라우팅 날짜 비교(`collect>route`=라우터 미반영). `.cache/research_pool_last_seen.json` 마커 NEW 판정(`--mark` 인지). **② 데이터 freshness**: `cache_freshness_audit.R`가 daily_refresh(Step 5 백그라운드)에 산출하던 `qepm/observability/cache_freshness_latest.json`(mtime+내부 max(Date) lag, OK/WARN/CRITICAL)을 boot이 읽어 `DataFresh:` 라인 노출 — 핵심 캐시(rawdata/benchmark/regime) stale 별도 강조. 06-12 arrow freeze류 silent staleness 조기감지(현 실측 즉시 regime_daily_v2 stale 포착). advisory(BOOT_FAILS 비계상). **③ 모닝 ran-today**: `/tmp/qm_morning_run_<today>.lock` 확인 `MorningRun:` 라인 — 스케줄러 silent 무발화 감지. **④ 4-Mode +RAMP 정합**: 배너/완료/`v8.1:` 라인 3-Mode→4-Mode + `Modes:` 라인(RAMP `/ramp` governor 정지). CLAUDE.md 헌법 정합. bootstrap.sh Step 8f/8g/8h + 상태 블록 5라인 추가. 체크리스트 24~27. 검증: `bash -n` PASS · route 0620/queue 0619 stale 정확 · NEW→seen flip · freshness CRITICAL 2/WARN 72 + regime stale 포착 · MorningRun 10:19 포착 · fail-soft(dir/json/python3 부재 SKIP).
- **v8.1.2** — 2026-06-11 — **UTF-8 출력 가드 (API 400 invalid high surrogate 완전 차단)**. /qvest 부트 시 Anthropic API 400 (`invalid high surrogate in string`) 근본 수리: 원인 = Bash tool 출력 내 non-BMP 문자(이모지, U+10000+)가 Claude Code 30k자 절단에서 surrogate pair가 갈라져 lone surrogate로 직렬화 (anthropics/claude-code#44230 + #16294, 공식 미수정). 조치: (1) `ops/utf8_output_guard.py` 신규 — invalid byte + non-BMP + U+FFFD → '?' 줄단위 정제, BMP-only 유효 UTF-8 보장. (2) bootstrap.sh 자체 재실행 래퍼(QVEST_BOOT_SANITIZED) — 자식 R/Python/백그라운드 출력 전부 가드 경유 + `[boot] utf8_output_guard: ACTIVE` 표시. (3) cleanup.sh stdout 누수 → /tmp/qm_cleanup_boot.log 리다이렉트 (비동기 끼어들기 + 가드 파이프 hold 방지). (4) 장식 글리프 ASCII화 (━→=, ✓→OK) + non-BMP 이모지 제거: sr_provenance_pre_certifier.sh U+1F4CB / daily_refresh.sh U+1F4C5(리프레시 로그 tail 경로) / _wt_pretty.py U+1F6AB→⛔(U+26D4 BMP). (5) 임의 커맨드용 `ops/safe_run.sh` 신규. 체크리스트 23 추가. **[추보 06-11 오후 — 실제 진범 확정]** 재발 포렌식(transcript 전수 스캔)으로 진범 = **hook additionalContext**: `python3 json.dumps(sys.stdin.read())`가 hook env에서 UTF-8 한글/이모지를 cp949+surrogateescape로 디코딩 → lone surrogate(\udcXX) 주입 → 해당 세션 전체 영구 400 (Stop마다 auto_commit/auto_push · Agent spawn마다 axiom_context_inject — 06-10 Stop hook 재등록 직후 발병). 수리: hook 6개(auto_commit/auto_push/axiom_context_inject/milestone_commit/role_taxonomy/unified_agent_guard) `sys.stdin.buffer` bytes-decode + surrogate 스크럽 + `export PYTHONUTF8=1`, `setx PYTHONUTF8 1`(user env 영구), 오염 transcript 8개 스크럽 복구(.surrogate_bak). 상세: `02_Infrastructure/docs/rules/harness.md` "Hook stdout JSON 규율".
- **v8.1.0** — 2026-06-05 — **3-Mode 헌법 + 실측 거버넌스 + 모듈 자동흐름 승격**. (1) alpha-search 제1원칙(논문 완전 복제 + 유니버스 K200∪KQ150 고정 `universe="K200_KQ150"` + 기간 2005~ 고정 `start_date="2005-01-01"`) — KR 데이터 한계(value/BM 2002-08~ · M08_ResidMom 1995~ · factor DB 1990~) 진단 기반. (2) factor-rotation Lane3(`register_module` 계약 floor: `contract_pass + backtested + frozen + hash/build/cost`, RCMA 6기준 양방향, `run_factor_rotation` allowlist) + ML/DPL register 다리(`register_research_outputs`, 계약 없으면 quarantine). (3) Axiom r7 원전 복원(5축 boolean-AND + 3-mode 2-tier + INV-1~7). (4) measurement-graduation 실측-only(real-computation · portfolio-α t forge-authoritative · oos_retention/calmar HARD · book-marginal). **bootstrap v8.1**: 배너 v8.1 + Step 4e 데이터 캐시/K200_KQ150 멤버십 검증(Critical 패치). 체크리스트 13+5 → +v8.1 4건(19-22). v8 readiness 15→16 check(v8_architecture). E2E 4축 배선 닫힘. 미완: residual momentum 사이클 register/factor_analysis 디버깅.
- **v7.2.1-boot** — 2026-05-02 Session 76 — **부팅 시퀸스 v7.2.1 자원 11항 통합 + readiness gate 15-check 갭 해소**. bootstrap.sh Step 4 교체 (`memory_knowledge_health.R` foreground hard 6 + warning 6) + Step 4b 신규 (`memory_metadata_normalize.R` selftest 2/2) + Step 4c 신규 (`lcode_corpus_rebuild.R` 백그라운드, 4 source 통합) + Step 7d 신규 (`qvest_v8_ready --no-write --json` 13/15 PASS + 2 SKIP 정상) + Step 8 확장 (axiom sot_map 기반 documented_active count + enforcement_mode 분류 documented/block/advisory + cache_core sync 표시). 부팅 직후 체크리스트 9 → 13건 확장. **메모리 정합성 갭 1건 해소**: `v8_readiness_gate.R` `check_memory_health` (15번째 check)는 코드상 이미 호출되어 있었으나 README/last run JSON이 14에 멈춰 있어서 메모리 "15 total" 표기와 외관 갭 발생. README 14→15 갱신 + bootstrap 메시지/qvest.md 체크리스트 동기화로 해소. baseline: HARD 0 / WARN 3 / INFO 1 PASS + readiness 13/15 PASS + 2 SKIP.
- **v6.3.3** — 2026-05-01 Session 75 — **v6.0 Codex Critic Round 의무 3중 장치 영구 정착**. 본 cycle WT-D20260501_001 alpha+risk codex round 누락 (도훈 지적) → 4-Layer 진단 (Q-Lead 인지 40% + spawn prompt 30% + agent 자율 무시 15% + Hook regex 갭 15%). 3중 장치 fix: (A) `CLAUDE.md` Level 0 `## v6.0 Codex Critic Round 의무` 신규 명문화 / (B) PreToolUse Hook `codex_round_pre_enforcer.sh` 신규 (130 LoC, final {role}_package.json 작성 시 _draft + critic_response 부재 block + waiver via challenge_note.md) / (C) `qlead_spawn_template.md` 신규 (5단계 흐름 + Self-Check + 6 role 적용 대상). settings.json PreToolUse Hook 17→18. 사후 alpha+risk codex round background spawn. L-269 적립.
- **v6.3.2** — 2026-05-01 Session 75 — **Cert Auto-Issuance Paths 명문화 + Layer 4 영구 deferred 확정**. (1) `.claude/settings.json` `hooks.FileChanged` array 영구 제거 (Layer 4 inconclusive 결론, B-3 채택). (2) 신규 `02_Infrastructure/worktask/cert_issuance_paths.md` SOT — Claude Code Write/Edit tool 경유 시 5 cert PostToolUse Hook 100% 자동 발급, Bash/Rscript/외부 editor 시 Layer 2 bootstrap sweep 사후 backfill 매트릭스 6 row + 운영 권장 패턴. E2E dry-run 6/6 PASS (alpha_discovery + sr_provenance + forge_package_validated + schedule_fidelity 4 cert auto-issue + 음의 시나리오 cert 부재 admit 차단 + Hard block fabrication label PASS) 입증 후 발행. L-267/L-268.
- **v6.31** — 2026-04-28 — **Alpha Discovery Certification + Research Process Coherence System**. Charter v1.2 §10 (5 certificate + 1 health score + 4 role card) + Positive Hook 패러다임 (Opus 4.7 정합) + hard block 2건 한정. STR_1715 OVERRIDE_006 사후 atomic patch.
- v6.3 — 2026-04-27 — Charter §8/§9 + sr_provenance/schedule_fidelity (L2 soft passed 한계 노출, v6.31에서 격상)
- v6.0 — 2026-04-23 Session 69 — QEPM 3-Agent Work Task 아키텍처 도입
- v5.5 — 2026-04-19 Session 67 v55 strict
- v5.3 — 2026-04-13 v53 TeamCreate + Hook 17종
