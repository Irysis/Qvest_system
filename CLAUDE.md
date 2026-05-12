# Quant Module Moltbot — Claude Code Instructions

## Active Version

**Qvest v7.2.1 — Memory Knowledge Hardening**

**계보**: v6.4.0 → v7.0.0 → v7.0.1 → v7.1.0-lite → v7.2.0 → **v7.2.1** (현재 active)
**Branch**: `v7.1-hardening` (lite 패치 발행 branch, master 동기화 daily_push)

**★ Active SOT (단일 진실)**: `02_Infrastructure/docs/qvest_v7_2_1_sot.md`
**전임 SOT (흡수됨)**: `02_Infrastructure/docs/qvest_v6_4_sot.md` (v6.4 base 흡수, read-only retain)
**Legacy boundary**: `02_Infrastructure/docs/qvest_legacy_boundary.md` (v55 / S0~S7 격리)

본 CLAUDE.md는 헌법만. 절차는 `.claude/skills/`, 룰은 `.claude/rules/`, 강제는 `02_Infrastructure/hooks/`, 역할은 `.claude/agents/`.

---

## Active Path (v7.2.1, lifecycle은 v6.4와 동일)

```
WorkTask → alpha-research → risk-research → optimizer-research → forge → judge → governor
```

각 agent spawn 시 **v6.0 Codex Critic Round 의무** (5단계 흐름, `_draft → codex → challenge_note → final`).

---

## Session Startup (MANDATORY)

새 세션 시작 시:
```
/qvest
```
Qvest 시스템 전체 구동. bootstrap.sh 실행 → 플러그인 리로드 → gap 확인.

## Session End (MANDATORY)

세션 종료 시:
- 메모리 파일 modified 시 `# 최종 업데이트:` date 갱신
- 새 L-code 추가 시 methodology_active.md 등재 + MEMORY.md 헤더 갱신
- infra 변경 시 infrastructure_state.md 갱신

---

## Core Rules

- R only (tidyverse + data.table). Python은 hook router (Phase 4) 외 strategies 금지
- **NEVER modify** `05_Production/`, `01_Literature/`
- All output to `04_Research/` and `06_Registry/`
- Korean semi-formal tone (존댓말). User = Dohoon Kim (도훈), calls me "Q"

## 병렬 에이전트 실행 규칙

- 독립적 작업 2건+ → Agent tool 병렬 spawn 필수
- RAM 80% 이하 시 추가 spawn
- 코드 작성과 실행 분리 (메인 작성 → background spawn → 즉시 다음)
- Stage Gate artifact 작성은 메인 직접 (서브 위임 금지)

---

## Active Entrypoints

| Command | 용도 |
|---|---|
| `/qvest` | Session startup + bootstrap + status |
| `/worktask` | WorkTask 생성 + 상태 + 전이 + admission |

---

## Absolute Rules (1줄 reference)

- **PIT C1~C15**: `.claude/rules/pit.md`
- **Lockbox / Frozen Alpha Scope**: `.claude/rules/lockbox-scope.md` (정규 리서치 alpha/risk/optimizer만 적용. forge/monitoring/Q-Lead/execution = 폐기. 도훈 mandate 2026-05-09)
- **Codex Critic Round 의무**: `.claude/rules/codex-round.md` (모든 agent spawn 시 5단계 흐름, 우회 시 PreToolUse Hook block)
- **Backtest Result Contract v1.0**: `.claude/rules/backtest-contract.md` (PerformanceAnalytics 표준 함수만)
- **Qvest 답변 원칙 (8원칙 + 5금지)**: `.claude/rules/answer-principles.md` (위반 = AX-002 동급)
- **Telegram v6 SOT**: `.claude/skills/qvest-telegram/SKILL.md` (단일 규칙. `tg_agent_brief()` 진입점, 약어 풀이 자동, 표준 4섹션 권장)
- **Caching Discipline**: `.claude/rules/caching.md` (Anthropic 5분 TTL, ScheduleWakeup ≤270s)
- **Harness Engineering (Hooks Tier 1~6)**: `.claude/rules/harness.md`
- **Factor DB + Forge 자원**: `.claude/rules/factor-db.md` (C13~C15 + load_month_factors 경유)
- **Axioms (AX-000~008)**: `.claude/rules/axioms.md`

