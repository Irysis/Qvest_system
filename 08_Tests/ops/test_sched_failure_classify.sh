#!/bin/bash
#==============================================================================
# test_sched_failure_classify.sh — 무인 스케줄러 실패 분류기 행동 검사
#
# 신설 계기 (2026-08-09): `timeout 3000 claude -p` 가 벽시계로 죽인 exit=124 를
#   분류기가 generic `exit_124` 로 떨어뜨려 "원인 미분류 — 로그 확인 필요" 를 안내했다.
#   그런데 그 로그는 **구조적으로 비어 있다** — claude -p 는 최종 메시지를 런 끝에 1회만
#   flush 하므로 kill 당하면 출력이 한 줄도 안 남는다. 즉 안내가 가리키는 증거가 존재할 수
#   없는 상태였고, 07-27~08-09 사이 6회를 그렇게 흘려보냈다.
#
# ★이 파일의 요구: **양방향으로 잰다**(정본 규약 — 오탐 제거와 검사 사망은 겉보기가 같다).
#   ① 양성 대조: 고쳐진 분류기가 옳은 라벨을 내는가
#   ② 위반 주입: rc=124 분기를 제거한 돌연변이에서 검사가 **실제로 실패하는가**
#      (실패하지 않으면 이 검사는 아무것도 재지 않는 것이다)
#   ③ 음성 대조: 124 이외 종료코드·기존 사유 판정을 건드리지 않았는가
#==============================================================================
set -uo pipefail
BASE="${QM_ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
SRC="$BASE/02_Infrastructure/ops/_sched_failure_classify.sh"
[ -f "$SRC" ] || { echo "FAIL: 분류기 없음 $SRC"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
ng(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n     기대=[%s] 실제=[%s]\n' "$1" "$2" "$3"; }
eq(){ [ "$2" = "$3" ] && ok "$1" || ng "$1" "$2" "$3"; }

# shellcheck source=/dev/null
source "$SRC"

echo "── ① 양성 대조: 시간초과 판정 ─────────────────────────────────────────"

# 실사고 재현: 킬 당한 런의 로그 = start 마커까지만 있고 claude 출력 0줄.
EMPTY_LOG="$TMP/alpha_queue_empty.log"
{ echo "2026-08-09T12:09:01+09:00 [alpha_queue] pending testable(큐+route−done): 1"
  echo "2026-08-09T12:09:01+09:00 [alpha_queue] start alpha-search queue (pending=1, MAX_ALPHA=2)"
} > "$EMPTY_LOG"
eq "rc=124 + 빈 로그 → timeout_kill" "timeout_kill" "$(sched_classify_failure 124 "$EMPTY_LOG")"
eq "rc=124 + 로그파일 인자 없음 → timeout_kill" "timeout_kill" "$(sched_classify_failure 124 "")"

eq "autorecovers(timeout_kill) = partial" "partial" "$(sched_failure_autorecovers timeout_kill)"

G="$(sched_failure_guidance timeout_kill)"
case "$G" in
  *"시간초과"*) ok "guidance(timeout_kill) 가 원인을 명시" ;;
  *)            ng "guidance(timeout_kill) 가 원인을 명시" "…시간초과…" "$G" ;;
esac
case "$G" in
  *"원인 미분류"*) ng "guidance(timeout_kill) 가 미분류 문구를 안 쓴다" "미분류 없음" "$G" ;;
  *)               ok "guidance(timeout_kill) 가 미분류 문구를 안 쓴다" ;;
esac

echo "── ② 음성 대조: 다른 사유·다른 코드를 잠식하지 않는가 ─────────────────"

# 한도/인증 문구가 **kill 이전에 이미 로그에 있는** 경우 — 그쪽이 이겨야 한다.
SPEND_LOG="$TMP/spend.log"
{ echo "2026-08-09T00:00:00+09:00 [alpha_queue] start alpha-search queue (pending=1, MAX_ALPHA=2)"
  echo "Claude usage limit reached — spend limit exceeded for this workspace."
} > "$SPEND_LOG"
eq "rc=124 인데 로그에 spend limit → spend_limit 우선" "spend_limit" "$(sched_classify_failure 124 "$SPEND_LOG")"

