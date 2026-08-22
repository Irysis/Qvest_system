#!/bin/bash
# test_credential_scope_wiring.sh — 무인 러너 자격 토큰 **스코프** 검사 (2026-08-22 신설)
#
# 왜 있나 (실사고 2026-08-22, A/B 로 확정):
#   러너들은 `CRED_ST=$(sched_check_credentials)` 로 사전점검한다. 그 함수는 내부에서
#   `sched_resolve_oauth_token` 을 불러 CLAUDE_CODE_OAUTH_TOKEN 을 **export** 하는데,
#   **명령치환은 서브셸**이라 그 export 가 부모 셸에 도달하지 않는다.
#   결과: 판정은 "ok" 인데 부모 셸 토큰은 unset → 이어지는 claude 가 **만료된 파일 자격**으로
#   떨어져 401. "사전점검은 통과했는데 실제 호출이 401" 의 정체가 이 자리였다.
#   ★Task Scheduler 처럼 프로세스 env 에 User-scope 변수가 실려 오는 컨텍스트에서는 증상이
#     안 나서 오래 잠복했다 — env 가 빈 컨텍스트(Git Bash 등)에서만 터진다.
#
# ★그리고 이 검사의 진짜 값은 **배선 순서 단언**(C절)이다:
#   수리 당일, 개행 혼재 때문에 수리줄이 `source` 보다 **앞**(헤더)에 박혀 `command -v` 가
#   거짓이 되고 `|| true` 가 삼켜 **완전히 무력**했다. 증상은 "수리했는데 여전히 401" 이라
#   진단이 틀린 것처럼 보였다. 순서를 기계로 못박지 않으면 같은 무력화가 조용히 재발한다.
#
# ★토큰 값은 어떤 경우에도 출력하지 않는다 — 길이/유무만 본다.
#   (같은 날 `${V:+SET}${V:-UNSET}` 오용으로 값이 두 번 노출된 사고가 있었다.
#    `${V:-...}` 는 V 가 **비었을 때만** 대체값을 낸다 — 값이 있으면 값을 낸다.)
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
HELPER="$ROOT/02_Infrastructure/ops/_sched_failure_classify.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

# 유무만 반환 — 값 출력 금지
tokstate(){ if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then echo "SET"; else echo "UNSET"; fi; }

RUNNERS="alpha_search_queue_run factor_deep_recheck_run mode_queue_research_run paper_router_run"

echo "== C. 배선 순서 단언: source < 수리줄 < claude 호출 인가 =="
# ★오늘 실제로 깨진 축. 수리줄이 source 앞이면 command -v 가 거짓 → || true 로 무력화된다.
for f in $RUNNERS; do
  p="$ROOT/02_Infrastructure/ops/$f.sh"
  if [ ! -f "$p" ]; then ng "$f 존재" "파일 없음"; continue; fi
  fix=$(grep -n '^command -v sched_resolve_oauth_token' "$p" | head -1 | cut -d: -f1)
  cal=$(grep -n 'timeout 3000 "\$CLAUDE_BIN" -p "\$PROMPT_TEXT"' "$p" | head -1 | cut -d: -f1)
  if [ -z "$fix" ]; then ng "$f 수리줄" "부재 — 서브셸 스코프 결함 미수리"; continue; fi
  if [ -z "$cal" ]; then ng "$f claude 호출" "앵커 없음"; continue; fi
  # 수리줄보다 앞에 있는 source 중 가장 마지막
  src=$(grep -n '_sched_failure_classify.sh' "$p" | cut -d: -f1 | awk -v F="$fix" '$1<F{v=$1} END{print v}')
  if [ -n "$src" ] && [ "$src" -lt "$fix" ] && [ "$fix" -lt "$cal" ]; then
    ok "$f (source $src < fix $fix < claude $cal)"
  else
    ng "$f 순서" "source=${src:-none} fix=$fix claude=$cal — 무력화 배치"
  fi
done

