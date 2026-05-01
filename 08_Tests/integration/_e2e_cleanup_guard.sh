#!/usr/bin/env bash
# _e2e_cleanup_guard.sh — v7.1-lite Sprint 0.1 Synthetic WT Safe Cleanup
#
# 목적: qepm/mailbox/worktask/WT-D9999*/ synthetic test residue 안전 제거.
#       + qepm/observability/timelines/wt_WT-D9999*.json 동시 정리.
#
# Safe procedure (4-step):
#   1. List candidates (write 안 함)
#   2. ID pattern + status.json verify (year 9999 prefix)
#   3. --force flag 또는 사용자 confirm
#   4. Verified만 삭제
#
# Usage:
#   bash _e2e_cleanup_guard.sh --list      # list only (default if no flag)
#   bash _e2e_cleanup_guard.sh --force     # delete verified items
#   bash _e2e_cleanup_guard.sh --check     # post-test residue check (CI: exit 1 if residue > 0)
#
# Plan: nifty-tickling-hinton.md → v7-1-cheerful-balloon.md Sprint 0.1

set -euo pipefail

PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
WT_ROOT="$PROJ_DIR/qepm/mailbox/worktask"
TIMELINES_DIR="$PROJ_DIR/qepm/observability/timelines"

MODE="${1:---list}"

# Synthetic ID pattern — year 9999 prefix
SYNTHETIC_PATTERN="^WT-D9999[0-9]{4}_[0-9]{3}$"

list_candidates() {
  local found=0
  if [ ! -d "$WT_ROOT" ]; then
    echo "[INFO] WT_ROOT not found: $WT_ROOT"
    return 0
  fi
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    found=$((found + 1))
    local wt_id
    wt_id=$(basename "$d")
    if [[ "$wt_id" =~ $SYNTHETIC_PATTERN ]]; then
      # Verify status.json
      local status_file="$d/status.json"
      if [ -f "$status_file" ]; then
        local task_id
        task_id=$(jq -r '.task_id // empty' "$status_file" 2>/dev/null || echo "")
        if [[ "$task_id" =~ ^WT-D9999 ]]; then
          echo "[VERIFIED] $wt_id (status.task_id=$task_id) — eligible"
        else
          echo "[SKIP] $wt_id (status.task_id mismatch: $task_id) — not eligible"
        fi
      else
        # status.json absent but pattern matches — still eligible (residue with broken state)
        echo "[VERIFIED] $wt_id (status.json absent, pattern match) — eligible"
      fi
    else
      echo "[SKIP] $wt_id — pattern mismatch (not synthetic year 9999)"
    fi
  done < <(find "$WT_ROOT" -maxdepth 1 -type d -name "WT-D9999*" 2>/dev/null | sort)

  if [ $found -eq 0 ]; then
    echo "[OK] no synthetic WT residue ✅"
  fi
  return 0
}

count_residue() {
  local n=0
  if [ -d "$WT_ROOT" ]; then
    n=$(find "$WT_ROOT" -maxdepth 1 -type d -name "WT-D9999*" 2>/dev/null | wc -l)
  fi
  echo "$n"
}

force_cleanup() {
  echo "=== Force cleanup mode ==="
  local deleted=0
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    local wt_id
    wt_id=$(basename "$d")
    if [[ ! "$wt_id" =~ $SYNTHETIC_PATTERN ]]; then
      echo "[ABORT] $wt_id pattern mismatch — refusing to delete (production safety)"
      continue
    fi
    # Verify status.json (or absent → still ok with pattern match)
    local status_file="$d/status.json"
    if [ -f "$status_file" ]; then
      local task_id
      task_id=$(jq -r '.task_id // empty' "$status_file" 2>/dev/null || echo "")
      if [[ ! "$task_id" =~ ^WT-D9999 ]] && [ -n "$task_id" ]; then
        echo "[ABORT] $wt_id status.task_id=$task_id (not synthetic) — refusing to delete"
        continue
      fi
    fi
    rm -rf "$d"
    deleted=$((deleted + 1))
    echo "[DELETED] $wt_id"
  done < <(find "$WT_ROOT" -maxdepth 1 -type d -name "WT-D9999*" 2>/dev/null | sort)

  # Timeline cleanup
  if [ -d "$TIMELINES_DIR" ]; then
    while IFS= read -r tf; do
      [ -z "$tf" ] && continue
      local tf_name
      tf_name=$(basename "$tf")
      # tf_name format: wt_WT-D9999YYYY_NNN.json
      if [[ "$tf_name" =~ ^wt_WT-D9999 ]]; then
        rm -f "$tf"
        echo "[DELETED] timeline $tf_name"
      fi
    done < <(find "$TIMELINES_DIR" -maxdepth 1 -type f -name "wt_WT-D9999*.json" 2>/dev/null | sort)
  fi

  echo ""
  echo "Total deleted: $deleted WT directories"
  local remaining
  remaining=$(count_residue)
  if [ "$remaining" -eq 0 ]; then
    echo "[OK] residue 0 ✅"
  else
    echo "[WARN] residue still $remaining — manual review needed"
    return 1
  fi
}

check_residue() {
  local n
  n=$(count_residue)
  if [ "$n" -eq 0 ]; then
    echo "[CI OK] synthetic WT residue 0 ✅"
    return 0
  else
    echo "[CI FAIL] synthetic WT residue $n in production mailbox:"
    find "$WT_ROOT" -maxdepth 1 -type d -name "WT-D9999*" 2>/dev/null
    return 1
  fi
}

case "$MODE" in
  --list) list_candidates ;;
  --force) force_cleanup ;;
  --check) check_residue ;;
  *) echo "Usage: $0 [--list|--force|--check]"; exit 2 ;;
esac