AUTH_LOG="$TMP/auth.log"
{ echo "2026-08-09T00:00:00+09:00 [alpha_queue] start alpha-search queue (pending=1, MAX_ALPHA=2)"
  echo "API Error: 401 OAuth access token has expired"
} > "$AUTH_LOG"
eq "rc=124 인데 로그에 401 → auth_expired 우선" "auth_expired" "$(sched_classify_failure 124 "$AUTH_LOG")"

eq "rc=0 → ok"        "ok"       "$(sched_classify_failure 0   "$EMPTY_LOG")"
eq "rc=1 → exit_1"    "exit_1"   "$(sched_classify_failure 1   "$EMPTY_LOG")"
eq "rc=137 → exit_137" "exit_137" "$(sched_classify_failure 137 "$EMPTY_LOG")"
eq "autorecovers(exit_1) 불변 = unknown" "unknown" "$(sched_failure_autorecovers exit_1)"
eq "autorecovers(spend_limit) 불변 = yes" "yes"    "$(sched_failure_autorecovers spend_limit)"

echo "── ③ 간헐 재발 카운터 (연속 streak 이 못 보는 축) ─────────────────────"

ADIR="$TMP/alerts"; mkdir -p "$ADIR/_resolved"
D0=$(date +%Y%m%d); D2=$(date -d "-2 day" +%Y%m%d); D3=$(date -d "-3 day" +%Y%m%d)
: > "$ADIR/alpha_queue_timeout_kill_${D0}.alert"          # 신 이름
: > "$ADIR/_resolved/alpha_queue_exit_124_${D2}.alert"    # 구 이름 + 아카이브
: > "$ADIR/alpha_queue_exit_124_${D3}.alert"              # 구 이름
eq "recent_count 가 아카이브·구이름을 함께 센다" "3" \
   "$(sched_failure_recent_count alpha_queue timeout_kill "$ADIR")"
# streak 은 연속만 세므로 여기서는 1 이어야 한다 — 두 축이 실제로 다른 것을 재는지 확인.
eq "streak 은 같은 상황에서 1 (두 축이 서로 다른 것을 잰다)" "1" \
   "$(sched_failure_streak alpha_queue timeout_kill "$ADIR")"
eq "다른 컴포넌트는 0 (교차 오계수 없음)" "0" \
   "$(sched_failure_recent_count paper_router timeout_kill "$ADIR")"

ANN="$(sched_failure_annotate alpha_queue timeout_kill "$ADIR")"
case "$ANN" in
  *"최근 14일 3회"*) ok "annotate 가 빈도(3회)를 격상 문구에 실측으로 노출" ;;
  *)                 ng "annotate 가 빈도를 격상 문구에 노출" "…최근 14일 3회…" "$ANN" ;;
esac
# ★문구가 streak 값과 어긋나면 안 된다 — 별칭 수리로 streak 이 0→2 가 되자
#   구 문구 "연속이 아니어서" 가 실제(연속 2일)와 모순됐다. 단정 대신 두 수를 다 말한다.
case "$ANN" in
  *"연속이 아니어서"*) ng "격상 문구가 streak 을 단정하지 않는다" "단정 없음" "$ANN" ;;
  *)                   ok "격상 문구가 streak 을 단정하지 않는다" ;;
esac
case "$ANN" in
  *"연속은 1일"*) ok "격상 문구가 실제 streak(1) 을 그대로 말한다" ;;
  *)              ng "격상 문구가 실제 streak 을 그대로 말한다" "…연속은 1일…" "$ANN" ;;
esac
case "$ANN" in
  *"자동복구=partial"*) ok "annotate 가 partial 을 그대로 전달" ;;
  *)                    ng "annotate 가 partial 을 그대로 전달" "자동복구=partial" "$ANN" ;;
esac

echo "── ③b 사유 개명 전환기: streak 이 별칭을 못 보면 계측이 끊긴다 ────────"
#   실사고(2026-08-09): recent_count 에만 별칭을 넣었더니 같은 경보가
#   "연속=0 | 최근14일=6회" 로 서로 다른 것을 말했다. 개명일 전후 카운터 0 은
#   결함 소멸이 아니라 **계측 단절**이다.
eq "aliases(timeout_kill) 가 구 이름을 포함" "timeout_kill exit_124" \
   "$(sched_reason_aliases timeout_kill)"
