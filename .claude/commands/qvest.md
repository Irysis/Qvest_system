---
name: qvest
description: "Qvest 시스템 구동 (v8.3 · Fable 5-Native · 4-Mode +RAMP) — Work Task 기반 리서치 엔진 부트스트랩"
disable-model-invocation: true
user-invocable: true
---

# Qvest — Work Task System (현행 버전은 CLAUDE.md Active Version이 정본 — 2026-07-26 v8.3)

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

### 3. 시스템 상태 확인

**★정본은 파일시스템 실측이다** — 아래 스냅샷은 2026-07-26 부팅감사 기준이며, 검수는 항상
`ls .claude/agents/ .claude/skills/` + 부팅 `Skills:`/`[hook-integrity]` 라인으로 한다
(구판이 9종 열거로 2주 낙후됐던 재발 방지 — 열거 갱신보다 위임이 강하다).

**Agent Registry** (2026-07-26 실측 14종): 6-agent 코어(`alpha-research`/`risk-research`/`optimizer-research`/`forge`/`judge`/`governor`) + 모드 진입(`alpha-search` ②·`ramp-orchestrator` ④·`dispatch-orchestrator` ③) + 온디맨드(`architect`/`blender`/`execution`/`monitoring`/`strategy-implementer`). scout는 파일 자체가 없음(alpha-research 흡수 완료).

**Skills** (2026-07-26 실측 — 디렉토리형 + 단일 .md 혼재): 6-agent별 리서치 skill + `qvest-worktask`(구 `worktask` 개명) / `qvest-telegram` **v7** SOT / `cleaner` / `factor-db-discovery` / `factor-rotation` / `ramp` / `kr-inverse-pattern-miner` / `simplify` / qvest-*-style 4종 / `qvest-cert-paths` / `qvest-hook-debug` 등. `commit-commands`·`codex`·`telegram-protocol`은 **부재**(폐지 — 본 문서 하단 Legacy 절 참조). 삭제 이력(2026-07-05): s0~s7 stage skill 8종.

**Hooks 5-Tier 방어선 (v6.31 발췌 — ★전수 아님)**: 현행 등록 = **46 distinct .sh**(직접 29 + 라우터 dispatch 18 − 중복 1, 2026-07-26 실측. `ast_spec_gate`·`research_continuity_guard`·`discovery_graduation_gate`·`backtest_contract_audit` 등 30건은 아래 발췌에 없음). 전수 SOT = `.claude/settings.json` + `02_Infrastructure/docs/rules/harness.md`. `sr_provenance_pre_certifier`는 2026-07-24 dispatch 해제됨(아래 Tier 5 서술은 역사 발췌).
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

PG2 active book = **`book_state.json` admitted_ids가 유일 정본** (부팅 `PG2 admit:` 라인으로 확인 — 문서 하드코딩 금지. 2026-07-26 현재 `STR_1715_on_M4gAE_R05_noLayer4_PG2` 단독).
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

