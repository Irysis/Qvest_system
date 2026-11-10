#!/usr/bin/env bash
#==============================================================================
# backtest_contract_audit.sh — PreToolUse[Write] L3 hard block
#
# Backtest Result Contract v1.0 §20 enforcement
# Reference: 00_Lawbook/specs/backtest_result_contract.md §20
#
# 차단 대상 (audit_status != PASS 시 deny):
#   - qepm/registry/backtest_registry.csv 등재 시도
#   - methodology_active.md L-code 등재 시도 (백테스트 metric 인용 시)
#
# ★2026-08-24 재등록 이력 — 이 훅은 2026-08-23 플랜 D-d 로 **등록 해제**돼 있었다.
#   해제 사유는 원장 integrity 차단이 아니라 **.py 자체합성 idiom 차단의 오탐**이었다
#   (v8.4 ML 레인의 정상 .py Write 가 걸렸다). 두 임무는 조기 반환으로 이미 분리돼
#   있었으므로 .py 가지만 잘라내고 재등록한다 — 오탐만 사라지고 게이트는 산다.
#   ⇒ python-policy.md §4/§5 의 자체합성 금지 **룰 자체는 텍스트로 존치**하며,
#     이 훅이 그것을 강제하지 않을 뿐이다. 다시 강제하려면 ML 레인 오탐부터 해결할 것.
#   해제 당시 기록 = 02_Infrastructure/hooks/_archive_v8_enforcement/MANIFEST.md:62
#
# 작동:
#   1. file_path가 backtest_registry.csv / methodology_*.md / metrics_official.csv 일 때만 작동
#   2. 동일 strategy의 bt_result.rds에서 audit$integrity_status 확인
#   3. integrity == "FAIL" 이면 deny (L3 block)
#   4. 그 외는 allow
#
# 우회: QVEST_SKIP_BACKTEST_CONTRACT_AUDIT=1 (사용 시 06_Registry/hook_skip_audit.log append 의무 —
#        append 실패 시 skip 미인정, 정상 게이트 로직으로 계속. v8.2.1 감사)
# 로그: /tmp/backtest_contract_audit.log
#==============================================================================

# (v8.2.1 2026-07-03 감사 HOOK-P2-1/MC-07, 도훈 confirm) 게이트급 fail-closed:
#   내부 오류(ERR trap) 시 무조건 '{}' allow 대신, 게이트 보호 대상
#   (backtest_registry.csv / methodology_active|memory.md / metrics_official.csv)
#   경로가 payload에 잡히면 block. 그 외 경로는 fail-open 유지.
#   (2026-08-24: .py 자체합성 스캔 제거로 '코드 파일 일반'이 대상에서 빠졌다 —
#    이제 fail-closed 대상과 TARGET_PATTERN 이 정확히 일치한다.)
_gate_fail_closed() {
  local hay="${FILE_PATH:-}"
  [ -n "$hay" ] || hay="${INPUT:-}"
  if printf '%s' "$hay" | grep -qE 'backtest_registry\.csv|methodology_(active|memory)\.md|metrics_official\.csv'; then
    echo '{"decision": "block", "reason": "backtest_contract_audit: hook 내부 오류 — registry/methodology 등재 검증 불가 (fail-closed). Reference: .claude/rules/backtest-contract.md"}'
  else
    echo '{}'
  fi
  exit 0
}
trap '_gate_fail_closed' ERR
set -u

INPUT=$(cat 2>/dev/null || echo '{}')

# 차단 대상 패턴 — 원장/방법론 정본만. (.py 는 2026-08-24 제거, 위 재등록 이력 참조)
#   (WP4 2026-10-20) 정의를 빠른 길 앞으로 옮겼다 — 빠른 길이 이 정의 하나에서 판정을 파생한다(낱말 목록 이중 관리 없음:
#   대상을 넓히면 빠른 길도 함께 넓어진다. test_backtest_contract_audit_gate.R C-2 가 이 패턴에 .py 를 넣어 그 연동을 잰다).
TARGET_PATTERN='(backtest_registry\.csv$|methodology_(active|memory)\.md$|metrics_official\.csv$)'

