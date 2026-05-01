---
name: launch-team
description: "[DEPRECATED v7.0] TeamCreate 4인 연구팀 — v6.4 /qvest로 대체"
disable-model-invocation: true
user-invocable: true
---

> ⚠️ **DEPRECATION WARNING (v7.0 Sprint 5, 2026-05-01)**
>
> `/launch-team`는 v53 legacy command입니다. v6.4부터 **`/qvest`** + WT lifecycle (alpha-research → risk-research → optimizer-research → forge → judge → governor)을 사용하세요.
>
> Codex Critic Round 5단계 흐름 + 5 cert auto-issue + state machine validation 모두 v6.4부터 통합되어 있습니다.
>
> **참조**: `00_Lawbook/DEPRECATION.md` / `02_Infrastructure/docs/qvest_v6_4_sot.md`
>
> 본 command는 retain (back-compat) 단 v7.1+에서 EOL 예정.

Launch the full research agent team via TeamCreate (v53).
Q-Lead 단일 세션 안에서 teammate 4인이 spawn되고 모든 Hook이 세션 내 자동 발동한다. 레거시 tmux supervisor는 폐기됨.

Steps:
1. TeamCreate로 연구팀 생성:
```
TeamCreate(team_name="research-v7", description="V7 All-Weather Portfolio Research Team")
```

2. 4인 teammate 병렬 스폰 (Agent tool, run_in_background=true):
```
Agent(name="scout", team_name="research-v7", run_in_background=true, model="sonnet",
  prompt="Read 02_Infrastructure/prompts/scout_init.md. inbox TODO 확인 → S0 가설 또는 S3/S5 작업.")
Agent(name="forge", team_name="research-v7", run_in_background=true, model="sonnet",
  prompt="Read 02_Infrastructure/prompts/forge_init.md. inbox TODO 대기.")
Agent(name="judge", team_name="research-v7", run_in_background=true, model="opus",
  prompt="Read 02_Infrastructure/prompts/judge_init.md. inbox TODO 대기.")
Agent(name="governor", team_name="research-v7", run_in_background=true, model="sonnet",
  prompt="Read 02_Infrastructure/prompts/governor_init.md. inbox TODO_PG0 대기.")
```

**모델 라우팅 원칙 (토큰 절감)**:
- **Opus 유지**: Judge (PIT/검증 최종 판결), Q-Lead (메인 세션)
- **Sonnet 다운그레이드**: Scout, Forge, Governor, Academic/Quant (S0 Debate)
- Risk Manager는 agent 정의 파일에서 model 지정 (R3 Closing 책임으로 Opus 권장)

3. 팀 상태 확인: `Read ~/.claude/teams/research-v7/config.json`

4. 이미 팀 실행 중이면 SendMessage로 상태 확인.

5. Send Telegram notification that team is online.

6. 세션 종료 시: `SendMessage(to="*", message={type:"shutdown_request"})`