echo "== C1b. 지문 배선: 정의만 해두고 호출 안 하는 상태가 아닌가 =="
# ★이 축이 없어서 오늘 401 이 "만료"인지 "배관 실패"인지 사후 구분이 불가능했다.
#   sched_token_fingerprint 는 정의만 되고 **호출자 0건**이었다 —
#   "만들었다"와 "설치했다"는 다른 사건이다(2026-08-20 계기 카드와 같은 계통).
nofp=""
for f in $RUNNERS; do
  p="$ROOT/02_Infrastructure/ops/$f.sh"
  fp=$(grep -n 'sched_token_fingerprint' "$p" | head -1 | cut -d: -f1)
  cal=$(grep -n 'timeout 3000 "\$CLAUDE_BIN" -p "\$PROMPT_TEXT"' "$p" | head -1 | cut -d: -f1)
  if [ -z "$fp" ] || [ -z "$cal" ] || [ "$fp" -ge "$cal" ]; then nofp="$nofp $f"; fi
done
[ -z "$nofp" ] && ok "4개 러너 모두 claude 호출 **전에** 지문 로깅"   || ng "지문 배선" "해당:$nofp — 다음 401 도 원인 구분 불가"

echo "== C2. 값 노출 금지: 러너가 토큰을 로그로 내지 않는가 =="
leak=""
for f in $RUNNERS; do
  p="$ROOT/02_Infrastructure/ops/$f.sh"
  # 토큰 변수를 echo/log/printf 인자로 직접 흘리는 패턴
  grep -nE '(echo|log|printf|cat)[^#]*\$\{?CLAUDE_CODE_OAUTH_TOKEN' "$p" >/dev/null 2>&1 && leak="$leak $f"
done
[ -z "$leak" ] && ok "토큰을 출력 경로로 흘리는 지점 없음" || ng "토큰 노출" "해당:$leak"

echo "== A. 양성 대조: 수리줄이 부모 셸에 토큰을 도달시키는가 =="
if [ ! -f "$HELPER" ]; then
  echo "  SKIP  헬퍼 부재 — 스코프 검사 불가"
else
  res=$(bash -c '
    unset CLAUDE_CODE_OAUTH_TOKEN
    source "'"$HELPER"'" 2>/dev/null || exit 9
    command -v sched_resolve_oauth_token >/dev/null 2>&1 || exit 8
    sched_resolve_oauth_token >/dev/null 2>&1 || true
    if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then echo SET; else echo UNSET; fi' 2>/dev/null)
  case "$res" in
    SET)   ok "직접 호출 → 부모 셸 토큰 확보" ;;
    UNSET) echo "  SKIP  이 머신에 User-scope 토큰이 없음 — 양성 대조 불가(자격 문제, 코드 문제 아님)" ;;
    *)     ng "resolver 사용 가능" "헬퍼 source 또는 함수 정의 실패(rc=$res)" ;;
  esac

  echo "== B. 위반 주입: 명령치환만 쓰면 부모 셸에 도달하지 **않는가** (구판 재현) =="
  res2=$(bash -c '
    unset CLAUDE_CODE_OAUTH_TOKEN
    source "'"$HELPER"'" 2>/dev/null || exit 9
    CRED_ST=$(sched_check_credentials 2>/dev/null)
    if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then echo SET; else echo "UNSET:$CRED_ST"; fi' 2>/dev/null)
  case "$res2" in
    UNSET*)
      # 판정은 ok 인데 토큰은 미도달 — 이 조합이 정확히 "통과했는데 401" 의 지문이다
      ok "명령치환 경로 → 미도달 (판정='${res2#UNSET:}' 인데 토큰 없음 = 401 지문)" ;;
    SET)
      ng "구판 재현" "명령치환으로도 도달함 — 이 검사가 결함을 못 잡는다(검출력 없음)" ;;
    *)
      ng "구판 재현" "헬퍼 실행 실패(rc=$res2)" ;;
  esac
fi

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ] || exit 1
