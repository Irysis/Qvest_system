# QEPM × Claude Code Agent Teams Setup Ticket
# Claude Code에 이 파일 + Lawbook v1.4.2를 함께 전달하여 실행

> **사용법**: 기존 QEPM 프로젝트가 있는 Claude Code 세션에서
> 이 파일과 Lawbook을 함께 전달하고 "이 티켓대로 셋업해줘"라고 요청한다.
> Phase 0부터 순서대로 진행한다.

---

# 프로젝트 컨텍스트

## 목표
기존 QEPM 퀀트 투자 시스템(R 기반)을 Claude Code Agent Teams 멀티에이전트 프레임워크 위에 올려서,
리서치 → 백테스트 → 심사 → 앙상블 → 리밸런싱 → 사후감시를 자동화한다.

## 아키텍처 원칙

1. **Claude Code Agent Teams로 멀티에이전트 오케스트레이션을 구현한다**
   - Team Lead(Manager)가 작업을 분배하고, Teammates가 병렬/순차로 실행
   - 에이전트 간 소통은 Mailbox 메시징 (P2P 직접 통신 가능)
   - CLAUDE.md가 모든 에이전트의 공유 컨텍스트
   - Claude API를 직접 호출하는 R 코드는 만들지 않는다

2. **R 코드는 순수하게 퀀트 연산만 담당한다**
   - 백테스트, 팩터 모델, 최적화, 통계 검정, KPI 계산
   - 이 함수들은 프로젝트 내 R 스크립트로 존재하며, 에이전트가 Bash로 호출

3. **기존 코드를 최대한 재사용한다**
   - 현재 프로젝트 폴더의 R 스크립트, MEMORY.md, 교훈, 데이터를 그대로 활용
   - 새로 만드는 건 Agent Teams 구조(CLAUDE.md, spawn prompts, task patterns)와 Memory Pipeline뿐

4. **파일 기반 coordination**
   - 에이전트 간 산출물 교환은 공유 파일(memory/, registry/, artifacts/)을 통해 이루어진다
   - Mailbox 메시징은 조율/피드백용, 대용량 데이터는 파일로

5. **Lawbook v1.4.2가 헌법이다**
   - 목적함수 우선순위: Validity > Implementability > Robustness > Performance > Novelty
   - Hard Law / Soft Prior 구분을 CLAUDE.md 에이전트 정의에 반영한다

6. **전원 Opus 4.6 확장 사고**
   - Agent Teams는 모든 teammate이 Team Lead의 모델을 상속한다
   - 따라서 16개 에이전트 전원이 Opus 4.6 확장 사고로 동작한다
   - 비용이 높지만, 모든 판단 지점에서 최고 품질의 추론이 가능하다

7. **세션 단위 운용**
   - Agent Teams는 세션 단위로 spawn/shutdown된다 (상시 가동이 아님)
   - 영구기관 루프는 "반복 세션 실행" 패턴으로 구현한다
   - 각 세션 시작 시 CLAUDE.md + memory/ + registry/에서 상태를 복원한다

## 통신 패턴: Hybrid (파이프라인 + 공유 파일 + 사용자 의사결정)

```
[도훈] ←── Telegram DM ──→ [Manager] ──→ Telegram Channel (브로드캐스트)
                              │                    │
                              │          시스템 산출물 자동 게시
                              │          (브리핑/알림/결과/차트)
    ┌─────── 연구 파이프라인 ──┤
    │                         │
    │  ResearchOps(큐선택)    │
    │       ↓                 │
    │  ResearchOps → Researcher(수집지시) → ResearchOps(검증)
    │       ↓                 │
    │  Strategist(설계+백테스트)│
    │       ↓                 │
    │  AlphaLab(fast filter)  │
    │       ↓                 │
    │  Auditor(심사+통계검증)  │
    │                         │
    ├─────── 월간 리밸 ────────┤
    │                         │
    │  Steward(데이터최신화)   │
    │       ↓                 │
    │  Features(피처 업데이트) │
    │       ↓                 │
    │  Regime(국면판단)        │
    │       ↓                 │
    │  Valuation(밸류에이션)   │
    │       ↓                 │
    │  Blender(후보군 3~5개)   │
    │       ↓                 │
    │  Auditor(후보별 검증)    │
    │       ↓                 │
    │  Manager(브리핑) → [사용자 /select] → Portfolio(집행)
    │                         │
    ├─────── 사후 감시 ────────┤
    │                         │
    │  Tower(이론적 사후감시)  │
    │       ↓                 │
    │  Monitor(성과 분해)      │
    │       ↓                 │
    │  → R6 Post-Trade Memory │
    │                         │
    ├─── 공유 자원 (파일) ─────┤
    │  memory/  registry/     │
    │  Lawbook  artifacts/    │
    │                         │
    └─── 아이디어 경로 ────────┘
       Catalyst → Compiler → ResearchOps(큐 등록)
       ResearchOps → Researcher(수집 지시) → ResearchOps(검증) → Strategist
```

---

# 에이전트 목록 (16개)

> **모델**: Agent Teams에서는 모든 teammate이 Team Lead의 모델을 상속한다.
> Team Lead(manager)를 Opus 4.6 확장으로 실행하므로, **전원 Opus 4.6 확장 사고**로 동작한다.
> 역할 분류는 유지하되, 모델 차등 배정은 Agent Teams 제약으로 불가.

## 핵심 체인 (4개 — 동적 포트폴리오 의사결정)

| ID | 이름 | Lawbook 장 | 역할 |
|---|---|---|---|
| `strategist` | Factor Strategy Builder | 01,04,14 | 전략 설계, 국면별 재료 확보, Failure Intelligence |
| `auditor` | Risk Auditor | 06,07,22 | Gate 0~5 심사, 가짜 알파 탐지, 통계 검증 |
| `regime` | Regime Modeler | 08 | 국면 분류, 앙상블 판단, 과적합 방지 — 동적 포트폴리오의 조타장치 |
| `blender` | Blender Agent | 08,12,20 | 국면 기반 동적 배분, overlay stack, LOO |

## 연구 방향 + 창의성 + 지식 수집 (3개)

| ID | 이름 | Lawbook 장 | 역할 |
|---|---|---|---|
| `researchops` | ResearchOps | 13,16 | VoE 다차원 판단, 4개 트랙 배분, memory-driven 우선순위 |
| `catalyst` | Catalyst | 23 | cross-domain 창의적 연결, 메커니즘 추출 |
| `researcher` | Idea Researcher | 01 | 논문/칼럼 수집, 학술 근거 요약, 프록시 제안 → ResearchOps 경유 제공 |

## 관리 + 데이터 (3개)

| ID | 이름 | Lawbook 장 | 역할 |
|---|---|---|---|
| `manager` | Manager AI (Team Lead) | 00,01,09,13 | **Team Lead** — 오케스트레이터, 영구기관, 브리핑, 정책, 사용자 소통 |
| `compiler` | Idea Compiler | 23 | 아이디어→실험 계약서 변환, PIT/구현가능성 판단 |
| `steward` | Data Steward | 02 | 데이터 수집/최신화/QC/스냅샷 — 사용자 데이터 우선 + API 보충 |

## 경량/규칙 기반 (6개)

| ID | 이름 | Lawbook 장 | 역할 |
|---|---|---|---|
| `tower` | Control Tower | 21 | 시장 데이터 기반 이론적 사후 감시, 팩터 환경 변화 감지, WATCHLIST |
| `valuation` | Valuation Agent | 11 | 밸류에이션 측정 (R 스크립트가 계산) |
| `features` | Feature Engineer | 03 | 피처 계약, PIT 검증 |
| `portfolio` | Portfolio Manager | 09 | 사용자 선택 후 트레이드리스트 생성, 주문 분할, 집행안 |
| `alphalab` | Alpha Lab Gatekeeper | 18 | Stage 0 cheap reject |
| `monitor` | Performance Monitor | 09 | 성과 분해, 피드백 |

---

# 디렉토리 구조

## 최종 목표 구조

```
~/.claude-agent-teams/                          # Claude Code Agent Teams 루트
├── settings.json                     # 글로벌 설정 (에이전트, 바인딩, 채널)
├── skills/                           # 공유 스킬 (모든 에이전트 접근 가능)
│   ├── qepm-backtest/
│   │   ├── main.R (진입점)
│   │   └── run.sh                    # Rscript 래퍼
│   ├── qepm-factor-model/
│   │   ├── main.R (진입점)
│   │   └── run.sh
│   ├── qepm-optimize/
│   │   ├── main.R (진입점)
│   │   └── run.sh
│   ├── qepm-stat-defense/
│   │   ├── main.R (진입점)
│   │   └── run.sh
│   ├── qepm-memory/
│   │   ├── main.R (진입점)
│   │   └── run.sh                    # R0~R6 읽기/쓰기/규칙기반 증류
│   ├── qepm-registry/
│   │   ├── main.R (진입점)
│   │   └── run.sh                    # 실험/전략/패밀리 CRUD
│   ├── qepm-kpi/
│   │   ├── main.R (진입점)
│   │   └── run.sh                    # Sharpe0, ES99, MDD 등
│   └── qepm-lawbook/
│       ├── main.R (진입점)
│       └── run.sh                    # Lawbook .md 검색/로드
│
├── agents/manager/
│   ├── spawn_prompt.md                # Team Lead spawn prompt
│   ├── AGENTS.md                     # 하위 에이전트 목록 + 위임 규칙
│   ├── USER.md                       # 사용자 선호 (도훈 프로필)
│   └── notes/
│       ├── backlog.json
│       └── state.json                # 영구기관 상태
│
├── agents/strategist/
│   ├── spawn_prompt.md
│   ├── AGENTS.md
│   └── notes/
│       └── failure_patterns/         # Failure Intelligence Loop
│
├── agents/auditor/
│   ├── spawn_prompt.md
│   ├── AGENTS.md
│   └── notes/
│       └── gate_templates/           # Gate 체크리스트
│
├── agents/researchops/
│   ├── spawn_prompt.md
│   ├── AGENTS.md
│   └── notes/
│       ├── priority_log.json
│       └── family_accounting.json
│
├── agents/blender/
│   ├── spawn_prompt.md
│   ├── AGENTS.md
│   └── notes/
│       └── ensemble_history/
│
├── agents/tower/
│   ├── spawn_prompt.md
│   └── notes/
│       └── drift_log/
│
├── agents/valuation/
│   ├── spawn_prompt.md
│   └── notes/
│
├── agents/regime/
│   ├── spawn_prompt.md
│   └── notes/
│
├── agents/compiler/
│   ├── spawn_prompt.md
│   └── notes/
│
├── agents/steward/
│   ├── spawn_prompt.md
│   └── notes/
│       ├── qc_reports/
│       └── collection_logs/        # 데이터 수집 로그
│
├── agents/features/
│   ├── spawn_prompt.md
│   └── notes/
│
├── agents/catalyst/
│   ├── spawn_prompt.md
│   └── notes/
│       ├── idea_backlog/
│       └── idea_feedback/          # 실패/반려 피드백 축적
│
├── agents/researcher/
│   ├── spawn_prompt.md
│   └── notes/
│       ├── paper_summaries/        # 수집한 논문/칼럼 요약
│       └── research_briefs/        # strategist에게 제공한 리서치 브리프
│
├── agents/portfolio/
│   ├── spawn_prompt.md
│   └── notes/
│
├── agents/alphalab/
│   ├── spawn_prompt.md
│   └── notes/
│
└── agents/monitor/
    ├── spawn_prompt.md
    └── notes/

{PROJECT_ROOT}/                       # 기존 QEPM 프로젝트 폴더 (변경 최소화)
├── R/                                # 기존 R 코드 (그대로 유지)
│   ├── backtest/                     # 백테스트 엔진
│   ├── factor/                       # 팩터 모델
│   ├── optimize/                     # 포트폴리오 최적화
│   └── ...
├── data/                             # 기존 데이터 (그대로 유지)
├── memory/                           # 신규: Memory Pipeline 저장소
│   ├── raw_artifacts/                # R0
│   ├── episodes/                     # R1 experiment digests
│   ├── families/                     # R2 family/mechanism memory
│   ├── evidence/                     # R3 statistical evidence
│   ├── regime_payoff/                # R4
│   ├── portfolio_policy/             # R5
│   ├── post_trade/                   # R6
│   └── lessons/                      # L-### lessons
├── registry/                         # 신규: 실험/전략/패밀리 레지스트리
│   ├── experiments.json
│   ├── strategies.json
│   ├── families.json
│   └── backlog.json
├── artifacts/                        # 신규: 태스크별 산출물
├── lawbook/                          # Lawbook .md 파일들
├── config/
│   └── qepm_config.md             # QEPM 전용 설정
├── CLAUDE.md                         # 기존 (유지, Claude Code Agent Teams과 공존)
└── MEMORY.md                         # 기존 (유지, migration 후 점진적 이전)
```

---

# Phase 0: Claude Code Agent Teams 활성화 + 프로젝트 구조 생성

## 목표
Claude Code에서 Agent Teams 실험 기능을 활성화하고,
CLAUDE.md에 16개 에이전트 정의를 작성하며,
공유 디렉토리(memory/, registry/, artifacts/, lawbook/)를 구축한다.

## Agent Teams 핵심 아키텍처

```
┌────────────────────────────────────────────────┐
│ Claude Code Session (Opus 4.6 Extended)        │
│                                                │
│  Team Lead: Manager                            │
│    ├── Teammate: strategist (spawn prompt)     │
│    ├── Teammate: auditor (spawn prompt)        │
│    ├── Teammate: regime (spawn prompt)         │
│    ├── Teammate: blender (spawn prompt)        │
│    ├── ... (15 teammates total)                │
│    │                                           │
│    ├── Shared Task List (~/.claude/tasks/)      │
│    ├── Mailbox (P2P messaging)                 │
│    └── CLAUDE.md (공유 컨텍스트)                │
│                                                │
│  공유 파일:                                     │
│    memory/ → 기억증류 R0~R6                     │
│    registry/ → 실험/전략/family 레지스트리       │
│    artifacts/ → 산출물                          │
│    R/skills/ → 퀀트 연산 R 스크립트              │
└────────────────────────────────────────────────┘
```

## 구현 절차

### 0-1. Agent Teams 활성화

```bash
# Claude Code 버전 확인 (v2.1.32 이상 필요)
claude --version

# settings.json에 Agent Teams 실험 기능 활성화
# 프로젝트 루트에 .claude/settings.json 생성
mkdir -p .claude
cat > .claude/settings.json << 'EOF'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "Bash(Rscript *)",
      "Bash(cd * && Rscript *)",
      "Bash(cat *)",
      "Bash(mkdir *)",
      "Bash(ls *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(wc *)",
      "Bash(grep *)"
    ]
  }
}
EOF
```

### 0-2. CLAUDE.md 생성 (에이전트 공유 컨텍스트)

> **핵심**: CLAUDE.md는 모든 teammate이 spawn 시 자동으로 로드하는 공유 컨텍스트다.
> 에이전트 정의, 프로젝트 규칙, 파이프라인 구조를 여기에 넣는다.

```markdown
# QEPM Multi-Agent System

## 프로젝트 목표
국면 기반 동적 팩터 포트폴리오 관리 시스템.
목표: CAGR 16%+, Sharpe 2+, MDD <25%, FF3/Carhart4/FF5 + FMB 통계 검증 통과.

## 에이전트 역할 정의

### manager (Team Lead)
- 역할: 오케스트레이터, 영구기관, 브리핑, 사용자 소통
- Lawbook: 00, 01, 09, 13장
- 다른 에이전트에 작업 위임. 직접 퀀트 연산하지 않음.

### strategist
- 역할: 팩터 전략 설계 + 실험 계약서 + 백테스트
- Lawbook: 01, 04, 14장
- 확장 사고로 가설→메커니즘→반증→construction 설계

### auditor
- 역할: Gate 0~5 심사, 가짜 알파 탐지, 통계 검증
- Lawbook: 06, 07, 22장
- 확장 사고로 알파 진위 판별. qepm-diversity로 Gate 5 수치 강제.

### regime
- 역할: 국면 분류, 앙상블 판단, 과적합 방지
- Lawbook: 08장
- 동적 포트폴리오의 조타장치. 확장 사고 활용.

### blender
- 역할: 국면 기반 동적 배분, overlay stack, LOO
- Lawbook: 08, 12, 20장
- 후보 포트폴리오 3~5개 생성. 확장 사고 활용.

### researchops
- 역할: 연구 우선순위, 4개 Track 배분, memory-driven queue
- Lawbook: 13, 16장
- researcher에 수집 지시, 결과 검증 후 strategist에 전달.

### catalyst
- 역할: cross-domain 창의적 연결
- Lawbook: 23장
- idea_feedback/ 과거 피드백 필수 참조.

### researcher
- 역할: 논문/칼럼 수집, 학술 근거 요약
- Lawbook: 01장
- ResearchOps 지시에 따라서만 수집. 독립 행동 금지.

### compiler
- 역할: 아이디어→실험 계약서 변환, 데이터 가용성 3단계 평가
- Lawbook: 23장

### steward
- 역할: 데이터 수집/최신화/QC/스냅샷
- Lawbook: 02장
- 사용자 업데이트 우선 → API 보충 → L0~L3 파이프라인.

### tower
- 역할: 시장 데이터 기반 이론적 사후 감시
- Lawbook: 21장
- 증권사 API 연동 금지 (사용자 명시 요청 전까지).

### valuation
- 역할: 밸류에이션 측정
- Lawbook: 11장

### features
- 역할: 피처 계약, PIT 검증
- Lawbook: 03장

### portfolio
- 역할: 사용자 선택 후 트레이드리스트 생성
- Lawbook: 09장

### alphalab
- 역할: Stage 0 cheap reject
- Lawbook: 18장

### monitor
- 역할: 이론적 성과 분해, 원인별 피드백
- Lawbook: 09장

## 목적함수 우선순위 (위반 불가)
1. Validity > 2. Implementability > 3. Robustness > 4. Performance > 5. Novelty

## 핵심 규칙
- 시스템은 후보군을 브리핑. 최종 포트폴리오 결정은 사용자.
- 증권사 API 연동은 사용자 명시 요청 시에만. 자의적 판단 금지.
- PIT(Point-in-Time) 준수 필수. 미래 데이터 사용 금지.
- 기존 R 코드 수정 금지. 래퍼만 생성.

## R 스크립트 실행
퀀트 연산은 R/skills/ 디렉토리의 R 스크립트를 Bash로 호출:
  Rscript R/skills/{skill_name}/main.R --input {input.json} --output {output.json}

## 파일 구조
- memory/ : 기억증류 R0~R6
- registry/ : 실험/전략/family JSON
- artifacts/ : 태스크별 산출물
- R/skills/ : 퀀트 연산 R 스크립트 14개
- lawbook/ : Lawbook v1.4.2 .md 파일
- config/ : 설정 파일 (YAML/JSON)
- agents/ : 에이전트별 노트/피드백 디렉토리
```

### 0-3. 프로젝트 디렉토리 구조 생성

```bash
# Memory Pipeline (25장)
mkdir -p memory/{raw_artifacts,episodes,families,evidence,regime_payoff,portfolio_policy,post_trade,lessons}

# Registry (15/16/17장)
mkdir -p registry
echo '[]' > registry/experiments.json
echo '{}' > registry/strategies.json
echo '{}' > registry/families.json
echo '[]' > registry/backlog.json

# Artifacts
mkdir -p artifacts

# R Skills (14개)
mkdir -p R/skills/{qepm-backtest,qepm-factor-model,qepm-optimize,qepm-stat-defense,qepm-kpi,qepm-memory,qepm-registry,qepm-lawbook,qepm-diversity,qepm-idea-pipeline,qepm-regime,qepm-datalake,qepm-research-collector,qepm-briefing}

# Lawbook
mkdir -p lawbook
# Lawbook .md 파일들을 lawbook/ 디렉토리에 복사

# Config
mkdir -p config

# Agent Notes
mkdir -p agents/{catalyst/{idea_backlog,idea_feedback},researcher/{paper_summaries,research_briefs},steward/collection_logs,monitoring}

# Task Patterns (워크플로우 정의)
mkdir -p .claude/task-patterns
```

### 0-4. QEPM 설정 파일 (`config/qepm_config.md`)

```yaml
project:
  name: "QEPM MoltBot"
  version: "1.4.2"
  market: "KR"
  language: "R"
  rebalance_freq: "monthly"
  benchmark: "KOSPI200_TR"

agent_teams:
  model: "opus"  # 전원 Opus 4.6 확장 사고
  display_mode: "tmux"  # 또는 "in-process"
  enable_extended_thinking: true

telegram:
  dm_bot_token: "YOUR_BOT_TOKEN"
  channel_id: "YOUR_CHANNEL_ID"
  user_id: "YOUR_TELEGRAM_ID"

kpi:
  primary_sharpe: "Sharpe0_m_ann"
  primary_tail: "ES99_m"
  benchmark: "KOSPI200_TR"
```

### 0-5. 기존 코드 연결 (필요 시)

```bash
# 기존 몰트봇 R 코드가 별도 디렉토리에 있으면 심볼릭 링크
# ln -s /path/to/existing/R/code R/existing
# Gap Analysis에서 기존 함수 위치를 파악한 뒤 결정
```

## 산출물
- `.claude/settings.json` (Agent Teams 활성화)
- `CLAUDE.md` (16개 에이전트 정의 + 프로젝트 규칙)
- `memory/` 하위 8개 디렉토리
- `registry/` 초기 JSON 파일 4개
- `R/skills/` 14개 skill 디렉토리
- `config/qepm_config.md`
- `lawbook/` 에 Lawbook 파일 배치
- `agents/` 에이전트별 노트 디렉토리

## 검증
- `claude --version` ≥ v2.1.32
- `.claude/settings.json`에 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` = "1"
- CLAUDE.md에 16개 에이전트 정의 포함
- memory/, registry/, R/skills/ 디렉토리 존재 확인
- config/qepm_config.md 로드 가능

```yaml
project:
  name: "QEPM MoltBot"
  version: "1.4.2"
  market: "KR"
  language: "R"
  rebalance_freq: "monthly"
  benchmark: "KOSPI200_TR"
  project_root: "."                    # 기존 QEPM 폴더 경로

memory:
  base_dir: "./memory"
  promotion:
    r2_min_experiments: 3
    r4_min_regime_months: 24
    r4_low_confidence: 0.3
    r4_med_confidence: 0.5
  retrieval_priority:
    rebalance: [schema, stat_evidence, regime_payoff, portfolio_policy, digests, working]
    research: [family_memory, lessons, stat_evidence, backlog, working]