---

## Project Goals

### 제1목표: 미래참조 없는 전략 설계 (PIT 완전 준수) — 성과보다 우선

### 제2목표: SR 2.0+ / CAGR 16%+ / MDD <25%

### 제약 (방침)

- 기존 인프라 극한 활용 (Factor DB / DART / FRED / ECOS / QuantiWise)
- 크로스마켓 / 대체데이터 금지
- 확장 허용: ML / 수리통계 / 물리학 / 카오스이론

---

## Production Constraints

| 제약 | 값 |
|---|---|
| 종목수 | max 20 (v53 hook 강제) |
| 유동성 | 20일 평균 거래대금 ≥ 2e8 KRW (LIQ_THRESHOLD) |
| Long-only | weights ≥ 0 |
| Weight bounds | [0, 0.20] |
| Σw | = 1 (absolute) |
| Universe | KOSPI200 ∪ KOSDAQ150 |
| Transaction cost | 15bps one-way (cost_model_version v2.3_kr_retail_15bps) |
| PIT | C1~C15 전체 (`.claude/rules/pit.md`) |

---

## Key Paths

- Project root: `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/`
- Infrastructure: `02_Infrastructure/` (config.R + 12 subdirs: data/ factor_db/ regime/ validation/ hooks/ agents/ telegram/ reports/ memory/ portfolio/ ops/ docs/ worktask/ contracts/ tools/ axiom/ prompts/)
- Strategies: `04_Research/strategies/STR_XXX_name/` (legacy retain)
- WT mailbox: `qepm/mailbox/worktask/{WT_ID}/`
- Stage artifacts: `stage_artifacts/WT_{ID}/`
- Memory: `/home/quant/.claude/projects/.../memory/MEMORY.md`

---

## R Execution Pattern

- `source('run_all.R')` pattern only (한글 path encoding 회피, NOT `--file=`)
- `cd` to strategy directory first, then `Rscript -e 'source("run_all.R")'`

---

## Multi-Agent Summary (v6.4 active 6 + 4 ondemand)

| Agent | 위치 | 역할 |
|---|---|---|
| **Q-Lead** | 메인 Claude 세션 (유일) | 오케스트레이션, agent spawn, memory commit, telegram 보고 |
| **alpha-research** | Agent tool | α̂ 생성 (factor specs + ICIR + Harvey-t). Σ/weight 절대 금지 |
| **risk-research** | Agent tool | Σ + tail + stress + crowding + style. alpha 수정 금지 |
| **optimizer-research** | Agent tool | weights 결정 (MVO/HRP/CVaR/etc 자율). alpha/risk 재해석 금지 |
| **forge** | Agent tool | run_all.R + backtest 통합 (Pure function). target_weights/cov 수정 금지 |
| **judge** | Agent tool | Gate 0~18 + PIT 검증 |
| **governor** | Agent tool | PG0~PG3 admission + book_state |
| architect | Agent tool (ondemand) | 인프라 진단 |
| blender | Agent tool (ondemand) | 국면 배분 (Grade A 4건+ 시) |
| execution | Agent tool (ondemand) | TWAP/VWAP schedule (deployment 시) |
| monitoring | Agent tool (ondemand / cron) | live drift 월간 |

상세 절차: `.claude/skills/qvest-worktask/SKILL.md`

---

## Axioms (Level 0 — 요약)

전체: `.claude/rules/axioms.md` 또는 `_shared_prefix.md`

```
계층: AX-code (Lv0) > PIT C1-C15 (Lv1) > L-code (Lv2) > Signals (Lv3)
```

- **AX-000** [IMMUTABLE]: 한계란 없다. 모든 목표 달성 가능
- **AX-001 v2** [IMMUTABLE]: 방어형 팩터 조건부 평가 (crisis_alpha + Core 대비 MDD + bad/normal IC ratio)
- **AX-002** [IMMUTABLE]: 하네스 내 성과만 유효. 프로세스 우회 = 미래참조
- **AX-003** [empirical]: KR value EP_STANDALONE 실패. L-132/135
- **AX-004** [methodological]: KR quality_profitability single-signal long-only 실패
- **AX-005 v1.2** [methodological]: KR defense top20 long-only 실패. EXCLUSION necessary not sufficient
- **AX-007** [methodological]: single-sleeve top20 mechanism break. 예외 4종 (multi-sleeve / long-short / 50+ / ML sizing)
- **AX-008** [process]: Verification Triangulation (Forge + Codex + Architect 2/3 PASS)

