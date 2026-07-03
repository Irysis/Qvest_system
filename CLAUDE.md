# Quant Module Moltbot — Claude Code Instructions

## Active Version

**Qvest v8.1.0 — Opus 4.8-Native · 4-Mode 헌법 (RAMP 추가 2026-06-17) · 실측 거버넌스** (2026-06-05)

**계보**: v6.4.0 → v7.0.0 → v7.0.1 → v7.1.0-lite → v7.2.0 → v7.2.1 → v8.0.0 → **v8.1.0** (현재 active)
**Branch**: `main` (Qvest active — GitHub default)

**v8.1 핵심** (3-Mode 정립 + 실측-only + 모듈 자동흐름, 도훈 mandate 2026-06-05):
- **3-Mode 헌법**: alpha-search 제1원칙(**논문 완전 복제** + 유니버스 K200∪KQ150 고정 + 기간 2005~ 고정) · factor-rotation Lane3(모듈 국면배합, RCMA 등급무관 양방향) · Axiom **r7 원전 복원**(5축 boolean-AND + 3-mode 2-tier + INV-1~7)
- **실측-only 거버넌스**: measurement-graduation(real-computation 의무 · portfolio-α t forge-authoritative · oos_retention≥0.7·calmar≥0.64 HARD · DSR 다중검정스타일only · book-marginal ΔIR≥0.05). proxy 손계산 graduation 폐지
- **모듈 표준화 + 자동흐름**: `register_module` 공용계약(**contract_pass+backtested+frozen+hash/build/cost floor 필수, 등급은 무관**) · 계약 미충족 산출은 `module_quarantine` 보존 · `build_module_performance`는 FR input-floor allowlist 소비 · run_factor_rotation 신선도 자동인식 · ML/DPL register 다리(register_research_outputs) · **E2E 4축 배선 닫힘**(자본게이트 book confirm+실주문 2버튼만 수동)
- **KR 데이터 한계 reference**: value/BM 2002-08~ · M08_ResidMom 1995~ · factor DB 1990~ (`feedback-alpha-search-paper-replication`)
- **부팅 패치(v8.1)**: bootstrap에 RAWDATA K200/KQ150 컬럼 검증 + 데이터 캐시 존재·신선도 검증 추가
- **v8.0 흡수(retain)**: R+Python 1급 · SR 2.5 · agent effort(judge/gov xhigh) · axiom_context_inject · harness_perf_eval · artifact-naming
- **미완(후속)**: residual momentum 사이클 register/factor_analysis 디버깅 · WT_WT-* cleanup · axiom global 실가동

**★ Active SOT (단일 진실)**: `02_Infrastructure/docs/qvest_v8_1_sot.md` (v8.1 설계 SOT) + `qvest_v8_0_upgrade_plan.md` (v8.0 base 흡수, retain)
**전임 SOT (흡수됨)**: `02_Infrastructure/docs/qvest_v6_4_sot.md` (v6.4 base 흡수, read-only retain)
**Legacy boundary**: `02_Infrastructure/docs/qvest_legacy_boundary.md` (v55 / S0~S7 격리)

본 CLAUDE.md는 헌법만. 절차는 `.claude/skills/`, 룰은 2단(`코어 6 = .claude/rules/ autoload` + `확장 10 = 02_Infrastructure/docs/rules/ on-demand` — 아래 Rules 절), 강제는 `02_Infrastructure/hooks/`, 역할은 `.claude/agents/`.

---

## Active Modes (4-Mode — 각자 평가·자가발전, 도훈 mandate 2026-06-05 / RAMP 추가 2026-06-17)

Qvest = 독립 리서치 모드 4개 (lifecycle ①②생산 → ③④소비; 진입점은 아래 `## Active Entrypoints`).
**각 모드 = 자기 평가체계 + 자기 자가발전** (L-code → mode-local axiom `AX-<MODE>-*`, `02_Infrastructure/docs/rules/axiom-engine.md` v8.0 E2E 검증). **평가체계(산출물 채점)는 모드별 자율 — 통일 금지.** 공유하는 건 *평가가 아니라 토대*: ① 정직 라벨 (`metric_type` proxy/backtested) ② 자본 게이트 (`book_state` = governor 수동+도훈) ③ **교차검증 global 공리** (자가발전 결과 중 backtested + r7 5축 + AX-008 + 도훈 confirm 통과분만 `AX-NNN`; 공유 *사실*이지 평가 통일 아님 — proxy·한 모드 loose 평가는 INV-1로 global 차단). SOT: `02_Infrastructure/docs/qvest_modes_sot.md`.

