#!/bin/bash
# test_scheduler_alert_surface.sh — 무인 경보 마커 표면화 검사 (2026-08-22 신설)
#
# 왜 있나: 마커는 써지는데 **읽는 소비자가 없어서** 무인 레인 전체를 세운 auth_expired 가
#   아무 화면에도 안 떴다(2026-08-22 실측, 미해소 16건 누적·최고령 25d).
#   이 검사는 그 소비면이 ①실제로 세는지 ②사람 조치가 필요한 건을 **구분해서** 올리는지를 잰다.
#
# ★양방향: 있으면 올리고(양성 대조), 없으면 조용하고(과잉 경보 방지),
#   해소된 것(_resolved/)은 세지 않는다(위반 주입).
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REAL_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SCRIPT="$REAL_ROOT/02_Infrastructure/ops/scheduler_alert_status.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/02_Infrastructure/hooks" "$FIX/02_Infrastructure/ops" "$FIX/.cache/scheduler_alerts/_resolved"
: > "$FIX/02_Infrastructure/hooks/qvest_hook_router.py"
cp "$REAL_ROOT/02_Infrastructure/ops/resolve_project.sh" "$FIX/02_Infrastructure/ops/" 2>/dev/null
cp "$REAL_ROOT/02_Infrastructure/ops/_sched_failure_classify.sh" "$FIX/02_Infrastructure/ops/" 2>/dev/null
cp "$SCRIPT" "$FIX/02_Infrastructure/ops/"
RUN="$FIX/02_Infrastructure/ops/scheduler_alert_status.sh"
AD="$FIX/.cache/scheduler_alerts"

mk(){ printf 'ts=%s\ncomponent=%s\nreason=%s\ndetail=test\n' "$(date -Iseconds)" "$1" "$2" > "$AD/$1_$2_$3.alert"; }
line(){ ( cd "$FIX" && QM_ROOT="$FIX" bash "$RUN" --status-line 2>/dev/null ); }

echo "== 양성 대조 1: 마커가 없으면 조용한가 (과잉 경보 방지) =="
got=$(line)
[[ "$got" == *"미해소 0건"* ]] && ok "0건 → '미해소 0건'" || ng "0건 처리" "$got"

echo "== 양성 대조 2: 마커 수를 실제로 세는가 =="
mk paper_router timeout_kill 20260821
mk alpha_queue rate_limit 20260821
got=$(line)
[[ "$got" == *"2건"* ]] && ok "2건 계수" || ng "계수" "$got"

echo "== 양성 대조 3: 사람 조치 필요 건을 **구분해서** 올리는가 =="
# ★이 축이 없으면 전부 같은 무게로 보여 '학습된 무시'가 된다 — 그래서 auth_expired 가 묻혔다.
mk paper_router auth_expired 20260822
got=$(line)
# ★2026-08-22: 상태라인이 4분류(사람조치/판정불가/부분복구/자동복구)로 바뀌었다.
#   구판은 "사람 조치 필요" 한 형태만 기대했다.
if [[ "$got" == *"사람 조치"* && "$got" == *"auth_expired"* ]]; then
  ok "auth_expired → '사람 조치 필요' 로 분리 표기"
else ng "사람 조치 구분" "$got"; fi

echo "== 위반 주입 1: 해소된 마커(_resolved/)를 세지 않는가 =="
mv "$AD/paper_router_auth_expired_20260822.alert" "$AD/_resolved/" 2>/dev/null
got=$(line)
if [[ "$got" != *"사람 조치 필요"* ]] && [[ "$got" == *"2건"* ]]; then
  ok "_resolved/ 이관분 제외 (해소가 반영됨)"
else ng "_resolved 제외" "$got — 해소한 것이 계속 뜨면 신뢰를 잃는다"; fi

echo "== 위반 주입 2: 자동복구 대상만 남으면 ★를 붙이지 않는가 =="
got=$(line)
# ★이 축의 의도는 유효하다 — **순수 자동복구뿐이면** ★ 를 붙이면 안 된다.
#   단 신판은 partial(부분복구)이 섞이면 ★ 를 붙인다(옳다: partial ≠ 완전 자동복구).
#   ⇒ 픽스처에서 timeout_kill(partial) 을 빼고 순수 yes 만 남겨 의도를 보존한다.
rm -f "$AD"/*timeout_kill*.alert 2>/dev/null
got=$(line)
[[ "$got" != *"★"* ]] && ok "순수 자동복구만 → ★ 없음 (경보 인플레 방지)" || ng "★ 남용" "$got"

echo "== 위반 주입 3: 마커 디렉터리 부재를 '정상 0건'으로 위장하지 않는가 =="
rm -rf "$AD"
got=$(line)
if [[ "$got" == *"디렉터리 없음"* ]]; then ok "부재를 별도 표기 (0건과 구분)"
else ng "부재/0건 구분" "$got — '없음'과 '0건'이 같은 문자열이면 계측 사망을 정상으로 읽는다"; fi

echo "== 배선 단언: bootstrap 이 이 상태라인을 실제로 부르는가 =="
if grep -q "scheduler_alert_status.sh" "$REAL_ROOT/02_Infrastructure/ops/bootstrap.sh" 2>/dev/null \
   && grep -q 'SCHED_ALERT_STATUS' "$REAL_ROOT/02_Infrastructure/ops/bootstrap.sh" 2>/dev/null; then
  ok "bootstrap 배선 존재 (소비자 0 재발 방지)"
else ng "bootstrap 배선" "만들어만 두고 부르지 않으면 이 결함이 그대로 재발한다"; fi

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ] || exit 1