research:
  budget_split:
    exploit: 0.50
    orthogonal: 0.30
    counterfactual: 0.20
  family_concentration_cap: 0.40
  cooldown_after_fails: 3
  max_wip: 3

kpi:
  primary_sharpe: "sharpe0_m_ann"
  primary_tail: "es99_m"
  target_cagr: 0.16
  target_sharpe: 2.0
  target_mdd: -0.25

briefing:
  triggers:
    sharpe_improvement: 0.10
    es99_improvement: 0.003
    mdd_improvement: 0.02
  dedup_hours: 24
  daily_max: 12

hurdle:
  objective_hierarchy: [validity, implementability, robustness, performance, novelty]

hard_laws:
  - "PIT: available_date <= rebal_date"
  - "재현성: 동일 입력 동일 결과"
  - "비용 반영 필수"
  - "허들 임의 변경 금지"
  - "fingerprint 동일 = 동일 전략"
  - "테스트 구간 봉인"
  - "산출물 없는 진척 금지"
```

### 0-6. 기존 코드 연결 심볼릭 링크 (필요 시)

```bash
# 기존 R 코드가 프로젝트 루트에 있으면 별도 작업 불필요
# 만약 다른 위치에 있으면 심볼릭 링크 생성
# ln -s /path/to/existing/R ./R
```

## 산출물
- Claude Code Agent Teams 설치 완료
- 16개 에이전트 workspace 디렉토리
- `~/.claude-agent-teams/settings.json`
- `memory/` 하위 7개 디렉토리
- `registry/` 초기 JSON 파일 4개
- `config/qepm_config.md`
- `lawbook/` 에 Lawbook 파일 배치

## 검증
- `.claude/settings.json에 AGENT_TEAMS 활성화 확인` 실행 시 16개 에이전트 출력
- `# Verify Agent Teams enabled` 정상
- memory/, registry/ 디렉토리 존재 확인
- config/qepm_config.md 로드 가능

---

# Phase 1: 에이전트 Spawn Prompt + 상세 규칙 정의

## 목표
CLAUDE.md의 에이전트 정의를 상세 규칙으로 확장하고, 각 에이전트의 spawn prompt 템플릿을 생성한다.
Agent Teams에서 teammate은 spawn 시 CLAUDE.md를 자동 로드하므로, CLAUDE.md + spawn prompt가 역할을 한다.
내용은 Lawbook의 해당 장에서 추출한다.

## 공통 spawn prompt 구조

모든 에이전트의 spawn prompt는 아래 구조를 따르며, agents/{name}/spawn_prompt.md에 저장한다:

```markdown
# {Agent Name}

## 목적함수 우선순위 (위반 불가)
1. Validity (PIT, 데이터 무결성, 재현성)
2. Implementability (TO, 비용, 유동성, 집행 가능성)
3. Robustness (OOS, Stress, Tail Risk)
4. Performance (Sharpe0, CAGR, IR)
5. Novelty (새로운 알파 원천, 직교성, 학습가치)

## 역할
{Lawbook 01장 해당 역할 설명}

## 권한 경계
{Lawbook 01장 해당 권한 경계}

## Hard Law
{config/qepm_config.md의 hard_laws 전체}

## 에이전트 고유 규칙
{Lawbook 해당 장의 핵심 규칙}

## 산출물 표준
모든 산출물에 포함: Artifact, Provenance, Decision Log, Fingerprint

## KPI 표준
기본 Sharpe: Sharpe0_m_ann (월간, Rf=0%)
기본 Tail: ES99_m (월간 ES 99%, 양의 손실 크기)

## 사용 가능한 Skills
{해당 에이전트가 사용할 shared skills 목록}

## 파일 접근
- 읽기: memory/, registry/, lawbook/, artifacts/
- 쓰기: memory/{해당 레이어}, artifacts/{task_id}/
```

## 에이전트별 spawn prompt 내용 가이드

### manager (Team Lead) spawn prompt
- 01장: 오케스트레이터 역할
- 13장: 영구기관 상태기계 (BOOT→MEMORY_LOAD→BACKLOG_REFRESH→DISPATCH→RUN_CHUNK→EVALUATE→MEMORY_COMMIT→BRIEF_IF_NEEDED)
- 09장: 월간 리밸런싱 파이프라인
- 13.7: 브리핑 트리거 규칙
- IDLE 금지 규칙: Backlog 비면 Stabilize→Explore→Diagnose→Exploit 순으로 생성
- 25장: MEMORY_COMMIT 시 R0→R1 자동 + 승격 판단

### manager/AGENTS.md
```markdown
# 위임 규칙

## 세션 시작 시 (데이터 최신화)
0. steward → 데이터 수집/최신화 (사용자 업데이트 감지 → API 보충 → QC → 스냅샷)

## 고정 파이프라인 (연구 청크)
1. researchops → 청크 선택 + 리서치 필요 여부 판단
   1a. (필요 시) researchops → researcher에 수집 방향 지시
   1b. researcher → 지시 방향에 맞춰 수집 → research_package.json
   1c. researchops → 수집 결과 검증 (방향 일치? 중복? 품질?)
2. researchops → strategist에 청크 + 검증된 리서치 패키지 전달
3. strategist → 설계 + 백테스트
4. alphalab → Stage 0 fast filter
5. auditor → 심사 (Gate 0~5 + diversity check)
6. blender → 조합 (PASS 시)
7. portfolio → 사용자 선택 후 트레이드리스트 생성
8. tower → 사후 감시

## 지원 에이전트
- steward: 매 세션 데이터 최신화 + 월말 스냅샷 봉인
- researcher: ResearchOps의 지시를 받아 논문/칼럼 수집 (독립 행동 금지)
- features: 피처 정의 변경 필요 시
- valuation: 밸류에이션 측정 필요 시
- regime: 국면 분류 필요 시
- catalyst: cross-domain 아이디어 생성 (Track D)
- compiler: 아이디어→실험 변환
- monitor: 성과 분해

## Researcher 정보 흐름 (ResearchOps 허브)
- ResearchOps가 "이 청크에 리서치 필요" 판단 → researcher에 방향 지시
- researcher가 지시 방향에 맞춰 수집 → research_package.json 생성
- ResearchOps가 수집 결과를 검증 (방향 일치? 중복? 품질?)
- 검증 통과한 패키지만 strategist에게 청크와 함께 전달
- ResearchOps가 "리서치 불필요" 판단하면 researcher 미호출

## Researcher vs Catalyst 구분
- researcher: ResearchOps 지시 → 수집 → ResearchOps 검증 → strategist
- catalyst: 기존 기억 + 다른 분야 → 창의적 유비 → compiler 경유 → backlog

## 위임 원칙
- 산출물이 다음 에이전트의 입력이 되는 파이프라인 구조
- 중간 결과는 artifacts/{task_id}/ 에 저장
- 예외/정책 질문만 나에게 올린다

## 사용자 질문 라우팅

사용자가 자유형 질문/요청을 보내면, 주제를 파악하여 담당 에이전트에 전달하고
답변을 받아 텔레그램으로 전달한다. Manager가 직접 답하지 않는다 (아래 예외 제외).

라우팅 규칙:
- 전략 설계/가설/메커니즘/construction → strategist
- 심사/허들/alpha/통계 검증/Gate 결과 → auditor
- 국면/regime/시장 상태/전환 확률 → regime
- 조합/배분/overlay/비중/role balance → blender
- 연구 우선순위/backlog/큐/Track 배분 → researchops
- 논문/칼럼/학술 근거/문헌 → researcher (ResearchOps 경유)
- 아이디어/cross-domain/유비추론 → catalyst
- 데이터/수집/API/스냅샷/최신화 → steward
- 피처/PIT/변수 정의/피처 계약 → features
- 성과 분해/기여도/원인 분석 → monitor
- OOS 추적/드리프트/WATCHLIST/이론적 감시 → tower
- 밸류에이션/z-score/relative PE → valuation
- 트레이드리스트/주문/집행 → portfolio

Manager가 직접 답변하는 경우:
- 기억/R0~R6/승격 현황 (manager가 memory 접근 가능)
- 시스템 상태/모드/설정/영구기관 상태
- 에이전트 목록/역할 설명

복합 질문(여러 주제)이면 관련 에이전트에 순차 질의 후 종합하여 답변.
판단이 어려우면 사용자에게 "어떤 관점에서 알고 싶으신가요?"로 확인.

## 사용자 요청 기반 온디맨드 브리핑

사용자가 특정 분석/브리핑을 요청하면, Manager가 관련 에이전트에 작업을 위임하고
qepm-briefing skill로 차트/카드를 생성하여 텔레그램으로 전송한다.

온디맨드 브리핑 예시:
- "지난 달 regime 판단 정확도 분석해줘"
  → regime(국면 사후 검증) + monitor(성과 분해) → qepm-briefing → 텔레그램
- "PASS 풀의 현재 직교성 현황 보여줘"
  → qepm-diversity(상관 행렬 + effective_N) → qepm-briefing → 텔레그램
- "idioVol family의 전체 실험 히스토리 정리해줘"
  → qepm-memory(R1/R2 조회) + qepm-registry → qepm-briefing → 텔레그램
- "이번 달 backlog 상위 10개 청크와 우선순위 근거"
  → researchops(backlog + priority 산출 근거) → 텔레그램
- "현재 포트폴리오의 팩터 노출 분석"
  → tower(이론적 노출 추적) + qepm-factor-model → qepm-briefing → 텔레그램
- "최근 3개월 R4 Regime Payoff 변화 추이"
  → qepm-memory(R4 시계열) → qepm-briefing(차트 생성) → 텔레그램

프로세스:
1. 사용자 요청 수신
2. Manager가 필요한 에이전트/skill 판단
3. 관련 에이전트에 분석 위임
4. 분석 결과 수집
5. 시각화가 도움되면 qepm-briefing으로 차트/카드 생성
6. 텔레그램으로 전송

시각화 없이 텍스트만으로 충분한 질문은 차트 없이 답변해도 된다.
사용자가 "차트로 보여줘", "시각화해줘" 명시하면 반드시 qepm-briefing 사용.

## 텔레그램 전송 정책: DM vs 채널

두 개의 텔레그램 출력 경로가 있다:
- **DM** (사용자 ↔ Manager 양방향): 명령, 질문, 선택, 개인 소통
- **Channel** (Manager → 브로드캐스트 단방향): 시스템 산출물 아카이브

### 채널에 보내는 것 (시스템 산출물 전부)
아래는 DM으로 보냄과 동시에 채널에도 게시한다:
- 전략 브리핑 카드 (PASS/FAIL/NEAR_MISS — 차트 + 요약 카드)
- PASS 전략 상세 리포트
- 월간 리밸런싱 후보군 비교표 + 각 후보 상세
- 월간 모니터링 브리핑 (이론적 성과 분해)
- 국면 전환 알림
- WATCHLIST/RETIRED 변동 알림
- 온디맨드 브리핑 (사용자 요청으로 생성된 분석/차트)
- 영구기관 상태 요약 (일일/주간)
- 기억 승격 알림 (R2~R5 신규 승격 시)
- Catalyst 아이디어 진행 상태 (QUEUED/COLLECTING/BLOCKED/REJECTED)

### DM에만 보내는 것 (채널에 보내지 않음)
- 사용자의 자유형 질문과 그에 대한 답변 (개인 소통)
- /select 등 의사결정 관련 대화
- 시스템 설정/모드 변경 확인 (/pause, /resume 등)
- 에러/장애 알림 (운영 이슈)

### 채널 게시 포맷
채널에는 가독성을 위해 아래 규칙을 따른다:
- 해시태그로 카테고리 표시: #전략브리핑, #월간리밸, #국면전환, #모니터링, #기억승격, #아이디어
- 날짜/시간 prefix: [2026-03-15 09:30]
- 채널용 요약 1줄 + 상세 내용 (DM과 동일한 내용)

> **Gap Analysis 지시**: 기존 에이전트의 텔레그램 채널 운용 지침을 찾아라.
> 기존 채널 포맷, 해시태그 체계, 게시 규칙이 있으면 이 규칙에 병합한다.
> 기존 관례와 충돌 시 기존을 우선한다.
```

### strategist spawn prompt (Opus 4.6 — 확장 사고 활용)
- 01장: 전략 설계 역할 + 권한 경계
- 04장: Strategy Spec Template (전체)
- 14장: Experiment Protocol 핵심 (1~8 계약서 항목)
- 13.2A: Hard Law vs Soft Prior — Soft Prior를 참고하되 복종 의무 없음
- 13.2B: 탐색 모드 (EXPLOIT/ORTHOGONAL/COUNTERFACTUAL)
- 01장 v1.4.1: Failure Intelligence Loop (4축 원인 분해, 최근 실패 5~20개 조회 의무)
- 15.8: 새 실험 전 Lesson 3개 인용 의무
- **확장 사고 활용 지시**: "전략 설계 시 확장 사고를 사용하라. 특히: (1) 가설의 경제적 메커니즘이 성립하는지 다각도로 검토, (2) 반증 조건을 먼저 설계한 뒤 전략을 확정, (3) 과거 실패 패턴과의 유사성을 체계적으로 대조, (4) construction 선택의 trade-off를 명시적으로 추론"

### auditor spawn prompt (Opus 4.6 — 확장 사고 활용)
- 01장: Risk Auditor 역할 + 권한 경계
- 06장: Hurdle System 전체 (Gate 0~5 순서, 등급, Near-Miss)
- 07장: Risk Audit 체크리스트 전체
- 22장: Statistical Defense 발동 규칙
- 14.2~14.3: Sharpe0/ES99 정의
- 06장 3B: 이중 승격 구조 (strategy-level + portfolio-level)
- **확장 사고 활용 지시**: "심사 시 확장 사고를 사용하라. 특히: (1) 높은 Sharpe0가 단일 국면/이벤트에서만 왔는지 분해, (2) factor-model alpha가 실제 구조적 알파인지 vs 시장/스타일 위장인지 판단, (3) Near-Miss의 수정 가능성을 구체적으로 추론, (4) 다중검정 환경에서 이 결과가 우연일 확률을 명시적으로 고려"

### researchops spawn prompt (Opus 4.6 — 확장 사고 활용)
- 16장: Priority Score 계산식 (Gain/Learning/Novelty/Cost/Dependency/FamilyPenalty)
- 16.2A: 0~5 정수 평가 기준
- 16.3A: 탐색 예산 분할 (50/30/20)
- 16.11: Memory-driven Queue Economics
- 13.4A: 다양성 보존 (family 40% cap, corr-cluster 35% cap)
- 13.5: WIP 상한, family cooldown
- **확장 사고 활용 지시**: "우선순위 결정 시 확장 사고를 사용하라. 특히: (1) '왜 이 실험이 지금 가치 있는지'를 기억의 공백(Regime Payoff 빈칸, role imbalance)과 연결해 추론, (2) family 간 비교 시 expected learning의 비대칭성을 고려, (3) exploit vs orthogonal vs counterfactual 예산이 현재 포트폴리오 상태에 적합한지 판단"

### blender spawn prompt (Opus 4.6 — 확장 사고 활용)
- 12장: Blender Agent 전체 (원칙 A/B/C, Step 1~6)
- 08장: 앙상블/국면 규칙
- 20장: Portfolio Construction 순서
- 11장: Valuation overlay 참조 규칙
- 20.8: Memory-aware Construction
- **확장 사고 활용 지시**: "조합 설계 시 확장 사고를 사용하라. 입력은 auditor(Opus)가 검증을 마친 후보다. 당신의 초점은 '진짜들을 어떻게 섞을지'에 있다. 특히: (1) 국면별/꼬리 조건부 상관 구조 분석, (2) baseline 대비 overlay의 실제 개선 인과 추론, (3) LOO에서 특정 1개가 빠졌을 때 메커니즘 분석, (4) 현재 regime에서 role balance 체계적 검토"

### catalyst spawn prompt (Opus 4.6 — 확장 사고 활용)
- 23장: Catalyst 역할, cross-domain 아이디어 생성, Reference Bundle 필수
- **확장 사고 활용 지시**: "아이디어 생성 시 확장 사고를 사용하라. 특히: (1) 다른 분야(물리/생물/정보이론 등)의 메커니즘을 금융 프록시로 번역할 때 유비(analogy)의 한계를 명시, (2) 기존 family와의 차별성을 구조적으로 논증, (3) falsification 조건을 먼저 설계한 뒤 아이디어를 확정, (4) 최근 FAIL lesson과 충돌하는지 체계적 대조"
- **피드백 루프 필수 참조**: 아이디어 생성 전 agents/catalyst/idea_feedback/ 의 과거 피드백을 확인한다. 동일 메커니즘/프록시에서 반복 실패한 패턴을 피하고, 피드백의 대안 제안을 우선 고려한다. 피드백은 compile 단계 반려, 데이터 수집 실패, 백테스트 FAIL, 심사 FAIL 등 전 단계에서 축적된다.

### regime spawn prompt (Opus 4.6 — 확장 사고 활용)
- 08장: 국면 정의, 국면별 배분, 과최적화 방지
- **확장 사고 활용 지시**: "국면 분류 시 확장 사고를 사용하라. 특히: (1) 변수 선택이 '과거에 잘 맞도록' 역설계된 것이 아닌지 비판적 검토, (2) 국면 수를 늘리는 게 설명력 증가인지 과적합인지 판단, (3) 국면 전환 시점의 노이즈/지연을 명시적으로 고려, (4) 경제적으로 해석 가능한 상태인지 검증"

### researcher spawn prompt (Opus 4.6 — 확장 사고 활용)
- 01장: Idea Researcher 역할 — 논문/문헌 기반 아이디어 제안, 학술 근거 필수
- **확장 사고 활용 지시**: "문헌 수집/분석 시 확장 사고를 사용하라. 특히: (1) 논문의 실증 결과가 한국시장에 적용 가능한지 시장 구조 차이를 고려, (2) 저자가 보고하지 않은 한계/편향을 파악, (3) 구현 시 필요한 데이터/프록시가 현재 데이터레이크에 있는지 확인, (4) 기존 PASS 풀의 메커니즘과 겹치지 않는 새로운 각도인지 판단"
- **ResearchOps 허브 원칙**: ResearchOps의 수집 방향 지시를 받아 행동한다. 독립적으로 strategist에게 전달하지 않는다.
- **수집 방향 준수**: ResearchOps가 지시한 키워드/메커니즘/타겟 소스에 맞춰 수집. 방향을 벗어나는 흥미로운 논문은 별도 태그로 보고하되, 메인 패키지에는 넣지 않는다.
- **Catalyst와의 역할 구분**: Researcher는 ResearchOps 지시 → 검증된 텍스트 수집, Catalyst는 다른 분야에서 창의적 유비추론

### steward spawn prompt (Opus 4.6 — 데이터 수집/최신화/QC)
- 02장: DataLake and DB Policy 전체
- **데이터 수집 프로세스 (핵심)**:
  1. 매 세션 시작 시 사용자가 직접 업데이트한 데이터 존재 여부 감지
  2. 사용자 데이터가 있으면 우선 반영 (L0 RAW 적재)
  3. 없거나 최신 영업일 기준 부족하면 API 자동 수집 (DART/FRED/KRX)
  4. L0 RAW → L1 STAGING → L2 FEATURES → L3 UNIVERSE 파이프라인 실행
  5. QC 실행 (스키마, 시계열 합리성, 커버리지, 룩어헤드 방지)
  6. 월말 스냅샷 봉인
- **사용자 데이터 우선 원칙**: API 데이터보다 사용자가 직접 넣은 데이터를 항상 우선한다
- **Skills**: qepm-datalake (데이터 수집/최신화), qepm-registry (스냅샷 관리)

### 나머지 에이전트들 (Haiku)
- tower (Haiku) → 21장, 시장 데이터 기반 이론적 사후 감시 (증권사 API 연동 불포함, 추후 확장 대비 인터페이스만 설계)
- compiler (Sonnet) → 23장 Idea Compiler
- valuation (Haiku) → 11장
- features (Haiku) → 03장
- portfolio (Haiku) → 09장 사용자 선택 후 트레이드리스트 생성
- alphalab (Haiku) → 18장
- monitor (Haiku) → 09장 성과관리 부분

## 산출물
- 16개 workspace에 에이전트 정의 배치
- manager, strategist, auditor, researchops, blender에 AGENTS.md 배치
- manager에 USER.md 배치

## 검증
- 각 에이전트 정의가 목적함수 우선순위 + Hard Law + 역할 + 권한 경계를 포함
- 각 에이전트 정의가 해당 Lawbook 장의 핵심 규칙을 반영
- AGENTS.md의 파이프라인 순서가 Lawbook 09장과 일치
- steward spawn prompt에 데이터 수집 5단계 프로세스가 포함
- researcher spawn prompt에 ResearchOps 허브 원칙 + 독립 행동 금지 규칙이 포함

---

# Phase 2: R Scripts & Skills + Communication Format + Experiment Protocol

## 목표
기존 R 코드를 Claude Code Agent Teams R Scripts & Skills로 래핑하고,
에이전트 간 산출물 교환 표준(통신 포맷)과 실험 프로토콜 템플릿을 확립한다.

## Skill 구조 표준

각 skill 디렉토리:
```
qepm-{name}/
├── main.R (진입점)          # 스킬 메타데이터
├── run.sh              # 진입점 (Rscript 호출)
├── R/                  # R 소스 (기존 코드 래핑)
│   └── main.R
└── README.md
```

**main.R (진입점) 표준:**
```json
{
  "name": "qepm-{name}",
  "description": "...",
  "version": "1.0.0",
  "command": "bash run.sh",
  "input": "json via stdin or file path argument",
  "output": "json to stdout"
}
```

**run.sh 표준:**
```bash
#!/bin/bash
INPUT="${1:-/dev/stdin}"
Rscript R/main.R "$INPUT"
```

---

## 2-A. 에이전트 간 통신 포맷 (모든 skill/에이전트 공통)

### deliverable_format 표준

모든 에이전트 산출물은 아래 3가지 포맷 중 하나로 반환한다.