**① QEPM 모드 경로** (신호-only 알파 정밀 검증·편입):
```
WorkTask → alpha-research → risk-research → optimizer-research → forge → judge → governor
```
각 agent spawn 시 **Self-Adversarial Challenge 의무** (v8.2 — Codex Round 제거, Opus 4.8 자체 적대검증: finalize 직전 약점 자가제기 → `challenge_note.md` 기록 → final. AX-008 3-source 중 1개).
**② alpha-search · ③ factor-rotation**: 각자 경량 경로 (각 skill + `## Active Entrypoints`).
**④ RAMP** (K-RAMP, 2026-06-17): 기존 전략풀 *소비* → 순수팩터 추출(통계 잠재팩터+FWL) → 팩터군 → M-code(역할 분업) → 리스크매니저 → 인베스터 에이전트 팩터배분. 거버넌스-우선 Gate 0~11 + CCS 13-score. 재귀 자가발전=Axiom 엔진 4번째 모드(modecode RAMP, backtested). 룰 `02_Infrastructure/docs/rules/ramp.md`, SOT `00_Lawbook/K_RAMP/`. governor 정지(자본 수동).

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

- **R + Python 공히 1급 허용** (v8.0, 2026-05-29 도훈 mandate — 기존 "R only" 폐지). 언어 선택은 도구적: R(tidyverse + data.table) / Python(venv `qvest_ml`). **PIT C1~C15 / Backtest Contract v1.0 / Production Constraints / lockbox-scope는 언어 무관 동일 적용.** Python backtest는 검증된 표준함수만(자체합성 금지) + 10-component `bt_result`는 R `build_bt_result` bridge 경유. 상세: `.claude/rules/python-policy.md`
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

**4 리서치 모드** (도훈 mandate): ① **QEPM**(6-에이전트 풀파이프라인, `/worktask`) — 모듈 생산 · ② **alpha-search**(논문 1편 경량 검증, `/alpha-search`) — 모듈 생산 · ③ **factor-rotation**(국면조건부 모듈 배합 meta-layer, `/factor-rotation`) — 모듈 *소비* · ④ **RAMP**(K-RAMP, 기존 전략풀에서 순수팩터→팩터군→M-code→인베스터 에이전트 팩터배분, `/ramp`) — 풀 *소비* + 거버넌스-우선 Gate 0~11. ②③ 산출물은 `register_module()` 경유 표준화되며, 계약 floor 통과분만 ③④가 소비한다.

| Command | 용도 |
|---|---|
| `/qvest` | Session startup + bootstrap + status |
| `/worktask` | WorkTask 생성 + 상태 + 전이 + admission (QEPM 모드) |
| `/alpha-search` | 논문/가설 경량 백테 검증 (alpha-search 모드) |
| `/factor-rotation <track>` | 국면조건부 모듈 배합 FR_XXXX (factor-rotation 모드. track∈{regime-engine, allocation}) |
| `/ramp <stage>` | K-RAMP 팩터배분 운용체계 RAMP_XXXX (RAMP 모드. Gate 0~11·CCS 13-score·실측-only·governor 정지. 룰 `docs/rules/ramp.md`) |

---

## Absolute Rules (1줄 reference)