# ── 빠른 길 (WP4 2026-10-20 · 훅 지연 — 판정 불변) ─────────────────────────────────
# 증명: 이 훅은 file_path 를 **원문에서** 뽑는다(grep -oE · 해독 없음). 차단·로그는 그 원문 부분 문자열이 위 패턴(끝 고정
#   '$')에 걸린 뒤에만 생긴다. 걸리면 끝 고정을 뗀 같은 정규식이 원문 어딘가에 걸린다(같은 글자 · 같은 자리).
#   fail-closed hay(같은 FILE_PATH, 비면 원문 INPUT)의 패턴도 같은 세 갈래(끝 고정 없음)다. 원문이 끝 고정을 뗀 판에 안
#   걸리면 원래 경로의 출력은 '{}'(로그 없음)다. 대상 낱말은 ASCII 라 해독·인코딩과 무관하다. 우회 표식
#   (QVEST_SKIP_BACKTEST_CONTRACT_AUDIT=1)은 감사 로그를 남기는 부수효과가 있어 빠른 길에서 뺀다 — 원래 경로로 간다.
# 끄기: QVEST_HOOK_FASTPATH=0 (검사 08_Tests/hooks/test_hook_fastpath_equivalence.sh)
_bca_may_target() { [[ $INPUT =~ ${TARGET_PATTERN//\$/} ]]; }
if [ "${QVEST_HOOK_FASTPATH:-1}" != "0" ] && [ "${QVEST_SKIP_BACKTEST_CONTRACT_AUDIT:-0}" != "1" ] && ! _bca_may_target; then
  echo '{}'; exit 0
fi

LOG="/tmp/backtest_contract_audit.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
PROJECT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-/c/Users/99922/OneDrive/Quant_Module_Moltbot}}"
# (2026-11-10 전수점검) 구분자 정규화 — CLAUDE_PROJECT_DIR · QM_ROOT 는 이 기계에서 역슬래시 표기다(C:\Users\…). 그 값이 아래 R 문자열에
#   끼어 들어가면 '\U' 같은 구문 오류로 Rscript 가 죽고, ERR trap 이 그 죽음을 차단으로 바꿨다 — 판정이 아니라 오류 차단이었다.
#   검사: 08_Tests/hooks/test_backtest_contract_audit_gate.R (역슬래시 PROJECT 칸)
PROJECT="${PROJECT//\\//}"

FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

# (v8.2.1 감사) QVEST_SKIP 우회 사용 시 감사 로그 append 의무화 (UTC시각|훅명|SKIP변수|file_path)
if [ "${QVEST_SKIP_BACKTEST_CONTRACT_AUDIT:-0}" = "1" ]; then
  SKIP_LOG="$PROJECT/06_Registry/hook_skip_audit.log"
  if echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ')|backtest_contract_audit.sh|QVEST_SKIP_BACKTEST_CONTRACT_AUDIT|${FILE_PATH:-}" >> "$SKIP_LOG" 2>/dev/null; then
    echo '{}'; exit 0
  fi
  # 감사 로그 기록 실패 → skip 미인정 (감사 불가 우회 금지), 정상 게이트 로직으로 계속
  echo "[$TS] WARN — skip 요청됐으나 hook_skip_audit.log append 실패, skip 미인정" >> "$LOG"
fi

[ -z "$FILE_PATH" ] && { echo '{}'; exit 0; }

# 차단 대상 패턴 = 위(빠른 길 앞) 정의 하나. (WP4 2026-10-20 이동)
if ! echo "$FILE_PATH" | grep -qE "$TARGET_PATTERN"; then
  echo '{}'; exit 0
fi

# 가장 최근 bt_result.rds 검색 — strategy_id 추정 (PROJECT는 상단 정의)
#   (2026-11-10) 전략 폴더(1,300여 개) 전체를 find 로 훑으면 45초를 넘겨 훅이 시간 초과로 빠졌다(= 판정 없이 통과). 결과 파일은
#   전략 폴더 바로 아래 또는 한 단계 아래(output/ 등)에만 있다 → 그 두 깊이의 파일만 골라 나이를 본다(실측 2초).
LATEST_RDS=$(find "$PROJECT"/04_Research/strategies/*/bt_result.rds "$PROJECT"/04_Research/strategies/*/*/bt_result.rds -maxdepth 0 -mmin -60 2>/dev/null | head -1)

if [ -z "$LATEST_RDS" ]; then
  echo "[$TS] no recent bt_result.rds — allow $FILE_PATH" >> "$LOG"
  echo '{}'; exit 0
fi

# Rscript로 audit integrity 추출
# ★2026-08-24 — 여기가 이 훅이 **한 번도 판정한 적 없는** 이유였다.
#   구판은 `Rscript -e "` 뒤에 개행이 들어간 여러 줄 표현식이었는데, 이 환경(Windows
#   + Git Bash)에서는 개행이 포함된 -e 가 **rc=139 로 죽는다**(실측: 한 줄 -e 는 rc=0,
#   같은 코드에 개행만 넣으면 139). 훅은 set -u + `trap _gate_fail_closed ERR` 이라
#   그 크래시가 곧바로 fail-closed 차단으로 나타났다 —
#   즉 integrity 를 읽어 판정하는 코드는 실행된 적이 없고, 산출은 항상
#   "hook 내부 오류" 차단이거나(최근 rds 있음) 무조건 allow(없음) 둘 중 하나였다.
#   ⇒ 한 줄로 고친다. 여러 개의 -e 로 나누는 것도 동작하나(실측), 한 줄이 더 짧다.
#   같은 idiom 이 agent_stop_continuity_check.sh:87(미등록) 과
#   ops/friday_alpha_snapshot.sh:170 에도 있다 — 별건 과제.
#   (2026-11-10) 경로는 R 문자열에 끼우지 않고 환경 변수로 넘긴다 — 경로 표기(역슬래시 · 따옴표)가 R 구문을 깨지 못한다.
INTEGRITY=$(BCA_RDS="$LATEST_RDS" Rscript -e "bt <- tryCatch(readRDS(Sys.getenv('BCA_RDS')), error = function(e) NULL); if (is.null(bt)) cat('UNKNOWN') else cat(as.character(bt\$manifest\$integrity_status[1]))" 2>/dev/null)

INTEGRITY=${INTEGRITY:-UNKNOWN}

if [ "$INTEGRITY" = "FAIL" ]; then
  echo "[$TS] L3 BLOCK — bt_result.rds integrity=FAIL" >> "$LOG"
  echo "[$TS]   target: $FILE_PATH" >> "$LOG"
  echo "[$TS]   source: $LATEST_RDS" >> "$LOG"
  cat <<EOF
{"decision": "block", "reason": "Backtest Result Contract v1.0 §20 — bt_result.rds integrity=FAIL. Audit critical FAIL → official metrics 등재 차단. Lawbook: 00_Lawbook/specs/backtest_result_contract.md"}
EOF
  exit 0
fi

echo "[$TS] allow — integrity=$INTEGRITY ($FILE_PATH)" >> "$LOG"
echo '{}'
exit 0
