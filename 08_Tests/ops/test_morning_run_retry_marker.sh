#!/usr/bin/env bash
# test_morning_run_retry_marker.sh — 아침 체인 재시도 근거 = 체인 자신의 마커만 (v10.4 2026-09-24)
#
# 왜: morning_run.sh 재시도 조건 ②(":오늘 경보 마커 존재")가 오늘자 마커를 **아무거나** 집었다(`ls … | head -1`).
#   task_health 는 그 체인 [0.7/3] 안에서 **다른 예약작업의 rc**(예: Qvest_DailyRefresh exit_1)를 관측해 마커를 남기므로,
#   그 마커 하나로 체인 전체가 다시 돌았다 — 실측 09-05 15:46 · 09-17 18:40 두 번, 각 ~1시간, 고쳐진 것 0.
#   수리 = 선택 규칙을 _sched_failure_classify.sh::sched_retry_alert_marker 로 옮기고 관측자 마커(task_health_* ·
#   unattended_line_*)를 뺀다.
#
# 판정 (운영 마커·로그 무접촉 — 픽스처 디렉터리만):
#   R1 양성 대조: 관측자 마커만 있으면 빈 값      R2 위반 주입: 체인 단계 마커(paper_recharge_stage_exit_124) → 선택
#   R3 어제 마커는 안 집는다                      R4 순서 = 구판 ls|head -1 과 같은 이름순 첫 항목
#   R5 디렉터리 부재 → 빈 값·rc 0                 W1 배선: morning_run.sh 의 첫 `_alert=$(` 가 헬퍼 호출이고 source 가 그 앞
#   M1 돌연변이(관측자 필터 제거) → R1 이 뒤집힘  M2 돌연변이(구판 한 줄 복원) → W1 이 뒤집힘
set -uo pipefail
_SELF="${BASH_SOURCE[0]:-$0}"; _SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
MARKER_REL="02_Infrastructure/hooks/qvest_hook_router.py"
PROJ=""
for c in "$_SELF_DIR/../.." "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$PWD"; do
  [ -n "$c" ] && [ -f "${c//\\//}/$MARKER_REL" ] && { PROJ="$(cd "${c//\\//}" && pwd)"; break; }
done
[ -n "$PROJ" ] || { echo '{"test":"morning_run_retry_marker","pass":0,"fail":1,"total":1,"preflight":"no_root"}'; exit 1; }
CLS="$PROJ/02_Infrastructure/ops/_sched_failure_classify.sh"
MR="$PROJ/02_Infrastructure/ops/morning_run.sh"
[ -f "$CLS" ] && [ -f "$MR" ] || { echo '{"test":"morning_run_retry_marker","pass":0,"fail":1,"total":1,"preflight":"no_src"}'; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
TODAY="$(date +%Y%m%d)"; YDAY="$(date -d yesterday +%Y%m%d 2>/dev/null || echo 19990101)"
# pick <classify-file> <adir> → 선택된 파일 basename (없으면 NONE) — 서브셸에서 source (호출 셸 오염 방지)
pick() { local r; r=$( . "$1" >/dev/null 2>&1; sched_retry_alert_marker "$2" "$TODAY" ); r="${r%$'\r'}"; [ -n "$r" ] && basename "$r" || echo NONE; }
fx() { rm -rf "$TMP/a"; mkdir -p "$TMP/a"; local n; for n in "$@"; do echo "reason=x" > "$TMP/a/$n"; done; }

echo "== 아침 체인 재시도 근거 마커 =="
( . "$CLS" >/dev/null 2>&1; command -v sched_retry_alert_marker >/dev/null ) && chk "H 헬퍼 정의 존재" YES YES || chk "H 헬퍼 정의 존재" YES NO
fx "task_health_scheduled_task_unhealthy_${TODAY}.alert" "unattended_line_daily_digest_${TODAY}_${TODAY}.alert"
chk "R1 관측자 마커만 → 재시도 근거 없음(양성 대조)" NONE "$(pick "$CLS" "$TMP/a")"
fx "task_health_scheduled_task_unhealthy_${TODAY}.alert" "paper_recharge_stage_exit_124_${TODAY}.alert"
chk "R2 체인 단계 마커 주입 → 선택" "paper_recharge_stage_exit_124_${TODAY}.alert" "$(pick "$CLS" "$TMP/a")"
fx "paper_recharge_stage_exit_124_${YDAY}.alert"
chk "R3 어제 마커는 근거 아님" NONE "$(pick "$CLS" "$TMP/a")"
fx "b_comp_x_${TODAY}.alert" "a_comp_y_${TODAY}.alert"
chk "R4 이름순 첫 항목(구판 ls|head -1 동치)" "$(cd "$TMP/a" && ls -1 *_"${TODAY}".alert | head -1)" "$(pick "$CLS" "$TMP/a")"
chk "R5 디렉터리 부재 → 빈 값" NONE "$(pick "$CLS" "$TMP/none")"

# 배선 — 첫 `_alert=$(` 가 헬퍼이고, 그보다 앞에 헬퍼 source 가 있다(파일 좌표가 아니라 순서로 잰다)
wired() {
  local f="$1" la ls
  la=$(tr -d '\r' < "$f" | grep -n '_alert=\$(' | head -1)
  case "$la" in *'_alert=$(sched_retry_alert_marker '*) ;; *) echo NO; return ;; esac
  la="${la%%:*}"
  ls=$(tr -d '\r' < "$f" | grep -n '^[[:space:]]*\. .*_sched_failure_classify\.sh' | head -1); ls="${ls%%:*}"
  [ -n "$ls" ] && [ "$ls" -lt "$la" ] && echo YES || echo NO
}
chk "W1 morning_run.sh 재시도 선택이 헬퍼 경유(source 선행)" YES "$(wired "$MR")"

# 돌연변이
grep -v 'task_health_\*|unattended_line_\*) continue' "$CLS" > "$TMP/cls_mut.sh"
fx "task_health_scheduled_task_unhealthy_${TODAY}.alert" "unattended_line_daily_digest_${TODAY}_${TODAY}.alert"
chk "M1 돌연변이(관측자 필터 제거) → R1 이 관측자 마커를 집음" "task_health_scheduled_task_unhealthy_${TODAY}.alert" "$(pick "$TMP/cls_mut.sh" "$TMP/a")"
"${QVEST_PY_BIN:-${QVEST_PY:-$PROJ/.venv_qvest_ml/Scripts/python.exe}}" - "$MR" "$TMP/mr_mut.sh" <<'PY' 2>/dev/null
import sys
b = open(sys.argv[1], "rb").read()
i = b.find(b"_alert=$(sched_retry_alert_marker ")
j = b.find(b"_alert=$(ls -1 ")
# 헬퍼 호출 줄 앞에 구판 선택 줄을 끼워 넣는다 = 첫 `_alert=$(` 가 구판이 되는 상태(수리 전 형태)
if i > 0 and j > 0:
    ls = b.rfind(b"\n", 0, j) + 1; le = b.find(b"\n", j) + 1
    hs = b.rfind(b"\n", 0, i) + 1
    b = b[:hs] + b[ls:le] + b[hs:]
open(sys.argv[2], "wb").write(b)
PY
chk "M2 돌연변이(구판 선택 줄 선행) → W1 이 뒤집힘" NO "$(wired "$TMP/mr_mut.sh")"

TOTAL=$((PASS+FAIL))
echo "  ── $PASS/$TOTAL pass"
printf '{"test":"morning_run_retry_marker","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$TOTAL"
[ "$FAIL" -eq 0 ]
