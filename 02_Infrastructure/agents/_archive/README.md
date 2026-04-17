# Legacy Archive (v50/v52)

v53 아키텍처(TeamCreate + Hook 단일 세션) 전환으로 아래 스크립트들은 더 이상 사용하지 않습니다.

| 파일 | 역할 (당시) | v53 대체 |
|------|------------|---------|
| `qlead_supervisor.sh` | tmux pane liveness 체크 + /scout //forge //judge 재주입 | TeamCreate + TeammateIdle Hook |
| `launch_team.sh` | tmux session/pane 생성 + mailbox loop | TeamCreate 도구 + Agent 스폰 |
| `forge_poller.sh` | Forge pane mailbox polling | pipeline_trigger.sh (PostToolUse) |
| `agent_forge.R` | Forge pane R loop (자율 실행) | teammate prompt + Hook |
| `agent_judge.R` | Judge pane R loop | teammate prompt + Hook |
| `agent_scout.R` | Scout pane R loop | teammate prompt + Hook |

이력 보존 목적으로만 남겨두며, 활성 경로에서 참조하지 않습니다. 필요 시 git blame / git log로 참고하세요.