- **PIT C1~C15**: `.claude/rules/pit.md`
- **Lockbox / Frozen Alpha Scope**: `02_Infrastructure/docs/rules/lockbox-scope.md` (정규 리서치 alpha/risk/optimizer만 적용. forge/monitoring/Q-Lead/execution = 폐기. 도훈 mandate 2026-05-09)
- **Self-Adversarial Challenge (Codex Round 대체)**: `02_Infrastructure/docs/rules/codex-round.md` (v8.2 — 외부 Codex Round 제거, 메인 Opus 4.8 자체 적대검증으로 finalize 직전 약점 자가제기 + `challenge_note.md` 기록. AX-008 3-source 중 1개)
- **Backtest Result Contract v1.0**: `.claude/rules/backtest-contract.md` (PerformanceAnalytics 표준 함수만)
- **Measurement Integrity + Graduation 허들 (v8.x)**: `.claude/rules/measurement-graduation.md` ⭐ (위반 = AX-002 동급. 실측 처리(canonical_screen_bt/build_bt_result + metric_type 라벨, proxy 손계산 금지) / portfolio-alpha t = forge-authoritative(NW lag-3) / graduation severity: PORT_t 2.95·DSR hard, rank-IC계열 advisory / admission = book-marginal ΔIR≥0.05 / DPL 구성레이어. E2E: FLOW proxy 3.55→forge 2.35)
- **Axiom Engine 2-Tier (v8.0)**: `02_Infrastructure/docs/rules/axiom-engine.md` ⭐ (원전 r7 복원 + 3-mode 2-tier(AS proxy→mode-local / QPM·FR backtested→global) + INV-1~7. mode-local AX-&lt;MODE&gt;-NNN / global AX-NNN. negative=provisional failure-ledger. 자동승격=documented·hook block은 주간 confirm. E2E 10/10. 위반=AX-002 동급)
- **Qvest 답변 원칙 (8원칙 + 5금지)**: `.claude/rules/answer-principles.md` (위반 = AX-002 동급)
- **Telegram v6 SOT**: `.claude/skills/qvest-telegram/SKILL.md` (단일 규칙. `tg_agent_brief()` 진입점, 약어 풀이 자동, 표준 4섹션 권장)
- **Caching Discipline**: `02_Infrastructure/docs/rules/caching.md` (Anthropic 5분 TTL, ScheduleWakeup ≤270s)
- **Harness Engineering (Hooks Tier 1~6)**: `02_Infrastructure/docs/rules/harness.md`
- **Factor DB + Forge 자원**: `02_Infrastructure/docs/rules/factor-db.md` (C13~C15 + load_month_factors 경유)
- **Axioms (AX-000~008)**: `.claude/rules/axioms.md`
- **Research Philosophy (7 QEPM Modern Trends)**: `02_Infrastructure/docs/rules/research_philosophy.md` ⭐ (Charter-level SOT `02_Infrastructure/docs/qvest_research_philosophy.md` v1.0 2026-05-14. Factor Zoo 축소 / Cost-aware / Uncertainty-aware / Direct Portfolio / Crowding / Implementation / Attribution. 분기별 review + trigger-based 보강. 위반 = AX-002 동급)

---

## Project Goals

### 제1목표: 미래참조 없는 전략 설계 (PIT 완전 준수) — 성과보다 우선

### 제2목표: SR 2.5+ / CAGR 16%+ / MDD <25% (SR 2.0→2.5 상향, 2026-05-29 도훈 mandate — KR 구조적 상승 반영)

도달 경로 (2026-07-03 도훈 confirm, 아키텍처 감사 — measurement-graduation §6 정합): ① overlay 정교화(주레버, 실증 유일) ② 잔차-직교 sleeve 스태킹(PORT_t 통과분만) ③ 비-return 신규 원천(DART insider 등). 신규 standalone 팩터 사냥은 16/16 FAIL posterior로 최후순위.

### 제약 (방침)

- 기존 인프라 극한 활용 (Factor DB / DART / FRED / ECOS / QuantiWise)
- 크로스마켓 / 대체데이터 금지
- 확장 허용: ML / 수리통계 / 물리학 / 카오스이론

---

## Production Constraints

| 제약 | 값 |
|---|---|
| 종목수 | max 25 (hook 강제, 도훈 mandate 2026-05-29 20→25) |
| 유동성 | 20일 평균 거래대금 ≥ 2e8 KRW (LIQ_THRESHOLD) |
| Long-only | weights ≥ 0 |
| Weight bounds | [0, 0.20] |
| Σw | = 1 (absolute) |
| Universe | KOSPI200 ∪ KOSDAQ150 |
| Transaction cost | 15bps one-way (cost_model_version v2.4_kr_retail_15bps — delta-based, 종목별 Δ보유명목 절대값에 레그당 과금. 2026-06-11 도훈 confirm. 구 v2.3 flat 기록과 비교 시 라벨 확인) |
| PIT | C1~C15 전체 (`.claude/rules/pit.md`) |

