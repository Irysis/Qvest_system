# QEPM 멀티에이전트 구현 — Claude Code Agent Teams 세션별 프롬프트

> 모든 세션에서 **Opus 4.6 확장 사고** 모델을 사용한다 (`claude --model opus`).
> Agent Teams에서는 모든 teammate이 Lead 모델을 상속하므로 전원 Opus 4.6.
> 각 세션 시작 시 아래 프롬프트를 그대로 붙여넣는다.

---

## 세션 1: Agent Teams 호환성 검증 + Gap Analysis

```
너에게 두 개의 핵심 문서를 줄게:

1. QEPM Agent Teams 설계 티켓 (qepm_agent_teams_ticket.md)
2. QEPM Lawbook v1.4.2

둘 다 꼼꼼히 읽어줘. 이 세션의 목표는 "구현에 들어가기 전에 모든 전제를 검증하는 것"이야.

### Part A: Claude Code Agent Teams 호환성 검증 (최우선)

Claude Code Agent Teams 공식 문서를 읽고, 티켓의 아래 가정들이 실제와 맞는지 대조해줘:

1. 에이전트 구조: CLAUDE.md가 모든 teammate에 자동 로드되는가? agents/{name}/spawn_prompt.md를 spawn 시 전달하는 방식이 올바른가?
2. Task 관리: TaskCreate, TaskUpdate 도구의 정확한 문법. 의존성/블로킹 지원 여부.
3. Teammate spawn: 16개 teammate을 하나의 team에서 spawn할 수 있는가? 제한이 있는가?
4. 통신: Mailbox P2P 메시징 (SendMessage). 한 teammate이 다른 teammate에게 직접 메시지할 수 있는가?
5. R 스크립트 실행: teammate이 Bash 도구로 Rscript를 호출할 수 있는가?
6. 텔레그램 연동: MCP server를 통해 텔레그램 DM + Channel 브로드캐스트가 가능한가? 아니면 별도 구현이 필요한가?
7. 대화 로그: 에이전트 간 메시지가 자동 보존되는가? ~/.claude/tasks/ 에 task JSON이 남는가?
8. 세션 지속성: 영구기관 루프를 어떻게 구현할지 (hooks? TeammateIdle? 외부 cron?)
9. 모델 상속: 모든 teammate이 Lead의 모델(Opus 4.6)을 상속하는 것이 확인되는가?
10. 파일 접근: 모든 teammate이 동일한 프로젝트 파일(memory/, registry/, R/skills/)에 접근 가능한가?

각 항목마다:
- ✅ 일치 / ⚠️ 부분 일치 / ❌ 불일치
- 불일치 시: 실제 스펙과 대안을 제시

### Part B: Gap Analysis

현재 프로젝트 폴더를 분석해서:

1. 기존 R 함수 중 R/skills/로 래핑할 수 있는 것
   - 국면 엔진 관련 함수 (최우선)
   - 백테스트, 최적화/HRP/RP, 팩터 모델/통계 검정, KPI 계산
   - 데이터 수집 함수 (DART/FRED/KRX API)
   각 함수의 파일 경로, 함수명, 입출력 형식을 기록

2. 새로 만들어야 하는 것

3. 기존 CLAUDE.md/MEMORY.md에서 새 CLAUDE.md + spawn prompt로 옮길 내용

4. 기존 이모지 관례 (config/emoji_taxonomy에 병합)

5. 기존 텔레그램 채널 운용 지침 (DM/Channel 정책에 병합)

6. 기존 브리핑 템플릿 (qepm-briefing에 반영)

### 산출물

아래 두 파일을 만들어줘:
- AGENT_TEAMS_VERIFICATION.md (Part A 결과)
- MIGRATION_PLAN.md (Part B 결과 + Part A에서 나온 티켓 수정 사항)

두 파일 다 만든 뒤, 내 승인을 기다려. 승인 전에 구현에 들어가지 마.
```

---

## 세션 2: Phase 0 + 1

```
세션 1에서 승인받은 MIGRATION_PLAN.md를 기반으로 Phase 0과 Phase 1을 실행해줘.

### Phase 0: Agent Teams 활성화 + 프로젝트 구조 생성
- .claude/settings.json에 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 활성화
- CLAUDE.md 생성 (16개 에이전트 정의 + 프로젝트 규칙 + 파일 구조)
- 디렉토리 구조 생성 (memory/, registry/, R/skills/, agents/, config/, lawbook/)
- config/qepm_config.yaml 생성

### Phase 1: Spawn Prompt 작성
- agents/{name}/spawn_prompt.md를 16개 에이전트별로 작성
- Lawbook에서 해당 장의 핵심 규칙을 추출하여 포함
- 모든 에이전트에 확장 사고 활용 지시 포함 (전원 Opus이므로)
- manager spawn prompt에 AGENTS.md 내용 통합 (파이프라인 + 라우팅 + 온디맨드 브리핑 + DM/Channel 정책)

한 에이전트씩 spawn prompt를 만들 때마다 "Lawbook 해당 장과 정합적인지" 확인.
전부 끝나면 요약 보고해줘.
```

---

## 세션 3: Phase 2 + 3

