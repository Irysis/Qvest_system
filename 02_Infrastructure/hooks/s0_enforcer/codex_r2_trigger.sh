#!/usr/bin/env bash
# codex_r2_trigger.sh — R1_COMPLETE 시 Codex R2 Verify 백그라운드 스폰 (Phase C3.5 split)
#
# 사용: bash codex_r2_trigger.sh <HYP_ID> <ARTIFACTS_DIR>
# 결과: stage_artifacts/r2_codex_verdict_<HYP_ID>.json (nohup 완료 후)
#
# 이미 파일 존재 시 skip. Transcript 없으면 R1 파일 병합해서 합성.

set -uo pipefail
trap 'echo "{}"; exit 0' ERR

HYP_ID="${1:-}"
ARTIFACTS_DIR="${2:-}"
[ -z "$HYP_ID" ] || [ -z "$ARTIFACTS_DIR" ] && exit 0

DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
LOG="/tmp/s0_debate_enforcer.log"
CODEX_R2_OUT="$DIR/stage_artifacts/r2_codex_verdict_${HYP_ID}.json"

# 이미 결과 있으면 skip
[ -f "$CODEX_R2_OUT" ] && exit 0

CODEX_R1_FILE="$ARTIFACTS_DIR/s0_debate_r1_codex_critic_${HYP_ID}.json"
TRANSCRIPT_FILE="$ARTIFACTS_DIR/s0_debate_transcript_${HYP_ID}.json"

CODEX_R1_JSON="NO_R1"
[ -f "$CODEX_R1_FILE" ] && CODEX_R1_JSON=$(cat "$CODEX_R1_FILE")

if [ -f "$TRANSCRIPT_FILE" ]; then
  TRANSCRIPT_JSON=$(cat "$TRANSCRIPT_FILE")
else
  # Transcript 미생성 시 R1 파일 병합
  TRANSCRIPT_JSON=$(ARTIFACTS_DIR="$ARTIFACTS_DIR" HYP_ID="$HYP_ID" python3 -c "
import os, json, glob
adir = os.environ['ARTIFACTS_DIR']; hyp = os.environ['HYP_ID']
out = {'hypothesis_id': hyp, 'round': 'R1', 'debaters': []}
for f in sorted(glob.glob(os.path.join(adir, f's0_debate_r1_*_{hyp}.json'))):
    try:
        with open(f) as fh: out['debaters'].append(json.load(fh))
    except Exception: pass
print(json.dumps(out, ensure_ascii=False))
" 2>/dev/null)
fi

(
  R1_TRANSCRIPT="$TRANSCRIPT_JSON" \
  CODEX_R1_RESULT="$CODEX_R1_JSON" \
  HYP_ID="$HYP_ID" \
  bash "$DIR/02_Infrastructure/tools/debate_helpers/run_codex_critic_r2.sh" \
    > "$CODEX_R2_OUT.tmp" 2>>"$LOG"
  if [ -s "$CODEX_R2_OUT.tmp" ]; then
    mv "$CODEX_R2_OUT.tmp" "$CODEX_R2_OUT"
    echo "$(date +%H:%M:%S) CODEX_R2: ${HYP_ID} → $CODEX_R2_OUT" >> "$LOG"
  else
    rm -f "$CODEX_R2_OUT.tmp"
  fi
) &
disown 2>/dev/null || true
exit 0