---

## Key Paths

- Project root: `C:/Users/99922/OneDrive/Quant_Module_Moltbot/` (OneDrive canonical, 도훈 mandate 2026-06-10. Git Bash: `/c/Users/99922/OneDrive/Quant_Module_Moltbot`)
- Infrastructure: `02_Infrastructure/` (config.R + 12 subdirs: data/ factor_db/ regime/ validation/ hooks/ agents/ telegram/ reports/ memory/ portfolio/ ops/ docs/ worktask/ contracts/ tools/ axiom/ prompts/)
- Strategies: `04_Research/strategies/STR_XXX_name/` (legacy retain)
- WT mailbox: `qepm/mailbox/worktask/{WT_ID}/`
- Stage artifacts: `stage_artifacts/WT_{ID}/`
- Memory: `C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory/MEMORY.md`
- Env (User scope 영구): `QM_ROOT` + `QVEST_PY` + `~/.Renviron` 동일값 (경로 이전 시 이 3곳 + config.R 후보만 갱신)
- 산출물 저장 위치 규칙 (저장 4원칙 + 루트 13항목 고정 + retention): `02_Infrastructure/docs/rules/artifact-storage.md`

---

## R Execution Pattern

- `source('run_all.R')` pattern only (한글 path encoding 회피, NOT `--file=`)
- `cd` to strategy directory first, then `Rscript -e 'source("run_all.R")'`

---

## Multi-Agent Summary (v8.1 active 6 + 4 ondemand)

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

- **AX-000** [IMMUTABLE]: 한계는 법칙 아닌 방법의 한계 — 모든 목표는 엄밀함·창의성·반복으로 달성 가능. **3~4회 실패로 한계/dead-end 단정 금지**; 모든 수단 소진 또는 도훈 중단 지시까지 탐색 계속. 실측·PIT 결과는 정직 보고하되 탐색 중단 근거 아님 (2026-06-21 개정)
- **AX-001 v2** [IMMUTABLE]: 방어형 팩터 조건부 평가 (crisis_alpha + Core 대비 MDD + bad/normal IC ratio)
- **AX-002** [IMMUTABLE]: 하네스 내 성과만 유효. 프로세스 우회 = 미래참조
- **AX-003** [empirical]: KR value EP_STANDALONE 실패. L-132/135
- **AX-004** [methodological]: KR quality_profitability single-signal long-only 실패
- **AX-005 v1.2** [methodological]: KR defense top20 long-only 실패. EXCLUSION necessary not sufficient
- **AX-007** [methodological]: single-sleeve top20 mechanism break. 예외 4종 (multi-sleeve / long-short / 50+ / ML sizing)
- **AX-008** [process]: Verification Triangulation (Forge + Self-Adversarial + Architect 2/3 PASS)

위반 시 즉시 중단. Hook `axiom_enforcement_hook.sh` 자동 차단.

---

## Q-Lead 역할 경계 (Level 0)

- ✅ 진단 / 지시 / 모니터링 / 결과 수집 / telegram 보고
- ✅ WT 생성 + 6 agent spawn orchestration
- ❌ 직접 Rscript 실행 / 백테 / factor_engine 수정 → Forge / Alpha agent 위임
- ❌ weight 결정 / 공분산 계산 → Optimizer / Risk agent 위임
- ❌ Alpha/Risk/Opt 경계 침범 (역할경계·lockbox 훅은 agent marker 존재 시에만 발화 — marker 자동 기록 메커니즘 부재. 실제 방어선 = R 계약(essence_score/registry_writer) + 게이트급 훅 + 수동 confirm. 2026-07-03 도훈 confirm, 아키텍처 감사)

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
| `/alpha-search` · `/factor-rotation` · `/ramp` | 모드 진입 (Active Entrypoints 표 참조) |
| `/qlead` | Q-Lead session dashboard |
| (legacy retain) | `/forge` `/judge` `/governor` `/launch-team` — v53/v6.4 호환 보존, 신규 사용 금지. `/scout`은 파일 부재로 표에서 제거 (2026-06-10) |

---

## Skills + Rules

### Skills (`.claude/skills/`) — domain-scoped

