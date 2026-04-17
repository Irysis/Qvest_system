---
name: launch-team
description: "TeamCreate 4인 연구팀 일괄 가동. Hook 세션 내 완전 자동."
disable-model-invocation: true
user-invocable: true
---
Launch the full research agent team via TeamCreate (v53).
Q-Lead 단일 세션 안에서 teammate 4인이 spawn되고 모든 Hook이 세션 내 자동 발동한다. 레거시 tmux supervisor는 폐기됨.

Steps:
1. TeamCreate로 연구팀 생성:
```
TeamCreate(team_name="research-v7", description="V7 All-Weather Portfolio Research Team")
```

2. 4인 teammate 병렬 스폰 (Agent tool, run_in_background=true):
```
Agent(name="scout", team_name="research-v7", run_in_background=true,
  prompt="Read 02_Infrastructure/prompts/scout_init.md. inbox TODO 확인 → S0 가설 또는 S3/S5 작업.")
Agent(name="forge", team_name="research-v7", run_in_background=true,
  prompt="Read 02_Infrastructure/prompts/forge_init.md. inbox TODO 대기.")
Agent(name="judge", team_name="research-v7", run_in_background=true,
  prompt="Read 02_Infrastructure/prompts/judge_init.md. inbox TODO 대기.")
Agent(name="governor", team_name="research-v7", run_in_background=true,
  prompt="Read 02_Infrastructure/prompts/governor_init.md. inbox TODO_PG0 대기.")
```

3. 팀 상태 확인: `Read ~/.claude/teams/research-v7/config.json`

4. 이미 팀 실행 중이면 SendMessage로 상태 확인.

5. Send Telegram notification that team is online.

6. 세션 종료 시: `SendMessage(to="*", message={type:"shutdown_request"})`
