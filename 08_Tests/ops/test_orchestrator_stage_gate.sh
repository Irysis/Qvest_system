#!/bin/bash
# test_orchestrator_stage_gate.sh — 오케스트레이터가 스테이지 실패를 **기록**하는가 (2026-08-22)
#
# 왜 있나 (감사 지적 — 7링크가 전부 놓친 층):
#   7링크 감사는 전부 **러너 단위**였고, 그 7개를 실제로 부르는 유일한 지점
#   (morning_run.sh)을 아무도 읽지 않았다. 거기서 `stage_result()` 는 그 컴포넌트가
#   오늘 마커를 남겼는지 **보고만** 했고 만들지는 않았다.
#   실측 귀결: `paper_recharge exit=1` **7회 / ★경보발행 0회**
#   (그 러너의 경보 커버리지가 1/5 — lock_owner_unknown 만 낸다).
#
# ★기전: 오케스트레이터는 exit 코드를 **알고 있다**. 스테이지가 자기 실패를 기억해
#   보고하는지에 의존할 이유가 없다. 링크별 경보만 있으면 이 층은 원리적으로 안 보인다.
#
# ★양방향: 실패를 기록하되(검출력) 성공을 경보하지 않고(오경보 방지),
#   스테이지 자신의 더 구체적인 진단을 덮지 않는다(정보 보존).
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
MR="$ROOT/02_Infrastructure/ops/morning_run.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

if [ ! -f "$MR" ]; then echo "  SKIP  morning_run 부재"; echo "== t_summary: PASS=0 FAIL=0 =="; printf '{"test":"orchestrator_stage_gate","pass":0,"fail":0,"total":0,"skipped":1,"skips":[{"axis":"ALL","reason":"morning_run 부재","missing":"%s"}]}\n' "$MR"; exit 0; fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ADIR="$T/.cache/scheduler_alerts"; mkdir -p "$ADIR"
H="$T/h.sh"
{ echo 'set -uo pipefail'; echo "BASE='$T'"; echo 'LOG=/dev/null'
  awk '/^stage_result\(\) \{/,/^\}/' "$MR"; } > "$H"

if ! grep -q 'stage_result()' "$H"; then
  ng "함수 추출" "stage_result() 를 떼어내지 못함 — 정의 형태가 바뀌었다"
  echo "== t_summary: PASS=$PASS FAIL=$FAIL =="; exit 1
  printf '{"test":"orchestrator_stage_gate","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
fi
ok "stage_result() 추출 성공"

nmark(){ ls -1 "$ADIR" 2>/dev/null | wc -l | tr -d ' '; }

echo "== 오경보 방지: rc=0 은 마커를 만들지 않는가 =="
rm -f "$ADIR"/*; OUT=$(bash -c "source '$H'; stage_result paper_recharge 0 paper_recharge" 2>&1)
[ "$(nmark)" = "0" ] && ok "rc=0 → 마커 0건" || ng "성공 경보" "성공에 마커를 만든다 — 학습된 무시를 만든다"
echo "$OUT" | grep -q "★경보발행" && ng "rc=0 표기" "성공인데 경보발행이라 찍는다" || ok "rc=0 → 경보 문구 없음"

echo "== 검출력: rc≠0 인데 스테이지가 자기 마커를 안 남기면 오케스트레이터가 만드는가 =="
rm -f "$ADIR"/*; OUT=$(bash -c "source '$H'; stage_result paper_recharge 1 paper_recharge" 2>&1)
[ "$(nmark)" = "1" ] && ok "rc=1 → 마커 자가 발행" \
  || ng "무마커 통과" "실측 7회 발생한 'exit=1 인데 마커 0건' 이 그대로 재현된다"
ls -1 "$ADIR" 2>/dev/null | grep -q "stage_exit_1" && ok "사유가 stage_exit_1 로 식별된다" \
  || ng "사유 라벨" "발행처를 구분할 수 없다: $(ls -1 "$ADIR" 2>/dev/null)"
echo "$OUT" | grep -q "★경보발행" && ok "로그에 ★경보발행 병기" || ng "로그 표기" "got=$OUT"

echo "== 정보 보존: 스테이지 자신의 진단을 덮지 않는가 =="
rm -f "$ADIR"/*
printf 'reason=sources_csv_missing\n' > "$ADIR/paper_recharge_x_$(date +%Y%m%d).alert"
OUT=$(bash -c "source '$H'; stage_result paper_recharge 1 paper_recharge" 2>&1)
[ "$(nmark)" = "1" ] && ok "기존 마커 있으면 추가 발행 안 함" \
  || ng "중복 발행" "구체적 진단 위에 일반 마커를 얹는다 (마커 $(nmark)건)"
echo "$OUT" | grep -q "sources_csv_missing" && ok "스테이지 진단이 그대로 보고된다" \
  || ng "진단 소실" "더 구체적인 사유가 stage_exit 로 덮였다: $OUT"

echo "== 멱등: 같은 실패를 두 번 봐도 마커가 늘지 않는가 =="
rm -f "$ADIR"/*
bash -c "source '$H'; stage_result paper_recharge 1 paper_recharge" >/dev/null 2>&1
bash -c "source '$H'; stage_result paper_recharge 1 paper_recharge" >/dev/null 2>&1
[ "$(nmark)" = "1" ] && ok "재호출해도 1건 (스로틀)" || ng "스로틀" "마커가 $(nmark)건으로 증식 — 부팅 표면이 익사한다"

echo "== 컴포넌트 미지정 시 조용한가 (경계) =="
rm -f "$ADIR"/*; bash -c "source '$H'; stage_result something 1 ''" >/dev/null 2>&1
[ "$(nmark)" = "0" ] && ok "comp 없으면 마커 안 만듦" || ng "comp 없음" "귀속 불가 마커를 만든다"

echo "== 계약: 실 호출부가 comp 인자를 실제로 넘기는가 =="
# comp 를 안 넘기면 위 게이트가 통째로 무력하다 — '만들고 안 부르는' 의 변형.
n_call=$(grep -cE 'stage_result +[A-Za-z_]+ +"?\$' "$MR")
n_comp=$(grep -E 'stage_result ' "$MR" | grep -cE 'stage_result +\S+ +\S+ +\S+')
if [ "$n_comp" -gt 0 ]; then ok "호출부 ${n_comp}건이 comp 인자 전달"
else ng "comp 미전달" "게이트가 배선돼도 호출부가 comp 를 안 주면 발화하지 않는다"; fi

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"orchestrator_stage_gate","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
