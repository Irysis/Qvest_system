#!/bin/bash
# test_failure_classify_window.sh — 실패 사유 분류기의 **구간**과 **사유 커버리지** (2026-08-22 신설)
#
# 왜 있나 (실사고 2026-08-22):
#   두 무인 런이 14:50 에 동시에 죽었고 원문은 "You've hit your session limit · resets 3:30pm"
#   = 시간 경과로 **자동 리셋**되는 사유였다. 그런데 분류기는 `auth_expired` 를 냈다.
#   두 결함이 겹쳐 있었다:
#     ① 구간 리셋 패턴이 `(alpha_queue|router|recheck)` 뿐이라 신설 러너 태그 `[modeq]` 가 빠졌고,
#        그래서 **당일 로그 전체**를 훑어 11:07 의 옛 401(4건)을 현재 원인으로 읽었다.
#        — 이 파일의 헤더가 2026-07-26 에 똑같은 사고로 만들어졌는데, 태그를 안 늘려 재발했다.
#     ② `session limit` 이 아예 없는 사유라 auth_expired 로 떨어졌다.
#        조치가 정반대다: auth_expired="재로그인하세요" vs session_limit="기다리면 풀린다".
#
# ★그래서 이 검사는 두 축이다 — **구간이 이번 런만 보는가** + **사유를 옳게 가르는가**.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
HELPER="$ROOT/02_Infrastructure/ops/_sched_failure_classify.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

if [ ! -f "$HELPER" ]; then echo "  SKIP  분류기 부재"; echo "== t_summary: PASS=0 FAIL=0 =="; printf '{"test":"failure_classify_window","pass":0,"fail":0,"total":0,"skipped":1,"skips":[{"axis":"ALL","reason":"분류기 부재","missing":"%s"}]}\n' "$HELPER"; exit 0; fi
source "$HELPER" 2>/dev/null

T="$(mktemp)"; trap 'rm -f "$T"' EXIT
SESSION_MSG="You've hit your session limit · resets 3:30pm (Asia/Seoul)"

echo "== 사유 커버리지: session limit 을 auth_expired 로 읽지 않는가 =="
printf '%s\n%s\n' "[modeq] start x" "$SESSION_MSG" > "$T"
r=$(sched_classify_failure 1 "$T")
[ "$r" = "session_limit" ] && ok "session limit → $r" || ng "session_limit 판정" "got=$r (auth_expired 면 '재로그인' 오안내)"

echo "== 조치 축: 자동복구 되는 사유로 표기되는가 =="
a=$(sched_failure_autorecovers "$r" 2>/dev/null)
[ "$a" = "yes" ] && ok "자동복구=yes (사람 조치 아님)" || ng "자동복구 축" "got=$a"

echo "== 구간 단절: 러너별 태그가 전부 리셋을 발화시키는가 =="
# 각 태그의 start 줄 앞에 **옛 401** 을 두고, 그 뒤에 이번 런의 세션한도를 둔다.
# 구간이 제대로 잘리면 옛 401 은 안 보여야 한다.
for tag in alpha_queue router recheck modeq; do
  printf '%s\n%s\n%s\n' \
    "API Error: 401 OAuth access token has expired." \
    "[$tag] start this-run" \
    "$SESSION_MSG" > "$T"
  r=$(sched_classify_failure 1 "$T")
  if [ "$r" = "session_limit" ]; then ok "[$tag] 구간 단절 — 옛 401 무시"
  else ng "[$tag] 구간 단절" "got=$r — 이전 런 오류를 현재 원인으로 읽는다"; fi
done

echo "== 양성 대조: 진짜 401 은 여전히 auth_expired 인가 (과잉 수리 방지) =="
printf '%s\n%s\n' "[modeq] start x" "API Error: 401 OAuth access token has expired." > "$T"
r=$(sched_classify_failure 1 "$T")
[ "$r" = "auth_expired" ] && ok "진짜 401 → auth_expired 유지" || ng "401 판정" "got=$r"

echo "== 양성 대조 2: spend limit 이 session limit 에 삼켜지지 않는가 =="
printf '%s\n%s\n' "[modeq] start x" "Your credit balance is too low. spend limit reached." > "$T"
r=$(sched_classify_failure 1 "$T")
[ "$r" = "spend_limit" ] && ok "spend limit → spend_limit 유지" || ng "spend 분리" "got=$r"

echo "== 위반 주입: 성공(rc=0)은 사유를 만들지 않는가 =="
printf '%s\n' "$SESSION_MSG" > "$T"
r=$(sched_classify_failure 0 "$T")
[ "$r" = "ok" ] && ok "rc=0 → ok (실패 아님)" || ng "성공 처리" "got=$r"

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"failure_classify_window","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
