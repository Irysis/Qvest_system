#!/bin/bash

trap 'echo "{}"; exit 0' ERR  # Phase C3 전수 강제
#==============================================================================
# TaskCompleted Hook — 작업 완료 시 artifact 검증
# exit 0 = 완료 허용, exit 2 = 완료 차단 + 피드백
#==============================================================================

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"

INPUT=$(cat)

# 최근 2분 내 생성된 DONE_S6 파일 → L-code 검증
RECENT_DONE=$(find "$PROJECT/qepm/mailbox/" -name "DONE_S6_*" -mmin -2 2>/dev/null | head -1)

if [ -n "$RECENT_DONE" ]; then
  strategy=$(basename "$RECENT_DONE" | sed 's/DONE_S6_//' | sed 's/.json//')

  # 1. L-code 필수 (기존)
  lcode=$(find "$PROJECT/04_Research/strategies/" -path "*${strategy}*" -name "l_code_*.json" 2>/dev/null | head -1)
  if [ -z "$lcode" ]; then
    echo "L-code가 없습니다. stage_artifacts/l_code_${strategy}.json을 먼저 작성하세요. L-code는 S6의 EXIT CONDITION입니다."
    exit 2
  fi

  # 2. tail_risk_result 필수 (신규 — Gate 6, Pfaff 2016)
  tail_risk=$(find "$PROJECT/04_Research/strategies/" -path "*${strategy}*" -name "tail_risk_result*.json" 2>/dev/null | head -1)
  if [ -z "$tail_risk" ]; then
    echo "tail_risk_result.json이 없습니다. compute_tail_risk_suite()를 먼저 실행하세요. Gate 6 (Tail Risk) 검증은 S6의 EXIT CONDITION입니다."
    exit 2
  fi
fi

exit 0
