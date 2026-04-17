#!/bin/bash
# Telegram Listener Auto-Start Script
# 세션 시작 시 텔레그램 리스너가 실행 중이 아니면 자동으로 시작합니다.

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"

# Check if listener is already running
if pgrep -f "telegram_listener.py" > /dev/null 2>&1; then
    echo "[Listener] Already running (PID: $(pgrep -f telegram_listener.py))"
else
    echo "[Listener] Not running. Starting..."
    cd "$BASE/02_Infrastructure" && nohup python3 telegram_listener.py > /tmp/tg_listener.log 2>&1 &
    NEW_PID=$!
    echo "[Listener] Started with PID: $NEW_PID"
fi
