#!/bin/bash
# test_stall_lock_alert.sh — 매달린 런이 **무경보로 무기한 점유**하지 않는가 (2026-08-22 신설)
#
# 왜 있나 (내가 만든 회귀):
#   도훈 지시로 `timeout 3000` 을 4러너에서 제거했다. 지시는 옳았다 — 상한이 자른 것은
#   폭주가 아니라 끝난 일의 뒷정리였다(18:10 alpha_package 완성 → 18:13 킬).
#   그러나 감사가 짚었듯 구 timeout 은 **4일간 5회 실제 발화한 활성 안전망**이기도 했다
#   (라우터 exit=124 ×4 + alpha ×2). 제거로 '행(hang) 1건 = 무기한' 이 열렸고,
#   락은 `kill -0` 만 보므로 **살아서 매달린** 홀더를 영원히 존중하며 조용히 skip 한다.
#
# ★수리 원칙 = **죽이지 않고 보이게 한다.**
#   '일하는 중' 과 '매달림' 은 벽시계가 아니라 **진척**으로 갈린다(로그가 자라는가).
#   그래서 이 검사의 축은 "상한이 있는가" 가 아니라
#   ① 진척 중인 홀더를 경보하지 않는가(오경보 방지 — 18:10 사례가 다시 잘리면 안 된다)
#   ② 정체된 홀더를 경보하는가(검출력)
#   ③ 홀더를 **죽이지는 않는가**(동시 실행 방지가 락의 존재 이유)
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
OPS="$ROOT/02_Infrastructure/ops"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

RUNNERS="paper_router_run.sh mode_queue_research_run.sh"

echo "== 배선 축: 락 경합 분기에 정체 검사가 있는가 =="
for f in $RUNNERS; do
  p="$OPS/$f"
  [ -f "$p" ] || { ng "$f" "파일 부재"; continue; }
  if grep -q "stalled_lock" "$p"; then ok "$f — 정체 경보 배선"
  else ng "$f 정체 경보" "홀더가 매달리면 무경보로 무기한 점유한다"; fi
done

echo "== 순서 축: 정체 검사가 skip(exit 0) **앞**에 있는가 =="
# 뒤에 있으면 원리적으로 도달 불가 — 오늘 FORCE 가 게이트 뒤에 갇힌 것과 같은 계통.
for f in $RUNNERS; do
  p="$OPS/$f"
  st=$(grep -n 'stalled_lock' "$p" | head -1 | cut -d: -f1)
  sk=$(grep -n '다른 인스턴스' "$p" | head -1 | cut -d: -f1)
  if [ -n "$st" ] && [ -n "$sk" ] && [ "$st" -lt "$sk" ]; then ok "$f — 검사가 skip 앞"
  else ng "$f 순서" "정체 검사가 skip 뒤라 도달 불가 (st=$st sk=$sk)"; fi
done

echo "== 의존 축: LOG 이 검사 시점에 정의돼 있는가 =="
for f in $RUNNERS; do
  p="$OPS/$f"
  lg=$(grep -n '^LOG=' "$p" | head -1 | cut -d: -f1)
  st=$(grep -n 'stalled_lock' "$p" | head -1 | cut -d: -f1)
  if [ -n "$lg" ] && [ -n "$st" ] && [ "$lg" -lt "$st" ]; then ok "$f — LOG 선정의"
  else ng "$f LOG 의존" "미정의 변수 참조 (lg=$lg st=$st)"; fi
done

echo "== 안전 축: 홀더를 죽이지 않는가 (동시 실행 방지 보존) =="
for f in $RUNNERS; do
  p="$OPS/$f"
  # 정체 블록 안에서 kill/rm -rf 로 락을 뺏는 코드가 없어야 한다
  seg=$(awk '/stalled_lock/{f=1} f{print} /^  fi$/{if(f)exit}' "$p" | head -20)
  if echo "$seg" | grep -qE '\bkill +-(9|TERM|KILL)\b|rm +-rf +"\$(R|M)LOCK"'; then
    ng "$f 안전" "정체 판정으로 남의 프로세스를 죽이거나 락을 뺏는다 — 비가역"
  else ok "$f — 경보만, 킬·회수 없음"; fi
done

echo "== 문턱 축: env 로 조정 가능한가 =="
for f in $RUNNERS; do
  grep -q "QVEST_STALL_ALERT_MIN" "$OPS/$f" && ok "$f — 문턱 외부화" \
    || ng "$f 문턱" "하드코딩 — 레인별 실소요가 다른데 하나로 못 맞춘다"
done

echo "== 행동 축: 정체/진척을 실제로 가르는가 (위반 주입) =="
# 정체 블록만 떼어내 두 상태로 돌린다.
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkharness(){ # $1=로그 mtime 나이(분)
  cat > "$T/h.sh" <<'HEOF'
set -uo pipefail
scheduler_alert(){ echo "ALERT:$1:$2"; }
log(){ echo "LOG:$*"; }
_rp=99999
HEOF
  awk '/★정체 감지/{f=1} f{print} /^    fi$/{if(f)exit}' "$OPS/paper_router_run.sh" >> "$T/h.sh"
  : > "$T/run.log"
  # mtime 을 과거로 민다
  touch -d "$(date -d "-$1 minutes" '+%Y-%m-%d %H:%M:%S')" "$T/run.log"
}
mkharness 5
OUT=$(LOG="$T/run.log" QVEST_STALL_ALERT_MIN=45 bash "$T/h.sh" 2>&1)
echo "$OUT" | grep -q "ALERT:" \
  && ng "진척 중 오경보" "5분 전 갱신인데 매달림으로 판정 — 18:10 사례가 다시 잘린다" \
  || ok "진척 중(5분) → 경보 없음 (오경보 방지)"

mkharness 90
OUT=$(LOG="$T/run.log" QVEST_STALL_ALERT_MIN=45 bash "$T/h.sh" 2>&1)
echo "$OUT" | grep -q "ALERT:paper_router:stalled_lock" \
  && ok "정체(90분) → stalled_lock 경보 (검출력)" \
  || ng "정체 미검출" "매달려도 조용하다: $OUT"

mkharness 90
OUT=$(LOG="$T/run.log" QVEST_STALL_ALERT_MIN=120 bash "$T/h.sh" 2>&1)
echo "$OUT" | grep -q "ALERT:" \
  && ng "문턱 무시" "QVEST_STALL_ALERT_MIN=120 인데 90분에 발화" \
  || ok "문턱 상향 시 90분은 미발화 (문턱이 실효)"

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"stall_lock_alert","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