**concise** (~30% 토큰, 에이전트 간 기본 통신용):
```json
{
  "task_id": "TASK_...",
  "agent": "auditor",
  "verdict": "NEAR_MISS",
  "grade": "B",
  "key_metrics": {
    "sharpe0_m_ann": 1.12,
    "mdd": -0.461,
    "es99_m": 0.098,
    "net_cagr": 0.158,
    "turnover_ann": 1.03
  },
  "fail_reasons": ["MDD 46.1% > 45% threshold"],
  "next_action": "repair_ticket: buffer_zone 강화",
  "artifact_paths": ["artifacts/TASK_.../risk_audit.json"]
}
```

**detailed** (~100% 토큰, 최종 브리핑/사람 검토용):
전체 stress test, gate별 상세, 민감도 분석 포함. `artifacts/{task_id}/` 의 전체 파일.

**stats_only** (~15% 토큰, Memory 승격용):
```json
{
  "sharpe0_m_ann": 1.12, "mdd": -0.461, "es99_m": 0.098,
  "ff3_alpha": 0.018, "ff3_t": 2.21,
  "verdict": "NEAR_MISS", "grade": "B"
}
```

### 파이프라인 통신 규칙

| 송신자 | 수신자 | format | 이유 |
|---|---|---|---|
| strategist | auditor | detailed | 전체 심사 필요 |
| auditor | blender | concise | 판정 + 핵심 수치 |
| auditor | manager | concise | 보고용 |
| auditor | memory pipeline | stats_only | 승격용 수치 |
| blender | auditor | detailed | 후보 검증 근거 |
| tower | manager | concise | 경보/상태 보고 |

### 응답 메시지 표준

모든 에이전트는 태스크 완료 시 아래를 `artifacts/{task_id}/response.json`에 저장:

```json
{
  "task_id": "TASK_...",
  "agent": "에이전트ID",
  "timestamp": "ISO8601+KST",
  "state": "done | failed | rejected",
  "result_summary": {
    "verdict": "PASS | FAIL | NEAR_MISS",
    "grade": "A | B | C | F",
    "key_metrics": {},
    "fail_reasons": [],
    "repair_suggestion": "..."
  },
  "deliverables": {
    "파일명": { "path": "...", "hash": "sha256:...", "format": "detailed" }
  },
  "memory_promotion_candidates": [
    { "target_stage": "R3", "evidence_type": "statistical", "data": {} }
  ],
  "next_actions": [
    { "type": "REPAIR_TICKET | SPAWN_CHUNK | ESCALATE | BRIEF",
      "description": "...", "target_family": "...",
      "expected_gain_axis": "Risk | Return | Robustness | Impl | Div" }
  ],
  "fail_guidance": {
    "gate_failed": "Gate 2: Robustness",
    "specific_issue": "MDD 46.1% > 45% threshold",
    "actionable_fix": "buffer_zone 25→50 확대 또는 defensive sleeve 추가",
    "estimated_difficulty": "low"
  }
}
```

### Experiment Protocol 템플릿

Strategist가 실험 설계 시 반드시 `artifacts/{task_id}/experiment_protocol.json`에 생성.
Lawbook 14장의 1~8 항목 구조화:

```json
{
  "exp_id": "EXP_YYYY-MM-DD_###",
  "parent_exp_id": null,
  "task_family": "idioVol_monthly_bufferzone",
  "strategy_fingerprint": "sha256:...",
  "hypothesis": {
    "statement": "buffer zone 50%로 확대하면 MDD가 3%p 개선된다",
    "mechanism": "불필요한 종목 교체를 줄여 회전율-비용 감소",
    "falsification": "MDD 개선 < 1%p이면 가설 기각",
    "null_design": "동일 전략에서 buffer zone을 제거한 버전"
  },
  "data": {
    "snapshot_id": "DS_YYYYMMDD_EOM",
    "pit_verified": true,
    "survivorship_handled": true,
    "qc_passed": true
  },
  "implementation": {
    "universe": "KR_ALL_LISTED",
    "signal": "idiosyncratic_volatility_residual",
    "rebalance": "monthly",
    "n_holdings": 30,
    "weighting": "equal",
    "neutralization": "sector",
    "buffer_zone": { "entry": 25, "exit": 50 },
    "cooldown": 2,
    "cost_model": "cost_v2.1",
    "constraints": { "max_weight": 0.05, "max_turnover_ann": 6.0 }
  },
  "execution_plan": {
    "preflight": { "period": "2020-2022", "check": ["data_ok", "to_calc", "cost_bind"] },
    "full_run": { "is_period": "2015-2020", "oos_period": "2020-2024",
                  "stress_windows": ["covid_2020", "rate_hike_2022"] }
  },
  "evaluation_metrics": {
    "primary": ["net_cagr", "sharpe0_m_ann", "mdd", "es99_m", "turnover_ann"],
    "secondary": ["sharpe0_d_ann", "es99_d", "hit_rate", "ic", "icir", "oos_retention"],
    "stat_defense": { "required": true, "methods": ["dsr"], "family_trial_count": 7 }
  },
  "lessons_referenced": ["L-018", "L-022"],
  "lessons_application": "L-018의 corr>0.8 필터 적용, L-022의 cooldown=2 채택",
  "search_mode": "EXPLOIT"
}
```

> Auditor는 `data.pit_verified`, `hypothesis.falsification`, `lessons_referenced`가
> 비어 있으면 Gate 0에서 즉시 FAIL 처리.

---

## 2-B. Quant & Infrastructure Skills (14개)

### 2-1. `qepm-backtest`
목적: 전략 파라미터 → 백테스트 실행 → 결과 반환
입력: experiment_protocol.json, 출력: backtest_result.json
R: 기존 백테스트 함수 래핑

### 2-2. `qepm-factor-model`
목적: FF3/Carhart4/FF5 alpha validation + Fama-MacBeth
R: lm() + sandwich(Newey-West)

### 2-3. `qepm-optimize`
목적: 앙상블 가중치 산출 (equal/rp/minvar/maxsharpe)
R: 기존 HRP/RP 래핑

### 2-4. `qepm-stat-defense`
목적: DSR, FDR, Reality Check, bootstrap/placebo
R: DSR 공식 + sample() 부트스트랩

### 2-5. `qepm-kpi`
목적: 수익률 → Sharpe0, ES99, MDD 등 표준 KPI
R: Sharpe0 = sqrt(12)*mean(r_m)/sd(r_m), ES99 = -mean(r[r<=q(r,0.01)])

### 2-6. `qepm-memory` (Phase 3에서 대폭 확장)
목적: R0~R6 전체 기억 파이프라인

### 2-7. `qepm-registry`
목적: experiments/strategies/families JSON CRUD + fingerprint 중복 체크
R: jsonlite + digest::digest

### 2-8. `qepm-lawbook`
목적: Lawbook .md 장/섹션 검색 + 로드
R: readLines + grep, nchar/2.5 토큰 추정

### 2-9. `qepm-diversity` (모드 붕괴 방지 핵심)

목적: 전략 간 다양성/중복도를 계산하고, 모드 붕괴를 자동 차단.
상관 0.9짜리 "합격 전략"만 쌓이는 것을 구조적으로 방지한다.

```r
#' 1. Return Correlation — 새 전략 vs 기존 PASS 풀
compute_return_correlation <- function(new_returns, existing_returns_matrix) {
  # 월간 수익률 pearson correlation
  # rolling 36개월 상관 (정상 시 낮지만 위기 시 급등하는지)
  # tail correlation (하위 10% 구간에서의 상관)
}

#' 2. Factor Exposure Overlap — 팩터 노출 벡터 코사인 유사도
compute_exposure_overlap <- function(new_exposures, existing_exposures_matrix) {
  # value/momentum/quality/lowvol/size 등 팩터 노출 벡터
}

#' 3. Holdings Overlap — 보유 종목 겹침도
compute_holdings_overlap <- function(new_holdings, existing_holdings_list) {
  # 월별 holdings intersection / union
}

#' 4. Drawdown Path Similarity — 낙폭 경로 유사도 (위기 시 같이 빠지는지)
compute_drawdown_similarity <- function(new_dd, existing_dd_matrix) {
  # drawdown 시계열 상관
  # 최대낙폭 구간 겹침도
}

#' 5. 종합 Redundancy Score
compute_redundancy_score <- function(new_strategy, existing_pool) {
  return_corr <- compute_return_correlation(...)
  exposure_overlap <- compute_exposure_overlap(...)
  holdings_overlap <- compute_holdings_overlap(...)
  dd_similarity <- compute_drawdown_similarity(...)

  redundancy <- max(
    return_corr$median_corr,
    exposure_overlap$max_cosine,
    dd_similarity$crisis_corr
  )

  list(
    redundancy_score = redundancy,
    return_corr = return_corr,
    exposure_overlap = exposure_overlap,
    holdings_overlap = holdings_overlap,
    dd_similarity = dd_similarity,
    verdict = if (redundancy > 0.85) "REDUNDANT"
              else if (redundancy > 0.70) "HIGH_OVERLAP"
              else if (redundancy > 0.50) "MODERATE"
              else "ORTHOGONAL"
  )
}

#' 6. Portfolio Effective N — 앙상블의 실효 전략 수
compute_effective_n <- function(correlation_matrix) {
  # effective_N = N / (1 + (N-1) * avg_corr)
  # effective_N < 3이면 "다양성 부족" 경고
}
```

### 2-10. `qepm-idea-pipeline` (Catalyst 아이디어 관리)

목적: Catalyst가 생성한 아이디어를 표준화하고, Compiler를 거쳐 실험 큐까지 도달시킨다.
Lawbook 23장의 IDEA_PROPOSAL → Compiler → EXPERIMENT_TICKET → ResearchOps Queue 경로를 구현.

```r
#' 1. 아이디어 제출 (Catalyst → idea_backlog)
submit_idea <- function(idea_proposal) {
  # idea_proposal 필수 필드 검증:
  #   source_idea, abstract_mechanism, observable_proxy,
  #   signal_sketch, reference_bundle, domain_tags, falsification
  # reference_bundle에 최소 1개 금융/통계 앵커 레퍼런스 확인
  # idea_backlog.json에 추가
  # 중복/유사 아이디어 감지 (기존 idea_backlog + registry 대조)
}

#' 2. 아이디어 컴파일 (Compiler → experiment_protocol)
compile_idea <- function(idea_id) {
  # idea_backlog에서 해당 아이디어 로드
  idea <- load_idea(idea_id)

  # === 데이터 가용성 3단계 판단 ===
  data_assessment <- assess_data_availability(idea$observable_proxy, idea$signal_sketch)
  # 결과:
  #   AVAILABLE:    필요 데이터가 이미 데이터레이크에 존재
  #   COLLECTIBLE:  현재 없지만, 기존 수집 인프라(DART/FRED/KRX/허용 소스)로 수집 가능
  #   UNAVAILABLE:  수집 인프라로도 확보 불가 (유료 DB, 비공개 데이터 등)

  # === 데이터 상태별 분기 ===
  if (data_assessment$status == "AVAILABLE") {
    # 바로 진행
  } else if (data_assessment$status == "COLLECTIBLE") {
    # steward에게 수집 요청 → 수집 완료 후 진행
    # idea_status = "COLLECTING" (수집 중)
    # 수집 예상 소요, 소스, 파라미터를 명시
    request_data_collection(data_assessment$collection_plan)
  } else {
    # UNAVAILABLE → BLOCKED (데이터 확보 방법이 없음)
    return(list(status = "BLOCKED", reason = data_assessment$reason))
  }

  # === 나머지 구현 가능성 검사 ===
  #   - PIT 준수 가능한가
  #   - 기존 skill로 백테스트 가능한 구조인가
  #   - 동일 theme에서 최근 FAIL lesson이 있는가 → 있으면 인용 강제

  # 통과하면: experiment_protocol.json 생성 → registry/backlog에 등록
  # 실패하면: idea_status = "BLOCKED" 또는 "REJECTED" + 사유 명시
}

#' 데이터 가용성 3단계 평가
assess_data_availability <- function(observable_proxy, signal_sketch) {
  # Step 1: 데이터레이크(L0~L3)에서 필요 변수 검색
  existing <- search_datalake(observable_proxy)
  if (existing$found) return(list(status = "AVAILABLE"))

  # Step 2: 기존 수집 인프라로 수집 가능한지 평가
  #   - DART: 공시/재무 데이터 (종목별 재무제표, 공시)
  #   - FRED: 매크로 데이터 (금리, 스프레드, 환율 등)
  #   - KRX: 시장 데이터 (가격, 거래량, 시총, 업종)
  #   - 허용된 웹 소스: 정부/공공 데이터
  collection_plan <- check_collection_feasibility(observable_proxy)
  if (collection_plan$feasible) {
    return(list(
      status = "COLLECTIBLE",
      collection_plan = collection_plan,
      estimated_days = collection_plan$days,
      source = collection_plan$source
    ))
  }

  # Step 3: 수집 불가
  return(list(
    status = "UNAVAILABLE",
    reason = collection_plan$reason  # "유료 Bloomberg 전용" 등
  ))
}

#' 3. 아이디어 상태 관리
manage_idea_status <- function(idea_id, action) {
  # 상태 흐름:
  # SUBMITTED → COMPILING → COLLECTING(데이터 수집 중) → QUEUED → RUNNING
  #                                                         ↓
  #                                              COMPLETED | FAILED
  #                                                         ↓
  #                                              (피드백 → Catalyst)
  # 분기:
  # BLOCKED: 데이터 수집 불가로 현재는 진행 불가 (인프라 변경 시 재시도)
  # REJECTED: 중복/비실현/falsification 구조 불가
  #
  # FAILED/BLOCKED/REJECTED 시 catalyst_feedback 생성 필수
}

#' 4. Catalyst 피드백 생성 (실패/반려 시 필수)
generate_catalyst_feedback <- function(idea_id, outcome) {
  # REJECTED/BLOCKED/FAILED 일 때 Catalyst에게 돌려보내는 피드백
  idea <- load_idea(idea_id)

  feedback <- list(
    idea_id = idea_id,
    original_idea = idea$source_idea,
    outcome = outcome$status,  # REJECTED | BLOCKED | FAILED
    stage_failed = outcome$stage,  # "compile" | "data_collection" | "backtest" | "audit"
    failure_reason = outcome$reason,
    failure_category = outcome$category,
    # 4축 원인 분해 (Failure Intelligence와 동일 구조):
    #   signal: 신호 자체가 약했는가
    #   construction: 구현 방식이 잘못됐는가
    #   data: 데이터 문제인가
    #   mechanism: 메커니즘 가설 자체가 틀렸는가
    failure_axis = outcome$axis,
    suggestion = outcome$suggestion,  # "다른 프록시로 재시도" 등
    related_lessons = outcome$related_lessons,  # 유사 실패 lesson 목록
    created_at = now_kst()
  )

  # Catalyst workspace에 피드백 저장
  write_json_safe(feedback,
    file.path("agents/catalyst/idea_feedback/", paste0(idea_id, "_feedback.json")))

  # R1 Experiment Digest에도 반영 (전체 학습에 기여)
  return(feedback)
}
```

**IDEA_PROPOSAL 표준 스키마:**
```json
{
  "idea_id": "IDEA_2026-03-15_001",
  "source_agent": "catalyst",
  "source_idea": "신용 스프레드의 비대칭적 확장이 팩터 로테이션 선행지표로 작용",
  "abstract_mechanism": "신용 리스크 재가격화가 quality/defensive factor 프리미엄을 확대",
  "observable_proxy": "한국 회사채 AA-BBB 스프레드 변화율",
  "signal_sketch": "스프레드 3개월 변화 > 1σ → quality/defensive 비중 확대",
  "construction_hint": "regime overlay 또는 standalone signal",
  "reference_bundle": {
    "anchors": [
      {"domain": "FIN", "ref": "Asness et al. (2019) Quality Minus Junk"},
      {"domain": "ECON", "ref": "Gilchrist & Zakrajsek (2012) Credit Spreads"}
    ],
    "domain_tags": ["FIN", "ECON", "CREDIT"]
  },
  "falsification": "스프레드 확장 후 6개월 quality 초과수익이 0 이하이면 기각",
  "expected_orthogonality": "기존 PASS 풀과 상관 < 0.5 예상 (신용 기반 ≠ 가격 기반)",
  "status": "SUBMITTED"
}
```

### 2-11. `qepm-regime` (Phase 4에서 상세 구현)
목적: 기존 국면 엔진 래핑 + baseline + 앙상블
상세는 Phase 4 참조.

### 2-12. `qepm-datalake` (데이터 수집/최신화)

목적: 매 세션 시작 시 데이터를 최신 상태로 유지.
기존 에이전트가 사용하던 데이터 수집 프로세스를 R 스크립트로 래핑한다.

```r
#' 데이터 최신화 메인 함수
#' 매 세션 시작 시 또는 월간 리밸런싱 전에 호출
refresh_data <- function(config) {

  # === Step 1: 사용자 직접 업데이트 감지 ===
  # data/raw/ 디렉토리에서 최근 수정된 파일 탐지
  # 사용자가 수동으로 넣은 csv/xlsx 파일이 있는지 확인
  user_updates <- detect_user_uploads(config$data$raw_dir)

  # === Step 2: 사용자 데이터 우선 반영 ===
  # 사용자 데이터가 있으면 L0 RAW에 먼저 적재
  if (length(user_updates) > 0) {
    for (f in user_updates) {
      ingest_to_raw(f, source = "user_manual")
    }
  }

  # === Step 3: 최신 영업일 기준 부족분 확인 ===
  # 현재 RAW의 마지막 날짜 vs 최신 영업일
  # 부족한 날짜 범위 계산
  gaps <- detect_data_gaps(config$data$raw_dir, as_of = latest_business_day())

  # === Step 4: API 자동 수집 (부족분만) ===
  if (length(gaps) > 0) {
    # DART: 공시/재무 데이터
    if ("dart" %in% gaps$sources) {
      collect_dart(gaps$dart_params)
    }
    # FRED: 매크로 데이터 (금리, 스프레드 등)
    if ("fred" %in% gaps$sources) {
      collect_fred(gaps$fred_params)
    }
    # KRX: 시장 데이터 (가격, 거래량, 시총 등)
    if ("krx" %in% gaps$sources) {
      collect_krx(gaps$krx_params)
    }
  }

  # === Step 5: L0→L1→L2→L3 파이프라인 실행 ===
  # L0 RAW → L1 STAGING (정규화)
  run_staging_pipeline()
  # L1 → L2 FEATURES (PIT 적용)
  run_feature_pipeline()
  # L2 → L3 UNIVERSE (tidy)
  run_universe_pipeline()

  # === Step 6: QC 실행 ===
  qc_result <- run_data_qc()  # 스키마, 시계열 합리성, 커버리지, 룩어헤드

  # === Step 7: 스냅샷 봉인 (월말 시) ===
  if (is_month_end()) {
    snapshot_id <- seal_snapshot()
  }

  list(
    user_updates = length(user_updates),
    api_collections = gaps$sources,
    qc_result = qc_result,
    snapshot_id = snapshot_id,
    last_date = max_date_in_universe()
  )
}
```

> **Gap Analysis 지시 (최우선)**:
> 기존 프로젝트 폴더에서 DART/FRED/KRX API 수집 함수를 반드시 찾아라.
> 사용자 업데이트 감지 로직, L0→L1→L2→L3 파이프라인도 찾아라.
> 이 함수들이 이미 존재할 가능성이 높다. 래퍼만 만든다.
> 기존 API 키 관리 방식, 호출 형식, 에러 처리를 그대로 유지한다.

### 2-13. `qepm-research-collector` (논문/칼럼 수집)

목적: 웹에서 퀀트 투자 관련 논문/칼럼/리포트를 수집하여 구조화된 요약을 생성.
Idea Researcher 에이전트가 사용하는 핵심 도구.

```r
#' 논문/칼럼 수집 및 요약
#' @param query 검색 키워드 (예: "factor momentum Korea", "smart beta valuation timing")
#' @param sources 검색 소스 (arxiv, ssrn, google_scholar, finance_blogs)
#' @param max_results 최대 결과 수
#' @return research_materials list
collect_research_materials <- function(query, sources = c("arxiv", "ssrn"), max_results = 10) {
  # 1. 허용된 소스에서만 검색 (Lawbook 00장: 인터넷은 허용된 순간에만)
  # 2. 결과를 표준 포맷으로 정리
}

#' 수집 결과 → 구조화된 리서치 브리프
#' @param paper 수집된 논문/칼럼 원문 또는 초록
#' @return research_brief
create_research_brief <- function(paper) {
  # Idea Researcher 에이전트가 이 결과를 보고 브리프를 작성
  # skill은 원문 수집/정리만, 해석/요약은 에이전트가 수행
  list(
    title = paper$title,
    authors = paper$authors,
    source = paper$source,
    url = paper$url,
    abstract = paper$abstract,
    collected_at = now_kst(),
    relevance_tags = NULL  # 에이전트가 채움
  )
}

#' ResearchOps 검증을 위한 raw 리서치 패키지 생성
#' @param briefs 리서치 브리프 리스트
#' @return raw_research_package.json (ResearchOps가 검증 후 strategist에 전달)
package_for_review <- function(briefs) {
  list(
    package_id = generate_task_id("RPKG"),
    briefs = briefs,
    total_count = length(briefs),
    created_at = now_kst(),
    status = "PENDING_REVIEW"  # ResearchOps 검증 대기
  )
}
```

> **인터넷 접근 규칙**: Lawbook 00장에 따라 허용된 소스만 사용한다.
> 논문: arxiv.org, ssrn.com, scholar.google.com
> 뉴스/칼럼: 사전 허용 도메인만 (config에서 관리)
> 수집한 원문은 data/raw/research/ 에 저장하고 RAW 규칙을 따른다.

### 2-14. `qepm-briefing` (전략 브리핑 차트 + 카드 생성)

목적: 개별 전략 연구 종료 시, 시각화 차트와 이모지 기반 대시보드 카드를 생성하여 텔레그램으로 전송.
**차트는 모든 전략(PASS/FAIL/NEAR_MISS)에 무조건 전송.
상세 리포트는 PASS 전략에만 추가 전송.**

```
qepm-briefing/
├── main.R (진입점)
├── run.sh
├── R/
│   ├── main.R
│   ├── equity_curve.R          # 누적 수익률 차트 생성
│   ├── annual_returns.R        # 연간 수익률 바 차트 생성
│   ├── summary_card.R          # 요약 카드 텍스트 생성
│   ├── detail_report.R         # 상세 리포트 텍스트 생성 (PASS only)
│   └── emoji_rules.R           # 이모지 매핑 규칙
└── config/
    └── emoji_taxonomy.md     # 이모지 매핑 설정
```

