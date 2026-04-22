---
name: qvest
description: "Qvest 시스템 구동 — 전천후 포트폴리오 수확을 위한 퀀트 리서치 에이전트팀 부트스트랩"
disable-model-invocation: true
user-invocable: true
---
# Qvest — Quant + Harvest

전천후 포트폴리오 수확을 위한 퀀트 리서치 시스템을 구동합니다.

## 구동 순서

1. **부트스트랩 실행**
```bash
bash 02_Infrastructure/ops/bootstrap.sh
```

1.5. **[Session 68 Day 2 설정] Block A~H 토큰 절감 검증 자동 실행**

다음 조건 시 자동으로 검증 스크립트 실행:
```bash
if [ -f .cache/token_reduction_test_pending.flag ]; then
  bash 02_Infrastructure/ops/test_token_reduction.sh
fi
```

**동작**:
- 플래그 존재 시 `02_Infrastructure/ops/test_token_reduction.sh` 실행
- Block A(모델 라우팅) / B(컨텍스트 분할) / C(Hook+Codex) / D(Caching) / E(R1→R2 요약) / F(Codex 캐시) / G(Lawbook) / H(Compact Mode Hook) 전수 검증
- 완료 시 플래그를 `.cache/token_reduction_test_done_{TS}.log`로 rename (1회만 자동 실행)
- **결과 보고**: PASS/FAIL/WARN 카운트 + 실패 항목 상세 보고
- FAIL 있을 시 Q-Lead가 텔레그램으로 알림
- 모두 PASS면 바로 리서치 사이클 진행

**수동 재실행**: `touch .cache/token_reduction_test_pending.flag` 후 /qvest

**Shadow Mode 테스트 (Compact Debate 검증)**:
자동 검증 PASS 후, 사용자가 `export QVEST_DEBATE_MODE=compact` 설정 시 다음 S0 Debate부터 3인 모드로 실행됩니다. 기본(미설정)은 5인 Full 모드 유지.


2. **플러그인 리로드**
```
/reload-plugins
```

3. **시스템 상태 확인**
- Skills: 27개 도메인별 (.claude/skills/) — Skill-scoped hooks + 동적 주입(`!`) 지원
- Commands: 7개 + qvest (.claude/commands/)
- Hooks: 4-Tier 방어선 (v53)
  - Tier 1 (전역): safety_guard, pipeline_trigger, artifact_validator
  - Tier 2 (Agent tool): PostToolUse[Write]→s0_debate_enforcer(상태머신), FileChanged→s0_verdict_router
  - Tier 3 (TeamCreate): TeammateIdle, TaskCompleted
  - Tier 4 (LLM-Powered): risk_gate agent, Codex R2 verify(S2.13), role_honesty_runner(S2.11)
- Agents: `.claude/agents/risk-manager.md` — TeamCreate + Agent tool 재사용
- Plugins: pyright-lsp, r-lsp, commit-commands, pr-review-toolkit
- MCP: 6개 서버 (jina, arxiv, paper-search, fred, yfinance, rss)

4. **포트폴리오 gap 확인**
```bash
cat .cache/portfolio_gap_vector.json
```

5. **팀 스폰 (TeamCreate — Hook 완전 자동)**

Q-Lead는 관리·감독·브리핑만 수행한다. 코드 작성/실행은 반드시 팀원에게 위임한다.
TeamCreate 모델에서는 모든 Hook(SubagentStop, FileChanged, TeammateIdle 등)이
Q-Lead 세션 내에서 자동 발동한다. supervisor 불필요.

5-1. TeamCreate로 연구팀 생성:
```
TeamCreate(team_name="research-v7", description="V7 All-Weather Portfolio Research Team")
```

5-2. 4인 teammate 병렬 스폰 (Agent tool, run_in_background=true):
```
Agent(name="scout", team_name="research-v7", prompt="Read 02_Infrastructure/prompts/scout_init.md. inbox TODO 확인 → S0 가설 또는 S3/S5 작업.")
Agent(name="forge", team_name="research-v7", prompt="Read 02_Infrastructure/prompts/forge_init.md. inbox TODO 대기. TODO_S1 도착 시 run_all.R 작성 + 백테스트.")
Agent(name="judge", team_name="research-v7", prompt="Read 02_Infrastructure/prompts/judge_init.md. inbox TODO 대기. TODO_S6 도착 시 Gate 0-6 검증.")
Agent(name="governor", team_name="research-v7", prompt="Read 02_Infrastructure/prompts/governor_init.md. inbox TODO_PG0 대기. S7 완료 전략 PG0~PG3.")
```

