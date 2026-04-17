#!/bin/bash
#==============================================================================
# persistent_remote_control.sh
# /remote-control 자동 재연결 래퍼
# 끊기면 10초 후 자동 재시작. tmux에서 백그라운드 실행 권장.
#
# 사용법:
#   bash 02_Infrastructure/persistent_remote_control.sh
#   또는 tmux에서: tmux new-session -d -s rc 'bash 02_Infrastructure/persistent_remote_control.sh'
#==============================================================================

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
RETRY_DELAY=10
MAX_RETRIES=0  # 0 = 무한 재시도

retry_count=0

while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Remote Control 시작..."
    cd "$PROJECT_ROOT"

    # claude remote-control 실행
    claude remote-control "Quant_Module_Moltbot"
    exit_code=$?

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Remote Control 종료 (exit=$exit_code)"

    # 정상 종료(사용자가 직접 종료)이면 루프 탈출
    if [ $exit_code -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 정상 종료. 재시작하지 않습니다."
        break
    fi

    retry_count=$((retry_count + 1))

    # MAX_RETRIES > 0이면 횟수 제한
    if [ $MAX_RETRIES -gt 0 ] && [ $retry_count -ge $MAX_RETRIES ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 최대 재시도 횟수($MAX_RETRIES) 도달. 종료."
        break
    fi

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${RETRY_DELAY}초 후 재시작 (시도 #${retry_count})..."
    sleep $RETRY_DELAY
done