위반 시 즉시 중단. Hook `axiom_enforcement_hook.sh` 자동 차단.

---

## Q-Lead 역할 경계 (Level 0)

- ✅ 진단 / 지시 / 모니터링 / 결과 수집 / telegram 보고
- ✅ WT 생성 + 6 agent spawn orchestration
- ❌ 직접 Rscript 실행 / 백테 / factor_engine 수정 → Forge / Alpha agent 위임
- ❌ weight 결정 / 공분산 계산 → Optimizer / Risk agent 위임
- ❌ Alpha/Risk/Opt 경계 침범 (Hook L3 자동 차단)

---

## qepm 하이브리드 모드 (Q-Lead 전용)

```bash
cd qepm && Rscript -e 'source("scripts/hybrid_mode.R")'
```

주요 함수: `hybrid_commit()` / `hybrid_status()` / `hybrid_queue()` / `hybrid_daily_digest()`

---

## Slash Commands (`.claude/commands/`)

| Command | 용도 |
|---|---|
| `/qvest` | Session startup + bootstrap + status |
| `/worktask` | WorkTask CRUD |
| `/scout` (legacy) | scout_init.md 로드 — alpha-research로 흡수, retain compat |
| `/forge` (legacy) | forge_init.md 로드 — v6.4 forge agent로 점진 |
| `/judge` (legacy) | judge_init.md 로드 |
| `/governor` (legacy) | governor_init.md 로드 |
| `/qlead` | Q-Lead session dashboard |
| `/launch-team` | TeamCreate 4인 가동 (legacy v53) |

---

## Skills + Rules

### Skills (`.claude/skills/`) — domain-scoped

| Skill | 용도 |
|---|---|
| `qvest-worktask` | WorkTask lifecycle 절차 (CLAUDE.md에서 이동) |
| `qvest-codex-round` | Codex Critic Round 5단계 흐름 |
| `qvest-telegram` | 텔레그램 단일 SOT (v6) — 양식 / 약어 풀이 / Hook 정책 / caller 예시 통합 |
| (Phase 9 추가 예정) | qvest-hook-debug / qvest-cert-paths |

### Rules (`.claude/rules/`) — Level 0 헌법 보강

| Rule | 용도 |
|---|---|
| `answer-principles.md` | 8원칙 + 5금지 + 자가체크 |
| `pit.md` | C1~C15 + S0/S1 overlay 금지 + Production Constraints |
| `codex-round.md` | Codex Round + Positive Hook 패러다임 |
| `harness.md` | Hooks Tier 1~6 매트릭스 |
| `backtest-contract.md` | bt_result 10-component + audit |
| `caching.md` | Anthropic 5분 TTL + ScheduleWakeup |
| `factor-db.md` | C13~C15 + load_month_factors 경유 |
| `axioms.md` | AX-000~008 본문 |

---

## Multi-Agent Team v53 (legacy compat retain)

TeamCreate teammate 4인 (Scout / Forge / Judge / Governor) Q-Lead 세션 spawn. Hook (SubagentStop / FileChanged / TeammateIdle / TaskCompleted) 자동 발동. tmux `rc` (telegram listener) 1개 retain.

상세: `.claude/skills/qvest-worktask/SKILL.md` Section 7.

---

## Safety Rules

- NEVER modify `05_Production/` (promote_to_production() 만 예외)
- `01_Literature/` read-only
- All output to `04_Research/` and `06_Registry/`
- 기존 stage_artifacts/ + 178+ STR 결과 보존
- legacy v55/S0-S7 격리 (삭제 X) — `qvest_legacy_boundary.md`

---

## Release Status (v6.4.0 → v7.2.1)

