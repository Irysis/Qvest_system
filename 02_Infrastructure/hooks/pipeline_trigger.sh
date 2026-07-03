#!/usr/bin/env bash
#==============================================================================
# pipeline_trigger.sh — V7 Pipeline Trigger (Phase C2: 30L wrapper)
#
# 310줄 bash 체인 → 30L wrapper + python3 dispatcher.
# 변경된 파일 1건 기반 O(1) 매칭. fallback: full mailbox scan.
#
# Stage transitions: pipeline/stage_transitions.json (선언적 테이블)
# Dedup: SQLite WAL (/tmp/pipeline_dedup.sqlite, TTL 30s)
# Special handlers: pipeline/{stage_dispatch,role_router}.py
#==============================================================================

trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/_shared_parse.sh"
source "$SCRIPT_DIR/resolve_project.sh"

LOCKFILE="/tmp/pipeline_trigger.lock"
# Git Bash(MSYS)엔 flock 부재 → command not found가 SKIP 분기로 빠져 stage_dispatch 영구 미호출이던 버그 수정 (2026-06-10)
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCKFILE" || exit 0
  flock -n 9 || { echo "$(date +%H:%M:%S) SKIP: another trigger running" >> /tmp/pipeline_trigger.log; exit 0; }
else
  LOCKDIR="/tmp/pipeline_trigger.lock.d"
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    # stale lock (10분+) 자동 해제 후 재시도
    if [ -n "$(find "$LOCKDIR" -maxdepth 0 -mmin +10 2>/dev/null)" ]; then
      rmdir "$LOCKDIR" 2>/dev/null
      mkdir "$LOCKDIR" 2>/dev/null || { echo "$(date +%H:%M:%S) SKIP: mkdir lock held" >> /tmp/pipeline_trigger.log; exit 0; }
    else
      echo "$(date +%H:%M:%S) SKIP: mkdir lock held" >> /tmp/pipeline_trigger.log; exit 0
    fi
  fi
  trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT
fi

# Stale axiom lockfile cleanup (24h+) — 기존 정책 유지
find /tmp -name "axiom_distill_trigger_*" -mmin +1440 -delete 2>/dev/null || true

# 변경 파일 추출 (Write/Edit). Bash event는 fallback (full scan).
CHANGED=""
if [ "${TOOL_NAME:-}" = "Write" ] || [ "${TOOL_NAME:-}" = "Edit" ]; then
  CHANGED="${FILE_PATH:-}"
fi

# Dispatcher 호출 (단일 python 프로세스)
if [ -n "$CHANGED" ]; then
  "$QVEST_PY_BIN" "$SCRIPT_DIR/pipeline/stage_dispatch.py" "$PROJECT_ROOT" "$CHANGED" 2>>/tmp/pipeline_trigger.log || true
else
  "$QVEST_PY_BIN" "$SCRIPT_DIR/pipeline/stage_dispatch.py" "$PROJECT_ROOT" 2>>/tmp/pipeline_trigger.log || true
fi

echo '{}'
exit 0