#### 차트 생성 (R — ggplot2, 모든 전략에 무조건)

```r
# R/equity_curve.R
generate_equity_curve <- function(strategy_returns, benchmark_returns,
                                   strategy_name, benchmark_name, output_path) {
  # 누적 수익률 차트
  # - 전략: 파란색 실선 (굵게)
  # - 벤치마크: 회색 점선
  # - 드로다운 구간: 연한 빨간색 음영
  # - 주요 이벤트 수직선: 코로나(2020-03), 금리급등(2022-06) 등
  # - 우측 상단에 최종 CAGR, Sharpe0, MDD 텍스트 박스
  # - 배경 깔끔한 흰색, 그리드 최소화
  # → PNG 저장
}

# R/annual_returns.R
generate_annual_returns <- function(strategy_returns, benchmark_returns,
                                     strategy_name, benchmark_name, output_path) {
  # 연도별 막대 차트
  # - 전략: 파란색 (수익 양수), 빨간색 (수익 음수)
  # - 벤치마크: 회색 (나란히)
  # - 각 막대 위에 수치 표시
  # - 하단에 연도, 상단에 초과수익 라인
  # → PNG 저장
}
```

#### 이모지 택소노미 (`config/emoji_taxonomy.md`)

```yaml
# 이모지 매핑 규칙
# Gap Analysis에서 기존 에이전트의 이모지 관례를 찾아 이 파일에 병합할 것

grade:
  A: "🏆"
  B: "🥈"
  C: "🥉"
  F: "❌"

verdict:
  PASS: "✅"
  NEAR_MISS: "⚠️"
  FAIL: "❌"

sharpe0_m_ann:
  excellent: { threshold: 1.2, emoji: "🔥" }
  good: { threshold: 0.8, emoji: "✅" }
  moderate: { threshold: 0.5, emoji: "⚠️" }
  poor: { threshold: 0, emoji: "❌" }

net_cagr:
  excellent: { threshold: 0.20, emoji: "🔥" }
  target_met: { threshold: 0.16, emoji: "✅" }
  near: { threshold: 0.12, emoji: "⚠️" }
  poor: { threshold: 0, emoji: "❌" }

mdd:
  target_met: { threshold: -0.25, emoji: "✅", note: "< 25%" }
  caution: { threshold: -0.35, emoji: "⚠️", note: "25~35%" }
  danger: { threshold: -0.45, emoji: "🔴", note: "35~45%" }
  fail: { threshold: -1.0, emoji: "❌", note: "> 45%" }

es99_m:
  good: { threshold: 0.10, emoji: "✅" }
  caution: { threshold: 0.15, emoji: "⚠️" }
  danger: { threshold: 1.0, emoji: "❌" }

turnover_ann:
  good: { threshold: 2.0, emoji: "✅" }
  caution: { threshold: 4.0, emoji: "⚠️" }
  excessive: { threshold: 100, emoji: "❌" }

alpha_t_stat:
  significant: { threshold: 1.96, emoji: "✅" }
  weak: { threshold: 1.5, emoji: "⚠️" }
  insignificant: { threshold: 0, emoji: "❌" }

redundancy:
  orthogonal: { threshold: 0.50, emoji: "🟢" }
  moderate: { threshold: 0.70, emoji: "🟡" }
  high_overlap: { threshold: 0.85, emoji: "🟠" }
  redundant: { threshold: 1.0, emoji: "🔴" }

role:
  core: "⚔️"
  defensive: "🛡️"
  diversifier: "🌀"

sortino:
  good: { threshold: 1.5, emoji: "✅" }
  moderate: { threshold: 1.0, emoji: "⚠️" }
  poor: { threshold: 0, emoji: "❌" }

calmar:
  good: { threshold: 0.5, emoji: "✅" }
  moderate: { threshold: 0.3, emoji: "⚠️" }
  poor: { threshold: 0, emoji: "❌" }

ir:
  good: { threshold: 0.5, emoji: "✅" }
  moderate: { threshold: 0.3, emoji: "⚠️" }
  poor: { threshold: 0, emoji: "❌" }

ic:
  good: { threshold: 0.05, emoji: "✅" }
  moderate: { threshold: 0.03, emoji: "⚠️" }
  poor: { threshold: 0, emoji: "❌" }

oos_retention:
  good: { threshold: 0.7, emoji: "✅" }
  moderate: { threshold: 0.5, emoji: "⚠️" }
  poor: { threshold: 0, emoji: "❌" }

hit_rate:
  good: { threshold: 0.55, emoji: "✅" }
  moderate: { threshold: 0.50, emoji: "⚠️" }
  poor: { threshold: 0, emoji: "❌" }

dsr:
  pass: { threshold: 0.5, emoji: "✅" }
  caution: { threshold: 0.3, emoji: "⚠️" }
  fail: { threshold: 0, emoji: "❌" }

search_mode:
  EXPLOIT: "🎯"
  ORTHOGONAL_SEARCH: "🔀"
  COUNTERFACTUAL: "🔄"

lifecycle:
  IDEA: "💡"
  ALPHA_LAB: "🧪"
  RESEARCH_PASS: "📋"
  CANDIDATE: "🏗️"
  PAPER: "📄"
  PRODUCTION: "🚀"
  WATCHLIST: "👀"
  RETIRED: "🪦"

# 기존 에이전트 이모지 병합 지시:
# Gap Analysis에서 기존 CLAUDE.md / MEMORY.md / 브리핑 템플릿에서
# 사용 중인 이모지 관례를 찾아서 이 파일의 해당 항목에 병합한다.
# 기존 관례와 충돌 시 기존을 우선한다.
```

#### 요약 카드 (모든 전략에 전송)

```r
# R/summary_card.R
generate_summary_card <- function(digest, risk_audit, emoji_config) {
  # 이모지 매핑
  e <- load_emoji_rules(emoji_config)

  card <- glue::glue("
📊 [전략 브리핑] {digest$exp_id}
━━━━━━━━━━━━━━━━━━━━━

{e$grade(digest$grade)} Grade {digest$grade}  |  {e$verdict(risk_audit$verdict)} {risk_audit$verdict}  |  {e$search_mode(digest$search_mode)} {digest$search_mode}
{e$role(risk_audit$role)} Role: {risk_audit$role}  |  📁 {digest$family}

━━━ 핵심 KPI ━━━━━━━━━━━
{e$sharpe0(digest$metrics$sharpe0_m_ann)} Sharpe0     {fmt(digest$metrics$sharpe0_m_ann)}
{e$cagr(digest$metrics$net_cagr)} CAGR        {pct(digest$metrics$net_cagr)}
{e$mdd(digest$metrics$mdd)} MDD         {pct(digest$metrics$mdd)}
{e$es99(digest$metrics$es99_m)} ES99        {pct(digest$metrics$es99_m)}
{e$to(digest$metrics$turnover_ann)} Turnover    {pct(digest$metrics$turnover_ann)}/yr

━━━ 보조 KPI ━━━━━━━━━━━
{e$sortino(digest$metrics$sortino)} Sortino     {fmt(digest$metrics$sortino)}
{e$calmar(digest$metrics$calmar)} Calmar      {fmt(digest$metrics$calmar)}
{e$ir(digest$metrics$ir)} IR          {fmt(digest$metrics$ir)}
{e$ic(digest$metrics$ic_mean)} IC          {fmt(digest$metrics$ic_mean)}
{e$ic(digest$metrics$icir)} ICIR        {fmt(digest$metrics$icir)}
{e$hit(digest$metrics$hit_rate)} Hit Rate    {pct(digest$metrics$hit_rate)}
{e$oos(digest$metrics$oos_retention)} OOS Ret     {pct(digest$metrics$oos_retention)}

━━━ Gate 통과 현황 ━━━━━━━
{gate_line(0, 'Validity', risk_audit)}
{gate_line(1, 'Implementability', risk_audit)}
{gate_line(2, 'Robustness', risk_audit)}
{gate_line(3, 'Performance', risk_audit)}
{gate_line(4, 'Statistical Validation', risk_audit)}
{gate_line(5, 'Diversification', risk_audit)}

━━━ Alpha 검증 ━━━━━━━━━━
{alpha_line('FF3', digest$alpha_tests)}
{alpha_line('Carhart4', digest$alpha_tests)}
{alpha_line('FF5', digest$alpha_tests)}
{alpha_line('FMB', digest$alpha_tests)}

━━━ 다중검정 ━━━━━━━━━━━
{e$dsr(digest$stat_defense$dsr)} DSR         {fmt(digest$stat_defense$dsr)}
   Family trials: {digest$stat_defense$family_trial_count}

━━━ 직교성 ━━━━━━━━━━━━━
{e$redundancy(digest$diversity$redundancy_score)} {digest$diversity$verdict} (score {fmt(digest$diversity$redundancy_score)})
   가장 유사: {digest$diversity$most_similar_strategy} (corr {fmt(digest$diversity$most_similar_corr)})

━━━ 비용 민감도 ━━━━━━━━━
비용0x  Sharpe {fmt(digest$cost_sensitivity$cost_0x)}
비용1x  Sharpe {fmt(digest$cost_sensitivity$cost_1x)} {e$sharpe0(digest$cost_sensitivity$cost_1x)}
비용2x  Sharpe {fmt(digest$cost_sensitivity$cost_2x)} {e$sharpe0(digest$cost_sensitivity$cost_2x)}
비용3x  Sharpe {fmt(digest$cost_sensitivity$cost_3x)} {e$sharpe0(digest$cost_sensitivity$cost_3x)}

━━━ 거래 상세 ━━━━━━━━━━━
📦 avg buys/rebal: {digest$trade_detail$avg_buys}
📤 avg sells/rebal: {digest$trade_detail$avg_sells}
💧 capacity: {digest$trade_detail$capacity_flag}
🔒 liquidity: {digest$trade_detail$liquidity_flag}

{failure_block(risk_audit)}
")
  return(card)
}

# FAIL/NEAR_MISS인 경우 추가 블록
failure_block <- function(risk_audit) {
  if (risk_audit$verdict == "PASS") return("")
  glue::glue("
━━━ 실패/근접 사유 ━━━━━━━
{paste(risk_audit$fail_reasons, collapse = '\n')}

{repair_block(risk_audit)}
")
}

repair_block <- function(risk_audit) {
  if (is.null(risk_audit$repair_ticket)) return("")
  rt <- risk_audit$repair_ticket
  glue::glue("
🔧 수정 제안: {rt$actionable_fix}
   목적 축: {rt$expected_gain_axis}
   난이도: {rt$estimated_difficulty}
")
}
```

#### 상세 리포트 (PASS 전략에만 추가 전송)

```r
# R/detail_report.R
generate_detail_report <- function(digest, risk_audit, backtest_result) {
  # PASS 전략에만 호출됨

  report <- glue::glue("
📋 [상세 리포트] {digest$exp_id}
━━━━━━━━━━━━━━━━━━━━━

━━━ 일간 보조 지표 ━━━━━━━
Sharpe0_d_ann   {fmt(digest$metrics$sharpe0_d_ann)}
ES99_d          {pct(digest$metrics$es99_d)}

━━━ 국면별 조건부 성과 ━━━━
        Sharpe0  CAGR     MDD      ES99
Normal  {regime_row('Normal', digest)}
Stress  {regime_row('Stress', digest)}
Euphoria{regime_row('Euphoria', digest)}
Transit {regime_row('Transition', digest)}

━━━ Stress Window 성과 ━━━━
COVID 2020-03: {pct(digest$stress$covid_2020)}
금리급등 2022: {pct(digest$stress$rate_hike_2022)}
최악 1M:       {pct(digest$stress$worst_1m)}
최악 3M:       {pct(digest$stress$worst_3m)}
최악 6M:       {pct(digest$stress$worst_6m)}

━━━ Alpha 검증 상세 ━━━━━━
FF3:
  alpha={fmt(digest$alpha$ff3_alpha)} t={fmt(digest$alpha$ff3_t)}
  주요 노출: {digest$alpha$ff3_exposures}
Carhart4:
  alpha={fmt(digest$alpha$carhart4_alpha)} t={fmt(digest$alpha$carhart4_t)}
FF5:
  alpha={fmt(digest$alpha$ff5_alpha)} t={fmt(digest$alpha$ff5_t)}
FMB:
  slope={fmt(digest$alpha$fmb_slope)} t={fmt(digest$alpha$fmb_t)}
  sign consistency={pct(digest$alpha$fmb_sign_consistency)}

━━━ 팩터/스타일 노출 ━━━━━
Value:    {bar(digest$exposures$value)}
Momentum: {bar(digest$exposures$momentum)}
Quality:  {bar(digest$exposures$quality)}
LowVol:   {bar(digest$exposures$lowvol)}
Size:     {bar(digest$exposures$size)}

━━━ 섹터 집중도 ━━━━━━━━━
HHI: {fmt(digest$concentration$hhi)}
상위 3개 섹터: {digest$concentration$top3_sectors}

━━━ 롤링 성과 (36M) ━━━━━
Sharpe 범위: {fmt(digest$rolling$sharpe_min)} ~ {fmt(digest$rolling$sharpe_max)}
MDD 범위:    {pct(digest$rolling$mdd_min)} ~ {pct(digest$rolling$mdd_max)}
β 범위:      {fmt(digest$rolling$beta_min)} ~ {fmt(digest$rolling$beta_max)}

━━━ 실험 메타 ━━━━━━━━━━━
{e$search_mode(digest$search_mode)} 탐색 모드: {digest$search_mode}
📎 참조 Lesson: {paste(digest$lessons_referenced, collapse=', ')}
🔗 부모 실험: {digest$parent_exp_id %||% '없음'}
📁 Family: {digest$family} (trial #{digest$stat_defense$family_trial_count})
{e$lifecycle(digest$lifecycle)} Lifecycle: {digest$lifecycle}
")
  return(report)
}
```

#### 전송 로직

```r
# R/main.R
send_strategy_briefing <- function(exp_id, output_dir = "artifacts/briefings/") {
  # 1. 데이터 로드
  digest <- load_digest(exp_id)
  risk_audit <- load_risk_audit(exp_id)
  returns <- load_returns(exp_id)
  benchmark <- load_benchmark_returns()
  emoji_config <- yaml::read_yaml("config/emoji_taxonomy.md")

  # 2. 차트 생성 (모든 전략에 무조건)
  eq_path <- file.path(output_dir, paste0(exp_id, "_equity.png"))
  ar_path <- file.path(output_dir, paste0(exp_id, "_annual.png"))
  generate_equity_curve(returns, benchmark, digest$strategy_id, "KOSPI200 TR", eq_path)
  generate_annual_returns(returns, benchmark, digest$strategy_id, "KOSPI200 TR", ar_path)

  # 3. 요약 카드 생성 (모든 전략에 무조건)
  card <- generate_summary_card(digest, risk_audit, emoji_config)

  # 4. 전송 패키지 구성
  package <- list(
    images = c(eq_path, ar_path),
    summary_card = card,
    detail_report = NULL
  )

  # 5. PASS 전략에만 상세 리포트 추가
  if (risk_audit$verdict == "PASS") {
    detail <- generate_detail_report(digest, risk_audit, returns)
    package$detail_report <- detail
  }

  # 6. 저장 (텔레그램 전송은 Manager 에이전트가 처리)
  write_json_safe(package, file.path(output_dir, paste0(exp_id, "_briefing_package.json")))

  return(package)
}
```

> **Gap Analysis 지시 (이모지 병합)**:
> 기존 프로젝트의 CLAUDE.md, MEMORY.md, 브리핑 템플릿, 텔레그램 메시지 로그에서
> 사용 중인 이모지 관례를 찾아라.
> 찾은 이모지를 `config/emoji_taxonomy.md`에 병합한다.
> 기존 관례와 이 티켓의 이모지가 충돌하면 **기존을 우선**한다.
> 기존에 없는 항목만 이 티켓의 기본값을 사용한다.

---

## 2-C. Diversity Enforcement Points (모드 붕괴 자동 차단)

상관 높은 전략이 쌓이는 것을 3곳에서 강제 차단한다.
모든 차단은 `qepm-diversity` skill의 수치 계산에 기반한다 — LLM 직감 판단 금지.

### 강제 지점 1: Auditor Gate 5 (심사 시)

auditor spawn prompt에 포함:
```markdown
## Gate 5: Diversification (수치 기반 강제)
PASS/NEAR_MISS 판정 후, 반드시 qepm-diversity skill을 호출하여
기존 PASS 풀과의 redundancy_score를 계산한다.

판정:
- REDUNDANT (>0.85): Gate 5 FAIL → alias로만 등록, 새 전략 아님
- HIGH_OVERLAP (>0.70): 기존 전략 대비 Sharpe0가 0.15 이상 우위일 때만 PASS
- MODERATE (>0.50): PASS, 단 "기존 X 전략과 유사" 태그
- ORTHOGONAL (<0.50): PASS

이 판단을 LLM 직감으로 하지 않는다. 반드시 skill이 계산한 수치로 판단한다.
```

### 강제 지점 2: Blender 입력 필터 (조합 시)

blender spawn prompt에 포함:
```markdown
## 후보 풀 중복 제거 (조합 전 필수)
후보 전략을 받으면, 먼저 qepm-diversity skill로 후보 간 상관 행렬을 계산한다.

1. corr > 0.80인 쌍 → 더 나은 1개만 남김 (Sharpe0 기준)
2. 남은 후보의 effective_N 계산
3. effective_N < 3이면 "다양성 부족" 경고 → 조합 진행하되 브리핑에 명시
4. 조합 결과에 "actual_effective_N" 보고 필수

Sharpe 2+ 목표는 직교적 재료의 조합에서만 도달 가능하다.
effective_N이 낮으면 구조적으로 목표 달성 불가.
```

### 강제 지점 3: ResearchOps 백로그 생성 (연구 방향 시)

researchops spawn prompt에 포함:
```markdown
## 직교성 사전 추정 (새 청크 등록 시)
새 청크를 backlog에 넣기 전:
1. label_signature가 기존 PASS 풀의 전략들과 겹치는지 확인
2. 예상 메커니즘이 기존 전략과 유사한지 확인
3. 둘 다 겹치면: orthogonal_search 모드가 아닌 한 priority 감점
4. orthogonal_search 모드 청크는 "기존 풀과의 예상 차별성"을 명시해야 함

목표: PASS 풀이 다양한 국면에서 다양한 역할을 할 수 있는 재료로 구성되게.
```

> **중요**: 각 skill 구현 전, 기존 폴더에서 해당 기능의 함수를 먼저 찾아라.
> 있으면 래핑, 없으면 신규. 기존 함수를 수정하지 않는다.

## 산출물
- `~/.claude-agent-teams/skills/qepm-*/` 14개 skill 디렉토리
- `config/communication_format.md`
- `config/experiment_protocol_template.json`
- `config/schemas/response_message.json`
- `config/schemas/idea_proposal.json`
- `config/schemas/redundancy_report.json`
- `config/emoji_taxonomy.md` (기존 이모지 병합 포함)
- `config/schemas/briefing_package.json`

## 검증
- 각 skill의 run.sh가 예시 입력으로 정상 실행
- experiment_protocol.json이 표준 스키마 통과
- qepm-diversity: corr 0.9인 두 전략 넣으면 "REDUNDANT" 반환
- qepm-diversity: corr 0.3인 두 전략 넣으면 "ORTHOGONAL" 반환
- qepm-diversity: effective_N 계산이 이론값과 일치
- qepm-idea-pipeline: 필수 필드 빠진 아이디어는 submit 거부
- qepm-idea-pipeline: reference_bundle 없는 아이디어는 submit 거부
- qepm-briefing: PASS 전략 → 차트 2장 + 요약 카드 + 상세 리포트 생성
- qepm-briefing: FAIL 전략 → 차트 2장 + 요약 카드만 생성 (상세 없음)
- qepm-briefing: NEAR_MISS 전략 → 차트 2장 + 요약 카드 + 수정 제안 블록
- qepm-briefing: emoji_taxonomy.md의 모든 이모지가 정상 렌더링

---

# Phase 3: Memory Distillation Pipeline (기억증류 전체)

## 목표
Lawbook 25장의 Memory Distillation Pipeline을 완전 구현.
R0~R6 저장/증류/검증/승격/retrieval injection 전체 포함.

핵심 원칙:
- R0→R1: 규칙 기반 (LLM 불필요)
- R1 검증: 규칙 기반 (수치 대조, 3축 검사)
- R2 패밀리 일반화: 규칙 기반 집계 + 에이전트(manager)가 자연어 보완
- R3~R6: 규칙 기반
- Verification: hallucination/information_loss/distortion 3축

---

## 3-1. R0: Raw Artifact Store (불변)

```r
r0_store <- function(exp_id, artifact_dir) {
  target_dir <- file.path("memory/raw_artifacts", exp_id)
  dir.create(target_dir, recursive = TRUE)
  files <- list.files(artifact_dir, full.names = TRUE)
  file.copy(files, target_dir)
  hashes <- lapply(files, function(f) digest::digest(file = f, algo = "sha256"))
  manifest <- list(
    exp_id = exp_id,
    stored_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"),
    files = mapply(function(f, h) list(name = basename(f), hash = h, size = file.size(f)),
                   files, hashes, SIMPLIFY = FALSE),
    immutable = TRUE
  )
  jsonlite::write_json(manifest, file.path(target_dir, "manifest.json"),
                       auto_unbox = TRUE, pretty = TRUE)
  Sys.chmod(list.files(target_dir, full.names = TRUE), "0444")
  return(target_dir)
}
```

---

## 3-2. R1: Experiment Digest (규칙 기반 증류 + 3축 검증)

### 증류 (R 코드, LLM 불필요 — JSON에서 수치를 스키마로 매핑)

