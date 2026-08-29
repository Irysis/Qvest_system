#!/usr/bin/env bash
# ★RETIRED (v10 2026-08-29, 도훈 지시 "lock box 개념은 삭제. 반박 금지")
#   lockbox 제도 폐지 — settings.json 미등록 + 재등록 금지. 파일은 사료 존치.
#   재열람 = git 태그 pre-v10-2layer.
# lockbox_audit_trail.sh — Lockbox 접근 전수 로깅 (Level 2 soft gate)
# v6.1 R2 P2
#
# 이벤트: PostToolUse[Read]
# 목적: lockbox 파일 읽기 발생 시 audit trail 기록
# (block은 selection_contamination_detector.sh가 Pre 단계에서)

set -euo pipefail
trap 'exit 0' ERR

# (v8.2.1 HOOK-P0-1) bare python3 = Windows Store 스텁 → 로깅 무발화 결함 수리.
# 공용 파서(_shared_parse.sh) 경유: FILE_PATH + QVEST_PY_BIN export.
INPUT=$(cat)
# (2026-07-24 Fable5 하네스 감사) raw-INPUT 조기-exit — 비-lockbox Read에서 python 파싱 스폰 제거 (superset 필터)
if ! printf '%s' "$INPUT" | grep -qi 'lockbox'; then exit 0; fi
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

FP_LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

case "$FP_LOWER" in
  *lockbox*)
    # (v8.2.1 AGT-01) Git Bash ps는 -o 미지원 → $PPID로 이식 (의미 동일: 현 셸의 부모 PID)
    PARENT_PID="${PPID:-0}"
    MARKER="/tmp/qvest_current_agent_${PARENT_PID}"
    AGENT=$([ -f "$MARKER" ] && cat "$MARKER" || echo "unknown")
    # (v8.2.1 HOOK-P1-2) WT-[DP] → WT-[DPSH]: 실제 mailbox 분포 D/S/P/H 반영
    WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DPSH][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "unknown")

    # (2026-08-02 r-portability 금칙 ③) 구 `/tmp/qvest_lockbox_access_*.log` 는 bash(MSYS)=
    # AppData\Local\Temp 인 반면 읽는 쪽(Windows R, v61_compliance_audit.R)은 C:/tmp 를 봤다.
    # → 기록이 감사자가 안 보는 디렉토리에 쌓여 P2 가 구조적으로 실패 불가였다(실측 237/237 PASS).
    # 경로 계약을 프로젝트-상대로 단일화: 02_Infrastructure/hooks/lockbox_paths.sh (짝 = worktask/lockbox_paths.R)
    source "$(dirname "${BASH_SOURCE[0]:-$0}")/lockbox_paths.sh"
    if LOG_FILE=$(qvest_lockbox_log_file "$WT_ID"); then
      mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
      echo "$(date -Iseconds) | $AGENT | read | $FILE_PATH" >> "$LOG_FILE"
      # 발화 사실 기록 — 감사가 "기록 0건"과 "검출기 사망"을 구별하는 유일한 근거
      qvest_lockbox_touch_heartbeat || true
    else
      # 루트 미해석 = 기록 유실. 조용히 삼키면 구 결함(빈 손 = 무위반)이 그대로 재발한다.
      echo "[lockbox_audit_trail] project root 미해석 — 접근기록 유실: $FILE_PATH" >&2
    fi
    ;;
esac

exit 0
