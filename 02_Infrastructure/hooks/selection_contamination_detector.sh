#!/usr/bin/env bash
# ★RETIRED (v10 2026-08-29, 도훈 지시 "lock box 개념은 삭제. 반박 금지")
#   lockbox 제도 폐지 — settings.json 미등록 + 재등록 금지. 파일은 사료 존치.
#   재열람 = git 태그 pre-v10-2layer.
# selection_contamination_detector.sh — Lockbox 데이터 오염 차단 (Level 3 hard block)
# v6.1 R2 P2 / v6.5 (2026-05-09 도훈 mandate scope 정정)
#
# 이벤트: PreToolUse[Read]
# 목적: **정규 리서치 단계 (alpha-research / risk-research / optimizer-research)** 에서만
#       lockbox 데이터 접근 차단. Judge / Forge / Monitoring / Q-Lead 는 허용.
#
# 도훈 mandate 2026-05-09:
#   "Frozen 규칙 리서치 정규 프로세스에만 적용. 전기간 백테스팅, 성과 트래킹 등
#    정규 리서치 외에선 Frozen 폐기"
#   → forge (전기간 백테), monitoring (성과 트래킹), Q-Lead (집계 보고) 모두 lockbox 접근 OK
#   → alpha / risk / optimizer 정규 리서치 단계만 block (PIT lookahead bias 방지)
#
# Lockbox 판별:
#   - 파일 경로에 "lockbox" 포함
#   - stage_artifacts/WT*/lockbox/ 경로
#   - evaluation_windows.lockbox_window 범위 내 날짜

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

# (v8.2.1 HOOK-P0-1) bare python3 = Windows Store 스텁 → 하드블록이 fail-open 되던 결함 수리.
# 공용 파서(_shared_parse.sh) 경유: FILE_PATH + QVEST_PY_BIN export.
INPUT=$(cat)
# (2026-07-24 Fable5 하네스 감사) raw-INPUT 조기-exit — 비-lockbox Read(사실상 전부)에서 python 파싱 스폰 제거.
# superset 필터(file_path가 raw JSON에 원문 포함, 'lockbox'는 ASCII라 escape 무관) — 정밀 판별은 아래 case가 수행.
if ! printf '%s' "$INPUT" | grep -qi 'lockbox'; then echo '{}'; exit 0; fi
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

FP_LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

# Lockbox 파일 판별
case "$FP_LOWER" in
  *lockbox*|*stage_artifacts/wt*/lockbox*)
    # Agent 식별
    # (v8.2.1 AGT-01) Git Bash ps는 -o 미지원 → 한 번도 발화 못함. $PPID(현 셸의 부모 PID)로
    # 이식 — 기존 `ps -o ppid= -p $$` 와 의미 동일.
    PARENT_PID="${PPID:-0}"
    MARKER="/tmp/qvest_current_agent_${PARENT_PID}"
    AGENT_NAME=""
    if [[ -f "$MARKER" ]]; then
      AGENT_NAME=$(cat "$MARKER")
    fi

    case "$AGENT_NAME" in
      judge*|forge*|monitoring*|execution*)
        # Judge / Forge / Monitoring / Execution 허용 (운용·트래킹 단계, lockbox 폐기 정합)
        # 도훈 mandate 2026-05-09: 전기간 백테 / 성과 트래킹 = lockbox 폐기
        # (v8.2.1 HOOK-P1-2) WT-[DP] → WT-[DPSH]: 실제 mailbox 분포 D/S/P/H 반영 (audit log 파일명용)
        WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DPSH][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "unknown")
        # (2026-08-02 r-portability 금칙 ③) 경로 계약 단일화 — lockbox_paths.sh 참조.
        # ⚠ 이 훅은 2026-07-24 도훈 승인으로 settings.json 등록 해제 상태(marker writer 부재로
        #    구조적 상시 allow). 파일은 retain 이므로 재등록 시 경로가 갈리지 않도록 함께 수리한다.
        source "$(dirname "${BASH_SOURCE[0]:-$0}")/lockbox_paths.sh"
        if _LB_LOG=$(qvest_lockbox_log_file "$WT_ID"); then
          mkdir -p "$(dirname "$_LB_LOG")" 2>/dev/null || true
          echo "$(date -Iseconds) | $AGENT_NAME | $FILE_PATH" >> "$_LB_LOG"
          qvest_lockbox_touch_heartbeat || true
        else
          echo "[selection_contamination_detector] project root 미해석 — 접근기록 유실: $FILE_PATH" >&2
        fi
        echo "{}"
        ;;
      alpha*|risk*|optimizer*|opt_*)
        # 정규 리서치 단계만 block (PIT lookahead bias 방지 — Frozen 규칙 적용)
        echo "{\"decision\":\"block\",\"reason\":\"P2 Data Separation 위반: $AGENT_NAME 정규 리서치 단계에서 lockbox 접근 시도 — Judge / Forge / Monitoring / Execution 만 허용. Frozen 규칙 적용 (도훈 mandate 2026-05-09 scope).\"}"
        ;;
      *)
        # Q-Lead / unidentified → allow (집계 보고 / 트래킹 mandate)
        echo '{}'
        ;;
    esac
    ;;
  *)
    echo '{}'
    ;;
esac