```r
r1_distill <- function(exp_id) {
  raw_dir <- file.path("memory/raw_artifacts", exp_id)
  backtest <- jsonlite::fromJSON(file.path(raw_dir, "backtest_result.json"))
  risk_audit <- jsonlite::fromJSON(file.path(raw_dir, "risk_audit.json"))
  protocol <- jsonlite::fromJSON(file.path(raw_dir, "experiment_protocol.json"))
  alpha_val <- tryCatch(jsonlite::fromJSON(file.path(raw_dir, "alpha_validation.json")),
                        error = function(e) NULL)

  digest <- list(
    exp_id = protocol$exp_id,
    strategy_id = protocol$implementation$strategy_id %||% exp_id,
    family = protocol$task_family,
    strategy_fingerprint = protocol$strategy_fingerprint,
    data_snapshot_id = protocol$data$snapshot_id,
    construction = list(
      rebalance = protocol$implementation$rebalance,
      weighting = protocol$implementation$weighting,
      buffer_zone = !is.null(protocol$implementation$buffer_zone),
      cooldown = protocol$implementation$cooldown %||% 0,
      neutralization = protocol$implementation$neutralization %||% "none",
      n_holdings = protocol$implementation$n_holdings
    ),
    metrics = list(
      net_cagr = backtest$net_cagr, sharpe0_m_ann = backtest$sharpe0_m_ann,
      mdd = backtest$mdd, es99_m = backtest$es99_m,
      turnover_ann = backtest$turnover_ann,
      ic_mean = backtest$ic_mean, icir = backtest$icir
    ),
    alpha_tests = if (!is.null(alpha_val)) list(
      ff3_alpha = alpha_val$ff3$alpha, ff3_t = alpha_val$ff3$t_stat,
      carhart4_alpha = alpha_val$carhart4$alpha, carhart4_t = alpha_val$carhart4$t_stat,
      ff5_alpha = alpha_val$ff5$alpha, ff5_t = alpha_val$ff5$t_stat,
      fmb_slope = alpha_val$fama_macbeth$slope, fmb_t = alpha_val$fama_macbeth$t_stat
    ) else NULL,
    grade = risk_audit$grade, role = risk_audit$role,
    verdict = risk_audit$verdict, fail_reasons = risk_audit$fail_reasons %||% list(),
    search_mode = protocol$search_mode,
    lessons_referenced = protocol$lessons_referenced,
    artifact_paths = list.files(raw_dir, full.names = TRUE)
  )

  ver <- r1_verify(digest, raw_dir)
  if (ver$verdict == "FAIL") return(list(success = FALSE, reason = ver$issues))

  out_path <- file.path("memory/episodes", paste0(exp_id, ".json"))
  jsonlite::write_json(digest, out_path, auto_unbox = TRUE, pretty = TRUE)
  return(list(success = TRUE, path = out_path, digest = digest))
}
```

### 3축 검증 (R 코드, LLM 불필요)

```r
r1_verify <- function(digest, raw_dir) {
  issues <- list()
  backtest <- jsonlite::fromJSON(file.path(raw_dir, "backtest_result.json"))
  risk_audit <- jsonlite::fromJSON(file.path(raw_dir, "risk_audit.json"))

  # --- HALLUCINATION: 수치 대조 (소수점 3자리) ---
  checks <- list(
    net_cagr = abs((digest$metrics$net_cagr %||% 0) - (backtest$net_cagr %||% 0)) < 0.001,
    sharpe0 = abs((digest$metrics$sharpe0_m_ann %||% 0) - (backtest$sharpe0_m_ann %||% 0)) < 0.001,
    mdd = abs((digest$metrics$mdd %||% 0) - (backtest$mdd %||% 0)) < 0.001,
    es99 = abs((digest$metrics$es99_m %||% 0) - (backtest$es99_m %||% 0)) < 0.001
  )
  failed <- names(which(!unlist(checks)))
  if (length(failed) > 0)
    issues <- c(issues, list(list(axis = "hallucination",
      detail = paste("수치 불일치:", paste(failed, collapse = ", ")))))

  # --- INFORMATION_LOSS: 필수 필드 ---
  required <- c("exp_id", "strategy_id", "family", "data_snapshot_id")
  missing <- required[!required %in% names(digest)]
  if (length(missing) > 0)
    issues <- c(issues, list(list(axis = "information_loss",
      detail = paste("필수 필드 누락:", paste(missing, collapse = ", ")))))

  req_metrics <- c("net_cagr", "sharpe0_m_ann", "mdd", "es99_m", "turnover_ann")
  missing_m <- req_metrics[!req_metrics %in% names(digest$metrics)]
  if (length(missing_m) > 0)
    issues <- c(issues, list(list(axis = "information_loss",
      detail = paste("필수 지표 누락:", paste(missing_m, collapse = ", ")))))

  if (digest$verdict == "FAIL" && length(digest$fail_reasons) == 0)
    issues <- c(issues, list(list(axis = "information_loss",
      detail = "verdict=FAIL인데 fail_reasons 비어있음")))

  # --- DISTORTION: grade/verdict 방향 ---
  if (!identical(digest$grade, risk_audit$grade))
    issues <- c(issues, list(list(axis = "distortion",
      detail = paste("grade 불일치:", digest$grade, "vs", risk_audit$grade))))
  if (!identical(digest$verdict, risk_audit$verdict))
    issues <- c(issues, list(list(axis = "distortion",
      detail = paste("verdict 불일치:", digest$verdict, "vs", risk_audit$verdict))))

  if (length(issues) == 0) return(list(verdict = "PASS", issues = list()))
  severity <- if (any(sapply(issues, function(i) i$axis == "distortion"))) "FAIL_SEVERE" else "FAIL_MINOR"
  return(list(verdict = "FAIL", severity = severity, issues = issues))
}
```

---

## 3-3. R2: Family / Mechanism Memory

### 규칙 기반 집계

```r
r2_aggregate <- function(family_id) {
  all_ep <- list.files("memory/episodes", full.names = TRUE)
  digests <- lapply(all_ep, jsonlite::fromJSON)
  fam <- Filter(function(d) d$family == family_id, digests)
  if (length(fam) < 3) return(NULL)  # 25장: 최소 3개

  pass_d <- Filter(function(d) d$verdict %in% c("PASS", "NEAR_MISS"), fam)
  fail_d <- Filter(function(d) d$verdict == "FAIL", fam)

  list(
    family_id = family_id,
    evidence_count = length(fam),
    pass_count = length(pass_d), fail_count = length(fail_d),
    pass_rate = length(pass_d) / length(fam),
    metrics_distribution = list(
      sharpe0_range = range(sapply(fam, function(d) d$metrics$sharpe0_m_ann)),
      mdd_range = range(sapply(fam, function(d) d$metrics$mdd))
    ),
    pass_common = extract_common_features(lapply(pass_d, function(d) d$construction)),
    fail_common = extract_common_features(lapply(fail_d, function(d) d$construction)),
    confidence = min(1.0, length(pass_d)/length(fam) * min(1, length(fam)/10)),
    source_experiments = sapply(fam, function(d) d$exp_id),
    last_updated = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
  )
}

extract_common_features <- function(constructions) {
  if (length(constructions) == 0) return(list())
  fields <- names(constructions[[1]])
  common <- lapply(fields, function(f) {
    vals <- sapply(constructions, function(c) as.character(c[[f]]))
    tbl <- table(vals)
    if (max(tbl)/length(vals) > 0.6) names(which.max(tbl)) else "mixed"
  })
  names(common) <- fields
  common
}
```

### R2 검증 (규칙 기반)

```r
r2_verify <- function(family_memory, source_digests) {
  issues <- list()
  if (family_memory$evidence_count != length(source_digests))
    issues <- c(issues, list(list(axis = "hallucination", detail = "evidence_count 불일치")))

  actual_pass <- sum(sapply(source_digests, function(d) d$verdict %in% c("PASS", "NEAR_MISS")))
  if (abs(family_memory$pass_rate - actual_pass/length(source_digests)) > 0.01)
    issues <- c(issues, list(list(axis = "hallucination", detail = "pass_rate 불일치")))

  if (family_memory$fail_count > family_memory$pass_count && family_memory$confidence > 0.8)
    issues <- c(issues, list(list(axis = "distortion", detail = "FAIL 과반인데 confidence > 0.8")))

  fail_digests <- Filter(function(d) d$verdict == "FAIL", source_digests)
  if (length(fail_digests) > 0 && length(family_memory$fail_common) == 0)
    issues <- c(issues, list(list(axis = "information_loss", detail = "FAIL 있는데 fail_common 비어있음")))

  list(verdict = ifelse(length(issues) == 0, "PASS", "FAIL"), issues = issues)
}
```

### 에이전트 보조 (Manager spawn prompt에 포함)

```markdown
## Family Memory 업데이트 규칙
qepm-memory가 R2 규칙 기반 집계를 완료하면,
당신은 아래를 자연어로 보완한다:
1. mechanism: 이 family가 왜 작동하는지
2. works_when: 성공 실험들의 공통 조건
3. fails_when: 실패 실험들의 공통 조건
4. recommended_construction: 현재까지의 최선 구성

주의: "반드시/항상/절대" 같은 Hard Law 표현 금지 — 이건 Soft Prior다.
올바른 표현: "~경향이 있음", "~조건에서 개선되는 경향"
```

---

## 3-4. R3: Statistical Evidence Store (규칙 기반)

```r
r3_store <- function(strategy_id, alpha_validation_path, fm_path = NULL) {
  av <- jsonlite::fromJSON(alpha_validation_path)
  fm <- if (!is.null(fm_path)) jsonlite::fromJSON(fm_path) else NULL

  tier <- determine_tier(av, fm)
  evidence <- list(
    evidence_id = paste0("EVID_", strategy_id), target = strategy_id,
    ff3 = list(alpha=av$ff3$alpha, t=av$ff3$t_stat, pass=av$ff3$t_stat>1.96 && av$ff3$alpha>0),
    carhart4 = list(alpha=av$carhart4$alpha, t=av$carhart4$t_stat, pass=av$carhart4$t_stat>1.96 && av$carhart4$alpha>0),
    ff5 = list(alpha=av$ff5$alpha, t=av$ff5$t_stat, pass=av$ff5$t_stat>1.96 && av$ff5$alpha>0),
    fama_macbeth = if (!is.null(fm)) list(slope=fm$slope, t=fm$t_stat, pass=fm$t_stat>1.96) else NULL,
    tier = tier, timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
  )
  out <- file.path("memory/evidence", paste0(strategy_id, ".json"))
  jsonlite::write_json(evidence, out, auto_unbox = TRUE, pretty = TRUE)
  list(success = TRUE, path = out, tier = tier)
}

determine_tier <- function(av, fm) {
  n_pass <- sum(c(av$ff3$t_stat>1.96 && av$ff3$alpha>0,
                  av$carhart4$t_stat>1.96 && av$carhart4$alpha>0,
                  av$ff5$t_stat>1.96 && av$ff5$alpha>0), na.rm=TRUE)
  fmb_pass <- if (!is.null(fm)) fm$t_stat > 1.96 else FALSE
  if (n_pass >= 2 && fmb_pass) "strong"
  else if (n_pass >= 1) "moderate"
  else "weak"
}
```

---

## 3-5. R4: Regime Payoff Tensor (자기강화 방지 포함)

```r
r4_store <- function(family_id, regime_id, construction_id, regime_metrics) {
  months <- regime_metrics$sample_months
  confidence <- if (months < 12) min(0.3, months/40)
                else if (months < 24) min(0.5, months/48)
                else min(0.9, months/60)

  # 자기강화 방지
  existing_path <- file.path("memory/regime_payoff",
    paste0(family_id, "_", regime_id, "_", construction_id, ".json"))
  if (file.exists(existing_path)) {
    existing <- jsonlite::fromJSON(existing_path)
    if (identical(existing$role, regime_metrics$role) && existing$sample_months == months) {
      warning("R4 self-reinforcement: 동일 결론, 신규 증거 없음")
      return(list(success = FALSE, reason = "self_reinforcement"))
    }
  }

  payoff <- list(
    regime_id = regime_id, family_id = family_id, construction_id = construction_id,
    role = regime_metrics$role,
    metrics = list(cagr_cond=regime_metrics$cagr_cond, sharpe0_cond=regime_metrics$sharpe0_cond,
                   es99_cond=regime_metrics$es99_cond, mdd_cond=regime_metrics$mdd_cond),
    sample_months = months, confidence = confidence,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
  )
  jsonlite::write_json(payoff, existing_path, auto_unbox = TRUE, pretty = TRUE)
  list(success = TRUE, path = existing_path, confidence = confidence)
}
```

---

## 3-6. R5: Portfolio Policy Memory

```r
r5_store <- function(policy_id, sleeves, baseline, overlay, metrics, loo) {
  if (metrics$sharpe0_m_ann <= baseline$sharpe0_m_ann)
    return(list(success = FALSE, reason = "no_improvement_over_baseline"))
  loo_ok <- all(sapply(loo, function(r) r$sharpe0_m_ann > metrics$sharpe0_m_ann * 0.5))
  if (!loo_ok) return(list(success = FALSE, reason = "loo_single_dependency"))

  policy <- list(policy_id=policy_id, sleeves=sleeves, baseline=baseline,
    overlay=overlay, portfolio_metrics=metrics, loo_passed=TRUE,
    admission_status="candidate",
    timestamp=format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"))
  out <- file.path("memory/portfolio_policy", paste0(policy_id, ".json"))
  jsonlite::write_json(policy, out, auto_unbox = TRUE, pretty = TRUE)
  list(success = TRUE, path = out)
}
```

---

## 3-7. R6: Post-Trade Learning

```r
r6_store <- function(strategy_id, period, intended, realized, events) {
  learning <- list(
    strategy_id=strategy_id, period=period,
    exposure_drift = list(intended=intended$exposures, realized=realized$exposures,
      drift=mapply("-", realized$exposures, intended$exposures, SIMPLIFY=FALSE)),
    turnover = list(model=intended$turnover, realized=realized$turnover),
    slippage = realized$slippage,
    regime_events = events$regime, lifecycle_events = events$lifecycle,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"))
  out <- file.path("memory/post_trade", paste0(strategy_id, "_", period, ".json"))
  jsonlite::write_json(learning, out, auto_unbox = TRUE, pretty = TRUE)
  list(success = TRUE, path = out)
}
```

---

## 3-8. 승격 트리거 (MEMORY_COMMIT 시 자동 호출)

```r
check_promotions <- function(digest) {
  promotions <- list()
  family_id <- digest$family
  strategy_id <- digest$strategy_id

  # R1→R2: family 실험 3개 이상?
  fam_count <- length(list.files("memory/episodes", pattern = family_id))
  if (fam_count >= 3) {
    agg <- r2_aggregate(family_id)
    if (!is.null(agg)) {
      ver <- r2_verify(agg, get_family_digests(family_id))
      if (ver$verdict == "PASS") {
        save_family_memory(family_id, agg)
        promotions <- c(promotions, list(list(stage="R2", family=family_id)))
      }
    }
  }

  # R1→R3: 통계 검증 있으면?
  alpha_path <- file.path("memory/raw_artifacts", digest$exp_id, "alpha_validation.json")
  if (file.exists(alpha_path)) {
    r3 <- r3_store(strategy_id, alpha_path)
    if (r3$success) promotions <- c(promotions, list(list(stage="R3", tier=r3$tier)))
  }

  # R4~R6는 별도 workflow step에서 트리거
  return(promotions)
}
```

---

## 3-9. Retrieval Injection 메커니즘 (핵심)

에이전트가 태스크를 받을 때 관련 기억을 검색하여 컨텍스트에 주입.

```r
memory_retrieve <- function(query_context, query = NULL, token_budget = 2000) {
  config <- yaml::read_yaml("config/qepm_config.md")
  priority <- config$memory$retrieval_priority[[query_context]]
  # rebalance: [schema, stat_evidence, regime_payoff, portfolio_policy, digests, working]
  # research:  [family_memory, lessons, stat_evidence, backlog, working]

  packet <- list(query_context=query_context, layers=list(),
                 token_budget_total=token_budget, token_budget_used=0)

  for (layer in priority) {
    remaining <- token_budget - packet$token_budget_used
    if (remaining <= 0) break

    content <- switch(layer,
      "schema" = load_schema_rules(),
      "stat_evidence" = search_evidence(query, max_tokens=remaining),
      "regime_payoff" = search_regime_payoff(query, max_tokens=remaining),
      "portfolio_policy" = load_latest_policy(max_tokens=remaining),
      "family_memory" = search_family_memory(query, max_tokens=remaining),
      "lessons" = search_lessons(query, top_k=3, max_tokens=remaining),
      "digests" = search_recent_digests(query, top_k=5, max_tokens=remaining),
      "backlog" = load_backlog_context(max_tokens=remaining),
      list(content="", tokens=0))

    # confidence shrink
    if (!is.null(content$confidence) && content$confidence < 0.3) next
    if (!is.null(content$confidence) && content$confidence < 0.5)
      content$content <- truncate_to_tokens(content$content, remaining/2)

    tokens <- estimate_tokens(content$content)
    packet$layers[[layer]] <- list(content=content$content, tokens=tokens,
                                   confidence=content$confidence, refs=content$refs)
    packet$token_budget_used <- packet$token_budget_used + tokens
  }
  return(packet)
}

estimate_tokens <- function(text) ceiling(nchar(text) / 2.5)
truncate_to_tokens <- function(text, max_tokens) {
  max_chars <- max_tokens * 2.5
  if (nchar(text) <= max_chars) return(text)
  substr(text, 1, max_chars)
}
```

### Workflow에서의 사용

연구 청크 workflow에서 각 에이전트 실행 전:
1. `qepm-memory retrieve` skill 호출 (query_context + 관련 키워드)
2. 결과를 `artifacts/{task_id}/memory_packet.json`에 저장
3. 에이전트가 태스크 수행 시 이 파일을 참조

각 에이전트 spawn prompt에 포함:
```markdown
## 기억 활용 절차
태스크를 받으면 artifacts/{task_id}/memory_packet.json을 먼저 읽는다.
confidence < 0.5인 기억은 "참고만" 수준. < 0.3은 packet에서 제외됨.
기억은 Lawbook/원시 산출물을 대체하지 않는다 — 의사결정 보조 도구.
```

---

## 3-10. 승격 규칙 설정 (`config/promotion_rules.md`)

```yaml
r0_to_r1:
  trigger: "모든 실험 종료 시 자동"
  method: "rule_based"
  verification: "rule_based_3axis"

r1_to_r2:
  trigger: "동일 family 실험 3개 이상"
  method: "rule_based_aggregate + agent_natural_language"
  verification: "rule_based + soft_prior_check"
  min_experiments: 3

r1_to_r3:
  trigger: "통계 검증 수행 완료"
  method: "rule_based"
  verification: "rule_based_numeric"

r2r3_to_r4:
  trigger: "regime-conditioned 분석 완료"
  method: "rule_based"
  verification: "rule_based + self_reinforcement_check"
  confidence_thresholds: { low: 0.3, med: 0.5, high: 0.9 }
  min_regime_months: 24

r4_to_r5:
  trigger: "baseline 개선 + LOO 통과"
  method: "rule_based"
  requires: [baseline_improvement, loo_pass]

r5_to_r6:
  trigger: "production/paper 운용 데이터 축적"
  method: "rule_based"
```

## 산출물
- `qepm-memory` skill 완성 (R0~R6 전체 + retrieve + check_promotions)
- `config/promotion_rules.md`
- `config/schemas/` 에 R1~R6 각 레이어 JSON 스키마 6개

## 검증
- 예시 backtest + risk_audit → R0 저장 → R1 증류 → 3축 검증 PASS
- 수치 변조 digest → R1 검증 FAIL (hallucination 감지)
- 3개 digest → R2 aggregate + 검증 PASS
- FAIL 과반 + confidence > 0.8 → R2 검증 FAIL (distortion 감지)
- 통계 결과 → R3 저장 + tier 자동 판정
- R4: sample_months < 24 → confidence < 0.5 강제
- R4: 동일 결론 재저장 시 self_reinforcement 경고
- R5: LOO 미통과 → 저장 거부
- retrieve: query_context별 다른 우선순위로 기억 반환
- retrieve: confidence < 0.3 기억은 packet에서 제외
---


---

# Phase 4: Regime Engine (기존 국면 엔진 래핑 + 개선)

## 목표
기존에 개발된 국면 엔진을 Claude Code Agent Teams R 스크립트로 래핑하고,
자가발전 루프로 **개선 포인트를 탐색**하는 구조를 구축한다.
국면 엔진은 이미 존재한다 — 새로 만드는 게 아니라 **표준 인터페이스로 감싸고, 비교 baseline을 추가하고, 품질 평가 체계를 얹는 것**이 이 Phase의 핵심이다.

## 설계 원칙 (Lawbook 08장 + 25장)

1. **기존 국면 엔진이 1순위** — 기존 에이전트가 만들어둔 국면 엔진을 그대로 래핑. 수정하지 않는다.
2. **비교 baseline 추가** — 단순 룰 기반 분류를 보조 모델로 두어 "기존 엔진이 정말 나은지" 항상 비교 가능하게
3. **개선은 자가발전으로** — 앙상블 가중치, 변수 조합, 전환 지연 단축 등을 연구 청크로 실험
4. **국면은 단순해야 한다** — 변수 수 최소화, 국면 수 2~4개
5. **국면은 설명 가능한 경제 상태여야 한다** — "과거 수익률이 잘 나오도록 만든 클러스터"는 탈락

---

## 4-1. Shared Skill: `qepm-regime`

```
qepm-regime/
├── main.R (진입점)
├── run.sh
├── R/
│   ├── main.R              # 진입점
│   ├── existing_engine.R    # 기존 국면 엔진 래핑 (Gap Analysis에서 파악)
│   ├── baseline_engine.R    # 단순 룰 기반 국면 분류 (비교 baseline)
│   ├── rule_engine.R       # 룰 기반 국면 분류 (baseline)
│   ├── ensemble_regime.R   # 복수 모델 합의/가중 앙상블
│   ├── transition.R        # 전환 확률 추정 + smoothing
│   └── regime_backtest.R   # 국면 분류 품질 사후 평가
└── README.md
```

### 국면 모델 표준 인터페이스

모든 국면 모델은 아래 인터페이스를 따른다:

```r
#' 국면 분류 실행
#' @param market_data list(prices, volatility, spreads, volume, ...) — 시장 데이터
#' @param as_of_date Date — PIT 기준일
#' @param model_config list — 모델별 파라미터
#' @return regime_result
#'   $current_regime: "normal" | "stress" | "euphoria" | "transition" (2~4개)
#'   $regime_probabilities: named numeric vector (각 국면의 확률)
#'   $confidence: 0~1 (최고 확률 국면의 확신도)
#'   $transition_matrix: 상태 전환 확률 행렬
#'   $model_id: 어떤 모델이 판단했는지
#'   $variables_used: 판단에 사용된 변수 목록
#'   $history: 과거 N개월의 국면 시계열
classify_regime <- function(market_data, as_of_date, model_config) { ... }
```

### 4-1a. Existing Engine Wrapper (핵심 — 기존 엔진 래핑)