```
Phase 2와 Phase 3을 실행해줘.

### Phase 2: R/skills/ 14개 R 스크립트 + 통신 포맷 + 실험 프로토콜

MIGRATION_PLAN.md에서 "기존 함수 → skill 래핑" 매핑을 참고해서:

R/skills/ 디렉토리에 14개 skill을 만들어줘.
각 skill은 main.R 진입점 + 보조 R 파일 구조.
teammate이 Bash로 `Rscript R/skills/{name}/main.R --input X --output Y` 호출.

1. qepm-backtest 2. qepm-factor-model 3. qepm-optimize 4. qepm-stat-defense
5. qepm-kpi 6. qepm-memory 7. qepm-registry 8. qepm-lawbook
9. qepm-diversity 10. qepm-idea-pipeline 11. qepm-regime 12. qepm-datalake
13. qepm-research-collector 14. qepm-briefing

기존 함수를 래핑할 때 원본 수정 금지. 어댑터만.
각 skill이 예시 입력으로 정상 실행되는지 테스트.

### Phase 3: 기억증류 파이프라인 R0~R6

R/skills/qepm-memory/ 를 확장하여 R0~R6 전체 구현.
mock 데이터로 각 레이어 정상 동작 테스트.
```

---

## 세션 4: Phase 4 + 5

```
Phase 4와 Phase 5를 실행해줘.

### Phase 4: 국면 엔진 래핑 + 개선 구조
기존 국면 엔진 → R/skills/qepm-regime/ 래핑 (수정 금지, 어댑터만).
baseline_engine.R (단순 룰 기반) + ensemble_regime.R + regime_backtest.R.

### Phase 5: 동적 배분 엔진
R/skills/qepm-dynamic-alloc/ 전체 구현.
overlay_stack + transition_smoother + role_balance + dynamic_backtest.
정적 baseline 대비 Sharpe 개선 확인 필수.
```

---

## 세션 5: Phase 6 + 7

```
Phase 6과 Phase 7을 실행해줘.

### Phase 6: Task Pattern 7개 정의

Agent Teams의 TaskCreate/TaskUpdate/SendMessage로 아래 7개 워크플로우 패턴을 구현:

1. research_chunk_strategy — researchops→researcher→researchops(검증)→strategist→alphalab→auditor→memory→briefing→catalyst_feedback
2. research_chunk_regime — regime 모델 실험→R4 갱신
3. research_chunk_allocation — 배분 전략 실험→R5 갱신
4. catalyst_idea_pipeline — catalyst→diversity→compiler(데이터3단계)→steward(수집)→researchops(큐)→feedback
5. monthly_rebalance — steward→features→regime→valuation→memory→blender(후보3~5)→auditor(full validation)→manager(브리핑)→/select→portfolio
6. post_trade_monitoring — tower(이론적 일간)→monitor(월간 분해)→R6
7. perpetual_research — data_freshness→select_track(A/B/C/D)→run→circuit_breaker→loop

각 패턴을 .claude/task-patterns/{name}.md에 문서화.
Manager가 사용자 요청에 따라 해당 패턴의 Task를 생성하는 구조.

### Phase 7: 텔레그램 연동
MCP server 또는 R 스크립트로 텔레그램 DM + Channel 구현.
봇 토큰/채널 ID는 플레이스홀더만.
```

---

## 세션 6: Phase 8

```
Phase 8 E2E 통합 테스트 12개 시나리오.

실제로 Agent Teams를 spawn하여 최소 1개 연구 청크를 완주해보는 것이 핵심.
mock 데이터로 각 시나리오가 전체 파이프라인을 통과하는지 확인.

E2E-01: 팩터 전략 PASS — 차트+요약+상세 브리핑
E2E-01b: 팩터 전략 FAIL — 차트+요약만
E2E-02: 국면 모델 연구 — R4 갱신
E2E-03: 배분 전략 연구 — R5 갱신
E2E-04: 월간 리밸런싱 — 후보→검증→브리핑→/select→트레이드리스트
E2E-04b: 사후 감시 이론적 — tower→monitor→R6
E2E-05: 영구기관 트랙 자동 선택
E2E-06: Memory 승격 체인 R0→R5
E2E-07: Circuit Breaker + Regime 불일치
E2E-08: 모드 붕괴 방지 (diversity)
E2E-09: Catalyst 파이프라인 (AVAILABLE/COLLECTIBLE/UNAVAILABLE + 피드백)
E2E-10: Track D 강제 트리거

각 시나리오별 PASS/FAIL + 실패 시 원인 보고.
```

---

## 긴급 세션: 특정 Phase만 재실행

```
Phase {N}에서 문제가 발견됐어.
문제: {구체적 설명}
해당 Phase만 수정해줘. 다른 Phase 건드리지 마.
수정 전에 영향 범위 먼저 분석 후 보고.
```

---

## 참고: 세션 간 연속성

각 세션 시작 시 이전 산출물이 프로젝트 폴더에 있는지 확인.
MIGRATION_PLAN.md와 AGENT_TEAMS_VERIFICATION.md는 프로젝트 루트에 유지.
CLAUDE.md는 전 세션에서 자동 로드되므로, 업데이트 시 주의.
