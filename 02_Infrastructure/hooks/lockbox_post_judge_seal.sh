#!/usr/bin/env bash
# ★RETIRED (v10 2026-08-29, 도훈 지시 "lock box 개념은 삭제. 반박 금지")
#   lockbox 제도 폐지 — settings.json 미등록 + 재등록 금지. 파일은 사료 존치.
#   재열람 = git 태그 pre-v10-2layer.
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# lockbox_post_judge_seal.sh — Judge verdict 저장 후 lockbox 봉인 (Level 2)
# v6.1 R2-B Hook 3
#
# 이벤트: PostToolUse[Write] on judge_verdict*.json
# 목적: Judge verdict 저장 순간 lockbox 데이터에 sealed=true flag
#       재접근 시 warn + 이유 기록 의무 (post-hoc selection bias 방지)

set -euo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

FP_LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

case "$FP_LOWER" in
  *judge_verdict*|*judge_ready*verdict*)
    WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DP][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "")
    [[ -z "$WT_ID" ]] && exit 0

    DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
    WT_DIR="$DIR/qepm/mailbox/worktask/$WT_ID"
    [[ ! -d "$WT_DIR" ]] && exit 0

    SEAL_FILE="$WT_DIR/lockbox_sealed.json"
    TS=$(date -Iseconds)
    # (2026-08-02) 접근기록 경로 계약 단일화 — 구 "/tmp/..." 는 bash 와 R 이 다른 디렉토리로
    # 해석해 감사가 죽었다. 안내문도 실제 기록 위치를 가리키게 한다(문서가 거짓말하면 사람이 헛본다).
    source "$(dirname "${BASH_SOURCE[0]:-$0}")/lockbox_paths.sh"
    SEAL_TRAIL_HINT=$(qvest_lockbox_log_file "$WT_ID" || echo "${QVEST_LOCKBOX_SUBDIR}/qvest_lockbox_access_${WT_ID}.log")
    cat > "$SEAL_FILE" <<EOF
{
  "task_id": "$WT_ID",
  "sealed": true,
  "sealed_at": "$TS",
  "sealed_by": "judge",
  "reason": "judge_verdict_published",
  "post_seal_access_warning": "lockbox re-access after seal requires explicit rationale in ${SEAL_TRAIL_HINT}"
}
EOF
    echo "[lockbox_seal] $WT_ID sealed at $TS" >> "/tmp/qvest_lockbox_seal.log"
    ;;
esac

exit 0