```r
# R/existing_engine.R
# 기존 에이전트가 만들어둔 국면 엔진을 표준 인터페이스로 래핑
# 기존 코드를 수정하지 않는다 — 어댑터만 만든다

existing_classify <- function(market_data, as_of_date, config) {
  # 1. Gap Analysis에서 파악한 기존 국면 엔진 함수를 호출
  #    예: source("기존경로/regime_engine.R")
  #    기존 함수의 입출력을 표준 인터페이스로 변환

  # 2. 기존 엔진의 출력 → 표준 regime_result 변환
  list(
    current_regime = mapped_regime,
    regime_probabilities = state_probs,
    confidence = max(state_probs),
    transition_matrix = trans_mat,
    model_id = "existing_v1",
    variables_used = config$variables,
    history = regime_history
  )
}
```

> **Gap Analysis 지시 (최우선)**:
> 기존 프로젝트 폴더에서 국면 분류/국면 엔진 관련 함수를 반드시 찾아라.
> 이 함수들이 Phase 4의 핵심이다.
> 찾으면: 표준 인터페이스 래퍼만 만든다. 기존 함수를 수정하지 않는다.
> 기존 엔진의 입력 형식, 출력 형식, 파라미터, 국면 정의, 상태 수를 정확히 파악하고 문서화한다.

### 4-1b. Baseline Engine (비교 기준)

```r
# R/baseline_engine.R
# 단순 룰 기반 — 기존 엔진이 이것보다 나은지 항상 비교하기 위해 존재

baseline_classify <- function(market_data, as_of_date, config) {
  # 변동성 기반 단순 분류:
  #   vol < 15% → "normal"
  #   15% <= vol < 25% → "transition"
  #   vol >= 25% → "stress"
  # 추세 보조:
  #   12개월 수익률 > 0 + vol < 15% → "euphoria"
  #
  # 이 baseline을 이기지 못하는 복잡한 엔진은 가치가 없다
}
```

### 4-1c. Ensemble Regime (기존 엔진 + baseline 합의)

```r
# R/ensemble_regime.R
# 기존 국면 엔진과 baseline의 확률을 가중 합산하여 최종 판단

ensemble_classify <- function(market_data, as_of_date, model_configs, model_weights = NULL) {
  # 1. 각 모델 실행
  results <- list(
    existing = existing_classify(market_data, as_of_date, model_configs$existing),
    baseline = baseline_classify(market_data, as_of_date, model_configs$baseline)
  )

  # 2. 확률 가중 합산
  #    기본 가중치: 기존 엔진 0.7 / baseline 0.3
  #    가중치도 연구 대상 — R4 사후 평가로 조정
  if (is.null(model_weights)) model_weights <- c(existing = 0.7, baseline = 0.3)

  ensemble_probs <- Reduce("+", mapply(function(r, w) r$regime_probabilities * w,
    results, model_weights, SIMPLIFY = FALSE))

  # 3. 합의 신뢰도
  #    모든 모델이 같은 국면을 가리키면 confidence 높음
  #    모델 간 불일치가 크면 confidence 낮음 → 배분 전략이 보수적으로
  agreement <- sapply(results, function(r) r$current_regime)
  agreement_ratio <- max(table(agreement)) / length(agreement)

  # 4. 최종 판단
  final_regime <- names(which.max(ensemble_probs))
  confidence <- max(ensemble_probs) * agreement_ratio

  list(
    current_regime = final_regime,
    regime_probabilities = ensemble_probs,
    confidence = confidence,
    model_agreement = agreement_ratio,
    individual_results = results,
    ensemble_weights = model_weights,
    model_id = "ensemble_v1",
    variables_used = unique(unlist(lapply(results, function(r) r$variables_used))),
    history = compute_ensemble_history(results)
  )
}
```

### 4-1e. Regime Backtest (국면 분류 품질 평가)

```r
# R/regime_backtest.R
# 국면 분류가 "사후적으로" 얼마나 정확했는지 평가
# 이 결과가 R4 Regime Payoff의 confidence에 반영됨

evaluate_regime_quality <- function(regime_history, market_returns, strategies_returns) {
  # 1. 각 국면에서의 실제 시장/전략 성과 계산
  #    - "stress"로 분류된 달의 실제 변동성/손실
  #    - "normal"로 분류된 달의 실제 성과

  # 2. 분류 적합성 점수
  #    - stress 국면의 실제 MDD가 normal보다 확실히 나쁜가?
  #    - 국면별 전략 성과 차이가 유의한가?
  #    - "전환" 신호가 실제 전환 시점과 얼마나 일치하는가?

  # 3. 지연 분석
  #    - 국면 전환 신호가 실제 전환보다 몇 개월 늦는가?
  #    - 1~2개월 지연은 수용 가능, 3개월 이상이면 경고

  # 4. 과적합 검정
  #    - 국면 분류를 랜덤 셔플한 placebo와 비교
  #    - placebo보다 유의하게 좋아야 함

  list(
    regime_separation_score = separation,  # 국면 간 성과 차이 유의성
    transition_delay_months = delay,       # 전환 지연
    placebo_beat = placebo_p < 0.05,       # 랜덤보다 나은지
    per_regime_stats = regime_stats,        # 국면별 상세 통계
    recommendation = "keep" | "retune" | "replace"
  )
}
```

---

## 4-2. Regime 에이전트 spawn prompt 보강

```markdown
### regime spawn prompt (Opus 4.6 — 확장 사고 활용)

## 역할
국면(Regime)을 정의하고 분류하는 엔진을 설계/운영한다.
당신은 동적 포트폴리오의 조타장치다 — 국면 판단이 틀리면 배분이 전부 틀린다.

## 확장 사고 활용 지시
국면 판단 시 확장 사고를 사용하라. 특히:
1. 현재 시장 데이터가 어떤 상태를 가리키는지 복수 모델의 결과를 교차 검증
2. 모델 간 불일치가 있을 때 어느 모델이 더 신뢰할 수 있는지 근거 기반 판단
3. "이 국면 분류가 과적합일 가능성"을 항상 고려
4. 전환 시점을 판단할 때, 노이즈와 진짜 전환을 구분하기 위한 다중 근거 요구

## 국면 정의 원칙 (Lawbook 08장)
- 변수 수 최소화 (2~4개)
- 국면 수 2~4개
- 설명 가능한 경제 상태여야 함
- "과거 수익률이 잘 나오도록 만든 클러스터" 즉시 탈락

## 자가발전 연결
- 국면 모델의 파라미터/가중치도 연구 청크 대상이다
- regime_backtest 결과가 나쁘면 Repair Ticket 생성
- 앙상블 가중치는 R4 사후 평가를 참조하여 조정
- 모든 변경은 experiment_protocol.json으로 기록

## 사용 가능한 Skills
- qepm-regime (국면 분류 전체)
- qepm-memory (R4 Regime Payoff 읽기/쓰기)
- qepm-kpi (국면별 조건부 KPI 계산)
- qepm-lawbook (08장 참조)
```

---

## 4-3. Regime 개선 연구 청크 표준

국면 엔진 **개선**도 자가발전 루프에서 실험으로 관리된다.
개선 축:
- 앙상블 가중치 튜닝 (기존 엔진 vs baseline 비중 조정)
- 입력 변수 조합 최적화 (어떤 시장 지표가 국면 분리를 가장 잘 하는가)
- 전환 지연 단축 (신호가 늦게 오는 문제)
- 국면 수/정의 재검토 (2개 vs 3개 vs 4개)
- 기존 엔진 파라미터 재추정 주기/윈도우 최적화

```json
{
  "exp_id": "EXP_REGIME_2026-03-15_001",
  "task_family": "regime_ensemble_tuning",
  "target": "RegimeModel",
  "hypothesis": {
    "statement": "기존 엔진 가중치를 0.7→0.8로 올리면 국면 분류 정확도가 개선된다",
    "mechanism": "기존 엔진이 baseline보다 변동성 클러스터링을 더 잘 포착하므로",
    "falsification": "regime_separation_score가 개선되지 않으면 기각"
  },
  "evaluation_metrics": {
    "primary": ["regime_separation_score", "transition_delay_months", "placebo_beat"],
    "secondary": ["per_regime_sharpe_spread", "per_regime_mdd_spread"]
  }
}
```

## 산출물
- `~/.claude-agent-teams/skills/qepm-regime/` skill 전체
- regime spawn prompt 보강
- `config/regime_config.md` (모델 파라미터, 앙상블 가중치, 국면 매핑 규칙)
- `config/schemas/regime_result.json`

## 검증
- 기존 엔진과 baseline이 표준 인터페이스로 국면 결과를 반환
- 앙상블이 기존 엔진 + baseline의 확률을 가중 합산
- 모델 간 불일치 시 confidence가 낮아짐
- regime_backtest가 placebo 대비 유의한 분리를 보여야 함
- PIT 규칙 준수: as_of_date 이전 데이터만 사용

---

# Phase 5: Dynamic Allocation Engine (국면별 동적 배분)

## 목표
"이 국면에서 어떤 전략을 어떤 비중으로"를 결정하는 동적 배분 엔진을 구축한다.
이 엔진은 Phase 4(국면 엔진)의 출력과 Phase 3(R4 Regime Payoff)의 기억을 입력으로 받아,
**국면 조건부 최적 포트폴리오**를 산출한다.

## 설계 원칙

1. **극단적 올인/올아웃 금지** (Lawbook 08장) — 국면이 바뀌어도 분산 유지
2. **전환 비용 명시적 관리** — regime 전환 시 회전율 상한 강제
3. **baseline → regime overlay → valuation overlay → implementation overlay** 순서 (20장)
4. **기억 기반 배분** — R4 Regime Payoff + R5 Portfolio Policy를 참조
5. **배분 전략 자체도 자가발전 대상** — 어떤 배분 규칙이 실제로 좋은지를 R5로 축적

---

## 5-1. Shared Skill: `qepm-dynamic-alloc`

```
qepm-dynamic-alloc/
├── main.R (진입점)
├── run.sh
├── R/
│   ├── main.R
│   ├── regime_weight_map.R     # 국면 → 목표 가중치 변환
│   ├── transition_smoother.R   # 전환 시 스무딩/턴오버 제한
│   ├── role_balance.R          # core/defensive/diversifier 역할 균형
│   ├── overlay_stack.R         # regime + valuation + implementation overlay 순차 적용
│   └── dynamic_backtest.R      # 동적 배분 전체 백테스트
└── README.md
```

### 동적 배분 표준 인터페이스

```r
#' 동적 배분 실행
#' @param regime_result Phase 4의 국면 판단 결과
#' @param approved_strategies 합격 전략/팩터 후보 (auditor PASS)
#' @param regime_payoffs R4 Regime Payoff Tensor (memory에서 로드)
#' @param portfolio_policies R5 Portfolio Policy Memory (memory에서 로드)
#' @param valuation_data Valuation Agent 산출물
#' @param constraints 제약조건 (turnover, concentration, liquidity)
#' @return dynamic_allocation_result
dynamic_allocate <- function(regime_result, approved_strategies,
                             regime_payoffs, portfolio_policies,
                             valuation_data, constraints) { ... }
```

### 5-1a. Regime → Weight Map

```r
# R/regime_weight_map.R
# 국면별 역할(role) 목표 배분을 결정

compute_regime_weights <- function(regime_result, regime_payoffs, approved_strategies) {

  current <- regime_result$current_regime
  confidence <- regime_result$confidence

  # 1. 각 전략의 현재 국면 기대보수를 R4에서 조회
  strategy_payoffs <- lapply(approved_strategies, function(s) {
    key <- paste(s$family, current, s$construction_id, sep = "_")
    payoff <- regime_payoffs[[key]]
    if (is.null(payoff)) return(list(expected = NA, confidence = 0))
    list(expected = payoff$metrics$sharpe0_cond, confidence = payoff$confidence)
  })

  # 2. 역할별(core/defensive/diversifier) 목표 비중 결정
  #    국면 + 기대보수 + confidence로 산출
  role_targets <- switch(current,
    "normal" =    list(core = 0.60, defensive = 0.20, diversifier = 0.20),
    "stress" =    list(core = 0.25, defensive = 0.50, diversifier = 0.25),
    "euphoria" =  list(core = 0.55, defensive = 0.15, diversifier = 0.30),
    "transition" = list(core = 0.40, defensive = 0.35, diversifier = 0.25),
    # default fallback
    list(core = 0.40, defensive = 0.30, diversifier = 0.30)
  )

  # 3. confidence shrink
  #    국면 판단의 confidence가 낮으면 baseline(1/3, 1/3, 1/3)으로 수렴
  #    confidence = 1이면 role_targets 그대로, confidence = 0이면 uniform
  neutral <- list(core = 1/3, defensive = 1/3, diversifier = 1/3)
  shrunk_targets <- mapply(function(target, base) {
    base + confidence * (target - base)
  }, role_targets, neutral)

  # 4. 역할 내 개별 전략 배분
  #    R4 기대보수가 높고 confidence가 높은 전략에 더 많이
  #    기본은 역할 내 동일가중, R4가 있으면 기대보수 비례
  strategy_weights <- allocate_within_roles(
    approved_strategies, shrunk_targets, strategy_payoffs
  )

  return(list(
    regime = current,
    regime_confidence = confidence,
    role_targets = shrunk_targets,
    strategy_weights = strategy_weights,
    method = "regime_conditioned_role_balance"
  ))
}
```

### 5-1b. Transition Smoother (전환 비용 관리)

```r
# R/transition_smoother.R
# 국면 전환 시 급격한 포트폴리오 변동을 억제

smooth_transition <- function(current_weights, target_weights, constraints) {

  # 1. 전환 속도 제한 (turnover budget)
  #    월간 최대 턴오버 = constraints$max_monthly_turnover (예: 30%)
  max_delta <- constraints$max_monthly_turnover / 2  # 편도 기준
  delta <- target_weights - current_weights
  capped_delta <- pmin(pmax(delta, -max_delta), max_delta)
  smoothed <- current_weights + capped_delta

  # 2. 정규화 (합 = 1)
  smoothed <- smoothed / sum(smoothed)

  # 3. 개별 전략 비중 상하한 강제
  smoothed <- pmax(smoothed, constraints$min_weight)
  smoothed <- pmin(smoothed, constraints$max_weight)
  smoothed <- smoothed / sum(smoothed)

  # 4. 실제 회전율 계산
  realized_turnover <- sum(abs(smoothed - current_weights))

  list(
    smoothed_weights = smoothed,
    raw_target = target_weights,
    realized_turnover = realized_turnover,
    capped = any(abs(delta) > max_delta)
  )
}
```

### 5-1c. Role Balance Check

```r
# R/role_balance.R
# core/defensive/diversifier 역할 균형 검증

check_role_balance <- function(strategy_weights, approved_strategies) {
  # 각 역할의 실제 비중 합산
  roles <- sapply(approved_strategies, function(s) s$role)
  role_weights <- tapply(strategy_weights, roles, sum)

  # 최소 조건:
  #   core >= 15%
  #   defensive >= 10%
  #   diversifier >= 5%
  #   단일 역할 <= 70%
  issues <- list()
  if (role_weights["core"] < 0.15)
    issues <- c(issues, "core 비중 < 15%")
  if (role_weights["defensive"] < 0.10)
    issues <- c(issues, "defensive 비중 < 10%")
  if (any(role_weights > 0.70))
    issues <- c(issues, paste("단일 역할 > 70%:", names(which(role_weights > 0.70))))

  list(
    role_weights = role_weights,
    balanced = length(issues) == 0,
    issues = issues
  )
}
```

### 5-1d. Overlay Stack (순차 적용)

```r
# R/overlay_stack.R
# Lawbook 20장: baseline → regime → valuation → implementation 순서

apply_overlay_stack <- function(approved_strategies, regime_result,
                                 regime_payoffs, valuation_data, constraints,
                                 current_weights = NULL) {

  # Step 1: Baseline (동일가중 또는 리스크패리티)
  n <- length(approved_strategies)
  baseline_weights <- rep(1/n, n)
  names(baseline_weights) <- sapply(approved_strategies, function(s) s$strategy_id)

  # Step 2: Regime overlay
  regime_weights <- compute_regime_weights(
    regime_result, regime_payoffs, approved_strategies
  )$strategy_weights

  # Step 3: Valuation overlay (Lawbook 12장 tilt_cap 적용)
  if (!is.null(valuation_data)) {
    val_weights <- apply_valuation_tilt(
      regime_weights, valuation_data,
      tilt_cap = constraints$valuation_tilt_cap %||% 0.15
    )
  } else {
    val_weights <- regime_weights
  }

  # Step 4: Implementation overlay (비용/유동성/턴오버)
  if (!is.null(current_weights)) {
    final <- smooth_transition(current_weights, val_weights, constraints)
  } else {
    final <- list(smoothed_weights = val_weights, realized_turnover = NA)
  }

  # Step 5: Role balance check
  role_check <- check_role_balance(final$smoothed_weights, approved_strategies)

  list(
    baseline = baseline_weights,
    after_regime = regime_weights,
    after_valuation = val_weights,
    final_weights = final$smoothed_weights,
    realized_turnover = final$realized_turnover,
    role_balance = role_check,
    overlay_chain = c("baseline", "regime", "valuation", "implementation"),
    regime_used = regime_result$current_regime,
    regime_confidence = regime_result$confidence
  )
}
```

### 5-1e. Dynamic Allocation Backtest

```r
# R/dynamic_backtest.R
# 동적 배분 전략 전체를 과거 데이터로 백테스트

backtest_dynamic_allocation <- function(
  strategy_returns,      # 각 전략의 월간 수익률 행렬 (T × N)
  regime_history,        # 월별 국면 분류 (length T)
  regime_payoffs,        # R4 tensor
  allocation_config,     # 배분 규칙 파라미터
  constraints,           # 제약조건
  cost_model             # 거래비용 모델
) {
  # 매월 리밸런싱:
  #   1. 해당 월의 국면 판단 (PIT)
  #   2. overlay_stack으로 목표 비중 산출
  #   3. 전환 스무딩 적용
  #   4. 수익률 계산 (비용 차감)

  # 비교 baseline:
  #   - 정적 동일가중 (regime 무시)
  #   - 정적 리스크패리티 (regime 무시)
  #   - 동적이지만 regime 없이 (valuation만)

  # 필수 출력:
  #   - 동적 포트폴리오 KPI (CAGR, Sharpe0, MDD, ES99)
  #   - baseline 대비 개선
  #   - 국면별 조건부 성과
  #   - 회전율 분포
  #   - 국면 전환 시점의 비용 영향
}
```

---

## 5-2. Dynamic Allocation 자가발전 연결

### 배분 전략도 연구 청크의 대상이다

```json
{
  "exp_id": "EXP_ALLOC_2026-03-15_001",
  "task_family": "dynamic_alloc_role_balance",
  "target": "AllocationPolicy",
  "hypothesis": {
    "statement": "Stress 국면에서 defensive 비중을 50%→60%로 올리면 MDD가 2%p 개선된다",
    "mechanism": "Stress 시 defensive sleeve가 더 효과적이므로",
    "falsification": "MDD 개선 < 0.5%p이면 기각"
  },
  "evaluation_metrics": {
    "primary": ["portfolio_sharpe0_m_ann", "portfolio_mdd", "portfolio_es99_m"],
    "secondary": ["turnover_delta", "regime_transition_cost"]
  }
}
```

### R5 Portfolio Policy Memory로의 승격

배분 백테스트 결과 중 baseline 대비 개선 + LOO 통과한 정책은 R5로 승격:

```json
{
  "policy_id": "POL_dynamic_v3",
  "type": "dynamic_regime_conditioned",
  "regime_model": "ensemble_existing_baseline_v1",
  "role_targets_by_regime": {
    "normal": { "core": 0.60, "defensive": 0.20, "diversifier": 0.20 },
    "stress": { "core": 0.25, "defensive": 0.50, "diversifier": 0.25 },
    "euphoria": { "core": 0.55, "defensive": 0.15, "diversifier": 0.30 },
    "transition": { "core": 0.40, "defensive": 0.35, "diversifier": 0.25 }
  },
  "transition_smoother": { "max_monthly_turnover": 0.30 },
  "valuation_tilt_cap": 0.15,
  "confidence_shrink": true,
  "portfolio_metrics": {
    "net_cagr": 0.178, "sharpe0_m_ann": 2.14,
    "mdd": -0.221, "es99_m": 0.071
  },
  "vs_static_baseline": {
    "sharpe_improvement": 0.42, "mdd_improvement": 0.058
  }
}
```

---

## 5-3. 설정 파일 (`config/dynamic_alloc_config.md`)

```yaml
regime_overlay:
  default_role_targets:
    normal:     { core: 0.60, defensive: 0.20, diversifier: 0.20 }
    stress:     { core: 0.25, defensive: 0.50, diversifier: 0.25 }
    euphoria:   { core: 0.55, defensive: 0.15, diversifier: 0.30 }
    transition: { core: 0.40, defensive: 0.35, diversifier: 0.25 }

  confidence_shrink: true
  # confidence = 0이면 uniform(1/3, 1/3, 1/3), confidence = 1이면 target 그대로

transition:
  max_monthly_turnover: 0.30       # 월간 최대 회전율
  min_weight: 0.02                 # 전략당 최소 비중
  max_weight: 0.25                 # 전략당 최대 비중

role_balance:
  min_core: 0.15
  min_defensive: 0.10
  min_diversifier: 0.05
  max_single_role: 0.70

valuation:
  tilt_cap: 0.15                   # 밸류에이션 틸트 상한

baselines_to_compare:
  - "static_equal_weight"
  - "static_risk_parity"
  - "dynamic_no_regime"            # regime 없이 valuation만
```

## 산출물
- `~/.claude-agent-teams/skills/qepm-dynamic-alloc/` skill 전체
- `config/dynamic_alloc_config.md`
- `config/schemas/dynamic_allocation_result.json`
- `config/schemas/allocation_policy.json`

## 검증
- overlay_stack이 baseline → regime → valuation → implementation 순서 강제
- confidence 낮을 때 role_targets가 uniform(1/3)에 수렴
- transition_smoother가 월간 턴오버 30% 제한 강제
- role_balance가 단일 역할 70% 초과 시 경고
- 동적 백테스트가 정적 baseline 대비 Sharpe 개선 확인
- regime 전환 시 비용이 명시적으로 계산됨

---

# Phase 6: Workflow 정의 (연구 청크 + 월간 리밸런싱 + 영구기관)