5-3. 팀 상태 확인: `Read ~/.claude/teams/research-v7/config.json`

5-4. 이미 팀 실행 중이면 재생성 않고 SendMessage로 상태 확인. idle teammate에 작업 재할당.

5-5. 세션 종료 시: `SendMessage(to="*", message={type:"shutdown_request"})`

6. **리서치 시작 — S0 가설 토론**
Q-Lead가 Scout을 plan mode로 스폰 → 4명 토론팀 검증 → 승인 후 실행.
supervisor.md의 "5 Agent Debate 체계" 참조.

**Q-Lead 역할 경계 (Level 0)**:
- ✅ 진단, 지시, 모니터링, 결과 수집, 텔레그램 보고
- ❌ 직접 Rscript 실행, factor_engine 수정, 백테스트 실행 → Forge에 위임
- ❌ 직접 S3/S6 검증 코드 실행 → Judge에 위임

## 시스템 구성

```
Qvest Architecture v53 (TeamCreate + Hook 단일 세션 모델)

┌─ Q-Lead 세션 (유일한 Claude instance) ────────────────────┐
│  /s0-debate → 5인 3-Round 토론 자동 체인                    │
│  TeamCreate("research-v7") → teammate 4인 spawn            │
│  SendMessage + TaskList 기반 분업                           │
│  Agent tool (온디맨드) → RiskMgr / Architect / Codex       │
│  진척률 모니터링 + 텔레그램 브리핑                           │
├─ 상시 백그라운드 tmux ──────────────────────────────────────┤
│  "rc"  : persistent_remote_control (텔레그램 listener)      │
├─ Hooks (v53 — 17중 4-Tier 방어선, Q-Lead 세션 내 발동) ────┤
│  Pre:  axiom_enforcement / safety_guard / forge_code_guard  │
│        unified_agent_guard (+AX 전제 주입 P0-B/P1-B/AX-P2) │
│        s0_debate_guard                                      │
│  Post: artifact_validator (스키마 + P2-B 합리화 탐지)       │
│        pipeline_trigger / circuit_breaker / risk_gate       │
│        s0_debate_enforcer (상태머신 + Codex R2 S2.13)       │
│        role_honesty_runner (S2.11)                          │
│        mutation_tracker / grade_a_catalog / axiom_harvester │
│  Event: s0_verdict_router (FileChanged)                     │
│         teammate_idle / task_complete                       │
├─ S0 Debate 3-Round + 합산 점수 ─────────────────────────────┤
│  Scout(plan) → R1 Write 5인 → enforcer 상태머신             │
│  → R2 Rebuttal 5인 + Codex R2 자동 verify                  │
│  → R3 Closing (|Δ|>4만 재소환)                              │
│  → VERDICT (transcript.rounds ≥2 필수)                      │
│  → FileChanged Hook → 자동 라우팅                           │
├─ Pipeline (S0→PG3→Axiom — 자동) ──────────────────────────┤
│  S0(debate) → S1~S7 → PG0~PG3 → AX promote                 │
│  DONE→TODO 자동 전환 (pipeline_trigger.sh)                  │
│  Stage gate S2/S3/S4 선행 artifact 강제 (P0-B)              │
│  S5 Fast-Track 차단 (S2.6 mutation_tracker)                 │
│  Grade 허들: DSR+FF5 Hard Gate(S2.9) + D075 AX Suspicion    │
│  PG0~PG3 단계별 gate (P1-B)                                 │
│  Role Honesty Audit 자동 (S2.11)                            │
│  L-code 추가 시 AX 엔진 auto-harvest/cluster/promote        │
└────────────────────────────────────────────────────────────┘

v50/v52 레거시 (deprecated):
  - tmux research 4-pane (scout/forge/judge/governor 독립 Claude)
  - tmux supervisor (qlead_supervisor.sh R 상주)
  부팅 시 자동 종료. QVEST_KEEP_LEGACY_TMUX=1로 유지 가능.
```