| Skill | 용도 |
|---|---|
| `qvest-worktask` | WorkTask lifecycle 절차 (CLAUDE.md에서 이동) |
| `qvest-telegram` | 텔레그램 단일 SOT (v6) — 양식 / 약어 풀이 / Hook 정책 / caller 예시 통합 |
| (Phase 9 추가 예정) | qvest-hook-debug / qvest-cert-paths |

### Rules — 2단 구조 (2026-06-10 P2 다이어트: autoload 16→6)

**코어 6 (`.claude/rules/` — 매 세션 autoload)**: `pit.md` (C1~C15) · `axioms.md` (AX-000~008) · `answer-principles.md` (8원칙+5금지) · `backtest-contract.md` (bt_result 10-component) · `measurement-graduation.md` (게이트 2계층+HARD) · `python-policy.md` (R/Python 1급)

**확장 10 (`02_Infrastructure/docs/rules/` — 해당 작업 시 on-demand Read, 효력 동일. v8.2 codex-round.md = DEPRECATED 스텁)**:

| Rule | 로드 시점 |
|---|---|
| `harness.md` | hook 디버깅 시 (qvest-hook-debug skill) |
| `axiom-engine.md` | axiom 승격/주간 파이프라인 작업 시 |
| `factor-rotation.md` | factor-rotation 모드 진입 시 (SKILL이 참조) |
| `lockbox-scope.md` | lockbox 판단 시 (pit.md에 요약 잔존) |
| `factor-db.md` | factor DB 직접 작업 시 |
| `data_table_shift_convention.md` | shift/forward label 작성 시 (pit.md C-체크 연계) |
| `artifact-naming.md` | WT 핸드오프 파일 생성 시 |
| `artifact-storage.md` | 산출물 저장 위치 판단 시 |
| `caching.md` | 토큰/캐시 운영 판단 시 |
| `research_philosophy.md` | 분기 review 시 (본문 SOT는 docs/qvest_research_philosophy.md) |

---

## Multi-Agent Team v53 (legacy — 2026-06-10 hook 등록 해제)

v53 TeamCreate 패턴은 v8.1에서 Agent tool spawn으로 대체됨. TeammateIdle/TaskCompleted hook은 settings.json에서 등록 해제 (스크립트는 FS retain — `02_Infrastructure/docs/rules/harness.md` 참조). tmux rc listener는 v8.0에서 폐지.

상세: `.claude/skills/qvest-worktask/SKILL.md` Section 7.

---

## Safety Rules

- NEVER modify `05_Production/` (promote_to_production() 만 예외)
- `01_Literature/` read-only
- All output to `04_Research/` and `06_Registry/`
- 기존 stage_artifacts/ + 178+ STR 결과 보존
- legacy v55/S0-S7 격리 (삭제 X) — `qvest_legacy_boundary.md`

---

## Release Status + 변경 이력

**SOT 분리 (2026-06-10 P2 다이어트)**: 버전 연혁·릴리스 상세는 `02_Infrastructure/docs/CHANGELOG_constitution.md` — CLAUDE.md는 현행 헌법만 담는다.
- 현행: **v8.2** (2026-06-30 도훈 mandate — Codex Critic Round 제거, Opus 4.8 자체 적대검증 대체. 훅 3개 archive · AX-008 Codex→Self-Adversarial 3-source 2/3 불변 · state_transitions codex required 제거 · qvest-codex-round skill 삭제 · codex-round.md DEPRECATED. 별개 S0/RAMP Codex 유지)
- 이전: **v8.1.1** (2026-06-10 완벽 수리 + P2 구조 개편 — hook 47/47 부활(당시 기준) · OneDrive canonical · 게이트 2계층 · rules autoload 6 코어). **현행 hook 등록 = settings.json 45 distinct .sh** (v8.2 codex 2건 해제 반영, 2026-07-03 실측 — `harness.md` 정합)
- 최근 검증: (v8.2) router selftest PASS · hook_e2e_battery 10/11(codex 케이스 제거, 잔여 FAIL=python3 환경) · health HARD-fail 0 (2026-06-30) / (v8.1.1) hook 차단 4종 실증 · readiness pass 12/fail 0 · bootstrap BOOT_FAILS=0 (2026-06-10)