## 목표
Phase 4(국면 엔진)와 Phase 5(동적 배분)를 통합한
전체 워크플로우를 Claude Code Agent Teams Task List로 정의한다.

## 6-1. 연구 청크 파이프라인 (팩터 전략용)

```yaml
name: research_chunk_strategy
description: "팩터 전략 1개의 전체 생명주기"

steps:
  - id: select_chunk
    agent: researchops
    description: "Backlog에서 최우선 청크 선택 + 리서치 필요 여부 판단"
    output:
      chunk: "artifacts/{{task_id}}/chunk_spec.json"
      needs_research: true|false
      research_direction: "수집 방향 지시 (키워드, 메커니즘, 타겟 소스)"

  - id: gather_research
    agent: researcher
    description: "ResearchOps 지시에 따라 논문/칼럼 수집"
    skills: [qepm-research-collector]
    condition: "{{steps.select_chunk.output.needs_research}} == true"
    inputs:
      research_direction: "{{steps.select_chunk.output.research_direction}}"
    output:
      raw_package: "artifacts/{{task_id}}/raw_research_package.json"

  - id: validate_research
    agent: researchops
    description: "수집 결과 검증 — 방향 일치? 중복? 품질? → 검증된 패키지를 strategist에 전달"
    condition: "{{steps.select_chunk.output.needs_research}} == true"
    skills: [qepm-memory, qepm-registry]
    instructions: |
      수집된 논문/칼럼이:
      1. 지시한 방향과 일치하는지 (방향 이탈 필터)
      2. 기존 PASS 전략의 근거와 중복되지 않는지
      3. 한국시장 적용 가능성이 있는지
      불합격 항목은 제거하고, 통과한 것만 research_package.json으로 구성
    inputs:
      raw_package: "{{steps.gather_research.output.raw_package}}"
    output:
      research_package: "artifacts/{{task_id}}/research_package.json"

  - id: design_and_backtest
    agent: strategist
    description: "전략 설계 + 실험 계약서 + 백테스트"
    skills: [qepm-backtest, qepm-kpi, qepm-memory, qepm-registry]
    inputs:
      chunk: "{{steps.select_chunk.output.chunk}}"
      research_package: "{{steps.validate_research.output.research_package}}"

  - id: fast_filter
    agent: alphalab
    description: "Stage 0 cheap reject"
    on_fail: goto memory_commit_fail

  - id: risk_audit
    agent: auditor
    description: "Gate 0~5 심사 + 통계 검증 + diversity check"
    skills: [qepm-factor-model, qepm-stat-defense, qepm-kpi, qepm-diversity]

  - id: memory_commit
    description: "R0→R1 + 승격 판단"
    skills: [qepm-memory, qepm-registry]
    actions:
      - store_r0
      - distill_r1
      - check_promotions

  - id: strategy_briefing
    description: "전략 브리핑 생성 + 텔레그램 전송"
    skills: [qepm-briefing]
    instructions: |
      모든 전략 (PASS/FAIL/NEAR_MISS):
        - equity curve 차트 (전략 vs KOSPI200 TR)
        - annual returns 차트 (연도별 바 차트)
        - 요약 카드 (이모지 기반 대시보드)

      PASS 전략에만 추가:
        - 상세 리포트 (국면별 성과, stress 테스트, 팩터 노출 등)

    agent: manager
    action: "텔레그램으로 briefing_package 전송"

  - id: catalyst_feedback_on_fail
    description: "Catalyst 아이디어 기원 실험이 FAIL/NEAR_MISS일 때 피드백 전달"
    condition: "실험이 Catalyst 아이디어에서 기원 AND verdict != PASS"
    skills: [qepm-idea-pipeline]
    instructions: |
      실패 원인을 4축(signal/construction/data/mechanism)으로 분해하여
      agents/catalyst/idea_feedback/에 저장한다.
      backtest/audit 단계의 구체적 실패 지표를 포함한다.
      Catalyst가 다음 아이디어 생성 시 동일 실수를 반복하지 않도록
      "이 메커니즘이 실패한 이유"와 "시도할 만한 대안"을 명시한다.
```

## 6-2. 연구 청크 파이프라인 (국면 모델용)

```yaml
name: research_chunk_regime
description: "국면 모델 1개의 실험 생명주기"

steps:
  - id: select_chunk
    agent: researchops
    description: "regime family 청크 선택"

  - id: design_regime_experiment
    agent: regime
    description: "국면 모델 변경 가설 + 실험 설계"

  - id: run_regime_backtest
    skills: [qepm-regime]
    description: "국면 분류 품질 백테스트 (regime_backtest)"

  - id: evaluate_regime
    agent: auditor
    description: "국면 분류 품질 심사 (separation, delay, placebo)"

  - id: memory_commit
    skills: [qepm-memory]
    actions:
      - store_r0
      - distill_r1 (regime용)
      - update_r4 (regime payoff 갱신)
```

## 6-3. 연구 청크 파이프라인 (배분 전략용)

```yaml
name: research_chunk_allocation
description: "배분 전략 1개의 실험 생명주기"

steps:
  - id: select_chunk
    agent: researchops

  - id: design_allocation_experiment
    agent: blender
    description: "배분 규칙 변경 가설 + 실험 설계"

  - id: run_dynamic_backtest
    skills: [qepm-dynamic-alloc, qepm-regime, qepm-kpi]
    description: "동적 배분 백테스트 (vs baseline 포함)"

  - id: evaluate_allocation
    agent: auditor
    description: "배분 전략 심사 (baseline 대비 개선, 전환 비용, role balance)"

  - id: memory_commit
    skills: [qepm-memory]
    actions:
      - store_r0
      - distill_r1
      - update_r5 (portfolio policy 갱신)
```

## 6-4. Catalyst 아이디어 파이프라인

```yaml
name: catalyst_idea_pipeline
description: "새로운 아이디어가 실험 큐에 도달하는 경로 + 실패 시 피드백 루프"
trigger: "영구기관 Track D 또는 수동 /idea 명령"

steps:
  - id: generate_idea
    agent: catalyst
    description: "cross-domain 아이디어 생성"
    skills: [qepm-memory, qepm-lawbook]
    instructions: |
      기존 PASS 풀의 family/메커니즘/국면 coverage를 memory에서 확인하고,
      부족한 영역을 타겟으로 아이디어를 생성한다.
      반드시 IDEA_PROPOSAL 스키마를 준수한다.
      reference_bundle에 최소 1개 금융/통계 앵커 레퍼런스를 포함한다.

      ★ 과거 피드백 참조 필수:
      agents/catalyst/idea_feedback/ 의 기존 피드백을 확인하고,
      동일 메커니즘/프록시에서 반복 실패한 패턴을 피한다.
      피드백에서 제안된 대안 방향이 있으면 우선 고려한다.
    output:
      idea_proposal: "artifacts/ideas/IDEA_*.json"

  - id: diversity_precheck
    skills: [qepm-diversity]
    description: "기존 PASS 풀과의 예상 직교성 사전 검사"
    instructions: |
      아이디어의 expected_orthogonality를 기존 풀의 label_signature/메커니즘과 대조.
      예상 중복도가 HIGH_OVERLAP 이상이면 catalyst에게 차별화 보강 요청.

  - id: compile
    agent: compiler
    description: "아이디어 → 실험 계약서 변환 (데이터 가용성 3단계 평가 포함)"
    skills: [qepm-idea-pipeline, qepm-registry, qepm-datalake]
    instructions: |
      IDEA_PROPOSAL을 읽고 아래를 순서대로 수행한다:

      1. 데이터 가용성 3단계 평가:
         ✅ AVAILABLE — 필요 데이터가 이미 데이터레이크에 존재 → 바로 진행
         📦 COLLECTIBLE — 현재 없지만 기존 수집 인프라(DART/FRED/KRX/허용소스)로 수집 가능
           → steward에게 수집 요청, idea_status = COLLECTING
           → 수집 예상 소요일, 소스, 파라미터를 명시
           → 수집 완료 후 나머지 검사 진행
         ❌ UNAVAILABLE — 수집 인프라로도 확보 불가 (유료 DB, 비공개 등)
           → idea_status = BLOCKED + 불가 사유 + 대안 프록시 제안

      2. PIT 준수 가능한지 확인
      3. 기존 skill로 백테스트 가능한 구조인지 확인
      4. 동일 theme에서 최근 FAIL lesson이 있으면 experiment에 인용 강제
      5. 통과: experiment_protocol.json 생성
      6. 실패: idea_status = BLOCKED 또는 REJECTED + 사유
    output:
      experiment_ticket: "artifacts/ideas/IDEA_*_compiled.json"
      status: "QUEUED | COLLECTING | BLOCKED | REJECTED"
      data_assessment: "artifacts/ideas/IDEA_*_data_assessment.json"

  - id: data_collection
    agent: steward
    description: "COLLECTIBLE 판정 시 데이터 수집 실행"
    condition: "{{steps.compile.output.status}} == 'COLLECTING'"
    skills: [qepm-datalake]
    instructions: |
      compiler가 명시한 collection_plan에 따라 데이터를 수집한다.
      수집 완료 후 L0→L1 적재 + QC.
      성공: status → QUEUED로 전환, compile 단계 재실행
      실패: status → BLOCKED로 전환 + 사유 명시

  - id: backlog_register
    agent: researchops
    description: "컴파일된 실험을 backlog에 등록 + 우선순위 산정"
    condition: "{{steps.compile.output.status}} == 'QUEUED'"
    skills: [qepm-registry, qepm-diversity]
    instructions: |
      priority_score 계산 시 "기존 풀과의 직교성"을 Novelty 점수에 반영.
      orthogonal_search 모드 청크로 태그.

  - id: catalyst_feedback
    description: "실패/반려 시 Catalyst에게 피드백 전달"
    condition: "status가 BLOCKED 또는 REJECTED일 때"
    skills: [qepm-idea-pipeline]
    instructions: |
      실패 원인을 4축(signal/construction/data/mechanism)으로 분해하여
      agents/catalyst/idea_feedback/에 저장한다.
      피드백에는:
      - 실패한 단계 (compile/data_collection/backtest/audit)
      - 실패 사유
      - 유사 과거 실패와의 관계
      - 구체적 대안 제안 ("다른 프록시로 재시도", "메커니즘 자체 재검토" 등)
      을 포함한다.
      이 피드백은 다음 번 generate_idea에서 Catalyst가 필수 참조한다.

  - id: notify
    agent: manager
    description: "아이디어 진행 상태 브리핑"
    instructions: |
      상태에 따라:
      - QUEUED: "아이디어 #{id}가 backlog에 등록됨. 예상 실행: 다음 Track A 차례"
      - COLLECTING: "데이터 수집 중. 예상 소요: {N}일. 소스: {source}"
      - BLOCKED: "아이디어 #{id} 보류. 사유: {reason}. Catalyst에 피드백 전달됨"
      - REJECTED: "아이디어 #{id} 반려. 사유: {reason}. Catalyst에 피드백 전달됨"
```

## 6-5. 월간 리밸런싱 파이프라인 (후보군 생성 → 검증 → 브리핑 → 사용자 결정)

> **핵심 원칙**: 시스템은 "최종 포트폴리오"를 결정하지 않는다.
> 시스템은 검증된 후보군 + 판단 근거를 브리핑하고, 최종 선택은 사용자가 한다.

```yaml
name: monthly_rebalance
description: "데이터 최신화 → 국면 판단 → 동적 배분 후보군 생성 → 개별 전략 수준 검증 → 후보군 비교 브리핑"
trigger: "월초 또는 수동"

steps:
  # === 데이터 준비 ===

  - id: data_refresh
    agent: steward
    description: "데이터 최신화 (사용자 업데이트 감지 → API 보충 → QC)"
    skills: [qepm-datalake]

  - id: data_snapshot
    agent: steward
    description: "월말 데이터 스냅샷 봉인"
    skills: [qepm-datalake]

  - id: feature_update
    agent: features
    description: "피처/유니버스 업데이트"

  # === 환경 판단 ===

  - id: regime_classify
    agent: regime
    description: "현재 국면 판단 (앙상블)"
    skills: [qepm-regime]
    output:
      regime_result: "artifacts/rebal_{month}/regime_result.json"

  - id: valuation_calc
    agent: valuation
    description: "밸류에이션 지표 산출"
    skills: [qepm-kpi]

  - id: memory_retrieve
    skills: [qepm-memory]
    description: "R4 Regime Payoff + R5 Portfolio Policy 로드"
    action: retrieve
    query_context: "rebalance"

  # === 후보군 생성 (복수) ===

  - id: generate_candidates
    agent: blender
    description: "국면 기반 동적 배분 포트폴리오 후보군 3~5개 생성"
    skills: [qepm-dynamic-alloc, qepm-diversity, qepm-optimize]
    instructions: |
      아래 후보를 최소 3개, 최대 5개 생성한다:

      후보 A: Baseline 정적 (동일가중, regime 무시)
        → "동적 배분이 정적보다 나은지" 비교 기준

      후보 B: Regime 동적 (overlay stack 전체 적용)
        → 현재 regime + R4/R5 기억 기반 배분

      후보 C: Regime 동적 보수적 (confidence shrink 강화)
        → regime 판단이 불확실할 때의 안전 배분

      후보 D (선택): 전월 대비 최소 변경
        → turnover 최소화, 전월 포트폴리오에서 미세 조정만

      후보 E (선택): R5에서 가장 강건했던 과거 정책 재적용
        → 이번 달에 새로 최적화하지 않고 검증된 정책 재사용

      각 후보에 대해:
      - 전략별 비중
      - role balance (core/defensive/diversifier)
      - effective_N
      - 예상 turnover (전월 대비)
      - overlay chain 상세 (어떤 overlay가 어떤 효과)
      를 명시한다.
    inputs:
      regime_result: "{{steps.regime_classify.output.regime_result}}"
      regime_payoffs: "{{steps.memory_retrieve.output.regime_payoffs}}"
      portfolio_policies: "{{steps.memory_retrieve.output.portfolio_policies}}"
      valuation_data: "{{steps.valuation_calc.output}}"
      current_weights: "이전 월 실제 보유 비중"
    output:
      candidates: "artifacts/rebal_{month}/candidates/"

  # === 각 후보에 대해 개별 전략 수준의 full validation ===

  - id: validate_candidates
    agent: auditor
    description: "각 후보 포트폴리오를 개별 전략에 준하는 수준으로 검증"
    skills: [qepm-kpi, qepm-factor-model, qepm-stat-defense, qepm-diversity, qepm-backtest]
    instructions: |
      각 후보 포트폴리오에 대해 아래를 모두 수행한다:

      1. 성과 지표 (전체 기간 + 국면별)
         - Sharpe0_m_ann, CAGR, MDD, ES99_m, Turnover
         - 국면별 조건부 성과 (Normal/Stress/Euphoria/Transition)
         - 최악 1M/3M/6M 성과

      2. 리스크 프로파일
         - 팩터/스타일 노출 (value/momentum/quality/lowvol/size)
         - 섹터 집중도 (HHI)
         - 꼬리 의존성 (tail correlation)
         - 롤링 변동성/베타

      3. 통계 검증 (포트폴리오 수준)
         - FF3/Carhart4/FF5 alpha (포트폴리오 수익률 기준)
         - 어떤 팩터에 주로 노출되어 있는지 분해

      4. 비용 민감도
         - 비용 0배/1배/2배/3배에서의 성과
         - 턴오버가 비용에 미치는 영향

      5. Stress 테스트
         - 코로나 급락, 금리 급등, 특정 연도 제외
         - crisis correlation jump 시나리오

      6. 전월 대비 변화 분석
         - 어떤 전략이 새로 편입/제외되었는지
         - 어떤 역할(core/defensive/diversifier) 비중이 변했는지
         - 변화의 원인 (regime 변화? 새 전략 PASS? 밸류에이션 변화?)

      7. 후보 간 비교
         - 후보별 핵심 KPI 비교표
         - "후보 B가 후보 A보다 나은 이유" / "후보 C를 선택하면 포기하는 것"
         - 각 후보의 장단점 명확화
    inputs:
      candidates: "{{steps.generate_candidates.output.candidates}}"
    output:
      validation_reports: "artifacts/rebal_{month}/validation/"
      comparison_table: "artifacts/rebal_{month}/comparison_table.json"

  # === 사용자 브리핑 (의사결정 지원) ===

  - id: decision_briefing
    agent: manager
    description: "후보군 비교 브리핑 → 사용자에게 전달 → 사용자 선택 대기"
    instructions: |
      텔레그램으로 아래 내용을 브리핑한다:

      ## 1. 환경 요약
      - 현재 국면: {국면} (confidence: {수치})
      - 국면 모델 합의도: {수치}
      - 전월 대비 국면 변화 여부

      ## 2. 후보 포트폴리오 비교표
      | 항목 | 후보A(정적) | 후보B(동적) | 후보C(보수적) | ... |
      |------|-----------|-----------|-------------|-----|
      | Sharpe0 | | | | |
      | CAGR | | | | |
      | MDD | | | | |
      | ES99 | | | | |
      | Turnover | | | | |
      | effective_N | | | | |
      | FF alpha | | | | |
      | 비용2배 Sharpe | | | | |

      ## 3. 각 후보 상세
      후보별로:
      - 전략 구성 (어떤 전략이 어떤 비중으로)
      - role balance (core/defensive/diversifier %)
      - 전월 대비 주요 변화와 이유
      - 강점 / 약점 / 리스크 포인트

      ## 4. Auditor 소견
      - 가장 강건한 후보
      - 가장 리스크가 큰 후보
      - 비용 민감도가 가장 낮은 후보
      - 국면 판단이 틀렸을 때 가장 안전한 후보

      ## 5. 선택 요청
      "/select A" 또는 "/select B" 등으로 선택해주세요.
      선택 후 트레이드리스트를 생성합니다.
      추가 분석이 필요하면 "/detail B" 로 상세 요청 가능합니다.

  # === 사용자 선택 후 집행 ===

  - id: await_user_decision
    description: "사용자의 /select 명령 대기"
    type: "human_in_the_loop"
    timeout: "24h"
    fallback: "timeout 시 가장 보수적 후보(C)로 자동 선택 + 알림"

  - id: generate_tradelist
    agent: portfolio
    description: "선택된 후보의 트레이드리스트 생성"
    condition: "사용자가 /select로 후보를 선택한 후"
    skills: [qepm-kpi]
    instructions: |
      선택된 후보의 가중치를 받아:
      - 종목별 목표 비중
      - 매수/매도 리스트
      - 주문 분할 계획 (유동성 고려)
      - 예상 거래비용 상세
      - 유동성 주의 종목 리스트

  - id: execution_briefing
    agent: manager
    description: "트레이드리스트 최종 브리핑"
    instructions: |
      선택된 후보 + 트레이드리스트를 텔레그램으로 전달:
      - "후보 B를 선택하셨습니다"
      - 종목 리스트 + 비중
      - 예상 매매 건수 / 비용
      - 실행 시 주의사항
```

## 6-6. 사후 감시 + 성과 피드백 파이프라인

> **범위 한정**: Tower는 **시장 데이터 기반 이론적 사후 감시**만 수행한다.
> 증권사 API 연동, 실제 체결 데이터 기반 감시, 자동매매 연동은 현재 범위에 포함되지 않는다.
> 리밸런싱 시점의 목표 가중치 + 이후 시장 수익률로 "이론적 포트폴리오 성과"를 추적하는 구조다.
>
> **증권사 API 연동 금지 규칙**:
> 증권사 API 연동 여부는 반드시 사용자가 결정한다. 에이전트/Claude Code가 자의적으로
> 증권사 연동을 제안하거나 구현하지 않는다. 사용자가 명시적으로 요청한 경우에만
> 확장 인터페이스를 통해 추가한다.
>
> **추후 확장 대비**: Tower의 입력 인터페이스를 `theoretical` / `realized` 모드로 분리하여,
> 사용자가 증권사 API를 연동하기로 결정하면 `realized` 모드로 전환만 하면 되게 설계한다.