## 시스템 아키텍처 (구조 개요 — 버전 정본은 CLAUDE.md)

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
│  PG2 active: book_state.json 정본 (부팅 라인 참조)    │
│  Governor / Judge / Forge 유지 (v8.2 Self-Adversarial)│
│  Axiom 엔진 active Law 4건(000/001/002/008) + CAND   │
└────────────────────────────────────────────────────┘
```

---

## 부팅 직후 체크리스트 (v8.1.3 갱신 — 13 + v8.0 5 + v8.1 4 + v8.1.2 1 + v8.1.3 4건)

### v8.1.3 신규 확인 (4건, 2026-06-20)
24. ✅ **페이퍼 적재 리서치풀 인지** 상태 라인 — `ResearchPool: route=<date> [NEW|seen · Nd] papers N · route a/o/r/rg/skip` + `AlphaQueue:`(alpha-search 대기 testable · `처리 N (ADOPT a/QUAR q)` auto_alpha_gate 결과) + `ModeQueue:`(optimizer/risk/regime = QEPM 연료 · dispatch 소비여부 · recheck 잔여). Step 3b `paper_recharge`가 적재한 신규 리서치풀을 부팅이 인지(`02_Infrastructure/ops/research_pool_status.py`, `.cache/research_pool_last_seen.json` 마커로 NEW 판정). `Routing: PENDING — collect>route`는 수집됐으나 라우터 미반영(`paper_router_run.sh _FORCE=1`). 부팅 후 갱신 시 Q-Lead가 reader 직접 재실행 가능. SKIP 시 script/python3 점검.
25. ✅ **데이터 freshness 인지** 상태 라인 — `DataFresh: <audit시각> · OK/WARN/CRITICAL N — crit: <paths>` + 핵심 연구캐시(rawdata/benchmark/regime) FRESH/stale 강조. `cache_freshness_audit.R`(daily_refresh Step 5 백그라운드 산출 `qepm/observability/cache_freshness_latest.json`, mtime+내부 max(Date) lag)를 boot이 읽어 노출 — 06-12 arrow freeze류 silent staleness 조기감지. **advisory(부팅 무중단, BOOT_FAILS 비계상)** — 핵심 캐시 stale 시 "성과수치 산출 전 갱신 의무" 경고([[feedback-performance-real-code-only]]). SKIP 시 daily_refresh 선행. ※ 표시값은 마지막 audit 시각 기준(boot Step 5 백그라운드 갱신 후 차회 부팅 반영).
26. ✅ **모닝 파이프라인 ran-today** 상태 라인 — `MorningRun: <date> 실행됨 (<시각>)` 또는 `미실행 (오늘 lock 부재)`. `/tmp/qm_morning_run_<today>.lock`(morning_run.sh once-per-day 락) 확인 — 스케줄러 silent 무발화([[project-morning-brief-scheduling]] mrs_daily 트랩) 조기감지. 미실행 시 수동 `bash 02_Infrastructure/ops/morning_run.sh manual`.
27. ✅ **4-Mode +RAMP 배너 정합** — 배너/완료배너/버전 상태 라인(`v8.3:`) `4-Mode +RAMP` + `Modes:` 라인(① QEPM ② alpha-search ③ factor-rotation ④ RAMP `/ramp` Gate0~11·CCS 13-score·governor 정지). CLAUDE.md "4-Mode 헌법(RAMP 2026-06-17)"과 사실 정합(구 "3-Mode" 폐기).

### v8.1.2 신규 확인 (1건, 2026-06-11)
23. ✅ **UTF-8 출력 가드** 부트 메시지 — `[boot] utf8_output_guard: ACTIVE`. INACTIVE WARN 시 python3 PATH 점검. 부트 외 이모지 출력 가능 커맨드는 `bash 02_Infrastructure/ops/safe_run.sh <cmd>` 경유 (API 400 invalid high surrogate 방지 — anthropics/claude-code#44230)

### v8.1 신규 확인 (4건, 2026-06-05)
19. ✅ 완료 배너·상태 라인이 **CLAUDE.md Active Version과 일치** (현행 v8.3 · Fable 5-Native · 4-Mode +RAMP — 항목 27과 동일 기준. 하드코딩 금지: 배너 버전이 헌법과 다르면 그쪽이 낡은 것)
20. ✅ **데이터 캐시 검증(Step 4e)** 부트 메시지 — `[boot] 데이터 캐시: rawdata.parquet OK + K200/KQ150 멤버십 OK` (없으면 WARN: alpha-search `universe=K200_KQ150` stop 위험) + `kr_factor_returns_v2: OK`
21. ✅ alpha-search 제1원칙 (`.claude/skills/alpha-search/SKILL.md` `## ★ 제1원칙`): 논문 완전 복제 + 유니버스 K200∪KQ150 고정(`run_alpha_search` universe 기본값) + 기간 2005~ 고정(start_date 기본값)
22. ✅ 모듈 자동흐름: `register_module` 계약 floor(`contract_pass + backtested + frozen + hash/build/cost`) + `register_research_outputs`(ML/DPL 다리, 계약 없으면 quarantine) + `run_factor_rotation` allowlist / Axiom r7 복원(`02_Infrastructure/docs/rules/axiom-engine.md` 5축 boolean-AND + INV-1~7)

### v8.0 신규 확인 (5건)
14. ✅ 완료 배너 + 버전 상태 라인 출력 확인 (기대 문자열은 항목 19/27 기준 — CLAUDE.md Active Version 정합)
15. ✅ PreToolUse[Agent] = `axiom_context_inject` + `worktask_sequence_enforcer` (unified_agent_guard 등록 해제 — `grep -c unified_agent_guard .claude/settings.json` = 0)
16. ✅ agent effort frontmatter (judge/governor xhigh, alpha/risk/optimizer/forge high) — `grep -l 'effort:' .claude/agents/*.md`
17. ✅ qvest-*-style skill 4종 + `skills:` frontmatter 부착 (alpha/risk/opt/judge/gov)
18. ✅ 헌법 R+Python 1급 (`.claude/rules/python-policy.md`) + SR목표 2.5 + AX-000 reframe / 신규 rule `artifact-naming.md` / 측정 `02_Infrastructure/eval/harness_perf_eval.R`

### v6.x 베이스 (9건)

