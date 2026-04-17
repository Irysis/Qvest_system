#!/bin/bash
# Q-Lead Supervisor v7.1 — ANSI-safe detection + polling restart + 3-state management
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
cd "$PROJECT"

SCOUT_PROMPT="/scout"
FORGE_PROMPT="/forge"
JUDGE_PROMPT="/judge"
# Governor는 Q-Lead가 수동으로만 깨움 (/governor)

strip_ansi() {
  sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\].*\x07//g'
}

round=0
while true; do
  round=$((round + 1))

  for pane in 0 1 2; do
    case $pane in
      0) PROMPT="$SCOUT_PROMPT" ;;
      1) PROMPT="$FORGE_PROMPT" ;;
      2) PROMPT="$JUDGE_PROMPT" ;;
    esac
    # Governor(pane 3)는 Q-Lead가 TODO_PG0 생성 시에만 수동 깨움

    last_line=$(tmux capture-pane -t research:0.$pane -p 2>/dev/null | strip_ansi | grep -v "^$" | tail -1)

    # State 1: Shell prompt — claude exited → restart with role enforcement
    if echo "$last_line" | grep -qE '(\$\s*$|^quant@)'; then
      echo "[sv] Pane $pane: shell detected. Restarting claude as $(echo $PROMPT | tr -d '/')..."
      # 역할 환경변수 설정
      ROLE=$(echo "$PROMPT" | tr -d '/')
      tmux send-keys -t research:0.$pane "export AGENT_ROLE=$ROLE" Enter
      sleep 0.5
      # Forge(pane 1)는 sonnet 모델로 실행
      if [ "$pane" -eq 1 ]; then
        tmux send-keys -t research:0.$pane "cd '$PROJECT' && claude --dangerously-skip-permissions --model sonnet" Enter
      else
        tmux send-keys -t research:0.$pane "cd '$PROJECT' && claude --dangerously-skip-permissions" Enter
      fi
      for i in $(seq 1 15); do
        sleep 2
        check=$(tmux capture-pane -t research:0.$pane -p 2>/dev/null | strip_ansi | grep -v "^$" | tail -1)
        if echo "$check" | grep -qE '(bypass|❯)'; then break; fi
      done
      # 역할별 slash command 주입 (pane 고정)
      tmux send-keys -t research:0.$pane "$PROMPT" Enter
      sleep 3
      continue
    fi

    # State 2: Claude idle → TeammateIdle Hook이 처리 (supervisor 불개입)
    # inbox TODO가 있으면 Hook이 exit 2로 에이전트를 계속 작동시킴
    # supervisor는 idle 상태에 개입하지 않음

    # State 3: Claude working → skip
  done

  # Governor pane health check — recreate if missing
  GOV_PANE_COUNT=$(tmux list-panes -t research:0 2>/dev/null | wc -l)
  if [ "$GOV_PANE_COUNT" -lt 4 ]; then
    echo "[sv] Governor pane missing ($GOV_PANE_COUNT panes). Recreating..."
    LAST=$((GOV_PANE_COUNT - 1))
    tmux split-window -v -t "research:0.${LAST}"
    sleep 1
    NEW_IDX=$(( $(tmux list-panes -t research:0 2>/dev/null | wc -l) - 1 ))
    tmux send-keys -t "research:0.${NEW_IDX}" "export AGENT_ROLE=governor" Enter
    sleep 0.5
    tmux send-keys -t "research:0.${NEW_IDX}" "cd '$PROJECT' && claude --dangerously-skip-permissions" Enter
    echo "[sv] Governor pane $NEW_IDX created (role=governor)"
    for i in $(seq 1 15); do
      sleep 2
      check=$(tmux capture-pane -t "research:0.${NEW_IDX}" -p 2>/dev/null | strip_ansi | grep -v "^$" | tail -1)
      if echo "$check" | grep -qE '(bypass|❯)'; then break; fi
    done
  fi

  # Pipeline driver (gap 갱신과 Scout TODO는 pipeline_trigger.sh Hook이 담당)
  Rscript --no-save -e 'suppressMessages({source("02_Infrastructure/config.R"); source("02_Infrastructure/stage_gate_engine.R")}); sg_sync_all(); sg_drive_pipeline()' 2>/dev/null

  # v53 Fix #2: 경로 오타 교정 (07_QEPM → qepm) + Forge/Judge/Governor 자동 깨움 확장
  MAILBOX="$PROJECT/qepm/mailbox"
  declare -A PANE_INBOX=(
    [1]="forge/inbox/TODO_S"
    [2]="judge/inbox/TODO_S"
    [3]="q_lead/inbox/TODO_PG"
  )
  declare -A PANE_CMD=( [1]="/forge" [2]="/judge" [3]="/governor" )
  for p in 1 2 3; do
    n=$(ls "$MAILBOX/${PANE_INBOX[$p]}"*.json 2>/dev/null | wc -l)
    [ "$n" -eq 0 ] && continue
    line=$(tmux capture-pane -t "research:0.$p" -p 2>/dev/null | strip_ansi | grep -v "^$" | tail -1)
    if echo "$line" | grep -qE '(bypass|❯)'; then
      tmux send-keys -t "research:0.$p" "${PANE_CMD[$p]}" Enter
      echo "[sv] pane $p woke: $n TODO files"
    fi
  done

  # Telegram monitor disabled (Session 50 — 도훈님 요청)
  if false && [ $((round % 30)) -eq 0 ]; then
    CLAUDE_N=$(ps aux | grep 'claude' | grep -v grep | grep -v "$$" | wc -l)
    R_N=$(ps aux | grep 'R --no-echo' | grep -v grep | grep -v 'krx\|arrow\|daily' | wc -l)
    RAM=$(free | awk '/Mem:/ {printf "%.0f", ($2-$7)/$2*100}')
    Rscript --no-save -e "
source('02_Infrastructure/telegram_notify.R')
tg_send(sprintf('[Q-Lead] %s Monitor\nClaude:%d R:%d RAM:%s%%\nPanes: Scout+Forge+Judge+Governor',
  format(Sys.time(),'%H:%M'), ${CLAUDE_N}, ${R_N}, '${RAM}'))
" 2>/dev/null
  fi

  sleep 30
done