```yaml
name: post_trade_monitoring
description: "시장 데이터 기반 이론적 사후 감시 + 성과 분해 + R6 학습"
trigger: "일간(tower) + 월간(monitor) + 리밸런싱 후(R6)"
mode: "theoretical"  # 추후 사용자 결정 시 "realized"로 전환 가능

steps:
  # === 일간 이론적 감시 (tower — 시장 데이터만 사용) ===

  - id: daily_theoretical_tracking
    agent: tower
    description: "시장 데이터 기반 이론적 포트폴리오 성과/노출 추적"
    skills: [qepm-kpi]
    schedule: "매 영업일"
    instructions: |
      ★ 시장 데이터만 사용한다. 증권사 API/실제 체결 데이터는 사용하지 않는다.

      리밸런싱 시점의 목표 가중치 + 이후 일간 시장 수익률로
      "이대로 들고 있었으면 어땠을지"를 이론적으로 추적한다:

      1. 이론적 비중 드리프트
         - 리밸런싱 후 시장 수익률에 의한 가중치 변화 계산
         - 목표 비중 대비 이론적 현재 비중 비교

      2. 팩터/스타일 노출 변화
         - 포트폴리오의 value/momentum/quality/lowvol/size 노출 추적
         - 리밸런싱 시점 대비 변화량 계산

      3. 팩터 환경 변화 감지
         - 최근 N일 팩터 프리미엄 추이 (팩터 모멘텀/반전 감지)
         - 시장 변동성 변화, 거래량 이상치
         - 밸류에이션 z-score 변화

      4. PASS 전략 out-of-sample 성과 추적
         - 합격된 전략들의 리밸런싱 이후 실제 시장에서의 이론적 성과
         - 백테스트 성과 대비 열화/개선 감지

      5. 국면 판단 사후 검증
         - 지난 리밸런싱 시 regime이 판단한 국면과 실제 시장 상태 비교

      임계값 기준:
      - 이론적 비중 드리프트 > 5%p: WARNING
      - 팩터 노출 변화 > 1.5σ: WARNING
      - 전략 OOS 성과가 IS 대비 50% 이상 열화: ALERT
      - 국면 판단 오류 (stress인데 normal 행세): ALERT
    output:
      daily_report: "artifacts/monitoring/daily_{date}.json"

  - id: watchlist_evaluation
    agent: tower
    description: "이론적 감시 결과 기반 WATCHLIST 전환 제안"
    condition: "daily_theoretical_tracking에서 ALERT 발생"
    instructions: |
      ALERT 발생 시:
      1. 해당 전략/팩터의 최근 30일 이론적 성과 추이 분석
      2. 일시적 노이즈인지 구조적 변화인지 판단 (30일 롤링 기준)
      3. 구조적 열화 판단 시: WATCHLIST 전환 제안 → manager에 보고
      4. 3개월 연속 이론적 성과 열화 + 개선 없음 → RETIRED 강등 제안

      ★ WATCHLIST/RETIRED 최종 결정은 사용자가 한다.
      tower는 제안만 하고, manager가 브리핑으로 전달한다.
    output:
      watchlist_proposal: "artifacts/monitoring/watchlist_proposal_{strategy_id}.json"

  # === 월간 성과 분해 (monitor — 이론적 성과 기준) ===

  - id: monthly_performance_decomposition
    agent: monitor
    description: "월간 이론적 성과를 원인별로 분해"
    skills: [qepm-kpi, qepm-factor-model]
    schedule: "매월 리밸런싱 후"
    instructions: |
      직전 월 이론적 포트폴리오 성과에 대해:
      1. 전략별 기여도 분해 (어떤 전략이 얼마나 기여?)
      2. 팩터 기여도 분해 (value/momentum/quality/lowvol/size)
      3. 국면 기여도 (regime 판단이 맞았는가?)
      4. 배분 기여도 (동적 배분이 정적 대비 개선했는가?)
      5. 이론적 비용 영향 (예상 비용 모델 기준)
      6. "왜 이겼는가/졌는가" 1문장 요약

      ★ "이론적 성과"임을 항상 명시한다. 실제 체결 기반 성과가 아니다.

      원인 카테고리:
      - REGIME: 국면 판단 오류
      - FACTOR: 팩터 환경 변화
      - VALUATION: 밸류에이션 변화
      - ALLOCATION: 배분 결정 문제
      - DATA: 데이터 품질 문제
      - IDIOSYNCRATIC: 개별 종목 이벤트
    output:
      performance_report: "artifacts/monitoring/monthly_perf_{month}.json"

  - id: feedback_dispatch
    agent: monitor
    description: "성과 분해 결과를 관련 에이전트에 피드백"
    instructions: |
      원인 카테고리에 따라 피드백 대상 결정:
      - REGIME → regime 에이전트 (국면 판단 정확도 피드백)
      - FACTOR → researchops (팩터 환경 변화 정보 → backlog 조정에 활용)
      - ALLOCATION → blender (배분 규칙 조정 제안)
      - DATA → steward (데이터 품질 이슈 보고)
      - 전략별 기여도 → R4 Regime Payoff 갱신 입력

  # === R6 Post-Trade Learning 승격 ===

  - id: r6_post_trade_commit
    description: "이론적 운용 결과를 R6 Post-Trade Learning Memory에 저장"
    skills: [qepm-memory]
    schedule: "매월 리밸런싱 후"
    instructions: |
      직전 월의 이론적 운용 결과를 R6에 저장:
      - 이론적 성과 (목표 가중치 + 시장 수익률 기준)
      - 성과 분해 결과 (monitor 산출물)
      - 이론적 비용 추정값
      - 국면 판단 정확도 (regime 예측 vs 실제 시장 상태)
      - 배분 결정 적절성 (blender 제안 vs 사용자 선택 vs 이론적 결과)

      ★ 사용자가 실제 체결 결과를 수동으로 입력하면,
      이론적 성과와 실현 성과의 차이(실행 갭)도 함께 기록한다.
      수동 입력이 없으면 이론적 성과만 기록한다.

      R6는 다음 영구기관 루프에서 참조된다:
      - strategist: "이 전략이 OOS에서 어떻게 됐는지" 확인
      - regime: "지난 달 국면 판단이 맞았는지" 학습
      - blender: "이 배분이 이론적으로 효과가 있었는지" 학습
      - researchops: "어떤 방향의 연구가 이론적 성과로 이어지는지" 우선순위 참조

  # === 브리핑 ===

  - id: monitoring_briefing
    agent: manager
    description: "사후 감시 결과 브리핑 (텔레그램)"
    instructions: |
      월간 모니터링 브리핑:
      - 이론적 포트폴리오 성과 요약
      - 전략별 기여도 상위/하위 3개
      - 국면 판단 적중률
      - 동적 배분 vs 정적 비교 (이론적)
      - WATCHLIST/RETIRED 변동 제안
      - 다음 달 주의사항

      일간 ALERT 발생 시 즉시 알림:
      - 어떤 전략/팩터에서 무슨 변화
      - 권고 조치 (유지/감시강화/WATCHLIST 제안)
```

## 6-7. 영구기관 루프 (4가지 연구 트랙 + 사후 감시 통합)

```yaml
name: perpetual_research
description: "4개 연구 트랙을 자동으로 순환"
loop: true
exit_condition: "/stop 또는 circuit_breaker"

steps:
  - id: check_mode
    description: "Production window이면 monthly_rebalance 우선"

  - id: data_freshness
    agent: steward
    description: "데이터 최신 여부 확인. 부족하면 수집 실행."
    skills: [qepm-datalake]
    note: "매 루프 시작 시 데이터가 최신인지 확인. 사용자 업데이트도 감지."

  - id: select_track
    agent: researchops
    description: "다음 실행할 연구 트랙 선택"
    logic: |
      Track A (팩터 전략): 재료 확보가 부족할 때
      Track B (국면 모델): regime 분류 품질이 낮거나 R4 공백이 있을 때
      Track C (배분 전략): 전략 재료는 충분한데 배분이 미흡할 때
      Track D (아이디어 탐색): 기존 Track A~C가 수렴/정체될 때 새로운 방향 탐색

      선택 기준:
      - R4 Regime Payoff에 빈 칸이 많으면 → Track A + Track B 우선
      - regime_backtest 점수가 낮으면 → Track B 우선
      - R5 Portfolio Policy가 baseline 대비 미달이면 → Track C 우선
      - 재료 충분 + 배분 충분이면 → Track A (orthogonal search)
      - PASS 풀의 effective_N이 낮거나 family 편중이면 → Track D 우선
      - 최근 N 청크 연속 개선 없으면(정체) → Track D 강제 트리거
      - idea_backlog에 QUEUED 아이디어가 있으면 → Track A로 실행 (이미 컴파일됨)

  - id: run_track
    description: "선택된 트랙의 연구 청크 실행"
    workflow: |
      Track A → research_chunk_strategy
      Track B → research_chunk_regime
      Track C → research_chunk_allocation
      Track D → catalyst_idea_pipeline

  - id: circuit_breaker_check
    description: "3회 연속 동일 실패 → cooldown"

  - id: loop_back
    description: "BACKLOG_REFRESH로 복귀"
```

## 산출물
- `.claude/task-patterns/research_chunk_strategy.md`
- `.claude/task-patterns/research_chunk_regime.md`
- `.claude/task-patterns/research_chunk_allocation.md`
- `.claude/task-patterns/catalyst_idea_pipeline.md`
- `.claude/task-patterns/monthly_rebalance.md`
- `.claude/task-patterns/post_trade_monitoring.md`
- `.claude/task-patterns/perpetual_research.md`

## 검증
- 팩터 전략 청크가 mock 데이터로 전체 흐름 완주
- Catalyst 파이프라인: 아이디어 생성 → 직교성 사전검사 → 컴파일 → backlog 등록
- 월간 리밸런싱에서 regime → blender(후보생성) → auditor(검증) → manager(브리핑) → 사용자 선택 → portfolio(집행) 흐름 정상
- 사후 감시: tower(이론적 일간 감시) → monitor(월간 분해) → R6(학습) 흐름 정상
- 영구기관이 4개 트랙을 R4/R5/effective_N 기반으로 자동 선택
- PASS 풀 정체 시 Track D 강제 트리거 확인
- production window에서 research WIP 축소 확인

---

# Phase 7: 텔레그램 연동 + 브리핑

## 목표
Manager 에이전트를 텔레그램에 연결하고, 자동 브리핑 + 명령 수신을 구현한다.

## 구현 항목

### 7-1. 텔레그램 봇 설정
```bash
# DM (양방향 소통)
# Configure: channels.telegram.botToken "YOUR_BOT_TOKEN"
# Configure: channels.telegram.dmPolicy "allowlist"
# Configure: channels.telegram.allowFrom '["YOUR_TELEGRAM_ID"]'

# Channel (단방향 브로드캐스트)
# Configure: channels.telegram.broadcast.channelId "YOUR_CHANNEL_ID"
# Configure: channels.telegram.broadcast.enabled true

# Restart Claude Code session
```

### 7-2. Manager 텔레그램 명령어 (CLAUDE.md에 정의)
```markdown
## 텔레그램 명령어

### 정형 명령어
- `/status` — 현재 상태 (국면, 모드, WIP, 최근 결과)
- `/regime` — 현재 국면 판단 상세 (모델별 확률, confidence, 전월 대비)
- `/allocation` — 현재 목표 배분 (역할별 비중, 전월 대비 변화)
- `/candidates` — 이번 달 후보 포트폴리오 비교표 재전송
- `/detail {A|B|C|D|E}` — 특정 후보의 상세 분석 요청
- `/select {A|B|C|D|E}` — 후보 선택 → 트레이드리스트 생성
- `/pause` / `/resume` / `/stop` / `/loop_on` / `/loop_off`
- `/rebalance` — 월간 리밸런싱 수동 실행
- `/briefing` — 최근 브리핑 재전송
- `/backlog` — 현재 백로그 상위 5개
- `/memory` — 기억 현황 (R1~R6 각 레이어 건수, 최근 승격)

### 자유형 질문/요청 (라우팅)
명령어 없이 자연어로 질문하면 Manager가 주제를 파악하여 담당 에이전트에 전달하고 답변을 받아 전달한다.
- "이 전략의 FF5 alpha가 왜 이 수준이야?" → auditor
- "현재 국면이 바뀔 가능성은?" → regime
- "idioVol family 실험 히스토리 보여줘" → qepm-memory
- "최근 논문에서 본 이런 아이디어 어때?" → catalyst (IDEA_PROPOSAL 경로)

### 온디맨드 브리핑 요청
분석/시각화가 필요한 요청을 보내면 Manager가 관련 에이전트에 작업을 위임하고, qepm-briefing으로 차트/카드를 생성하여 텔레그램으로 전송한다.
- "지난 달 regime 판단 정확도 분석해줘" → regime + monitor → 차트 + 분석
- "PASS 풀 직교성 현황 보여줘" → qepm-diversity → 상관 행렬 차트
- "현재 포트폴리오 팩터 노출 분석" → tower + qepm-factor-model → 차트
- "이번 달 R4 Regime Payoff 변화 추이" → qepm-memory → 차트
- 사용자가 "차트로", "시각화해줘" 명시하면 반드시 차트 포함
- 텍스트만으로 충분한 질문은 차트 없이 답변 가능
```

### 7-3. 브리핑 내용 (국면 + 배분 포함)
월간 브리핑에 반드시 포함:
- **현재 국면**: 어떤 국면인지 + confidence + 모델 합의도
- **배분 변화**: 전월 대비 역할별 비중 변화 + 이유
- **전략 변화**: 신규 편입/제외 전략 + 사유
- **리스크**: MDD/ES99 변화 + 스트레스 시나리오
- **기억 업데이트**: 이번 달 새로 승격된 R2~R5 기억

## 산출물
- 텔레그램 연동 설정
- CLAUDE.md 및 Manager spawn prompt 명령어 섹션 보강

## 검증
- `/regime` → 현재 국면 + 확률 + confidence 응답
- `/allocation` → 역할별 비중 응답

---

# Phase 8: E2E 통합 테스트

## 목표
전체 시스템이 연결되어 3개 연구 트랙 + 월간 리밸런싱이 작동하는 것을 확인한다.

## 시나리오

### E2E-01: 팩터 전략 연구 청크 (PASS 케이스)
1. backlog에 팩터 전략 청크 등록
2. researchops → 청크 선택 + 리서치 필요 판단 → researcher에 방향 지시
3. researcher → 지시 방향 수집 → researchops → 검증/필터 → strategist에 전달
4. strategist → alphalab → auditor → memory_commit 완주
5. R0/R1/registry 정상 저장 확인
6. qepm-briefing이 equity curve + annual returns 차트 생성
7. 요약 카드에 모든 KPI + 이모지 정상 렌더링
8. PASS이므로 상세 리포트도 함께 전송
9. 텔레그램에 이미지 2장 + 요약 카드 + 상세 리포트 도착

### E2E-01b: 팩터 전략 연구 청크 (FAIL 케이스)
1. 의도적으로 약한 전략 실행
2. auditor FAIL 판정
3. qepm-briefing이 차트 2장 + 요약 카드만 생성 (상세 없음)
4. 요약 카드에 실패 사유 + 수정 제안 포함
5. 텔레그램에 이미지 2장 + 요약 카드 도착 (상세 없음 확인)

### E2E-02: 국면 모델 연구 청크
1. backlog에 regime 실험 청크 등록
2. regime 에이전트가 국면 모델 변경 실험
3. regime_backtest로 품질 평가
4. R4 Regime Payoff 업데이트 확인
5. placebo 대비 유의한 분리 확인

### E2E-03: 배분 전략 연구 청크
1. R4가 축적된 상태에서 배분 실험 청크 등록
2. blender가 동적 배분 백테스트 실행
3. 정적 baseline 대비 개선 확인
4. R5 Portfolio Policy 저장 확인

### E2E-04: 월간 리밸런싱 전체 흐름
1. 월말 데이터 스냅샷 봉인
2. regime 에이전트가 현재 국면 판단
3. blender가 후보 포트폴리오 3~5개 생성
4. auditor가 각 후보를 개별 전략 수준으로 full validation
   - Sharpe0/CAGR/MDD/ES99 + 국면별 조건부 성과
   - FF3/Carhart4/FF5 alpha (포트폴리오 수준)
   - 비용 민감도 (0/1/2/3배)
   - Stress 테스트
5. manager가 후보 비교표 + 각 후보 상세 + auditor 소견을 텔레그램 브리핑
6. /select 명령 대기 (human_in_the_loop)
7. 사용자 선택 후 portfolio가 트레이드리스트 생성
8. 최종 실행 브리핑 발송

### E2E-04b: 사후 감시 + R6 학습 (이론적)
1. 리밸런싱 후 tower가 시장 데이터 기반 이론적 성과 추적 시작
2. 의도적 팩터 노출 변화 시뮬레이션 → WARNING/ALERT 발생 확인
3. 전략 OOS 이론적 성과 50% 이상 열화 → WATCHLIST 전환 제안 확인
4. monitor가 월간 이론적 성과 분해 실행 (전략별/팩터별/국면별 기여도)
5. feedback_dispatch가 원인 카테고리별 에이전트에 피드백 전달
6. R6 Post-Trade Learning Memory 저장 확인 (이론적 성과 기준)
7. 다음 영구기관 루프에서 R6 참조 확인 (strategist/regime/blender)

### E2E-05: 영구기관 트랙 자동 선택
1. R4에 빈 칸이 많은 상태 → Track A/B 우선 선택 확인
2. regime 품질 낮은 상태 → Track B 우선 선택 확인
3. 재료 충분 + R5 미달 → Track C 우선 선택 확인

### E2E-06: Memory 승격 체인 (국면 포함)
1. 동일 family 실험 3개 → R2 생성
2. 통계 검증 → R3 저장
3. regime-conditioned 분석 → R4 저장 (confidence 포함)
4. 배분 백테스트 → R5 저장 (baseline 대비 개선)

### E2E-07: Circuit Breaker + Regime 불일치
1. 국면 모델들이 서로 다른 판단 → confidence 급락
2. confidence 낮으면 role_targets가 uniform에 수렴 확인
3. 동일 regime 실패 3회 → cooldown 확인

### E2E-08: 모드 붕괴 방지 (Diversity Enforcement)
1. corr 0.9인 전략 2개를 auditor에 순차 제출
2. 첫 번째는 Gate 5 PASS
3. 두 번째는 qepm-diversity가 REDUNDANT 판정 → Gate 5 FAIL, alias 등록
4. blender에 corr 0.8+ 전략 5개를 넣으면 → 중복 제거 후 2~3개만 남음
5. effective_N < 3이면 "다양성 부족" 경고 발생 확인

### E2E-09: Catalyst 아이디어 파이프라인
1. catalyst가 아이디어 생성 (IDEA_PROPOSAL 스키마)
2. reference_bundle 없는 아이디어 → submit 거부 확인
3. 정상 아이디어 → diversity precheck → compiler에 전달
4. compiler 데이터 3단계 평가:
   - AVAILABLE 케이스: 바로 experiment_protocol.json 생성
   - COLLECTIBLE 케이스: steward에 수집 요청 → 수집 완료 후 진행
   - UNAVAILABLE 케이스: BLOCKED + 사유 + Catalyst 피드백 생성
5. QUEUED → researchops가 backlog에 등록 + priority 산정
6. 영구기관이 해당 청크를 Track A로 실행
7. 실행 후 FAIL → catalyst_feedback_on_fail 스텝이 피드백 생성
8. Catalyst가 다음 아이디어 생성 시 피드백 참조 확인

### E2E-10: 영구기관 Track D 강제 트리거
1. PASS 풀의 effective_N이 낮은 상태 설정 (corr 높은 전략만 존재)
2. 최근 5 청크 연속 개선 없음 설정
3. researchops가 Track D (Catalyst) 강제 선택 확인
4. catalyst 파이프라인이 실행되고, 새 아이디어가 backlog에 등록

## 산출물
- E2E 테스트 시나리오 12개 검증 결과
- 필요 시 디버깅/수정

---

# 실행 가이드 (최종)

## 모델 선택
모든 세션에서 **Opus 4.6 확장 사고**로 실행한다. 이 아키텍처의 복잡도(3,800줄+ 설계, 16개 에이전트, 14개 skill, 7개 workflow)를 정확히 이해하고 구현하려면 확장 사고가 필수.

## Claude Code에 전달하는 방법

### 세션 1: Agent Teams 호환성 검증 + Gap Analysis (최우선, 필수)
```
이 티켓과 Lawbook v1.4.2를 읽어줘.

★ 최우선: Claude Code Agent Teams 호환성 검증
Claude Code Agent Teams 공식 문서를 읽고, 이 티켓의 아래 가정들이 실제와 맞는지 검증해:
1. 에이전트 구조: CLAUDE.md + spawn prompt + Task List + Mailbox 패턴
2. Task 생성/관리: TaskCreate, TaskUpdate 도구의 정확한 사용법
3. Teammate spawn: spawn prompt에 에이전트 역할을 넣는 방법
4. 통신: Mailbox P2P 메시징, SendMessage 도구
5. 텔레그램 연동: MCP server로 텔레그램 DM + Channel 브로드캐스트 가능 여부
6. R 스크립트 실행: teammate이 Bash로 Rscript 호출 가능한지
7. 에이전트 간 대화 로그: 자동 보존? 보존 기간? 검색 API?
8. 세션 지속성: 영구기관 루프를 어떻게 구현할지 (hooks? 반복 실행?)
9. 모든 teammate이 Lead 모델을 상속하는지 확인
안 맞는 부분이 있으면 무엇을 어떻게 수정해야 하는지 명시해.

★ Gap Analysis
현재 프로젝트 폴더를 분석해서:
1. 기존 R 함수 중 R/skills/로 래핑할 수 있는 것 (특히 국면 엔진/백테스트/최적화)
2. 새로 만들어야 하는 것
3. CLAUDE.md/MEMORY.md에서 새 CLAUDE.md + spawn prompt로 옮길 내용
4. 기존 이모지 관례 (emoji_taxonomy에 병합)
5. 기존 텔레그램 채널 운용 지침 (DM/Channel 정책에 병합)

MIGRATION_PLAN.md로 저장하고 내 승인을 기다려.
검증 결과에 따라 티켓 수정이 필요하면 수정 사항도 함께 정리해.
```

### 세션 2: Phase 0 + 1
```
Agent Teams 활성화 + CLAUDE.md(16개 에이전트 정의) + spawn prompt 16개 생성.
Agent Teams에서는 전원 Opus 4.6 확장 사고 (Lead 모델 상속).
agents/ 디렉토리에 에이전트별 spawn_prompt.md 배치.
세션 1 검증 결과에서 수정이 필요한 부분 반영.
```

### 세션 3: Phase 2 + 3
```
R/skills/ 14개 R 스크립트 + 기억증류 파이프라인 전체 (R0~R6).
기존 R 코드를 래핑하는 것 위주.
```

### 세션 4: Phase 4 + 5
```
국면 엔진 래핑(qepm-regime) + 동적 배분(qepm-dynamic-alloc).
기존 국면 엔진을 찾아서 표준 인터페이스로 래핑하는 게 최우선.
단순 룰 기반 비교 baseline을 추가.
overlay stack + transition smoother + role balance 구현.
```

### 세션 5: Phase 6 + 7
```
Task pattern 7개 + 텔레그램 연동 (MCP server로 DM + Channel).
4개 연구 트랙 + 월간 리밸런싱(후보군→검증→브리핑→사용자 선택) +
사후 감시(이론적) + 영구기관 루프.
Agent Teams의 TaskCreate/TaskUpdate로 워크플로우 구현.
```

### 세션 6: Phase 8
```
E2E 통합 테스트 12개 시나리오 실행.
실제로 Agent Teams를 spawn하여 연구 청크 1개를 완주해보는 것이 핵심.
```

## 주의사항
1. **기존 코드 수정 금지**: 래퍼만 만든다.
2. **Agent Teams 검증 먼저**: 세션 1에서 공식 문서와 대조하고, 불일치 시 티켓 수정안을 먼저 보고.
3. **Gap Analysis 먼저**: 구현 전에 반드시 기존 폴더 분석.
4. **API 키는 사용자가 입력**: 대화형 입력은 직접.
5. **LLM 직접 호출 금지**: R에서 Claude API 직접 호출하지 않는다.
6. **국면 엔진은 기존 래핑 우선**: 이미 개발된 국면 엔진이 있다. 래퍼만.
7. **동적 배분은 baseline 비교 필수**: 정적 대비 개선 안 되면 동적 채택 불가.
8. **증권사 API 연동 금지**: 사용자가 명시적으로 요청한 경우에만. 자의적 판단 금지.
9. **최종 포트폴리오 결정 금지**: 시스템은 후보군 + 판단 근거를 브리핑. 최종 선택은 사용자.
10. **전원 Opus 4.6**: Agent Teams는 Lead 모델 상속. 모델 차등 배정 불가.