| Release | 일자 | 핵심 |
|---|---|---|
| ✅ **v6.4.0** | 2026-05-01 | Harness Kernel Stabilization. Sprint 0+1+2+3 9-phase. Codex 3중 장치 + 5 Cert + State Machine. |
| ✅ **v7.0.0** | 2026-05-02 | Hardening 7 sprint. "검증 가능한 소프트웨어 커널" — 우회 불가능한 실행 계약. 14 schema + sm_validated_advance + events.jsonl + qvest_observe + legacy_write_block. E2E 12/12 PASS. |
| ✅ **v7.0.1** | 2026-05-02 | 도훈 흠 4건 fix (synthetic cleanup / cert_rules data layer / harness_health hook 제거 / qvest_observe error masking). |
| ✅ **v7.1.0-lite** | 2026-05-02 | Solo Operator productivity 5 sprint (qvest_search + qvest_wt + INDEX.md + 3 workflow examples). 15 atomic commits. |
| ✅ **v7.2.0** | 2026-05-02 | v8 readiness gate 14-check write mode strict PASS + CHANGELOG + 3-day soak. |
| ✅ **v7.2.1** | 2026-05-02 | Memory Knowledge Hardening. Axiom JSON SOT (8 active) + memory_health 12-check (hard 6 + warn 6) + 15 readiness + auto-push hook. 도훈 audit 32 critical 모두 반영. |

**검증 (v7.2.1 strict run, 2026-05-02 17:22:55)**: 30/30 hooks PASS · 15/15 readiness · memory_health hard 0 · 19 JSON validate-schema PASS.

**v8 후속 (이연)**:
- v7.3: AX-002/003/004/005 advisory → block 강화 / AX-007/008 hook hard-block 검토 / timeline_e2e check 추가 (15→16)
- v7.x ext: SQLite event DB (현 JSONL fallback) / Daily brief Telegram SLO / Dashboard Shiny UI / legacy file 이동

Plan (v6.4): `/home/quant/.claude/plans/nifty-tickling-hinton.md`

---

## 변경 이력

- **v7.2.1** — 2026-05-02 Session 76 — Memory Knowledge Hardening release (도훈 audit 32 critical 반영). Axiom JSON SOT (active 8건) + memory_health 12-check + 15 readiness + auto-push Stop hook. CLAUDE.md Active Version 슬롯 v6.4 → v7.2.1 full sync (옵션 B), 신규 SOT `qvest_v7_2_1_sot.md` 발행. L-273~L-275.
- **v7.2.0** — 2026-05-02 — v8 readiness gate 14 check write mode strict PASS + CHANGELOG v7.2.0 entry + 3-day soak.
- **v7.1.0-lite** — 2026-05-02 — Solo Operator productivity (qvest_search + qvest_wt + INDEX.md + 3 examples). 15 atomic commits.
- **v7.0.1** — 2026-05-02 — Hardening patch (도훈 흠 4건 fix).
- **v7.0.0** — 2026-05-02 — Hardening 7 sprint release. "검증 가능한 소프트웨어 커널" 패러다임 (Codex 외부 평가 "SW 아키텍처 약함" → 우회 불가능한 실행 계약). L-272.
- **v6.4.0** — 2026-05-01 Session 75 — Harness Kernel Stabilization release. Sprint 0+1+2+3 9-phase. Codex 3중 장치 + 5 Cert + State Machine + dry-run 30/30 + E2E 10/10. L-269~L-271.
- **v6.4 Sprint 1** — 2026-05-01 Session 75 — Active SOT 단일화 + CLAUDE.md 경량화 (436 → ~270 lines) + skills/rules 8 신규.
- **v6.3.3** — 2026-05-01 — v6.0 Codex Critic Round 3중 장치 영구 정착 (L-269)
- **v6.3.2** — 2026-05-01 — Cert Auto-Issuance Paths 명문화 + Layer 4 deferred
- **v6.31** — 2026-04-28 — Charter v1.2 §10 Certification System
- **v6.0** — 2026-04-23 — QEPM 3-Agent WorkTask 도입
- **v5.5** — 2026-04-19 — v55 strict
- **v5.3** — 2026-04-13 — v53 TeamCreate + Hook 17종

상세: `.claude/commands/qvest.md` ## Version
