# settings.json Hook 등록 패치 초안 (Q-Lead 승인 필요)

## 현황
- 기존 Hook: 17개 (PreToolUse 5 + PostToolUse 7 + Stop 1 + FileChanged 1 + TeammateIdle 1 + TaskCompleted 1)
  - 실제 settings.json 기준: PreToolUse 5항목 + PostToolUse 5항목(일부 다중) + Stop 1 + FileChanged 1 + TeammateIdle 1 + TaskCompleted 1
- 추가 Hook: 3개 (v54 Freeze Guard)
- 결과: 20개

## 추가할 JSON 블록

### 1. PreToolUse[Write|Edit] 에 추가 -- Admission Rule Guard

```json
{
  "matcher": "Write|Edit",
  "hooks": [
    {
      "type": "command",
      "command": "DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo \"$PWD\"); bash \"$DIR/02_Infrastructure/hooks/v54_freeze_admission_rule_guard.sh\""
    }
  ]
}
```

### 2. PreToolUse[Write] 에 추가 -- Governor Rev Guard

```json
{
  "matcher": "Write",
  "hooks": [
    {
      "type": "command",
      "command": "DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo \"$PWD\"); bash \"$DIR/02_Infrastructure/hooks/v54_freeze_governor_rev_guard.sh\""
    }
  ]
}
```

### 3. PreToolUse[Write] 에 추가 -- Friday Exec-Only Guard

```json
{
  "matcher": "Write",
  "hooks": [
    {
      "type": "command",
      "command": "DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo \"$PWD\"); bash \"$DIR/02_Infrastructure/hooks/v54_freeze_friday_exec_only.sh\""
    }
  ]
}
```

## PreToolUse 배열 전체 (패치 후)

기존 5개 + 신규 3개 = 8개 항목:

```json
"PreToolUse": [
  { "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": "... axiom_enforcement_hook.sh" }] },
  { "matcher": "Write|Edit|Bash", "hooks": [{ "type": "command", "command": "... safety_guard.sh" }] },
  { "matcher": "Write|Edit|Bash", "hooks": [{ "type": "command", "command": "... forge_code_guard.sh" }] },
  { "matcher": "Agent", "hooks": [{ "type": "command", "command": "... unified_agent_guard.sh" }] },
  { "matcher": "Agent", "hooks": [{ "type": "command", "command": "... s0_debate_guard.sh" }] },
  { "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": "... v54_freeze_admission_rule_guard.sh" }] },
  { "matcher": "Write", "hooks": [{ "type": "command", "command": "... v54_freeze_governor_rev_guard.sh" }] },
  { "matcher": "Write", "hooks": [{ "type": "command", "command": "... v54_freeze_friday_exec_only.sh" }] }
]
```

## 실행 순서 (PreToolUse Write 시)

1. axiom_enforcement_hook.sh (AX-code 공리)
2. safety_guard.sh (05_Production/01_Literature 보호)
3. forge_code_guard.sh (OPT 코드 최적화)
4. v54_freeze_admission_rule_guard.sh (Admission Rule 동결) -- 신규
5. v54_freeze_governor_rev_guard.sh (Governor rev 동결) -- 신규
6. v54_freeze_friday_exec_only.sh (금요일 실행 전용) -- 신규

## 참고: crontab 추가 제안

```bash
# friday_alpha_snapshot.sh (KST 18:00 = UTC 09:00 금요일)
0 9 * * 5 cd /mnt/c/Users/User/OneDrive/바탕\ 화면/Quant_Module_Moltbot && bash 02_Infrastructure/ops/friday_alpha_snapshot.sh >> /tmp/friday_snapshot.log 2>&1
```
