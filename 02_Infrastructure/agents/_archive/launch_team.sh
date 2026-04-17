#!/bin/bash
# ══════════════════════════════════════════════════════════════════
# QEPM Multi-Agent Team Launcher v2
# Usage: bash launch_team.sh [mode]
#   mode: research | monitor | infra | full | mailbox | dispatch
# Requires: tmux, Claude Code with Agent Teams enabled
#
# v2 Changes:
#   - mailbox mode: Start agent polling loops (API-free IPC)
#   - dispatch mode: Execute backlog items via skill_dispatch.R
#   - All modes: Initialize mailbox directories on startup
# ══════════════════════════════════════════════════════════════════

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
SESSION_NAME="qepm-team"
MODE="${1:-research}"
DISPATCH_SCRIPT="$PROJECT_ROOT/qepm/R/orchestration/skill_dispatch.R"
MAILBOX_SCRIPT="$PROJECT_ROOT/qepm/R/orchestration/agent_mailbox.R"

export QEPM_PROJECT_ROOT="$PROJECT_ROOT"

# ── Initialize mailbox directories ──
init_mailbox() {
  for agent in q_lead scout forge judge blender watch; do
    mkdir -p "$PROJECT_ROOT/qepm/mailbox/$agent/inbox"
    mkdir -p "$PROJECT_ROOT/qepm/mailbox/$agent/outbox"
  done
  echo "[OK] Mailbox directories initialized"
}

# Kill existing session if any
cleanup_session() {
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null
}

echo "══════════════════════════════════════"
echo " QEPM Multi-Agent System v2"
echo " Mode: $MODE"
echo "══════════════════════════════════════"

# Always init mailbox
init_mailbox

case "$MODE" in
  research)
    echo "[INFO] Research mode: Q-Lead + Scout + Forge x3"
    echo "[INFO] Start Claude Code in this tmux session."
    echo "[INFO] Then ask: '전략 연구 팀 구성해줘'"
    cleanup_session
    tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50
    tmux send-keys -t "$SESSION_NAME" "cd \"$PROJECT_ROOT\" && claude --dangerously-skip-permissions" Enter
    tmux attach -t "$SESSION_NAME"
    ;;

  monitor)
    echo "[INFO] Monitor mode: Q-Lead + Watch"
    echo "[INFO] Start Claude Code for daily monitoring."
    cleanup_session
    tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50
    tmux send-keys -t "$SESSION_NAME" "cd \"$PROJECT_ROOT\" && claude --dangerously-skip-permissions" Enter
    tmux attach -t "$SESSION_NAME"
    ;;

  infra)
    echo "[INFO] Infrastructure mode: Q-Lead + Scout + Forge"
    echo "[INFO] Start Claude Code for infra development."
    cleanup_session
    tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50
    tmux send-keys -t "$SESSION_NAME" "cd \"$PROJECT_ROOT\" && claude --dangerously-skip-permissions" Enter
    tmux attach -t "$SESSION_NAME"
    ;;

  full)
    echo "[INFO] Full mode: All agents (Claude Code + Mailbox polling)"
    cleanup_session
    tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50

    # Pane 0: Q-Lead (Claude Code main)
    tmux send-keys -t "$SESSION_NAME" "cd \"$PROJECT_ROOT\" && claude --dangerously-skip-permissions" Enter

    # Pane 1: Forge agent polling loop
    tmux split-window -h -t "$SESSION_NAME"
    tmux send-keys -t "$SESSION_NAME" "cd \"$PROJECT_ROOT\" && Rscript -e 'source(\"qepm/R/orchestration/skill_dispatch.R\"); agent_poll_loop(\"forge\", 15)'" Enter

    # Pane 2: Judge agent polling loop
    tmux split-window -v -t "$SESSION_NAME"
    tmux send-keys -t "$SESSION_NAME" "cd \"$PROJECT_ROOT\" && Rscript -e 'source(\"qepm/R/orchestration/skill_dispatch.R\"); agent_poll_loop(\"judge\", 15)'" Enter

    # Pane 3: Watch agent polling loop
    tmux split-window -v -t "$SESSION_NAME":0
    tmux send-keys -t "$SESSION_NAME" "cd \"$PROJECT_ROOT\" && Rscript -e 'source(\"qepm/R/orchestration/skill_dispatch.R\"); agent_poll_loop(\"watch\", 30)'" Enter

    tmux select-pane -t "$SESSION_NAME":0.0
    tmux attach -t "$SESSION_NAME"
    ;;

  mailbox)
    echo "[INFO] Mailbox mode: Start polling loops for all agents"
    echo "[INFO] Each agent watches its inbox and auto-executes tasks"
    cleanup_session
    tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50

    # One pane per agent (except q_lead which is Claude Code)
    for agent in forge judge scout blender watch; do
      if [ "$agent" != "forge" ]; then
        tmux split-window -t "$SESSION_NAME"
      fi
      interval=15
      [ "$agent" = "watch" ] && interval=30
      [ "$agent" = "blender" ] && interval=20
      tmux send-keys -t "$SESSION_NAME" "cd \"$PROJECT_ROOT\" && echo '[$agent] Starting...' && Rscript -e 'source(\"qepm/R/orchestration/skill_dispatch.R\"); agent_poll_loop(\"$agent\", $interval)'" Enter
    done

    tmux select-layout -t "$SESSION_NAME" tiled
    echo "[INFO] 5 agent polling loops started"
    echo "[INFO] Q-Lead = Claude Code (this terminal or separate session)"
    echo "[INFO] Send tasks: Rscript qepm/R/orchestration/agent_mailbox.R send <to> <from> task <subject>"
    tmux attach -t "$SESSION_NAME"
    ;;

  dispatch)
    # One-shot dispatch: run N items from backlog
    N="${2:-1}"
    echo "[INFO] Dispatching $N items from backlog..."
    cd "$PROJECT_ROOT"
    Rscript -e "source('qepm/R/orchestration/skill_dispatch.R'); dispatch_batch($N)"
    ;;

  status)
    echo "[INFO] Mailbox status:"
    cd "$PROJECT_ROOT"
    Rscript -e "source('qepm/R/orchestration/agent_mailbox.R'); cat(jsonlite::toJSON(mailbox_status(), auto_unbox=TRUE, pretty=TRUE))"
    ;;

  cleanup)
    HOURS="${2:-24}"
    echo "[INFO] Cleaning up messages older than ${HOURS}h..."
    cd "$PROJECT_ROOT"
    Rscript -e "source('qepm/R/orchestration/agent_mailbox.R'); n <- mailbox_cleanup($HOURS); cat(sprintf('Cleaned %d messages\n', n))"
    ;;

  *)
    echo "Usage: bash launch_team.sh [mode]"
    echo ""
    echo "  Claude Code modes:"
    echo "    research   — Q-Lead + Scout + Forge x3 (tmux)"
    echo "    monitor    — Q-Lead + Watch (tmux)"
    echo "    infra      — Q-Lead + Scout + Forge (tmux)"
    echo "    full       — All agents: Claude Code + mailbox polling"
    echo ""
    echo "  API-free modes:"
    echo "    mailbox    — Start 5 agent polling loops (no Claude Code)"
    echo "    dispatch   — One-shot: dispatch N backlog items"
    echo "    status     — Show mailbox queue status"
    echo "    cleanup    — Remove old messages (default: 24h)"
    exit 1
    ;;
esac
