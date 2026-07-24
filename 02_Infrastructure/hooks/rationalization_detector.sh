#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# rationalization_detector.sh — Tier 4 self-rationalization phrase detector (L2 soft gate)
#
# 이벤트: PostToolUse[Write]
# 목적: agent self-bypass via 합리화 표현 자동 탐지
# 무한루프 회피: read-only + retry counter (3+ warn → escalate)

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
# (2026-07-24 Fable5 하네스 감사) raw-INPUT 조기-exit — 비대상 W/E에서 python 2스폰 제거 (superset 필터)
if ! printf '%s' "$INPUT" | grep -qE 'challenge_note|_verdict\.json|judge_verdict|_admission\.json|governor_admission'; then echo '{}'; exit 0; fi
TOOL=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{}'; exit 0; fi

# Strict regex matching: challenge_note / verdict / admission / risk_challenge / optimizer_challenge / governor_challenge / judge_challenge
case "$FILE_PATH" in
  *_challenge_note.md|*challenge_note*.md)
    ;;
  *_verdict.json|*judge_verdict*.json)
    ;;
  *_admission.json|*governor_admission*.json)
    ;;
  *)
    echo '{}'; exit 0
    ;;
esac

CONTENT=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content","") or d.get("tool_input",{}).get("new_string",""))' 2>/dev/null || echo "")

DETECTED=()

# 한글 합리화 phrase library
declare -a PHRASES_KR=(
  "영향 미미"
  "관행적 허용"
  "보수적이면 괜찮다"
  "보수적이면 OK"
  "대부분 결과 동일"
  "이미 반영되어 있었을 것"
  "이미 반영"
  "백테스트 기간 충분"
  "백테스트 기간이 충분히"
  "영향이 미미"
  "사소함"
  "효과 미미"
  "충분한 표본"
)

# English rationalization library
declare -a PHRASES_EN=(
  "in spirit"
  "PASS_WITH_NOTE without evidence"
  "negligible impact"
  "minor deviation"
  "common practice"
  "structurally fine"
)

# Special cases — 단독 사용 시만 합리화 (학술 인용과 함께면 정당)
declare -a CONDITIONAL_PHRASES=(
  "necessary not sufficient"
  "supplementary not primary"
  "load_month_factors equivalent"
)

for phrase in "${PHRASES_KR[@]}" "${PHRASES_EN[@]}"; do
  if echo "$CONTENT" | grep -qF "$phrase"; then
    DETECTED+=("$phrase")
  fi
done

# Conditional check: phrase 사용 시 학술 인용 (DOI/논문/L-code) 동시 존재 검증
for phrase in "${CONDITIONAL_PHRASES[@]}"; do
  if echo "$CONTENT" | grep -qF "$phrase"; then
    if ! echo "$CONTENT" | grep -qE '(L-[0-9]{3}|doi:|arxiv:|논문|2009|2013|2016|Harvey|DeMiguel)'; then
      DETECTED+=("$phrase (no academic citation)")
    fi
  fi
done

# Retry counter (3+ → escalate)
if [[ ${#DETECTED[@]} -gt 0 ]]; then
  COUNTER_FILE="/tmp/rationalization_warn_count_$(basename "$FILE_PATH").txt"
  COUNT=0
  [[ -f "$COUNTER_FILE" ]] && COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  COUNT=$((COUNT + 1))
  echo "$COUNT" > "$COUNTER_FILE"

  PHRASE_LIST=$(IFS=','; echo "${DETECTED[*]}")
  RD_MSG="합리화 표현 감지: [$PHRASE_LIST] — 3축 근거(학술 인용 + L-code + 정량 데이터) 보강 또는 표현 제거 (answer-principles 회피표현 조항)"
  if [[ $COUNT -ge 3 ]]; then
    RD_MSG="RATIONALIZATION_RETRY_CAP (동일 파일 3+ 감지 — Q-Lead escalate 필요): $RD_MSG"
  fi
  # (2026-07-24 Fable5 하네스 감사) 전달 복원 — 0ab8b039(2026-05-29) 회귀로 감지 결과가 어떤 채널에도
  # 도달하지 않던 no-op 상태 수리 (challenge_note 카운터 52회 누적·전달 0 실측). additionalContext 실전달.
  RD_MSG="$RD_MSG" "$QVEST_PY_BIN" -c 'import json,os; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[rationalization_detector] "+os.environ.get("RD_MSG","")}}))' 2>/dev/null || echo '{}'
else
  echo '{}'
fi
