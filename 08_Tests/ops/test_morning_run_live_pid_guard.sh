#!/bin/bash
# test_morning_run_live_pid_guard.sh — morning_run 재시도의 "생존 PID" 가드 검사 (2026-08-22 신설)
#
# 왜 있나 (실사고 2026-08-21):
#   구판은 `.done` 마커 부재를 **직전 런의 사망**으로 단정했다. 그런데 morning_run 은
#   [0.5/3] paper_router 에서 최대 50분을 쓴다 — 그 동안 .done 은 원리적으로 없다.
#   07:06:27 런이 살아 있는데 07:10:02 cron 이 재시도로 진입해 라우터를 2개 띄웠고
#   (PID 35460 / 9824), 둘이 같은 route JSON 을 덮어써 07:19 판(22,901B · route_v2 ·
#   autorun 2편 · factor_candidates 4종)이 07:31 판(16,419B)으로 사라졌다. 07:58 에 3번째까지.
#   ★생존 판정에 쓸 PID 는 락 파일 첫 필드에 **이미 적혀 있었다** — 쓰고도 읽지 않았다.
#
# ★양방향: 살아있으면 막고(위반 주입), 죽었으면 막지 않는다(양성 대조 — 과잉 fail-closed 방지).
#
# ⚠공유 경로 주의: morning_run 의 LOCK 은 `/tmp/qm_morning_run_<TODAY>.lock` 로 **고정 공유**다.
#   테스트가 이걸 건드리면 실운영 런과 충돌한다 → 실행 전 생존 런을 확인하고, 기존 락은
#   백업 후 복원한다. (같은 계통: 공유 샌드박스 경로가 검사 flake 를 만든 2026-08-21 사례)
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REAL_ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SCRIPT="$REAL_ROOT/02_Infrastructure/ops/morning_run.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

TODAY=$(date +%Y%m%d)
LOCK="/tmp/qm_morning_run_${TODAY}.lock"
BAK="/tmp/_test_mrlock_backup_$$"

# 생존 런이 있으면 검사하지 않는다 — 실운영 락을 흔들지 않기 위해.
if [ -f "$LOCK" ]; then
  _p=$(awk '{print $1; exit}' "$LOCK" 2>/dev/null)
  if [ -n "${_p:-}" ] && kill -0 "$_p" 2>/dev/null; then
    echo "  SKIP  실운영 morning_run(PID=$_p) 생존 중 — 공유 락을 건드리지 않음"
    echo "== t_summary: PASS=0 FAIL=0 =="; exit 0
  fi
fi
mkdir -p "$BAK"
for f in "$LOCK" "${LOCK}.done" "${LOCK}.retry"; do
  [ -f "$f" ] && cp -p "$f" "$BAK/$(basename "$f")"
done
restore(){
  rm -f "$LOCK" "${LOCK}.done" "${LOCK}.retry"
  for f in "$BAK"/*; do [ -e "$f" ] && cp -p "$f" "/tmp/$(basename "$f")"; done
  rm -rf "$BAK"
}
trap restore EXIT

OUT="/tmp/_test_mr_out_$$.txt"
# ★morning_run 은 본문 전체를 `} >> "$LOG"` 로 리다이렉트한다 — stdout 캡처는 **항상 빈다**.
#   (초판 검사기가 이걸로 2건 거짓 FAIL 했다.) 로그 파일의 **증분**만 읽는다.
MRLOG="$REAL_ROOT/.cache/scheduler_logs/morning_run.log"
[ -f "$MRLOG" ] || MRLOG="/tmp/qm_morning_run.log"
_off=0
snap(){ _off=$(wc -c < "$MRLOG" 2>/dev/null || echo 0); }
grab(){ local now; now=$(wc -c < "$MRLOG" 2>/dev/null || echo 0)
        if [ "$now" -ge "$_off" ]; then tail -c "+$((_off+1))" "$MRLOG" 2>/dev/null > "$OUT"
        else cp "$MRLOG" "$OUT" 2>/dev/null; fi; }

echo "== 위반 주입: 직전 런이 **생존 중**이면 재시도를 막는가 =="
# 이 셸($$)은 확실히 살아 있다 — 구판이라면 '.done 없음'만 보고 재시도 진입한다.
printf '%s @ %s trigger=test\n' "$$" "$(date)" > "$LOCK"
rm -f "${LOCK}.done" "${LOCK}.retry"
snap; timeout 60 bash "$SCRIPT" test >/dev/null 2>&1; grab
if grep -q "생존 중 — 재시도하지 않고 종료" "$OUT" 2>/dev/null \
   && ! grep -q "재시도 진입" "$OUT" 2>/dev/null \
   && ! grep -q "\[0/3\]" "$OUT" 2>/dev/null; then
  ok "생존 PID → 즉시 종료 (체인 미진입)"
else
  ng "생존 PID 차단" "$(grep -m3 -E '재시도|생존|\[0/3\]' "$OUT" 2>/dev/null | tr '\n' ' ')"
fi

echo "== 양성 대조: 직전 런이 **죽었으면** 막지 않는가 (과잉 fail-closed 방지) =="
# 존재하지 않는 PID + 재시도 상한 0 → 가드는 통과하고 상한에서 멈춰야 한다.
printf '%s @ %s trigger=test\n' "999999" "$(date)" > "$LOCK"
rm -f "${LOCK}.done" "${LOCK}.retry"
snap; MORNING_MAX_RETRY=0 timeout 60 bash "$SCRIPT" test >/dev/null 2>&1; grab
if ! grep -q "생존 중 — 재시도하지 않고 종료" "$OUT" 2>/dev/null \
   && grep -q "재시도 상한 도달" "$OUT" 2>/dev/null; then
  ok "죽은 PID → 가드 침묵, 기존 재시도 로직으로 진행"
else
  ng "죽은 PID 통과" "$(grep -m3 -E '재시도|생존' "$OUT" 2>/dev/null | tr '\n' ' ')"
fi

echo "== 양성 대조 2: PID 를 못 읽는 락은 구판 경로로 가는가 (보수적) =="
printf 'garbage-no-pid\n' > "$LOCK"
rm -f "${LOCK}.done" "${LOCK}.retry"
snap; MORNING_MAX_RETRY=0 timeout 60 bash "$SCRIPT" test >/dev/null 2>&1; grab
if ! grep -q "생존 중 — 재시도하지 않고 종료" "$OUT" 2>/dev/null; then
  ok "PID 불명 → 차단하지 않음 (읽기 실패를 '생존'으로 단정하지 않음)"
else
  ng "PID 불명 처리" "읽기 실패를 생존으로 오판 — 하루 전체가 막힐 수 있음"
fi

rm -f "$OUT"
echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ] || exit 1