1. ✅ `02_Infrastructure/worktask/` 존재 확인
2. ✅ Agent registry에 `alpha-research`, `risk-research`, `optimizer-research` 등록 확인
3. ✅ Skill 목록에 `qvest-worktask`(구 `worktask` 개명), `alpha-research`, `risk-research`, `optimizer-research` 확인
4. ✅ `qepm/mailbox/worktask/` 존재 + 부팅 `Inbox:` 라인 확인 (alpha/risk/optimizer inbox는 현행 구조상 부재 = `n/a` 정상 — 2026-07-26 정직 라벨. n/a가 아닌 실수 0/N이면 해당 mailbox 활성)
5. ✅ Hook 등록 실측 확인 — 부팅 `[hook-integrity]` 라인(router=OK·dispatch 수) + `harness_health` `hook entries registered` 수(0 또는 UNREPORTED = FAIL). 개수 하드코딩 금지, 전수 SOT = settings.json + harness.md (`sr_provenance_pre_certifier`는 2026-07-24 dispatch 해제)
6. ✅ Charter `v1.2` 인용 확인 (`grep "v1.2" 02_Infrastructure/worktask/common_charter.md`)
7. ✅ **Measurement Coherence Health Score** 부트 메시지 확인 (`[boot] Measurement coherence: ... Tier: HEALTHY/WARNING/DRIFTED`)
8. ✅ 폐기 Hook 아카이브 확인 — 현행 실존 아카이브는 `08_Tests/hooks/_archive_codex_round_v8_2/` (구 `_archive_v55/` 표기는 부재 경로였음, 2026-07-26 정정)
9. ✅ Git tag `pre-qepm-3agent-migration` 존재 (rollback 지점)

### v7.2.1 신규 (4건)

10. ✅ **Memory Knowledge Health** 부트 메시지 확인 (`[boot] Memory health: hard=0 warn=W info=N`). 판정 = **hard=0** 필수, warn은 0이 현행 baseline(2026-07-25 W-슬롯 재배치 후) — **warn≥1이면 신규 발생이므로 조사**(구 "warn=3 정상" 폐기: 래칫을 3칸 되돌리는 기대값이었음). 출력: `qepm/observability/memory_health_latest.json`
11. ✅ **Axiom SOT 3축 동기화** 상태 라인 확인 (`Axioms:` 라인 — `active=N candidates=M (sot_map documented=N: ...)`. 상태 보고 블록 출력, `[boot]` prefix 없음). 판정은 개수 하드코딩이 아니라 **primary(`active/AX-*.json`) ↔ documented(`.claude/rules/axioms.md`) 동수 일치** = `memory_knowledge_health.R` HARD 3 PASS. 현행 active Law = 4건(000/001/002/008 — 2026-07-05 negative 4종 Distilled 강등. 8이 나오면 강등 역행 의심)
12. ✅ **v8 Readiness Gate** 부트 메시지 확인 (`[boot] v8 readiness (--no-write, 16 check ...): ... — pass=P fail=0 [warn=W] skip=S`). 판정 기준 = **fail=0** (pass 개수 하드코딩 금지 — check 추가/soak로 변동). warn≥1이면 사유 확인(soak = human 확인 의무). e2e_kernel + timeline_generation은 no-write 시 SKIP 정상. `memory_health` cached read
13. ✅ **Cache_core sync** 상태 라인 확인 (`Cache_core: FULL (n)` — n은 **documented_active와 동수**면 정상, 현행 4. `STALE (n vs m)` = derived cache WARN only, `UNKNOWN` = 카운터 사망(일치로 취급 금지). STALE은 hard fail 아님 — axiom_sot_map.json hard_fail_basis = primary↔documented만)

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
5. 6-agent pipeline 순차 실행 (Agent tool spawn — alpha→risk→optimizer→**forge(실측권위)→judge→governor(수동)**. 3-agent에서 멈추면 proxy 수치로 끝나 measurement-graduation 위반)

---

## Legacy v53 요소 (2026-07-24 현행화)

**현역 잔존**: qepm 하이브리드 모드 (hybrid_commit / hybrid_status 등) · Axiom 엔진 (AX-000~008 → v8.x 2-tier + Distilled) · L-code 적립 체계.
**폐지됨 (현재형 서술 금지)**: TeamCreate/teammate 패턴(v8.1에서 Agent tool spawn 대체, hook 등록 해제) · tmux `rc` Telegram listener(v8.0 폐지) · Codex Critic Round(v8.2 폐지 → Self-Adversarial).

---

## 참조

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

- 현행 v8.3 (2026-07-24 Fable 5 정합 패치). 전체 버전 이력(v5.3~v8.1.3)은 `02_Infrastructure/docs/CHANGELOG_qvest_command.md`로 이관 (2026-07-24 세션 로드 다이어트).