eq "aliases(미지 사유) 는 원형 보존" "spend_limit" "$(sched_reason_aliases spend_limit)"

ADIR2="$TMP/alerts2"; mkdir -p "$ADIR2/_resolved"
D1=$(date -d "-1 day" +%Y%m%d)
: > "$ADIR2/alpha_queue_exit_124_${D0}.alert"   # 개명 전 이름으로만 쌓인 이틀
: > "$ADIR2/alpha_queue_exit_124_${D1}.alert"
eq "구 이름 마커 2일 → streak(신 이름)=2 (별칭 인지)" "2" \
   "$(sched_failure_streak alpha_queue timeout_kill "$ADIR2")"

# ★두 축은 여전히 달라야 한다 — streak 은 _resolved/ 를 보지 않는다(해소 의미 보존).
: > "$ADIR2/_resolved/alpha_queue_exit_124_$(date -d '-5 day' +%Y%m%d).alert"
eq "streak 은 _resolved/ 를 세지 않는다" "2" \
   "$(sched_failure_streak alpha_queue timeout_kill "$ADIR2")"
eq "recent_count 는 _resolved/ 를 센다 (축 분리 확인)" "3" \
   "$(sched_failure_recent_count alpha_queue timeout_kill "$ADIR2")"

echo "── ④ 위반 주입: rc=124 분기를 죽이면 검사가 실제로 실패하는가 ─────────"
#   ★이 절이 없으면 위 PASS 들은 "검사가 살아 있다"를 증명하지 못한다.
MUT="$TMP/mutant.sh"
"${QVEST_PY:-python}" - "$SRC" "$MUT" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, 'rb').read().decode('utf-8')
old = '  if [ "${rc:-0}" -eq 124 ]; then\r\n    echo "timeout_kill"; return 0\r\n  fi\r\n'
if old not in t:
    old = old.replace('\r\n', '\n')
assert old in t, "돌연변이 앵커 없음 — 검사기가 낡았다"
open(dst, 'wb').write(t.replace(old, '', 1).encode('utf-8'))
PYEOF
if [ ! -s "$MUT" ]; then
  ng "돌연변이 생성" "파일 생성" "빈 파일/실패"
else
  MUT_OUT=$(bash -c 'source "$1"; sched_classify_failure 124 "$2"' _ "$MUT" "$EMPTY_LOG")
  if [ "$MUT_OUT" = "timeout_kill" ]; then
    ng "돌연변이에서 검사가 실패해야 함(검출력)" "timeout_kill 아님" "$MUT_OUT"
  else
    ok "돌연변이(rc=124 분기 제거) → '$MUT_OUT' 로 회귀, 검사가 잡는다"
  fi
fi

echo "── ④b 위반 주입: 별칭표를 비우면 streak 이 끊기는가 ────────────────────"
MUT2="$TMP/mutant2.sh"
"${QVEST_PY:-python}" - "$SRC" "$MUT2" <<'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, 'rb').read().decode('utf-8')
old = '    timeout_kill) echo "timeout_kill exit_124" ;;   # 2026-08-09 개명\r\n'
if old not in t:
    old = old.replace('\r\n', '\n')
assert old in t, "별칭 돌연변이 앵커 없음 — 검사기가 낡았다"
open(dst, 'wb').write(t.replace(old, '', 1).encode('utf-8'))
PYEOF
if [ ! -s "$MUT2" ]; then
  ng "별칭 돌연변이 생성" "파일 생성" "빈 파일/실패"
else
  M2=$(bash -c 'source "$1"; sched_failure_streak alpha_queue timeout_kill "$2"' _ "$MUT2" "$ADIR2")
  if [ "$M2" = "2" ]; then
    ng "별칭 제거 돌연변이를 검사가 잡아야 함(검출력)" "2 아님" "$M2"
  else
    ok "돌연변이(별칭표 제거) → streak='$M2' 로 계측 단절, 검사가 잡는다"
  fi
fi

echo
echo "════ test_sched_failure_classify: PASS=$PASS FAIL=$FAIL ════"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
